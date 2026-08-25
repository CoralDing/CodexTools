/**
 * 文件说明：仪表盘解析、额度计算与会话过期逻辑单元测试
 * 作者：dingyi60(Codex)
 * 创建时间：2026-08-25
 */

import Foundation
import SQLite3
import XCTest
@testable import CodexTools

/// 验证不同数据源被整理成稳定界面模型时不会发生金额或时间语义错误。
final class ModelsTests: XCTestCase {
    /// 验证嵌套接口字段可以被解析，并正确计算剩余额度与百分比。
    func testDashboardParserCalculatesRemainingQuota() {
        let profile: JSONValue = .object([
            "data": .object(["balance": .number(128.4)])
        ])
        let summary: JSONValue = .object(["total_quota": .number(500)])
        let progress: JSONValue = .object([
            "used_quota": .number(320),
            "reset_at": .string("2026-08-26T00:00:00Z")
        ])
        let usage: JSONValue = .object([
            "total_tokens": .number(1_284_620),
            "total_requests": .number(842),
            "total_actual_cost": .number(3.42),
            "average_duration_ms": .number(1_286)
        ])
        let models: JSONValue = .array([
            .object(["model_name": .string("gpt-5.6-sol")])
        ])

        let snapshot = DashboardParser.parse(
            profile: profile,
            subscriptionSummary: summary,
            subscriptionProgress: progress,
            usageStats: usage,
            modelStats: models
        )

        XCTAssertEqual(snapshot.balance, 128.4)
        XCTAssertEqual(snapshot.quotaRemaining, 180)
        XCTAssertEqual(snapshot.quotaRemainingPercent, 36)
        XCTAssertEqual(snapshot.periodTokens, 1_284_620)
        XCTAssertEqual(snapshot.requestCount, 842)
        XCTAssertEqual(snapshot.usageCost, 3.42)
        XCTAssertEqual(snapshot.averageResponseMilliseconds, 1_286)
        XCTAssertEqual(snapshot.usagePeriod, .today)
        XCTAssertEqual(snapshot.recentModel, "gpt-5.6-sol")
    }

    /// 验证数据源缺少字段时保持空值，防止界面错误显示为“余额 0”。
    func testDashboardParserKeepsMissingValuesNil() {
        let snapshot = DashboardParser.parse(
            profile: .object([:]),
            subscriptionSummary: nil,
            subscriptionProgress: nil,
            usageStats: nil,
            modelStats: nil
        )

        XCTAssertNil(snapshot.balance)
        XCTAssertNil(snapshot.quotaProgress)
        XCTAssertNil(snapshot.quotaRemaining)
        XCTAssertNil(snapshot.periodTokens)
        XCTAssertNil(snapshot.requestCount)
        XCTAssertNil(snapshot.usageCost)
        XCTAssertNil(snapshot.averageResponseMilliseconds)
    }

    /// 验证近 7 天以所选时区的“今天”为终点，并且只包含七个自然日。
    func testUsagePeriodBuildsInclusiveDateRangeInSelectedTimeZone() throws {
        let referenceDate = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-08-25T23:30:00Z")
        )
        let timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))

        let query = UsagePeriod.sevenDays.dateQuery(
            referenceDate: referenceDate,
            timeZone: timeZone
        )

        XCTAssertEqual(query["start_date"], "2026-08-20")
        XCTAssertEqual(query["end_date"], "2026-08-26")
        XCTAssertEqual(query["timezone"], "Asia/Shanghai")
    }

    /// 验证菜单栏紧凑格式和小额消费精度，避免关键指标被显示成零或过长文本。
    func testUsageFormatterUsesCompactUnitsAndPreservesSmallCosts() {
        XCTAssertEqual(UsageFormatter.compactTokens(1_284_620), "1.28M")
        XCTAssertEqual(UsageFormatter.compactTokens(12_400), "12.4K")
        XCTAssertEqual(UsageFormatter.cost(3.42), "$3.42")
        XCTAssertEqual(UsageFormatter.cost(0.0034), "$0.0034")
        XCTAssertEqual(UsageFormatter.duration(milliseconds: 1_286), "1.29 s")
    }

    /// 验证令牌在一分钟内过期时提前刷新，较远过期时间则继续复用。
    func testSessionRefreshWindow() {
        let referenceDate = Date(timeIntervalSince1970: 1_000)
        let expiringSession = AuthSession(
            serverURL: URL(string: "https://sub2api.example")!,
            accessToken: "test",
            refreshToken: "refresh",
            expiresAt: referenceDate.addingTimeInterval(30),
            userID: nil
        )
        let validSession = AuthSession(
            serverURL: URL(string: "https://sub2api.example")!,
            accessToken: "test",
            refreshToken: "refresh",
            expiresAt: referenceDate.addingTimeInterval(600),
            userID: nil
        )

        XCTAssertTrue(expiringSession.needsRefresh(referenceDate: referenceDate))
        XCTAssertFalse(validSession.needsRefresh(referenceDate: referenceDate))
    }

    /// 验证真实站点使用的 `data` 外层和字符串有效期可以被解析。
    func testLoginResponseDecodesWrappedDataAndStringExpiresIn() throws {
        let fixture = """
        {
          "code": 0,
          "message": "success",
          "data": {
            "access_token": "access-token",
            "refresh_token": "refresh-token",
            "expires_in": "3600",
            "user": { "id": "user-1" }
          }
        }
        """

        let response = try JSONDecoder().decode(LoginResponse.self, from: Data(fixture.utf8))

        XCTAssertEqual(response.accessToken, "access-token")
        XCTAssertEqual(response.refreshToken, "refresh-token")
        XCTAssertEqual(response.expiresIn, 3_600)
        XCTAssertEqual(response.user?.firstValue(forKeys: ["id"])?.stringValue, "user-1")
        XCTAssertFalse(response.requiresTwoFactor)
    }

    /// 验证被包裹的两步验证挑战和字符串开关可以正常解码。
    func testLoginResponseDecodesTwoFactorChallenge() throws {
        let fixture = """
        {
          "data": {
            "requires_2fa": "true",
            "temp_token": "temporary-token",
            "user_email_masked": "d***@example.com"
          }
        }
        """

        let response = try JSONDecoder().decode(LoginResponse.self, from: Data(fixture.utf8))

        XCTAssertTrue(response.requiresTwoFactor)
        XCTAssertEqual(response.tempToken, "temporary-token")
        XCTAssertEqual(response.maskedEmail, "d***@example.com")
        XCTAssertNil(response.accessToken)
    }

    /// 验证 Codex Resets 当前公开字段和带毫秒的 UTC 时间能够稳定解码。
    func testCodexResetStatusDecoding() throws {
        let fixture = """
        {
          "data": {
            "latest_reset": {
              "reset_type": "regular",
              "announced_at": "2026-08-24T00:46:51.000Z",
              "source": { "url": "https://x.com/example/status/1" }
            },
            "stats": { "last_reset_at": "2026-08-24T00:46:51.000Z" }
          },
          "meta": { "generated_at": "2026-08-25T03:07:27.693Z" }
        }
        """

        let response = try CodexResetsClient.decodeStatus(Data(fixture.utf8))

        XCTAssertEqual(response.data.latestReset?.resetType, "regular")
        XCTAssertEqual(
            response.data.latestReset?.source.url.absoluteString,
            "https://x.com/example/status/1"
        )
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        XCTAssertEqual(
            response.data.latestReset?.announcedAt,
            formatter.date(from: "2026-08-24T00:46:51.000Z")
        )
    }

    /// 验证首次同步不误报历史重置，且只有严格更新的社区时间才触发一次提醒。
    func testCommunityResetNotificationPolicyRejectsBaselineDuplicatesAndOlderEvents() {
        let lastObserved = Date(timeIntervalSince1970: 1_000)

        XCTAssertFalse(
            CommunityResetNotificationPolicy.shouldNotify(
                current: Date(timeIntervalSince1970: 2_000),
                lastObserved: nil
            )
        )
        XCTAssertFalse(
            CommunityResetNotificationPolicy.shouldNotify(
                current: lastObserved,
                lastObserved: lastObserved
            )
        )
        XCTAssertFalse(
            CommunityResetNotificationPolicy.shouldNotify(
                current: Date(timeIntervalSince1970: 900),
                lastObserved: lastObserved
            )
        )
        XCTAssertTrue(
            CommunityResetNotificationPolicy.shouldNotify(
                current: Date(timeIntervalSince1970: 1_001),
                lastObserved: lastObserved
            )
        )
    }

    /// 验证带 `data.items` 外层的真实分页结构可以解析倍率、成本、Token 和响应时间。
    func testUsageRecordParserDecodesPaginatedUsageLogs() throws {
        let fixture = """
        {
          "code": 0,
          "data": {
            "items": [{
              "created_at": "2026-08-25T06:30:00.000Z",
              "model": "gpt-5.6-sol",
              "input_tokens": 100,
              "output_tokens": 20,
              "cache_creation_tokens": 5,
              "cache_read_tokens": 25,
              "total_cost": 1.25,
              "actual_cost": 1.0,
              "rate_multiplier": 0.8,
              "duration_ms": 1286,
              "billing_mode": "token"
            }],
            "page": 2,
            "pages": 3
          }
        }
        """
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(fixture.utf8))

        let page = UsageRecordParser.parsePage(value)

        XCTAssertEqual(page.page, 2)
        XCTAssertEqual(page.pages, 3)
        XCTAssertEqual(page.records.count, 1)
        XCTAssertEqual(page.records.first?.model, "gpt-5.6-sol")
        XCTAssertEqual(page.records.first?.totalTokens, 150)
        XCTAssertEqual(page.records.first?.standardCost, 1.25)
        XCTAssertEqual(page.records.first?.actualCost, 1.0)
        XCTAssertEqual(page.records.first?.recordedMultiplier, 0.8)
        XCTAssertEqual(page.records.first?.durationMilliseconds, 1_286)
    }

    /// 验证 Sub2API 实扣除以本地标准成本得到 0.80 倍，且两侧数量一致时结论正常。
    func testConsumptionAnalyzerCalculatesHealthyEffectiveMultiplier() {
        let end = Date(timeIntervalSince1970: 10_000)
        let records = [
            makeUsageRecord(date: end.addingTimeInterval(-300), standardCost: 1, actualCost: 0.8, multiplier: 0.8),
            makeUsageRecord(date: end.addingTimeInterval(-600), standardCost: 2, actualCost: 1.6, multiplier: 0.8)
        ]

        let analysis = ConsumptionAnalyzer.analyze(
            localUsage: makeLocalUsage(requestCount: 2, standardCost: 3),
            records: records,
            windowStart: end.addingTimeInterval(-3_600),
            windowEnd: end,
            analyzedAt: end,
            isTruncated: false
        )

        XCTAssertEqual(analysis.status, .normal)
        XCTAssertEqual(analysis.requestCount, 2)
        XCTAssertEqual(analysis.billedRequestCount, 2)
        XCTAssertEqual(analysis.standardCost, 3)
        XCTAssertEqual(analysis.actualCost, 2.4, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(analysis.effectiveMultiplier), 0.8, accuracy: 0.000_001)
        XCTAssertEqual(analysis.inconsistentRequestCount, 0)
    }

    /// 验证本地调用与中转账单数量明显不一致时标记“需关注”。
    func testConsumptionAnalyzerFlagsRequestCountMismatch() {
        let end = Date(timeIntervalSince1970: 10_000)
        let record = makeUsageRecord(
            date: end.addingTimeInterval(-300),
            standardCost: 1,
            actualCost: 1.2,
            multiplier: 0.8
        )

        let analysis = ConsumptionAnalyzer.analyze(
            localUsage: makeLocalUsage(requestCount: 10, standardCost: 1),
            records: [record],
            windowStart: end.addingTimeInterval(-3_600),
            windowEnd: end,
            analyzedAt: end,
            isTruncated: false
        )

        XCTAssertEqual(analysis.status, .attention)
        XCTAssertEqual(analysis.inconsistentRequestCount, 9)
    }

    /// 验证本地读取器只汇总指定窗口内的 Codex 会话记录，并排除代理来源与其他应用。
    func testLocalCodexUsageStoreFiltersWindowAndDataSource() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appending(path: "CodexToolsTests-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        let openedDatabase = try XCTUnwrap(database)
        defer { sqlite3_close(openedDatabase) }

        let schema = """
            CREATE TABLE proxy_request_logs (
                app_type TEXT NOT NULL,
                data_source TEXT NOT NULL,
                input_tokens INTEGER NOT NULL,
                output_tokens INTEGER NOT NULL,
                cache_read_tokens INTEGER NOT NULL,
                cache_creation_tokens INTEGER NOT NULL,
                total_cost_usd TEXT NOT NULL,
                created_at INTEGER NOT NULL
            );
            INSERT INTO proxy_request_logs VALUES ('codex', 'codex_session', 1000, 200, 800, 0, '0.50', 9500);
            INSERT INTO proxy_request_logs VALUES ('codex', 'proxy', 9000, 900, 0, 0, '9.00', 9500);
            INSERT INTO proxy_request_logs VALUES ('claude', 'codex_session', 8000, 800, 0, 0, '8.00', 9500);
            INSERT INTO proxy_request_logs VALUES ('codex', 'codex_session', 7000, 700, 0, 0, '7.00', 5000);
            """
        XCTAssertEqual(sqlite3_exec(openedDatabase, schema, nil, nil, nil), SQLITE_OK)

        let usage = try LocalCodexUsageStore(databaseURL: databaseURL).readUsage(
            windowStart: Date(timeIntervalSince1970: 9_000),
            windowEnd: Date(timeIntervalSince1970: 10_000)
        )

        XCTAssertEqual(usage.requestCount, 1)
        XCTAssertEqual(usage.totalTokens, 1_200)
        XCTAssertEqual(usage.cacheReadTokens, 800)
        XCTAssertEqual(usage.standardCost, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(usage.latestRecordAt, Date(timeIntervalSince1970: 9_500))
    }

    /// 创建固定的 CC Switch 本地汇总，用来验证分析器不会继续采用 Sub2API 自带标准成本。
    private func makeLocalUsage(requestCount: Int, standardCost: Double) -> LocalCodexUsageSummary {
        LocalCodexUsageSummary(
            requestCount: requestCount,
            inputTokens: 8_000,
            outputTokens: 2_000,
            cacheReadTokens: 4_000,
            cacheCreationTokens: 0,
            standardCost: standardCost,
            latestRecordAt: Date(timeIntervalSince1970: 9_900)
        )
    }

    /// 创建固定 Token 计费记录，减少多个分析测试中与判断目标无关的样板数据。
    private func makeUsageRecord(
        date: Date,
        standardCost: Double,
        actualCost: Double,
        multiplier: Double
    ) -> UsageRecord {
        UsageRecord(
            createdAt: date,
            model: "gpt-5.6-sol",
            totalTokens: 1_000,
            standardCost: standardCost,
            actualCost: actualCost,
            recordedMultiplier: multiplier,
            durationMilliseconds: 1_200,
            billingMode: "token"
        )
    }
}
