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
    /// 验证新安装默认开启登录自启动，同时仅注册默认值而不覆盖后续用户选择。
    func testPreferencesEnableLaunchAtLoginByDefaultWithoutOverridingUserChoice() throws {
        let suiteName = "CodexToolsTests.LaunchAtLogin.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        PreferenceKey.registerDefaults(in: defaults)
        XCTAssertTrue(defaults.bool(forKey: PreferenceKey.launchAtLoginEnabled))

        defaults.set(false, forKey: PreferenceKey.launchAtLoginEnabled)
        PreferenceKey.registerDefaults(in: defaults)
        XCTAssertFalse(defaults.bool(forKey: PreferenceKey.launchAtLoginEnabled))
    }

    /// 验证嵌套接口字段可以被解析，并正确计算剩余额度与百分比。
    func testDashboardParserCalculatesRemainingQuota() {
        let profile: JSONValue = .object([
            "data": .object([
                "balance": .number(128.4),
                "concurrency": .number(10)
            ])
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
        XCTAssertEqual(snapshot.concurrencyLimit, 10)
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
        XCTAssertNil(snapshot.concurrencyLimit)
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
        XCTAssertEqual(UsageFormatter.balanceChange(-0.688), "-$0.69")
        XCTAssertEqual(UsageFormatter.balanceChange(20), "+$20.00")
        XCTAssertEqual(UsageFormatter.balanceChange(0), "$0.00")
        XCTAssertEqual(UsageFormatter.concurrencyLimit(10), "10")
        XCTAssertEqual(UsageFormatter.concurrencyLimit(0), "不限")
        XCTAssertEqual(UsageFormatter.concurrencyLimit(nil), "—")
        XCTAssertEqual(UsageFormatter.duration(milliseconds: 1_286), "1.29 s")
        XCTAssertEqual(
            UsageFormatter.tokenPricePerMillion(cost: 0.003, tokens: 1_000),
            "$3.0000 / 1M Token"
        )
        XCTAssertEqual(UsageFormatter.tokenPricePerMillion(cost: 0.003, tokens: 0), "—")
    }

    /// 验证 Codex 导入只创建独立 Profile 和权限受限密钥文件，不改写默认 config.toml。
    func testAPIKeyImportCreatesIsolatedCodexProfile() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let codexDirectory = home.appending(path: ".codex", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: codexDirectory, withIntermediateDirectories: true)
        let defaultConfig = codexDirectory.appending(path: "config.toml")
        try Data("model = \"existing\"\n".utf8).write(to: defaultConfig)

        let result = try APIKeyClientImportService.importKey(
            makePortalAPIKey(),
            serverURL: URL(string: "https://sub2api.example")!,
            model: "gpt-test",
            target: .codex,
            paths: APIKeyImportPaths(homeDirectory: home)
        )

        let profile = try String(contentsOf: codexDirectory.appending(path: "subpilot.config.toml"), encoding: .utf8)
        let secret = try String(contentsOf: home.appending(path: ".config/subpilot/api-key-99"), encoding: .utf8)
        let original = try String(contentsOf: defaultConfig, encoding: .utf8)
        XCTAssertTrue(profile.contains("model_provider = \"subpilot\""))
        XCTAssertTrue(profile.contains("base_url = \"https://sub2api.example/v1\""))
        XCTAssertTrue(profile.contains("command = \"/bin/cat\""))
        XCTAssertFalse(profile.contains("sk-subpilot-test"))
        XCTAssertEqual(secret, "sk-subpilot-test\n")
        XCTAssertEqual(original, "model = \"existing\"\n")
        XCTAssertEqual(result.message, "已导入 Codex Profile")
    }

    /// 验证 Claude Code 导入保留既有权限和环境变量，只覆盖 SubPilot 负责的三个字段。
    func testAPIKeyImportMergesClaudeSettings() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let settingsURL = home.appending(path: ".claude/settings.json")
        try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let existing = """
        {"permissions":{"allow":["Bash"]},"env":{"KEEP":"yes"}}
        """
        try Data(existing.utf8).write(to: settingsURL)

        _ = try APIKeyClientImportService.importKey(
            makePortalAPIKey(),
            serverURL: URL(string: "https://sub2api.example/")!,
            model: "claude-test",
            target: .claudeCode,
            paths: APIKeyImportPaths(homeDirectory: home)
        )

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as? [String: Any]
        )
        let environment = try XCTUnwrap(object["env"] as? [String: String])
        let permissions = try XCTUnwrap(object["permissions"] as? [String: Any])
        XCTAssertEqual(environment["KEEP"], "yes")
        XCTAssertEqual(environment["ANTHROPIC_BASE_URL"], "https://sub2api.example")
        XCTAssertEqual(environment["ANTHROPIC_AUTH_TOKEN"], "sk-subpilot-test")
        XCTAssertEqual(environment["ANTHROPIC_MODEL"], "claude-test")
        XCTAssertEqual(permissions["allow"] as? [String], ["Bash"])
    }

    /// 验证 CC Switch 导入两个供应商且不改变当前供应商，同时生成可恢复数据库备份。
    func testAPIKeyImportAddsCCSwitchProvidersWithoutActivatingThem() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let databaseURL = home.appending(path: ".cc-switch/cc-switch.db")
        try FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        let openedDatabase = try XCTUnwrap(database)
        let schema = """
        CREATE TABLE providers (
            id TEXT NOT NULL, app_type TEXT NOT NULL, name TEXT NOT NULL,
            settings_config TEXT NOT NULL, website_url TEXT, category TEXT,
            created_at INTEGER, sort_index INTEGER, notes TEXT, icon TEXT,
            icon_color TEXT, meta TEXT NOT NULL DEFAULT '{}',
            is_current BOOLEAN NOT NULL DEFAULT 0,
            in_failover_queue BOOLEAN NOT NULL DEFAULT 0,
            cost_multiplier TEXT NOT NULL DEFAULT '1.0',
            PRIMARY KEY (id, app_type)
        );
        INSERT INTO providers (id, app_type, name, settings_config, meta, is_current)
        VALUES ('existing', 'codex', 'Existing', '{}', '{}', 1);
        """
        XCTAssertEqual(sqlite3_exec(openedDatabase, schema, nil, nil, nil), SQLITE_OK)
        sqlite3_close(openedDatabase)
        database = nil

        _ = try APIKeyClientImportService.importKey(
            makePortalAPIKey(),
            serverURL: URL(string: "https://sub2api.example")!,
            model: "gpt-test",
            target: .ccSwitch,
            paths: APIKeyImportPaths(homeDirectory: home)
        )

        var verificationDatabase: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(databaseURL.path, &verificationDatabase, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        let verified = try XCTUnwrap(verificationDatabase)
        defer { sqlite3_close(verified) }
        XCTAssertEqual(sqliteInteger(verified, sql: "SELECT COUNT(*) FROM providers WHERE id = 'subpilot-99'"), 2)
        XCTAssertEqual(sqliteInteger(verified, sql: "SELECT COUNT(*) FROM providers WHERE is_current = 1"), 1)
        XCTAssertEqual(sqliteInteger(verified, sql: "SELECT is_current FROM providers WHERE id = 'existing'"), 1)
        let backupRoot = home.appending(path: ".cc-switch/subpilot-backups")
        let backups = try FileManager.default.subpathsOfDirectory(atPath: backupRoot.path)
        XCTAssertTrue(backups.contains { $0.hasSuffix("cc-switch.db") })
    }

    /// 验证弹窗只保留余额增加记录，并过滤并发兑换和人工扣减。
    func testBalanceActivityParserUsesOnlyBalanceCredits() throws {
        let redeem: JSONValue = .object([
            "data": .array([
                .object([
                    "type": .string("admin_balance"),
                    "value": .number(5),
                    "used_at": .string("2026-08-26T01:30:00Z")
                ]),
                .object([
                    "type": .string("admin_balance"),
                    "value": .number(-2),
                    "used_at": .string("2026-08-26T01:40:00Z")
                ]),
                .object([
                    "type": .string("concurrency"),
                    "value": .number(10),
                    "used_at": .string("2026-08-26T01:50:00Z")
                ])
            ])
        ])
        let payments: JSONValue = .object([
            "data": .object([
                "items": .array([
                    .object([
                        "order_type": .string("balance"),
                        "status": .string("completed"),
                        "amount": .number(20),
                        "payment_type": .string("alipay"),
                        "completed_at": .string("2026-08-26T01:20:00Z")
                    ])
                ])
            ])
        ])

        let activities = BalanceActivityParser.parse(
            redeemResponse: redeem,
            paymentResponse: payments
        )

        XCTAssertEqual(activities.count, 2)
        XCTAssertEqual(activities.map(\.title), ["管理员增加余额", "余额充值"])
        XCTAssertEqual(activities.map(\.amountChange), [5, 20])
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

    /// 验证平台额度接口能同时保留 OpenAI 周额度、月额度及两套独立重置时间。
    func testPlatformQuotaParserKeepsWeeklyAndMonthlyWindows() throws {
        let fixture = """
        {
          "platform_quotas": [{
            "platform": "openai",
            "daily_limit_usd": null,
            "weekly_limit_usd": 550,
            "monthly_limit_usd": 2200,
            "weekly_usage_usd": 0.11,
            "monthly_usage_usd": 0.02,
            "weekly_window_resets_at": "2026-08-30T16:00:00Z",
            "monthly_window_resets_at": "2026-09-27T01:47:00Z"
          }]
        }
        """
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(fixture.utf8))

        let quotas = PlatformQuotaParser.parse(value)
        let openAI = try XCTUnwrap(quotas.first)

        XCTAssertEqual(openAI.platform, "openai")
        XCTAssertEqual(openAI.weekly?.used, 0.11)
        XCTAssertEqual(openAI.weekly?.limit, 550)
        XCTAssertEqual(openAI.weekly?.resetsAt, "2026-08-30T16:00:00Z")
        XCTAssertEqual(openAI.monthly?.used, 0.02)
        XCTAssertEqual(openAI.monthly?.limit, 2_200)
        XCTAssertEqual(openAI.monthly?.resetsAt, "2026-09-27T01:47:00Z")
        XCTAssertEqual(openAI.weekly?.remaining, 549.89)
    }

    /// 验证只有用量或重置时间、但没有正数上限的周期不会被误判为已配置额度。
    func testPlatformQuotaParserHidesWindowsWithoutPositiveLimits() throws {
        let fixture = """
        {
          "platform_quotas": [{
            "platform": "openai",
            "daily_limit_usd": 0,
            "weekly_usage_usd": 12.5,
            "weekly_window_resets_at": "2026-09-07T00:00:00Z",
            "monthly_limit_usd": null,
            "monthly_usage_usd": 40
          }]
        }
        """
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(fixture.utf8))

        let quota = try XCTUnwrap(PlatformQuotaParser.parse(value).first)

        XCTAssertNil(quota.daily)
        XCTAssertNil(quota.weekly)
        XCTAssertNil(quota.monthly)
        XCTAssertFalse(quota.hasConfiguredQuota)
    }

    /// 验证仪表盘不会为只有周用量、没有周上限的平台保留额度区域。
    func testDashboardHidesQuotaSummaryWhenNoLimitIsConfigured() throws {
        let fixture = """
        {"platform_quotas":[{"platform":"openai","weekly_usage_usd":12.5}]}
        """
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(fixture.utf8))

        let snapshot = DashboardParser.parse(
            profile: nil,
            subscriptionSummary: nil,
            subscriptionProgress: nil,
            platformQuotas: value,
            usageStats: nil,
            modelStats: nil
        )

        XCTAssertNil(snapshot.primaryPlatformQuota)
        XCTAssertFalse(snapshot.hasLegacyQuota)
        XCTAssertFalse(snapshot.hasQuotaSummary)
    }

    /// 验证仪表盘兼容字段优先采用 OpenAI 周额度，而不是误取订阅总额。
    func testDashboardParserPrefersOpenAIPlatformWeeklyQuota() throws {
        let platformFixture = """
        {"platform_quotas":[{"platform":"openai","weekly_limit_usd":550,"weekly_usage_usd":0.11}]}
        """
        let subscriptionFixture = """
        {"quota_total":5000,"quota_used":4000}
        """
        let decoder = JSONDecoder()
        let platform = try decoder.decode(JSONValue.self, from: Data(platformFixture.utf8))
        let subscription = try decoder.decode(JSONValue.self, from: Data(subscriptionFixture.utf8))

        let snapshot = DashboardParser.parse(
            profile: nil,
            subscriptionSummary: subscription,
            subscriptionProgress: subscription,
            platformQuotas: platform,
            usageStats: nil,
            modelStats: nil
        )

        XCTAssertEqual(snapshot.quotaUsed, 0.11)
        XCTAssertEqual(snapshot.quotaTotal, 550)
        XCTAssertEqual(snapshot.primaryPlatformQuota?.displayName, "OpenAI")
    }

    /// 验证用户端分页响应可以解析密钥和真实使用记录，且 Token 口径包含缓存。
    func testUserPortalParserDecodesKeysAndUsageRecords() throws {
        let keysFixture = """
        {"data":{"items":[{
          "id":7,"name":"Codex","key":"sk-test-1234","status":"active",
          "current_concurrency":2,"quota":100,"quota_used":12.5,
          "group":{"name":"OpenAI"},"created_at":"2026-08-28T01:00:00Z"
        }]}}
        """
        let usageFixture = """
        {"items":[{
          "id":9,"api_key_id":7,"model":"gpt-5.6-sol","input_tokens":100,
          "output_tokens":20,"cache_creation_tokens":5,"cache_read_tokens":25,
          "total_cost":0.20,"actual_cost":0.16,"rate_multiplier":0.8,
          "duration_ms":1200,"created_at":"2026-08-28T02:00:00Z"
        }]}
        """
        let decoder = JSONDecoder()
        let keysValue = try decoder.decode(JSONValue.self, from: Data(keysFixture.utf8))
        let usageValue = try decoder.decode(JSONValue.self, from: Data(usageFixture.utf8))

        let keys = UserPortalParser.apiKeys(from: keysValue)
        let records = UserPortalParser.usageRecords(from: usageValue)

        XCTAssertEqual(keys.first?.id, 7)
        XCTAssertEqual(keys.first?.groupName, "OpenAI")
        XCTAssertEqual(keys.first?.quotaProgress, 0.125)
        XCTAssertEqual(records.first?.model, "gpt-5.6-sol")
        XCTAssertEqual(records.first?.totalTokens, 150)
        XCTAssertEqual(records.first?.actualCost, 0.16)
    }

    /// 验证使用记录分页元数据和详情字段可以一起解析，滚动加载不会错误判断最后一页。
    func testUserPortalParserKeepsUsagePaginationAndDetailFields() throws {
        let fixture = """
        {
          "items":[{
            "id":21,"request_id":"req_21","api_key_id":7,"model":"gpt-5.6-sol",
            "inbound_endpoint":"/v1/responses","input_tokens":120,"output_tokens":30,
            "cache_creation_tokens":10,"cache_read_tokens":40,"input_cost":0.02,
            "output_cost":0.01,"cache_creation_cost":0.003,"cache_read_cost":0.002,
            "total_cost":0.035,"actual_cost":0.028,"rate_multiplier":0.8,
            "request_type":"stream","billing_type":1,"billing_mode":"standard",
            "stream":true,"duration_ms":900,"first_token_ms":240,
            "created_at":"2026-08-28T02:00:00Z"
          }],
          "page":2,"page_size":50,"total":121,"pages":3
        }
        """
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(fixture.utf8))

        let page = UserPortalParser.usagePage(from: value)
        let record = try XCTUnwrap(page.records.first)

        XCTAssertEqual(page.page, 2)
        XCTAssertEqual(page.pageSize, 50)
        XCTAssertEqual(page.total, 121)
        XCTAssertEqual(page.pages, 3)
        XCTAssertEqual(record.requestID, "req_21")
        XCTAssertEqual(record.inputTokens, 120)
        XCTAssertEqual(record.cacheReadTokens, 40)
        XCTAssertEqual(record.firstTokenMilliseconds, 240)
        XCTAssertTrue(record.isStream)
    }

    /// 验证订阅进度接口会覆盖列表中的旧用量，并保留日、周、月上限与重置倒计时。
    func testUserPortalParserMergesSubscriptionProgress() throws {
        let subscriptions = """
        [{"id":5,"status":"active","daily_usage_usd":1,"weekly_usage_usd":2,
          "monthly_usage_usd":3,"group":{"name":"OpenAI","daily_limit_usd":100,
          "weekly_limit_usd":550,"monthly_limit_usd":2200}}]
        """
        let progress = """
        [{"subscription_id":5,"daily":{"used":4,"limit":100,"reset_in_seconds":3600},
          "weekly":{"used":18,"limit":550,"reset_in_seconds":7200},
          "monthly":{"used":82,"limit":2200,"reset_in_seconds":10800}}]
        """
        let decoder = JSONDecoder()
        let subscriptionValue = try decoder.decode(JSONValue.self, from: Data(subscriptions.utf8))
        let progressValue = try decoder.decode(JSONValue.self, from: Data(progress.utf8))

        let item = try XCTUnwrap(
            UserPortalParser.subscriptions(from: subscriptionValue, progressResponse: progressValue).first
        )

        XCTAssertEqual(item.dailyUsage, 4)
        XCTAssertEqual(item.weeklyLimit, 550)
        XCTAssertEqual(item.monthlyLimit, 2_200)
        XCTAssertEqual(item.dailyResetInSeconds, 3_600)
        XCTAssertEqual(item.configuredDailyLimit, 100)
        XCTAssertEqual(item.configuredWeeklyLimit, 550)
        XCTAssertEqual(item.configuredMonthlyLimit, 2_200)
        XCTAssertTrue(item.hasConfiguredQuota)
    }

    /// 验证订阅周期的空值和零上限都不会进入界面，仅保留真实配置的正数额度。
    func testSubscriptionConfiguredLimitsIgnoreMissingAndZeroValues() throws {
        let subscriptions = """
        [{"id":8,"status":"active","daily_usage_usd":1,"weekly_usage_usd":2,
          "monthly_usage_usd":3,"group":{"name":"OpenAI","daily_limit_usd":50,
          "weekly_limit_usd":0,"monthly_limit_usd":null}}]
        """
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(subscriptions.utf8))
        let item = try XCTUnwrap(UserPortalParser.subscriptions(from: value, progressResponse: nil).first)

        XCTAssertEqual(item.configuredDailyLimit, 50)
        XCTAssertNil(item.configuredWeeklyLimit)
        XCTAssertNil(item.configuredMonthlyLimit)
        XCTAssertTrue(item.hasConfiguredQuota)
    }

    /// 创建完全隔离的临时用户目录，导入测试不会触碰当前机器上的真实客户端配置。
    private func makeTemporaryHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "SubPilotImportTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 创建只包含导入测试所需字段的虚拟 API 密钥，令牌不对应任何真实服务。
    private func makePortalAPIKey() -> UserAPIKey {
        UserAPIKey(
            id: 99,
            name: "Test Key",
            key: "sk-subpilot-test",
            groupName: "OpenAI",
            currentConcurrency: 0,
            quota: 0,
            quotaUsed: 0,
            status: "active",
            expiresAt: nil,
            createdAt: nil,
            lastUsedAt: nil,
            ipWhitelist: [],
            ipBlacklist: [],
            rateLimit5Hours: 0,
            rateLimit1Day: 0,
            rateLimit7Days: 0,
            usage5Hours: 0,
            usage1Day: 0,
            usage7Days: 0
        )
    }

    /// 执行只返回单个整数的 SQLite 查询，用于核对供应商数量和当前状态。
    private func sqliteInteger(_ database: OpaquePointer, sql: String) -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { return -1 }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return -1 }
        return Int(sqlite3_column_int64(statement, 0))
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
