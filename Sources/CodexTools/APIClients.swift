/**
 * 文件说明：Sub2API 与 Codex Resets 的只读数据请求封装
 * 作者：dingyi60(Codex)
 * 创建时间：2026-08-25
 */

import Foundation

/// 负责 Sub2API 登录、令牌刷新和用量数据读取。
struct Sub2APIClient: Sendable {
    private let baseURL: URL

    /// 校验并规范化用户输入的服务器地址，防止请求被拼到错误的主机或路径。
    init(serverURL: URL) throws {
        guard serverURL.scheme == "https", serverURL.host != nil else {
            throw CodexToolsError.invalidServerURL
        }
        baseURL = serverURL
    }

    /// 使用邮箱密码换取令牌；密码只存在于当前请求内，不会持久化到本机。
    func login(email: String, password: String) async throws -> LoginOutcome {
        let body: [String: String] = [
            "email": email,
            "password": password
        ]
        let bodyData = try JSONEncoder().encode(body)
        let response: LoginResponse = try await request(
            path: "auth/login",
            method: "POST",
            token: nil,
            body: bodyData
        )

        if response.requiresTwoFactor {
            guard let tempToken = response.tempToken, !tempToken.isEmpty else {
                throw CodexToolsError.invalidResponse
            }
            return .requiresTwoFactor(
                PendingTwoFactor(
                    serverURL: baseURL,
                    tempToken: tempToken,
                    maskedEmail: response.maskedEmail
                )
            )
        }

        return .authenticated(try makeSession(from: response))
    }

    /// 使用临时令牌和 6 位 TOTP 验证码完成登录第二步。
    func completeTwoFactor(tempToken: String, code: String) async throws -> AuthSession {
        let body: [String: String] = [
            "temp_token": tempToken,
            "totp_code": code
        ]
        let response: LoginResponse = try await request(
            path: "auth/login/2fa",
            method: "POST",
            token: nil,
            body: try JSONEncoder().encode(body)
        )
        return try makeSession(from: response)
    }

    /// 从已完成认证的响应创建会话，并拒绝缺少访问令牌的异常成功响应。
    private func makeSession(from response: LoginResponse) throws -> AuthSession {
        guard let accessToken = response.accessToken, !accessToken.isEmpty else {
            throw CodexToolsError.invalidResponse
        }
        let userID = response.user?.firstValue(forKeys: ["id", "user_id", "uuid"])?.stringValue

        return AuthSession(
            serverURL: baseURL,
            accessToken: accessToken,
            refreshToken: response.refreshToken,
            expiresAt: response.expiresIn.map { Date().addingTimeInterval($0) },
            userID: userID
        )
    }

    /// 使用刷新令牌续期访问令牌，避免定时刷新过程中频繁要求重新输入密码。
    func refresh(session: AuthSession) async throws -> AuthSession {
        guard let refreshToken = session.refreshToken else {
            throw CodexToolsError.missingRefreshToken
        }
        let bodyData = try JSONEncoder().encode(["refresh_token": refreshToken])
        let response: LoginResponse = try await request(
            path: "auth/refresh",
            method: "POST",
            token: nil,
            body: bodyData
        )

        guard let accessToken = response.accessToken, !accessToken.isEmpty else {
            throw CodexToolsError.invalidResponse
        }

        return AuthSession(
            serverURL: session.serverURL,
            accessToken: accessToken,
            refreshToken: response.refreshToken ?? refreshToken,
            expiresAt: response.expiresIn.map { Date().addingTimeInterval($0) },
            userID: session.userID
        )
    }

    /// 并行读取各块数据；用明确日期和时区统一 Token、消费、请求与模型的统计口径。
    func fetchDashboard(
        token: String,
        period: UsagePeriod,
        timeZone: TimeZone
    ) async throws -> DashboardSnapshot {
        let dateQuery = period.dateQuery(timeZone: timeZone)
        async let profile = optionalJSON(path: "user/profile", token: token)
        async let subscriptions = optionalJSON(path: "subscriptions/summary", token: token)
        async let progress = optionalJSON(path: "subscriptions/progress", token: token)
        async let platformQuotas = optionalJSON(path: "user/platform-quotas", token: token)
        async let usage = optionalJSON(path: "usage/stats", token: token, query: dateQuery)
        async let models = optionalJSON(path: "usage/dashboard/models", token: token, query: dateQuery)

        let results = await (profile, subscriptions, progress, platformQuotas, usage, models)
        guard [results.0, results.1, results.2, results.3, results.4, results.5].contains(where: { $0 != nil }) else {
            throw CodexToolsError.invalidResponse
        }

        return DashboardParser.parse(
            profile: results.0,
            subscriptionSummary: results.1,
            subscriptionProgress: results.2,
            platformQuotas: results.3,
            usageStats: results.4,
            modelStats: results.5,
            usagePeriod: period
        )
    }

    /// 分页读取最近一小时真实调用；按时间倒序，在遇到窗口起点前的记录后立即停止。
    func fetchRecentUsageRecords(
        token: String,
        timeZone: TimeZone,
        referenceDate: Date = Date()
    ) async throws -> (records: [UsageRecord], isTruncated: Bool) {
        let windowStart = referenceDate.addingTimeInterval(-3_600)
        let pageSize = 1_000
        let maximumPages = 10
        var collected: [UsageRecord] = []

        for page in 1...maximumPages {
            var query = Self.dateRangeQuery(
                start: windowStart,
                end: referenceDate,
                timeZone: timeZone
            )
            query["page"] = String(page)
            query["page_size"] = String(pageSize)
            query["sort_by"] = "created_at"
            query["sort_order"] = "desc"

            let response: JSONValue = try await request(
                path: "usage",
                method: "GET",
                token: token,
                query: query,
                body: nil
            )
            let parsed = UsageRecordParser.parsePage(response)
            let recordsInWindow = parsed.records.filter {
                $0.createdAt >= windowStart && $0.createdAt <= referenceDate
            }
            collected.append(contentsOf: recordsInWindow)

            let reachedWindowStart = parsed.records.contains { $0.createdAt < windowStart }
            if reachedWindowStart || page >= parsed.pages || parsed.records.isEmpty {
                return (collected, false)
            }
        }

        // 十页仍未越过窗口起点说明一小时内超过 10,000 条，需要明确标记为不完整。
        return (collected, true)
    }

    /// 并行读取兑换和充值记录，只返回会增加账户余额的最近活动。
    func fetchBalanceActivities(token: String, limit: Int = 20) async throws -> [BalanceActivity] {
        let normalizedLimit = min(max(limit, 1), 100)
        async let redeem = optionalJSON(path: "redeem/history", token: token)
        async let payments = optionalJSON(
            path: "payment/orders/my",
            token: token,
            query: [
                "page": "1", "page_size": String(normalizedLimit),
                "status": "completed", "order_type": "balance"
            ]
        )
        let responses = await (redeem, payments)
        guard responses.0 != nil || responses.1 != nil else {
            throw CodexToolsError.invalidResponse
        }
        return BalanceActivityParser.parse(
            redeemResponse: responses.0,
            paymentResponse: responses.1,
            limit: normalizedLimit
        )
    }

    /// 读取当前用户的 API 密钥列表，分页上限 100 足以覆盖桌面端的常规管理场景。
    func fetchAPIKeys(token: String) async throws -> [UserAPIKey] {
        let response: JSONValue = try await request(
            path: "keys",
            method: "GET",
            token: token,
            query: ["page": "1", "page_size": "100", "sort_by": "created_at", "sort_order": "desc"],
            body: nil
        )
        return UserPortalParser.apiKeys(from: response)
    }

    /// 读取当前用户可使用的分组，创建密钥时使用真实分组 ID 而不是名称猜测。
    func fetchAvailableGroups(token: String) async throws -> [AvailableUserGroup] {
        let response: JSONValue = try await request(
            path: "groups/available",
            method: "GET",
            token: token,
            body: nil
        )
        return UserPortalParser.availableGroups(from: response)
    }

    /// 使用完整配置创建 API 密钥，限额、过期、IP 和周期限制与网页端字段保持一致。
    func createAPIKey(token: String, configuration: APIKeyConfiguration) async throws -> UserAPIKey {
        let response: JSONValue = try await request(
            path: "keys",
            method: "POST",
            token: token,
            body: try JSONEncoder().encode(configuration)
        )
        guard let key = UserPortalParser.apiKeys(from: .array([response])).first else {
            throw CodexToolsError.invalidResponse
        }
        return key
    }

    /// 编辑现有 API 密钥；自定义密钥只能在创建时设置，因此更新请求会主动忽略该字段。
    func updateAPIKey(token: String, id: Int, configuration: APIKeyConfiguration, status: String) async throws {
        let body = APIKeyUpdatePayload(
            name: configuration.name,
            groupID: configuration.groupID,
            status: status,
            ipWhitelist: configuration.ipWhitelist,
            ipBlacklist: configuration.ipBlacklist,
            quota: configuration.quota,
            rateLimit5Hours: configuration.rateLimit5Hours,
            rateLimit1Day: configuration.rateLimit1Day,
            rateLimit7Days: configuration.rateLimit7Days
        )
        let _: JSONValue = try await request(
            path: "keys/\(id)",
            method: "PUT",
            token: token,
            body: try JSONEncoder().encode(body)
        )
    }

    /// 启用或停用 API 密钥，服务端仍保留密钥和历史用量。
    func updateAPIKeyStatus(token: String, id: Int, status: String) async throws {
        let _: JSONValue = try await request(
            path: "keys/\(id)",
            method: "PUT",
            token: token,
            body: try JSONEncoder().encode(["status": status])
        )
    }

    /// 永久删除指定 API 密钥；调用方必须在界面层先显示二次确认。
    func deleteAPIKey(token: String, id: Int) async throws {
        let _: JSONValue = try await request(
            path: "keys/\(id)",
            method: "DELETE",
            token: token,
            body: nil
        )
    }

    /// 按当前周期、筛选条件和页码读取使用记录，返回服务端总数供滚动加载历史数据。
    func fetchUsageRecords(
        token: String,
        period: UsagePeriod,
        timeZone: TimeZone,
        page: Int,
        pageSize: Int,
        filters: PortalUsageFilters
    ) async throws -> PortalUsagePage {
        var query = period.dateQuery(timeZone: timeZone)
        query["page"] = String(max(page, 1))
        query["page_size"] = String(min(max(pageSize, 20), 200))
        query["sort_by"] = "created_at"
        query["sort_order"] = "desc"
        if let value = filters.apiKeyID { query["api_key_id"] = String(value) }
        if let value = filters.model, !value.isEmpty { query["model"] = value }
        if let value = filters.groupID { query["group_id"] = String(value) }
        if let value = filters.requestType, !value.isEmpty { query["request_type"] = value }
        if let value = filters.billingType { query["billing_type"] = String(value) }
        if let value = filters.billingMode, !value.isEmpty { query["billing_mode"] = value }
        let response: JSONValue = try await request(
            path: "usage",
            method: "GET",
            token: token,
            query: query,
            body: nil
        )
        return UserPortalParser.usagePage(from: response)
    }

    /// 读取单条使用记录的完整计费明细，列表字段不足时详情面板仍能展示完整数据。
    func fetchUsageRecord(token: String, id: Int) async throws -> PortalUsageRecord {
        let response: JSONValue = try await request(
            path: "usage/\(id)",
            method: "GET",
            token: token,
            body: nil
        )
        guard let record = UserPortalParser.usageRecords(from: .array([response])).first else {
            throw CodexToolsError.invalidResponse
        }
        return record
    }

    /// 读取管理员允许普通用户查看的渠道健康状态，不请求管理员监控接口。
    func fetchChannelMonitors(token: String) async throws -> [UserChannelMonitor] {
        let response: JSONValue = try await request(
            path: "channel-monitors",
            method: "GET",
            token: token,
            body: nil
        )
        return UserPortalParser.channelMonitors(from: response)
    }

    /// 读取当前用户的全部订阅，包含已过期或暂停状态，便于核对历史计划。
    func fetchSubscriptions(token: String) async throws -> [UserSubscriptionItem] {
        async let subscriptions: JSONValue = request(
            path: "subscriptions",
            method: "GET",
            token: token,
            body: nil
        )
        async let progress = optionalJSON(path: "subscriptions/progress", token: token)
        let values = try await (subscriptions, progress)
        return UserPortalParser.subscriptions(from: values.0, progressResponse: values.1)
    }

    /// 读取个人资料摘要，供原生账户页面展示和编辑用户名。
    func fetchUserProfile(token: String) async throws -> UserProfileSummary {
        let response: JSONValue = try await request(
            path: "user/profile",
            method: "GET",
            token: token,
            body: nil
        )
        guard let profile = UserPortalParser.profile(from: response) else {
            throw CodexToolsError.invalidResponse
        }
        return profile
    }

    /// 提交兑换码并解析余额、并发或订阅变化；兑换码不会写入本地日志。
    func redeem(token: String, code: String) async throws -> RedeemResult {
        let response: JSONValue = try await request(
            path: "redeem",
            method: "POST",
            token: token,
            body: try JSONEncoder().encode(["code": code])
        )
        return UserPortalParser.redeemResult(from: response)
    }

    /// 更新当前账户用户名，邮箱和认证绑定仍由 Sub2API 服务端负责校验。
    func updateUsername(token: String, username: String) async throws -> UserProfileSummary {
        let response: JSONValue = try await request(
            path: "user",
            method: "PUT",
            token: token,
            body: try JSONEncoder().encode(["username": username])
        )
        guard let profile = UserPortalParser.profile(from: response) else {
            throw CodexToolsError.invalidResponse
        }
        return profile
    }

    /// 修改当前账户密码；密码仅存在于这次 HTTPS（加密网页传输协议）请求内。
    func changePassword(token: String, oldPassword: String, newPassword: String) async throws {
        let _: JSONValue = try await request(
            path: "user/password",
            method: "PUT",
            token: token,
            body: try JSONEncoder().encode([
                "old_password": oldPassword,
                "new_password": newPassword
            ])
        )
    }

    /// 对非关键统计接口执行宽容请求，失败时返回空值而不是中断整个悬浮层刷新。
    private func optionalJSON(path: String, token: String, query: [String: String] = [:]) async -> JSONValue? {
        try? await request(path: path, method: "GET", token: token, query: query, body: nil)
    }

    /// 为跨午夜的一小时窗口生成本地日期边界，服务端再用记录时间完成精确过滤。
    private static func dateRangeQuery(start: Date, end: Date, timeZone: TimeZone) -> [String: String] {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return [
            "start_date": formatter.string(from: start),
            "end_date": formatter.string(from: end),
            "timezone": timeZone.identifier
        ]
    }

    /// 构造统一的 `/api/v1` 请求并解码响应，集中处理鉴权头和错误消息。
    private func request<Response: Decodable & Sendable>(
        path: String,
        method: String,
        token: String?,
        query: [String: String] = [:],
        body: Data?
    ) async throws -> Response {
        var components = URLComponents(
            url: baseURL.appending(path: "api/v1/\(path)"),
            resolvingAgainstBaseURL: false
        )
        var mergedQuery = query
        if method == "GET", mergedQuery["timezone"] == nil {
            // 未显式指定统计时区的普通 GET（读取请求）仍沿用 Mac 当前时区。
            mergedQuery["timezone"] = TimeZone.current.identifier
        }
        components?.queryItems = mergedQuery.isEmpty
            ? nil
            : mergedQuery.sorted(by: { $0.key < $1.key }).map(URLQueryItem.init)

        guard let url = components?.url else {
            throw CodexToolsError.invalidServerURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("SubPilot/0.2", forHTTPHeaderField: "User-Agent")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CodexToolsError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw CodexToolsError.server(
                statusCode: httpResponse.statusCode,
                message: Self.serverMessage(from: data)
            )
        }

        do {
            return try Self.decoder.decode(Response.self, from: data)
        } catch {
            throw CodexToolsError.invalidResponse
        }
    }

    /// 从不同格式的错误响应中提取最有用的服务端提示。
    private static func serverMessage(from data: Data) -> String {
        guard let value = try? decoder.decode(JSONValue.self, from: data) else {
            return "服务器未提供错误详情"
        }
        return value.firstValue(forKeys: ["message", "detail", "error"])?.stringValue
            ?? "服务器未提供错误详情"
    }

    /// 共用 JSON 解码器，日期策略与 Sub2API 的普通数据字段保持兼容。
    private static let decoder = JSONDecoder()
}

/// 表示密钥编辑请求；自定义密钥只能在创建时设置，因此这里不包含该敏感字段。
private struct APIKeyUpdatePayload: Encodable {
    let name: String
    let groupID: Int?
    let status: String
    let ipWhitelist: [String]
    let ipBlacklist: [String]
    let quota: Double
    let rateLimit5Hours: Double
    let rateLimit1Day: Double
    let rateLimit7Days: Double

    enum CodingKeys: String, CodingKey {
        case name
        case groupID = "group_id"
        case status
        case ipWhitelist = "ip_whitelist"
        case ipBlacklist = "ip_blacklist"
        case quota
        case rateLimit5Hours = "rate_limit_5h"
        case rateLimit1Day = "rate_limit_1d"
        case rateLimit7Days = "rate_limit_7d"
    }
}

/// 负责读取 codex-resets.com 的公开只读重置状态。
struct CodexResetsClient: Sendable {
    private let statusURL = URL(string: "https://codex-resets.com/api/v1/status")!

    /// 获取最近一次全局重置公告；该数据是社区追踪结果，不代表具体账户的官方账单记录。
    func fetchStatus() async throws -> CodexResetStatusResponse {
        var request = URLRequest(url: statusURL)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("SubPilot/0.2", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw CodexToolsError.invalidResponse
        }

        do {
            return try Self.decodeStatus(data)
        } catch {
            throw CodexToolsError.invalidResponse
        }
    }

    /// 独立解码公共接口响应，便于用固定样本测试毫秒时间和字段映射。
    static func decodeStatus(_ data: Data) throws -> CodexResetStatusResponse {
        try decoder.decode(CodexResetStatusResponse.self, from: data)
    }

    /// 同时兼容带毫秒和不带毫秒的 ISO 8601 时间。
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) {
                return date
            }
            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            if let date = standard.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "无法解析 ISO 8601 时间：\(value)"
            )
        }
        return decoder
    }()
}
