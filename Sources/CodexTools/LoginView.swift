/**
 * 文件说明：Sub2API 登录与两步验证界面
 * 作者：dingyi60(Codex)
 * 创建时间：2026-08-25
 */

import SwiftUI

/// 收集服务器和登录凭据，并在服务端要求时切换到两步验证流程。
struct LoginView: View {
    @EnvironmentObject private var appState: AppState
    @State private var server = ""
    @State private var email = ""
    @State private var password = ""
    @State private var twoFactorCode = ""
    @State private var showsPassword = false
    @FocusState private var focusedField: LoginField?

    /// 区分输入焦点，使边框强调和回车跳转保持一致。
    private enum LoginField: Hashable {
        case server
        case email
        case password
    }

    /// 根据认证阶段展示完整表单，窗口高度固定以避免状态切换时跳动。
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 24)

            Group {
                if let challenge = appState.pendingTwoFactor {
                    twoFactorContent(challenge)
                } else {
                    credentialsContent
                }
            }

            Spacer(minLength: 18)

            if let error = appState.errorMessage {
                errorMessage(error)
                    .padding(.bottom, 12)
            }

            Button(action: submit) {
                HStack(spacing: 8) {
                    if appState.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    }
                    Text(primaryButtonTitle)
                }
                .frame(maxWidth: .infinity)
            }
            .subPilotProminentGlassButtonStyle()
            .controlSize(.large)
            .disabled(!canSubmit || appState.isLoading)

            if appState.pendingTwoFactor != nil {
                Button {
                    twoFactorCode = ""
                    appState.cancelTwoFactor()
                } label: {
                    Label("返回邮箱密码登录", systemImage: "arrow.left")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.top, 14)
            }
        }
        .padding(AppTheme.contentPadding)
        .frame(minHeight: 480)
        .background(Color.clear)
        .animation(.easeInOut(duration: 0.18), value: appState.pendingTwoFactor != nil)
    }

    /// 标题区以产品名作为第一视觉信号，并保持说明文字简短。
    private var header: some View {
        HStack(spacing: 12) {
            SubPilotBrandIcon(size: 38)
            VStack(alignment: .leading, spacing: 4) {
                Text("SubPilot")
                    .font(.system(size: 21, weight: .semibold))
                Text(appState.pendingTwoFactor == nil ? "登录 Sub2API，同步模型用量" : "完成两步验证")
                    .font(AppTheme.bodyFont)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 展示服务器、邮箱和密码输入；密码仅保存在当前视图内存中。
    private var credentialsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            labeledField("服务器地址") {
                fieldShell(icon: "server.rack", isFocused: focusedField == .server) {
                    TextField("https://your-sub2api.example", text: $server)
                        .textFieldStyle(.plain)
                        .focused($focusedField, equals: .server)
                        .onSubmit { focusedField = .email }
                }
            }

            labeledField("邮箱") {
                fieldShell(icon: "envelope", isFocused: focusedField == .email) {
                    TextField("name@example.com", text: $email)
                        .textFieldStyle(.plain)
                        .focused($focusedField, equals: .email)
                        .onSubmit { focusedField = .password }
                }
            }

            labeledField("密码") {
                fieldShell(icon: "lock", isFocused: focusedField == .password) {
                    Group {
                        if showsPassword {
                            TextField("请输入密码", text: $password)
                        } else {
                            SecureField("请输入密码", text: $password)
                        }
                    }
                    .textFieldStyle(.plain)
                    .focused($focusedField, equals: .password)
                    .onSubmit(submit)

                    Button {
                        showsPassword.toggle()
                    } label: {
                        Image(systemName: showsPassword ? "eye.slash" : "eye")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(showsPassword ? "隐藏密码" : "显示密码")
                }
            }

            securityNote("仅登录令牌保存在本机钥匙串，不保存密码")
        }
    }

    /// 展示 6 位 TOTP 验证码和脱敏账户，不复用第一步的密码输入。
    private func twoFactorContent(_ challenge: PendingTwoFactor) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("6 位验证码")
                    .font(.system(size: 14, weight: .medium))
                Text(challenge.maskedEmail.map { "请验证账户 \($0)" } ?? "请输入身份验证器中的验证码")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TwoFactorCodeField(code: $twoFactorCode, onSubmit: submit)

            securityNote("验证码只用于本次验证，不会保存")
        }
        .padding(.top, 12)
    }

    /// 标签与输入框在同一布局单元中排列，避免用负间距手工拼接导致焦点切换时跳动。
    private func labeledField<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AppTheme.bodyEmphasizedFont)
                .foregroundStyle(.secondary)
            content()
        }
    }

    /// 使用图标、统一高度和焦点边框构建输入容器，避免系统默认样式在不同字段间不一致。
    private func fieldShell<Content: View>(
        icon: String,
        isFocused: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(isFocused ? AppTheme.accent : .secondary)
                .frame(width: 17)
            content()
        }
        .padding(.horizontal, 11)
        .frame(height: 40)
        .background(AppTheme.subtleSurface, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .stroke(isFocused ? AppTheme.accent : AppTheme.border, lineWidth: isFocused ? 1.5 : 1)
        }
    }

    /// 安全提示使用锁图标和次级文字，不与错误或主操作争夺注意力。
    private func securityNote(_ text: String) -> some View {
        Label(text, systemImage: "lock.shield")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 错误信息放在轻量提示条中，长服务端消息可以自然换行。
    private func errorMessage(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.07), in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
    }

    /// 仅在当前认证阶段的必要字段完整时启用主按钮。
    private var canSubmit: Bool {
        if appState.pendingTwoFactor != nil {
            return twoFactorCode.count == 6
        }
        return !server.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
    }

    /// 根据当前阶段提交邮箱密码或两步验证码，提交前立即清空视图中的密码。
    private func submit() {
        guard canSubmit else { return }

        if appState.pendingTwoFactor != nil {
            let code = twoFactorCode
            Task { await appState.completeTwoFactor(code: code) }
            return
        }

        let submittedPassword = password
        password = ""
        Task {
            await appState.login(server: server, email: email, password: submittedPassword)
        }
    }

    /// 根据加载状态和认证阶段生成准确的主按钮文字。
    private var primaryButtonTitle: String {
        if appState.isLoading { return "正在验证" }
        return appState.pendingTwoFactor == nil ? "登录" : "验证并登录"
    }
}

/// 使用单一文本输入承载粘贴和键盘输入，同时以六个稳定方格呈现验证码。
private struct TwoFactorCodeField: View {
    @Binding var code: String
    let onSubmit: () -> Void
    @FocusState private var isFocused: Bool

    /// 透明输入层保证整行都可点击，视觉层只负责稳定展示每一位数字。
    var body: some View {
        ZStack {
            HStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { index in
                    codeBox(at: index)
                }
            }

            TextField("", text: $code)
                .textFieldStyle(.plain)
                .foregroundStyle(.clear)
                .tint(.clear)
                .opacity(0.02)
                .focused($isFocused)
                .onSubmit(onSubmit)
                .onChange(of: code) { _, newValue in
                    // 过滤粘贴内容中的空格和连字符，并限制为服务端要求的 6 位数字。
                    code = String(newValue.filter(\.isNumber).prefix(6))
                }
                .accessibilityLabel("6 位验证码")
        }
        .frame(height: 48)
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
        .onAppear { isFocused = true }
    }

    /// 单个验证码方格根据输入位置显示焦点边框，不改变固定尺寸。
    private func codeBox(at index: Int) -> some View {
        let characters = Array(code)
        let isActive = isFocused && (index == min(code.count, 5))

        return Text(index < characters.count ? String(characters[index]) : "")
            .font(.system(size: 21, weight: .medium, design: .monospaced))
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(AppTheme.subtleSurface, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .stroke(isActive ? AppTheme.accent : AppTheme.border, lineWidth: isActive ? 1.5 : 1)
            }
    }
}
