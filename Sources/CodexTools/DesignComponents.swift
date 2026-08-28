/**
 * 文件说明：SubPilot 通用指标轨道、分区标题和状态标签组件
 * 作者：dingyi60(Codex)
 * 创建时间：2026-08-28
 */

import SwiftUI

/// 描述一个可横向比较的运营指标，避免概览和使用记录重复拼装标题、数字与说明。
struct AppMetricItem: Identifiable {
    let id: String
    let icon: String
    let title: String
    let value: String
    let detail: String?

    /// 默认使用标题作为稳定标识；同一轨道内标题应保持唯一。
    init(icon: String, title: String, value: String, detail: String? = nil) {
        id = title
        self.icon = icon
        self.title = title
        self.value = value
        self.detail = detail
    }
}

/// 把多个关键指标放入一个连续表面，使用分隔线表达比较关系而不是生成一组独立卡片。
struct AppMetricRail: View {
    let items: [AppMetricItem]
    var compact = false

    /// 所有指标共享同一高度和数字基线，内容变化时不会推动相邻列位移。
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                metricCell(item)
                if index < items.count - 1 {
                    Divider()
                        .frame(height: compact ? 42 : 50)
                }
            }
        }
        .panelSurface(padding: 0)
    }

    /// 单格把标题、主值和口径说明分成三级，最小字号保持在 11pt 以上。
    private func metricCell(_ item: AppMetricItem) -> some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 7) {
            Label(item.title, systemImage: item.icon)
                .font(AppTheme.captionFont)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(item.value)
                .font(compact ? .system(size: 17, weight: .semibold, design: .rounded) : AppTheme.metricFont)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            if let detail = item.detail {
                Text(detail)
                    .font(AppTheme.captionFont)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, compact ? 12 : 14)
        .frame(maxWidth: .infinity, minHeight: compact ? 70 : 84, alignment: .leading)
    }
}

/// 为表格、图表和列表提供统一的标题高度与辅助信息对齐方式。
struct AppSectionHeader: View {
    let title: String
    var trailing: String?

    /// 标题始终保持主文字层级，右侧说明使用次级文字且不会挤压标题。
    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(AppTheme.sectionTitleFont)
            Spacer(minLength: 12)
            if let trailing {
                Text(trailing)
                    .font(AppTheme.captionFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
    }
}

/// 使用系统语义颜色展示带圆点的明确状态，颜色只辅助文字而不单独承载含义。
struct AppStatusLabel: View {
    let title: String
    let color: Color

    /// 固定圆点尺寸和文字字号，表格状态列与窗口连接状态能够保持一致。
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .font(AppTheme.captionFont.weight(.medium))
        }
        .foregroundStyle(color)
    }
}
