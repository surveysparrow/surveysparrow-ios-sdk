Pod::Spec.new do |spec|
  spec.name         = "SurveySparrowSdk"
  spec.version      = "0.2.0"
  spec.summary      = "SurveySparrow Feedback SDK for iOS"
  spec.description  = "SurveySparrow iOS SDK enables you to collect feedback from your mobile app. Embed the Classic & Chat surveys in your iOS application seamlessly with few lines of code."
  spec.homepage     = "https://surveysparrow.com"
  spec.license      = { :type => "MIT", :file => "LICENSE" }
  spec.author             = { "Ajay Sivan" => "ajaysivan@surveysparrow.com" }
  spec.platform     = :ios, "9.0"

  spec.source       = { :git => "https://github.com/surveysparrow/surveysparrow-ios-sdk.git", :tag => "#{spec.version}" }
  spec.source_files = "SurveySparrowSdk/**/*.swift"
  spec.swift_version = "5.0" 
end
