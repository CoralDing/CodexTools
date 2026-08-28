#!/usr/bin/env bash
# 文件说明：从高分辨率源图生成 SubPilot 的完整 macOS ICNS 图标资源
# 作者：dingyi60(Codex)
# 创建时间：2026-08-26

set -euo pipefail

readonly PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly SOURCE_ICON="${PROJECT_ROOT}/Resources/AppIconSource/SubPilot-1024.png"
readonly NORMALIZED_ICON="${PROJECT_ROOT}/Resources/AppIconSource/AppIcon.png"
readonly ICONSET_DIR="${PROJECT_ROOT}/Resources/AppIcon.iconset"
readonly OUTPUT_ICON="${PROJECT_ROOT}/Resources/AppIcon.icns"

if [[ ! -f "${SOURCE_ICON}" ]]; then
    echo "错误：缺少图标源文件 ${SOURCE_ICON}" >&2
    exit 1
fi

# 模型输出尺寸可能略大于请求值；先固定为带透明安全区的 1024 像素标准源图。
swift "${PROJECT_ROOT}/scripts/render_app_icon.swift" "${SOURCE_ICON}" "${NORMALIZED_ICON}"

rm -rf "${ICONSET_DIR}"
mkdir -p "${ICONSET_DIR}"

# iconutil 要求精确的文件名和像素尺寸，@2x 文件用于 Retina（高分辨率）屏幕。
sips -z 16 16 "${NORMALIZED_ICON}" --out "${ICONSET_DIR}/icon_16x16.png" >/dev/null
sips -z 32 32 "${NORMALIZED_ICON}" --out "${ICONSET_DIR}/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "${NORMALIZED_ICON}" --out "${ICONSET_DIR}/icon_32x32.png" >/dev/null
sips -z 64 64 "${NORMALIZED_ICON}" --out "${ICONSET_DIR}/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "${NORMALIZED_ICON}" --out "${ICONSET_DIR}/icon_128x128.png" >/dev/null
sips -z 256 256 "${NORMALIZED_ICON}" --out "${ICONSET_DIR}/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "${NORMALIZED_ICON}" --out "${ICONSET_DIR}/icon_256x256.png" >/dev/null
sips -z 512 512 "${NORMALIZED_ICON}" --out "${ICONSET_DIR}/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "${NORMALIZED_ICON}" --out "${ICONSET_DIR}/icon_512x512.png" >/dev/null
cp "${NORMALIZED_ICON}" "${ICONSET_DIR}/icon_512x512@2x.png"

iconutil -c icns "${ICONSET_DIR}" -o "${OUTPUT_ICON}"
echo "${OUTPUT_ICON}"
