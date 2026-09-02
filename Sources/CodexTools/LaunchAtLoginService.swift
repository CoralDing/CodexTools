/**
 * 文件说明：管理 SubPilot 的 macOS 开机登录自启动状态
 * 作者：dingyi60(Codex)
 * 创建时间：2026-09-01
 */

import Foundation
import ServiceManagement

/// 将系统登录项状态转换为界面和业务层容易理解的稳定状态。
enum LaunchAtLoginStatus: Equatable {
    case enabled
    case disabled
    case requiresApproval
    case unavailable
}

/// 封装 SMAppService（macOS 原生登录项管理接口），统一处理首次默认开启和用户手动切换。
enum LaunchAtLoginService {
    /// 返回当前登录项的真实系统状态；非应用包运行方式无法注册登录项。
    static var status: LaunchAtLoginStatus {
        guard isRunningFromApplicationBundle else { return .unavailable }

        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered:
            return .disabled
        case .notFound:
            return .unavailable
        @unknown default:
            return .unavailable
        }
    }

    /// 按用户选择注册或注销登录项，并返回操作后的真实状态供界面即时反馈。
    @discardableResult
    static func setEnabled(_ enabled: Bool) throws -> LaunchAtLoginStatus {
        guard isRunningFromApplicationBundle else {
            throw LaunchAtLoginError.requiresApplicationBundle
        }

        let service = SMAppService.mainApp
        if enabled {
            // 已启用或等待系统批准时不重复注册，避免系统不断生成相同授权请求。
            switch service.status {
            case .enabled, .requiresApproval:
                return status
            case .notRegistered, .notFound:
                try service.register()
            @unknown default:
                try service.register()
            }
        } else {
            // 未注册状态视为已经关闭，避免无意义的注销调用产生系统错误。
            switch service.status {
            case .enabled, .requiresApproval:
                try service.unregister()
            case .notRegistered, .notFound:
                return .disabled
            @unknown default:
                try service.unregister()
            }
        }

        return status
    }

    /// 应用启动时应用已保存偏好；注册默认值为开启，因此首次安装会自动创建登录项。
    static func synchronizePreferredState() {
        let environment = ProcessInfo.processInfo.environment
        // QA（质量检查）和命令行预览不应修改当前用户的系统登录项。
        guard environment["CODEXTOOLS_QA_WINDOW"] != "1",
              environment["CODEXTOOLS_QA_RENDER_DIR"] == nil,
              isRunningFromApplicationBundle else {
            return
        }

        let shouldEnable = UserDefaults.standard.bool(forKey: PreferenceKey.launchAtLoginEnabled)
        // 启动同步失败不会阻止应用打开；用户仍可在设置页再次操作并看到具体错误。
        _ = try? setEnabled(shouldEnable)
    }

    /// 只有标准 `.app` 应用包具备稳定的可执行路径，才能可靠加入系统登录项。
    private static var isRunningFromApplicationBundle: Bool {
        Bundle.main.bundleURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame
    }
}

/// 将登录项注册失败转换为用户可理解的设置页提示。
private enum LaunchAtLoginError: LocalizedError {
    case requiresApplicationBundle

    /// 解释为什么开发环境直接运行可执行文件时无法开启登录项。
    var errorDescription: String? {
        switch self {
        case .requiresApplicationBundle:
            return "请从 Applications（应用程序）文件夹启动 SubPilot 后再开启"
        }
    }
}
