// swift-tools-version: 5.9
// AttroSDK - Lightweight iOS SDK for Attro affiliate tracking

import PackageDescription

let package = Package(
    name: "AttroSDK",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "AttroSDK",
            targets: ["AttroSDK"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "AttroSDK",
            dependencies: [],
            path: "Sources/AttroSDK"
        ),
        .testTarget(
            name: "AttroSDKTests",
            dependencies: ["AttroSDK"],
            path: "Tests/AttroSDKTests"
        ),
    ]
)
