/**
 * 文件说明：CodexTools 主操作窗口，承载完整用量、消耗分析和重置记录工作区
 * 作者：dingyi60(Codex)
 * 创建时间：2026-08-25
 */

import AppKit
import Charts
import SwiftUI

/// 定义主窗口侧栏的稳定页面集合，避免用字符串分支导致导航状态失效。
enum MainWindowSection: String, CaseIterable, Identifiable {
    case overview
    case apiKeys
    case usage
    case channels
    case subscriptions
    case redeem
    case profile
    case analysis
    case resets

    var id: String { rawValue }

    /// 提供面向用户的简短中文页面名称。
    var title: String {
        switch self {
        case .overview: return "概览"
        case .apiKeys: return "API 密钥"
        case .usage: return "使用记录"
        case .channels: return "渠道状态"
        case .subscriptions: return "我的订阅"
        case .redeem: return "兑换"
        case .profile: return "个人资料"
        case .analysis: return "消耗分析"
        case .resets: return "重置记录"
        }
    }

    /// 每个页面使用语义对应的 SF Symbols（苹果系统图标库）图标。
    var systemImage: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .apiKeys: return "key"
        case .usage: return "chart.xyaxis.line"
        case .channels: return "antenna.radiowaves.left.and.right"
        case .subscriptions: return "creditcard"
        case .redeem: return "gift"
        case .profile: return "person"
        case .analysis: return "waveform.path.ecg"
        case .resets: return "clock.arrow.circlepath"
        }
    }

    /// 日常账户功能保持与 Sub2API 用户端相同顺序，降低从网页迁移的学习成本。
    static let accountSections: [MainWindowSection] = [
        .overview, .apiKeys, .usage, .channels, .subscriptions, .redeem, .profile
    ]

    /// 工具自身能力放在侧栏底部，与服务端账户操作形成清晰边界。
    static let toolSections: [MainWindowSection] = [.analysis, .resets]
}

/// 表示概览平台表的一行真实聚合数据。
private struct OverviewPlatformSummary: Identifiable {
    let platform: String
    let tokens: Double
    let requests: Int
    let cost: Double
    let averageResponse: Double?
    var id: String { platform }
}

/// 表示概览模型图的一项 Token 聚合数据。
private struct OverviewModelSummary: Identifiable {
    let model: String
    let tokens: Double
    var id: String { model }
}

private extension Collection where Element == Double {
    /// 对非空延迟集合计算算术平均值，空集合返回 nil 以避免误显示为 0 毫秒。
    var average: Double? {
        guard !isEmpty else { return nil }
        return reduce(0, +) / Double(count)
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
                    SubPilotWindowBackdrop()
                    LoginView()
                        // 主窗口会向子视图提供全部可用高度；固定登录卡高度，避免内部 Spacer 把按钮推到窗口底部。
                        .frame(width: 380, height: 480)
                        .glassSurface(radius: 14, tint: AppTheme.floatingGlassTint, addsShadow: true)
                }
            } else {
                MainWindowView()
            }
        }
        .frame(minWidth: AppTheme.mainWindowMinimumSize.width, minHeight: AppTheme.mainWindowMinimumSize.height)
        .background(WindowGlassConfigurator())
    }
}

/// 使用原生分栏结构组织完整数据视图，菜单栏面板仍负责快速查看。
struct MainWindowView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openSettings) private var openSettings
    @AppStorage(PreferenceKey.displayTimeZone) private var displayTimeZone = TimeZone.current.identifier
    @AppStorage(PreferenceKey.consumptionAnalysisEnabled) private var consumptionAnalysisEnabled = true
    @State private var selection: MainWindowSection
    @State private var showsBalanceActivities = false

    /// 生产默认打开概览，质量检查可以直接注入其他页面验证完整应用布局。
    init(initialSection: MainWindowSection = .overview) {
        _selection = State(initialValue: initialSection)
    }

    /// 左侧使用可控的系统玻璃材质，避免离屏渲染和不同系统版本出现侧栏底色漂移。
    var body: some View {
        ZStack {
            SubPilotWindowBackdrop()
            HStack(spacing: 0) {
                sidebar
                    .frame(width: AppTheme.sidebarWidth)
                Rectangle()
                    .fill(AppTheme.strongBorder)
                    .frame(width: 0.5)
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(
            minWidth: AppTheme.mainWindowMinimumSize.width,
            minHeight: AppTheme.mainWindowMinimumSize.height
        )
        .onChange(of: selection) { _, _ in
            appState.clearPortalMessage()
        }
        .task(id: selection) {
            // 概览需要最近调用生成平台、模型和趋势；其他用户端页面仍由各自视图按需加载。
            if selection == .overview {
                await appState.loadPortalUsageRecords()
            }
        }
    }

    /// 侧栏把高频数据页面和低频设置入口分开，底部固定显示连接状态。
    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                SubPilotBrandIcon(size: 38)

                Text("SubPilot")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 14)

            VStack(spacing: 4) {
                ForEach(MainWindowSection.accountSections) { section in
                    sidebarButton(section)
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            VStack(spacing: 10) {
                VStack(spacing: 4) {
                    ForEach(MainWindowSection.toolSections) { section in
                        sidebarButton(section)
                    }
                }

                Divider()

                Button {
                    openSettingsWindow()
                } label: {
                    Label("设置", systemImage: "gearshape")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .font(.system(size: 14, weight: .medium))

                Divider()

                HStack(spacing: 8) {
                    Circle()
                        .fill(sidebarStatusColor)
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(sidebarStatusTitle)
                            .font(.system(size: 12, weight: .medium))
                        Text("Sub2API")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .padding(14)
        }
        .glassChromeSurface()
    }

    /// 侧栏按钮共用固定高度和选中态，页面数量增加后仍保持一致的点击区域。
    private func sidebarButton(_ section: MainWindowSection) -> some View {
        Button {
            // 页面包含图表、长列表和玻璃材质，整页参与动画会触发大量中间帧重排和重绘。
            selection = section
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 20)
                Text(section.title)
                    .font(.system(size: 14, weight: .medium))
                Spacer()
            }
            .foregroundStyle(selection == section ? AppTheme.accent : Color.primary)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(
                selection == section ? AppTheme.selectedSurface : Color.clear,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay {
                // 选中态的细高光边界让它像嵌在侧栏玻璃中的控制面，而不是简单色块。
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(selection == section ? Color.white.opacity(0.08) : Color.clear, lineWidth: 0.75)
            }
        }
        .buttonStyle(.plain)
    }

    /// 根据同步状态选择数据页、加载页或可恢复的错误页。
    @ViewBuilder
    private var detail: some View {
        if let snapshot = appState.snapshot {
            VStack(spacing: 0) {
                pageHeader(snapshot)
                Divider()
                Group {
                    if selection == .usage {
                        // 使用记录包含独立长列表，让列表自己滚动才能真正按需创建可见行。
                        UsageRecordsPortalView()
                            .padding(AppTheme.compactContentPadding)
                    } else {
                        ScrollView {
                            selectedContent(snapshot)
                                .padding(AppTheme.compactContentPadding)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.workspaceCanvas)
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
                    .font(AppTheme.pageTitleFont)
                Text(pageSubtitle(snapshot))
                    .font(AppTheme.captionFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if selection == .overview || selection == .usage {
                periodSelector
                    .frame(width: 184)
            }

            Text("更新 \(formattedTime(snapshot.refreshedAt))")
                .font(AppTheme.captionFont)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button {
                Task { await refreshSelectedSection() }
            } label: {
                if appState.isLoading || appState.isLoadingPortal {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(ToolbarIconButtonStyle())
            .help("刷新数据")
            .disabled(appState.isLoading || appState.isLoadingPortal)
        }
        .padding(.horizontal, 20)
        .frame(height: AppTheme.pageHeaderHeight)
        .glassChromeSurface()
    }

    /// 不同页面使用同一个数据快照，但提供针对任务的内容密度和重点。
    @ViewBuilder
    private func selectedContent(_ snapshot: DashboardSnapshot) -> some View {
        switch selection {
        case .overview:
            overviewContent(snapshot)
        case .apiKeys:
            APIKeysPortalView()
        case .usage:
            // 使用记录在主窗口中走独立滚动分支，这里只保留类型完整性所需的占位视图。
            EmptyView()
        case .channels:
            ChannelStatusPortalView()
        case .subscriptions:
            SubscriptionsPortalView()
        case .redeem:
            RedeemPortalView()
        case .profile:
            ProfilePortalView()
        case .analysis:
            analysisContent
        case .resets:
            resetContent(snapshot)
        }
    }

    /// 概览保留一个主趋势、一个模型侧栏和一个平台表格，避免多个同权面板形成卡片墙。
    private func overviewContent(_ snapshot: DashboardSnapshot) -> some View {
        VStack(spacing: 12) {
            accountSummary(snapshot)
            metricStrip(snapshot)

            HStack(alignment: .top, spacing: 12) {
                overviewTrendPanel
                    .frame(maxWidth: .infinity)
                modelDistributionPanel
                    .frame(width: 320)
            }

            platformDistributionPanel

            HStack(alignment: .top, spacing: 12) {
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
                    .font(AppTheme.captionFont)
                    .foregroundStyle(.secondary)
                Button {
                    presentBalanceActivities()
                } label: {
                    HStack(spacing: 6) {
                        Text(currency(snapshot.balance))
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                            .monospacedDigit()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help("查看余额增加记录")
                .accessibilityLabel("可用余额 \(currency(snapshot.balance))，查看余额增加记录")
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
                .font(AppTheme.captionFont.weight(.medium))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider().frame(height: 92)

            platformQuotaSummary(snapshot)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .panelSurface(padding: 20)
    }

    /// 平台额度优先展示周和月两套窗口；旧服务端没有新接口时回退为原单额度行。
    private func platformQuotaSummary(_ snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(snapshot.primaryPlatformQuota?.displayName ?? "订阅") 平台额度")
                    .font(AppTheme.sectionTitleFont)
                Spacer()
                AppStatusLabel(title: "已连接", color: AppTheme.success)
            }

            if let quota = snapshot.primaryPlatformQuota,
               quota.weekly != nil || quota.monthly != nil {
                if let weekly = quota.weekly {
                    platformQuotaRow(title: "周额度", window: weekly)
                }
                if quota.weekly != nil, quota.monthly != nil {
                    Divider()
                }
                if let monthly = quota.monthly {
                    platformQuotaRow(title: "月（近 30 天）", window: monthly)
                }
            } else {
                legacyQuotaRow(snapshot)
            }
        }
    }

    /// 单个额度窗口在一行中显示金额、进度和带时区的重置时间。
    private func platformQuotaRow(title: String, window: PlatformQuotaWindow) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Text("\(UsageFormatter.cost(window.used)) / \(UsageFormatter.cost(window.limit))")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            ProgressView(value: window.progress ?? 0)
                .tint(quotaTint(window.progress))
                .controlSize(.small)
            Text("\(formattedQuotaReset(window.resetsAt)) 重置 · \(selectedTimeZone.identifier)")
                .font(AppTheme.captionFont)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    /// 旧部署回退行保持原有金额和剩余额度信息，避免接口升级成为硬性要求。
    private func legacyQuotaRow(_ snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("订阅额度")
                Spacer()
                Text("\(currency(snapshot.quotaUsed)) / \(currency(snapshot.quotaTotal))")
                    .fontWeight(.semibold)
            }
            .font(.system(size: 11))
            quotaProgressBar(snapshot.quotaProgress)
            Text(snapshot.resetAt.map { "\($0) 重置 · \(selectedTimeZone.identifier)" } ?? "暂未配置额度")
                .font(AppTheme.captionFont)
                .foregroundStyle(.secondary)
        }
    }

    /// 额度超过九成时使用警示色，其余保持产品强调色。
    private func quotaTint(_ progress: Double?) -> Color {
        guard let progress else { return .secondary }
        return progress >= 0.9 ? AppTheme.warning : AppTheme.accent
    }

    /// 服务端重置时间转换到用户选择时区，仅显示月日和分钟以保持紧凑。
    private func formattedQuotaReset(_ value: String?) -> String {
        guard let value, let date = parseISO8601Date(value) else { return "暂未提供时间" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = selectedTimeZone
        formatter.dateFormat = "M/d HH:mm"
        return formatter.string(from: date)
    }

    /// 同时兼容带小数秒和普通 ISO 8601（国际标准时间格式）的服务端时间。
    private func parseISO8601Date(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value)
    }

    /// 打开余额增加弹窗，并立即从 Sub2API 请求充值、兑换和人工加款记录。
    private func presentBalanceActivities() {
        showsBalanceActivities = true
        Task { await appState.loadBalanceActivities(force: true) }
    }

    /// 六项高频指标共用一个连续轨道；并发上限已在账户摘要展示，这里保留 RPM 与 TPM 运行速率。
    private func metricStrip(_ snapshot: DashboardSnapshot) -> some View {
        AppMetricRail(items: [
            AppMetricItem(
                icon: "textformat.123",
                title: "Token",
                value: UsageFormatter.compactTokens(snapshot.periodTokens),
                detail: snapshot.usagePeriod.metricTitle
            ),
            AppMetricItem(
                icon: "arrow.up.arrow.down",
                title: "请求",
                value: UsageFormatter.requestCount(snapshot.requestCount),
                detail: "模型调用记录"
            ),
            AppMetricItem(
                icon: "dollarsign",
                title: "实际消费",
                value: UsageFormatter.cost(snapshot.usageCost),
                detail: "中转实际扣费"
            ),
            AppMetricItem(
                icon: "timer",
                title: "平均响应",
                value: UsageFormatter.duration(milliseconds: snapshot.averageResponseMilliseconds),
                detail: "服务端记录"
            ),
            AppMetricItem(
                icon: "gauge.with.dots.needle.33percent",
                title: "RPM",
                value: recentRPM.formatted(.number.precision(.fractionLength(0...1))),
                detail: "近 5 分钟"
            ),
            AppMetricItem(
                icon: "gauge.with.dots.needle.67percent",
                title: "TPM",
                value: UsageFormatter.compactTokens(recentTPM),
                detail: "近 5 分钟"
            )
        ])
    }

    /// 单个主指标固定布局，长数值缩放而不会推动相邻列变化。
    private func mainMetric(icon: String, title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: icon)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
    }

    /// 指标列之间使用短分隔线，容器边界保持连续。
    private var metricDivider: some View {
        Divider().frame(height: 56)
    }

    /// 按平台聚合当前已加载的真实记录，平台名称优先来自分组，缺失时根据模型前缀判断。
    private var platformSummaries: [OverviewPlatformSummary] {
        let grouped = Dictionary(grouping: appState.portalUsageRecords) { record in
            overviewPlatformName(record)
        }
        return grouped.map { platform, records in
            OverviewPlatformSummary(
                platform: platform,
                tokens: records.reduce(0) { $0 + $1.totalTokens },
                requests: records.count,
                cost: records.reduce(0) { $0 + $1.actualCost },
                averageResponse: records.compactMap(\.durationMilliseconds).average
            )
        }
        .sorted { $0.cost > $1.cost }
    }

    /// 平台拆分采用单层表格，金额和延迟列保持固定宽度以便快速比较。
    private var platformDistributionPanel: some View {
        VStack(spacing: 0) {
            sectionBar("按平台拆分", trailing: "最近 \(appState.portalUsageRecords.count) 条")
            HStack(spacing: 8) {
                Text("平台").frame(maxWidth: .infinity, alignment: .leading)
                Text("Token").frame(width: 68, alignment: .trailing)
                Text("请求").frame(width: 52, alignment: .trailing)
                Text("消费").frame(width: 70, alignment: .trailing)
                Text("平均响应").frame(width: 72, alignment: .trailing)
            }
            .font(AppTheme.captionFont.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(AppTheme.tableHeader)
            ForEach(platformSummaries.prefix(4)) { item in
                HStack(spacing: 8) {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(AppTheme.accent)
                            .frame(width: 7, height: 7)
                        Text(item.platform)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(UsageFormatter.compactTokens(item.tokens)).frame(width: 68, alignment: .trailing)
                    Text(item.requests.formatted()).frame(width: 52, alignment: .trailing)
                    Text(UsageFormatter.cost(item.cost)).frame(width: 70, alignment: .trailing)
                    Text(UsageFormatter.duration(milliseconds: item.averageResponse)).frame(width: 72, alignment: .trailing)
                }
                .font(AppTheme.bodyFont)
                .monospacedDigit()
                .padding(.horizontal, 14)
                .frame(height: 40)
                Divider().padding(.leading, 14)
            }
            if platformSummaries.isEmpty {
                Text("同步最近调用后显示平台分布")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 104)
            }
        }
        .panelSurface(padding: 0)
    }

    /// 模型分布按真实 Token 聚合，条形图长度使用同一最大值作为基准。
    private var modelDistributionPanel: some View {
        VStack(spacing: 0) {
            sectionBar("模型分布", trailing: snapshotPeriodTitle)
            if overviewModelSummaries.isEmpty {
                Text("暂无模型调用")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 136)
            } else {
                Chart(overviewModelSummaries) { item in
                    BarMark(
                        x: .value("Token", item.tokens),
                        y: .value("模型", item.model)
                    )
                    .foregroundStyle(AppTheme.accent)
                    .cornerRadius(2)
                    .annotation(position: .trailing) {
                        Text(UsageFormatter.compactTokens(item.tokens))
                            .font(AppTheme.captionFont)
                            .foregroundStyle(.secondary)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 176)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }
        }
        .panelSurface(padding: 0)
    }

    /// Token 趋势使用最近真实调用点，面积只用于帮助识别峰值而不改变数据含义。
    private var overviewTrendPanel: some View {
        VStack(spacing: 0) {
            sectionBar("Token 使用趋势", trailing: "当前已加载")
            if overviewTrendRecords.isEmpty {
                Text("暂无趋势数据")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 188)
            } else {
                Chart(overviewTrendRecords) { record in
                    LineMark(
                        x: .value("时间", record.createdAt),
                        y: .value("Token", record.totalTokens)
                    )
                    .foregroundStyle(AppTheme.accent)
                    .interpolationMethod(.catmullRom)
                    PointMark(
                        x: .value("时间", record.createdAt),
                        y: .value("Token", record.totalTokens)
                    )
                    .foregroundStyle(AppTheme.accent)
                    .symbolSize(10)
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) }
                .frame(height: 188)
                .padding(12)
            }
        }
        .panelSurface(padding: 0)
    }

    /// 最近使用列表展示模型、Token、费用和响应，点击行可在使用记录页继续查看完整历史。
    private var recentUsagePanel: some View {
        VStack(spacing: 0) {
            sectionBar("最近使用", trailing: "最新 5 条")
            ForEach(appState.portalUsageRecords.prefix(5)) { record in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.model).font(.system(size: 10, weight: .medium)).lineLimit(1)
                        Text(formattedTime(record.createdAt)).font(.system(size: 8)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(UsageFormatter.compactTokens(record.totalTokens)).frame(width: 52, alignment: .trailing)
                    Text(UsageFormatter.cost(record.actualCost)).frame(width: 62, alignment: .trailing)
                    Text(UsageFormatter.duration(milliseconds: record.durationMilliseconds)).frame(width: 58, alignment: .trailing)
                }
                .font(.system(size: 9))
                .monospacedDigit()
                .padding(.horizontal, 12)
                .frame(height: 34)
                Divider().padding(.leading, 12)
            }
            if appState.portalUsageRecords.isEmpty {
                Text("暂无最近调用")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 150)
            }
        }
        .panelSurface(padding: 0)
    }

    /// 所有数据面板复用同一标题组件，避免页面出现不同的标题高度和文字层级。
    private func sectionBar(_ title: String, trailing: String) -> some View {
        AppSectionHeader(title: title, trailing: trailing)
    }

    /// 最近五分钟速率以最新一条账单为窗口终点，离线预览和真实数据都能稳定复现。
    private var recentRateRecords: [PortalUsageRecord] {
        guard let newest = appState.portalUsageRecords.map(\.createdAt).max() else { return [] }
        let start = newest.addingTimeInterval(-300)
        return appState.portalUsageRecords.filter { $0.createdAt >= start && $0.createdAt <= newest }
    }

    /// RPM（每分钟请求数）使用五分钟窗口均摊，避免瞬时一条请求显示夸大的速率。
    private var recentRPM: Double {
        Double(recentRateRecords.count) / 5
    }

    /// TPM（每分钟 Token 数）与 RPM 使用完全相同的时间窗口。
    private var recentTPM: Double {
        recentRateRecords.reduce(0) { $0 + $1.totalTokens } / 5
    }

    /// 模型分布只保留前五项，避免长尾模型压缩主图可读性。
    private var overviewModelSummaries: [OverviewModelSummary] {
        Dictionary(grouping: appState.portalUsageRecords, by: \.model)
            .map { OverviewModelSummary(model: $0.key, tokens: $0.value.reduce(0) { $0 + $1.totalTokens }) }
            .sorted { $0.tokens > $1.tokens }
            .prefix(5)
            .map { $0 }
    }

    /// 趋势图最多绘制 60 条最近调用，避免大量滚动历史导致界面重绘卡顿。
    private var overviewTrendRecords: [PortalUsageRecord] {
        Array(appState.portalUsageRecords.prefix(60).reversed())
    }

    /// 统计周期短标题用于图表辅助信息。
    private var snapshotPeriodTitle: String {
        appState.snapshot?.usagePeriod.metricTitle ?? "当前周期"
    }

    /// 分组信息缺失时根据常见模型前缀推断展示名称，仅影响界面分组不改变账单数据。
    private func overviewPlatformName(_ record: PortalUsageRecord) -> String {
        if let group = record.groupName, !group.isEmpty { return group }
        let model = record.model.lowercased()
        if model.contains("claude") { return "Claude" }
        if model.contains("gemini") { return "Gemini" }
        if model.contains("grok") { return "grok" }
        return "OpenAI"
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
                set: { period in
                    appState.selectUsagePeriod(period)
                    if selection == .overview || selection == .usage {
                        Task { await appState.loadPortalUsageRecords(force: true) }
                    }
                }
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
    }

    /// 根据页面内容生成一行辅助说明，不增加无关产品文案。
    private func pageSubtitle(_ snapshot: DashboardSnapshot) -> String {
        switch selection {
        case .overview: return "\(snapshot.recentModel ?? "暂无模型记录") · \(sidebarStatusTitle)"
        case .apiKeys: return "创建、启停和管理访问密钥"
        case .usage:
            let total = appState.portalUsageTotal > 0 ? appState.portalUsageTotal : appState.portalUsageRecords.count
            return "\(snapshot.usagePeriod.metricTitle) · 共 \(total) 条 · 滚动加载历史"
        case .channels: return "普通用户可见的渠道可用率与延迟"
        case .subscriptions: return "订阅计划和周期实际使用量"
        case .redeem: return "兑换余额、并发或订阅权益"
        case .profile: return "账户资料与安全设置"
        case .analysis: return "滚动统计最近 1 小时"
        case .resets: return timeZoneDescription
        }
    }

    /// 根据当前页面选择最小必要刷新范围，避免一次操作触发全部用户端接口。
    private func refreshSelectedSection() async {
        switch selection {
        case .overview, .resets:
            await appState.refresh()
        case .apiKeys:
            await appState.loadAPIKeys(force: true)
        case .usage:
            await appState.loadPortalUsageRecords(force: true)
        case .channels:
            await appState.loadChannelMonitors(force: true)
        case .subscriptions:
            await appState.loadSubscriptions(force: true)
        case .redeem:
            await appState.loadBalanceActivities(force: true)
            await appState.refresh(showLoading: false)
        case .profile:
            await appState.loadUserProfile(force: true)
        case .analysis:
            await appState.analyzeConsumption(force: true)
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
        appState.errorMessage == nil ? AppTheme.success : AppTheme.warning
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
            : AppTheme.success
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
