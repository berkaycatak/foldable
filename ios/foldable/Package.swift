// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "foldable",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "foldable", targets: ["foldable"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "foldable",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                // If your plugin requires a privacy manifest, for example if it uses any required
                // reason APIs, update the PrivacyInfo.xcprivacy file to describe your plugin's
                // privacy impact, and then uncomment these lines. For more information, see
                // https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
                // .process("PrivacyInfo.xcprivacy"),

                // If you have other resources that need to be bundled with your plugin, refer to
                // the following instructions to add them:
                // https://developer.apple.com/documentation/xcode/bundling-resources-with-a-swift-package
            ],
            swiftSettings: [
                // The iPhone Duo hinge APIs ship in the iOS 27.1 SDK. Until
                // this package is built with Xcode 27.1 or newer, the hinge is
                // read through the Objective-C runtime instead, which keeps
                // the deployment target at iOS 13 and keeps older toolchains
                // compiling.
                //
                // With Xcode 27.1+, uncomment the next line to compile
                // NativeSources.swift against the real types.
                // .define("FOLDABLE_NATIVE_API"),
            ]
        )
    ]
)
