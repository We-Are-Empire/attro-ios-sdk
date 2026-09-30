// swift-tools-version: 5.9
// AttroSDK - iOS SDK for Attro affiliate attribution
// (contract: Attro docs/contracts/ios-attribution.md)

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
            path: "Sources/AttroSDK",
            resources: [.copy("Resources/PrivacyInfo.xcprivacy")]
        ),
        .target(
            name: "AttroRevenueCat",
            dependencies: [
                "AttroSDK",
                .product(name: "RevenueCat", package: "purchases-ios-spm"),
            ],
            path: "Sources/AttroRevenueCat",
            resources: [.copy("Resources/PrivacyInfo.xcprivacy")]
        ),
        .testTarget(
            name: "AttroSDKTests",
            dependencies: ["AttroSDK"],
            path: "Tests/AttroSDKTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
