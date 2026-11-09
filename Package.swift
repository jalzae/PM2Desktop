// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PM2Desktop",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "PM2Desktop",
            path: "Sources/PM2Desktop"
        )
    ]
)
