Pod::Spec.new do |s|

  s.name         = "NetworkStack"
  s.version      = "0.1.10"
  s.summary      = "A Swift network request manager framework using reactive programming"

  s.homepage     = "https://github.com/NijiDigital/NetworkStack"
  s.license      = { :type => "Apache 2", :file => "LICENSE" }

  s.authors            = { "Niji" => "" }
  s.social_media_url   = "https://twitter.com/niji_digital"

  s.ios.deployment_target = "10.0"

  s.source       = { :git => 'https://github.com/rrolland/NetworkStack.git', :tag => s.version.to_s }

  s.source_files = 'Sources/**/*.swift'

  s.ios.framework  = 'MobileCoreServices'

  s.dependency 'Alamofire', '~> 5.4'
  s.dependency 'RxSwift', '~> 5.1'
  s.dependency 'KeychainAccess', '~> 3.1'
end
