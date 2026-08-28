/**
 * 文件说明：余额、额度、周期运营指标、每小时消耗分析和重置时间悬浮层
 * 作者：dingyi60(Codex)
 * 创建时间：2026-08-25
 */

import AppKit
import SwiftUI

/// 展示登录后的核心用量状态，并提供刷新、设置和账户操作入口。
struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @AppStorage(PreferenceKey.displayTimeZone) private var displayTimeZone = TimeZone.current.identifier
    @AppStorage(PreferenceKey.consumptionAnalysisEnabled) private var consumptionAnalysisEnabled = true
    @State private var showsBalanceActivities = false

    /// 通过固定标题栏、可滚动数据区和命令底栏形成稳定结构，小屏幕也不会裁掉低频操作。
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let snapshot = appState.snapshot {
                ScrollView {
                    content(snapshot)
                }
                .scrollIndicators(.visible)
            } else if appState.isLoading {
                loadingState
            } else {
                emptyState
            }

            Divider()
            footer
        }
        .frame(height: 680)
        .background(Color.clear)
    }

    /// 标题栏把最近模型和连接状态合并到品牌旁，仅保留高频刷新命令。
    private var header: some View {
        HStack(spacing: 10) {
            SubPilotBrandIcon(size: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text("SubPilot")
                        .font(.system(size: 16, weight: .semibold))
                    AppStatusLabel(title: connectionStatusText, color: connectionStatusColor)
                }
                Text(appState.snapshot?.recentModel ?? "等待模型调用")
                    .font(AppTheme.captionFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let refreshedAt = appState.snapshot?.refreshedAt {
                Text(formattedTime(refreshedAt))
                    .font(AppTheme.captionFont)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Button {
                Task { await appState.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(ToolbarIconButtonStyle())
            .help("刷新数据")
            .disabled(appState.isLoading)
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
    }

    /// 主内容按统计口径、账户额度、关键指标和低频状态排列，取消重复描边卡片。
    private func content(_ snapshot: DashboardSnapshot) -> some View {
        VStack(spacing: 14) {
            periodSelector
            accountOverview(snapshot)
            usageMetrics(snapshot)
            if consumptionAnalysisEnabled {
                consumptionAnalysisPanel
            }
            resetList(snapshot)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    /// 原生分段控件明确当前统计口径，切换后立即刷新面板和菜单栏摘要。
    private var periodSelector: some View {
        Picker(
            "统计周期",
            selection: Binding(
                get: { appState.usagePeriod },
                set: { appState.selectUsagePeriod($0) }
            )
        ) {
            ForEach(UsagePeriod.allCases, id: \.self) { period in
                Text(period.shortTitle).tag(period)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .tint(AppTheme.accent)
        .controlSize(.small)
        .accessibilityLabel("统计周期")
    }

    /// 余额与订阅额度纵向排列，窄浮层中的文字和进度条都能保持完整宽度。
    private func accountOverview(_ snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                presentBalanceActivities()
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("账户余额")
                            .font(AppTheme.captionFont)
                            .foregroundStyle(.secondary)
                        Text(currency(snapshot.balance))
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Label(balanceState(snapshot.balance), systemImage: balanceStateIcon(snapshot.balance))
                            .font(AppTheme.captionFont.weight(.medium))
                            .foregroundStyle(balanceColor(snapshot.balance))
                        Text("查看余额增加记录")
                            .font(AppTheme.captionFont)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .help("查看余额增加记录")
            .accessibilityLabel("账户余额 \(currency(snapshot.balance))，查看余额增加记录")
            .popover(isPresented: $showsBalanceActivities, arrowEdge: .trailing) {
                BalanceActivityView(balance: snapshot.balance)
                    .environmentObject(appState)
            }

            Divider()

            dashboardQuotaSummary(snapshot)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(AppTheme.subtleSurface, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
    }

    /// 菜单栏面板使用两条紧凑额度行，数据口径与主窗口完全一致。
    private func dashboardQuotaSummary(_ snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("\(snapshot.primaryPlatformQuota?.displayName ?? "订阅") 平台额度")
                .font(AppTheme.bodyEmphasizedFont)

            if let quota = snapshot.primaryPlatformQuota,
               quota.weekly != nil || quota.monthly != nil {
                if let weekly = quota.weekly {
                    dashboardQuotaRow("周", weekly)
                }
                if let monthly = quota.monthly {
                    dashboardQuotaRow("月（近 30 天）", monthly)
                }
            } else {
                HStack {
                    Text("已用 \(currency(snapshot.quotaUsed))")
                    Spacer()
                    Text("共 \(currency(snapshot.quotaTotal))")
                }
                .font(AppTheme.captionFont)
                .foregroundStyle(.secondary)
                quotaProgressBar(snapshot.quotaProgress)
            }
        }
    }

    /// 窄面板额度行将金额和进度放在同一视觉组，重置时间单独占一行避免拥挤。
    private func dashboardQuotaRow(_ title: String, _ window: PlatformQuotaWindow) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                    .font(AppTheme.captionFont.weight(.medium))
                Spacer()
                Text("\(UsageFormatter.cost(window.used)) / \(UsageFormatter.cost(window.limit))")
                    .font(AppTheme.captionFont.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            ProgressView(value: window.progress ?? 0)
                .tint((window.progress ?? 0) >= 0.9 ? AppTheme.warning : AppTheme.accent)
                .controlSize(.mini)
            Text("\(formattedQuotaReset(window.resetsAt)) · \(selectedTimeZone.identifier)")
                .font(AppTheme.captionFont)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
    }

    /// 将服务端额度重置时间转换成设置中选择的时区。
    private func formattedQuotaReset(_ value: String?) -> String {
        guard let value else { return "暂未提供重置时间" }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        guard let date = fractional.date(from: value) ?? standard.date(from: value) else {
            return value
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = selectedTimeZone
        formatter.dateFormat = "M/d HH:mm 重置"
        return formatter.string(from: date)
    }

    /// 打开余额增加弹窗，并读取最新的 Sub2API 充值、兑换和人工加款记录。
    private func presentBalanceActivities() {
        showsBalanceActivities = true
        Task { await appState.loadBalanceActivities(force: true) }
    }

    /// 两项主指标与三项辅助指标共用一个连续表面，窄浮层中优先保证数字可读。
    private func usageMetrics(_ snapshot: DashboardSnapshot) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                usageMetric(
                    icon: "textformat.123",
                    title: "\(snapshot.usagePeriod.metricTitle) Token",
                    value: UsageFormatter.compactTokens(snapshot.periodTokens)
                )
                Divider().frame(height: 48)
                usageMetric(
                    icon: "dollarsign",
                    title: "\(snapshot.usagePeriod.metricTitle)消费",
                    value: UsageFormatter.cost(snapshot.usageCost)
                )
            }

            Divider()

            HStack(spacing: 0) {
                compactUsageMetric(
                    title: "请求",
                    value: UsageFormatter.requestCount(snapshot.requestCount)
                )
                Divider().frame(height: 36)
                compactUsageMetric(
                    title: "平均响应",
                    value: UsageFormatter.duration(milliseconds: snapshot.averageResponseMilliseconds)
                )
                Divider().frame(height: 36)
                compactUsageMetric(
                    title: "并发上限",
                    value: UsageFormatter.concurrencyLimit(snapshot.concurrencyLimit)
                )
            }
        }
        .panelSurface(padding: 0)
    }

    /// 单个运营指标固定最小高度和等分宽度，数据变化不会推动相邻指标位移。
    private func usageMetric(icon: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(AppTheme.captionFont)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(value)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    }

    /// 辅助指标用三列紧凑布局，减少菜单浮层纵向滚动且保留完整文字语义。
    private func compactUsageMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AppTheme.captionFont)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
    }

    /// 每小时分析面板明确区分本地标准成本与中转实扣，并允许用户手动复查。
    private var consumptionAnalysisPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(analysisColor)

                Text("消耗分析")
                    .font(AppTheme.sectionTitleFont)

                if let analysis = appState.consumptionAnalysis {
                    Text(analysisStatusTitle(analysis.status))
                        .font(AppTheme.captionFont.weight(.medium))
                        .foregroundStyle(analysisColor)
                }

                Spacer()

                Text(multiplierText(appState.consumptionAnalysis?.effectiveMultiplier))
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .monospacedDigit()

                Button {
                    Task { await appState.analyzeConsumption(force: true) }
                } label: {
                    if appState.isAnalyzingConsumption {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.plain)
                .frame(width: 22, height: 22)
                .help("立即分析最近 1 小时")
                .disabled(appState.isAnalyzingConsumption)
            }

            if let analysis = appState.consumptionAnalysis {
                Text(analysis.message)
                    .font(AppTheme.captionFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                HStack(spacing: 6) {
                    Text("中转实扣 \(UsageFormatter.cost(analysis.actualCost))")
                    Text("/ 本地估算 \(UsageFormatter.cost(analysis.standardCost))")
                }
                .font(AppTheme.captionFont)
                .foregroundStyle(.secondary)
                .monospacedDigit()

                HStack(spacing: 6) {
                    Text("本地 \(analysis.requestCount.formatted()) 次")
                    if let billedRequestCount = analysis.billedRequestCount {
                        Text("/ 账单 \(billedRequestCount.formatted()) 条")
                    }
                    Spacer()
                    Text(formattedTime(analysis.analyzedAt))
                }
                .font(AppTheme.captionFont)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            } else {
                Text(appState.consumptionAnalysisErrorMessage ?? "等待首次分析最近 1 小时调用")
                    .font(AppTheme.captionFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 86)
        .background(AppTheme.subtleSurface, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
    }

    /// 根据分析结论选择颜色；正常使用强调色，需关注使用警示色，其余保持次级层级。
    private var analysisColor: Color {
        switch appState.consumptionAnalysis?.status {
        case .normal: return AppTheme.accent
        case .attention: return AppTheme.warning
        case .noUsage, .insufficientData, nil: return .secondary
        }
    }

    /// 将内部状态转换成简短中文结论，避免在紧凑面板中展示技术枚举值。
    private func analysisStatusTitle(_ status: ConsumptionAnalysisStatus) -> String {
        switch status {
        case .normal: return "正常"
        case .attention: return "需关注"
        case .noUsage: return "暂无调用"
        case .insufficientData: return "数据不足"
        }
    }

    /// 综合倍率固定保留两位，缺少标准成本时显示未知而不是错误的 0 倍。
    private func multiplierText(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return value.formatted(.number.precision(.fractionLength(2))) + "×"
    }

    /// 低频重置时间保持为两行描边列表，与高频运营指标形成清晰的信息层级。
    private func resetList(_ snapshot: DashboardSnapshot) -> some View {
        VStack(spacing: 0) {
            metricRow(
                icon: "calendar",
                title: "订阅周期重置",
                value: snapshot.resetAt ?? "暂无数据",
                detail: utcOffsetDescription
            )

            rowDivider

            Button(action: appState.openResetSource) {
                metricRow(
                    icon: "clock.arrow.circlepath",
                    title: "上次全局重置",
                    value: formattedDate(snapshot.lastGlobalResetAt),
                    detail: "社区同步 · \(timeZoneDescription)",
                    accessory: snapshot.resetSourceURL == nil ? nil : "arrow.up.right"
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(snapshot.resetSourceURL == nil ? "暂未同步来源" : "打开社区公告来源")
        }
        .panelSurface(padding: 0)
    }

    /// 指标行使用固定图标列和右对齐数值，保证长短内容都容易扫描。
    private func metricRow(
        icon: String,
        title: String,
        value: String,
        detail: String? = nil,
        accessory: String? = nil
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            Text(title)
                .font(AppTheme.bodyFont)

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .font(AppTheme.bodyEmphasizedFont)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                if let detail {
                    Text(detail)
                        .font(AppTheme.captionFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .frame(maxWidth: 180, alignment: .trailing)

            if let accessory {
                Image(systemName: accessory)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 52)
    }

    /// 列表分隔线从文字列开始，避免连续横线切断图标的垂直节奏。
    private var rowDivider: some View {
        Divider()
            .padding(.leading, 40)
    }

    /// 请求期间保持内容区域尺寸稳定，避免菜单栏面板突然缩放。
    private var loadingState: some View {
        VStack(spacing: 10) {
            ProgressView()
                .tint(AppTheme.accent)
            Text("正在同步用量")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 首次同步失败时显示明确错误和直接恢复动作。
    private var emptyState: some View {
        VStack(spacing: 13) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text(appState.errorMessage ?? "尚未同步到用量数据")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("重新同步") {
                Task { await appState.refresh() }
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 底栏保留三个清晰命令，避免用户在小图标中猜测主窗口、设置和账户操作。
    private var footer: some View {
        HStack(spacing: 0) {
            footerCommand(title: "打开主界面", icon: "macwindow", action: openMainWindow)
            Divider().frame(height: 24)
            footerCommand(title: "设置", icon: "gearshape") {
                // 设置使用独立窗口，激活应用后即使菜单浮层关闭也能继续编辑。
                openSettings()
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            Divider().frame(height: 24)
            Menu {
                Button("退出登录", role: .destructive, action: appState.logout)
                Divider()
                Button("退出 SubPilot") {
                    NSApplication.shared.terminate(nil)
                }
            } label: {
                Label("账户", systemImage: "person.crop.circle")
                    .font(AppTheme.bodyEmphasizedFont)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(maxWidth: .infinity)
            .help("账户与退出操作")
        }
        .padding(.horizontal, 8)
        .frame(height: 50)
    }

    /// 底栏普通命令使用图标加文字并等分宽度，点击区域在菜单栏浮层中保持足够大。
    private func footerCommand(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(AppTheme.bodyEmphasizedFont)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    /// 打开主操作窗口并激活应用，菜单栏面板仍保留为快速查看入口。
    private func openMainWindow() {
        openWindow(id: "main")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    /// 标题状态优先反映本轮同步结果；保留旧快照时也不会把失败误报为已连接。
    private var connectionStatusText: String {
        if appState.isLoading { return "同步中" }
        if appState.errorMessage != nil { return "同步失败" }
        return "已连接"
    }

    /// 同步失败使用警示色，加载中降低视觉权重，正常连接使用系统成功色。
    private var connectionStatusColor: Color {
        if appState.isLoading { return .secondary }
        if appState.errorMessage != nil { return AppTheme.warning }
        return AppTheme.success
    }

    /// 使用稳定高度的进度条，并标出用户设置的剩余额度提醒阈值。
    private func quotaProgressBar(_ progress: Double?) -> some View {
        GeometryReader { geometry in
            let normalized = min(max(progress ?? 0, 0), 1)
            let remainingThreshold = UserDefaults.standard.double(forKey: PreferenceKey.quotaThreshold) / 100
            let thresholdPosition = min(max(1 - remainingThreshold, 0), 1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.14))
                Capsule()
                    .fill(AppTheme.accent)
                    .frame(width: geometry.size.width * normalized)
                Rectangle()
                    .fill(AppTheme.warning)
                    .frame(width: 1.5, height: 11)
                    .offset(x: max(geometry.size.width * thresholdPosition - 1, 0))
            }
        }
        .frame(height: 7)
        .accessibilityElement()
        .accessibilityLabel("订阅额度使用进度")
        .accessibilityValue(percent(progress))
    }

    /// 格式化金额，空值使用长横线表达未知而不是零余额。
    private func currency(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "$" + value.formatted(.number.precision(.fractionLength(2)))
    }

    /// 根据提醒阈值生成余额状态文字。
    private func balanceState(_ value: Double?) -> String {
        guard let value else { return "暂无数据" }
        let threshold = UserDefaults.standard.double(forKey: PreferenceKey.balanceThreshold)
        return value <= threshold ? "余额偏低" : "余额正常"
    }

    /// 余额状态使用熟悉的警告或确认图标。
    private func balanceStateIcon(_ value: Double?) -> String {
        guard let value else { return "questionmark.circle" }
        let threshold = UserDefaults.standard.double(forKey: PreferenceKey.balanceThreshold)
        return value <= threshold ? "exclamationmark.circle.fill" : "checkmark.circle.fill"
    }

    /// 余额低于阈值时使用警示色，其余状态使用品牌强调色。
    private func balanceColor(_ value: Double?) -> Color {
        guard let value else { return .secondary }
        let threshold = UserDefaults.standard.double(forKey: PreferenceKey.balanceThreshold)
        return value <= threshold ? AppTheme.warning : AppTheme.success
    }

    /// 将 0 到 1 的进度格式化为整数百分比。
    private func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.percent.precision(.fractionLength(0)))
    }

    /// 按用户选择时区展示底栏短时间。
    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = selectedTimeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    /// 按用户选择时区展示社区全局重置日期时间。
    private func formattedDate(_ date: Date?) -> String {
        guard let date else { return "暂未同步" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = selectedTimeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    /// 无效时区配置回退到系统当前时区，避免时间格式化失败。
    private var selectedTimeZone: TimeZone {
        TimeZone(identifier: displayTimeZone) ?? .current
    }

    /// 同时显示标准时区名称和 UTC（协调世界时）偏移。
    private var timeZoneDescription: String {
        "\(selectedTimeZone.identifier) · \(utcOffsetDescription)"
    }

    /// 根据所选时区生成固定宽度的 UTC 偏移，夏令时变化也会正确更新。
    private var utcOffsetDescription: String {
        let seconds = selectedTimeZone.secondsFromGMT(for: Date())
        let sign = seconds >= 0 ? "+" : "-"
        let absolute = abs(seconds)
        let hours = absolute / 3600
        let minutes = (absolute % 3600) / 60
        return "UTC\(sign)\(String(format: "%02d:%02d", hours, minutes))"
    }
}
