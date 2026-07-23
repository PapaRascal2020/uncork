// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Uncork",
    platforms: [
        .macOS(.v14)   // NavigationSplitView + modern SwiftUI
    ],
    targets: [
        .executableTarget(
            name: "Uncork",
            path: "Sources/Uncork"
        )
    ]
)
