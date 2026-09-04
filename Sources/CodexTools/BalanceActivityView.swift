/**
 * 文件说明：账户余额最近增加活动弹窗
 * 作者：dingyi60(Codex)
 * 创建时间：2026-08-26
 */

import SwiftUI

/// 展示当前余额和最近增加活动，不把逐条账户记录写入本地持久化存储。
struct BalanceActivityView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage(PreferenceKey.displayTimeZone) private var displayTimeZone = TimeZone.current.identifier

    let balance: Double?

    /// 使用固定宽高保证加载、失败、空数据和长列表之间不会引起弹窗跳动。
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            balanceSummary
            Divider()
            activityContent
        }
        .frame(width: 440, height: 480)
        .background(Color.clear)
        .glassSurface(radius: 14, tint: AppTheme.floatingGlassTint, addsShadow: true)
    }

    /// 标题栏提供数据范围、时区和手动刷新；原生弹窗可点击外部关闭，无需重复关闭按钮。
    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("余额增加记录")
                    .font(.system(size: 16, weight: .semibold))
                Text("最近 20 条余额增加 · \(selectedTimeZone.identifier)")
                    .font(AppTheme.captionFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                Task { await appState.loadBalanceActivities(force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(ToolbarIconButtonStyle())
            .help("刷新余额增加记录")
            .disabled(appState.isLoadingBalanceActivities)

        }
        .padding(.horizontal, 16)
        .frame(height: 62)
    }

    /// 当前余额保持为弹窗首要信息，并明确下面只展示余额增加活动。
    private var balanceSummary: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("当前可用余额")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(currency(balance))
                    .font(.system(size: 27, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }

            Spacer()

            Text("最近 20 条入账")
                .font(AppTheme.captionFont)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .frame(height: 88)
        .background(AppTheme.contentCanvas.opacity(0.46))
    }

    /// 根据请求状态切换为稳定的加载、错误、空数据或活动列表视图。
    @ViewBuilder
    private var activityContent: some View {
        if appState.isLoadingBalanceActivities && appState.balanceActivities.isEmpty {
            ProgressView("正在读取余额增加记录")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let message = appState.balanceActivityErrorMessage,
                  appState.balanceActivities.isEmpty {
            ContentUnavailableView {
                Label("余额记录读取失败", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("重新加载") {
                    Task { await appState.loadBalanceActivities(force: true) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if appState.balanceActivities.isEmpty {
            ContentUnavailableView {
                Label("暂无余额增加记录", systemImage: "clock")
            } description: {
                Text("Sub2API 暂未返回充值或加款记录")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                if appState.balanceActivityErrorMessage != nil {
                    Label("刷新失败，正在显示上次读取结果", systemImage: "exclamationmark.triangle.fill")
                        .font(AppTheme.captionFont.weight(.medium))
                        .foregroundStyle(AppTheme.warning)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                    Divider()
                }

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(appState.balanceActivities.enumerated()), id: \.offset) { index, activity in
                            activityRow(activity)
                            if index < appState.balanceActivities.count - 1 {
                                Divider().padding(.leading, 50)
                            }
                        }
                    }
                }
            }
        }
    }

    /// 单条记录突出余额增加金额，并展示具体活动来源。
    private func activityRow(_ activity: BalanceActivity) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.up.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.success)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(activity.title)
                        .font(AppTheme.bodyEmphasizedFont)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(UsageFormatter.balanceChange(activity.amountChange))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.success)
                        .monospacedDigit()
                }

                HStack(spacing: 8) {
                    Text(activity.detail)
                        .font(AppTheme.captionFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(formattedTime(activity.createdAt))
                        .font(AppTheme.captionFont)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 61)
    }

    /// 使用用户选择的时区显示月日和分钟，保证与重置时间口径一致。
    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = selectedTimeZone
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }

    /// 空余额使用长横线表达未知，避免误显示为零余额。
    private func currency(_ value: Double?) -> String {
        guard let value else { return "—" }
        return UsageFormatter.cost(value)
    }

    /// 无效的时区设置回退到 Mac 当前时区，避免日期格式化失败。
    private var selectedTimeZone: TimeZone {
        TimeZone(identifier: displayTimeZone) ?? .current
    }
}
