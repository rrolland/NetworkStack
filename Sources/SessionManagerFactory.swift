//
//  SessionFactory.swift
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
import Alamofire

public struct SessionFactory {
  
  // MARK: Request session manager
  
  static func session(defaultHTTPHeaders: Alamofire.HTTPHeaders?,
                             requestTimeout: TimeInterval = 60.0) -> Alamofire.Session {
    let configuration = URLSessionConfiguration.default
    
    if let defaultHTTPHeaders = defaultHTTPHeaders {
        configuration.httpAdditionalHeaders = defaultHTTPHeaders.dictionary
    }
    
    configuration.timeoutIntervalForRequest = requestTimeout
    
    return self.session(withConfiguration: configuration)
  }
  
  // MARK: Common
  
  static func session(withConfiguration configuration: URLSessionConfiguration) -> Alamofire.Session {
    return Alamofire.Session(configuration: configuration)
  }
}
