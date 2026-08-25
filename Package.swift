// swift-tools-version: 6.0
/**
 * 文件说明：CodexTools 的 Swift Package（Swift 包管理器）工程配置
 * 作者：dingyi60(Codex)
 * 创建时间：2026-08-25
 */

import PackageDescription

let package = Package(
    name: "CodexTools",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CodexTools", targets: ["CodexTools"])
    ],
    targets: [
        .executableTarget(
            name: "CodexTools",
            path: "Sources/CodexTools"
        ),
        .testTarget(
            name: "CodexToolsTests",
            dependencies: ["CodexTools"],
            path: "Tests/CodexToolsTests"
        )
    ]
)
