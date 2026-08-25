/**
 * 文件说明：将确定性的 SwiftUI 质量检查状态离屏渲染为 PNG 图片
 * 作者：dingyi60(Codex)
 * 创建时间：2026-08-25
 */

import AppKit
import SwiftUI

/// 仅在显式 QA 环境变量存在时生成界面截图，不读取钥匙串或发送网络请求。
@MainActor
enum QARenderer {
    /// 根据状态名称创建固定数据视图，通过原生承载视图以 2 倍比例保存为 PNG 图片。
    static func render(mode: String, outputDirectory: URL) throws -> URL {
        let renderTarget = makeRenderTarget(mode: mode)
        let hostingView = NSHostingView(rootView: renderTarget.view)
        hostingView.frame = NSRect(origin: .zero, size: renderTarget.size)

        // 原生窗口承载能正确绘制 TextField、Picker 和 Menu，ImageRenderer 会把这些控件画成占位符。
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()

        let scale = 2
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(renderTarget.size.width) * scale,
            pixelsHigh: Int(renderTarget.size.height) * scale,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw QARenderError.imageEncodingFailed
        }
        bitmap.size = renderTarget.size
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw QARenderError.imageEncodingFailed
        }

        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        let outputURL = outputDirectory.appending(path: "codextools-\(mode).png")
        try pngData.write(to: outputURL, options: .atomic)
        return outputURL
    }

    /// 为登录、两步验证、菜单栏、主窗口和设置创建无凭据的确定性渲染目标。
    private static func makeRenderTarget(mode: String) -> RenderTarget {
        switch mode {
        case "two-factor":
            let state = AppState(previewTwoFactor: AppState.makeQAPreviewTwoFactor())
            return RenderTarget(
                view: AnyView(RootView().environmentObject(state)),
                size: CGSize(width: 360, height: 480)
            )
        case "dashboard":
            let state = AppState(previewSnapshot: AppState.makeQAPreviewSnapshot())
            return RenderTarget(
                view: AnyView(RootView().environmentObject(state)),
                size: CGSize(width: 372, height: 680)
            )
        case "main":
            let state = AppState(previewSnapshot: AppState.makeQAPreviewSnapshot())
            return RenderTarget(
                view: AnyView(MainWindowView().environmentObject(state)),
                size: CGSize(width: 920, height: 680)
            )
        case "settings":
            let state = AppState(previewSnapshot: AppState.makeQAPreviewSnapshot())
            return RenderTarget(
                view: AnyView(SettingsView().environmentObject(state)),
                size: CGSize(width: 420, height: 660)
            )
        default:
            let state = AppState(restoreStoredSession: false)
            return RenderTarget(
                view: AnyView(RootView().environmentObject(state)),
                size: CGSize(width: 372, height: 480)
            )
        }
    }

    /// 将类型擦除后的视图和目标尺寸绑定在一起，避免不同状态分支产生泛型冲突。
    private struct RenderTarget {
        let view: AnyView
        let size: CGSize
    }

    /// 描述离屏渲染过程中唯一需要单独识别的图片编码错误。
    private enum QARenderError: LocalizedError {
        case imageEncodingFailed

        /// 为命令行质量检查输出可理解的失败原因。
        var errorDescription: String? {
            "SwiftUI 离屏图片编码失败"
        }
    }
}
