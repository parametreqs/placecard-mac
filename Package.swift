// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "PlaceCardMac", platforms: [.macOS(.v14)], products: [
    .executable(name: "PlaceCardMac", targets: ["PlaceCardMac"])
], targets: [
    .target(name: "Z2Transport", linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]),
    .target(name: "CardCore"),
    .executableTarget(name: "PlaceCardMac", dependencies: ["Z2Transport", "CardCore"]),
    .testTarget(name: "CardCoreTests", dependencies: ["CardCore", "Z2Transport"])
], swiftLanguageModes: [.v5])
