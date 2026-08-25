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
        async let usage = optionalJSON(path: "usage/stats", token: token, query: dateQuery)
        async let models = optionalJSON(path: "usage/dashboard/models", token: token, query: dateQuery)

        let results = await (profile, subscriptions, progress, usage, models)
        guard [results.0, results.1, results.2, results.3, results.4].contains(where: { $0 != nil }) else {
            throw CodexToolsError.invalidResponse
        }

        return DashboardParser.parse(
            profile: results.0,
            subscriptionSummary: results.1,
            subscriptionProgress: results.2,
            usageStats: results.3,
            modelStats: results.4,
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
        request.setValue("CodexTools/0.1", forHTTPHeaderField: "User-Agent")
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

/// 负责读取 codex-resets.com 的公开只读重置状态。
struct CodexResetsClient: Sendable {
    private let statusURL = URL(string: "https://codex-resets.com/api/v1/status")!

    /// 获取最近一次全局重置公告；该数据是社区追踪结果，不代表具体账户的官方账单记录。
    func fetchStatus() async throws -> CodexResetStatusResponse {
        var request = URLRequest(url: statusURL)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CodexTools/0.1", forHTTPHeaderField: "User-Agent")

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
