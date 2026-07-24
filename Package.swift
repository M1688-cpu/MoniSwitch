// swift-tools-version: 5.9
// MoniSwitch — a macOS menu bar utility for quick display switching.
// 构建命令：swift build -c release   （正式打包请用 Support/build-app.sh）

import PackageDescription

let package = Package(
    name: "MoniSwitch",
    platforms: [
        // MenuBarExtra 从 macOS 13 开始提供
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "MoniSwitch",
            path: "Sources/MoniSwitch"
        )
    ]
)
