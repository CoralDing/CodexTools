/**
 * 文件说明：Sub2API 用户端功能的轻量界面模型与宽容解析逻辑
 * 作者：dingyi60(Codex)
 * 创建时间：2026-08-28
 */

import Foundation

/// 表示当前用户的一枚 API 密钥；密钥内容只保存在内存中，不额外持久化。
struct UserAPIKey: Sendable, Equatable, Identifiable {
    let id: Int
    let name: String
    let key: String
    let groupName: String?
    let currentConcurrency: Int
    let quota: Double
    let quotaUsed: Double
    let status: String
    let expiresAt: Date?
    let createdAt: Date?
    let lastUsedAt: Date?
    let ipWhitelist: [String]
    let ipBlacklist: [String]
    let rateLimit5Hours: Double
    let rateLimit1Day: Double
    let rateLimit7Days: Double
    let usage5Hours: Double
    let usage1Day: Double
    let usage7Days: Double

    /// 服务端用 0 表示不限额，界面按这一语义统一显示。
    var quotaProgress: Double? {
        guard quota > 0 else { return nil }
        return min(max(quotaUsed / quota, 0), 1)
    }
}

/// 表示当前用户可选的服务分组，创建和编辑密钥时必须使用服务端真实分组 ID。
struct AvailableUserGroup: Sendable, Equatable, Identifiable {
    let id: Int
    let name: String
    let platform: String?
}

/// 集中保存 API 密钥创建或编辑参数，避免视图直接拼接容易遗漏的请求字段。
struct APIKeyConfiguration: Sendable, Equatable, Encodable {
    let name: String
    let groupID: Int?
    let customKey: String?
    let ipWhitelist: [String]
    let ipBlacklist: [String]
    let quota: Double
    let expiresInDays: Int?
    let rateLimit5Hours: Double
    let rateLimit1Day: Double
    let rateLimit7Days: Double

    enum CodingKeys: String, CodingKey {
        case name
        case groupID = "group_id"
        case customKey = "custom_key"
        case ipWhitelist = "ip_whitelist"
        case ipBlacklist = "ip_blacklist"
        case quota
        case expiresInDays = "expires_in_days"
        case rateLimit5Hours = "rate_limit_5h"
        case rateLimit1Day = "rate_limit_1d"
        case rateLimit7Days = "rate_limit_7d"
    }
}

/// 表示使用记录表的一行，保留计费、延迟和筛选时最常用的信息。
struct PortalUsageRecord: Sendable, Equatable, Identifiable {
    let id: Int
    let apiKeyName: String
    let model: String
    let endpoint: String?
    let groupName: String?
    let totalTokens: Double
    let standardCost: Double
    let actualCost: Double
    let multiplier: Double?
    let durationMilliseconds: Double?
    let createdAt: Date
    let requestID: String
    let inputTokens: Double
    let outputTokens: Double
    let cacheCreationTokens: Double
    let cacheReadTokens: Double
    let inputCost: Double
    let outputCost: Double
    let cacheCreationCost: Double
    let cacheReadCost: Double
    let requestType: String?
    let billingType: Int?
    let billingMode: String?
    let isStream: Bool
    let firstTokenMilliseconds: Double?

    /// 输入和输出分开显示，便于发现上下文过长或输出异常的问题。
    var inputOutputDescription: String {
        "\(UsageFormatter.compactTokens(inputTokens)) / \(UsageFormatter.compactTokens(outputTokens))"
    }
}

/// 表示使用记录的服务端筛选条件；空字段不会进入 URL 查询参数。
struct PortalUsageFilters: Sendable, Equatable {
    var apiKeyID: Int?
    var model: String?
    var groupID: Int?
    var requestType: String?
    var billingType: Int?
    var billingMode: String?

    static let empty = PortalUsageFilters()
}

/// 表示一页使用记录及服务端分页元数据，用于滚动加载时判断是否还有历史数据。
struct PortalUsagePage: Sendable, Equatable {
    let records: [PortalUsageRecord]
    let page: Int
    let pageSize: Int
    let total: Int
    let pages: Int
}

/// 表示用户可查看的一条渠道健康状态，渠道状态页面不会暴露上游账号信息。
struct UserChannelMonitor: Sendable, Equatable, Identifiable {
    let id: Int
    let name: String
    let provider: String
    let groupName: String
    let model: String
    let status: String
    let latencyMilliseconds: Double?
    let availability7Days: Double
}

/// 表示当前用户的一项订阅及其日、周、月实际使用情况。
struct UserSubscriptionItem: Sendable, Equatable, Identifiable {
    let id: Int
    let groupName: String
    let status: String
    let startsAt: Date?
    let expiresAt: Date?
    let dailyUsage: Double
    let weeklyUsage: Double
    let monthlyUsage: Double
    let dailyLimit: Double?
    let weeklyLimit: Double?
    let monthlyLimit: Double?
    let dailyResetInSeconds: Double?
    let weeklyResetInSeconds: Double?
    let monthlyResetInSeconds: Double?
}

/// 表示个人资料页需要的账户信息，敏感密码从不进入该模型。
struct UserProfileSummary: Sendable, Equatable {
    let username: String
    let email: String
    let role: String
    let status: String
    let balance: Double
    let concurrency: Int
    let createdAt: Date?
}

/// 表示兑换成功后服务端返回的账户变化，便于界面给出明确反馈。
struct RedeemResult: Sendable, Equatable {
    let message: String
    let type: String
    let value: Double
    let newBalance: Double?
    let newConcurrency: Int?
}

/// 集中解析 Sub2API 用户端接口，兼容响应直接返回数组或包裹在 `data/items` 中。
enum UserPortalParser {
    /// 解析 API 密钥列表；缺失 ID 的异常记录会被跳过，避免操作命令指向错误对象。
    static func apiKeys(from response: JSONValue) -> [UserAPIKey] {
        return responseItems(response).compactMap { item -> UserAPIKey? in
            guard let id = integer(item, "id") else { return nil }
            return UserAPIKey(
                id: id,
                name: string(item, "name") ?? "未命名密钥",
                key: string(item, "key") ?? "",
                groupName: item.directValue(forKey: "group")?.directValue(forKey: "name")?.stringValue,
                currentConcurrency: integer(item, "current_concurrency") ?? 0,
                quota: number(item, "quota"),
                quotaUsed: number(item, "quota_used"),
                status: string(item, "status") ?? "unknown",
                expiresAt: date(item, "expires_at"),
                createdAt: date(item, "created_at"),
                lastUsedAt: date(item, "last_used_at"),
                ipWhitelist: strings(item, "ip_whitelist"),
                ipBlacklist: strings(item, "ip_blacklist"),
                rateLimit5Hours: number(item, "rate_limit_5h"),
                rateLimit1Day: number(item, "rate_limit_1d"),
                rateLimit7Days: number(item, "rate_limit_7d"),
                usage5Hours: number(item, "usage_5h"),
                usage1Day: number(item, "usage_1d"),
                usage7Days: number(item, "usage_7d")
            )
        }
    }

    /// 解析当前用户可以选择的分组，兼容 `groups`、`items` 或直接数组结构。
    static func availableGroups(from response: JSONValue) -> [AvailableUserGroup] {
        let items = responseItems(response).isEmpty
            ? response.firstValue(forKeys: ["groups"])?.arrayValue ?? []
            : responseItems(response)
        return items.compactMap { item in
            guard let id = integer(item, "id"), let name = string(item, "name") else { return nil }
            return AvailableUserGroup(id: id, name: name, platform: string(item, "platform"))
        }
    }

    /// 解析详细使用记录，并把输入、输出和两类缓存 Token 合并成同一口径。
    static func usageRecords(from response: JSONValue) -> [PortalUsageRecord] {
        usagePage(from: response).records
    }

    /// 解析使用记录及页数、总数；服务端没有返回总数时使用当前页数量安全回退。
    static func usagePage(from response: JSONValue) -> PortalUsagePage {
        let records: [PortalUsageRecord] = responseItems(response).compactMap { item -> PortalUsageRecord? in
            guard let createdAt = date(item, "created_at") else { return nil }
            let id = integer(item, "id") ?? Int(createdAt.timeIntervalSince1970)
            let inputTokens = number(item, "input_tokens")
            let outputTokens = number(item, "output_tokens")
            let cacheCreationTokens = number(item, "cache_creation_tokens")
            let cacheReadTokens = number(item, "cache_read_tokens")
            return PortalUsageRecord(
                id: id,
                apiKeyName: item.directValue(forKey: "api_key")?.directValue(forKey: "name")?.stringValue
                    ?? "密钥 #\(integer(item, "api_key_id") ?? 0)",
                model: string(item, "model") ?? "未知模型",
                endpoint: string(item, "inbound_endpoint"),
                groupName: item.directValue(forKey: "group")?.directValue(forKey: "name")?.stringValue,
                totalTokens: inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens,
                standardCost: number(item, "total_cost"),
                actualCost: number(item, "actual_cost"),
                multiplier: item.directValue(forKey: "rate_multiplier")?.doubleValue,
                durationMilliseconds: item.directValue(forKey: "duration_ms")?.doubleValue,
                createdAt: createdAt,
                requestID: string(item, "request_id") ?? "usage-\(id)",
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                cacheCreationTokens: cacheCreationTokens,
                cacheReadTokens: cacheReadTokens,
                inputCost: number(item, "input_cost"),
                outputCost: number(item, "output_cost"),
                cacheCreationCost: number(item, "cache_creation_cost"),
                cacheReadCost: number(item, "cache_read_cost"),
                requestType: string(item, "request_type"),
                billingType: integer(item, "billing_type"),
                billingMode: string(item, "billing_mode"),
                isStream: item.directValue(forKey: "stream")?.boolValue ?? false,
                firstTokenMilliseconds: item.directValue(forKey: "first_token_ms")?.doubleValue
            )
        }
        let page = max(Int(response.firstValue(forKeys: ["page"])?.doubleValue ?? 1), 1)
        let pageSize = max(Int(response.firstValue(forKeys: ["page_size"])?.doubleValue ?? Double(max(records.count, 1))), 1)
        let total = max(Int(response.firstValue(forKeys: ["total"])?.doubleValue ?? Double(records.count)), records.count)
        let pages = max(Int(response.firstValue(forKeys: ["pages", "total_pages"])?.doubleValue ?? ceil(Double(total) / Double(pageSize))), 1)
        return PortalUsagePage(records: records, page: page, pageSize: pageSize, total: total, pages: pages)
    }

    /// 解析渠道监控列表；部署未配置监控时自然返回空数组。
    static func channelMonitors(from response: JSONValue) -> [UserChannelMonitor] {
        return responseItems(response).compactMap { item -> UserChannelMonitor? in
            guard let id = integer(item, "id") else { return nil }
            return UserChannelMonitor(
                id: id,
                name: string(item, "name") ?? "未命名渠道",
                provider: string(item, "provider") ?? "unknown",
                groupName: string(item, "group_name") ?? "未分组",
                model: string(item, "primary_model") ?? "—",
                status: string(item, "primary_status") ?? "unknown",
                latencyMilliseconds: item.directValue(forKey: "primary_latency_ms")?.doubleValue,
                availability7Days: number(item, "availability_7d")
            )
        }
    }

    /// 解析订阅列表；额度上限来自平台额度或分组配置，订阅页先展示服务端提供的实际用量。
    static func subscriptions(from response: JSONValue, progressResponse: JSONValue? = nil) -> [UserSubscriptionItem] {
        let progressItems = progressResponse.map(responseItems) ?? []
        let progressByID = Dictionary(uniqueKeysWithValues: progressItems.compactMap { item -> (Int, JSONValue)? in
            guard let id = integer(item, "subscription_id") else { return nil }
            return (id, item)
        })
        return responseItems(response).compactMap { item -> UserSubscriptionItem? in
            guard let id = integer(item, "id") else { return nil }
            let group = item.directValue(forKey: "group")
            let progress = progressByID[id]
            let daily = progress?.directValue(forKey: "daily")
            let weekly = progress?.directValue(forKey: "weekly")
            let monthly = progress?.directValue(forKey: "monthly")
            return UserSubscriptionItem(
                id: id,
                groupName: group?.directValue(forKey: "name")?.stringValue ?? "订阅 #\(id)",
                status: string(item, "status") ?? "unknown",
                startsAt: date(item, "starts_at"),
                expiresAt: progress?.directValue(forKey: "expires_at")?.stringValue.flatMap(parseDate) ?? date(item, "expires_at"),
                dailyUsage: daily?.directValue(forKey: "used")?.doubleValue ?? number(item, "daily_usage_usd"),
                weeklyUsage: weekly?.directValue(forKey: "used")?.doubleValue ?? number(item, "weekly_usage_usd"),
                monthlyUsage: monthly?.directValue(forKey: "used")?.doubleValue ?? number(item, "monthly_usage_usd"),
                dailyLimit: daily?.directValue(forKey: "limit")?.doubleValue ?? group?.directValue(forKey: "daily_limit_usd")?.doubleValue,
                weeklyLimit: weekly?.directValue(forKey: "limit")?.doubleValue ?? group?.directValue(forKey: "weekly_limit_usd")?.doubleValue,
                monthlyLimit: monthly?.directValue(forKey: "limit")?.doubleValue ?? group?.directValue(forKey: "monthly_limit_usd")?.doubleValue,
                dailyResetInSeconds: daily?.directValue(forKey: "reset_in_seconds")?.doubleValue,
                weeklyResetInSeconds: weekly?.directValue(forKey: "reset_in_seconds")?.doubleValue,
                monthlyResetInSeconds: monthly?.directValue(forKey: "reset_in_seconds")?.doubleValue
            )
        }
    }

    /// 解析个人资料，只有邮箱和用户名等用户本就可见的信息进入内存状态。
    static func profile(from response: JSONValue) -> UserProfileSummary? {
        guard let email = response.firstValue(forKeys: ["email"])?.stringValue else { return nil }
        return UserProfileSummary(
            username: response.firstValue(forKeys: ["username"])?.stringValue ?? email,
            email: email,
            role: response.firstValue(forKeys: ["role"])?.stringValue ?? "user",
            status: response.firstValue(forKeys: ["status"])?.stringValue ?? "unknown",
            balance: response.firstValue(forKeys: ["balance"])?.doubleValue ?? 0,
            concurrency: Int(response.firstValue(forKeys: ["concurrency"])?.doubleValue ?? 0),
            createdAt: response.firstValue(forKeys: ["created_at"])?.stringValue.flatMap(parseDate)
        )
    }

    /// 解析兑换响应；余额和并发只在对应兑换类型下存在。
    static func redeemResult(from response: JSONValue) -> RedeemResult {
        RedeemResult(
            message: response.firstValue(forKeys: ["message"])?.stringValue ?? "兑换成功",
            type: response.firstValue(forKeys: ["type"])?.stringValue ?? "unknown",
            value: response.firstValue(forKeys: ["value"])?.doubleValue ?? 0,
            newBalance: response.firstValue(forKeys: ["new_balance"])?.doubleValue,
            newConcurrency: response.firstValue(forKeys: ["new_concurrency"])?.doubleValue.map(Int.init)
        )
    }

    /// 兼容直接数组、标准分页 `items` 和后端统一 `data` 包裹。
    private static func responseItems(_ response: JSONValue) -> [JSONValue] {
        if let items = response.arrayValue { return items }
        if let items = response.directValue(forKey: "items")?.arrayValue { return items }
        if let data = response.directValue(forKey: "data") {
            if let items = data.arrayValue { return items }
            if let items = data.directValue(forKey: "items")?.arrayValue { return items }
        }
        return []
    }

    /// 直接读取当前对象的数字字段，缺失时按零处理适用于聚合金额和 Token。
    private static func number(_ item: JSONValue, _ key: String) -> Double {
        item.directValue(forKey: key)?.doubleValue ?? 0
    }

    /// ID 和并发等整数字段统一从服务端数字编码转换。
    private static func integer(_ item: JSONValue, _ key: String) -> Int? {
        item.directValue(forKey: key)?.doubleValue.map(Int.init)
    }

    /// 空字符串不进入界面模型，防止表格显示无意义空白。
    private static func string(_ item: JSONValue, _ key: String) -> String? {
        guard let value = item.directValue(forKey: key)?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    /// IP 列表等数组字段只保留非空字符串，防止表单回填时出现空行。
    private static func strings(_ item: JSONValue, _ key: String) -> [String] {
        item.directValue(forKey: key)?.arrayValue?.compactMap { value in
            guard let text = value.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return nil }
            return text
        } ?? []
    }

    /// 日期字段使用同一解析规则，兼容有无小数秒的 ISO 8601（国际标准时间格式）。
    private static func date(_ item: JSONValue, _ key: String) -> Date? {
        item.directValue(forKey: key)?.stringValue.flatMap(parseDate)
    }

    /// 提供给所有用户端模型共用的标准时间解析。
    private static func parseDate(_ value: String) -> Date? {
        if let date = try? fractionalDateFormat.parse(value) { return date }
        return try? standardDateFormat.parse(value)
    }

    /// 不可变解析策略可安全跨任务复用，避免长列表每页为每条记录重复初始化解析器。
    private static let fractionalDateFormat = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    /// 无小数秒时间使用独立不可变策略，兼容 Sub2API 不同版本的时间精度。
    private static let standardDateFormat = Date.ISO8601FormatStyle()
}
