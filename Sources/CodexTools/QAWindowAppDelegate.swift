/**
 * 文件说明：仅在质量检查环境中创建可被自动化工具读取的普通窗口
 * 作者：dingyi60(Codex)
 * 创建时间：2026-08-25
 */

import AppKit
import SwiftUI

/// 将菜单栏根视图放进 QA 专用窗口，生产启动时不会创建任何普通窗口。
@MainActor
final class QAWindowAppDelegate: NSObject, NSApplicationDelegate {
    private var qaWindow: NSWindow?
    private var qaState: AppState?

    /// 应用启动完成后检查环境开关，并创建与当前仪表盘高度一致的视觉验收窗口。
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let outputPath = ProcessInfo.processInfo.environment["CODEXTOOLS_QA_RENDER_DIR"],
           !outputPath.isEmpty {
            let qaMode = ProcessInfo.processInfo.environment["CODEXTOOLS_QA_STATE"] ?? "login"
            do {
                let outputURL = try QARenderer.render(
                    mode: qaMode,
                    outputDirectory: URL(filePath: outputPath, directoryHint: .isDirectory)
                )
                print(outputURL.path)
            } catch {
                fputs("QA 渲染失败：\(error.localizedDescription)\n", stderr)
            }
            NSApplication.shared.terminate(nil)
            return
        }

        guard ProcessInfo.processInfo.environment["CODEXTOOLS_QA_WINDOW"] == "1" else {
            return
        }

        NSApplication.shared.setActivationPolicy(.regular)
        let qaMode = ProcessInfo.processInfo.environment["CODEXTOOLS_QA_STATE"] ?? "login"
        let state: AppState
        let rootView: AnyView
        let windowSize: NSSize
        switch qaMode {
        case "two-factor":
            // 使用固定的脱敏账户和无效临时令牌，只渲染界面而不接触真实登录数据。
            state = AppState(previewTwoFactor: AppState.makeQAPreviewTwoFactor())
            rootView = AnyView(RootView().environmentObject(state))
            windowSize = NSSize(width: 360, height: 710)
        case "settings":
            state = AppState(previewSnapshot: AppState.makeQAPreviewSnapshot())
            // 设置模式直接使用独立窗口内容，不再依赖菜单栏临时窗口上的 Sheet。
            rootView = AnyView(SettingsView().environmentObject(state))
            windowSize = NSSize(width: 420, height: 660)
        case "dashboard":
            state = AppState(previewSnapshot: AppState.makeQAPreviewSnapshot())
            rootView = AnyView(RootView().environmentObject(state))
            windowSize = NSSize(width: 372, height: 740)
        case "main":
            state = AppState(previewSnapshot: AppState.makeQAPreviewSnapshot())
            rootView = AnyView(MainWindowView().environmentObject(state))
            windowSize = NSSize(width: 1_120, height: 760)
        case "main-api-keys":
            state = AppState(previewSnapshot: AppState.makeQAPreviewSnapshot())
            rootView = AnyView(MainWindowView(initialSection: .apiKeys).environmentObject(state))
            windowSize = NSSize(width: 1_120, height: 760)
        case "main-api-key-usage":
            state = AppState(previewSnapshot: AppState.makeQAPreviewSnapshot())
            rootView = AnyView(
                ZStack {
                    MainWindowView(initialSection: .apiKeys)
                        .environmentObject(state)
                    Color.black.opacity(0.22)
                    APIKeyUsageSheet(
                        key: QARenderer.makePreviewAPIKey(),
                        serverURL: URL(string: "https://sub2api.example")!,
                        suggestedModel: "gpt-5.6-sol"
                    )
                    .offset(x: 286, y: 44)
                }
            )
            windowSize = NSSize(width: 1_120, height: 760)
        case "balance-activity":
            state = AppState(previewSnapshot: AppState.makeQAPreviewSnapshot())
            rootView = AnyView(
                BalanceActivityView(balance: state.snapshot?.balance)
                    .environmentObject(state)
            )
            windowSize = NSSize(width: 430, height: 480)
        default:
            state = AppState(restoreStoredSession: false)
            rootView = AnyView(RootView().environmentObject(state))
            windowSize = NSSize(width: 360, height: 710)
        }
        let controller = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: controller)
        window.title = "SubPilot QA"
        // QA 窗口使用与生产窗口相同的透明全尺寸内容，才能由 WindowServer 合成真实 Liquid Glass。
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.setContentSize(windowSize)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)

        // 强引用窗口和状态，防止 SwiftUI 内容在验收过程中被提前释放。
        qaState = state
        qaWindow = window
    }
}
