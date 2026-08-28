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

        // 视觉检查可显式覆盖外观，避免自动化进程始终继承启动终端的浅色模式。
        if let appearance = requestedAppearance {
            hostingView.appearance = appearance
        }

        // 原生窗口承载能正确绘制 TextField、Picker 和 Menu，ImageRenderer 会把这些控件画成占位符。
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        if let appearance = requestedAppearance {
            window.appearance = appearance
        }
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

    /// 把 QA 环境变量转换为 AppKit 外观；未设置时继续跟随当前 macOS 系统偏好。
    private static var requestedAppearance: NSAppearance? {
        switch ProcessInfo.processInfo.environment["CODEXTOOLS_QA_APPEARANCE"]?.lowercased() {
        case "dark": return NSAppearance(named: .darkAqua)
        case "light": return NSAppearance(named: .aqua)
        default: return nil
        }
    }

    /// 为登录、两步验证、菜单栏、主窗口和设置创建无凭据的确定性渲染目标。
    private static func makeRenderTarget(mode: String) -> RenderTarget {
        switch mode {
        case "two-factor":
            let state = AppState(previewTwoFactor: AppState.makeQAPreviewTwoFactor())
            return RenderTarget(
                view: AnyView(RootView().environmentObject(state)),
                size: CGSize(width: 388, height: 500)
            )
        case "dashboard":
            let state = AppState(previewSnapshot: AppState.makeQAPreviewSnapshot())
            return RenderTarget(
                view: AnyView(RootView().environmentObject(state)),
                size: CGSize(width: 388, height: 680)
            )
        case "main":
            let state = AppState(previewSnapshot: AppState.makeQAPreviewSnapshot())
            return RenderTarget(
                view: AnyView(MainWindowView().environmentObject(state)),
                size: CGSize(width: 1_120, height: 760)
            )
        case "main-api-keys":
            let state = AppState(previewSnapshot: AppState.makeQAPreviewSnapshot())
            return RenderTarget(
                view: AnyView(MainWindowView(initialSection: .apiKeys).environmentObject(state)),
                size: CGSize(width: 1_120, height: 760)
            )
        case "main-api-key-usage":
            let state = AppState(previewSnapshot: AppState.makeQAPreviewSnapshot())
            return RenderTarget(
                view: AnyView(
                    ZStack {
                        MainWindowView(initialSection: .apiKeys)
                            .environmentObject(state)
                        Color.black.opacity(0.045)
                        APIKeyUsageSheet(
                            key: makePreviewAPIKey(),
                            serverURL: URL(string: "https://sub2api.example")!,
                            suggestedModel: "gpt-5.6-sol",
                            previewResult: APIKeyImportResult(
                                message: "已导入 CC Switch",
                                detail: "已添加 Codex 与 Claude 供应商，当前供应商未切换。备份：/Users/example/.cc-switch/subpilot-backups/2026-08-28-120000/cc-switch.db"
                            )
                        )
                        // 检查器贴近窗口右侧，位置与真实 API 密钥页面中的右对齐浮层保持一致。
                        .offset(x: 286, y: 44)
                    }
                ),
                size: CGSize(width: 1_120, height: 760)
            )
        case "api-key-usage":
            return RenderTarget(
                view: AnyView(
                    APIKeyUsageSheet(
                        key: makePreviewAPIKey(),
                        serverURL: URL(string: "https://sub2api.example")!,
                        suggestedModel: "gpt-5.6-sol"
                    )
                ),
                size: CGSize(width: 430, height: 570)
            )
        case "api-key-usage-result":
            return RenderTarget(
                view: AnyView(
                    APIKeyUsageSheet(
                        key: makePreviewAPIKey(),
                        serverURL: URL(string: "https://sub2api.example")!,
                        suggestedModel: "gpt-5.6-sol",
                        previewResult: APIKeyImportResult(
                            message: "已导入 CC Switch",
                            detail: "已添加 Codex 与 Claude 供应商，当前供应商未切换。备份：/Users/example/.cc-switch/subpilot-backups/2026-08-28-120000/cc-switch.db"
                        )
                    )
                ),
                size: CGSize(width: 430, height: 570)
            )
        case "main-usage":
            let state = AppState(previewSnapshot: AppState.makeQAPreviewSnapshot())
            return RenderTarget(
                view: AnyView(MainWindowView(initialSection: .usage).environmentObject(state)),
                size: CGSize(width: 1_120, height: 760)
            )
        case "main-usage-detail":
            let state = AppState(previewSnapshot: AppState.makeQAPreviewSnapshot())
            state.showQAPreviewUsageDetail()
            return RenderTarget(
                view: AnyView(MainWindowView(initialSection: .usage).environmentObject(state)),
                size: CGSize(width: 1_120, height: 760)
            )
        case "main-profile":
            let state = AppState(previewSnapshot: AppState.makeQAPreviewSnapshot())
            return RenderTarget(
                view: AnyView(MainWindowView(initialSection: .profile).environmentObject(state)),
                size: CGSize(width: 1_120, height: 760)
            )
        case "settings":
            let state = AppState(previewSnapshot: AppState.makeQAPreviewSnapshot())
            return RenderTarget(
                view: AnyView(SettingsView().environmentObject(state)),
                size: CGSize(width: 460, height: 650)
            )
        case "balance-activity":
            let state = AppState(previewSnapshot: AppState.makeQAPreviewSnapshot())
            return RenderTarget(
                view: AnyView(
                    BalanceActivityView(balance: state.snapshot?.balance)
                        .environmentObject(state)
                ),
                size: CGSize(width: 440, height: 480)
            )
        default:
            let state = AppState(restoreStoredSession: false)
            return RenderTarget(
                view: AnyView(RootView().environmentObject(state)),
                size: CGSize(width: 388, height: 500)
            )
        }
    }

    /// 使用完全虚拟的密钥渲染导入弹窗，视觉检查不会读取或暴露用户的真实凭据。
    static func makePreviewAPIKey() -> UserAPIKey {
        UserAPIKey(
            id: 99,
            name: "Codex 主密钥",
            key: "sk-subpilot-preview-1234",
            groupName: "OpenAI",
            currentConcurrency: 1,
            quota: 100,
            quotaUsed: 24.8,
            status: "active",
            expiresAt: nil,
            createdAt: nil,
            lastUsedAt: nil,
            ipWhitelist: [],
            ipBlacklist: [],
            rateLimit5Hours: 0,
            rateLimit1Day: 0,
            rateLimit7Days: 0,
            usage5Hours: 0,
            usage1Day: 0,
            usage7Days: 0
        )
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
