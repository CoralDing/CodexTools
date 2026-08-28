/**
 * 文件说明：CodexTools 菜单栏应用入口
 * 作者：dingyi60(Codex)
 * 创建时间：2026-08-25
 */

import AppKit
import SwiftUI

/// 创建主操作窗口和菜单栏悬浮层，并持有贯穿应用生命周期的共享状态。
@main
struct CodexToolsApp: App {
    @NSApplicationDelegateAdaptor(QAWindowAppDelegate.self) private var appDelegate
    @StateObject private var appState: AppState

    /// 注册默认偏好后创建状态对象，确保轮询任务读取到有效间隔。
    init() {
        PreferenceKey.registerDefaults()
        let environment = ProcessInfo.processInfo.environment
        let isQualityCheck = environment["CODEXTOOLS_QA_WINDOW"] == "1"
            || environment["CODEXTOOLS_QA_RENDER_DIR"] != nil
        // QA 状态禁止恢复钥匙串会话，避免截图流程接触用户真实登录信息。
        _appState = StateObject(wrappedValue: AppState(restoreStoredSession: !isQualityCheck))
    }

    /// 主窗口承载完整操作，菜单栏负责快速查看，两个界面共享登录和用量状态。
    var body: some Scene {
        Window("SubPilot", id: "main") {
            MainWindowRootView()
                .environmentObject(appState)
        }
        .defaultSize(width: 1_120, height: 760)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unifiedCompact)

        MenuBarExtra {
            RootView()
                .environmentObject(appState)
        } label: {
            MenuBarStatusLabel(snapshot: appState.snapshot)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}

/// 根据设置把当前周期 Token 与消费排成紧凑的菜单栏摘要，数据不可用时自动只显示图标。
private struct MenuBarStatusLabel: View {
    let snapshot: DashboardSnapshot?
    @AppStorage(PreferenceKey.menuBarShowsTokens) private var showsTokens = true
    @AppStorage(PreferenceKey.menuBarShowsCost) private var showsCost = true

    /// 两项指标上下排列以减少横向占用；仅有一项时保持单行，避免出现多余空白。
    @ViewBuilder
    var body: some View {
        if metricLines.isEmpty {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .help("SubPilot")
        } else {
            // MenuBarExtra 会丢弃多行文本的第二行，因此合成为单个模板图像交给系统状态项绘制。
            Image(nsImage: MenuBarStatusImage.make(token: tokenMetric, cost: costMetric))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)
            .help("SubPilot · \(metricLines.joined(separator: " · "))")
        }
    }

    /// 返回菜单栏上排 Token；设置关闭或数据暂不可用时不占据空行。
    private var tokenMetric: String? {
        guard showsTokens, let tokens = snapshot?.periodTokens else { return nil }
        return UsageFormatter.compactTokens(tokens)
    }

    /// 返回菜单栏下排消费；设置关闭或数据暂不可用时不占据空行。
    private var costMetric: String? {
        guard showsCost, let cost = snapshot?.usageCost else { return nil }
        return UsageFormatter.cost(cost)
    }

    /// 按设置顺序生成可见行；Token 固定在上、消费固定在下，形成稳定的视觉记忆。
    private var metricLines: [String] {
        [tokenMetric, costMetric].compactMap { $0 }
    }

    /// 为辅助功能提供完整语义，视觉上的两行缩写不会降低屏幕阅读器可理解性。
    private var accessibilitySummary: String {
        guard let snapshot else { return "SubPilot" }
        var parts: [String] = ["SubPilot"]
        if showsTokens, snapshot.periodTokens != nil {
            parts.append("Token \(UsageFormatter.compactTokens(snapshot.periodTokens))")
        }
        if showsCost, snapshot.usageCost != nil {
            parts.append("消费 \(UsageFormatter.cost(snapshot.usageCost))")
        }
        return parts.joined(separator: "，")
    }
}

/// 把系统图标与一至两行指标绘制成模板图像，保证 macOS 菜单栏不会裁掉第二行。
private enum MenuBarStatusImage {
    private static let imageHeight: CGFloat = 24
    private static let iconSize: CGFloat = 19
    private static let contentSpacing: CGFloat = 5
    private static let minimumTextWidth: CGFloat = 44

    /// 根据启用的指标生成紧凑图像；模板模式会让系统自动适配浅色、深色和按下状态。
    static func make(token: String?, cost: String?) -> NSImage {
        let lines = [token, cost].compactMap { $0 }
        let fontSize: CGFloat = lines.count > 1 ? 10.5 : 12
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: lines.count > 1 ? .medium : .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]
        let lineSizes = lines.map { ($0 as NSString).size(withAttributes: attributes) }
        // 稳定的最小文字宽度避免 Token 或金额变化时菜单栏状态项持续左右跳动。
        let textWidth = max(ceil(lineSizes.map(\.width).max() ?? 0), minimumTextWidth)
        let imageWidth = ceil(iconSize + contentSpacing + textWidth)

        let image = NSImage(
            size: NSSize(width: imageWidth, height: imageHeight),
            flipped: false
        ) { bounds in
            drawIcon(in: bounds)
            drawLines(
                lines,
                sizes: lineSizes,
                attributes: attributes,
                textOriginX: iconSize + contentSpacing
            )
            return true
        }
        image.isTemplate = true
        return image
    }

    /// 使用 SF Symbols（苹果系统图标库）绘制应用标识，并与两行文字保持垂直居中。
    private static func drawIcon(in bounds: NSRect) {
        guard let symbol = NSImage(
            systemSymbolName: "gauge.with.dots.needle.67percent",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(.init(pointSize: iconSize, weight: .medium)) else {
            return
        }
        let originY = (bounds.height - iconSize) / 2
        symbol.draw(
            in: NSRect(x: 0, y: originY, width: iconSize, height: iconSize),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
    }

    /// 两项指标围绕画布中线排布并留出上下呼吸空间；单项指标保持垂直居中。
    private static func drawLines(
        _ lines: [String],
        sizes: [NSSize],
        attributes: [NSAttributedString.Key: Any],
        textOriginX: CGFloat
    ) {
        guard !lines.isEmpty else { return }
        if lines.count == 1, let size = sizes.first {
            let originY = (imageHeight - size.height) / 2
            (lines[0] as NSString).draw(at: NSPoint(x: textOriginX, y: originY), withAttributes: attributes)
            return
        }

        // AppKit 坐标从左下角开始；两条基线以 0.5pt 间距整体居中，避免贴住菜单栏边缘。
        let combinedHeight = sizes[0].height + sizes[1].height + 0.5
        let bottomY = max((imageHeight - combinedHeight) / 2, 0)
        let topY = bottomY + sizes[1].height + 0.5
        (lines[0] as NSString).draw(at: NSPoint(x: textOriginX, y: topY), withAttributes: attributes)
        (lines[1] as NSString).draw(at: NSPoint(x: textOriginX, y: bottomY), withAttributes: attributes)
    }
}
