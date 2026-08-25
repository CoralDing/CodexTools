/**
 * 文件说明：从 CC Switch 本地数据库读取 Codex 会话用量，作为倍率分析的独立调用依据
 * 作者：dingyi60(Codex)
 * 创建时间：2026-08-25
 */

import Foundation
import SQLite3

/// 表示指定时间窗口内由 CC Switch 从 Codex 会话日志计算出的本地用量。
struct LocalCodexUsageSummary: Sendable, Equatable {
    let requestCount: Int
    let inputTokens: Double
    let outputTokens: Double
    let cacheReadTokens: Double
    let cacheCreationTokens: Double
    let standardCost: Double
    let latestRecordAt: Date?

    /// Codex 的输入 Token 已包含缓存读取部分，因此总量只使用输入与输出相加，避免重复计算缓存。
    var totalTokens: Double {
        inputTokens + outputTokens
    }
}

/// 描述读取 CC Switch 本地用量失败的原因，避免把数据源缺失误报成零调用。
enum LocalCodexUsageStoreError: LocalizedError, Sendable {
    case databaseNotFound
    case databaseUnavailable(String)
    case invalidSchema(String)

    /// 转换成面向用户的简短说明，并指出需要检查的本地数据源。
    var errorDescription: String? {
        switch self {
        case .databaseNotFound:
            return "未找到 CC Switch 本地用量数据库，请先在 CC Switch 中同步 Codex 用量。"
        case let .databaseUnavailable(message):
            return "无法读取 CC Switch 本地用量：\(message)"
        case let .invalidSchema(message):
            return "CC Switch 用量数据库结构不兼容：\(message)"
        }
    }
}

/// 以只读方式查询 CC Switch 已从 `~/.codex/sessions` 同步的 Codex 会话用量。
struct LocalCodexUsageStore: Sendable {
    private let databaseURL: URL

    /// 默认使用 CC Switch 的标准数据库位置，测试时允许注入隔离数据库。
    init(databaseURL: URL? = nil) {
        self.databaseURL = databaseURL
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appending(path: ".cc-switch/cc-switch.db")
    }

    /// 汇总时间窗口内的本地调用；成本直接采用 CC Switch 当前模型价目表计算后的结果。
    func readUsage(windowStart: Date, windowEnd: Date) throws -> LocalCodexUsageSummary {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw LocalCodexUsageStoreError.databaseNotFound
        }

        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard openResult == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "未知错误"
            if let database { sqlite3_close(database) }
            throw LocalCodexUsageStoreError.databaseUnavailable(message)
        }
        defer { sqlite3_close(database) }

        // CC Switch 可能正在写入 WAL（预写日志），短暂等待可避免同步瞬间出现数据库忙错误。
        sqlite3_busy_timeout(database, 1_000)

        let query = """
            SELECT
                COUNT(*),
                COALESCE(SUM(CAST(input_tokens AS REAL)), 0),
                COALESCE(SUM(CAST(output_tokens AS REAL)), 0),
                COALESCE(SUM(CAST(cache_read_tokens AS REAL)), 0),
                COALESCE(SUM(CAST(cache_creation_tokens AS REAL)), 0),
                COALESCE(SUM(CAST(total_cost_usd AS REAL)), 0),
                MAX(created_at)
            FROM proxy_request_logs
            WHERE app_type = 'codex'
              AND data_source = 'codex_session'
              AND created_at >= ?1
              AND created_at <= ?2
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw LocalCodexUsageStoreError.invalidSchema(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }

        // CC Switch 的 created_at 使用 Unix 秒；起点向下、终点向上取整，避免丢掉边界调用。
        sqlite3_bind_int64(statement, 1, Int64(floor(windowStart.timeIntervalSince1970)))
        sqlite3_bind_int64(statement, 2, Int64(ceil(windowEnd.timeIntervalSince1970)))

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw LocalCodexUsageStoreError.databaseUnavailable(String(cString: sqlite3_errmsg(database)))
        }

        let latestRecordAt: Date?
        if sqlite3_column_type(statement, 6) == SQLITE_NULL {
            latestRecordAt = nil
        } else {
            latestRecordAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 6))
        }

        return LocalCodexUsageSummary(
            requestCount: Int(sqlite3_column_int64(statement, 0)),
            inputTokens: sqlite3_column_double(statement, 1),
            outputTokens: sqlite3_column_double(statement, 2),
            cacheReadTokens: sqlite3_column_double(statement, 3),
            cacheCreationTokens: sqlite3_column_double(statement, 4),
            standardCost: sqlite3_column_double(statement, 5),
            latestRecordAt: latestRecordAt
        )
    }
}
