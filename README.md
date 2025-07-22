# Nabto WebRTC Signaling SDK for iOS

This is the Nabto WebRTC Signaling SDK for iOS. This repository contains the core signaling package, util package and an example app.

The libraries in this repository can be used together with the Nabto WebRTC Signaling Service and a WebRTC library. This way it is possible to create an application which streams video from an IoT device such as a camera.

Contents of this repository:
  * `Sources/NabtoWebRTC`: The `NabtoWebRTC` package which implements the nabto
    WebRTC core signaling client.
  * `Sources/NabtoWebRTCUtil`: The `NabtoWebRTCUtil` package which implements generic utilities.
    used when creating a WebRTC connection.
  * `Demo`: A simple example app using these libraries to showcase how to make a
    WebRTC connection to a Nabto WebRTC Signaling Device.

## Run the example test application:

1. Open the `Demo/Demo.xcodeproj` project in xcode.
2. Open `ViewController.swift` and edit `productId`, `deviceId` and `sharedSecret`
   to your configuration

A test video feed can be started at https://nabto.github.io/nabto-webrtc-sdk-js/

## SDK installation

The SDK is currently only available through the [Swift Package Manager](https://www.swift.org/documentation/package-manager/)

To install via the Swift Package Manager, add it through xcode by pressing `File > Add Package Dependencies...`.

Alternatively, if you are using a `Package.swift` file, add the following line to `dependencies`:

```swift
.package(url: "https://github.com/nabto/nabto-webrtc-sdk-ios.git", from: "x.x.x")
```

Then add `NabtoWebRTC` and `NabtoWebRTCUtil` to your target's dependencies (replace `x.x.x` with the latest [release](https://github.com/nabto/nabto-webrtc-sdk-ios/releases))

```swift
.target(name: "example", dependencies: ["NabtoWebRTC", "NabtoWebRTCUtil"]),
```

## Run integration tests
1. Run the integration test server from <https://github.com/nabto/nabto-webrtc-sdk-js/tree/main/integration_test_server>
2. Run `swift test`