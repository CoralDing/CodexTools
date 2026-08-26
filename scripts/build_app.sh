#!/usr/bin/env bash
# 文件说明：编译并组装可直接运行的 CodexTools.app
# 作者：dingyi60(Codex)
# 创建时间：2026-08-25

set -euo pipefail

readonly PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly APP_BUNDLE="${PROJECT_ROOT}/dist/CodexTools.app"
readonly CONTENTS_DIR="${APP_BUNDLE}/Contents"
readonly MACOS_DIR="${CONTENTS_DIR}/MacOS"
readonly RESOURCES_DIR="${CONTENTS_DIR}/Resources"

# 先使用 Swift Package Manager 生成经过优化的 arm64 原生可执行文件。
swift build --package-path "${PROJECT_ROOT}" --configuration release
readonly BIN_DIR="$(swift build --package-path "${PROJECT_ROOT}" --configuration release --show-bin-path)"

# 使用固定、精确的目标目录组装标准 macOS 应用包；install 会安全覆盖旧可执行文件。
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"
install -m 755 "${BIN_DIR}/CodexTools" "${MACOS_DIR}/CodexTools"
install -m 644 "${PROJECT_ROOT}/Resources/Info.plist" "${CONTENTS_DIR}/Info.plist"
install -m 644 "${PROJECT_ROOT}/Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"

# 本地开发版本使用临时签名，使 Keychain 和通知服务能识别稳定的 Bundle ID。
codesign --force --deep --sign - "${APP_BUNDLE}"

echo "${APP_BUNDLE}"
