/**
 * 文件说明：CodexTools 主操作窗口，承载完整用量、消耗分析和重置记录工作区
 * 作者：dingyi60(Codex)
 * 创建时间：2026-08-25
 */

import AppKit
import SwiftUI

/// 定义主窗口侧栏的稳定页面集合，避免用字符串分支导致导航状态失效。
private enum MainWindowSection: String, CaseIterable, Identifiable {
    case overview
    case usage
    case analysis
    case resets

    var id: String { rawValue }

    /// 提供面向用户的简短中文页面名称。
    var title: String {
        switch self {
        case .overview: return "概览"
        case .usage: return "用量"
        case .analysis: return "消耗分析"
        case .resets: return "重置记录"
        }
    }

    /// 每个页面使用语义对应的 SF Symbols（苹果系统图标库）图标。
    var systemImage: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .usage: return "chart.xyaxis.line"
        case .analysis: return "waveform.path.ecg"
        case .resets: return "clock.arrow.circlepath"
        }
    }
}

/// 根据登录状态显示完整工作区或居中的登录面板，主窗口与菜单栏共享同一个 AppState。
struct MainWindowRootView: View {
    @EnvironmentObject private var appState: AppState

    /// 未登录时让表单保持合适宽度，登录后切换到可调整尺寸的导航工作区。
    var body: some View {
        Group {
            if appState.session == nil {
                ZStack {
                    AppTheme.canvas
                    LoginView()
                        .frame(width: 380)
                        .glassSurface(radius: 12, addsShadow: true)
                }
                .frame(minWidth: AppTheme.mainWindowMinimumSize.width, minHeight: AppTheme.mainWindowMinimumSize.height)
            } else {
                MainWindowView()
            }
        }
    }
}

/// 使用原生分栏结构组织完整数据视图，菜单栏面板仍负责快速查看。
struct MainWindowView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openSettings) private var openSettings
    @AppStorage(PreferenceKey.displayTimeZone) private var displayTimeZone = TimeZone.current.identifier
    @AppStorage(PreferenceKey.consumptionAnalysisEnabled) private var consumptionAnalysisEnabled = true
    @State private var selection: MainWindowSection = .overview
    @State private var showsBalanceActivities = false

    /// 左侧使用可控的系统玻璃材质，避免离屏渲染和不同系统版本出现侧栏底色漂移。
    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 204)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.canvas)
        }
        .frame(
            minWidth: AppTheme.mainWindowMinimumSize.width,
            minHeight: AppTheme.mainWindowMinimumSize.height
        )
    }

    /// 侧栏把高频数据页面和低频设置入口分开，底部固定显示连接状态。
    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 34, height: 34)
                    .background(AppTheme.accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 8))

                Text("CodexTools")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 12)

            VStack(spacing: 4) {
                ForEach(MainWindowSection.allCases) { section in
                    Button {
                        withAnimation(.easeOut(duration: 0.14)) {
                            selection = section
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: section.systemImage)
                                .font(.system(size: 14))
                                .frame(width: 19)
                            Text(section.title)
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                        }
                        .foregroundStyle(selection == section ? AppTheme.accent : Color.primary)
                        .padding(.horizontal, 12)
                        .frame(height: 38)
                        .background(
                            selection == section ? AppTheme.accent.opacity(0.12) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            VStack(spacing: 10) {
                Button {
                    openSettingsWindow()
                } label: {
                    Label("设置", systemImage: "gearshape")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))

                Divider()

                HStack(spacing: 8) {
                    Circle()
                        .fill(sidebarStatusColor)
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(sidebarStatusTitle)
                            .font(.system(size: 11, weight: .medium))
                        Text("Sub2API")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .padding(16)
        }
        .background(.ultraThinMaterial)
    }

    /// 根据同步状态选择数据页、加载页或可恢复的错误页。
    @ViewBuilder
    private var detail: some View {
        if let snapshot = appState.snapshot {
            VStack(spacing: 0) {
                pageHeader(snapshot)
                Divider()
                ScrollView {
                    selectedContent(snapshot)
                        .padding(24)
                }
            }
        } else if appState.isLoading {
            ProgressView("正在同步用量")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView {
                Label("尚未同步到用量", systemImage: "wifi.exclamationmark")
            } description: {
                Text(appState.errorMessage ?? "请检查网络或登录状态")
            } actions: {
                Button("重新同步") {
                    Task { await appState.refresh() }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
            }
        }
    }

    /// 顶部工具区集中页面标题、统计周期与刷新动作，减少内容区重复控件。
    private func pageHeader(_ snapshot: DashboardSnapshot) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(selection.title)
                    .font(.system(size: 20, weight: .semibold))
                Text(pageSubtitle(snapshot))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if selection == .overview || selection == .usage {
                periodSelector
                    .frame(width: 210)
            }

            Text("更新 \(formattedTime(snapshot.refreshedAt))")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button {
                Task { await appState.refresh() }
            } label: {
                if appState.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(ToolbarIconButtonStyle())
            .help("刷新数据")
            .disabled(appState.isLoading)
        }
        .padding(.horizontal, 24)
        .frame(height: 72)
        .background(.ultraThinMaterial)
    }

    /// 不同页面使用同一个数据快照，但提供针对任务的内容密度和重点。
    @ViewBuilder
    private func selectedContent(_ snapshot: DashboardSnapshot) -> some View {
        switch selection {
        case .overview:
            overviewContent(snapshot)
        case .usage:
            usageContent(snapshot)
        case .analysis:
            analysisContent
        case .resets:
            resetContent(snapshot)
        }
    }

    /// 概览将账户、核心指标和两个状态面板组织成从上到下的扫描路径。
    private func overviewContent(_ snapshot: DashboardSnapshot) -> some View {
        VStack(spacing: 18) {
            accountSummary(snapshot)
            metricStrip(snapshot)

            HStack(alignment: .top, spacing: 18) {
                if consumptionAnalysisEnabled {
                    compactAnalysisPanel
                        .frame(maxWidth: .infinity)
                }
                compactResetPanel(snapshot)
                    .frame(maxWidth: consumptionAnalysisEnabled ? 310 : .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    /// 用量页突出当前统计口径、四项聚合指标和模型来源，不虚构缺失的趋势数据。
    private func usageContent(_ snapshot: DashboardSnapshot) -> some View {
        VStack(spacing: 18) {
            metricStrip(snapshot)

            VStack(spacing: 0) {
                detailRow(
                    icon: "calendar",
                    title: "统计周期",
                    value: snapshot.usagePeriod.metricTitle,
                    detail: "按 \(selectedTimeZone.identifier) 计算"
                )
                Divider().padding(.leading, 44)
                detailRow(
                    icon: "cpu",
                    title: "最近使用模型",
                    value: snapshot.recentModel ?? "暂无模型记录",
                    detail: "来自 Sub2API 模型统计"
                )
                Divider().padding(.leading, 44)
                detailRow(
                    icon: "checkmark.circle",
                    title: "数据连接",
                    value: sidebarStatusTitle,
                    detail: "Sub2API"
                )
            }
            .panelSurface(padding: 0)

            accountSummary(snapshot)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    /// 消耗分析页展示计算口径、金额对比和两侧调用数量，并提供立即重新分析动作。
    private var analysisContent: some View {
        VStack(spacing: 18) {
            if !consumptionAnalysisEnabled {
                ContentUnavailableView {
                    Label("消耗分析已关闭", systemImage: "waveform.path.ecg")
                } description: {
                    Text("可在应用设置中重新开启每小时分析")
                } actions: {
                    Button("打开设置", action: openSettingsWindow)
                }
                .frame(maxWidth: .infinity, minHeight: 360)
                .panelSurface()
            } else if let analysis = appState.consumptionAnalysis {
                detailedAnalysisPanel(analysis)
            } else {
                ContentUnavailableView {
                    Label("等待首次分析", systemImage: "waveform.path.ecg")
                } description: {
                    Text(appState.consumptionAnalysisErrorMessage ?? "分析范围为滚动的最近 1 小时")
                } actions: {
                    Button("立即分析") {
                        Task { await appState.analyzeConsumption(force: true) }
                    }
                    .disabled(appState.isAnalyzingConsumption)
                }
                .frame(maxWidth: .infinity, minHeight: 360)
                .panelSurface()
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    /// 重置记录页明确区分账户订阅周期和社区全局重置，并始终显示所选时区。
    private func resetContent(_ snapshot: DashboardSnapshot) -> some View {
        VStack(spacing: 18) {
            VStack(spacing: 0) {
                detailRow(
                    icon: "calendar",
                    title: "订阅周期重置",
                    value: snapshot.resetAt ?? "暂无数据",
                    detail: utcOffsetDescription
                )
                Divider().padding(.leading, 44)
                Button(action: appState.openResetSource) {
                    detailRow(
                        icon: "clock.arrow.circlepath",
                        title: "上次全局重置",
                        value: formattedDate(snapshot.lastGlobalResetAt),
                        detail: "社区同步 · \(timeZoneDescription)",
                        accessory: snapshot.resetSourceURL == nil ? nil : "arrow.up.right"
                    )
                }
                .buttonStyle(.plain)
                .disabled(snapshot.resetSourceURL == nil)
            }
            .panelSurface(padding: 0)

            HStack(spacing: 10) {
                Image(systemName: "info.circle")
                    .foregroundStyle(AppTheme.accent)
                Text("社区全局重置来自 codex-resets.com，不代表个人账户的实际账单重置时间。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(14)
            .glassSurface()
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    /// 余额与额度共用一个横向容器，让主窗口第一视觉焦点保持稳定。
    private func accountSummary(_ snapshot: DashboardSnapshot) -> some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 7) {
                Text("可用余额")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Button {
                    presentBalanceActivities()
                } label: {
                    HStack(spacing: 6) {
                        Text(currency(snapshot.balance))
                            .font(.system(size: 32, weight: .semibold, design: .rounded))
                            .foregroundStyle(balanceColor(snapshot.balance))
                            .monospacedDigit()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help("查看余额最近活动")
                .accessibilityLabel("可用余额 \(currency(snapshot.balance))，查看最近活动")
                .popover(isPresented: $showsBalanceActivities, arrowEdge: .trailing) {
                    BalanceActivityView(balance: snapshot.balance)
                        .environmentObject(appState)
                }
                HStack(spacing: 14) {
                    Label(balanceState(snapshot.balance), systemImage: balanceStateIcon(snapshot.balance))
                        .foregroundStyle(balanceColor(snapshot.balance))
                    Label(
                        "并发上限 \(UsageFormatter.concurrencyLimit(snapshot.concurrencyLimit))",
                        systemImage: "rectangle.3.group"
                    )
                    .foregroundStyle(.secondary)
                }
                .font(.system(size: 11, weight: .medium))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider().frame(height: 92)

            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("订阅额度")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(percent(snapshot.quotaProgress))
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                }
                Text("已用 \(currency(snapshot.quotaUsed)) / \(currency(snapshot.quotaTotal))")
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                quotaProgressBar(snapshot.quotaProgress)
                HStack {
                    Text("剩余额度")
                    Spacer()
                    Text(currency(snapshot.quotaRemaining))
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .panelSurface(padding: 20)
    }

    /// 打开余额活动弹窗，并立即从 Sub2API 请求最近的余额变动记录。
    private func presentBalanceActivities() {
        showsBalanceActivities = true
        Task { await appState.loadBalanceActivities(force: true) }
    }

    /// 四项指标放在同一容器中通过分隔线组织，避免形成重复卡片网格。
    private func metricStrip(_ snapshot: DashboardSnapshot) -> some View {
        HStack(spacing: 0) {
            mainMetric(
                icon: "textformat.123",
                title: "Token",
                value: UsageFormatter.compactTokens(snapshot.periodTokens),
                detail: snapshot.usagePeriod.metricTitle
            )
            metricDivider
            mainMetric(
                icon: "arrow.up.arrow.down",
                title: "请求",
                value: UsageFormatter.requestCount(snapshot.requestCount),
                detail: "模型调用记录"
            )
            metricDivider
            mainMetric(
                icon: "dollarsign",
                title: "消费",
                value: UsageFormatter.cost(snapshot.usageCost),
                detail: "中转实际扣费"
            )
            metricDivider
            mainMetric(
                icon: "timer",
                title: "平均响应",
                value: UsageFormatter.duration(milliseconds: snapshot.averageResponseMilliseconds),
                detail: "服务端记录"
            )
        }
        .panelSurface(padding: 0)
    }

    /// 单个主指标固定布局，长数值缩放而不会推动相邻列变化。
    private func mainMetric(icon: String, title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: icon)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
    }

    /// 指标列之间使用短分隔线，容器边界保持连续。
    private var metricDivider: some View {
        Divider().frame(height: 76)
    }

    /// 概览中的消耗分析只保留结论、倍率和三项核对信息，详细解释放在独立页面。
    private var compactAnalysisPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("最近 1 小时消耗分析", systemImage: "waveform.path.ecg")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if let analysis = appState.consumptionAnalysis {
                    Text(analysisStatusTitle(analysis.status))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(analysisColor(analysis.status))
                }
                Button {
                    Task { await appState.analyzeConsumption(force: true) }
                } label: {
                    if appState.isAnalyzingConsumption {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.plain)
                .help("立即分析最近 1 小时")
                .disabled(appState.isAnalyzingConsumption)
            }

            if let analysis = appState.consumptionAnalysis {
                HStack(alignment: .firstTextBaseline) {
                    Text(multiplierText(analysis.effectiveMultiplier))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("综合倍率")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                Text(analysis.message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 0) {
                    analysisMetric("中转实扣", UsageFormatter.cost(analysis.actualCost))
                    metricDivider
                    analysisMetric("本地估算", UsageFormatter.cost(analysis.standardCost))
                    metricDivider
                    analysisMetric("调用对比", "\(analysis.requestCount) / \(analysis.billedRequestCount ?? 0)")
                }
            } else {
                Text(appState.consumptionAnalysisErrorMessage ?? "等待首次分析最近 1 小时调用")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            }
        }
        .panelSurface()
    }

    /// 分析摘要子项保持相同宽度和数字基线，便于横向核对。
    private func analysisMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 概览重置面板在有限宽度内保留两个关键时间和时区。
    private func compactResetPanel(_ snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("重置时间", systemImage: "clock.arrow.circlepath")
                .font(.system(size: 13, weight: .semibold))
                .padding(.bottom, 10)

            compactResetRow("订阅周期", snapshot.resetAt ?? "暂无数据")
            Divider().padding(.vertical, 10)
            compactResetRow("上次全局重置", formattedDate(snapshot.lastGlobalResetAt))

            Spacer(minLength: 12)
            Text(timeZoneDescription)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(minHeight: 184, alignment: .top)
        .panelSurface()
    }

    /// 重置摘要行使用上标签下数值，窄栏中不会挤压时间文本。
    private func compactResetRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

    /// 详细分析用真实成本比例绘制对比条，不补造任何时间序列数据。
    private func detailedAnalysisPanel(_ analysis: ConsumptionAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("综合倍率")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text(multiplierText(analysis.effectiveMultiplier))
                        .font(.system(size: 42, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(analysis.message)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(analysisColor(analysis.status))
                }
                Spacer()
                Button {
                    Task { await appState.analyzeConsumption(force: true) }
                } label: {
                    Label(appState.isAnalyzingConsumption ? "正在分析" : "立即分析", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(appState.isAnalyzingConsumption)
            }

            Divider()

            costComparison(
                title: "中转实际扣费",
                value: analysis.actualCost,
                maximum: max(analysis.actualCost, analysis.standardCost),
                color: AppTheme.accent
            )
            costComparison(
                title: "本地标准成本",
                value: analysis.standardCost,
                maximum: max(analysis.actualCost, analysis.standardCost),
                color: .secondary
            )

            Divider()

            HStack(spacing: 0) {
                analysisMetric("本地调用", "\(analysis.requestCount) 次")
                metricDivider
                analysisMetric("中转账单", "\(analysis.billedRequestCount ?? 0) 条")
                metricDivider
                analysisMetric("Token", UsageFormatter.compactTokens(analysis.totalTokens))
                metricDivider
                analysisMetric("平均响应", UsageFormatter.duration(milliseconds: analysis.averageResponseMilliseconds))
            }

            Text("分析窗口 \(formattedDateTime(analysis.windowStart)) – \(formattedDateTime(analysis.windowEnd)) · \(timeZoneDescription)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .panelSurface(padding: 22)
    }

    /// 成本对比条以两者较大值作为统一上限，直观表达真实扣费和标准成本的比例。
    private func costComparison(title: String, value: Double, maximum: Double, color: Color) -> some View {
        VStack(spacing: 7) {
            HStack {
                Text(title)
                    .font(.system(size: 12))
                Spacer()
                Text(UsageFormatter.cost(value))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            GeometryReader { geometry in
                let ratio = maximum > 0 ? min(max(value / maximum, 0), 1) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.12))
                    Capsule().fill(color).frame(width: geometry.size.width * ratio)
                }
            }
            .frame(height: 7)
        }
    }

    /// 通用详情行固定图标和右侧值列，长时间或模型名称会安全缩放。
    private func detailRow(
        icon: String,
        title: String,
        value: String,
        detail: String,
        accessory: String? = nil
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if let accessory {
                Image(systemName: accessory)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 66)
    }

    /// 原生分段控件保持三个周期与菜单栏当前快照同步。
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
    }

    /// 根据页面内容生成一行辅助说明，不增加无关产品文案。
    private func pageSubtitle(_ snapshot: DashboardSnapshot) -> String {
        switch selection {
        case .overview: return "\(snapshot.recentModel ?? "暂无模型记录") · \(sidebarStatusTitle)"
        case .usage: return "\(snapshot.usagePeriod.metricTitle)聚合数据"
        case .analysis: return "滚动统计最近 1 小时"
        case .resets: return timeZoneDescription
        }
    }

    /// 打开独立设置窗口并激活应用，侧栏按钮不会改变当前数据页面。
    private func openSettingsWindow() {
        openSettings()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    /// 同步状态在加载、错误和正常三种情况下使用明确文字。
    private var sidebarStatusTitle: String {
        if appState.isLoading { return "正在同步" }
        if appState.errorMessage != nil { return "同步失败" }
        return "已连接"
    }

    /// 连接状态只在错误时使用警示色，其余延续品牌强调色。
    private var sidebarStatusColor: Color {
        appState.errorMessage == nil ? AppTheme.accent : AppTheme.warning
    }

    /// 使用稳定高度的进度条，并标记用户设置的剩余额度阈值。
    private func quotaProgressBar(_ progress: Double?) -> some View {
        GeometryReader { geometry in
            let normalized = min(max(progress ?? 0, 0), 1)
            let remainingThreshold = UserDefaults.standard.double(forKey: PreferenceKey.quotaThreshold) / 100
            let thresholdPosition = min(max(1 - remainingThreshold, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.13))
                Capsule().fill(AppTheme.accent).frame(width: geometry.size.width * normalized)
                Rectangle()
                    .fill(AppTheme.warning)
                    .frame(width: 1.5, height: 12)
                    .offset(x: max(geometry.size.width * thresholdPosition - 1, 0))
            }
        }
        .frame(height: 7)
    }

    /// 空金额使用长横线，避免把数据缺失误认为零美元。
    private func currency(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "$" + value.formatted(.number.precision(.fractionLength(2)))
    }

    /// 余额状态遵守用户配置的预警阈值。
    private func balanceState(_ value: Double?) -> String {
        guard let value else { return "暂无数据" }
        return value <= UserDefaults.standard.double(forKey: PreferenceKey.balanceThreshold)
            ? "余额偏低"
            : "余额正常"
    }

    /// 余额图标与正常、警示和未知三种状态一一对应。
    private func balanceStateIcon(_ value: Double?) -> String {
        guard let value else { return "questionmark.circle" }
        return value <= UserDefaults.standard.double(forKey: PreferenceKey.balanceThreshold)
            ? "exclamationmark.circle.fill"
            : "checkmark.circle.fill"
    }

    /// 余额颜色只在低于阈值时切换到橙色，避免页面出现过多语义颜色。
    private func balanceColor(_ value: Double?) -> Color {
        guard let value else { return .secondary }
        return value <= UserDefaults.standard.double(forKey: PreferenceKey.balanceThreshold)
            ? AppTheme.warning
            : AppTheme.accent
    }

    /// 将额度比例格式化为整数百分比。
    private func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.percent.precision(.fractionLength(0)))
    }

    /// 综合倍率保留两位小数，缺少标准成本时明确显示未知。
    private func multiplierText(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return value.formatted(.number.precision(.fractionLength(2))) + "×"
    }

    /// 把分析状态映射成简短中文结论。
    private func analysisStatusTitle(_ status: ConsumptionAnalysisStatus) -> String {
        switch status {
        case .normal: return "正常"
        case .attention: return "需关注"
        case .noUsage: return "暂无调用"
        case .insufficientData: return "数据不足"
        }
    }

    /// 分析结论正常时使用强调色，需要关注时使用警示色。
    private func analysisColor(_ status: ConsumptionAnalysisStatus) -> Color {
        switch status {
        case .normal: return AppTheme.accent
        case .attention: return AppTheme.warning
        case .noUsage, .insufficientData: return .secondary
        }
    }

    /// 主窗口顶部更新时间只显示时分，并遵守用户选择的时区。
    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = selectedTimeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    /// 重置时间使用完整日期和分钟，避免跨日时产生歧义。
    private func formattedDate(_ date: Date?) -> String {
        guard let date else { return "暂未同步" }
        return formattedDateTime(date)
    }

    /// 分析窗口和重置记录共用统一的完整日期格式。
    private func formattedDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = selectedTimeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    /// 无效时区偏好回退到系统时区，保证所有时间仍可显示。
    private var selectedTimeZone: TimeZone {
        TimeZone(identifier: displayTimeZone) ?? .current
    }

    /// 同时显示 IANA（互联网号码分配机构）时区名称和 UTC 偏移。
    private var timeZoneDescription: String {
        "\(selectedTimeZone.identifier) · \(utcOffsetDescription)"
    }

    /// 生成当前时区包含正负号的固定宽度 UTC 偏移。
    private var utcOffsetDescription: String {
        let seconds = selectedTimeZone.secondsFromGMT(for: Date())
        let sign = seconds >= 0 ? "+" : "-"
        let absolute = abs(seconds)
        return "UTC\(sign)\(String(format: "%02d:%02d", absolute / 3600, (absolute % 3600) / 60))"
    }
}
