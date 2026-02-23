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
        .library(
            name: "AttroRevenueCat",
            targets: ["AttroRevenueCat"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/RevenueCat/purchases-ios-spm.git", from: "5.0.0"),
    ],
    targets: [
        .target(
            name: "AttroSDK",
            dependencies: [],
            path: "Sources/AttroSDK"
        ),
        .target(
            name: "AttroRevenueCat",
            dependencies: [
                "AttroSDK",
                .product(name: "RevenueCat", package: "purchases-ios-spm"),
            ],
            path: "Sources/AttroRevenueCat"
        ),
        .testTarget(
            name: "AttroSDKTests",
            dependencies: ["AttroSDK"],
            path: "Tests/AttroSDKTests"
        ),
    ]
)
