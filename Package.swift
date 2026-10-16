// swift-tools-version: 6.0
// MoniSwitch — a macOS menu bar utility for quick display switching.
// 构建命令：swift build -c release   （正式打包请用 Support/build-app.sh）
// v2：最低 macOS 14（@Observable / Observation 框架），新增单元测试目标。

import PackageDescription

let package = Package(
    name: "MoniSwitch",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "MoniSwitch",
            path: "Sources/MoniSwitch",
            swiftSettings: [
                // v2 重构期暂用 Swift 5 语言模式：旧 UI 层的 ObservableObject 单例
                // 尚未 Sendable 化（Phase 5/6 重写后尝试翻回 .v6）。
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "MoniSwitchTests",
            dependencies: ["MoniSwitch"],
            path: "Tests/MoniSwitchTests"
        )
    ]
)
