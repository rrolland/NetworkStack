//
//  NetworkStack.swift
//
//  Copyright © 2017 Niji. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
import RxSwift
import Alamofire

public final class NetworkStack {
  
  // MARK: - Constants
  
  static let authorizationHeaderKey = "Authorization"
  
  // MARK: - Type aliases
  
  public typealias RenewTokenHandler = (() -> Observable<Void>)
  
  // MARK: - Properties
  
  fileprivate let disposeBag = DisposeBag()
  fileprivate let keychainService: KeychainService
  public let baseURL: String
  
  fileprivate var requestManager: Alamofire.Session
  
  /// Auth - Tokens part
  fileprivate var tokenManager: TokenManager?
  public var askCredential: AskCredential?
  public var renewTokenHandler: RenewTokenHandler? {
    didSet {
      if let tokenFetcher = renewTokenHandler {
        let tokenFetchAndGiveValue: Observable<String> = tokenFetcher().map { _ in
          if let token = self.currentAccessToken() {
            return token
          } else {
            throw NetworkStackError.tokenUnavaible
          }
        }
        
        self.tokenManager = TokenManager(tokenFetcher: tokenFetchAndGiveValue)
      }
    }
  }
  
  public weak var delegate: NetworkStackDelegate?
  
  // MARK: - Setup
  
  public init(baseURL: String,
              keychainService: KeychainService,
              requestManager: Alamofire.Session = Alamofire.Session(),
              askCredential: AskCredential? = nil) {
    
    self.baseURL = baseURL
    self.keychainService = keychainService
    self.requestManager = requestManager
    
    self.askCredential = askCredential
  }
}

// MARK: - Cancellation
extension NetworkStack {
  
  public func disconnect() -> Observable<Void> {
    return self.cancelAllRequest()
      .map({ [unowned self] () -> Void in
        return self.clearToken()
      })
  }
  
  fileprivate func cancelAllRequest() -> Observable<Void> {
    return Observable.just(Void())
      .map { () -> Void in
        self.resetRequestManager()
      }
  }
  
  fileprivate func resetRequestManager() {
    self.requestManager = self.recreateManager(manager: self.requestManager)
  }
  
  fileprivate func recreateManager(manager: Session) -> Session {
    let configuration = manager.session.configuration
    manager.session.invalidateAndCancel()
    return Session(configuration: configuration)
  }
}

// MARK: - Request building
extension NetworkStack {
  
  public func request(method: Alamofire.HTTPMethod,
                      route: Routable,
                      needsAuthorization: Bool = false,
                      parameters: Alamofire.Parameters? = nil,
                      headers: Alamofire.HTTPHeaders? = nil,
                      encoding: Alamofire.ParameterEncoding = JSONEncoding.default) -> DataRequest? {
    return request(method: method, route: route, needsAuthorization: needsAuthorization, parameters: parameters, headers: headers, encoding: encoding, httpBody: nil)
  }
  
  public func request(method: Alamofire.HTTPMethod,
                      route: Routable,
                      needsAuthorization: Bool = false,
                      headers: Alamofire.HTTPHeaders? = nil,
                      encoding: Alamofire.ParameterEncoding = JSONEncoding.default,
                      httpBody: Data? = nil) -> DataRequest? {
    let result: DataRequest? = request(method: method, route: route, needsAuthorization: needsAuthorization, parameters: nil, headers: headers, encoding: encoding, httpBody: httpBody)
    
    return result
  }
  
  private func request(method: Alamofire.HTTPMethod,
                       route: Routable,
                       needsAuthorization: Bool = false,
                       parameters: Alamofire.Parameters? = nil,
                       headers: Alamofire.HTTPHeaders? = nil,
                       encoding: Alamofire.ParameterEncoding = JSONEncoding.default,
                       httpBody: Data? = nil) -> DataRequest? {
    guard let requestUrl = self.requestURL(route) else {
      return nil
    }
    
    let requestHeaders = self.requestHeaders(needsAuthorization: needsAuthorization, headers: headers)
    
    return self.request(requestUrl,
                        method: method,
                        parameters: parameters,
                        encoding: encoding,
                        headers: requestHeaders,
                        httpBody: httpBody)
  }
  
  private func request(
    _ url: URLConvertible,
    method: HTTPMethod = .get,
    parameters: Parameters? = nil,
    encoding: ParameterEncoding = URLEncoding.default,
    headers: HTTPHeaders? = nil,
    httpBody: Data? = nil)
    -> DataRequest?
  {
    var originalRequest: URLRequest?
    
    do {
      originalRequest = try URLRequest(url: url, method: method, headers: headers)
      originalRequest?.httpBody = httpBody
      let encodedURLRequest = try encoding.encode(originalRequest!, with: parameters)
      return self.requestManager.request(encodedURLRequest)
    } catch {
      return nil
    }
  }
  
  fileprivate func buildRequest(requestParameters: RequestParameters) -> DataRequest? {
    return self.request(method: requestParameters.method,
                        route: requestParameters.route,
                        needsAuthorization: requestParameters.needsAuthorization,
                        parameters: requestParameters.parameters,
                        headers: requestParameters.headers,
                        encoding: requestParameters.parametersEncoding)
  }
  
  fileprivate func requestURL(_ route: Routable) -> URL? {
    guard let requestUrl = URL(string: self.baseURL + route.path) else {
      return nil
    }
    return requestUrl
  }
  
  fileprivate func requestHeaders(needsAuthorization: Bool = false, headers: Alamofire.HTTPHeaders?) -> Alamofire.HTTPHeaders {
    var requestHeaders: Alamofire.HTTPHeaders
    if let headers = headers {
      requestHeaders = headers
    } else {
      requestHeaders = [:]
    }
    
    if needsAuthorization {
      let tokenValue = self.auhtorizationHeaderValue()
      if let tokenAutValue = tokenValue {
        requestHeaders[NetworkStack.authorizationHeaderKey] = tokenAutValue
      }
    }
    if let headers = headers {
        headers.forEach { header in
            requestHeaders[header.name] = header.value
        }
    }
    return requestHeaders
  }
  
  public func updateRequestAuthorizationHeader(dataRequest: Alamofire.DataRequest) -> Alamofire.DataRequest {
    guard let tokenValue = self.auhtorizationHeaderValue(), var newURLRequest = dataRequest.request else {
      return dataRequest
    }
    
    newURLRequest.setValue(tokenValue, forHTTPHeaderField: NetworkStack.authorizationHeaderKey)
    return self.requestManager.request(newURLRequest)
  }
}

// MARK: - Request validation
extension NetworkStack {
  fileprivate func validateRequest(request: Alamofire.DataRequest) -> Alamofire.DataRequest {
    return request.validate(statusCode: 200 ..< 300)
  }
}

// MARK: - Retry management

extension NetworkStack {
  fileprivate func askCredentialsIfNeeded(forError error: Error) -> Observable<Void> {
    if self.shouldAskCredentials(forError: error) == true {
      return self.askCredentials()
    } else {
      return Observable.just(Void())
    }
  }
  
  fileprivate func askCredentials() -> Observable<Void> {
    guard let askCredentialHandler = self.askCredential?.handler else {
      return Observable.just(Void())
    }
    
    return Observable.just(Void())
      .map({ [unowned self] () -> Void in
        self.clearToken()
      })
      .flatMap({ () -> Observable<Void> in
        return askCredentialHandler()
      })
  }
  
  fileprivate func shouldRenewToken(forError error: Error) -> Bool {
    var shouldRenewToken = false
    if case NetworkStackError.http(httpURLResponse: let httpURLResponse, data: _) = error, httpURLResponse.statusCode == 401 {
      shouldRenewToken = true
    }
    return shouldRenewToken
  }
  
  fileprivate func shouldAskCredentials(forError error: Error) -> Bool {
    guard let triggerCondition = self.askCredential?.triggerCondition else {
      return false
    }
    return triggerCondition(error)
  }
  
  fileprivate func sendAutoRetryRequest<T>(_ sendRequestBlock: @escaping () -> Observable<T>, renewTokenFunction: @escaping () -> Observable<Void>) -> Observable<T> {
    
    return sendRequestBlock()
      .catchError { [unowned self] (error: Error) -> Observable<T> in
        // On error, check if we need to refresh token
        if let tokenManager = self.tokenManager, self.shouldRenewToken(forError: error) {
          tokenManager.invalidateToken()
          
          return tokenManager.fetchToken()
            .do(onError: { [unowned self] error in
              // Ask for credentials if renew token fail for any reason
              self.askCredentials()
                .subscribe()
                .disposed(by: self.disposeBag)
            })
            .flatMap({ (token) -> Observable<T> in
              // On success, retry the initial request
              return sendRequestBlock()
            }).take(1)// Send .completed after the first .next received from inside the flatMap (because the .completed from inside the flatMap doesn't propagate ouside the flatMap)
        } else {
          throw error
        }
    }
  }
}

// MARK: - Error management

extension NetworkStack {
  
  fileprivate func webserviceStackError(error: Error, httpURLResponse: HTTPURLResponse?, responseData: Data?) -> NetworkStackError {
    let otherErrorsBlock = { (error: NSError) -> NetworkStackError in
      let returnError: NetworkStackError
      if let httpURLResponse = httpURLResponse, 400..<600 ~= httpURLResponse.statusCode {
        returnError = NetworkStackError.http(httpURLResponse: httpURLResponse, data: responseData)
      } else if let httpURLResponse = httpURLResponse, 304 == httpURLResponse.statusCode {
        returnError = NetworkStackError.notModified
      } else {
        returnError = NetworkStackError.otherError(error: error)
      }
      return returnError
    }
    
    // We're forced to compare with NSError because there's a bug in Xcode 8.2 / Swift 3.0
    // when bridging NSErrors to Errors makes the program crash (BAD_INSTRUCTION) — Solved in 8.3
    let nserror = error as NSError
    guard nserror.domain == NSURLErrorDomain else {
      return otherErrorsBlock(nserror)
    }
    
    let finalError: NetworkStackError
    
    switch nserror.code {
    case NSURLErrorNotConnectedToInternet,
         NSURLErrorCannotLoadFromNetwork, NSURLErrorNetworkConnectionLost,
         NSURLErrorCallIsActive, NSURLErrorInternationalRoamingOff, NSURLErrorDataNotAllowed:
      finalError = NetworkStackError.noInternet(error: nserror)
    case NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed, NSURLErrorRedirectToNonExistentLocation:
      finalError = NetworkStackError.serverUnreachable(error: nserror)
    case NSURLErrorBadServerResponse, NSURLErrorCannotParseResponse, NSURLErrorCannotDecodeContentData, NSURLErrorCannotDecodeRawData:
      finalError = NetworkStackError.badServerResponse(error: nserror)
    default:
      finalError = otherErrorsBlock(nserror)
    }
    
    return finalError
  }
}

// MARK: - Request
extension NetworkStack {
  
  public func sendRequest<T: DataResponseSerializerProtocol>(
    alamofireRequest: Alamofire.DataRequest,
    queue: DispatchQueue = DispatchQueue.global(qos: .default),
    responseSerializer: T)
    -> Observable<(HTTPURLResponse, T.SerializedObject)> {
      
      // If Sessions.startImmediatly == false, need to manually launch the request.
      if alamofireRequest.state == .initialized {
        alamofireRequest.resume()
      }
      
      return Observable.create { [unowned self] observer in
        self.validateRequest(request: alamofireRequest)
          .response(queue: queue, responseSerializer: responseSerializer) { [unowned self] (packedResponse: DataResponse) -> Void in
            
            if let response = packedResponse.response, let request = packedResponse.request {
              self.delegate?.networkStack(self, didReceiveResponse: response, forRequest: request)
            }
            
            switch packedResponse.result {
            case .success(let result):
              if let httpResponse = packedResponse.response {
                observer.onNext((httpResponse, result))
              } else {
                observer.onError(NetworkStackError.unknown)
              }
              observer.onCompleted()
            case .failure(let error):
              let networkStackError = self.webserviceStackError(error: error, httpURLResponse: packedResponse.response, responseData: packedResponse.data)
              observer.onError(networkStackError)
            }
        }
        return Disposables.create {
          alamofireRequest.cancel()
        }
        }
        .subscribeOn(ConcurrentDispatchQueueScheduler(queue: queue))
  }
  
  fileprivate func sendRequest<T: DataResponseSerializerProtocol>(requestParameters: RequestParameters,
                                                                  queue: DispatchQueue = DispatchQueue.global(qos: .default),
                                                                  responseSerializer: T) -> Observable<(HTTPURLResponse, T.SerializedObject)> {
    if requestParameters.needsAuthorization {
      // Need to pass the parameters directly, because in case of retry, need to build the request again.
      return self.sendAuthenticatedRequest(requestParameters: requestParameters, queue: queue, responseSerializer: responseSerializer)
    } else {
      // Be carefull, call buildRequest and so `requestManager.request` method launch immediatly the request by default
      guard let request = self.buildRequest(requestParameters: requestParameters) else {
        return Observable.error(NetworkStackError.requestBuildFail)
      }
      
      return self.sendRequest(alamofireRequest: request, queue: queue, responseSerializer: responseSerializer)
    }
  }
  
  public func sendAuthenticatedRequest<T: DataResponseSerializerProtocol>(
    requestParameters: RequestParameters,
    queue: DispatchQueue = DispatchQueue.global(qos: .default),
    responseSerializer: T) -> Observable<(HTTPURLResponse, T.SerializedObject)> {
    
    let requestObservable: Observable<(HTTPURLResponse, T.SerializedObject)>
    
    if let tokenFetcher = self.renewTokenHandler {
      requestObservable = self.sendAutoRetryRequest({ [unowned self] () -> Observable<(HTTPURLResponse, T.SerializedObject)> in
        
        guard let request = self.buildRequest(requestParameters: requestParameters) else {
          return Observable.error(NetworkStackError.requestBuildFail)
        }
        
        return self.sendRequest(alamofireRequest: request, queue: queue, responseSerializer: responseSerializer)
        }, renewTokenFunction: { () -> Observable<Void> in
          return tokenFetcher().map { _ in return }
      })
    } else {
      
      guard let request = self.buildRequest(requestParameters: requestParameters) else {
        return Observable.error(NetworkStackError.requestBuildFail)
      }
      
      requestObservable = self.sendRequest(alamofireRequest: request, queue: queue, responseSerializer: responseSerializer)
    }
    
    return requestObservable
      .do(onError: { [unowned self] error in
        self.askCredentialsIfNeeded(forError: error)
          .subscribe()
          .disposed(by: self.disposeBag)
      })
  }
  
  /**
   Use this function if you need to send some parameters in xml format and so directly as data
   */
  public func sendAuthenticatedRequest<T: DataResponseSerializerProtocol>(
    request: DataRequest,
    queue: DispatchQueue = DispatchQueue.global(qos: .default),
    responseSerializer: T) -> Observable<(HTTPURLResponse, T.SerializedObject)> {
    
    let requestObservable: Observable<(HTTPURLResponse, T.SerializedObject)>
    
    if let tokenFetcher = self.renewTokenHandler {
      requestObservable = self.sendAutoRetryRequest({ [unowned self] () -> Observable<(HTTPURLResponse, T.SerializedObject)> in
        
        // In case of HTTP 401 error, need to launch a copy with updated accessToken
        var copy = self.copyAndUpdateAuthHeader(request: request) ?? request
        
        return self.sendRequest(alamofireRequest: copy, queue: queue, responseSerializer: responseSerializer)
        }, renewTokenFunction: { () -> Observable<Void> in
          return tokenFetcher()
            .map { _ in return }
      })
    } else {
      requestObservable = self.sendRequest(alamofireRequest: request, queue: queue, responseSerializer: responseSerializer)
    }
    
    return requestObservable
      .do(onError: { [unowned self] error in
        self.askCredentialsIfNeeded(forError: error)
          .subscribe()
          .disposed(by: self.disposeBag)
      })
  }
  
  private func copyAndUpdateAuthHeader(request: DataRequest) -> DataRequest? {
    guard let url: URL = request.request?.url,
      let methodString: String = request.request?.httpMethod,
      var headers: [String: String] = request.request?.allHTTPHeaderFields,
      let body: Data = request.request?.httpBody else {
        return nil
    }
    
    var originalRequest: URLRequest?
    let method: HTTPMethod = HTTPMethod(rawValue: methodString)
    
    // Update token
    if let authorizationHeaderValue = self.auhtorizationHeaderValue() {
      headers[NetworkStack.authorizationHeaderKey] = authorizationHeaderValue
    }
    
    do {
        originalRequest = try URLRequest(url: url, method: method, headers: HTTPHeaders(headers))
      originalRequest?.httpBody = body
      let encodedURLRequest = try URLEncoding.default.encode(originalRequest!, with: nil)
      let result = self.requestManager.request(encodedURLRequest)
      
      return result
    } catch {
      return nil
    }
  }
}

// MARK: - Data request
extension NetworkStack {
  
  public func sendRequestWithDataResponse(requestParameters: RequestParameters,
                                          queue: DispatchQueue = DispatchQueue.global(qos: .default)) -> Observable<(HTTPURLResponse, Data)> {
    return self.sendRequest(requestParameters: requestParameters,
                            queue: queue,
                            responseSerializer: DataResponseSerializer())
  }

}

// MARK: - JSON request
extension NetworkStack {
  
  public func sendRequestWithJSONResponse(requestParameters: RequestParameters,
                                          queue: DispatchQueue = DispatchQueue.global(qos: .default)) -> Observable<(HTTPURLResponse, Any)> {
    
    return self.sendRequest(requestParameters: requestParameters,
                            queue: queue,
                            responseSerializer: JSONResponseSerializer())
  }
  
}

// MARK: - OAuth
extension NetworkStack {
  fileprivate func auhtorizationHeaderValue() -> String? {
    guard let accessToken = self.keychainService.accessToken, self.keychainService.isAccessTokenValid else {
      return nil
    }
    return "Bearer \(accessToken)"
  }
  
  public func clearToken() {
    self.keychainService.accessToken = nil
    self.keychainService.refreshToken = nil
    self.keychainService.expirationInterval = nil
  }
  
  public func updateToken(token: String, refreshToken: String? = nil, expiresIn: TimeInterval? = nil) {
    self.keychainService.accessToken = token
    self.keychainService.refreshToken = refreshToken
    self.keychainService.expirationInterval = expiresIn
  }
  
  // Returns true if token is expired, and the app should show the authentication view
  public func isTokenExpired() -> Bool {
    return self.keychainService.isAccessTokenValid == false
  }
  
  public func currentAccessToken() -> String? {
    let token = self.keychainService.accessToken
    return token
  }
  
  public func currentRefreshToken() -> String? {
    return self.keychainService.refreshToken
  }
}
