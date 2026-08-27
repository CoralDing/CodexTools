/**
 * 文件说明：账户余额最近入账、扣减和调用消费活动弹窗
 * 作者：dingyi60(Codex)
 * 创建时间：2026-08-26
 */

import SwiftUI

/// 展示当前余额和最近余额变动，不把逐条账单明细写入本地持久化存储。
struct BalanceActivityView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
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
        .frame(width: 430, height: 480)
        .background(.ultraThinMaterial)
    }

    /// 标题栏提供数据范围、时区、手动刷新和关闭命令。
    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("余额最近活动")
                    .font(.system(size: 16, weight: .semibold))
                Text("最近 20 条余额变动 · \(selectedTimeZone.identifier)")
                    .font(.system(size: 10))
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
            .help("刷新余额活动")
            .disabled(appState.isLoadingBalanceActivities)

            Button(action: dismiss.callAsFunction) {
                Image(systemName: "xmark")
            }
            .buttonStyle(ToolbarIconButtonStyle())
            .help("关闭")
        }
        .padding(.horizontal, 16)
        .frame(height: 62)
    }

    /// 当前余额保持为弹窗首要信息，并用简短标签说明下面是余额变动流水。
    private var balanceSummary: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("当前可用余额")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(currency(balance))
                    .font(.system(size: 27, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.accent)
                    .monospacedDigit()
            }

            Spacer()

            Label("余额变动", systemImage: "arrow.up.arrow.down")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.accent)
        }
        .padding(.horizontal, 18)
        .frame(height: 88)
        .background(AppTheme.contentCanvas.opacity(0.46))
    }

    /// 根据请求状态切换为稳定的加载、错误、空数据或活动列表视图。
    @ViewBuilder
    private var activityContent: some View {
        if appState.isLoadingBalanceActivities && appState.balanceActivities.isEmpty {
            ProgressView("正在读取最近活动")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let message = appState.balanceActivityErrorMessage,
                  appState.balanceActivities.isEmpty {
            ContentUnavailableView {
                Label("活动读取失败", systemImage: "exclamationmark.triangle")
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
                Label("暂无余额活动", systemImage: "clock")
            } description: {
                Text("Sub2API 暂未返回余额变动记录")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                if appState.balanceActivityErrorMessage != nil {
                    Label("刷新失败，正在显示上次读取结果", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .medium))
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

    /// 单条活动突出余额增减；调用记录额外展示 Token 和响应时间供核对。
    private func activityRow(_ activity: BalanceActivity) -> some View {
        HStack(spacing: 12) {
            Image(systemName: activityIcon(activity))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(activityColor(activity))
                .frame(width: 26, height: 26)
                .background(activityColor(activity).opacity(0.10), in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(activity.title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Text(formattedTime(activity.createdAt))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Text(activityMetadata(activity))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(UsageFormatter.balanceChange(activity.amountChange))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(activityColor(activity))
                    .monospacedDigit()
                Text(activity.amountChange >= 0 ? "入账" : "扣减")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 61)
    }

    /// 将 Token 与可选响应时间压缩为单行，避免活动行随字段有无改变高度。
    private func activityMetadata(_ activity: BalanceActivity) -> String {
        var parts = [activity.detail]
        if let totalTokens = activity.totalTokens {
            parts.append("\(UsageFormatter.compactTokens(totalTokens)) Token")
        }
        if let duration = activity.durationMilliseconds {
            parts.append(UsageFormatter.duration(milliseconds: duration))
        }
        return parts.joined(separator: " · ")
    }

    /// 入账使用向上箭头，所有扣减使用向下箭头，避免只依赖颜色传达含义。
    private func activityIcon(_ activity: BalanceActivity) -> String {
        activity.amountChange >= 0 ? "arrow.up.right" : "arrow.down.right"
    }

    /// 入账沿用品牌青绿色，扣减沿用警示橙色，保持与余额状态的现有语义一致。
    private func activityColor(_ activity: BalanceActivity) -> Color {
        activity.amountChange >= 0 ? AppTheme.accent : AppTheme.warning
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
