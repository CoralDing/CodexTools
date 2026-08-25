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
            windowSize = NSSize(width: 372, height: 680)
        case "main":
            state = AppState(previewSnapshot: AppState.makeQAPreviewSnapshot())
            rootView = AnyView(MainWindowView().environmentObject(state))
            windowSize = NSSize(width: 920, height: 680)
        default:
            state = AppState(restoreStoredSession: false)
            rootView = AnyView(RootView().environmentObject(state))
            windowSize = NSSize(width: 360, height: 710)
        }
        let controller = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: controller)
        window.title = "CodexTools QA"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(windowSize)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)

        // 强引用窗口和状态，防止 SwiftUI 内容在验收过程中被提前释放。
        qaState = state
        qaWindow = window
    }
}
