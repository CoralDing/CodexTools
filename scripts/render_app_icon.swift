/**
 * 文件说明：将图片生成模型输出规范化为带透明边缘的 macOS 应用图标源图
 * 作者：dingyi60(Codex)
 * 创建时间：2026-08-26
 */

import AppKit
import Foundation

/// 图标规范化工具的错误类型，用于输出比系统异常更容易理解的失败原因。
enum IconRenderError: LocalizedError {
    case invalidArguments
    case cannotLoadSource(String)
    case cannotCreateBitmap
    case cannotEncodePNG

    /// 为构建脚本提供可直接展示的中文错误信息。
    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            return "用法：swift render_app_icon.swift <源图片> <输出 PNG>"
        case let .cannotLoadSource(path):
            return "无法读取图标源图片：\(path)"
        case .cannotCreateBitmap:
            return "无法创建 1024 像素图标画布"
        case .cannotEncodePNG:
            return "无法编码图标 PNG 文件"
        }
    }
}

/// 将模型生成的方形底图缩放到 Apple 图标安全区，并裁出透明圆角边缘。
func renderAppIcon(sourcePath: String, outputPath: String) throws {
    guard let sourceImage = NSImage(contentsOfFile: sourcePath) else {
        throw IconRenderError.cannotLoadSource(sourcePath)
    }

    let canvasPixels = 1024
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: canvasPixels,
        pixelsHigh: canvasPixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [.alphaFirst],
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw IconRenderError.cannotCreateBitmap
    }

    bitmap.size = NSSize(width: canvasPixels, height: canvasPixels)
    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        NSGraphicsContext.restoreGraphicsState()
        throw IconRenderError.cannotCreateBitmap
    }
    NSGraphicsContext.current = context

    // 透明安全区让图标在 Finder 与 Dock 中保持符合 macOS 习惯的视觉尺寸。
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: canvasPixels, height: canvasPixels).fill()

    let iconRect = NSRect(x: 62, y: 62, width: 900, height: 900)
    let clippingPath = NSBezierPath(roundedRect: iconRect, xRadius: 205, yRadius: 205)
    clippingPath.addClip()
    sourceImage.draw(
        in: iconRect,
        from: NSRect(origin: .zero, size: sourceImage.size),
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: true,
        hints: [.interpolation: NSImageInterpolation.high]
    )

    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
        throw IconRenderError.cannotEncodePNG
    }
    try pngData.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
}

do {
    guard CommandLine.arguments.count == 3 else {
        throw IconRenderError.invalidArguments
    }
    try renderAppIcon(sourcePath: CommandLine.arguments[1], outputPath: CommandLine.arguments[2])
} catch {
    FileHandle.standardError.write(Data("错误：\(error.localizedDescription)\n".utf8))
    exit(1)
}
