// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "NabtoWebRTC",
    platforms: [.iOS(.v13), .macOS(.v11)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "NabtoWebRTC",
            targets: ["NabtoWebRTC"]),
        .library(
            name: "NabtoWebRTCUtil",
            targets: ["NabtoWebRTCUtil"])
    ],
    dependencies: [ .package(url: "https://github.com/Kitura/Swift-JWT.git", from: "4.0.0") ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "NabtoWebRTC",
            dependencies: [
                .product(name: "SwiftJWT", package: "Swift-JWT")
            ]),
        .target(
            name: "NabtoWebRTCUtil",
            dependencies: [
                .product(name: "SwiftJWT", package: "Swift-JWT"),
                .byName(name: "NabtoWebRTC")
            ]),
        .testTarget(
            name: "NabtoWebRTCTests",
            dependencies: ["NabtoWebRTC", "NabtoWebRTCUtil"]),
    ]
)
