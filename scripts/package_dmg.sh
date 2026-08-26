#!/usr/bin/env bash
# 文件说明：构建 CodexTools 应用并生成可拖入“应用程序”文件夹安装的 DMG
# 作者：dingyi60(Codex)
# 创建时间：2026-08-26

set -euo pipefail

readonly PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${PROJECT_ROOT}/Resources/Info.plist")"
readonly ARCHITECTURE="$(uname -m)"
readonly APP_BUNDLE="${PROJECT_ROOT}/dist/CodexTools.app"
readonly DMG_PATH="${PROJECT_ROOT}/dist/CodexTools-${VERSION}-macos-${ARCHITECTURE}.dmg"
readonly STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codextools-dmg.XXXXXX")"

# 无论打包成功或失败，都清理临时装载目录，避免残留无用文件。
cleanup() {
    rm -rf "${STAGING_DIR}"
}
trap cleanup EXIT

"${PROJECT_ROOT}/scripts/generate_app_icon.sh"
"${PROJECT_ROOT}/scripts/build_app.sh"

# 安装映像只保留应用和 Applications 快捷方式，用户打开后可直接拖拽安装。
cp -R "${APP_BUNDLE}" "${STAGING_DIR}/CodexTools.app"
ln -s /Applications "${STAGING_DIR}/Applications"
rm -f "${DMG_PATH}"

hdiutil create \
    -volname "CodexTools" \
    -srcfolder "${STAGING_DIR}" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov \
    "${DMG_PATH}"

echo "${DMG_PATH}"
