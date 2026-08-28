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
    @Published private(set) var apiKeys: [UserAPIKey] = []
    @Published private(set) var availableGroups: [AvailableUserGroup] = []
    @Published private(set) var portalUsageRecords: [PortalUsageRecord] = []
    @Published private(set) var portalUsageRecordDetail: PortalUsageRecord?
    @Published private(set) var portalUsagePage = 0
    @Published private(set) var portalUsageTotal = 0
    @Published private(set) var hasMorePortalUsageRecords = false
    @Published private(set) var isLoadingMorePortalUsage = false
    @Published private(set) var channelMonitors: [UserChannelMonitor] = []
    @Published private(set) var subscriptions: [UserSubscriptionItem] = []
    @Published private(set) var userProfile: UserProfileSummary?
    @Published private(set) var latestRedeemResult: RedeemResult?
    @Published private(set) var isLoadingPortal = false
    @Published var portalErrorMessage: String?
    @Published var portalSuccessMessage: String?
    @Published private(set) var isLoading = false
    @Published private(set) var usagePeriod: UsagePeriod
    @Published var errorMessage: String?

    private let keychain = KeychainSessionStore()
    private let resetsClient = CodexResetsClient()
    private let localUsageStore = LocalCodexUsageStore()
    private var pollingTask: Task<Void, Never>?
    private var periodRefreshTask: Task<Void, Never>?
    private var consumptionAnalysisTask: Task<Void, Never>?
    private var activePortalUsageFilters = PortalUsageFilters.empty

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
            applyQAPreviewPortalData()
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
            quotaUsed: 0.11,
            quotaTotal: 550,
            platformQuotas: [
                PlatformQuota(
                    platform: "openai",
                    daily: nil,
                    weekly: PlatformQuotaWindow(
                        used: 0.11,
                        limit: 550,
                        resetsAt: "2026-08-30T16:00:00Z"
                    ),
                    monthly: PlatformQuotaWindow(
                        used: 0.02,
                        limit: 2_200,
                        resetsAt: "2026-09-27T01:47:00Z"
                    )
                )
            ],
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

    /// 创建不含账户标识的固定余额增加记录，用于弹窗截图和行布局检查。
    static func makeQAPreviewBalanceActivities() -> [BalanceActivity] {
        let formatter = ISO8601DateFormatter()
        return [
            BalanceActivity(
                createdAt: formatter.date(from: "2026-08-26T01:28:00Z")!,
                title: "余额充值",
                detail: "支付宝",
                amountChange: 20
            ),
            BalanceActivity(
                createdAt: formatter.date(from: "2026-08-25T15:42:00Z")!,
                title: "兑换码充值",
                detail: "兑换记录",
                amountChange: 10
            ),
            BalanceActivity(
                createdAt: formatter.date(from: "2026-08-25T13:15:00Z")!,
                title: "管理员增加余额",
                detail: "余额调整",
                amountChange: 5
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

    /// 注入不含真实账号与密钥的示例用户端数据，确保所有迁移页面都可以离线截图验收。
    private func applyQAPreviewPortalData() {
        let now = ISO8601DateFormatter().date(from: "2026-08-28T02:42:18Z")!
        apiKeys = [
            UserAPIKey(
                id: 1,
                name: "Codex 主密钥",
                key: "sk-codex-preview-••••9K2F",
                groupName: "OpenAI",
                currentConcurrency: 1,
                quota: 550,
                quotaUsed: 0.11,
                status: "active",
                expiresAt: nil,
                createdAt: now.addingTimeInterval(-86_400 * 28),
                lastUsedAt: now,
                ipWhitelist: [],
                ipBlacklist: [],
                rateLimit5Hours: 2_000,
                rateLimit1Day: 8_000,
                rateLimit7Days: 30_000,
                usage5Hours: 18.42,
                usage1Day: 42.18,
                usage7Days: 183.24
            ),
            UserAPIKey(
                id: 2,
                name: "备用密钥",
                key: "sk-codex-preview-••••A7M3",
                groupName: "OpenAI",
                currentConcurrency: 0,
                quota: 0,
                quotaUsed: 0,
                status: "inactive",
                expiresAt: nil,
                createdAt: now.addingTimeInterval(-86_400 * 12),
                lastUsedAt: now.addingTimeInterval(-86_400 * 3),
                ipWhitelist: ["127.0.0.1"],
                ipBlacklist: [],
                rateLimit5Hours: 0,
                rateLimit1Day: 0,
                rateLimit7Days: 0,
                usage5Hours: 0,
                usage1Day: 0,
                usage7Days: 0
            )
        ]
        availableGroups = [AvailableUserGroup(id: 1, name: "OpenAI", platform: "openai")]
        portalUsageRecords = (0..<12).map { index in
            let input = Double(2_800 + index * 730)
            let output = Double(420 + index * 95)
            return PortalUsageRecord(
                id: index + 1,
                apiKeyName: index % 4 == 0 ? "备用密钥" : "Codex 主密钥",
                model: index % 3 == 0 ? "gpt-5.6-luna" : "gpt-5.6-sol",
                endpoint: "/v1/responses",
                groupName: "OpenAI",
                totalTokens: input + output + 1_200,
                standardCost: 0.04 + Double(index) * 0.008,
                actualCost: 0.032 + Double(index) * 0.0064,
                multiplier: 0.8,
                durationMilliseconds: Double(720 + index * 95),
                createdAt: now.addingTimeInterval(Double(-index * 900)),
                requestID: "req_preview_\(index + 1)",
                inputTokens: input,
                outputTokens: output,
                cacheCreationTokens: 0,
                cacheReadTokens: 1_200,
                inputCost: 0.02 + Double(index) * 0.004,
                outputCost: 0.012 + Double(index) * 0.0024,
                cacheCreationCost: 0,
                cacheReadCost: 0.004,
                requestType: index % 2 == 0 ? "stream" : "sync",
                billingType: 1,
                billingMode: "standard",
                isStream: index % 2 == 0,
                firstTokenMilliseconds: Double(260 + index * 12)
            )
        }
        portalUsagePage = 1
        portalUsageTotal = 842
        hasMorePortalUsageRecords = true
        channelMonitors = [
            UserChannelMonitor(
                id: 1,
                name: "OpenAI 主渠道",
                provider: "openai",
                groupName: "OpenAI",
                model: "gpt-5.6-sol",
                status: "operational",
                latencyMilliseconds: 1_286,
                availability7Days: 99.98
            )
        ]
        subscriptions = [
            UserSubscriptionItem(
                id: 1,
                groupName: "OpenAI 专业订阅",
                status: "active",
                startsAt: now.addingTimeInterval(-86_400 * 12),
                expiresAt: now.addingTimeInterval(86_400 * 78),
                dailyUsage: 3.42,
                weeklyUsage: 18.36,
                monthlyUsage: 82.14,
                dailyLimit: 100,
                weeklyLimit: 550,
                monthlyLimit: 2_200,
                dailyResetInSeconds: 42_300,
                weeklyResetInSeconds: 214_500,
                monthlyResetInSeconds: 2_410_000
            )
        ]
        userProfile = UserProfileSummary(
            username: "dingyi",
            email: "dingyi@example.com",
            role: "user",
            status: "active",
            balance: 18.42,
            concurrency: 10,
            createdAt: now.addingTimeInterval(-86_400 * 31)
        )
    }

    /// 仅供离线视觉检查选择第一条脱敏示例记录，生产数据不会通过此入口被修改。
    func showQAPreviewUsageDetail() {
        portalUsageRecordDetail = portalUsageRecords.first
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
        apiKeys = []
        availableGroups = []
        portalUsageRecords = []
        portalUsageRecordDetail = nil
        portalUsagePage = 0
        portalUsageTotal = 0
        hasMorePortalUsageRecords = false
        isLoadingMorePortalUsage = false
        channelMonitors = []
        subscriptions = []
        userProfile = nil
        latestRedeemResult = nil
        portalErrorMessage = nil
        portalSuccessMessage = nil
        isLoadingPortal = false
        UserDefaults.standard.removeObject(forKey: PreferenceKey.consumptionAnalysisSnapshot)
    }

    /// 按需读取最近余额增加活动；列表只保留在内存中，避免持久化逐条账户记录。
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

    /// 按需读取 API 密钥列表，切换页面时保留上次成功结果以减少界面闪烁。
    func loadAPIKeys(force: Bool = false) async {
        guard force || apiKeys.isEmpty else { return }
        await performPortalRequest {
            let context = try await self.authenticatedClient()
            // 密钥与可用分组互不依赖，并行读取可缩短首次进入密钥和使用记录页面的等待时间。
            async let keysTask = context.client.fetchAPIKeys(token: context.token)
            async let groupsTask = try? context.client.fetchAvailableGroups(token: context.token)
            let (keys, groups) = try await (keysTask, groupsTask)
            self.apiKeys = keys
            self.availableGroups = groups ?? []
        }
    }

    /// 从第一页读取当前统计周期的使用记录，并保存服务端总数供滚动加载使用。
    func loadPortalUsageRecords(
        force: Bool = false,
        filters: PortalUsageFilters = .empty
    ) async {
        guard force || portalUsageRecords.isEmpty || filters != activePortalUsageFilters else { return }
        let timeZone = TimeZone(
            identifier: UserDefaults.standard.string(forKey: PreferenceKey.displayTimeZone) ?? ""
        ) ?? .current
        await performPortalRequest {
            let context = try await self.authenticatedClient()
            let page = try await context.client.fetchUsageRecords(
                token: context.token,
                period: self.usagePeriod,
                timeZone: timeZone,
                page: 1,
                pageSize: 50,
                filters: filters
            )
            self.activePortalUsageFilters = filters
            self.portalUsageRecords = page.records
            self.portalUsagePage = page.page
            self.portalUsageTotal = page.total
            self.hasMorePortalUsageRecords = page.page < page.pages
        }
    }

    /// 当列表接近底部时读取下一页，并按记录 ID 去重，避免网络重试造成重复行。
    func loadMorePortalUsageRecords(filters: PortalUsageFilters = .empty) async {
        guard hasMorePortalUsageRecords,
              !isLoadingMorePortalUsage,
              filters == activePortalUsageFilters else { return }
        let timeZone = TimeZone(
            identifier: UserDefaults.standard.string(forKey: PreferenceKey.displayTimeZone) ?? ""
        ) ?? .current
        isLoadingMorePortalUsage = true
        portalErrorMessage = nil
        defer { isLoadingMorePortalUsage = false }

        do {
            let context = try await authenticatedClient()
            let page = try await context.client.fetchUsageRecords(
                token: context.token,
                period: usagePeriod,
                timeZone: timeZone,
                page: portalUsagePage + 1,
                pageSize: 50,
                filters: filters
            )
            let existingIDs = Set(portalUsageRecords.map(\.id))
            portalUsageRecords.append(contentsOf: page.records.filter { !existingIDs.contains($0.id) })
            portalUsagePage = page.page
            portalUsageTotal = page.total
            hasMorePortalUsageRecords = page.page < page.pages
        } catch {
            portalErrorMessage = error.localizedDescription
        }
    }

    /// 读取并保存一条完整使用明细，详情面板可以先显示列表数据，再无闪烁地补齐服务端字段。
    func loadPortalUsageRecordDetail(_ record: PortalUsageRecord) async {
        portalUsageRecordDetail = record
        do {
            let context = try await authenticatedClient()
            portalUsageRecordDetail = try await context.client.fetchUsageRecord(token: context.token, id: record.id)
        } catch {
            // 明细接口失败时保留列表行已有数据，只在页面提示错误，不关闭用户正在查看的抽屉。
            portalErrorMessage = error.localizedDescription
        }
    }

    /// 关闭使用明细时只清理当前选择，不影响已加载的历史页。
    func clearPortalUsageRecordDetail() {
        portalUsageRecordDetail = nil
    }

    /// 读取普通用户可见的渠道健康状态；空数组表示管理员尚未配置监控。
    func loadChannelMonitors(force: Bool = false) async {
        guard force || channelMonitors.isEmpty else { return }
        await performPortalRequest {
            let context = try await self.authenticatedClient()
            self.channelMonitors = try await context.client.fetchChannelMonitors(token: context.token)
        }
    }

    /// 读取当前账户的订阅计划和实际使用量。
    func loadSubscriptions(force: Bool = false) async {
        guard force || subscriptions.isEmpty else { return }
        await performPortalRequest {
            let context = try await self.authenticatedClient()
            self.subscriptions = try await context.client.fetchSubscriptions(token: context.token)
        }
    }

    /// 读取最新个人资料，编辑成功后也使用此模型立即更新界面。
    func loadUserProfile(force: Bool = false) async {
        guard force || userProfile == nil else { return }
        await performPortalRequest {
            let context = try await self.authenticatedClient()
            self.userProfile = try await context.client.fetchUserProfile(token: context.token)
        }
    }

    /// 使用完整配置创建 API 密钥并重新加载列表，确保服务端最终状态和排序一致。
    func createAPIKey(configuration: APIKeyConfiguration) async -> Bool {
        let normalizedName = configuration.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            portalErrorMessage = "请输入密钥名称"
            return false
        }
        let normalized = APIKeyConfiguration(
            name: normalizedName,
            groupID: configuration.groupID,
            customKey: configuration.customKey?.trimmingCharacters(in: .whitespacesAndNewlines),
            ipWhitelist: configuration.ipWhitelist,
            ipBlacklist: configuration.ipBlacklist,
            quota: max(configuration.quota, 0),
            expiresInDays: configuration.expiresInDays,
            rateLimit5Hours: max(configuration.rateLimit5Hours, 0),
            rateLimit1Day: max(configuration.rateLimit1Day, 0),
            rateLimit7Days: max(configuration.rateLimit7Days, 0)
        )
        var succeeded = false
        await performPortalRequest {
            let context = try await self.authenticatedClient()
            _ = try await context.client.createAPIKey(token: context.token, configuration: normalized)
            self.apiKeys = try await context.client.fetchAPIKeys(token: context.token)
            self.portalSuccessMessage = "API 密钥已创建"
            succeeded = true
        }
        return succeeded
    }

    /// 为仅提供名称的旧调用保留兼容入口，内部仍统一走完整配置模型。
    func createAPIKey(name: String) async -> Bool {
        await createAPIKey(
            configuration: APIKeyConfiguration(
                name: name,
                groupID: availableGroups.first?.id,
                customKey: nil,
                ipWhitelist: [],
                ipBlacklist: [],
                quota: 0,
                expiresInDays: nil,
                rateLimit5Hours: 0,
                rateLimit1Day: 0,
                rateLimit7Days: 0
            )
        )
    }

    /// 编辑密钥的分组、限额和访问限制；到期时间暂时沿用服务端现有值，避免误清除。
    func updateAPIKey(_ key: UserAPIKey, configuration: APIKeyConfiguration, enabled: Bool) async -> Bool {
        var succeeded = false
        await performPortalRequest {
            let context = try await self.authenticatedClient()
            try await context.client.updateAPIKey(
                token: context.token,
                id: key.id,
                configuration: configuration,
                status: enabled ? "active" : "inactive"
            )
            self.apiKeys = try await context.client.fetchAPIKeys(token: context.token)
            self.portalSuccessMessage = "API 密钥已更新"
            succeeded = true
        }
        return succeeded
    }

    /// 切换 API 密钥状态；失败时保留当前列表并显示服务端错误。
    func setAPIKey(_ key: UserAPIKey, enabled: Bool) async {
        await performPortalRequest {
            let context = try await self.authenticatedClient()
            try await context.client.updateAPIKeyStatus(
                token: context.token,
                id: key.id,
                status: enabled ? "active" : "inactive"
            )
            self.apiKeys = try await context.client.fetchAPIKeys(token: context.token)
            self.portalSuccessMessage = enabled ? "密钥已启用" : "密钥已停用"
        }
    }

    /// 删除 API 密钥；界面层会在调用前要求用户确认具体密钥名称。
    func deleteAPIKey(_ key: UserAPIKey) async {
        await performPortalRequest {
            let context = try await self.authenticatedClient()
            try await context.client.deleteAPIKey(token: context.token, id: key.id)
            self.apiKeys.removeAll { $0.id == key.id }
            self.portalSuccessMessage = "API 密钥已删除"
        }
    }

    /// 兑换成功后同步仪表盘、兑换活动和订阅，覆盖余额、并发及订阅三种兑换类型。
    func redeem(code: String) async -> Bool {
        let normalizedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCode.isEmpty else {
            portalErrorMessage = "请输入兑换码"
            return false
        }
        var succeeded = false
        await performPortalRequest {
            let context = try await self.authenticatedClient()
            self.latestRedeemResult = try await context.client.redeem(token: context.token, code: normalizedCode)
            self.portalSuccessMessage = self.latestRedeemResult?.message ?? "兑换成功"
            succeeded = true
        }
        if succeeded {
            await refresh(showLoading: false)
            await loadBalanceActivities(force: true)
            await loadSubscriptions(force: true)
        }
        return succeeded
    }

    /// 更新用户名并保留服务端返回的完整账户摘要。
    func updateUsername(_ username: String) async -> Bool {
        let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedUsername.isEmpty else {
            portalErrorMessage = "用户名不能为空"
            return false
        }
        var succeeded = false
        await performPortalRequest {
            let context = try await self.authenticatedClient()
            self.userProfile = try await context.client.updateUsername(
                token: context.token,
                username: normalizedUsername
            )
            self.portalSuccessMessage = "个人资料已更新"
            succeeded = true
        }
        return succeeded
    }

    /// 修改密码前校验最小长度和两次输入，避免无效请求到达服务端。
    func changePassword(oldPassword: String, newPassword: String, confirmation: String) async -> Bool {
        guard newPassword.count >= 8 else {
            portalErrorMessage = "新密码至少需要 8 个字符"
            return false
        }
        guard newPassword == confirmation else {
            portalErrorMessage = "两次输入的新密码不一致"
            return false
        }
        var succeeded = false
        await performPortalRequest {
            let context = try await self.authenticatedClient()
            try await context.client.changePassword(
                token: context.token,
                oldPassword: oldPassword,
                newPassword: newPassword
            )
            self.portalSuccessMessage = "密码已修改"
            succeeded = true
        }
        return succeeded
    }

    /// 清理页面级提示，避免成功或错误信息在切换页面后继续显示。
    func clearPortalMessage() {
        portalErrorMessage = nil
        portalSuccessMessage = nil
    }

    /// 集中处理用户端页面的加载状态和错误，短暂失败不会清空上次成功数据。
    private func performPortalRequest(_ operation: () async throws -> Void) async {
        guard !isLoadingPortal else { return }
        isLoadingPortal = true
        portalErrorMessage = nil
        portalSuccessMessage = nil
        defer { isLoadingPortal = false }
        do {
            try await operation()
        } catch {
            portalErrorMessage = error.localizedDescription
        }
    }

    /// 返回可用客户端和访问令牌；令牌即将过期时先刷新并安全写回钥匙串。
    private func authenticatedClient() async throws -> (client: Sub2APIClient, token: String) {
        guard var activeSession = session else { throw CodexToolsError.invalidResponse }
        var client = try Sub2APIClient(serverURL: activeSession.serverURL)
        if activeSession.needsRefresh() {
            activeSession = try await client.refresh(session: activeSession)
            try keychain.save(activeSession)
            session = activeSession
            client = try Sub2APIClient(serverURL: activeSession.serverURL)
        }
        return (client, activeSession.accessToken)
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
                title: "SubPilot 社区重置提醒",
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
                title: "SubPilot 余额提醒",
                body: "当前余额 \(balance.formatted(.number.precision(.fractionLength(2))))，已低于设定阈值。"
            )
        }

        let quotaThreshold = UserDefaults.standard.double(forKey: PreferenceKey.quotaThreshold)
        if let remaining = snapshot.quotaRemainingPercent, remaining <= quotaThreshold {
            await Self.sendNotification(
                title: "SubPilot 额度提醒",
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
