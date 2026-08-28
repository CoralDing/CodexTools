/**
 * 文件说明：根据登录状态切换登录页与用量悬浮层
 * 作者：dingyi60(Codex)
 * 创建时间：2026-08-25
 */

import SwiftUI

/// 作为菜单栏玻璃悬浮层的根视图，避免两个页面各自决定窗口尺寸。
struct RootView: View {
    @EnvironmentObject private var appState: AppState

    /// 已存在安全会话时展示数据，否则展示登录表单。
    var body: some View {
        Group {
            if appState.session == nil {
                LoginView()
            } else {
                DashboardView()
            }
        }
        .frame(width: 372)
        .background(SubPilotWindowBackdrop())
    }
}
