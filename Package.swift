// swift-tools-version: 5.9
// RideDeskSDK - Lightweight iOS SDK for RideDesk affiliate tracking

import PackageDescription

let package = Package(
    name: "RideDeskSDK",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "RideDeskSDK",
            targets: ["RideDeskSDK"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "RideDeskSDK",
            dependencies: [],
            path: "Sources/RideDeskSDK"
        ),
        .testTarget(
            name: "RideDeskSDKTests",
            dependencies: ["RideDeskSDK"],
            path: "Tests/RideDeskSDKTests"
        ),
    ]
)
