/**
 * 文件说明：菜单栏摘要、通知阈值、刷新频率与时间显示设置
 * 作者：dingyi60(Codex)
 * 创建时间：2026-08-25
 */

import AppKit
import SwiftUI

/// 提供通知、同步和时区设置，修改后立即持久化并在关闭时重启轮询。
struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PreferenceKey.notificationsEnabled) private var notificationsEnabled = false
    @AppStorage(PreferenceKey.balanceThreshold) private var balanceThreshold = 20.0
    @AppStorage(PreferenceKey.quotaThreshold) private var quotaThreshold = 15.0
    @AppStorage(PreferenceKey.refreshMinutes) private var refreshMinutes = 5
    @AppStorage(PreferenceKey.displayTimeZone) private var displayTimeZone = TimeZone.current.identifier
    @AppStorage(PreferenceKey.menuBarShowsTokens) private var menuBarShowsTokens = true
    @AppStorage(PreferenceKey.menuBarShowsCost) private var menuBarShowsCost = true
    @AppStorage(PreferenceKey.consumptionAnalysisEnabled) private var consumptionAnalysisEnabled = true
    @AppStorage(PreferenceKey.communityResetNotificationsEnabled) private var communityResetNotificationsEnabled = true

    /// 使用开放式分组和紧凑设置行，保持原生控件能力但减少默认表单的厚重感。
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    settingsSection("菜单栏") { menuBarSettings }
                    settingsSection("分析") { consumptionAnalysisSettings }
                    settingsSection("提醒") { notificationSettings }
                    settingsSection("同步与时间") { syncSettings }
                }
                .padding(AppTheme.contentPadding)
            }

            Divider()
            footer
        }
        .frame(width: 460, height: 650)
        .background(SubPilotWindowBackdrop(showsSidebarTint: false))
    }

    /// 消耗分析使用独立开关；关闭后立即停止后台任务，且不会连带关闭设置窗口。
    private var consumptionAnalysisSettings: some View {
        VStack(spacing: 0) {
            settingRow(
                icon: "waveform.path.ecg",
                title: "启用消耗分析",
                subtitle: "每小时使用 CC Switch 本地数据核对中转扣费"
            ) {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { consumptionAnalysisEnabled },
                        set: { enabled in
                            consumptionAnalysisEnabled = enabled
                            appState.setConsumptionAnalysisEnabled(enabled)
                        }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(AppTheme.accent)
            }
        }
        .modifier(SettingsGroupStyle())
    }

    /// 标题栏提供清晰页面名称和固定尺寸的关闭命令。
    private var header: some View {
        HStack {
            Text("应用设置")
                .font(.system(size: 17, weight: .semibold))
            Spacer()
            Button(action: saveAndDismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(ToolbarIconButtonStyle())
            .help("保存并关闭")
        }
        .padding(.horizontal, AppTheme.contentPadding)
        .frame(height: 56)
        .glassChromeSurface()
    }

    /// 菜单栏摘要用两个独立开关组合；全部关闭时仅保留应用图标，避免另设冗余模式控件。
    private var menuBarSettings: some View {
        VStack(spacing: 0) {
            settingRow(icon: "textformat.123", title: "显示 Token", subtitle: "使用 M（百万）或 K（千）紧凑显示") {
                Toggle("", isOn: $menuBarShowsTokens)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(AppTheme.accent)
            }

            settingDivider

            settingRow(icon: "dollarsign", title: "显示消费", subtitle: "跟随悬浮面板当前统计周期") {
                Toggle("", isOn: $menuBarShowsCost)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(AppTheme.accent)
            }
        }
        .modifier(SettingsGroupStyle())
    }

    /// 通知分组包含总开关、社区重置开关和两个阈值，关闭总开关时仍保留各项设置。
    private var notificationSettings: some View {
        VStack(spacing: 0) {
            settingRow(icon: "bell", title: "启用系统通知") {
                Toggle("", isOn: $notificationsEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(AppTheme.accent)
            }

            settingDivider

            settingRow(
                icon: "clock.arrow.circlepath",
                title: "社区重置提醒",
                subtitle: "社区追踪，非个人账户账单记录"
            ) {
                Toggle("", isOn: $communityResetNotificationsEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(AppTheme.accent)
                    .opacity(notificationsEnabled ? 1 : 0.5)
                    .disabled(!notificationsEnabled)
            }

            settingDivider

            settingRow(icon: "dollarsign.circle", title: "余额阈值", subtitle: "低于此金额时提醒") {
                HStack(spacing: 6) {
                    TextField("20", value: $balanceThreshold, format: .number.precision(.fractionLength(0...2)))
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 72)
                    Text("USD")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .opacity(notificationsEnabled ? 1 : 0.5)
                .disabled(!notificationsEnabled)
            }

            settingDivider

            settingRow(icon: "chart.pie", title: "额度剩余", subtitle: "低于此比例时提醒") {
                Stepper(
                    "\(Int(quotaThreshold))%",
                    value: $quotaThreshold,
                    in: 1...100,
                    step: 1
                )
                .frame(width: 120)
                .opacity(notificationsEnabled ? 1 : 0.5)
                .disabled(!notificationsEnabled)
            }
        }
        .modifier(SettingsGroupStyle())
    }

    /// 同步分组管理轮询频率和所有时间字段使用的显示时区。
    private var syncSettings: some View {
        VStack(spacing: 0) {
            settingRow(icon: "arrow.clockwise", title: "刷新间隔") {
                Picker("", selection: $refreshMinutes) {
                    Text("每 1 分钟").tag(1)
                    Text("每 5 分钟").tag(5)
                    Text("每 15 分钟").tag(15)
                    Text("每 30 分钟").tag(30)
                }
                .labelsHidden()
                .frame(width: 132)
            }

            settingDivider

            settingRow(icon: "globe", title: "显示时区") {
                Picker("", selection: $displayTimeZone) {
                    ForEach(timeZoneOptions, id: \.self) { identifier in
                        Text(identifier).tag(identifier)
                    }
                }
                .labelsHidden()
                .frame(width: 176)
            }
        }
        .modifier(SettingsGroupStyle())
    }

    /// 底栏只保留主要完成操作，避免设置面板出现多个语义相近的按钮。
    private var footer: some View {
        HStack {
            Spacer()
            Button("完成", action: saveAndDismiss)
                .buttonStyle(PrimaryActionButtonStyle())
                .frame(width: 92)
        }
        .padding(.horizontal, AppTheme.contentPadding)
        .frame(height: 58)
        .glassChromeSurface()
    }

    /// 标题和设置组作为一个整体参与纵向排版，避免依赖负间距造成窗口缩放时错位。
    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppTheme.captionFont.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 3)
            content()
        }
    }

    /// 设置行固定图标列和最小高度，副标题存在时也不会挤压右侧原生控件。
    private func settingRow<Control: View>(
        icon: String,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 19)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                if let subtitle {
                    Text(subtitle)
                        .font(AppTheme.captionFont)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)
            control()
        }
        .padding(.horizontal, 13)
        .frame(minHeight: subtitle == nil ? 52 : 58)
    }

    /// 分隔线从文字列起始，保持图标列的连续性。
    private var settingDivider: some View {
        Divider()
            .padding(.leading, 44)
    }

    /// 保存后的重启操作让刷新频率和时区在关闭面板后立即生效。
    private func saveAndDismiss() {
        appState.restartPolling()
        // 设置现在是独立窗口，显式关闭当前关键窗口可兼容生产 Settings 场景和 QA 普通窗口。
        if let settingsWindow = NSApplication.shared.keyWindow {
            settingsWindow.performClose(nil)
        } else {
            dismiss()
        }
    }

    /// 提供常用时区并保留 Mac 当前时区，去重排序后便于快速查找。
    private var timeZoneOptions: [String] {
        Array(Set([
            TimeZone.current.identifier,
            "Asia/Shanghai",
            "UTC",
            "America/Los_Angeles",
            "America/New_York",
            "Europe/London"
        ])).sorted()
    }
}

/// 设置分组使用单层轻描边容器，避免系统分组表单产生多重背景和大圆角卡片。
private struct SettingsGroupStyle: ViewModifier {
    /// 为所有设置分组应用一致的背景、边框和圆角。
    func body(content: Content) -> some View {
        content
            .background(AppTheme.contentCanvas, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .stroke(AppTheme.border, lineWidth: 0.75)
            }
    }
}
