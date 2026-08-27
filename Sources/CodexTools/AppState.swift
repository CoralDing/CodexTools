/**
 * 文件说明：应用登录状态、自动刷新流程、时区偏好和提醒策略
 * 作者：dingyi60(Codex)
 * 创建时间：2026-08-25
 */

import AppKit
import Combine
import Foundation
import UserNotifications

/// 集中维护应用状态，保证登录页、悬浮层和设置页看到同一份数据。
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var session: AuthSession?
    @Published private(set) var pendingTwoFactor: PendingTwoFactor?
    @Published private(set) var snapshot: DashboardSnapshot?
    @Published private(set) var consumptionAnalysis: ConsumptionAnalysis?
    @Published private(set) var isAnalyzingConsumption = false
    @Published private(set) var consumptionAnalysisErrorMessage: String?
    @Published private(set) var balanceActivities: [BalanceActivity] = []
    @Published private(set) var isLoadingBalanceActivities = false
    @Published private(set) var balanceActivityErrorMessage: String?
    @Published private(set) var isLoading = false
    @Published private(set) var usagePeriod: UsagePeriod
    @Published var errorMessage: String?

    private let keychain = KeychainSessionStore()
    private let resetsClient = CodexResetsClient()
    private let localUsageStore = LocalCodexUsageStore()
    private var pollingTask: Task<Void, Never>?
    private var periodRefreshTask: Task<Void, Never>?
    private var consumptionAnalysisTask: Task<Void, Never>?

    /// 从 Keychain 恢复会话，并在应用启动后立即同步一次状态；QA 可注入无凭据的示例快照或两步验证状态。
    init(
        previewSnapshot: DashboardSnapshot? = nil,
        previewTwoFactor: PendingTwoFactor? = nil,
        restoreStoredSession: Bool = true
    ) {
        usagePeriod = UsagePeriod(
            rawValue: UserDefaults.standard.string(forKey: PreferenceKey.usagePeriod) ?? ""
        ) ?? .today
        consumptionAnalysis = Self.loadStoredConsumptionAnalysis()

        if let previewTwoFactor {
            pendingTwoFactor = previewTwoFactor
            return
        }

        if let previewSnapshot {
            session = AuthSession(
                serverURL: URL(string: "https://sub2api.example")!,
                accessToken: "qa-preview-token",
                refreshToken: nil,
                expiresAt: nil,
                userID: "qa-preview-user"
            )
            snapshot = previewSnapshot
            consumptionAnalysis = Self.makeQAPreviewConsumptionAnalysis()
            balanceActivities = Self.makeQAPreviewBalanceActivities()
            return
        }

        // QA 登录预览会关闭会话恢复，避免视觉检查意外读取用户的真实钥匙串数据。
        guard restoreStoredSession else { return }

        do {
            session = try keychain.load()
        } catch {
            errorMessage = error.localizedDescription
        }

        if session != nil {
            startPolling()
            startConsumptionAnalysis()
            Task { await refresh() }
        }
    }

    /// 创建覆盖余额警告、额度进度、时区和社区重置时间的确定性示例数据。
    static func makeQAPreviewSnapshot() -> DashboardSnapshot {
        DashboardSnapshot(
            balance: 18.42,
            concurrencyLimit: 10,
            quotaUsed: 320,
            quotaTotal: 500,
            periodTokens: 1_284_620,
            requestCount: 842,
            usageCost: 3.42,
            averageResponseMilliseconds: 1_286,
            usagePeriod: .today,
            recentModel: "gpt-5.6-sol",
            resetAt: "2026-08-26 08:00",
            lastGlobalResetAt: ISO8601DateFormatter().date(from: "2026-08-24T00:46:51Z"),
            lastGlobalResetType: "regular",
            resetSourceURL: URL(string: "https://codex-resets.com"),
            resetSyncedAt: ISO8601DateFormatter().date(from: "2026-08-25T03:07:27Z"),
            displayTimeZone: "Asia/Shanghai",
            refreshedAt: ISO8601DateFormatter().date(from: "2026-08-25T03:10:00Z")!
        )
    }

    /// 创建覆盖正常结论、综合倍率和最近一小时成本的确定性分析示例。
    static func makeQAPreviewConsumptionAnalysis() -> ConsumptionAnalysis {
        let analyzedAt = ISO8601DateFormatter().date(from: "2026-08-25T06:10:00Z")!
        return ConsumptionAnalysis(
            status: .normal,
            message: "本地调用与 Sub2API 账单数量已对齐",
            windowStart: analyzedAt.addingTimeInterval(-3_600),
            windowEnd: analyzedAt,
            analyzedAt: analyzedAt,
            requestCount: 128,
            billedRequestCount: 127,
            totalTokens: 12_846_200,
            standardCost: 4.275,
            actualCost: 3.42,
            effectiveMultiplier: 0.8,
            minimumRecordedMultiplier: 0.8,
            maximumRecordedMultiplier: 0.8,
            averageResponseMilliseconds: 1_286,
            inconsistentRequestCount: 0,
            isTruncated: false
        )
    }

    /// 创建不含账户标识的固定余额活动，用于弹窗截图和行布局检查。
    static func makeQAPreviewBalanceActivities() -> [BalanceActivity] {
        let formatter = ISO8601DateFormatter()
        return [
            BalanceActivity(
                createdAt: formatter.date(from: "2026-08-26T01:28:00Z")!,
                kind: .usage,
                title: "gpt-5.6-sol",
                detail: "模型调用",
                amountChange: -0.688,
                totalTokens: 248_620,
                durationMilliseconds: 1_286
            ),
            BalanceActivity(
                createdAt: formatter.date(from: "2026-08-26T01:06:00Z")!,
                kind: .recharge,
                title: "余额充值",
                detail: "支付宝",
                amountChange: 20,
                totalTokens: nil,
                durationMilliseconds: nil
            ),
            BalanceActivity(
                createdAt: formatter.date(from: "2026-08-25T15:42:00Z")!,
                kind: .usage,
                title: "gpt-5.2-codex",
                detail: "模型调用",
                amountChange: -0.064,
                totalTokens: 16_820,
                durationMilliseconds: 610
            ),
            BalanceActivity(
                createdAt: formatter.date(from: "2026-08-25T13:15:00Z")!,
                kind: .adjustment,
                title: "管理员增加余额",
                detail: "余额调整",
                amountChange: 5,
                totalTokens: nil,
                durationMilliseconds: nil
            )
        ]
    }

    /// 创建不含真实账户信息的两步验证示例，避免视觉检查依赖用户密码或临时令牌。
    static func makeQAPreviewTwoFactor() -> PendingTwoFactor {
        PendingTwoFactor(
            serverURL: URL(string: "https://sub2api.example")!,
            tempToken: "qa-preview-temp-token",
            maskedEmail: "d***@example.com"
        )
    }

    deinit {
        pollingTask?.cancel()
        periodRefreshTask?.cancel()
        consumptionAnalysisTask?.cancel()
    }

    /// 校验输入并登录 Sub2API，成功后马上获取仪表盘数据。
    func login(server: String, email: String, password: String) async {
        guard let serverURL = Self.normalizedServerURL(server) else {
            errorMessage = CodexToolsError.invalidServerURL.localizedDescription
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let client = try Sub2APIClient(serverURL: serverURL)
            let outcome = try await client.login(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
            switch outcome {
            case let .authenticated(newSession):
                try await finishLogin(with: newSession)
            case let .requiresTwoFactor(challenge):
                pendingTwoFactor = challenge
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 提交 TOTP 验证码，成功后沿用普通登录的安全存储和首次同步流程。
    func completeTwoFactor(code: String) async {
        guard let challenge = pendingTwoFactor else {
            errorMessage = "两步验证会话已失效，请返回重新登录。"
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let client = try Sub2APIClient(serverURL: challenge.serverURL)
            let newSession = try await client.completeTwoFactor(
                tempToken: challenge.tempToken,
                code: code
            )
            pendingTwoFactor = nil
            try await finishLogin(with: newSession)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 取消两步验证并清理临时令牌，返回邮箱密码登录表单。
    func cancelTwoFactor() {
        pendingTwoFactor = nil
        errorMessage = nil
    }

    /// 同时刷新 Sub2API 用量和 Codex Resets 社区重置时间，两者互不阻塞。
    func refresh(showLoading: Bool = true) async {
        guard var activeSession = session else { return }
        let requestedPeriod = usagePeriod
        let timeZoneIdentifier = UserDefaults.standard.string(
            forKey: PreferenceKey.displayTimeZone
        ) ?? TimeZone.current.identifier
        let requestedTimeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        if showLoading { isLoading = true }
        errorMessage = nil
        defer { if showLoading { isLoading = false } }

        do {
            let client = try Sub2APIClient(serverURL: activeSession.serverURL)
            if activeSession.needsRefresh() {
                activeSession = try await client.refresh(session: activeSession)
                try keychain.save(activeSession)
                session = activeSession
            }

            async let dashboardTask = client.fetchDashboard(
                token: activeSession.accessToken,
                period: requestedPeriod,
                timeZone: requestedTimeZone
            )
            async let resetTask = try? resetsClient.fetchStatus()
            var refreshedSnapshot = try await dashboardTask
            let resetStatus = await resetTask
            merge(resetStatus: resetStatus, into: &refreshedSnapshot)
            refreshedSnapshot.displayTimeZone = requestedTimeZone.identifier

            // 用户快速切换周期时，丢弃较早请求的结果，避免旧数据覆盖新选择。
            guard requestedPeriod == usagePeriod else { return }

            snapshot = refreshedSnapshot
            await evaluateNotifications(for: refreshedSnapshot)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 清除本机令牌和状态，退出过程不向第三方发送额外数据。
    func logout() {
        pollingTask?.cancel()
        pollingTask = nil
        periodRefreshTask?.cancel()
        periodRefreshTask = nil
        consumptionAnalysisTask?.cancel()
        consumptionAnalysisTask = nil
        do {
            try keychain.delete()
        } catch {
            errorMessage = error.localizedDescription
        }
        session = nil
        pendingTwoFactor = nil
        snapshot = nil
        consumptionAnalysis = nil
        consumptionAnalysisErrorMessage = nil
        balanceActivities = []
        balanceActivityErrorMessage = nil
        isLoadingBalanceActivities = false
        UserDefaults.standard.removeObject(forKey: PreferenceKey.consumptionAnalysisSnapshot)
    }

    /// 按需读取最近余额变动；列表只保留在内存中，避免持久化逐条账户活动。
    func loadBalanceActivities(force: Bool = false) async {
        guard !isLoadingBalanceActivities else { return }
        if !force, !balanceActivities.isEmpty { return }
        guard var activeSession = session else { return }

        isLoadingBalanceActivities = true
        balanceActivityErrorMessage = nil
        defer { isLoadingBalanceActivities = false }

        do {
            var client = try Sub2APIClient(serverURL: activeSession.serverURL)
            if activeSession.needsRefresh() {
                activeSession = try await client.refresh(session: activeSession)
                try keychain.save(activeSession)
                session = activeSession
                client = try Sub2APIClient(serverURL: activeSession.serverURL)
            }
            balanceActivities = try await client.fetchBalanceActivities(
                token: activeSession.accessToken
            )
        } catch {
            // 保留上次成功结果，让短暂网络故障只显示提示而不会清空活动列表。
            balanceActivityErrorMessage = error.localizedDescription
        }
    }

    /// 保存最终会话并执行首次同步，确保普通登录和两步验证行为一致。
    private func finishLogin(with newSession: AuthSession) async throws {
        try keychain.save(newSession)
        session = newSession
        startPolling()
        startConsumptionAnalysis()
        await refresh(showLoading: false)
    }

    /// 用户修改刷新间隔后重新启动定时任务，使设置立即生效。
    func restartPolling() {
        if var currentSnapshot = snapshot {
            currentSnapshot.displayTimeZone = UserDefaults.standard.string(
                forKey: PreferenceKey.displayTimeZone
            ) ?? TimeZone.current.identifier
            snapshot = currentSnapshot
        }
        startPolling()
        Task { await refresh(showLoading: false) }
    }

    /// 应用消耗分析开关；关闭时停止后台任务，重新开启时立即强制生成一份新结果。
    func setConsumptionAnalysisEnabled(_ enabled: Bool) {
        consumptionAnalysisTask?.cancel()
        consumptionAnalysisTask = nil
        guard enabled else {
            isAnalyzingConsumption = false
            return
        }
        startConsumptionAnalysis(forceInitialAnalysis: true)
    }

    /// 切换统计周期并立即同步；取消上一次周期刷新可减少快速点击产生的无效请求。
    func selectUsagePeriod(_ period: UsagePeriod) {
        guard usagePeriod != period else { return }
        usagePeriod = period
        UserDefaults.standard.set(period.rawValue, forKey: PreferenceKey.usagePeriod)
        periodRefreshTask?.cancel()
        periodRefreshTask = Task { [weak self] in
            await self?.refresh()
        }
    }

    /// 打开浏览器查看社区重置公告的原始来源。
    func openResetSource() {
        guard let url = snapshot?.resetSourceURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// 将用户输入规范化为不带尾部斜杠的 HTTPS 地址。
    private static func normalizedServerURL(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              components.scheme == "https",
              components.host != nil else {
            return nil
        }
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return components.url
    }

    /// 启动单一轮询任务，避免用户多次登录或改设置后出现并发定时器。
    private func startPolling() {
        pollingTask?.cancel()
        guard session != nil else { return }

        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                let minutes = max(UserDefaults.standard.integer(forKey: PreferenceKey.refreshMinutes), 1)
                try? await Task.sleep(for: .seconds(minutes * 60))
                guard !Task.isCancelled else { return }
                await self?.refresh(showLoading: false)
            }
        }
    }

    /// 启动独立的每小时分析任务；失败时五分钟后重试，成功后从分析完成时间计算下次执行。
    private func startConsumptionAnalysis(forceInitialAnalysis: Bool = false) {
        consumptionAnalysisTask?.cancel()
        guard session != nil,
              UserDefaults.standard.bool(forKey: PreferenceKey.consumptionAnalysisEnabled) else {
            return
        }

        consumptionAnalysisTask = Task { [weak self] in
            var shouldForceAnalysis = forceInitialAnalysis
            while !Task.isCancelled {
                await self?.analyzeConsumption(force: shouldForceAnalysis)
                shouldForceAnalysis = false
                guard !Task.isCancelled else { return }

                let secondsUntilNext: TimeInterval
                if let analyzedAt = self?.consumptionAnalysis?.analyzedAt {
                    secondsUntilNext = max(3_600 - Date().timeIntervalSince(analyzedAt), 60)
                } else {
                    secondsUntilNext = 300
                }
                try? await Task.sleep(for: .seconds(secondsUntilNext))
            }
        }
    }

    /// 分析最近一小时调用；普通调度遵守一小时限频，用户手动触发时可强制立即更新。
    func analyzeConsumption(force: Bool = false) async {
        guard UserDefaults.standard.bool(forKey: PreferenceKey.consumptionAnalysisEnabled),
              !isAnalyzingConsumption else {
            return
        }
        if !force,
           let analyzedAt = consumptionAnalysis?.analyzedAt,
           Date().timeIntervalSince(analyzedAt) < 3_600 {
            return
        }
        guard var activeSession = session else { return }

        isAnalyzingConsumption = true
        consumptionAnalysisErrorMessage = nil
        defer { isAnalyzingConsumption = false }

        do {
            var client = try Sub2APIClient(serverURL: activeSession.serverURL)
            if activeSession.needsRefresh() {
                activeSession = try await client.refresh(session: activeSession)
                try keychain.save(activeSession)
                session = activeSession
                client = try Sub2APIClient(serverURL: activeSession.serverURL)
            }

            let timeZoneIdentifier = UserDefaults.standard.string(
                forKey: PreferenceKey.displayTimeZone
            ) ?? TimeZone.current.identifier
            let timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
            let analyzedAt = Date()
            let windowStart = analyzedAt.addingTimeInterval(-3_600)
            // 本地标准成本来自 CC Switch 同步的 Codex 会话记录，与 Sub2API 账单形成独立对照。
            let localUsage = try localUsageStore.readUsage(
                windowStart: windowStart,
                windowEnd: analyzedAt
            )
            let fetched = try await client.fetchRecentUsageRecords(
                token: activeSession.accessToken,
                timeZone: timeZone,
                referenceDate: analyzedAt
            )
            let result = ConsumptionAnalyzer.analyze(
                localUsage: localUsage,
                records: fetched.records,
                windowStart: windowStart,
                windowEnd: analyzedAt,
                analyzedAt: analyzedAt,
                isTruncated: fetched.isTruncated
            )

            // 用户可能在网络请求期间关闭分析；此时丢弃结果，避免已关闭功能继续更新状态。
            guard UserDefaults.standard.bool(forKey: PreferenceKey.consumptionAnalysisEnabled) else {
                return
            }
            consumptionAnalysis = result
            Self.storeConsumptionAnalysis(result)
        } catch {
            // 保留上一次成功结果，网络短暂失败不会把面板降级成空白状态。
            consumptionAnalysisErrorMessage = error.localizedDescription
        }
    }

    /// 从 UserDefaults（macOS 轻量偏好存储）恢复最近分析，不包含调用明细或任何凭据。
    private static func loadStoredConsumptionAnalysis() -> ConsumptionAnalysis? {
        guard let data = UserDefaults.standard.data(forKey: PreferenceKey.consumptionAnalysisSnapshot) else {
            return nil
        }
        guard let analysis = try? JSONDecoder().decode(ConsumptionAnalysis.self, from: data),
              analysis.billedRequestCount != nil else {
            // 旧版本没有本地与中转双数据源，必须丢弃旧口径结果，避免继续展示循环计算出的倍率。
            return nil
        }
        return analysis
    }

    /// 只持久化汇总结果，避免将请求标识、模型明细或其他调用数据长期保存在本机。
    private static func storeConsumptionAnalysis(_ analysis: ConsumptionAnalysis) {
        guard let data = try? JSONEncoder().encode(analysis) else { return }
        UserDefaults.standard.set(data, forKey: PreferenceKey.consumptionAnalysisSnapshot)
    }

    /// 将社区重置数据合并到用量快照；接口失败时保留 Sub2API 自己的重置提示。
    private func merge(
        resetStatus: CodexResetStatusResponse?,
        into snapshot: inout DashboardSnapshot
    ) {
        guard let resetStatus else { return }
        snapshot.lastGlobalResetAt = resetStatus.data.latestReset?.announcedAt
            ?? resetStatus.data.stats.lastResetAt
        snapshot.lastGlobalResetType = resetStatus.data.latestReset?.resetType
        snapshot.resetSourceURL = resetStatus.data.latestReset?.source.url
        snapshot.resetSyncedAt = resetStatus.meta.generatedAt
    }

    /// 评估社区重置、余额和额度提醒；系统权限只在用户明确启用总开关后请求。
    private func evaluateNotifications(for snapshot: DashboardSnapshot) async {
        // 无论通知是否启用都先更新社区观察记录，避免以后开启通知时补发历史消息。
        let shouldNotifyCommunityReset = observeCommunityReset(snapshot.lastGlobalResetAt)
        guard UserDefaults.standard.bool(forKey: PreferenceKey.notificationsEnabled) else { return }
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return }

        if shouldNotifyCommunityReset,
           UserDefaults.standard.bool(forKey: PreferenceKey.communityResetNotificationsEnabled),
           let resetAt = snapshot.lastGlobalResetAt {
            await Self.sendNotification(
                title: "CodexTools 社区重置提醒",
                body: Self.communityResetNotificationBody(
                    resetAt: resetAt,
                    resetType: snapshot.lastGlobalResetType,
                    timeZoneIdentifier: snapshot.displayTimeZone
                )
            )
        }

        let balanceThreshold = UserDefaults.standard.double(forKey: PreferenceKey.balanceThreshold)
        if let balance = snapshot.balance, balance <= balanceThreshold {
            await Self.sendNotification(
                title: "CodexTools 余额提醒",
                body: "当前余额 \(balance.formatted(.number.precision(.fractionLength(2))))，已低于设定阈值。"
            )
        }

        let quotaThreshold = UserDefaults.standard.double(forKey: PreferenceKey.quotaThreshold)
        if let remaining = snapshot.quotaRemainingPercent, remaining <= quotaThreshold {
            await Self.sendNotification(
                title: "CodexTools 额度提醒",
                body: "订阅额度仅剩 \(remaining.formatted(.number.precision(.fractionLength(0))))%。"
            )
        }
    }

    /// 持久化最新社区重置时间，并只为严格更新的事件返回 true；首次记录不会触发历史提醒。
    private func observeCommunityReset(_ resetAt: Date?) -> Bool {
        guard let resetAt else { return false }
        let defaults = UserDefaults.standard
        let key = PreferenceKey.lastObservedCommunityResetAt

        guard defaults.object(forKey: key) != nil else {
            defaults.set(resetAt.timeIntervalSince1970, forKey: key)
            return false
        }

        let lastObserved = Date(timeIntervalSince1970: defaults.double(forKey: key))
        guard CommunityResetNotificationPolicy.shouldNotify(
            current: resetAt,
            lastObserved: lastObserved
        ) else {
            return false
        }

        defaults.set(resetAt.timeIntervalSince1970, forKey: key)
        return true
    }

    /// 生成带重置类型、当地时间和时区名称的通知正文，避免用户误解时间口径。
    private static func communityResetNotificationBody(
        resetAt: Date,
        resetType: String?,
        timeZoneIdentifier: String
    ) -> String {
        let timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        let typeDescription: String
        switch resetType?.lowercased() {
        case "regular": typeDescription = "常规重置"
        case "emergency": typeDescription = "紧急重置"
        default: typeDescription = "全局重置"
        }

        return "社区追踪到新的\(typeDescription)：\(formatter.string(from: resetAt))（\(timeZone.identifier)）。"
    }

    /// 创建本地通知请求，使用稳定标识符覆盖同类旧提醒以减少重复打扰。
    private static func sendNotification(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: title,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}

/// UserDefaults 键集中定义，避免视图和业务逻辑因字符串拼写不同而失联。
enum PreferenceKey {
    static let notificationsEnabled = "notificationsEnabled"
    static let balanceThreshold = "balanceThreshold"
    static let quotaThreshold = "quotaThreshold"
    static let refreshMinutes = "refreshMinutes"
    static let displayTimeZone = "displayTimeZone"
    static let usagePeriod = "usagePeriod"
    static let menuBarShowsTokens = "menuBarShowsTokens"
    static let menuBarShowsCost = "menuBarShowsCost"
    static let consumptionAnalysisEnabled = "consumptionAnalysisEnabled"
    static let communityResetNotificationsEnabled = "communityResetNotificationsEnabled"
    static let lastObservedCommunityResetAt = "lastObservedCommunityResetAt"
    static let consumptionAnalysisSnapshot = "consumptionAnalysisSnapshot"

    /// 首次启动时写入合理默认值，后续不覆盖用户已经调整过的设置。
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            notificationsEnabled: false,
            balanceThreshold: 20.0,
            quotaThreshold: 15.0,
            refreshMinutes: 5,
            displayTimeZone: TimeZone.current.identifier,
            usagePeriod: UsagePeriod.today.rawValue,
            menuBarShowsTokens: true,
            menuBarShowsCost: true,
            consumptionAnalysisEnabled: true,
            communityResetNotificationsEnabled: true
        ])
    }
}
