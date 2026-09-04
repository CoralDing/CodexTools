/**
 * 文件说明：Sub2API 用户端功能迁移后的原生 macOS 页面集合
 * 作者：dingyi60(Codex)
 * 创建时间：2026-08-28
 */

import AppKit
import Charts
import SwiftUI
import UniformTypeIdentifiers

/// API 密钥管理页，支持常用的搜索、创建、复制、启停和删除操作。
private struct LegacyAPIKeysPortalView: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""
    @State private var showsCreateSheet = false
    @State private var newKeyName = ""
    @State private var keyPendingDeletion: UserAPIKey?

    /// 页面使用单层工具栏和表格列表，避免把每一枚密钥做成独立大卡片。
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                TextField("搜索名称或密钥", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)

                Spacer()

                Button {
                    newKeyName = ""
                    showsCreateSheet = true
                } label: {
                    Label("创建密钥", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
            }

            portalMessageBanner

            if appState.apiKeys.isEmpty && !appState.isLoadingPortal {
                ContentUnavailableView {
                    Label("暂无 API 密钥", systemImage: "key")
                } description: {
                    Text("创建密钥后即可在 Codex 或其他客户端中使用")
                } actions: {
                    Button("创建密钥") { showsCreateSheet = true }
                }
                .frame(maxWidth: .infinity, minHeight: 330)
                .panelSurface()
            } else {
                keyTable
            }
        }
        .task { await appState.loadAPIKeys() }
        .sheet(isPresented: $showsCreateSheet) { createSheet }
        .alert(
            "删除 API 密钥？",
            isPresented: Binding(
                get: { keyPendingDeletion != nil },
                set: { if !$0 { keyPendingDeletion = nil } }
            ),
            presenting: keyPendingDeletion
        ) { key in
            Button("删除", role: .destructive) {
                Task { await appState.deleteAPIKey(key) }
            }
            Button("取消", role: .cancel) {}
        } message: { key in
            Text("“\(key.name)”删除后无法恢复，正在使用它的客户端会立即失效。")
        }
    }

    /// 过滤只作用于当前已加载列表，不额外发送搜索内容到服务器。
    private var filteredKeys: [UserAPIKey] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return appState.apiKeys }
        return appState.apiKeys.filter {
            $0.name.lowercased().contains(query) || $0.key.lowercased().contains(query)
        }
    }

    /// 表头和数据行使用相同列宽，密钥数量变化不会推动操作按钮位置。
    private var keyTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("名称").frame(maxWidth: .infinity, alignment: .leading)
                Text("分组").frame(width: 110, alignment: .leading)
                Text("用量").frame(width: 130, alignment: .leading)
                Text("并发").frame(width: 60, alignment: .trailing)
                Text("状态").frame(width: 74, alignment: .leading)
                Text("操作").frame(width: 112, alignment: .trailing)
            }
            .font(AppTheme.captionFont.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .frame(height: 36)

            Divider()

            ForEach(filteredKeys) { key in
                keyRow(key)
                if key.id != filteredKeys.last?.id { Divider().padding(.leading, 14) }
            }
        }
        .panelSurface(padding: 0)
    }

    /// 单行同时展示密钥尾号和额度，不在列表中暴露不必要的完整认证信息。
    private func keyRow(_ key: UserAPIKey) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(key.name)
                    .font(.system(size: 12, weight: .medium))
                Text(maskedKey(key.key))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(key.groupName ?? "未分组")
                .frame(width: 110, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(key.quota > 0
                    ? "\(UsageFormatter.cost(key.quotaUsed)) / \(UsageFormatter.cost(key.quota))"
                    : "不限额")
                if let progress = key.quotaProgress {
                    ProgressView(value: progress)
                        .tint(AppTheme.accent)
                        .controlSize(.small)
                }
            }
            .frame(width: 130, alignment: .leading)

            Text(key.currentConcurrency.formatted())
                .monospacedDigit()
                .frame(width: 60, alignment: .trailing)

            Label(statusTitle(key.status), systemImage: statusIcon(key.status))
                .foregroundStyle(statusColor(key.status))
                .frame(width: 74, alignment: .leading)

            HStack(spacing: 4) {
                Button {
                    copyKey(key.key)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help("复制 API 密钥")

                Button {
                    Task { await appState.setAPIKey(key, enabled: key.status != "active") }
                } label: {
                    Image(systemName: key.status == "active" ? "pause" : "play")
                }
                .help(key.status == "active" ? "停用密钥" : "启用密钥")

                Button(role: .destructive) {
                    keyPendingDeletion = key
                } label: {
                    Image(systemName: "trash")
                }
                .help("删除密钥")
            }
            .buttonStyle(.borderless)
            .frame(width: 112, alignment: .trailing)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 14)
        .frame(minHeight: 60)
    }

    /// 创建弹窗只收集必要名称，高级限制仍可以在后续版本中按接口字段逐步开放。
    private var createSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("创建 API 密钥")
                .font(.system(size: 18, weight: .semibold))
            TextField("例如：Codex 主密钥", text: $newKeyName)
                .textFieldStyle(.roundedBorder)
            Text("创建后请立即复制并妥善保存密钥。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("取消") { showsCreateSheet = false }
                    .keyboardShortcut(.cancelAction)
                Button("创建") {
                    Task {
                        if await appState.createAPIKey(name: newKeyName) {
                            showsCreateSheet = false
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newKeyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 390)
    }

    /// 页面级错误或成功消息使用同一横条，不打断当前列表操作。
    @ViewBuilder
    private var portalMessageBanner: some View {
        if let error = appState.portalErrorMessage {
            PortalMessageBanner(message: error, isError: true)
        } else if let success = appState.portalSuccessMessage {
            PortalMessageBanner(message: success, isError: false)
        }
    }

    /// 只显示密钥前缀和末四位，复制按钮仍使用内存中的完整服务端返回值。
    private func maskedKey(_ key: String) -> String {
        guard key.count > 10 else { return key }
        return "\(key.prefix(7))••••\(key.suffix(4))"
    }

    /// 把用户主动选择的密钥写入系统剪贴板，不落盘也不进入应用日志。
    private func copyKey(_ key: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(key, forType: .string)
        appState.portalSuccessMessage = "API 密钥已复制"
    }

    /// 将服务端状态转换为用户可理解的短标题。
    private func statusTitle(_ status: String) -> String {
        switch status {
        case "active": return "启用"
        case "inactive": return "停用"
        case "expired": return "过期"
        case "quota_exhausted": return "用尽"
        default: return "未知"
        }
    }

    /// 不同状态使用稳定的系统图标，颜色只承担辅助识别作用。
    private func statusIcon(_ status: String) -> String {
        status == "active" ? "checkmark.circle.fill" : "circle"
    }

    /// 启用使用强调色，额度用尽和过期使用警示色，其余保持次级层级。
    private func statusColor(_ status: String) -> Color {
        switch status {
        case "active": return AppTheme.accent
        case "expired", "quota_exhausted": return AppTheme.warning
        default: return .secondary
        }
    }
}

/// 完整使用记录页，提供本地搜索和服务端周期过滤后的真实账单行。
private struct LegacyUsageRecordsPortalView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage(PreferenceKey.displayTimeZone) private var displayTimeZone = TimeZone.current.identifier
    @State private var searchText = ""

    /// 表格上方只保留搜索控件，统计周期由主窗口顶部统一控制。
    var body: some View {
        VStack(spacing: 14) {
            HStack {
                TextField("搜索模型、密钥或分组", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
                Spacer()
                Text("最新 \(filteredRecords.count) 条")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if appState.portalUsageRecords.isEmpty && !appState.isLoadingPortal {
                ContentUnavailableView {
                    Label("当前周期暂无使用记录", systemImage: "chart.xyaxis.line")
                } description: {
                    Text("切换今天、7 天或 30 天后可查看其他时间范围")
                }
                .frame(maxWidth: .infinity, minHeight: 330)
                .panelSurface()
            } else {
                usageTable
            }
        }
        .task { await appState.loadPortalUsageRecords() }
    }

    /// 搜索不上传关键字，所有过滤均在本机当前列表中完成。
    private var filteredRecords: [PortalUsageRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return appState.portalUsageRecords }
        return appState.portalUsageRecords.filter {
            $0.model.lowercased().contains(query)
                || $0.apiKeyName.lowercased().contains(query)
                || ($0.groupName?.lowercased().contains(query) ?? false)
        }
    }

    /// 表格保留最常用七列，端点和倍率等细节可从模型与费用口径推断。
    private var usageTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("时间").frame(width: 116, alignment: .leading)
                Text("模型").frame(maxWidth: .infinity, alignment: .leading)
                Text("API 密钥").frame(width: 120, alignment: .leading)
                Text("Token").frame(width: 78, alignment: .trailing)
                Text("实扣 / 标准").frame(width: 126, alignment: .trailing)
                Text("倍率").frame(width: 54, alignment: .trailing)
                Text("响应").frame(width: 72, alignment: .trailing)
            }
            .font(AppTheme.captionFont.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .frame(height: 36)
            Divider()

            ForEach(filteredRecords) { record in
                HStack(spacing: 12) {
                    Text(formattedDate(record.createdAt))
                        .frame(width: 116, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.model).fontWeight(.medium)
                        Text(record.groupName ?? record.endpoint ?? "—")
                            .font(AppTheme.captionFont)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(record.apiKeyName)
                        .lineLimit(1)
                        .frame(width: 120, alignment: .leading)
                    Text(UsageFormatter.compactTokens(record.totalTokens))
                        .monospacedDigit()
                        .frame(width: 78, alignment: .trailing)
                    Text("\(UsageFormatter.cost(record.actualCost)) / \(UsageFormatter.cost(record.standardCost))")
                        .monospacedDigit()
                        .frame(width: 126, alignment: .trailing)
                    Text(record.multiplier.map { String(format: "%.2f×", $0) } ?? "—")
                        .monospacedDigit()
                        .frame(width: 54, alignment: .trailing)
                    Text(UsageFormatter.duration(milliseconds: record.durationMilliseconds))
                        .monospacedDigit()
                        .frame(width: 72, alignment: .trailing)
                }
                .font(.system(size: 11))
                .padding(.horizontal, 14)
                .frame(minHeight: 52)
                Divider().padding(.leading, 14)
            }
        }
        .panelSurface(padding: 0)
    }

    /// 使用用户选择的时区显示到分钟，避免同一记录在不同页面出现时间差。
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: displayTimeZone) ?? .current
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

/// API 密钥管理页，提供筛选、创建、编辑、限额和访问限制等完整原生操作。
struct APIKeysPortalView: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""
    @State private var statusFilter = "all"
    @State private var groupFilter = "all"
    @State private var showsEditor = false
    @State private var editingKey: UserAPIKey?
    @State private var keyForUsage: UserAPIKey?
    @State private var keyPendingDeletion: UserAPIKey?
    @State private var formName = ""
    @State private var formGroupID: Int?
    @State private var formUsesCustomKey = false
    @State private var formCustomKey = ""
    @State private var formQuota = ""
    @State private var formExpirationDays = ""
    @State private var formIPWhitelist = ""
    @State private var formIPBlacklist = ""
    @State private var formRate5Hours = ""
    @State private var formRate1Day = ""
    @State private var formRate7Days = ""
    @State private var formEnabled = true

    /// 页面使用单层数据表和原生表单弹窗，避免密钥较多时形成卡片墙。
    var body: some View {
        ZStack(alignment: .trailing) {
            VStack(spacing: 12) {
                keyToolbar
                portalMessageBanner
                if filteredKeys.isEmpty && !appState.isLoadingPortal {
                    ContentUnavailableView {
                        Label(appState.apiKeys.isEmpty ? "暂无 API 密钥" : "没有符合条件的密钥", systemImage: "key")
                    } description: {
                        Text(appState.apiKeys.isEmpty ? "创建密钥后即可在 Codex 或其他客户端中使用" : "请调整搜索内容或筛选条件")
                    } actions: {
                        if appState.apiKeys.isEmpty { Button("创建密钥", action: beginCreate) }
                    }
                    .frame(maxWidth: .infinity, minHeight: 360)
                    .panelSurface()
                } else {
                    keyTable
                }
                Spacer(minLength: 0)
            }
            .allowsHitTesting(keyForUsage == nil)
            .accessibilityHidden(keyForUsage != nil)

            if let key = keyForUsage, let serverURL = appState.session?.serverURL {
                // 自定义窗口内浮层让 API 密钥表格真正参与 Liquid Glass 折射，避开系统 Sheet 的独立白色窗口。
                Color.black.opacity(0.22)
                    .contentShape(Rectangle())
                    .onTapGesture { closeUsageSheet() }
                    .transition(.opacity)

                APIKeyUsageSheet(
                    key: key,
                    serverURL: serverURL,
                    suggestedModel: appState.snapshot?.recentModel ?? "gpt-5.6-sol",
                    onDismiss: closeUsageSheet
                )
                .padding(.trailing, 14)
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .zIndex(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 590, alignment: .top)
        .animation(.easeOut(duration: 0.18), value: keyForUsage?.id)
        .onExitCommand {
            if keyForUsage != nil {
                closeUsageSheet()
            }
        }
        .task { await appState.loadAPIKeys() }
        .sheet(isPresented: $showsEditor) {
            keyEditor
                .presentationBackground(.clear)
        }
        .alert(
            "删除 API 密钥？",
            isPresented: Binding(
                get: { keyPendingDeletion != nil },
                set: { if !$0 { keyPendingDeletion = nil } }
            ),
            presenting: keyPendingDeletion
        ) { key in
            Button("删除", role: .destructive) { Task { await appState.deleteAPIKey(key) } }
            Button("取消", role: .cancel) {}
        } message: { key in
            Text("“\(key.name)”删除后无法恢复，正在使用它的客户端会立即失效。")
        }
    }

    /// 统一关闭窗口内导入浮层，点击关闭按钮或遮罩时使用同一段过渡动画。
    private func closeUsageSheet() {
        withAnimation(.easeOut(duration: 0.18)) {
            keyForUsage = nil
        }
    }

    /// 工具栏集中搜索、状态、分组和创建命令，让表格本身保持干净。
    private var keyToolbar: some View {
        HStack(spacing: 8) {
            TextField("搜索名称或密钥", text: $searchText)
                .textFieldStyle(.plain)
                .padding(.horizontal, 11)
                .frame(maxWidth: 280, minHeight: 34)
                .background(AppTheme.controlFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(AppTheme.border, lineWidth: 0.75)
                }
            Picker("状态", selection: $statusFilter) {
                Text("全部状态").tag("all")
                Text("已启用").tag("active")
                Text("已停用").tag("inactive")
                Text("已过期").tag("expired")
            }
            .labelsHidden()
            .frame(width: 118)
            Picker("分组", selection: $groupFilter) {
                Text("全部分组").tag("all")
                ForEach(appState.availableGroups) { group in
                    Text(group.name).tag(String(group.id))
                }
            }
            .labelsHidden()
            .frame(width: 128)
            Spacer()
            Text("共 \(filteredKeys.count) 个")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Button(action: beginCreate) {
                Label("创建密钥", systemImage: "plus")
            }
            .subPilotProminentGlassButtonStyle()
        }
        .padding(10)
        .glassSurface(radius: 12, isInteractive: true)
    }

    /// 搜索与筛选均在已加载列表中完成，不会把密钥文本发送到额外服务。
    private var filteredKeys: [UserAPIKey] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return appState.apiKeys.filter { key in
            let matchesText = query.isEmpty
                || key.name.lowercased().contains(query)
                || key.key.lowercased().contains(query)
            let matchesStatus = statusFilter == "all" || key.status == statusFilter
            let groupID = appState.availableGroups.first { $0.name == key.groupName }?.id
            let matchesGroup = groupFilter == "all" || groupFilter == groupID.map(String.init)
            return matchesText && matchesStatus && matchesGroup
        }
    }

    /// 表格列覆盖额度、频率限制和最近使用时间，避免必须打开网页才能判断密钥状态。
    private var keyTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("名称 / 密钥").frame(maxWidth: .infinity, alignment: .leading)
                Text("分组").frame(width: 92, alignment: .leading)
                Text("总额度").frame(width: 116, alignment: .leading)
                Text("周期限制").frame(width: 110, alignment: .leading)
                Text("最近使用").frame(width: 92, alignment: .leading)
                Text("状态").frame(width: 66, alignment: .leading)
                Text("操作").frame(width: 118, alignment: .trailing)
            }
            .font(AppTheme.captionFont.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(AppTheme.tableHeader)
            Divider()
            LazyVStack(spacing: 0) {
                ForEach(filteredKeys) { key in
                    keyRow(key)
                    if key.id != filteredKeys.last?.id { Divider().padding(.leading, 14) }
                }
            }
        }
        .panelSurface(padding: 0)
    }

    /// 单行只显示密钥掩码，复制操作仍使用内存中的完整值且不会写入日志。
    private func keyRow(_ key: UserAPIKey) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(key.name).font(AppTheme.bodyEmphasizedFont)
                Text(maskedKey(key.key)).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(key.groupName ?? "未分组").lineLimit(1).frame(width: 92, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(key.quota > 0 ? "\(UsageFormatter.cost(key.quotaUsed)) / \(UsageFormatter.cost(key.quota))" : "不限额")
                    .monospacedDigit()
                if let progress = key.quotaProgress {
                    ProgressView(value: progress).tint(progress >= 0.9 ? AppTheme.warning : AppTheme.accent)
                }
            }
            .frame(width: 116, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(key.rateLimit5Hours > 0 ? "5h \(UsageFormatter.cost(key.rateLimit5Hours))" : "未设置")
                if key.rateLimit1Day > 0 { Text("1d \(UsageFormatter.cost(key.rateLimit1Day))") }
            }
            .font(AppTheme.captionFont)
            .foregroundStyle(.secondary)
            .frame(width: 110, alignment: .leading)
            Text(key.lastUsedAt.map(relativeDate) ?? "从未")
                .font(AppTheme.captionFont)
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            Label(statusTitle(key.status), systemImage: "circle.fill")
                .font(AppTheme.captionFont.weight(.medium))
                .foregroundStyle(statusColor(key.status))
                .frame(width: 66, alignment: .leading)
            HStack(spacing: 4) {
                Button { keyForUsage = key } label: {
                    Image(systemName: "arrow.down.to.line.compact")
                }
                .buttonStyle(TableIconButtonStyle(tint: AppTheme.accent))
                .help("使用方式与导入客户端")
                Button { copyKey(key.key) } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(TableIconButtonStyle())
                    .help("复制 API 密钥")
                Button { beginEdit(key) } label: { Image(systemName: "pencil") }
                    .buttonStyle(TableIconButtonStyle())
                    .help("编辑密钥")
                Button(role: .destructive) { keyPendingDeletion = key } label: { Image(systemName: "trash") }
                    .buttonStyle(TableIconButtonStyle(tint: AppTheme.danger))
                    .help("删除密钥")
            }
            .frame(width: 118, alignment: .trailing)
        }
        .font(AppTheme.bodyFont)
        .padding(.horizontal, 14)
        .frame(minHeight: 58)
        .contentShape(Rectangle())
        .onTapGesture { beginEdit(key) }
    }

    /// 创建和编辑共用同一原生表单，字段顺序与 Sub2API 网页端保持一致。
    private var keyEditor: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(editingKey == nil ? "创建 API 密钥" : "编辑 API 密钥")
                        .font(.system(size: 19, weight: .semibold))
                    Text("配置访问范围、额度和周期限制")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { showsEditor = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(ToolbarIconButtonStyle())
            }
            .padding(20)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    editorSectionTitle("基本信息")
                    LabeledContent("名称") {
                        TextField("例如：Codex 主密钥", text: $formName).frame(width: 330)
                    }
                    LabeledContent("分组") {
                        Picker("分组", selection: $formGroupID) {
                            Text("请选择分组").tag(nil as Int?)
                            ForEach(appState.availableGroups) { group in Text(group.name).tag(group.id as Int?) }
                        }
                        .labelsHidden()
                        .frame(width: 330)
                    }
                    if editingKey == nil {
                        Toggle("使用自定义密钥", isOn: $formUsesCustomKey)
                        if formUsesCustomKey {
                            LabeledContent("自定义密钥") {
                                SecureField("至少 16 个字符", text: $formCustomKey).frame(width: 330)
                            }
                        }
                    }

                    Divider()
                    editorSectionTitle("使用限制")
                    HStack(spacing: 16) {
                        editorTextField("总额度（USD）", placeholder: "0 表示不限", text: $formQuota)
                        editorTextField("过期天数", placeholder: "留空表示长期", text: $formExpirationDays)
                    }
                    HStack(spacing: 16) {
                        editorTextField("5 小时限额", placeholder: "0 表示不限", text: $formRate5Hours)
                        editorTextField("1 天限额", placeholder: "0 表示不限", text: $formRate1Day)
                        editorTextField("7 天限额", placeholder: "0 表示不限", text: $formRate7Days)
                    }

                    Divider()
                    editorSectionTitle("网络访问")
                    HStack(alignment: .top, spacing: 16) {
                        editorMultilineField("IP 白名单", placeholder: "每行一个 IP 或 CIDR", text: $formIPWhitelist)
                        editorMultilineField("IP 黑名单", placeholder: "每行一个 IP 或 CIDR", text: $formIPBlacklist)
                    }
                    Toggle("启用密钥", isOn: $formEnabled)
                }
                .padding(20)
            }

            Divider()
            HStack {
                Text("创建后请立即复制并妥善保存完整密钥")
                    .font(AppTheme.captionFont)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("取消") { showsEditor = false }.keyboardShortcut(.cancelAction)
                    .subPilotGlassButtonStyle()
                Button(editingKey == nil ? "创建密钥" : "保存更改", action: submitEditor)
                    .subPilotProminentGlassButtonStyle()
                    .keyboardShortcut(.defaultAction)
                    .disabled(formName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || appState.isLoadingPortal)
            }
            .padding(16)
        }
        .frame(width: 620, height: 670)
        .glassSurface(radius: 16, tint: AppTheme.floatingGlassTint, addsShadow: true)
    }

    /// 表单分区标题使用轻量层级，不再为每个字段增加额外容器。
    private func editorSectionTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 13, weight: .semibold))
    }

    /// 数字字段统一使用上标签下输入框布局，三项周期限制可以快速横向比较。
    private func editorTextField(_ title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(AppTheme.captionFont).foregroundStyle(.secondary)
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity)
    }

    /// IP 列表使用等高多行输入区，支持直接粘贴网页端原有规则。
    private func editorMultilineField(_ title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(AppTheme.captionFont).foregroundStyle(.secondary)
            TextEditor(text: text)
                .font(.system(size: 11, design: .monospaced))
                .frame(height: 72)
                .overlay { RoundedRectangle(cornerRadius: 6).stroke(AppTheme.border) }
            Text(placeholder).font(AppTheme.captionFont).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    /// 打开创建表单时恢复稳定默认值，并默认选择服务端返回的第一个可用分组。
    private func beginCreate() {
        editingKey = nil
        formName = ""
        formGroupID = appState.availableGroups.first?.id
        formUsesCustomKey = false
        formCustomKey = ""
        formQuota = ""
        formExpirationDays = ""
        formIPWhitelist = ""
        formIPBlacklist = ""
        formRate5Hours = ""
        formRate1Day = ""
        formRate7Days = ""
        formEnabled = true
        showsEditor = true
    }

    /// 编辑时回填服务端现有规则；自定义密钥不可回读，因此不会出现在编辑状态。
    private func beginEdit(_ key: UserAPIKey) {
        editingKey = key
        formName = key.name
        formGroupID = appState.availableGroups.first { $0.name == key.groupName }?.id
        formUsesCustomKey = false
        formCustomKey = ""
        formQuota = key.quota > 0 ? String(key.quota) : ""
        formExpirationDays = ""
        formIPWhitelist = key.ipWhitelist.joined(separator: "\n")
        formIPBlacklist = key.ipBlacklist.joined(separator: "\n")
        formRate5Hours = key.rateLimit5Hours > 0 ? String(key.rateLimit5Hours) : ""
        formRate1Day = key.rateLimit1Day > 0 ? String(key.rateLimit1Day) : ""
        formRate7Days = key.rateLimit7Days > 0 ? String(key.rateLimit7Days) : ""
        formEnabled = key.status == "active"
        showsEditor = true
    }

    /// 将输入规范化为接口模型，并在成功后关闭弹窗和刷新表格。
    private func submitEditor() {
        let configuration = APIKeyConfiguration(
            name: formName,
            groupID: formGroupID,
            customKey: formUsesCustomKey && !formCustomKey.isEmpty ? formCustomKey : nil,
            ipWhitelist: parseLines(formIPWhitelist),
            ipBlacklist: parseLines(formIPBlacklist),
            quota: Double(formQuota) ?? 0,
            expiresInDays: Int(formExpirationDays),
            rateLimit5Hours: Double(formRate5Hours) ?? 0,
            rateLimit1Day: Double(formRate1Day) ?? 0,
            rateLimit7Days: Double(formRate7Days) ?? 0
        )
        Task {
            let succeeded: Bool
            if let editingKey {
                succeeded = await appState.updateAPIKey(editingKey, configuration: configuration, enabled: formEnabled)
            } else {
                succeeded = await appState.createAPIKey(configuration: configuration)
            }
            if succeeded { showsEditor = false }
        }
    }

    /// 多行 IP 输入只保留非空规则，空白不会被服务端解释成无效地址。
    private func parseLines(_ value: String) -> [String] {
        value.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// 最近使用时间显示相对描述，超过一天后回退为自然日期。
    private func relativeDate(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "刚刚" }
        if interval < 3_600 { return "\(Int(interval / 60)) 分钟前" }
        if interval < 86_400 { return "\(Int(interval / 3_600)) 小时前" }
        return date.formatted(.dateTime.month().day())
    }

    /// 密钥只显示前缀和尾号，降低旁观者看到完整凭据的风险。
    private func maskedKey(_ key: String) -> String {
        guard key.count > 10 else { return key }
        return "\(key.prefix(7))••••\(key.suffix(4))"
    }

    /// 用户主动复制时才写入系统剪贴板，不做任何本地持久化。
    private func copyKey(_ key: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(key, forType: .string)
        appState.portalSuccessMessage = "API 密钥已复制"
    }

    /// 把服务端状态转换成紧凑中文标签。
    private func statusTitle(_ status: String) -> String {
        switch status { case "active": return "启用"; case "inactive": return "停用"; case "expired": return "过期"; case "quota_exhausted": return "用尽"; default: return "未知" }
    }

    /// 状态颜色只承担辅助识别，文字仍明确描述具体状态。
    private func statusColor(_ status: String) -> Color {
        switch status { case "active": return AppTheme.success; case "expired", "quota_exhausted": return AppTheme.warning; default: return .secondary }
    }

    /// 页面消息保持为非阻塞横条，保存失败不会清空用户正在编辑的字段。
    @ViewBuilder
    private var portalMessageBanner: some View {
        if let error = appState.portalErrorMessage { PortalMessageBanner(message: error, isError: true) }
        else if let success = appState.portalSuccessMessage { PortalMessageBanner(message: success, isError: false) }
    }
}

/// 展示单枚 API 密钥的常用客户端导入方式，并在用户点击后才执行本地写入。
struct APIKeyUsageSheet: View {
    let key: UserAPIKey
    let serverURL: URL
    let onDismiss: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var model: String
    @State private var importingTarget: APIKeyClientTarget?
    @State private var completedTargets: Set<APIKeyClientTarget> = []
    @State private var resultMessage: String?
    @State private var resultDetail: String?
    @State private var isError = false

    /// 使用仪表盘最近模型作为默认值；预览结果只供 QA 验收长提示布局，生产调用保持为空。
    init(
        key: UserAPIKey,
        serverURL: URL,
        suggestedModel: String,
        previewResult: APIKeyImportResult? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.key = key
        self.serverURL = serverURL
        self.onDismiss = onDismiss
        _model = State(initialValue: suggestedModel)
        _resultMessage = State(initialValue: previewResult?.message)
        _resultDetail = State(initialValue: previewResult?.detail)
    }

    /// 页面按“连接信息、快速导入、手动使用”排序，让用户先确认目标再写入本机配置。
    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            Rectangle()
                .fill(Color.white.opacity(0.24))
                .frame(height: 0.5)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    connectionSection
                    if let resultMessage {
                        importMessage(title: resultMessage, detail: resultDetail ?? "")
                    }
                    Text("快速导入")
                        .font(.system(size: 13, weight: .semibold))
                    VStack(spacing: 0) {
                        ForEach(APIKeyClientTarget.allCases) { target in
                            targetRow(target)
                            if target != APIKeyClientTarget.allCases.last { Divider() }
                        }
                    }
                    .background(AppTheme.subtleSurface, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))

                    manualUsageSection
                }
                .padding(14)
            }
            .scrollIndicators(.visible)
        }
        .frame(width: 430, height: 570)
        // 导入面板本身是唯一玻璃层，内部连接信息和客户端列表只使用间距与分隔线分组。
        .glassSurface(radius: AppTheme.floatingCornerRadius, tint: AppTheme.floatingGlassTint, addsShadow: true)
    }

    /// 标题区显示密钥名称和掩码，不在屏幕上暴露完整令牌。
    private var sheetHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("API 密钥使用方式")
                    .font(.system(size: 17, weight: .semibold))
                Text("\(key.name) · \(maskedKey)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { closeSheet() } label: { Image(systemName: "xmark") }
                .subPilotGlassButtonStyle()
                .controlSize(.large)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    /// 生产浮层通过回调关闭，独立 QA 或系统 Sheet 预览则回退到环境 dismiss。
    private func closeSheet() {
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }

    /// 服务地址和模型会进入生成配置，集中展示便于用户在导入前发现选错环境。
    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("连接信息").font(.system(size: 13, weight: .semibold))
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("API Base URL")
                        .font(AppTheme.captionFont.weight(.medium))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Text(openAIBaseURL)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                        Button { copy(openAIBaseURL, message: "API Base URL 已复制") } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("默认模型")
                        .font(AppTheme.captionFont.weight(.medium))
                        .foregroundStyle(.secondary)
                    TextField("例如：gpt-5.6-sol", text: $model)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 9)
                        .frame(height: 30)
                        .background(AppTheme.controlFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(AppTheme.border, lineWidth: 0.75)
                        }
                }
                .frame(width: 170)
            }
            .padding(.vertical, 4)
        }
    }

    /// 每个客户端使用同一行结构，同时清楚区分自动导入和 Cursor 的半自动流程。
    private func targetRow(_ target: APIKeyClientTarget) -> some View {
        HStack(spacing: 12) {
            Image(systemName: target.systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(completedTargets.contains(target) ? AppTheme.accent : Color.secondary)
                .frame(width: 30, height: 30)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(target.title).font(.system(size: 12, weight: .semibold))
                    if target == .cursor {
                        Text("半自动")
                            .font(AppTheme.captionFont.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(target.detail)
                    .font(AppTheme.captionFont)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if importingTarget == target {
                ProgressView().controlSize(.small).frame(width: 82)
            } else if completedTargets.contains(target) {
                Label("已完成", systemImage: "checkmark.circle.fill")
                    .font(AppTheme.captionFont.weight(.medium))
                    .foregroundStyle(AppTheme.success)
                    .frame(width: 82)
            } else {
                Button(target.actionTitle) { beginImport(target) }
                    .subPilotTintedGlassButtonStyle()
                    .foregroundStyle(AppTheme.accent)
                    .controlSize(.small)
                    .frame(width: 82)
                    .disabled(importingTarget != nil)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 56)
    }

    /// 手动配置提供可复制的通用环境变量，密钥本身仍只在点击复制时进入剪贴板。
    private var manualUsageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("手动使用").font(.system(size: 13, weight: .semibold))
            Text("""
            export OPENAI_BASE_URL="\(openAIBaseURL)"
            export OPENAI_API_KEY="<当前密钥>"
            """)
            .font(.system(size: 11, design: .monospaced))
            .textSelection(.enabled)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.codeSurface, in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(AppTheme.border, lineWidth: 0.75)
            }
            HStack {
                Text("适用于读取 OpenAI 兼容环境变量的命令行工具")
                    .font(AppTheme.captionFont)
                    .foregroundStyle(.secondary)
                Spacer()
                Button { copy(shellConfiguration, message: "环境变量已复制") } label: {
                    Label("复制环境变量", systemImage: "doc.on.doc")
                }
                .subPilotGlassButtonStyle()
                .controlSize(.small)
            }
        }
    }

    /// 导入结果横条同时显示下一步和备份位置，失败时保持弹窗打开便于调整模型重试。
    private func importMessage(title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isError ? AppTheme.warning : AppTheme.success)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 11, weight: .semibold))
                Text(detail).font(AppTheme.captionFont).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Spacer()
        }
        .padding(12)
        .background(
            (isError ? AppTheme.warning : AppTheme.success).opacity(0.08),
            in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
        )
    }

    /// Cursor 只执行公开可控的剪贴板和页面跳转，其他客户端在后台线程完成文件或数据库写入。
    private func beginImport(_ target: APIKeyClientTarget) {
        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedModel.isEmpty else {
            isError = true
            resultMessage = "模型名称不能为空"
            resultDetail = "请填写当前密钥分组支持的模型后再导入。"
            return
        }
        importingTarget = target
        isError = false
        resultMessage = nil
        resultDetail = nil

        if target == .cursor {
            copy(key.key, message: nil)
            openCursorSettings()
            completedTargets.insert(target)
            importingTarget = nil
            resultMessage = "API 密钥已复制并打开 Cursor"
            resultDetail = "请在 Cursor 的 Models 设置中粘贴密钥；自定义 Base URL 需要按当前版本手动确认。"
            return
        }

        Task {
            do {
                let key = key
                let serverURL = serverURL
                let result = try await Task.detached(priority: .userInitiated) {
                    try APIKeyClientImportService.importKey(
                        key,
                        serverURL: serverURL,
                        model: normalizedModel,
                        target: target
                    )
                }.value
                completedTargets.insert(target)
                resultMessage = result.message
                resultDetail = result.detail
                isError = false
            } catch {
                resultMessage = "导入未完成"
                resultDetail = error.localizedDescription
                isError = true
            }
            importingTarget = nil
        }
    }

    /// 打开 Cursor 模型设置；URL 路由不可用时回退为启动 Cursor 应用。
    private func openCursorSettings() {
        if let settingsURL = URL(string: "cursor://settings/models"), NSWorkspace.shared.open(settingsURL) {
            return
        }
        let applicationURL = URL(filePath: "/Applications/Cursor.app", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: applicationURL.path) else {
            resultDetail = "未检测到 Cursor，请安装后在 Models 设置中粘贴已复制的密钥。"
            return
        }
        NSWorkspace.shared.openApplication(at: applicationURL, configuration: .init())
    }

    /// 剪贴板只在用户主动点击时写入，不持久化额外副本。
    private func copy(_ value: String, message: String?) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        if let message {
            isError = false
            resultMessage = message
            resultDetail = "剪贴板包含敏感信息，使用后建议复制其他内容覆盖。"
        }
    }

    /// 完整密钥只显示短前缀和尾号，避免屏幕共享时泄露凭据。
    private var maskedKey: String {
        guard key.key.count > 10 else { return "••••••••" }
        return "\(key.key.prefix(7))••••\(key.key.suffix(4))"
    }

    /// 所有 OpenAI 兼容工具统一使用带 `/v1` 的基础地址。
    private var openAIBaseURL: String {
        serverURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/v1"
    }

    /// 复制内容包含真实密钥，屏幕预览仍使用占位符避免泄露。
    private var shellConfiguration: String {
        "export OPENAI_BASE_URL=\"\(openAIBaseURL)\"\nexport OPENAI_API_KEY=\"\(key.key)\"\n"
    }
}

/// 使用记录工作台，支持服务端筛选、历史滚动加载、真实图表、CSV 导出和逐条明细。
struct UsageRecordsPortalView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage(PreferenceKey.displayTimeZone) private var displayTimeZone = TimeZone.current.identifier
    @State private var selectedKeyID: Int?
    @State private var selectedModel = ""
    @State private var selectedGroupID: Int?
    @State private var selectedRequestType = ""
    @State private var selectedBillingType: Int?
    @State private var selectedBillingMode = ""
    @State private var derivedData = UsageRecordsDerivedData.empty
    @State private var filterRefreshTask: Task<Void, Never>?

    /// 页面从筛选到图表、表格和详情形成连续工作流，行出现时自动加载下一页。
    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 12) {
                filterBar
                usageSummaryRail
                chartsPanel
                usageTable
            }
            .frame(maxWidth: .infinity)

            if let record = appState.portalUsageRecordDetail {
                usageDetail(record)
                    .frame(width: 360)
                    // 玻璃抽屉只淡入，不再横向移动整个材质采样区域，降低打开明细时的合成压力。
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.12), value: appState.portalUsageRecordDetail?.id)
        .task {
            await appState.loadAPIKeys()
            await appState.loadPortalUsageRecords(filters: activeFilters)
            rebuildDerivedData()
        }
        .onChange(of: filterSignature) { _, _ in
            scheduleFilterRefresh()
        }
        .onChange(of: appState.portalUsageRecords.map(\.id)) { _, _ in
            rebuildDerivedData()
        }
        .onDisappear {
            // 离开使用记录页后取消尚未开始的筛选刷新，避免后台结果触发无意义的整页更新。
            filterRefreshTask?.cancel()
        }
    }

    /// 高频筛选保持单行，低频计费条件收进更多菜单，给长列表留出足够首屏高度。
    private var filterBar: some View {
        HStack(spacing: 8) {
            usagePicker("API 密钥", selection: $selectedKeyID, values: appState.apiKeys.map { ($0.id, $0.name) })
            menuPicker("模型", selection: $selectedModel, values: availableModels)
            usagePicker("分组", selection: $selectedGroupID, values: appState.availableGroups.map { ($0.id, $0.name) })
            menuPicker("请求类型", selection: $selectedRequestType, values: ["sync", "stream", "ws_v2", "live"])
            billingFilterMenu
            Spacer(minLength: 0)
            Button(action: clearFilters) {
                Image(systemName: "line.3.horizontal.decrease.circle")
            }
            .buttonStyle(ToolbarIconButtonStyle())
            .help("清除全部筛选")
            Button(action: exportCSV) {
                Image(systemName: "square.and.arrow.down")
            }
            .buttonStyle(ToolbarIconButtonStyle())
            .help("导出当前已加载记录")
        }
        .padding(8)
        .glassSurface(radius: AppTheme.floatingCornerRadius, isInteractive: true)
    }

    /// 更多筛选集中计费类型和计费模式，菜单标题会提示当前是否存在额外条件。
    private var billingFilterMenu: some View {
        Menu {
            Picker("计费类型", selection: $selectedBillingType) {
                Text("全部计费类型").tag(nil as Int?)
                Text("余额").tag(0 as Int?)
                Text("订阅").tag(1 as Int?)
            }
            Picker("计费模式", selection: $selectedBillingMode) {
                Text("全部计费模式").tag("")
                ForEach(["standard", "batch", "priority", "flex"], id: \.self) { mode in
                    Text(mode).tag(mode)
                }
            }
        } label: {
            Label(hasBillingFilter ? "计费已筛选" : "更多", systemImage: "ellipsis.circle")
        }
        .frame(minWidth: 92)
    }

    /// 任一低频计费条件生效时返回真，用于在折叠菜单上提供可见反馈。
    private var hasBillingFilter: Bool {
        selectedBillingType != nil || !selectedBillingMode.isEmpty
    }

    /// 可选整数菜单同时用于密钥、分组和计费类型，空值统一表示全部。
    private func usagePicker(_ title: String, selection: Binding<Int?>, values: [(Int, String)]) -> some View {
        Picker(title, selection: selection) {
            Text("全部\(title)").tag(nil as Int?)
            ForEach(values, id: \.0) { value in Text(value.1).tag(value.0 as Int?) }
        }
        .labelsHidden()
        .frame(minWidth: 108, maxWidth: 126)
    }

    /// 字符串菜单用于模型和请求类型，空字符串不会进入服务端查询。
    private func menuPicker(_ title: String, selection: Binding<String>, values: [String]) -> some View {
        Picker(title, selection: selection) {
            Text("全部\(title)").tag("")
            ForEach(values, id: \.self) { Text($0).tag($0) }
        }
        .labelsHidden()
        .frame(minWidth: 108, maxWidth: 126)
    }

    /// 汇总带优先使用仪表盘服务端聚合值，标准消费则由当前已加载历史页准确求和。
    private var usageSummaryRail: some View {
        AppMetricRail(
            items: [
                AppMetricItem(icon: "circle.hexagongrid", title: "Token", value: UsageFormatter.compactTokens(appState.snapshot?.periodTokens)),
                AppMetricItem(icon: "arrow.up.right", title: "请求", value: UsageFormatter.requestCount(appState.snapshot?.requestCount)),
                AppMetricItem(icon: "dollarsign", title: "实际消费", value: UsageFormatter.cost(appState.snapshot?.usageCost)),
                AppMetricItem(icon: "doc.text", title: "标准消费", value: UsageFormatter.cost(displayedDerivedData.standardCost)),
                AppMetricItem(icon: "timer", title: "平均响应", value: UsageFormatter.duration(milliseconds: appState.snapshot?.averageResponseMilliseconds))
            ],
            compact: true
        )
    }

    /// 趋势图和模型分布都基于当前已加载真实记录，不生成不存在的示例时间序列。
    private var chartsPanel: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("请求与 Token 趋势").font(.system(size: 12, weight: .semibold))
                Chart(displayedDerivedData.trendPoints) { point in
                    LineMark(x: .value("时间", point.date), y: .value("Token", point.tokens))
                        .foregroundStyle(AppTheme.accent)
                        .interpolationMethod(.catmullRom)
                    AreaMark(x: .value("时间", point.date), y: .value("Token", point.tokens))
                        .foregroundStyle(AppTheme.accent.opacity(0.08))
                }
                .chartXAxis(.hidden)
                .frame(height: 82)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("模型分布").font(.system(size: 12, weight: .semibold))
                Chart(displayedDerivedData.modelSummaries) { item in
                    BarMark(x: .value("Token", item.tokens), y: .value("模型", item.model))
                        .foregroundStyle(usageModelColor(item.model))
                        .cornerRadius(2)
                }
                .chartXAxis(.hidden)
                .frame(height: 82)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
        }
        .frame(height: 132)
        .panelSurface(padding: 0)
    }

    /// 模型分布使用离散系统色板，相邻模型无需只靠标签文字区分。
    private func usageModelColor(_ model: String) -> Color {
        let index = displayedDerivedData.modelSummaries.firstIndex { $0.model == model } ?? 0
        return AppTheme.chartPalette[index % AppTheme.chartPalette.count]
    }

    /// 表格拥有独立滚动视口和固定表头，惰性容器只创建屏幕附近的行以控制长列表开销。
    private var usageTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Text("时间").frame(width: 92, alignment: .leading)
                Text("模型 / 分组").frame(maxWidth: .infinity, alignment: .leading)
                Text("密钥").frame(width: 96, alignment: .leading)
                Text("Token").frame(width: 68, alignment: .trailing)
                Text("输入 / 输出").frame(width: 92, alignment: .trailing)
                Text("响应").frame(width: 62, alignment: .trailing)
                Text("实际 / 标准").frame(width: 106, alignment: .trailing)
                Text("状态").frame(width: 52, alignment: .trailing)
            }
            .font(AppTheme.captionFont.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(AppTheme.tableHeader)
            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(appState.portalUsageRecords) { record in
                        usageRow(record)
                            .onAppear {
                                // 只有最后一条真正进入可视区域时才加载下一页，避免首屏并发请求多页。
                                if record.id == appState.portalUsageRecords.last?.id {
                                    Task { await appState.loadMorePortalUsageRecords(filters: activeFilters) }
                                }
                            }
                        Divider().padding(.leading, 12)
                    }

                    usageTableFooter
                        .frame(height: 40)
                        .onAppear {
                            // 首屏能直接露出页脚时继续补页，直到列表可以滚动或数据已经加载完毕。
                            if appState.hasMorePortalUsageRecords {
                                Task { await appState.loadMorePortalUsageRecords(filters: activeFilters) }
                            }
                        }
                }
            }
            .scrollIndicators(.visible)
        }
        .frame(minHeight: 180, maxHeight: .infinity)
        .panelSurface(padding: 0)
        .clipped()
    }

    /// 页脚同时反馈已加载数量和网络状态，并保留手动加载入口便于失败后重试。
    private var usageTableFooter: some View {
        HStack {
            Text("已加载 \(appState.portalUsageRecords.count) / \(appState.portalUsageTotal) 条")
                .font(AppTheme.captionFont)
                .foregroundStyle(.secondary)
            Spacer()
            if appState.isLoadingMorePortalUsage {
                ProgressView().controlSize(.small)
            } else if appState.hasMorePortalUsageRecords {
                Button("加载更多") { Task { await appState.loadMorePortalUsageRecords(filters: activeFilters) } }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.accent)
            } else if !appState.portalUsageRecords.isEmpty {
                Text("已加载全部记录").font(AppTheme.captionFont).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
    }

    /// 点击一行立即显示已有明细，同时异步补读 `/usage/{id}` 的完整字段。
    private func usageRow(_ record: PortalUsageRecord) -> some View {
        HStack(spacing: 9) {
            Text(formattedTime(record.createdAt)).frame(width: 92, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.model).fontWeight(.medium).lineLimit(1)
                Text(record.groupName ?? record.endpoint ?? "—").font(AppTheme.captionFont).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(record.apiKeyName).lineLimit(1).frame(width: 96, alignment: .leading)
            Text(UsageFormatter.compactTokens(record.totalTokens)).monospacedDigit().frame(width: 68, alignment: .trailing)
            Text(record.inputOutputDescription).monospacedDigit().frame(width: 92, alignment: .trailing)
            Text(UsageFormatter.duration(milliseconds: record.durationMilliseconds)).monospacedDigit().frame(width: 62, alignment: .trailing)
            Text("\(UsageFormatter.cost(record.actualCost)) / \(UsageFormatter.cost(record.standardCost))").monospacedDigit().frame(width: 106, alignment: .trailing)
            Label("成功", systemImage: "circle.fill").labelStyle(.titleAndIcon).foregroundStyle(AppTheme.success).frame(width: 52, alignment: .trailing)
        }
        .font(AppTheme.bodyFont)
        .padding(.horizontal, 12)
        .frame(minHeight: AppTheme.tableRowHeight)
        .background(appState.portalUsageRecordDetail?.id == record.id ? AppTheme.selectedSurface : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { Task { await appState.loadPortalUsageRecordDetail(record) } }
    }

    /// 详情抽屉完整展示请求、Token、费用拆分与时间口径，复制命令仅复制请求 ID。
    private func usageDetail(_ record: PortalUsageRecord) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("记录详情").font(.system(size: 16, weight: .semibold))
                    Text("\(formattedTime(record.createdAt)) · \(record.model)").font(AppTheme.captionFont).foregroundStyle(.secondary)
                }
                Spacer()
                Button { appState.clearPortalUsageRecordDetail() } label: { Image(systemName: "xmark") }
                    .buttonStyle(ToolbarIconButtonStyle())
            }
            .padding(14)
            Divider()

            HStack(spacing: 0) {
                detailSummaryMetric("实际消费", UsageFormatter.cost(record.actualCost))
                Divider().frame(height: 34)
                detailSummaryMetric("标准消费", UsageFormatter.cost(record.standardCost))
                Divider().frame(height: 34)
                detailSummaryMetric("倍率", record.multiplier.map { String(format: "%.2f×", $0) } ?? "—")
            }
            .padding(.vertical, 10)
            .background(AppTheme.subtleSurface)
            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    detailSection("请求信息")
                    detailRow("请求 ID", record.requestID)
                    detailRow("端点", record.endpoint ?? "—")
                    detailRow("请求类型", record.requestType ?? (record.isStream ? "stream" : "sync"))
                    detailRow("首 Token", UsageFormatter.duration(milliseconds: record.firstTokenMilliseconds))
                    detailSection("Token 明细")
                    detailRow("输入", UsageFormatter.compactTokens(record.inputTokens))
                    detailRow("输出", UsageFormatter.compactTokens(record.outputTokens))
                    detailRow("缓存创建", UsageFormatter.compactTokens(record.cacheCreationTokens))
                    detailRow("缓存读取", UsageFormatter.compactTokens(record.cacheReadTokens))
                    detailSection("模型单价")
                    detailRow("输入单价", UsageFormatter.tokenPricePerMillion(cost: record.inputCost, tokens: record.inputTokens))
                    detailRow("输出单价", UsageFormatter.tokenPricePerMillion(cost: record.outputCost, tokens: record.outputTokens))
                    detailRow("缓存创建单价", UsageFormatter.tokenPricePerMillion(cost: record.cacheCreationCost, tokens: record.cacheCreationTokens))
                    detailRow("缓存读取单价", UsageFormatter.tokenPricePerMillion(cost: record.cacheReadCost, tokens: record.cacheReadTokens))
                    Text("根据本次账单反算，实际价格可能受分组、倍率与计费模式影响")
                        .font(AppTheme.captionFont)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    detailSection("费用拆分")
                    detailRow("输入费用", UsageFormatter.cost(record.inputCost))
                    detailRow("输出费用", UsageFormatter.cost(record.outputCost))
                    detailRow("缓存创建费用", UsageFormatter.cost(record.cacheCreationCost))
                    detailRow("缓存读取费用", UsageFormatter.cost(record.cacheReadCost))
                    detailRow("实际 / 标准", "\(UsageFormatter.cost(record.actualCost)) / \(UsageFormatter.cost(record.standardCost))")
                    detailRow("倍率", record.multiplier.map { String(format: "%.2f×", $0) } ?? "—")
                    detailRow("计费模式", record.billingMode ?? "—")
                }
            }
            .scrollIndicators(.visible)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(record.requestID, forType: .string)
            } label: {
                Label("复制请求 ID", systemImage: "doc.on.doc").frame(maxWidth: .infinity)
            }
            .subPilotGlassButtonStyle()
            .padding(14)
        }
        .frame(maxHeight: .infinity)
        // 详情抽屉本身就是悬浮层，不再叠加实体底色，桌面和表格可以真正参与玻璃折射。
        .glassSurface(radius: AppTheme.floatingCornerRadius, tint: AppTheme.floatingGlassTint, addsShadow: true)
    }

    /// 详情顶部三项费用使用相同数字基线，打开抽屉后无需滚动即可完成倍率核对。
    private func detailSummaryMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AppTheme.captionFont)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 详情分区标题和细分隔线共同建立层级，不增加嵌套背景或卡片。
    private func detailSection(_ title: String) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(AppTheme.captionFont.weight(.semibold))
                .foregroundStyle(.secondary)
            Divider()
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
    }

    /// 明细键值行固定右侧对齐，长请求 ID 会安全缩放。
    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack { Text(title).foregroundStyle(.secondary); Spacer(); Text(value).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6) }
            .font(AppTheme.captionFont).padding(.horizontal, 14).frame(height: 32)
    }

    /// 当前筛选条件集中构造，图表、列表刷新和继续加载始终使用同一口径。
    private var activeFilters: PortalUsageFilters {
        PortalUsageFilters(
            apiKeyID: selectedKeyID,
            model: selectedModel.isEmpty ? nil : selectedModel,
            groupID: selectedGroupID,
            requestType: selectedRequestType.isEmpty ? nil : selectedRequestType,
            billingType: selectedBillingType,
            billingMode: selectedBillingMode.isEmpty ? nil : selectedBillingMode
        )
    }

    /// SwiftUI 通过稳定签名监听多个筛选字段，避免为每个菜单复制刷新逻辑。
    private var filterSignature: String {
        "\(selectedKeyID ?? -1)|\(selectedModel)|\(selectedGroupID ?? -1)|\(selectedRequestType)|\(selectedBillingType ?? -1)|\(selectedBillingMode)"
    }

    /// 模型菜单从当前历史和仪表盘最近模型合并生成，去重后按名称排序。
    private var availableModels: [String] {
        var values = Set(displayedDerivedData.models)
        if let model = appState.snapshot?.recentModel { values.insert(model) }
        return values.sorted()
    }

    /// 离线首帧尚未执行视图任务时直接计算一次，正常交互中仍优先复用已缓存的数据。
    private var displayedDerivedData: UsageRecordsDerivedData {
        guard derivedData.recordCount == appState.portalUsageRecords.count else {
            return UsageRecordsDerivedData.make(from: appState.portalUsageRecords)
        }
        return derivedData
    }

    /// 只在历史页发生变化时重建图表和汇总缓存，选中详情不会重复遍历全部记录。
    private func rebuildDerivedData() {
        derivedData = UsageRecordsDerivedData.make(from: appState.portalUsageRecords)
    }

    /// 清除所有筛选后由签名监听自动重新请求第一页。
    private func clearFilters() {
        selectedKeyID = nil
        selectedModel = ""
        selectedGroupID = nil
        selectedRequestType = ""
        selectedBillingType = nil
        selectedBillingMode = ""
    }

    /// 合并短时间内连续发生的筛选变更，避免用户快速选择时创建多次网络请求和整页刷新。
    private func scheduleFilterRefresh() {
        filterRefreshTask?.cancel()
        let filters = activeFilters
        filterRefreshTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled else { return }
                await appState.loadPortalUsageRecords(force: true, filters: filters)
            } catch {
                // 新筛选会主动取消旧延迟任务；取消属于正常控制流，不应在界面显示错误。
            }
        }
    }

    /// CSV 导出使用当前已加载记录，文件写入由系统保存面板明确交给用户选择位置。
    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "SubPilot-使用记录.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let header = "时间,请求ID,模型,API密钥,分组,端点,输入Token,输出Token,缓存Token,实际费用,标准费用,倍率,响应毫秒\n"
        let rows: String = appState.portalUsageRecords.map { record -> String in
            let cachedTokens = record.cacheCreationTokens + record.cacheReadTokens
            let multiplier = record.multiplier.map { String($0) } ?? ""
            let duration = record.durationMilliseconds.map { String($0) } ?? ""
            let fields: [String] = [
                formattedISODate(record.createdAt),
                record.requestID,
                record.model,
                record.apiKeyName,
                record.groupName ?? "",
                record.endpoint ?? "",
                String(record.inputTokens),
                String(record.outputTokens),
                String(cachedTokens),
                String(record.actualCost),
                String(record.standardCost),
                multiplier,
                duration
            ]
            return fields.map(csvEscaped).joined(separator: ",")
        }.joined(separator: "\n")
        do {
            try (header + rows).write(to: url, atomically: true, encoding: .utf8)
            appState.portalSuccessMessage = "已导出 \(appState.portalUsageRecords.count) 条使用记录"
        } catch {
            appState.portalErrorMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    /// CSV 字段统一双引号转义，模型名或分组包含逗号时仍能被表格软件正确解析。
    private func csvEscaped(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    /// 列表时间遵守应用设置中的时区并显示到秒，便于对照日志。
    private func formattedTime(_ date: Date) -> String {
        Self.listTimeFormatter.timeZone = TimeZone(identifier: displayTimeZone) ?? .current
        return Self.listTimeFormatter.string(from: date)
    }

    /// 长列表复用同一日期格式化器，避免每个可见行在每次状态更新时重复创建 Foundation 对象。
    @MainActor
    private static let listTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter
    }()

    /// 导出文件使用带时区的 ISO 8601 时间，跨设备查看时不会产生歧义。
    private func formattedISODate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: displayTimeZone) ?? .current
        return formatter.string(from: date)
    }
}

/// 表示使用趋势中的一个真实调用点，ID 沿用账单记录 ID 保持稳定。
private struct PortalTrendPoint: Identifiable {
    let id: Int
    let date: Date
    let tokens: Double
}

/// 表示模型分布的一项聚合值，模型名称直接作为稳定标识。
private struct PortalModelSummary: Identifiable {
    let model: String
    let tokens: Double
    var id: String { model }
}

/// 缓存使用记录页面的聚合结果，避免 SwiftUI 每次刷新视图时重复分组、排序和求和。
private struct UsageRecordsDerivedData {
    let recordCount: Int
    let standardCost: Double
    let models: [String]
    let trendPoints: [PortalTrendPoint]
    let modelSummaries: [PortalModelSummary]

    /// 初始空数据让界面在网络结果返回前保持稳定，不显示伪造图表内容。
    static let empty = UsageRecordsDerivedData(
        recordCount: 0,
        standardCost: 0,
        models: [],
        trendPoints: [],
        modelSummaries: []
    )

    /// 每次分页数据改变时单次完成所有聚合，图表最多保留 80 个趋势点和 5 个模型。
    static func make(from records: [PortalUsageRecord]) -> UsageRecordsDerivedData {
        var modelTokens: [String: Double] = [:]
        var standardCost = 0.0
        for record in records {
            standardCost += record.standardCost
            modelTokens[record.model, default: 0] += record.totalTokens
        }
        let summaries = modelTokens
            .map { PortalModelSummary(model: $0.key, tokens: $0.value) }
            .sorted { $0.tokens > $1.tokens }
            .prefix(5)
        let trends = Array(records.prefix(80).reversed()).map {
            PortalTrendPoint(id: $0.id, date: $0.createdAt, tokens: $0.totalTokens)
        }
        return UsageRecordsDerivedData(
            recordCount: records.count,
            standardCost: standardCost,
            models: modelTokens.keys.sorted(),
            trendPoints: trends,
            modelSummaries: Array(summaries)
        )
    }
}

/// 渠道状态页，显示普通用户接口公开的可用率、延迟和模型状态。
struct ChannelStatusPortalView: View {
    @EnvironmentObject private var appState: AppState

    /// 管理员未配置监控时给出明确空状态，不把空响应误判为连接失败。
    var body: some View {
        Group {
            if appState.channelMonitors.isEmpty && !appState.isLoadingPortal {
                ContentUnavailableView {
                    Label("暂无可显示的渠道", systemImage: "antenna.radiowaves.left.and.right")
                } description: {
                    Text("管理员尚未配置普通用户可查看的渠道监控")
                }
                .frame(maxWidth: .infinity, minHeight: 360)
                .panelSurface()
            } else {
                VStack(spacing: 12) {
                    channelSummaryRail

                    VStack(spacing: 0) {
                        AppSectionHeader(title: "渠道明细", trailing: "共 \(appState.channelMonitors.count) 个")
                        LazyVStack(spacing: 0) {
                            ForEach(Array(appState.channelMonitors.enumerated()), id: \.element.id) { index, monitor in
                                HStack(spacing: 14) {
                                    Image(systemName: "antenna.radiowaves.left.and.right")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(statusColor(monitor.status))
                                        .frame(width: 30, height: 30)
                                        .background(
                                            statusColor(monitor.status).opacity(0.10),
                                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        )
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(monitor.name).font(.system(size: 13, weight: .medium))
                                        Text("\(monitor.groupName) · \(monitor.model)")
                                            .font(AppTheme.captionFont)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    metric("7 天可用率", monitor.availability7Days.formatted(.number.precision(.fractionLength(2))) + "%")
                                    metric("响应延迟", UsageFormatter.duration(milliseconds: monitor.latencyMilliseconds))
                                    AppStatusLabel(title: statusTitle(monitor.status), color: statusColor(monitor.status))
                                        .frame(width: 64, alignment: .trailing)
                                }
                                .padding(.horizontal, 16)
                                .frame(minHeight: 72)
                                if index < appState.channelMonitors.count - 1 {
                                    Divider().padding(.leading, 60)
                                }
                            }
                        }
                    }
                    .panelSurface(padding: 0)
                }
            }
        }
        .task { await appState.loadChannelMonitors() }
    }

    /// 汇总只基于当前接口返回的监控项，空集合由上层空状态处理，不生成虚构的零值。
    private var channelSummaryRail: some View {
        let monitors = appState.channelMonitors
        let healthyCount = monitors.filter { statusTitle($0.status) == "正常" }.count
        let averageAvailability = monitors.reduce(0) { $0 + $1.availability7Days } / Double(monitors.count)
        let latencyValues = monitors.compactMap(\.latencyMilliseconds)
        let averageLatency = latencyValues.isEmpty
            ? nil
            : latencyValues.reduce(0, +) / Double(latencyValues.count)
        let modelCount = Set(monitors.map(\.model)).count

        return AppMetricRail(
            items: [
                AppMetricItem(icon: "checkmark.circle", title: "正常渠道", value: "\(healthyCount) / \(monitors.count)"),
                AppMetricItem(icon: "chart.line.uptrend.xyaxis", title: "平均可用率", value: averageAvailability.formatted(.number.precision(.fractionLength(2))) + "%"),
                AppMetricItem(icon: "timer", title: "平均延迟", value: UsageFormatter.duration(milliseconds: averageLatency)),
                AppMetricItem(icon: "cpu", title: "覆盖模型", value: modelCount.formatted())
            ],
            compact: true
        )
    }

    /// 指标使用上标签下数值，渠道名称变化不会挤压数值列。
    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(title).font(AppTheme.captionFont).foregroundStyle(.secondary)
            Text(value).font(.system(size: 12, weight: .medium)).monospacedDigit()
        }
        .frame(width: 96, alignment: .trailing)
    }

    /// 兼容 v1 渠道监控常见状态字符串。
    private func statusTitle(_ status: String) -> String {
        switch status.lowercased() {
        case "operational", "healthy", "success": return "正常"
        case "degraded", "warning": return "波动"
        case "outage", "critical", "failed": return "异常"
        default: return "未知"
        }
    }

    /// 正常、波动和异常分别使用强调、警示和红色，未知保持灰色。
    private func statusColor(_ status: String) -> Color {
        switch statusTitle(status) {
        case "正常": return AppTheme.success
        case "波动": return AppTheme.warning
        case "异常": return .red
        default: return .secondary
        }
    }
}

/// 描述订阅页中一个经过有效性过滤的额度周期，避免视图直接拼装可选值。
private struct SubscriptionQuotaPresentation: Identifiable {
    let id: String
    let title: String
    let used: Double
    let limit: Double
    let resetInSeconds: Double?
}

/// 我的订阅页，只展示服务端明确配置了正数上限的日、周、月额度。
struct SubscriptionsPortalView: View {
    @EnvironmentObject private var appState: AppState

    /// 没有有效订阅时仍提醒平台额度可能由账户级配置提供，两者口径相互独立。
    var body: some View {
        Group {
            if appState.subscriptions.isEmpty && !appState.isLoadingPortal {
                ContentUnavailableView {
                    Label("暂无有效订阅", systemImage: "creditcard")
                } description: {
                    Text("账户平台额度仍可在概览查看；订阅计划需由管理员分配")
                }
                .frame(maxWidth: .infinity, minHeight: 360)
                .panelSurface()
            } else {
                VStack(spacing: 12) {
                    ForEach(appState.subscriptions) { subscription in
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(subscription.groupName)
                                        .font(.system(size: 15, weight: .semibold))
                                    Text(subscription.expiresAt.map { "有效期至 \(formattedDate($0))" } ?? "长期有效")
                                        .font(AppTheme.captionFont)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(subscription.status == "active" ? "使用中" : subscription.status)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(subscription.status == "active" ? AppTheme.success : .secondary)
                            }

                            let periods = quotaPeriods(for: subscription)
                            if periods.isEmpty {
                                Label("该订阅未配置周期额度", systemImage: "gauge.with.dots.needle.0percent")
                                    .font(AppTheme.bodyFont)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                            } else {
                                HStack(alignment: .top, spacing: 0) {
                                    ForEach(Array(periods.enumerated()), id: \.element.id) { index, period in
                                        usageMetric(
                                            period.title,
                                            used: period.used,
                                            limit: period.limit,
                                            resetInSeconds: period.resetInSeconds
                                        )
                                        if index < periods.count - 1 {
                                            Divider().frame(height: 76)
                                        }
                                    }
                                }
                            }
                        }
                        .panelSurface()
                    }
                }
            }
        }
        .task { await appState.loadSubscriptions() }
    }

    /// 按日、周、月顺序组装服务端明确配置的额度；零值和空值周期不会进入界面。
    private func quotaPeriods(for subscription: UserSubscriptionItem) -> [SubscriptionQuotaPresentation] {
        var periods: [SubscriptionQuotaPresentation] = []
        if let limit = subscription.configuredDailyLimit {
            periods.append(SubscriptionQuotaPresentation(
                id: "daily",
                title: "今日额度",
                used: subscription.dailyUsage,
                limit: limit,
                resetInSeconds: subscription.dailyResetInSeconds
            ))
        }
        if let limit = subscription.configuredWeeklyLimit {
            periods.append(SubscriptionQuotaPresentation(
                id: "weekly",
                title: "本周额度",
                used: subscription.weeklyUsage,
                limit: limit,
                resetInSeconds: subscription.weeklyResetInSeconds
            ))
        }
        if let limit = subscription.configuredMonthlyLimit {
            periods.append(SubscriptionQuotaPresentation(
                id: "monthly",
                title: "近 30 天额度",
                used: subscription.monthlyUsage,
                limit: limit,
                resetInSeconds: subscription.monthlyResetInSeconds
            ))
        }
        return periods
    }

    /// 单个有效周期显示已用、上限、百分比和重置倒计时，口径来自订阅进度接口。
    private func usageMetric(
        _ title: String,
        used: Double,
        limit: Double,
        resetInSeconds: Double?
    ) -> some View {
        let progress = min(max(used / limit, 0), 1)
        return VStack(alignment: .leading, spacing: 5) {
            Text(title).font(AppTheme.captionFont).foregroundStyle(.secondary)
            HStack {
                Text("\(UsageFormatter.cost(used)) / \(UsageFormatter.cost(limit))")
                Spacer()
                Text(progress.formatted(.percent.precision(.fractionLength(0))))
                    .font(AppTheme.captionFont)
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .monospacedDigit()
            ProgressView(value: progress)
                .tint(progress >= 0.9 ? AppTheme.warning : AppTheme.accent)
            Text(resetDescription(resetInSeconds))
                .font(AppTheme.captionFont)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 把服务端秒数转换为天、小时或分钟，避免只显示难理解的绝对秒数。
    private func resetDescription(_ seconds: Double?) -> String {
        guard let seconds, seconds > 0 else { return "暂未提供重置时间" }
        let totalMinutes = Int(seconds / 60)
        let days = totalMinutes / 1_440
        let hours = (totalMinutes % 1_440) / 60
        let minutes = totalMinutes % 60
        if days > 0 { return "\(days) 天 \(hours) 小时后重置" }
        if hours > 0 { return "\(hours) 小时 \(minutes) 分钟后重置" }
        return "\(minutes) 分钟后重置"
    }

    /// 订阅有效期按本机自然日期显示，精确重置时区仍由概览额度行展示。
    private func formattedDate(_ date: Date) -> String {
        date.formatted(.dateTime.year().month().day())
    }
}

/// 兑换页把输入、当前账户摘要和最近余额增加活动放在同一任务流中。
struct RedeemPortalView: View {
    @EnvironmentObject private var appState: AppState
    @State private var code = ""

    /// 兑换按钮只有输入非空且当前没有请求时可用，避免重复提交同一兑换码。
    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("输入兑换码")
                        .font(.system(size: 14, weight: .semibold))
                    TextField("兑换码区分大小写", text: $code)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        Task {
                            if await appState.redeem(code: code) { code = "" }
                        }
                    } label: {
                        Label("兑换", systemImage: "gift")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                    .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || appState.isLoadingPortal)

                    if let error = appState.portalErrorMessage {
                        PortalMessageBanner(message: error, isError: true)
                    } else if let success = appState.portalSuccessMessage {
                        PortalMessageBanner(message: success, isError: false)
                    }
                }
                .frame(maxWidth: .infinity)
                .panelSurface()

                VStack(alignment: .leading, spacing: 12) {
                    Text("当前账户")
                        .font(.system(size: 14, weight: .semibold))
                    accountLine("可用余额", UsageFormatter.cost(appState.snapshot?.balance))
                    Divider()
                    accountLine("并发上限", UsageFormatter.concurrencyLimit(appState.snapshot?.concurrencyLimit))
                }
                .frame(width: 260)
                .panelSurface()
            }

            VStack(alignment: .leading, spacing: 0) {
                Text("最近余额增加")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(16)
                Divider()
                if appState.balanceActivities.isEmpty {
                    Text("暂无余额增加记录")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 100)
                } else {
                    ForEach(Array(appState.balanceActivities.prefix(8).enumerated()), id: \.offset) { _, activity in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(activity.title).font(.system(size: 12, weight: .medium))
                                Text(activity.detail).font(AppTheme.captionFont).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(UsageFormatter.balanceChange(activity.amountChange))
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.success)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 50)
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .panelSurface(padding: 0)
        }
        .task { await appState.loadBalanceActivities() }
    }

    /// 账户摘要使用固定标签和值对齐，余额和并发变化不会改变容器高度。
    private func accountLine(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold).monospacedDigit()
        }
        .font(.system(size: 12))
    }
}

/// 个人资料页支持用户名和密码更新，并把网页授权类功能明确留在服务端管理。
struct ProfilePortalView: View {
    @EnvironmentObject private var appState: AppState
    @State private var username = ""
    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var passwordConfirmation = ""

    /// 两列布局分别承载账户资料和安全设置，窗口缩放时保持稳定阅读顺序。
    var body: some View {
        VStack(spacing: 16) {
            if let profile = appState.userProfile {
                HStack(alignment: .top, spacing: 18) {
                    profilePanel(profile)
                        .frame(maxWidth: .infinity)
                    passwordPanel
                        .frame(maxWidth: .infinity)
                }
                authorizationPanel
            } else if !appState.isLoadingPortal {
                ContentUnavailableView {
                    Label("无法读取个人资料", systemImage: "person.crop.circle.badge.exclamationmark")
                } description: {
                    Text(appState.portalErrorMessage ?? "请刷新后重试")
                }
                .frame(maxWidth: .infinity, minHeight: 360)
                .panelSurface()
            }
        }
        .task {
            await appState.loadUserProfile()
            username = appState.userProfile?.username ?? ""
        }
    }

    /// 资料面板展示只读账户信息，并允许修改用户名。
    private func profilePanel(_ profile: UserProfileSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text(String(profile.username.prefix(1)).uppercased())
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(AppTheme.accent, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.email).font(.system(size: 13, weight: .semibold))
                    Text("\(profile.role == "user" ? "用户" : profile.role) · \(profile.status == "active" ? "启用" : profile.status)")
                        .font(AppTheme.captionFont)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()
            TextField("用户名", text: $username)
                .textFieldStyle(.roundedBorder)
            Button("更新资料") {
                Task { _ = await appState.updateUsername(username) }
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)

            HStack {
                accountMetric("余额", UsageFormatter.cost(profile.balance))
                Divider().frame(height: 34)
                accountMetric("并发", profile.concurrency.formatted())
            }

            if let message = appState.portalSuccessMessage {
                PortalMessageBanner(message: message, isError: false)
            } else if let error = appState.portalErrorMessage {
                PortalMessageBanner(message: error, isError: true)
            }
        }
        .panelSurface()
    }

    /// 密码输入使用安全文本框，成功后立即清空全部密码状态。
    private var passwordPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("修改密码", systemImage: "lock")
                .font(.system(size: 14, weight: .semibold))
            SecureField("当前密码", text: $oldPassword)
                .textFieldStyle(.roundedBorder)
            SecureField("新密码（至少 8 个字符）", text: $newPassword)
                .textFieldStyle(.roundedBorder)
            SecureField("确认新密码", text: $passwordConfirmation)
                .textFieldStyle(.roundedBorder)
            Button("修改密码") {
                Task {
                    if await appState.changePassword(
                        oldPassword: oldPassword,
                        newPassword: newPassword,
                        confirmation: passwordConfirmation
                    ) {
                        oldPassword = ""
                        newPassword = ""
                        passwordConfirmation = ""
                    }
                }
            }
            .disabled(oldPassword.isEmpty || newPassword.isEmpty || passwordConfirmation.isEmpty)
        }
        .panelSurface()
    }

    /// 安全状态只展示接口能够确认的结果，未返回的 2FA 和 Passkey 不推测为已启用或未启用。
    private var authorizationPanel: some View {
        HStack(spacing: 0) {
            securityState("邮箱登录", icon: "envelope", value: "已绑定", isAvailable: true)
            Divider().frame(height: 38)
            securityState("2FA 双因素认证", icon: "lock.shield", value: "状态未提供", isAvailable: false)
            Divider().frame(height: 38)
            securityState("Passkey 通行密钥", icon: "person.badge.key", value: "状态未提供", isAvailable: false)
        }
        .panelSurface(padding: 0)
    }

    /// 单个安全状态使用明确文字，灰色表示接口未提供而不是功能不可用。
    private func securityState(_ title: String, icon: String, value: String, isAvailable: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(isAvailable ? AppTheme.accent : Color.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 11, weight: .medium))
                Text(value).font(AppTheme.captionFont).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 64)
    }

    /// 账户指标固定等分，避免金额长度影响并发值位置。
    private func accountMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(AppTheme.captionFont).foregroundStyle(.secondary)
            Text(value).font(.system(size: 14, weight: .semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

}

/// 页面级成功和错误提示共用的紧凑信息条。
private struct PortalMessageBanner: View {
    let message: String
    let isError: Bool

    /// 图标、颜色和文本保持同一语义，长错误信息允许换行但不遮挡后续内容。
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isError ? AppTheme.warning : AppTheme.accent)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            (isError ? AppTheme.warning : AppTheme.accent).opacity(0.08),
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
    }
}
