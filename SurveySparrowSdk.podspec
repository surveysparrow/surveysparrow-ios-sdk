Pod::Spec.new do |spec|
  spec.name         = "SurveySparrowSdk"
  spec.version      = "0.0.3"
  spec.summary      = "SurveySparrow Feedback SDK for iOS"
  spec.description  = "SurveySparrow Feedback SDK for iOS"
  spec.homepage     = "https://surveysparrow.com"
  spec.license      = "MIT"
  spec.author             = { "Ajay Sivan" => "ajaysivan@surveysparrow.com" }
  spec.platform     = :ios, "9.0"

  # spec.source       = { :git => "http://EXAMPLE/SurveySparrowSdk.git", :tag => "#{spec.version}" }
  spec.source       = { :path => '.' }
  spec.source_files = "SurveySparrowSdk/**/*.swift"
  spec.swift_version = "5.0" 
end
