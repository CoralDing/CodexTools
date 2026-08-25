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

    /// 通过标题栏、主内容和状态底栏形成稳定的三段式信息结构。
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let snapshot = appState.snapshot {
                content(snapshot)
            } else if appState.isLoading {
                loadingState
            } else {
                emptyState
            }

            Divider()
            footer
        }
        .frame(minHeight: 680)
        .background(.ultraThinMaterial)
    }

    /// 标题栏保留产品名、主窗口和刷新命令，完整操作从菜单面板自然过渡到主窗口。
    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                Text("CodexTools")
                    .font(.system(size: 17, weight: .semibold))
            }
            Spacer()

            Button {
                openMainWindow()
            } label: {
                Image(systemName: "macwindow")
            }
            .buttonStyle(ToolbarIconButtonStyle())
            .help("打开主窗口")

            Button {
                Task { await appState.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(ToolbarIconButtonStyle())
            .help("刷新数据")
            .disabled(appState.isLoading)

            Button {
                // 独立设置窗口不会依赖菜单栏悬浮层的生命周期，控件交互时可持续保持打开。
                openSettings()
                NSApplication.shared.activate(ignoringOtherApps: true)
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(ToolbarIconButtonStyle())
            .help("打开应用设置")
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
        .background(.ultraThinMaterial)
    }

    /// 主内容按连接、周期、账户、运营指标和重置时间排列，支持从上到下快速扫描。
    private func content(_ snapshot: DashboardSnapshot) -> some View {
        VStack(spacing: 12) {
            modelStatus(snapshot)
            periodSelector
            accountOverview(snapshot)
            usageMetrics(snapshot)
            if consumptionAnalysisEnabled {
                consumptionAnalysisPanel
            }
            resetList(snapshot)
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
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
        .controlSize(.small)
        .accessibilityLabel("统计周期")
    }

    /// 最近模型与连接状态使用单行状态轨道，便于用户快速确认数据来源是否正常。
    private func modelStatus(_ snapshot: DashboardSnapshot) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "cpu")
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text("最近使用模型")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(snapshot.recentModel ?? "暂无模型记录")
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Circle()
                    .fill(AppTheme.accent)
                    .frame(width: 7, height: 7)
                Text("已连接")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .glassSurface()
    }

    /// 余额与订阅额度并排展示，构成面板唯一的强视觉焦点。
    private func accountOverview(_ snapshot: DashboardSnapshot) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("账户余额")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(currency(snapshot.balance))
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(balanceColor(snapshot.balance))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Label(balanceState(snapshot.balance), systemImage: balanceStateIcon(snapshot.balance))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(balanceColor(snapshot.balance))
            }
            .frame(width: 118, alignment: .leading)

            Divider()
                .frame(height: 88)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text("订阅额度")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(percent(snapshot.quotaProgress))
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                }

                Text(currency(snapshot.quotaTotal))
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .monospacedDigit()

                quotaProgressBar(snapshot.quotaProgress)

                HStack {
                    Text("已用 \(currency(snapshot.quotaUsed))")
                    Spacer()
                    Text("剩余 \(currency(snapshot.quotaRemaining))")
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(AppTheme.contentCanvas, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }

    /// 四项关键运营指标使用单层 2×2 网格，减少重复容器并提高横向比较效率。
    private func usageMetrics(_ snapshot: DashboardSnapshot) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                usageMetric(
                    icon: "textformat.123",
                    title: "\(snapshot.usagePeriod.metricTitle) Token",
                    value: UsageFormatter.compactTokens(snapshot.periodTokens)
                )
                Divider().frame(height: 57)
                usageMetric(
                    icon: "arrow.up.arrow.down",
                    title: "\(snapshot.usagePeriod.metricTitle)请求",
                    value: UsageFormatter.requestCount(snapshot.requestCount)
                )
            }

            Divider()

            HStack(spacing: 0) {
                usageMetric(
                    icon: "dollarsign",
                    title: "\(snapshot.usagePeriod.metricTitle)消费",
                    value: UsageFormatter.cost(snapshot.usageCost)
                )
                Divider().frame(height: 57)
                usageMetric(
                    icon: "timer",
                    title: "平均响应",
                    value: UsageFormatter.duration(milliseconds: snapshot.averageResponseMilliseconds)
                )
            }
        }
        .background(AppTheme.contentCanvas, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }

    /// 单个运营指标固定最小高度和等分宽度，数据变化不会推动相邻指标位移。
    private func usageMetric(icon: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 67, alignment: .leading)
    }

    /// 每小时分析面板明确区分本地标准成本与中转实扣，并允许用户手动复查。
    private var consumptionAnalysisPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(analysisColor)

                Text("消耗分析")
                    .font(.system(size: 12, weight: .semibold))

                if let analysis = appState.consumptionAnalysis {
                    Text(analysisStatusTitle(analysis.status))
                        .font(.system(size: 10, weight: .medium))
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
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                HStack(spacing: 6) {
                    Text("中转实扣 \(UsageFormatter.cost(analysis.actualCost))")
                    Text("/ 本地估算 \(UsageFormatter.cost(analysis.standardCost))")
                }
                .font(.system(size: 9))
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
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            } else {
                Text(appState.consumptionAnalysisErrorMessage ?? "等待首次分析最近 1 小时调用")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 86)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .stroke(AppTheme.border, lineWidth: 1)
        }
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
        .background(AppTheme.contentCanvas, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .stroke(AppTheme.border, lineWidth: 1)
        }
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
                .font(.system(size: 12))

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                if let detail {
                    Text(detail)
                        .font(.system(size: 9))
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

    /// 底栏同时反馈同步结果、更新时间和低频账户菜单。
    private var footer: some View {
        HStack(spacing: 8) {
            Label(footerStatusText, systemImage: footerStatusIcon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(footerStatusColor)
                .help(appState.errorMessage ?? footerStatusText)

            Spacer()

            if let refreshedAt = appState.snapshot?.refreshedAt {
                Text("更新 \(formattedTime(refreshedAt))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Menu {
                Button("退出登录", role: .destructive, action: appState.logout)
                Divider()
                Button("退出 CodexTools") {
                    NSApplication.shared.terminate(nil)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 20, height: 20)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 24)
            .help("更多操作")
        }
        .padding(.horizontal, AppTheme.contentPadding)
        .frame(height: 43)
        .background(.ultraThinMaterial)
    }

    /// 打开主操作窗口并激活应用，菜单栏面板仍保留为快速查看入口。
    private func openMainWindow() {
        openWindow(id: "main")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    /// 将同步错误压缩到底栏状态，保留上次数据时不改变主体高度。
    private var footerStatusText: String {
        if appState.isLoading { return "正在同步" }
        if appState.errorMessage != nil { return "同步失败" }
        return "已连接 Sub2API"
    }

    /// 为加载、失败和成功状态选择语义明确的系统图标。
    private var footerStatusIcon: String {
        if appState.isLoading { return "arrow.triangle.2.circlepath" }
        if appState.errorMessage != nil { return "exclamationmark.triangle.fill" }
        return "checkmark.circle.fill"
    }

    /// 同步失败使用警示色，正常连接使用全局强调色。
    private var footerStatusColor: Color {
        if appState.isLoading { return .secondary }
        if appState.errorMessage != nil { return AppTheme.warning }
        return AppTheme.accent
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
        return value <= threshold ? AppTheme.warning : AppTheme.accent
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
