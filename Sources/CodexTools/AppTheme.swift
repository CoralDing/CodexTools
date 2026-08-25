/**
 * 文件说明：CodexTools 界面颜色、尺寸和通用按钮样式
 * 作者：dingyi60(Codex)
 * 创建时间：2026-08-25
 */

import SwiftUI

/// 集中维护应用视觉变量，避免登录、仪表盘和设置页出现相近但不一致的样式。
enum AppTheme {
    static let accent = Color(red: 0.01, green: 0.49, blue: 0.50)
    static let accentPressed = Color(red: 0.01, green: 0.40, blue: 0.42)
    static let warning = Color(red: 0.92, green: 0.55, blue: 0.08)
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let contentCanvas = Color(nsColor: .textBackgroundColor).opacity(0.72)
    static let subtleSurface = Color(nsColor: .controlBackgroundColor).opacity(0.58)
    static let border = Color(nsColor: .separatorColor).opacity(0.58)
    static let strongBorder = Color(nsColor: .separatorColor).opacity(0.82)
    static let cornerRadius: CGFloat = 8
    static let contentPadding: CGFloat = 20
    static let mainWindowMinimumSize = CGSize(width: 860, height: 610)
}

/// 为主要数据区域提供单层浅色表面，使用细边框而不是多层阴影维持清晰分组。
struct PanelSurfaceModifier: ViewModifier {
    let padding: CGFloat

    /// 统一数据面板的内边距、背景和边界，防止不同页面出现细微样式漂移。
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(AppTheme.contentCanvas, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 1)
            }
    }
}

/// 为菜单栏和悬浮工具区提供真实系统材质，颜色会随桌面背景和深浅模式自然变化。
struct GlassSurfaceModifier: ViewModifier {
    let radius: CGFloat
    let addsShadow: Bool

    /// macOS 26 使用系统 Liquid Glass，旧系统回退到超薄材质并保持相同几何尺寸。
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                // 玻璃作为独立背景层，避免系统在深色模式下重新解释前景文字颜色。
                .background {
                    Color.clear
                        .glassEffect(
                            .regular,
                            in: RoundedRectangle(cornerRadius: radius, style: .continuous)
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 0.5)
                }
                .shadow(color: Color.black.opacity(addsShadow ? 0.10 : 0), radius: 18, y: 8)
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(Color.white.opacity(0.22), lineWidth: 0.5)
                }
                .shadow(color: Color.black.opacity(addsShadow ? 0.10 : 0), radius: 18, y: 8)
        }
    }
}

extension View {
    /// 应用标准数据面板样式，默认内边距适用于主窗口内容区。
    func panelSurface(padding: CGFloat = 18) -> some View {
        modifier(PanelSurfaceModifier(padding: padding))
    }

    /// 应用原生半透明玻璃表面，菜单栏根面板可选择更明显的柔和阴影。
    func glassSurface(radius: CGFloat = AppTheme.cornerRadius, addsShadow: Bool = false) -> some View {
        modifier(GlassSurfaceModifier(radius: radius, addsShadow: addsShadow))
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
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
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
