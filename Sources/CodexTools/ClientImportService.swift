/**
 * 文件说明：将 SubPilot API 密钥安全导入常用 AI 编程客户端
 * 作者：dingyi60(Codex)
 * 创建时间：2026-08-28
 */

import Foundation
import SQLite3

/// 表示密钥可以导入或辅助配置的常用客户端。
enum APIKeyClientTarget: String, CaseIterable, Identifiable, Sendable {
    case codex
    case claudeCode
    case cursor
    case ccSwitch

    var id: String { rawValue }

    /// 使用用户熟悉的客户端名称，避免把 Claude Code 与 Claude 桌面版混淆。
    var title: String {
        switch self {
        case .codex: return "Codex"
        case .claudeCode: return "Claude Code"
        case .cursor: return "Cursor"
        case .ccSwitch: return "CC Switch"
        }
    }

    /// SF Symbols（苹果系统图标库）图标只用于快速辨认导入目标。
    var systemImage: String {
        switch self {
        case .codex: return "terminal"
        case .claudeCode: return "chevron.left.forwardslash.chevron.right"
        case .cursor: return "cursorarrow.rays"
        case .ccSwitch: return "arrow.triangle.2.circlepath"
        }
    }

    /// 明确说明写入范围；Cursor 没有稳定公开接口，因此不宣称可以完全自动导入。
    var detail: String {
        switch self {
        case .codex: return "创建独立 SubPilot Profile，不覆盖默认配置"
        case .claudeCode: return "备份并合并 ~/.claude/settings.json"
        case .cursor: return "复制密钥并打开模型设置，需要手动确认"
        case .ccSwitch: return "导入 Codex 与 Claude 供应商，保留当前选择"
        }
    }

    /// 按行为差异提供准确的按钮文案。
    var actionTitle: String {
        self == .cursor ? "复制并打开" : "一键导入"
    }
}

/// 描述一次客户端导入的结果和用户下一步操作。
struct APIKeyImportResult: Sendable, Equatable {
    let message: String
    let detail: String
}

/// 集中描述导入器使用的用户目录，生产指向真实主目录，测试可注入完全隔离的位置。
struct APIKeyImportPaths: Sendable {
    let homeDirectory: URL

    /// 运行应用时使用当前 macOS 用户的主目录。
    static var live: APIKeyImportPaths {
        APIKeyImportPaths(homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
    }
}

/// 将导入过程中的文件、数据库和输入错误转换为可理解的提示。
enum APIKeyImportError: LocalizedError, Sendable {
    case invalidModel
    case invalidKey
    case malformedConfiguration(String)
    case ccSwitchNotFound
    case ccSwitchSchemaUnsupported
    case database(String)

    /// 错误信息明确指出未完成的步骤，不把本地配置问题误报成网络错误。
    var errorDescription: String? {
        switch self {
        case .invalidModel:
            return "模型名称不能为空，请填写服务端支持的模型。"
        case .invalidKey:
            return "API 密钥为空，无法导入。"
        case let .malformedConfiguration(path):
            return "现有配置文件格式无效，为避免覆盖已停止写入：\(path)"
        case .ccSwitchNotFound:
            return "未找到 CC Switch 数据库，请先安装并打开 CC Switch 一次。"
        case .ccSwitchSchemaUnsupported:
            return "当前 CC Switch 数据库结构不受支持，请升级 CC Switch 后重试。"
        case let .database(message):
            return "CC Switch 导入失败：\(message)"
        }
    }
}

/// 负责所有本地配置写入；调用方只传入当前密钥、服务地址和用户确认的模型。
enum APIKeyClientImportService {
    /// 每次操作获取系统文件管理器，避免把非 Sendable（不可安全跨线程传递）对象保存为共享状态。
    private static var fileManager: FileManager { FileManager.default }

    /// 根据目标选择对应导入器；Cursor 由界面完成剪贴板和设置页跳转，不在这里写私有配置。
    static func importKey(
        _ key: UserAPIKey,
        serverURL: URL,
        model: String,
        target: APIKeyClientTarget,
        paths: APIKeyImportPaths = .live
    ) throws -> APIKeyImportResult {
        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedModel.isEmpty else { throw APIKeyImportError.invalidModel }
        guard !key.key.isEmpty else { throw APIKeyImportError.invalidKey }

        switch target {
        case .codex:
            return try importIntoCodex(key: key, serverURL: serverURL, model: normalizedModel, paths: paths)
        case .claudeCode:
            return try importIntoClaudeCode(key: key, serverURL: serverURL, model: normalizedModel, paths: paths)
        case .ccSwitch:
            return try importIntoCCSwitch(key: key, serverURL: serverURL, model: normalizedModel, paths: paths)
        case .cursor:
            return APIKeyImportResult(
                message: "API 密钥已复制",
                detail: "请在 Cursor 的 Models 设置中粘贴密钥；自定义 Base URL 需按当前 Cursor 版本手动确认。"
            )
        }
    }

    /// 为 Codex 创建独立 Profile，并让官方支持的命令认证从权限受限文件读取令牌。
    private static func importIntoCodex(
        key: UserAPIKey,
        serverURL: URL,
        model: String,
        paths: APIKeyImportPaths
    ) throws -> APIKeyImportResult {
        let home = paths.homeDirectory
        let codexDirectory = home.appending(path: ".codex", directoryHint: .isDirectory)
        let secretDirectory = home.appending(path: ".config/subpilot", directoryHint: .isDirectory)
        let secretURL = secretDirectory.appending(path: "api-key-\(key.id)")
        let profileURL = codexDirectory.appending(path: "subpilot.config.toml")

        try createPrivateDirectory(secretDirectory)
        try fileManager.createDirectory(at: codexDirectory, withIntermediateDirectories: true)
        try backupIfNeeded(profileURL, category: "codex", paths: paths)
        try atomicWrite(Data((key.key + "\n").utf8), to: secretURL, permissions: 0o600)

        let profile = """
        model_provider = "subpilot"
        model = "\(tomlEscaped(model))"

        [model_providers.subpilot]
        name = "SubPilot"
        base_url = "\(tomlEscaped(openAIBaseURL(from: serverURL)))"
        wire_api = "responses"

        [model_providers.subpilot.auth]
        command = "/bin/cat"
        args = ["\(tomlEscaped(secretURL.path))"]
        """
        try atomicWrite(Data((profile + "\n").utf8), to: profileURL, permissions: 0o600)
        return APIKeyImportResult(
            message: "已导入 Codex Profile",
            detail: "运行 codex --profile subpilot 即可使用，原有默认配置未修改。"
        )
    }

    /// 结构化合并 Claude Code 的环境变量，保留用户已有权限、钩子和其他设置。
    private static func importIntoClaudeCode(
        key: UserAPIKey,
        serverURL: URL,
        model: String,
        paths: APIKeyImportPaths
    ) throws -> APIKeyImportResult {
        let settingsURL = paths.homeDirectory
            .appending(path: ".claude/settings.json")
        var root: [String: Any] = [:]
        if fileManager.fileExists(atPath: settingsURL.path) {
            let data = try Data(contentsOf: settingsURL)
            guard let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw APIKeyImportError.malformedConfiguration(settingsURL.path)
            }
            root = decoded
            try backupIfNeeded(settingsURL, category: "claude", paths: paths)
        }

        var environment = root["env"] as? [String: Any] ?? [:]
        environment["ANTHROPIC_BASE_URL"] = rootBaseURL(from: serverURL)
        environment["ANTHROPIC_AUTH_TOKEN"] = key.key
        environment["ANTHROPIC_MODEL"] = model
        root["env"] = environment

        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try atomicWrite(data + Data("\n".utf8), to: settingsURL, permissions: 0o600)
        return APIKeyImportResult(
            message: "已导入 Claude Code",
            detail: "重新打开 Claude Code 后生效；现有设置已备份并保留。"
        )
    }

    /// 向 CC Switch 数据库写入两个供应商，并在事务前创建一致性备份。
    private static func importIntoCCSwitch(
        key: UserAPIKey,
        serverURL: URL,
        model: String,
        paths: APIKeyImportPaths
    ) throws -> APIKeyImportResult {
        let databaseURL = paths.homeDirectory
            .appending(path: ".cc-switch/cc-switch.db")
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            throw APIKeyImportError.ccSwitchNotFound
        }

        var database: OpaquePointer?
        guard sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "无法打开数据库"
            if let database { sqlite3_close(database) }
            throw APIKeyImportError.database(message)
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 2_000)

        guard tableExists("providers", in: database) else {
            throw APIKeyImportError.ccSwitchSchemaUnsupported
        }
        let backupURL = try backupCCSwitchDatabase(database, paths: paths)
        let codexSettings = try ccSwitchCodexSettings(key: key, serverURL: serverURL, model: model)
        let claudeSettings = try ccSwitchClaudeSettings(key: key, serverURL: serverURL, model: model)
        let providerID = "subpilot-\(key.id)"

        try execute("BEGIN IMMEDIATE", in: database)
        do {
            try upsertCCSwitchProvider(
                database: database,
                id: providerID,
                appType: "codex",
                name: "SubPilot · \(key.name)",
                settings: codexSettings,
                apiFormat: "openai_responses"
            )
            try upsertCCSwitchProvider(
                database: database,
                id: providerID,
                appType: "claude",
                name: "SubPilot · \(key.name)",
                settings: claudeSettings,
                apiFormat: "anthropic"
            )
            try execute("COMMIT", in: database)
        } catch {
            try? execute("ROLLBACK", in: database)
            throw error
        }

        return APIKeyImportResult(
            message: "已导入 CC Switch",
            detail: "已添加 Codex 与 Claude 供应商，当前供应商未切换。备份：\(backupURL.path)"
        )
    }

    /// 生成 CC Switch 可识别的 Codex 供应商 JSON，不修改用户当前 Codex 文件。
    private static func ccSwitchCodexSettings(
        key: UserAPIKey,
        serverURL: URL,
        model: String
    ) throws -> String {
        let config = """
        model_provider = "subpilot"
        model = "\(tomlEscaped(model))"

        [model_providers.subpilot]
        name = "SubPilot"
        base_url = "\(tomlEscaped(openAIBaseURL(from: serverURL)))"
        wire_api = "responses"
        requires_openai_auth = true
        """
        return try jsonString(["auth": ["OPENAI_API_KEY": key.key], "config": config + "\n"])
    }

    /// 生成 CC Switch 可识别的 Claude 环境变量 JSON，密钥只进入本机数据库。
    private static func ccSwitchClaudeSettings(
        key: UserAPIKey,
        serverURL: URL,
        model: String
    ) throws -> String {
        try jsonString([
            "env": [
                "ANTHROPIC_AUTH_TOKEN": key.key,
                "ANTHROPIC_BASE_URL": rootBaseURL(from: serverURL),
                "ANTHROPIC_MODEL": model
            ]
        ])
    }

    /// 在不改变 `is_current` 的前提下新增或更新 SubPilot 供应商。
    private static func upsertCCSwitchProvider(
        database: OpaquePointer,
        id: String,
        appType: String,
        name: String,
        settings: String,
        apiFormat: String
    ) throws {
        let sql = """
        INSERT INTO providers (
            id, app_type, name, settings_config, created_at, notes, meta,
            is_current, in_failover_queue, cost_multiplier
        ) VALUES (?1, ?2, ?3, ?4, ?5, '由 SubPilot 导入', ?6, 0, 0, '1.0')
        ON CONFLICT(id, app_type) DO UPDATE SET
            name = excluded.name,
            settings_config = excluded.settings_config,
            notes = excluded.notes,
            meta = excluded.meta
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw APIKeyImportError.ccSwitchSchemaUnsupported
        }
        defer { sqlite3_finalize(statement) }
        let meta = try jsonString([
            "commonConfigEnabled": true,
            "endpointAutoSelect": true,
            "apiFormat": apiFormat
        ])
        bind(id, at: 1, to: statement)
        bind(appType, at: 2, to: statement)
        bind(name, at: 3, to: statement)
        bind(settings, at: 4, to: statement)
        sqlite3_bind_int64(statement, 5, Int64(Date().timeIntervalSince1970 * 1_000))
        bind(meta, at: 6, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw APIKeyImportError.database(String(cString: sqlite3_errmsg(database)))
        }
    }

    /// 使用 SQLite 在线备份接口生成可恢复副本，即使 CC Switch 正在读取数据库也保持一致。
    private static func backupCCSwitchDatabase(
        _ source: OpaquePointer,
        paths: APIKeyImportPaths
    ) throws -> URL {
        let directory = paths.homeDirectory
            .appending(path: ".cc-switch/subpilot-backups/\(timestamp())", directoryHint: .isDirectory)
        try createPrivateDirectory(directory)
        let backupURL = directory.appending(path: "cc-switch.db")
        var destination: OpaquePointer?
        guard sqlite3_open(backupURL.path, &destination) == SQLITE_OK, let destination else {
            if let destination { sqlite3_close(destination) }
            throw APIKeyImportError.database("无法创建备份数据库")
        }
        defer { sqlite3_close(destination) }
        guard let backup = sqlite3_backup_init(destination, "main", source, "main") else {
            throw APIKeyImportError.database(String(cString: sqlite3_errmsg(destination)))
        }
        let stepResult = sqlite3_backup_step(backup, -1)
        let finishResult = sqlite3_backup_finish(backup)
        guard stepResult == SQLITE_DONE, finishResult == SQLITE_OK else {
            throw APIKeyImportError.database("数据库备份未完成")
        }
        return backupURL
    }

    /// 查询目标表是否存在，避免向未知版本数据库执行不兼容 SQL。
    private static func tableExists(_ name: String, in database: OpaquePointer) -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?1",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else { return false }
        defer { sqlite3_finalize(statement) }
        bind(name, at: 1, to: statement)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    /// 执行不带参数的事务语句，并统一转换 SQLite 错误。
    private static func execute(_ sql: String, in database: OpaquePointer) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw APIKeyImportError.database(String(cString: sqlite3_errmsg(database)))
        }
    }

    /// 将 Swift 字符串绑定到 SQLite，并让数据库在当前语句结束前持有安全副本。
    private static func bind(_ value: String, at index: Int32, to statement: OpaquePointer) {
        sqlite3_bind_text(statement, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }

    /// 将字典编码为紧凑 JSON，CC Switch 会在自身界面中再次解析这些字段。
    private static func jsonString(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard let value = String(data: data, encoding: .utf8) else {
            throw APIKeyImportError.malformedConfiguration("CC Switch 供应商配置")
        }
        return value
    }

    /// 给已有配置创建带时间戳的副本；源文件不存在时无需生成空备份。
    private static func backupIfNeeded(
        _ source: URL,
        category: String,
        paths: APIKeyImportPaths
    ) throws {
        guard fileManager.fileExists(atPath: source.path) else { return }
        let directory = paths.homeDirectory
            .appending(path: ".config/subpilot/backups/\(category)/\(timestamp())", directoryHint: .isDirectory)
        try createPrivateDirectory(directory)
        try fileManager.copyItem(at: source, to: directory.appending(path: source.lastPathComponent))
    }

    /// 原子写入后收紧权限，防止应用中途退出留下半份配置或让其他本机用户读取密钥。
    private static func atomicWrite(_ data: Data, to url: URL, permissions: Int16) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: NSNumber(value: permissions)], ofItemAtPath: url.path)
    }

    /// 创建仅当前用户可访问的目录，已有目录也会重新校正权限。
    private static func createPrivateDirectory(_ url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    /// 返回不带尾部斜杠的服务根地址，Claude Code 会自行追加消息接口路径。
    private static func rootBaseURL(from serverURL: URL) -> String {
        serverURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// Codex Responses Provider 使用包含 `/v1` 的 API Base URL。
    private static func openAIBaseURL(from serverURL: URL) -> String {
        rootBaseURL(from: serverURL) + "/v1"
    }

    /// 转义 TOML（常见配置文件格式）字符串中的控制字符，模型名无法注入额外配置行。
    private static func tomlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }

    /// 生成文件名安全且按时间排序的备份目录片段。
    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter.string(from: Date())
    }
}
