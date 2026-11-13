// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SurveySparrowSdk",
    
    platforms: [
        .iOS(.v15)
    ],
    
    products: [
        .library(
            name: "SurveySparrowSdk",
            targets: ["SurveySparrowSdk"]
        )
    ],
    
    targets: [
        .target(
            name: "SurveySparrowSdk"
        ),
        .testTarget(
            name: "SurveySparrowSdkTests",
            dependencies: ["SurveySparrowSdk"]
        )
    ]
)
