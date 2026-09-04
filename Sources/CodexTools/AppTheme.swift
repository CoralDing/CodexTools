/**
 * 文件说明：CodexTools 界面颜色、尺寸和通用按钮样式
 * 作者：dingyi60(Codex)
 * 创建时间：2026-08-25
 */

import AppKit
import SwiftUI

/// 集中维护应用视觉变量，避免登录、仪表盘和设置页出现相近但不一致的样式。
enum AppTheme {
    // 使用系统语义色保证浅色、深色和高对比度模式都可读；品牌色只承担交互和主图表语义。
    static let accent = Color(red: 0.02, green: 0.58, blue: 0.57)
    static let accentPressed = Color(red: 0.01, green: 0.46, blue: 0.45)
    static let success = Color(nsColor: .systemGreen)
    static let warning = Color(nsColor: .systemOrange)
    static let danger = Color(nsColor: .systemRed)

    // 离散图表使用系统语义色区分模型和平台，避免所有数据都挤在同一种青绿色里。
    static let chartPalette: [Color] = [
        accent,
        Color(nsColor: .systemBlue),
        Color(nsColor: .systemOrange),
        Color(nsColor: .systemIndigo),
        Color(nsColor: .systemPink)
    ]

    // 使用 AppKit 语义色跟随 macOS 外观。此前固定的深石墨背景遇到浅色系统文字时，会产生黑底黑字。
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let contentCanvas = Color(nsColor: .controlBackgroundColor)
    static let inspectorCanvas = Color(nsColor: .underPageBackgroundColor)
    static let workspaceCanvas = Color(nsColor: .windowBackgroundColor)

    // 控件、代码块和表头都从系统主文字色派生，浅色模式使用黑色轻染，深色模式自动改为白色轻染。
    static let controlFill = Color.primary.opacity(0.055)
    static let codeSurface = Color.primary.opacity(0.060)
    static let subtleSurface = Color.primary.opacity(0.040)
    static let selectedSurface = accent.opacity(0.11)
    static let tableHeader = Color.primary.opacity(0.032)
    static let border = Color.primary.opacity(0.085)
    static let strongBorder = Color.primary.opacity(0.14)

    // 玻璃只保留极轻的语义色染色，避免在浅色模式下把整个悬浮层压成灰黑色。
    static let glassTint = Color.primary.opacity(0.010)
    static let chromeGlassTint = Color.primary.opacity(0.018)
    // 阅读型浮层需要压住底层图表和选中行的颜色折射；仍使用 Liquid Glass，只提高中性染色保证长文本清晰。
    static let floatingGlassTint = Color(nsColor: .windowBackgroundColor).opacity(0.42)
    static let cornerRadius: CGFloat = 8
    static let floatingCornerRadius: CGFloat = 12
    static let contentPadding: CGFloat = 20
    static let compactContentPadding: CGFloat = 16
    static let sidebarWidth: CGFloat = 208
    static let pageHeaderHeight: CGFloat = 64
    static let controlHeight: CGFloat = 32
    static let tableRowHeight: CGFloat = 52
    static let mainWindowMinimumSize = CGSize(width: 1_040, height: 680)

    // 字体角色集中定义后，页面不再各自使用难以辨认的 8～10pt 字号。
    static let pageTitleFont = Font.system(size: 20, weight: .semibold)
    static let sectionTitleFont = Font.system(size: 13, weight: .semibold)
    static let bodyFont = Font.system(size: 12)
    static let bodyEmphasizedFont = Font.system(size: 12, weight: .medium)
    static let captionFont = Font.system(size: 11)
    static let metricFont = Font.system(size: 20, weight: .semibold, design: .rounded)

    /// 离屏位图没有 WindowServer（窗口合成服务）上下文，必须使用传统材质才能生成可读 QA 截图。
    static var usesOffscreenMaterialFallback: Bool {
        ProcessInfo.processInfo.environment["CODEXTOOLS_QA_RENDER_DIR"] != nil
    }
}

/// 在整个工作区后方提供宽幅色带，让透明材质能呈现真实折射而不干扰数据阅读。
struct SubPilotWindowBackdrop: View {
    var showsSidebarTint = true

    /// 使用静态低透明度色带为玻璃提供折射层次，避免大半径实时模糊拖慢窗口滚动和缩放。
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                AppTheme.canvas

                // 左侧仅保留极淡静态色带，为侧栏玻璃提供折射层次且不会把工作区染成单一青色。
                if showsSidebarTint {
                    Rectangle()
                        .fill(AppTheme.accent.opacity(0.020))
                        .frame(width: min(AppTheme.sidebarWidth + 36, proxy.size.width * 0.22))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // 底部横带使用固定透明度表达层次，不参与滚动内容的动态采样和模糊计算。
                Rectangle()
                    .fill(Color.primary.opacity(0.008))
                    .frame(height: max(96, proxy.size.height * 0.16))
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .ignoresSafeArea()
        }
    }
}

/// 把 SwiftUI 主窗口配置为可显示系统材质的透明窗口，避免 AppKit 默认实色背景吞掉玻璃效果。
struct WindowGlassConfigurator: NSViewRepresentable {
    /// 创建一个不可见的附着视图；真正配置要等它进入 NSWindow（macOS 窗口对象）后执行。
    func makeNSView(context: Context) -> NSView {
        WindowGlassAttachmentView()
    }

    /// 窗口属性不依赖 SwiftUI 状态，更新阶段无需重复设置。
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// 监听自身进入窗口的时机，保证透明背景配置不会因为首次创建时 `window == nil` 而失效。
private final class WindowGlassAttachmentView: NSView {
    /// 视图进入主窗口后开启透明标题栏和透明窗口底色，保留标准窗口按钮与拖拽行为。
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.hasShadow = true
    }
}

/// 在应用包中优先加载正式 App Icon，调试环境缺少资源时回退为同色系 S 标识。
struct SubPilotBrandIcon: View {
    let size: CGFloat

    /// 使用固定方形尺寸，图标加载状态不会改变侧栏和登录页布局。
    var body: some View {
        Group {
            if let image = NSImage(named: "AppIcon") {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                Text("S")
                    .font(.system(size: size * 0.58, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.accent)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}

/// 为主要数据区域提供单层自适应表面，以细边框和静态微阴影维持清晰分组。
struct PanelSurfaceModifier: ViewModifier {
    let padding: CGFloat

    /// 统一数据面板的内边距、背景和边界，防止不同页面出现细微样式漂移。
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(AppTheme.contentCanvas, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 0.75)
            }
            .overlay(alignment: .top) {
                // 顶边高光模拟原生控制面的受光关系，静态描边不会触发滚动中的实时模糊。
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                    .trim(from: 0.04, to: 0.46)
                    .stroke(Color.white.opacity(0.22), lineWidth: 0.65)
                    .padding(0.5)
            }
            .shadow(color: Color.black.opacity(0.035), radius: 7, y: 2)
    }
}

/// 为菜单栏和悬浮工具区提供真实系统材质，颜色会随桌面背景和深浅模式自然变化。
struct GlassSurfaceModifier: ViewModifier {
    let radius: CGFloat
    let tint: Color?
    let isInteractive: Bool
    let addsShadow: Bool

    /// macOS 26 使用系统 Liquid Glass，旧系统回退到超薄材质并保持相同几何尺寸。
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), !AppTheme.usesOffscreenMaterialFallback {
            content
                // 直接把玻璃应用到容器，避免额外实色背景阻断系统对下方内容的折射采样。
                .glassEffect(
                    .regular.tint(tint).interactive(isInteractive),
                    in: RoundedRectangle(cornerRadius: radius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(AppTheme.border, lineWidth: 0.75)
                }
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .trim(from: 0.04, to: 0.46)
                        .stroke(Color.white.opacity(0.34), lineWidth: 0.8)
                        .padding(0.5)
                }
                .shadow(color: Color.black.opacity(addsShadow ? 0.16 : 0), radius: 24, y: 12)
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .background(tint ?? Color.clear, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(AppTheme.border, lineWidth: 0.75)
                }
                .shadow(color: Color.black.opacity(addsShadow ? 0.14 : 0), radius: 20, y: 10)
        }
    }
}

/// 为侧栏和顶部工具栏提供无圆角的系统玻璃背景，保持窗口内容与操作区域的清晰分层。
struct GlassChromeSurfaceModifier: ViewModifier {
    /// 新系统使用 Liquid Glass，旧系统使用原生薄材质，并保留一条克制的高光边界。
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), !AppTheme.usesOffscreenMaterialFallback {
            content
                .glassEffect(.regular.tint(AppTheme.chromeGlassTint), in: Rectangle())
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.white.opacity(0.22)).frame(height: 0.5)
                }
                .overlay(alignment: .bottom) {
                    Rectangle().fill(AppTheme.border).frame(height: 0.5)
                }
        } else {
            content
                .background(.thinMaterial)
                .background(AppTheme.chromeGlassTint)
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.white.opacity(0.18)).frame(height: 0.5)
                }
                .overlay(alignment: .bottom) {
                    Rectangle().fill(AppTheme.border).frame(height: 0.5)
                }
        }
    }
}

extension View {
    /// 应用标准数据面板样式，默认内边距适用于主窗口内容区。
    func panelSurface(padding: CGFloat = 18) -> some View {
        modifier(PanelSurfaceModifier(padding: padding))
    }

    /// 应用原生半透明玻璃表面，菜单栏根面板可选择更明显的柔和阴影。
    func glassSurface(
        radius: CGFloat = AppTheme.cornerRadius,
        tint: Color? = AppTheme.glassTint,
        isInteractive: Bool = false,
        addsShadow: Bool = false
    ) -> some View {
        modifier(
            GlassSurfaceModifier(
                radius: radius,
                tint: tint,
                isInteractive: isInteractive,
                addsShadow: addsShadow
            )
        )
    }

    /// 应用适合窗口侧栏和工具栏的整块玻璃背景，不改变内容本身的布局尺寸。
    func glassChromeSurface() -> some View {
        modifier(GlassChromeSurfaceModifier())
    }

    /// 在 macOS 26 使用原生玻璃按钮，旧系统回退到标准边框按钮并保持同一点击尺寸。
    @ViewBuilder
    func subPilotGlassButtonStyle() -> some View {
        if #available(macOS 26.1, *), !AppTheme.usesOffscreenMaterialFallback {
            self.buttonStyle(.glass(.regular.interactive()))
        } else {
            self.buttonStyle(.bordered)
        }
    }

    /// 主要命令使用更高对比度的原生玻璃按钮，避免依赖自绘渐变或厚重阴影。
    @ViewBuilder
    func subPilotProminentGlassButtonStyle() -> some View {
        if #available(macOS 26.0, *), !AppTheme.usesOffscreenMaterialFallback {
            self.buttonStyle(.glassProminent)
                .tint(AppTheme.accent)
        } else {
            self.buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
        }
    }

    /// 次级但高价值的命令使用轻度品牌色玻璃，提升辨识度但不与主创建按钮争抢层级。
    @ViewBuilder
    func subPilotTintedGlassButtonStyle() -> some View {
        self.buttonStyle(SubPilotTintedCommandButtonStyle())
    }
}

/// 次级命令使用清晰的青绿文字和轻玻璃底，窗口失焦时也不会看起来像禁用按钮。
struct SubPilotTintedCommandButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    /// 按压只改变底色和描边，不缩放控件，避免表格行与检查器按钮发生布局抖动。
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isEnabled ? AppTheme.accent : Color.secondary)
            .padding(.horizontal, 10)
            .frame(minHeight: 28)
            .background(
                AppTheme.accent.opacity(configuration.isPressed ? 0.20 : 0.10),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(AppTheme.accent.opacity(isEnabled ? 0.24 : 0.08), lineWidth: 0.75)
            }
            .opacity(isEnabled ? 1 : 0.48)
    }
}

/// 主操作按钮使用稳定高度和克制圆角，按压反馈不改变布局尺寸。
struct PrimaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    /// 根据按压和禁用状态切换颜色，保证按钮语义明确且具备原生反馈。
    func makeBody(configuration: Configuration) -> some View {
        let foregroundColor = isEnabled ? Color.white : Color.secondary
        let backgroundColor = isEnabled
            ? (configuration.isPressed ? AppTheme.accentPressed : AppTheme.accent)
            : Color.secondary.opacity(0.12)

        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(
                backgroundColor,
                in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
            )
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// 工具栏图标按钮使用固定方形点击区域，避免加载状态或不同图标造成界面位移。
struct ToolbarIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    /// 为常用图标命令提供统一边框、悬浮层背景和按压反馈。
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.primary)
            .frame(width: 30, height: 30)
            .background(AppTheme.controlFill, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
            .background(
                configuration.isPressed ? Color.primary.opacity(0.08) : Color.clear,
                in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 1)
            }
            .opacity(isEnabled ? 1 : 0.45)
    }
}

/// 表格中的图标命令使用稳定点击区域，颜色仅用于强调导入和删除等不同语义。
struct TableIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var tint: Color = .secondary

    /// 固定按钮尺寸，避免小图标难以点击；按压只改变背景，不造成表格行抖动。
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isEnabled ? tint : Color.secondary)
            .frame(width: 26, height: 26)
            .background(
                configuration.isPressed ? tint.opacity(0.14) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.45)
    }
}
