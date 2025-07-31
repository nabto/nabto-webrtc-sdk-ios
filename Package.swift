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
            targets: ["NabtoWebRTCUtil"]),
        .library(
            name: "NabtoWebRTCUtilPerfectNegotiation",
            targets: ["NabtoWebRTCUtilPerfectNegotiation"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/Kitura/Swift-JWT.git", from: "4.0.0"),
        .package(url: "https://github.com/apple/swift-openapi-generator", from: "1.6.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.7.0"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession", from: "1.0.0"),
        .package(url: "https://github.com/stasel/WebRTC.git", from: "138.0.0")
    ],
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
        .target(
            name: "NabtoWebRTCUtilPerfectNegotiation",
            dependencies: ["NabtoWebRTC", "NabtoWebRTCUtil", "WebRTC"]),
        .testTarget(
            name: "NabtoWebRTCTests",
            dependencies: ["NabtoWebRTC", "NabtoWebRTCUtil"]),
        .testTarget(
            name: "NabtoWebRTCIntegrationTest",
            dependencies: [
                .byName(name: "NabtoWebRTC"),
                .byName(name: "NabtoWebRTCUtil"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession")
            ],
            plugins: [
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")
            ]
        )
    ]
)
