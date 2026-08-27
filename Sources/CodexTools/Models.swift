/**
 * 文件说明：Sub2API 响应模型、应用状态模型和宽容的数据解析逻辑
 * 作者：dingyi60(Codex)
 * 创建时间：2026-08-25
 */

import Foundation

/// 表示任意 JSON（接口结构化数据）值，用于兼容不同 Sub2API 部署版本的字段差异。
enum JSONValue: Codable, Sendable, Equatable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    /// 根据实际 JSON 类型依次尝试解码，避免把服务端版本差异变成登录失败。
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    /// 按当前枚举分支编码，状态快照和单元测试会复用这一能力。
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    /// 在当前对象及子节点中查找第一个候选字段，兼容字段被包在 `data` 或 `summary` 中的情况。
    func firstValue(forKeys keys: [String]) -> JSONValue? {
        let normalizedKeys = Set(keys.map { $0.lowercased() })

        switch self {
        case let .object(object):
            if let match = object.first(where: { normalizedKeys.contains($0.key.lowercased()) }) {
                return match.value
            }
            for value in object.values {
                if let nested = value.firstValue(forKeys: keys) {
                    return nested
                }
            }
        case let .array(array):
            for value in array {
                if let nested = value.firstValue(forKeys: keys) {
                    return nested
                }
            }
        default:
            break
        }

        return nil
    }

    /// 将数字或数字字符串统一转换为 `Double`，避免金额字段因编码方式不同而丢失。
    var doubleValue: Double? {
        switch self {
        case let .number(value): return value
        case let .string(value): return Double(value)
        default: return nil
        }
    }

    /// 将布尔值、0/1 和常见布尔字符串统一转换，兼容不同部署版本的开关字段编码。
    var boolValue: Bool? {
        switch self {
        case let .bool(value):
            return value
        case let .number(value):
            return value != 0
        case let .string(value):
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1", "yes": return true
            case "false", "0", "no": return false
            default: return nil
            }
        default:
            return nil
        }
    }

    /// 将常见标量统一转换为字符串，便于读取模型名称和重置时间。
    var stringValue: String? {
        switch self {
        case let .string(value): return value
        case let .number(value): return String(value)
        case let .bool(value): return String(value)
        default: return nil
        }
    }

    /// 返回当前数组分支，分页调用记录解析会用它读取 `items`，其他类型明确返回空值。
    var arrayValue: [JSONValue]? {
        guard case let .array(value) = self else { return nil }
        return value
    }

    /// 只读取当前对象的直接字段，避免单条调用记录误取嵌套用户或分组中的同名字段。
    func directValue(forKey key: String) -> JSONValue? {
        guard case let .object(object) = self else { return nil }
        return object.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame })?.value
    }
}

/// 登录成功后需要持久化的最小会话数据，不包含邮箱密码。
struct AuthSession: Codable, Sendable, Equatable {
    let serverURL: URL
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
    let userID: String?

    /// 判断访问令牌是否即将过期，提前刷新可避免悬浮层短暂显示离线。
    func needsRefresh(referenceDate: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSince(referenceDate) < 60
    }
}

/// 登录第一步需要用户继续输入的两步验证信息，不包含密码和最终访问令牌。
struct PendingTwoFactor: Sendable, Equatable {
    let serverURL: URL
    let tempToken: String
    let maskedEmail: String?
}

/// 登录第一步可能直接完成，也可能要求输入 TOTP（基于时间的一次性验证码）。
enum LoginOutcome: Sendable, Equatable {
    case authenticated(AuthSession)
    case requiresTwoFactor(PendingTwoFactor)
}

/// 登录接口的兼容模型；支持普通令牌响应、两步验证响应和字符串形式的有效期。
struct LoginResponse: Decodable, Sendable {
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Double?
    let user: JSONValue?
    let requiresTwoFactor: Bool
    let tempToken: String?
    let maskedEmail: String?

    /// 递归读取响应字段，兼容令牌直接返回或被 `data` / `result` 包裹的 Sub2API 部署。
    init(from decoder: Decoder) throws {
        let response = try JSONValue(from: decoder)
        accessToken = response.firstValue(forKeys: ["access_token", "accessToken"])?.stringValue
        refreshToken = response.firstValue(forKeys: ["refresh_token", "refreshToken"])?.stringValue
        expiresIn = response.firstValue(forKeys: ["expires_in", "expiresIn"])?.doubleValue
        user = response.firstValue(forKeys: ["user"])
        requiresTwoFactor = response.firstValue(
            forKeys: ["requires_2fa", "requires_two_factor", "requiresTwoFactor"]
        )?.boolValue ?? false
        tempToken = response.firstValue(forKeys: ["temp_token", "tempToken"])?.stringValue
        maskedEmail = response.firstValue(
            forKeys: ["user_email_masked", "masked_email", "maskedEmail"]
        )?.stringValue
    }
}

/// 描述悬浮面板支持的统计周期，并集中生成 Sub2API 所需的本地日期范围。
enum UsagePeriod: String, CaseIterable, Codable, Sendable, Equatable {
    case today
    case sevenDays
    case thirtyDays

    /// 分段控件使用短标题，保证 360 点宽的菜单栏面板内不会拥挤。
    var shortTitle: String {
        switch self {
        case .today: return "今天"
        case .sevenDays: return "7 天"
        case .thirtyDays: return "30 天"
        }
    }

    /// 指标标签使用完整周期名称，让数值口径无需额外说明也能被理解。
    var metricTitle: String {
        switch self {
        case .today: return "今日"
        case .sevenDays: return "近 7 天"
        case .thirtyDays: return "近 30 天"
        }
    }

    /// 返回包含今天在内的自然日数量，避免“近 7 天”被错误计算成 8 个日期。
    private var includedDayCount: Int {
        switch self {
        case .today: return 1
        case .sevenDays: return 7
        case .thirtyDays: return 30
        }
    }

    /// 按指定时区生成闭区间日期参数；只发送日期可与 Sub2API 网页端统计口径保持一致。
    func dateQuery(referenceDate: Date = Date(), timeZone: TimeZone) -> [String: String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let endDate = calendar.startOfDay(for: referenceDate)
        let startDate = calendar.date(
            byAdding: .day,
            value: -(includedDayCount - 1),
            to: endDate
        ) ?? endDate

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        return [
            "start_date": formatter.string(from: startDate),
            "end_date": formatter.string(from: endDate),
            "timezone": timeZone.identifier
        ]
    }
}

/// 集中格式化用量指标，保证菜单栏摘要与悬浮面板使用完全相同的精度规则。
enum UsageFormatter {
    /// 大于一百万的 Token 使用 M（百万）单位，较小数值使用 K（千）单位以节省菜单栏空间。
    static func compactTokens(_ value: Double?) -> String {
        guard let value else { return "—" }
        let absoluteValue = abs(value)
        if absoluteValue >= 1_000_000 {
            return compact(value / 1_000_000, suffix: "M")
        }
        if absoluteValue >= 1_000 {
            return compact(value / 1_000, suffix: "K")
        }
        return value.formatted(.number.precision(.fractionLength(0)))
    }

    /// 消费金额通常保留两位，小于一美分时保留四位，避免真实的小额消费被显示成零。
    static func cost(_ value: Double?) -> String {
        guard let value else { return "—" }
        let fractionLength = value != 0 && abs(value) < 0.01 ? 4 : 2
        return "$" + value.formatted(.number.precision(.fractionLength(fractionLength)))
    }

    /// 余额活动使用正负号区分入账和扣减；零金额不显示误导性的符号。
    static func balanceChange(_ value: Double) -> String {
        let formattedCost = cost(abs(value))
        if value > 0 { return "+\(formattedCost)" }
        if value < 0 { return "-\(formattedCost)" }
        return formattedCost
    }

    /// 请求数按整数和本地千位分隔符显示，接口返回浮点编码时也不会出现小数尾数。
    static func requestCount(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(0)))
    }

    /// Sub2API 约定并发值小于等于零表示不限制，正数按整数显示允许同时执行的请求数。
    static func concurrencyLimit(_ value: Double?) -> String {
        guard let value else { return "—" }
        if value <= 0 { return "不限" }
        return value.formatted(.number.precision(.fractionLength(0)))
    }

    /// 平均响应时间在一秒内使用毫秒，超过一秒后改用秒，兼顾精度和扫描效率。
    static func duration(milliseconds value: Double?) -> String {
        guard let value else { return "—" }
        if abs(value) < 1_000 {
            return value.formatted(.number.precision(.fractionLength(0))) + " ms"
        }
        return (value / 1_000).formatted(.number.precision(.fractionLength(0...2))) + " s"
    }

    /// 删除无意义的尾随零，同时最多保留两位小数，避免菜单栏宽度频繁跳变。
    private static func compact(_ value: Double, suffix: String) -> String {
        value.formatted(.number.precision(.fractionLength(0...2))) + suffix
    }
}

/// 描述每小时消耗分析的结论，原始值用于持久化最近一次分析结果。
enum ConsumptionAnalysisStatus: String, Codable, Sendable, Equatable {
    case normal
    case attention
    case noUsage
    case insufficientData
}

/// 表示最近一小时内的一条实际调用，只保留计费核对与界面摘要需要的字段。
struct UsageRecord: Sendable, Equatable {
    let createdAt: Date
    let model: String
    let totalTokens: Double
    let standardCost: Double
    let actualCost: Double
    let recordedMultiplier: Double?
    let durationMilliseconds: Double?
    let billingMode: String?
}

/// 区分余额增加、调用消费和人工调整，让弹窗可以使用一致的颜色与图标语义。
enum BalanceActivityKind: Sendable, Equatable {
    case usage
    case recharge
    case adjustment
}

/// 表示来自用量、兑换记录或支付订单的一条统一余额变动。
struct BalanceActivity: Sendable, Equatable {
    let createdAt: Date
    let kind: BalanceActivityKind
    let title: String
    let detail: String
    let amountChange: Double
    let totalTokens: Double?
    let durationMilliseconds: Double?
}

/// 表示 Sub2API 分页调用记录中的一页，页数用于判断是否需要继续向前读取。
struct UsageRecordPage: Sendable, Equatable {
    let records: [UsageRecord]
    let page: Int
    let pages: Int
}

/// 最近一小时消耗、调用与倍率的稳定分析结果，可在应用重启后继续展示。
struct ConsumptionAnalysis: Codable, Sendable, Equatable {
    let status: ConsumptionAnalysisStatus
    let message: String
    let windowStart: Date
    let windowEnd: Date
    let analyzedAt: Date
    let requestCount: Int
    let billedRequestCount: Int?
    let totalTokens: Double
    let standardCost: Double
    let actualCost: Double
    let effectiveMultiplier: Double?
    let minimumRecordedMultiplier: Double?
    let maximumRecordedMultiplier: Double?
    let averageResponseMilliseconds: Double?
    let inconsistentRequestCount: Int
    let isTruncated: Bool
}

/// 把宽容的 JSON（接口结构化数据）分页响应转换成可分析的调用记录。
enum UsageRecordParser {
    /// 兼容标准 `data.items` 外层，并跳过缺少有效创建时间的损坏记录。
    static func parsePage(_ response: JSONValue) -> UsageRecordPage {
        let items = response.firstValue(forKeys: ["items", "records", "list"])?.arrayValue ?? []
        let records = items.compactMap(parseRecord)
        let page = Int(response.firstValue(forKeys: ["page"])?.doubleValue ?? 1)
        let pages = max(Int(response.firstValue(forKeys: ["pages", "total_pages"])?.doubleValue ?? 1), 1)
        return UsageRecordPage(records: records, page: max(page, 1), pages: pages)
    }

    /// 解析单条调用的直接字段；Token 包含输入、输出、缓存创建和缓存读取四部分。
    private static func parseRecord(_ value: JSONValue) -> UsageRecord? {
        guard let createdAtValue = value.directValue(forKey: "created_at")?.stringValue,
              let createdAt = parseDate(createdAtValue) else {
            return nil
        }

        let inputTokens = number(value, "input_tokens")
        let outputTokens = number(value, "output_tokens")
        let cacheCreationTokens = number(value, "cache_creation_tokens")
        let cacheReadTokens = number(value, "cache_read_tokens")

        return UsageRecord(
            createdAt: createdAt,
            model: value.directValue(forKey: "model")?.stringValue ?? "未知模型",
            totalTokens: inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens,
            standardCost: number(value, "total_cost"),
            actualCost: number(value, "actual_cost"),
            recordedMultiplier: value.directValue(forKey: "rate_multiplier")?.doubleValue,
            durationMilliseconds: value.directValue(forKey: "duration_ms")?.doubleValue,
            billingMode: value.directValue(forKey: "billing_mode")?.stringValue
        )
    }

    /// 缺少数字字段时按零处理，因为 Sub2API 的旧记录可能省略未使用的缓存字段。
    private static func number(_ value: JSONValue, _ key: String) -> Double {
        value.directValue(forKey: key)?.doubleValue ?? 0
    }

    /// 同时兼容带小数秒和普通 ISO 8601（国际标准时间格式）的创建时间。
    private static func parseDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value)
    }
}

/// 将 Sub2API 分散在三个只读接口中的余额变动合并为统一、倒序的活动列表。
enum BalanceActivityParser {
    /// 合并调用扣费、兑换/人工调整和已完成充值订单，最终只保留最近指定条数。
    static func parse(
        usageResponse: JSONValue?,
        redeemResponse: JSONValue?,
        paymentResponse: JSONValue?,
        limit: Int = 20
    ) -> [BalanceActivity] {
        let normalizedLimit = min(max(limit, 1), 100)
        let activities = usageActivities(from: usageResponse)
            + redeemActivities(from: redeemResponse)
            + paymentActivities(from: paymentResponse)
        return Array(
            activities
                .sorted { $0.createdAt > $1.createdAt }
                .prefix(normalizedLimit)
        )
    }

    /// 将每条调用的实际成本转换为负数余额变动，并保留核对所需的模型与性能数据。
    private static func usageActivities(from response: JSONValue?) -> [BalanceActivity] {
        guard let response else { return [] }
        return UsageRecordParser.parsePage(response).records.map { record in
            BalanceActivity(
                createdAt: record.createdAt,
                kind: .usage,
                title: record.model,
                detail: "模型调用",
                amountChange: -max(record.actualCost, 0),
                totalTokens: record.totalTokens,
                durationMilliseconds: record.durationMilliseconds
            )
        }
    }

    /// 兑换历史只保留会改变余额的类型，排除并发数和订阅等非余额事件。
    private static func redeemActivities(from response: JSONValue?) -> [BalanceActivity] {
        guard let response else { return [] }
        return responseArray(response, preferredKeys: ["items", "records", "list", "data"])
            .compactMap { item in
                guard let type = item.directValue(forKey: "type")?.stringValue,
                      ["balance", "admin_balance", "affiliate_balance"].contains(type),
                      let value = item.directValue(forKey: "value")?.doubleValue,
                      let date = eventDate(item, preferredKeys: ["used_at", "created_at"]) else {
                    return nil
                }

                let title: String
                let detail: String
                switch type {
                case "balance":
                    title = "兑换码充值"
                    detail = "兑换记录"
                case "affiliate_balance":
                    title = value >= 0 ? "推广余额转入" : "推广余额转出"
                    detail = "推广余额"
                default:
                    title = value >= 0 ? "管理员增加余额" : "管理员扣减余额"
                    detail = "余额调整"
                }

                return BalanceActivity(
                    createdAt: date,
                    kind: type == "balance" ? .recharge : .adjustment,
                    title: title,
                    detail: detail,
                    amountChange: value,
                    totalTokens: nil,
                    durationMilliseconds: nil
                )
            }
    }

    /// 支付订单仅把已完成的余额订单视为入账，忽略待支付、失败和订阅订单。
    private static func paymentActivities(from response: JSONValue?) -> [BalanceActivity] {
        guard let response else { return [] }
        return responseArray(response, preferredKeys: ["items", "records", "list", "data"])
            .compactMap { item in
                guard item.directValue(forKey: "order_type")?.stringValue == "balance",
                      item.directValue(forKey: "status")?.stringValue == "completed",
                      let amount = item.directValue(forKey: "amount")?.doubleValue,
                      let date = eventDate(
                        item,
                        preferredKeys: ["completed_at", "paid_at", "created_at"]
                      ) else {
                    return nil
                }
                let paymentType = item.directValue(forKey: "payment_type")?.stringValue
                    .flatMap { $0.isEmpty ? nil : $0 }
                return BalanceActivity(
                    createdAt: date,
                    kind: .recharge,
                    title: "余额充值",
                    detail: paymentType ?? "支付订单",
                    amountChange: max(amount, 0),
                    totalTokens: nil,
                    durationMilliseconds: nil
                )
            }
    }

    /// 兼容响应直接为数组、`data` 数组或标准分页 `data.items` 三种结构。
    private static func responseArray(_ response: JSONValue, preferredKeys: [String]) -> [JSONValue] {
        if let directArray = response.arrayValue { return directArray }
        for key in preferredKeys {
            if let array = response.firstValue(forKeys: [key])?.arrayValue {
                return array
            }
        }
        return []
    }

    /// 按字段优先级读取事件时间，并兼容带毫秒和普通 ISO 8601 字符串。
    private static func eventDate(_ item: JSONValue, preferredKeys: [String]) -> Date? {
        for key in preferredKeys {
            guard let value = item.directValue(forKey: key)?.stringValue else { continue }
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) { return date }

            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            if let date = standard.date(from: value) { return date }
        }
        return nil
    }
}

/// 使用本地 Codex 会话成本和 Sub2API 实际扣费计算综合倍率，并核对两侧调用数量。
enum ConsumptionAnalyzer {
    /// 分析同一时间窗口的本地用量和中转账单，避免使用 Sub2API 自己的标准成本循环验证。
    static func analyze(
        localUsage: LocalCodexUsageSummary,
        records: [UsageRecord],
        windowStart: Date,
        windowEnd: Date,
        analyzedAt: Date,
        isTruncated: Bool
    ) -> ConsumptionAnalysis {
        guard localUsage.requestCount > 0 || !records.isEmpty else {
            return result(
                status: .noUsage,
                message: "最近 1 小时暂无调用",
                localUsage: localUsage,
                records: [],
                windowStart: windowStart,
                windowEnd: windowEnd,
                analyzedAt: analyzedAt,
                isTruncated: isTruncated,
                inconsistentRequestCount: 0
            )
        }

        let hasInvalidMoney = !localUsage.standardCost.isFinite
            || localUsage.standardCost < 0
            || records.contains { !$0.actualCost.isFinite || $0.actualCost < 0 }
        let inconsistentRequestCount = abs(localUsage.requestCount - records.count)
        let allowedRequestDifference = max(2, Int(ceil(Double(localUsage.requestCount) * 0.05)))

        let status: ConsumptionAnalysisStatus
        let message: String
        if hasInvalidMoney {
            status = .attention
            message = "本地估算或中转扣费包含异常金额"
        } else if isTruncated {
            status = .attention
            message = "Sub2API 调用超过 10,000 条，本次对账不完整"
        } else if localUsage.requestCount == 0 {
            status = .attention
            message = "Sub2API 有 \(records.count) 条账单，但本地未找到调用"
        } else if records.isEmpty {
            status = .attention
            message = "本地有 \(localUsage.requestCount) 次调用，但 Sub2API 未返回账单"
        } else if localUsage.standardCost <= 0 {
            status = .insufficientData
            message = "本地调用缺少有效模型价格，暂时无法计算倍率"
        } else if inconsistentRequestCount > allowedRequestDifference {
            status = .attention
            message = "本地 \(localUsage.requestCount) 次调用，Sub2API 返回 \(records.count) 条账单"
        } else {
            status = .normal
            message = "本地调用与 Sub2API 账单数量已对齐"
        }

        return result(
            status: status,
            message: message,
            localUsage: localUsage,
            records: records,
            windowStart: windowStart,
            windowEnd: windowEnd,
            analyzedAt: analyzedAt,
            isTruncated: isTruncated,
            inconsistentRequestCount: inconsistentRequestCount
        )
    }

    /// 汇总公共指标，并使用“Sub2API 实扣 ÷ CC Switch 本地标准成本”计算真实综合倍率。
    private static func result(
        status: ConsumptionAnalysisStatus,
        message: String,
        localUsage: LocalCodexUsageSummary,
        records: [UsageRecord],
        windowStart: Date,
        windowEnd: Date,
        analyzedAt: Date,
        isTruncated: Bool,
        inconsistentRequestCount: Int
    ) -> ConsumptionAnalysis {
        let actualCost = records.reduce(0) { $0 + $1.actualCost }
        let multipliers = records.compactMap(\.recordedMultiplier).filter { $0.isFinite && $0 >= 0 }
        let durations = records.compactMap(\.durationMilliseconds).filter { $0.isFinite && $0 >= 0 }

        return ConsumptionAnalysis(
            status: status,
            message: message,
            windowStart: windowStart,
            windowEnd: windowEnd,
            analyzedAt: analyzedAt,
            requestCount: localUsage.requestCount,
            billedRequestCount: records.count,
            totalTokens: localUsage.totalTokens,
            standardCost: localUsage.standardCost,
            actualCost: actualCost,
            effectiveMultiplier: localUsage.standardCost > 0 ? actualCost / localUsage.standardCost : nil,
            minimumRecordedMultiplier: multipliers.min(),
            maximumRecordedMultiplier: multipliers.max(),
            averageResponseMilliseconds: durations.isEmpty
                ? nil
                : durations.reduce(0, +) / Double(durations.count),
            inconsistentRequestCount: inconsistentRequestCount,
            isTruncated: isTruncated
        )
    }
}

/// 悬浮层和菜单栏摘要共同使用的只读状态快照。
struct DashboardSnapshot: Codable, Sendable, Equatable {
    var balance: Double?
    var concurrencyLimit: Double?
    var quotaUsed: Double?
    var quotaTotal: Double?
    var periodTokens: Double?
    var requestCount: Double?
    var usageCost: Double?
    var averageResponseMilliseconds: Double?
    var usagePeriod: UsagePeriod
    var recentModel: String?
    var resetAt: String?
    var lastGlobalResetAt: Date?
    var lastGlobalResetType: String?
    var resetSourceURL: URL?
    var resetSyncedAt: Date?
    var displayTimeZone: String
    var refreshedAt: Date

    /// 返回 0 到 1 之间的额度使用比例；缺少有效总额度时不显示进度条数据。
    var quotaProgress: Double? {
        guard let quotaUsed, let quotaTotal, quotaTotal > 0 else { return nil }
        return min(max(quotaUsed / quotaTotal, 0), 1)
    }

    /// 返回剩余额度，统一在模型层处理，避免多个界面各自重复计算。
    var quotaRemaining: Double? {
        guard let quotaUsed, let quotaTotal else { return nil }
        return max(quotaTotal - quotaUsed, 0)
    }

    /// 返回剩余额度百分比，供通知阈值判断使用。
    var quotaRemainingPercent: Double? {
        guard let quotaProgress else { return nil }
        return (1 - quotaProgress) * 100
    }
}

/// 把多个 Sub2API 接口结果整理成稳定的界面模型。
enum DashboardParser {
    /// 解析余额、并发上限、订阅进度、周期用量和模型统计；每一部分都允许为空，避免单个接口异常拖垮整个面板。
    static func parse(
        profile: JSONValue?,
        subscriptionSummary: JSONValue?,
        subscriptionProgress: JSONValue?,
        usageStats: JSONValue?,
        modelStats: JSONValue?,
        usagePeriod: UsagePeriod = .today,
        refreshedAt: Date = Date()
    ) -> DashboardSnapshot {
        let balance = number(in: profile, keys: ["balance", "available_balance", "current_balance"])
        let concurrencyLimit = number(
            in: profile,
            keys: ["concurrency", "concurrency_limit", "max_concurrency"]
        )
        let quotaTotal = number(
            in: subscriptionSummary,
            keys: ["quota", "total_quota", "quota_total", "limit", "amount"]
        ) ?? number(in: subscriptionProgress, keys: ["quota", "total_quota", "quota_total", "limit"])
        let quotaUsed = number(
            in: subscriptionProgress,
            keys: ["used", "used_quota", "quota_used", "usage", "usage_usd"]
        ) ?? number(in: subscriptionSummary, keys: ["used", "used_quota", "quota_used", "usage"])
        let periodTokens = number(
            in: usageStats,
            keys: ["total_tokens", "tokens", "token_count", "input_output_tokens"]
        )
        let requestCount = number(in: usageStats, keys: ["total_requests", "request_count", "requests"])
        let usageCost = number(in: usageStats, keys: ["total_actual_cost", "actual_cost", "total_cost"])
        let averageResponseMilliseconds = number(
            in: usageStats,
            keys: ["average_duration_ms", "avg_duration_ms", "average_response_ms"]
        )
        let recentModel = string(
            in: modelStats,
            keys: ["model", "model_name", "name"]
        )
        let resetAt = string(
            in: subscriptionProgress,
            keys: ["reset_at", "reset_time", "period_end", "expires_at", "end_at"]
        ) ?? string(in: subscriptionSummary, keys: ["reset_at", "period_end", "expires_at"])

        return DashboardSnapshot(
            balance: balance,
            concurrencyLimit: concurrencyLimit,
            quotaUsed: quotaUsed,
            quotaTotal: quotaTotal,
            periodTokens: periodTokens,
            requestCount: requestCount,
            usageCost: usageCost,
            averageResponseMilliseconds: averageResponseMilliseconds,
            usagePeriod: usagePeriod,
            recentModel: recentModel,
            resetAt: resetAt,
            lastGlobalResetAt: nil,
            lastGlobalResetType: nil,
            resetSourceURL: nil,
            resetSyncedAt: nil,
            displayTimeZone: TimeZone.current.identifier,
            refreshedAt: refreshedAt
        )
    }

    /// 从候选字段中读取第一个数字，字段不存在时明确返回空值。
    private static func number(in value: JSONValue?, keys: [String]) -> Double? {
        value?.firstValue(forKeys: keys)?.doubleValue
    }

    /// 从候选字段中读取第一个非空字符串，防止空模型名占用界面位置。
    private static func string(in value: JSONValue?, keys: [String]) -> String? {
        guard let result = value?.firstValue(forKeys: keys)?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !result.isEmpty else {
            return nil
        }
        return result
    }
}

/// codex-resets.com 的公开状态响应，只解码应用真正需要的稳定字段。
struct CodexResetStatusResponse: Decodable, Sendable, Equatable {
    let data: DataPayload
    let meta: Meta

    /// 公共接口中与最新重置有关的数据容器。
    struct DataPayload: Decodable, Sendable, Equatable {
        let latestReset: Reset?
        let stats: Stats

        private enum CodingKeys: String, CodingKey {
            case latestReset = "latest_reset"
            case stats
        }
    }

    /// 单条重置公告，时间表示公告发布时刻，站点不保证它等于每个账户的实际生效时刻。
    struct Reset: Decodable, Sendable, Equatable {
        let resetType: String
        let announcedAt: Date
        let source: Source

        private enum CodingKeys: String, CodingKey {
            case resetType = "reset_type"
            case announcedAt = "announced_at"
            case source
        }
    }

    /// 重置公告的原始来源链接。
    struct Source: Decodable, Sendable, Equatable {
        let url: URL
    }

    /// 站点聚合统计中的最近重置时间，用作公告对象缺失时的回退数据。
    struct Stats: Decodable, Sendable, Equatable {
        let lastResetAt: Date?

        private enum CodingKeys: String, CodingKey {
            case lastResetAt = "last_reset_at"
        }
    }

    /// 响应生成时间，帮助用户判断同步数据是否新鲜。
    struct Meta: Decodable, Sendable, Equatable {
        let generatedAt: Date

        private enum CodingKeys: String, CodingKey {
            case generatedAt = "generated_at"
        }
    }
}

/// 判断社区重置是否比本机最后观察记录更新，纯逻辑独立出来便于覆盖重复与乱序边界。
enum CommunityResetNotificationPolicy {
    /// 首次同步只建立基线；之后仅严格更晚的重置时间才属于需要提醒的新事件。
    static func shouldNotify(current: Date, lastObserved: Date?) -> Bool {
        guard let lastObserved else { return false }
        return current > lastObserved
    }
}

/// 统一描述可展示给用户的网络或解析错误。
enum CodexToolsError: LocalizedError, Equatable {
    case invalidServerURL
    case invalidResponse
    case server(statusCode: Int, message: String)
    case missingRefreshToken
    case keychain(status: Int32)

    /// 将内部错误转换成前端开发者容易理解的中文提示。
    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "服务器地址无效，请填写完整的 https:// 地址。"
        case .invalidResponse:
            return "服务器返回了无法识别的数据，请稍后重试。"
        case let .server(statusCode, message):
            return "请求失败（HTTP \(statusCode)）：\(message)"
        case .missingRefreshToken:
            return "登录已过期，请重新登录。"
        case let .keychain(status):
            return "无法访问本机钥匙串（错误码 \(status)）。"
        }
    }
}
