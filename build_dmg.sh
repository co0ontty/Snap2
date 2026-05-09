#!/bin/bash
#
# Snap² 一键构建脚本
# 编译 → 生成图标 → 打包 App Bundle → 创建美化 DMG
#
# 用法: chmod +x build_dmg.sh && ./build_dmg.sh
#

set -euo pipefail

# ──────────────── 配置 ────────────────
APP_NAME="Snap2"
DISPLAY_NAME="Snap²"
BUNDLE_ID="com.chuer.snap2"
DMG_NAME="${APP_NAME}.dmg"
ZIP_NAME="${APP_NAME}.zip"
DMG_VOLUME_NAME="${DISPLAY_NAME}"
APP_BUNDLE="${APP_NAME}.app"
BUILD_DIR="build_output"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ICON_SET_DIR="${SCRIPT_DIR}/build_tmp/${APP_NAME}.iconset"
DMG_TEMP="${SCRIPT_DIR}/build_tmp/dmg_staging"
DMG_RW="${SCRIPT_DIR}/build_tmp/rw.dmg"

# 可选：Developer ID 签名身份。设置后走"Developer ID + 公证"路径，否则 ad-hoc。
# 例: export DEV_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)"
DEV_ID_APPLICATION="${DEV_ID_APPLICATION:-}"
# 可选：notarytool keychain profile（由 `xcrun notarytool store-credentials` 一次性创建）
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
# 可选：自签名 Code Signing 证书的 Common Name。
# 设置后走"自签名"路径：和 ad-hoc 不同，TCC 会以证书指纹作为身份，跨版本保留屏幕录制等权限。
# 优先级：DEV_ID_APPLICATION > SELF_SIGN_IDENTITY > ad-hoc。
# 例: export SELF_SIGN_IDENTITY="Snap2 Self Sign"
SELF_SIGN_IDENTITY="${SELF_SIGN_IDENTITY:-}"
# 可选：自签名路径下让 codesign 使用指定 keychain（CI 上常用，避免 system 默认 keychain 找不到 key）。
SELF_SIGN_KEYCHAIN="${SELF_SIGN_KEYCHAIN:-}"

cd "$SCRIPT_DIR"

# 版本号取自 Info.plist，避免与脚本常量两处维护漂移
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist 2>/dev/null || echo '0.0.0')"

# ──────────────── 环境检查 ────────────────
check_environment() {
    echo "=== 检查构建环境 ==="

    if [[ "$(uname)" != "Darwin" ]]; then
        echo "错误: 此脚本只能在 macOS 上运行 (当前系统: $(uname))"
        echo "请将项目复制到 Mac 后再执行此脚本。"
        exit 1
    fi

    if ! command -v swift &>/dev/null; then
        echo "错误: 未找到 swift 编译器，请安装 Xcode 或 Xcode Command Line Tools"
        echo "  xcode-select --install"
        exit 1
    fi

    if ! command -v iconutil &>/dev/null; then
        echo "警告: 未找到 iconutil，将跳过图标生成"
    fi

    local swift_version
    swift_version=$(swift --version 2>&1 | head -1)
    echo "  Swift: ${swift_version}"
    echo "  macOS: $(sw_vers -productVersion)"
    echo ""
}

# ──────────────── 清理 ────────────────
clean_previous() {
    echo "=== 清理上次构建产物 ==="
    rm -rf "${APP_BUNDLE}" "${DMG_NAME}" build_tmp
    mkdir -p build_tmp
    echo ""
}

# ──────────────── 编译 ────────────────
build_project() {
    echo "=== 编译项目 (Release) ==="
    mkdir -p "${BUILD_DIR}"
    # 不再 tail 截断 stderr，否则 CI 上失败时根因被吞
    swiftc -o "${BUILD_DIR}/${APP_NAME}" \
        -target arm64-apple-macosx14.0 \
        -sdk "$(xcrun --show-sdk-path)" \
        -swift-version 5 \
        -O \
        $(find Sources -name "*.swift")
    echo "  二进制文件: ${BUILD_DIR}/${APP_NAME}"
    echo ""
}

# ──────────────── 生成应用图标 ────────────────
generate_icon() {
    echo "=== 生成应用图标 ==="

    if ! command -v iconutil &>/dev/null; then
        echo "  跳过 (iconutil 不可用)"
        echo ""
        return
    fi

    # 复用 gen_icon.py，统一图标生成逻辑
    python3 gen_icon.py
    echo "  icns 文件: build_tmp/${APP_NAME}.icns"
    echo ""
}

# ──────────────── 创建 App Bundle ────────────────
create_app_bundle() {
    echo "=== 创建 App Bundle ==="

    local contents="${APP_BUNDLE}/Contents"
    local macos_dir="${contents}/MacOS"
    local resources_dir="${contents}/Resources"

    mkdir -p "${macos_dir}" "${resources_dir}"

    # 1. 复制二进制文件
    cp "${BUILD_DIR}/${APP_NAME}" "${macos_dir}/${APP_NAME}"
    chmod +x "${macos_dir}/${APP_NAME}"

    # 2. 复制 Info.plist
    cp "Resources/Info.plist" "${contents}/Info.plist"

    # 3. PkgInfo 文件
    echo -n "APPL????" > "${contents}/PkgInfo"

    # 4. 复制图标
    if [ -f "build_tmp/${APP_NAME}.icns" ]; then
        cp "build_tmp/${APP_NAME}.icns" "${resources_dir}/AppIcon.icns"
        # 在 Info.plist 中添加图标引用（如果还没有）
        if ! grep -q "CFBundleIconFile" "${contents}/Info.plist"; then
            sed -i '' 's|</dict>|    <key>CFBundleIconFile</key>\n    <string>AppIcon</string>\n</dict>|' "${contents}/Info.plist"
        fi
    fi

    # 5. 签名
    if [ -n "${DEV_ID_APPLICATION}" ]; then
        echo "  签名 App Bundle (Developer ID + Hardened Runtime)..."
        # 内层二进制先签，再签 .app
        find "${APP_BUNDLE}/Contents" -type f \( -perm -u+x -o -name "*.dylib" \) \
            -not -path "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}" -print0 \
            | xargs -0 -I {} codesign --force --options runtime --timestamp \
                --sign "${DEV_ID_APPLICATION}" \
                --entitlements "Resources/${APP_NAME}.entitlements" \
                "{}" 2>/dev/null || true
        codesign --force --options runtime --timestamp \
            --sign "${DEV_ID_APPLICATION}" \
            --entitlements "Resources/${APP_NAME}.entitlements" \
            "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
        codesign --force --options runtime --timestamp \
            --sign "${DEV_ID_APPLICATION}" \
            --entitlements "Resources/${APP_NAME}.entitlements" \
            "${APP_BUNDLE}"
        echo "  验证签名..."
        codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"
    elif [ -n "${SELF_SIGN_IDENTITY}" ]; then
        echo "  签名 App Bundle (Self-signed: ${SELF_SIGN_IDENTITY})..."
        # 自签名不开 hardened runtime / timestamp：
        #   - 不用走公证；
        #   - hardened runtime 会拒掉一些 API，对裸机 Swift app 反而碍事；
        #   - timestamp 需要 Apple TSA，自签证书走不通。
        local sign_keychain_arg=()
        if [ -n "${SELF_SIGN_KEYCHAIN}" ]; then
            sign_keychain_arg=(--keychain "${SELF_SIGN_KEYCHAIN}")
        fi
        codesign --force --deep --sign "${SELF_SIGN_IDENTITY}" \
            "${sign_keychain_arg[@]}" \
            --entitlements "Resources/${APP_NAME}.entitlements" \
            "${APP_BUNDLE}"
        echo "  验证签名..."
        codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"
        # 打印 designated requirement，方便人工核对证书指纹是否稳定
        echo "  designated requirement:"
        codesign -d --requirements - "${APP_BUNDLE}" 2>&1 | sed 's/^/    /'
    else
        echo "  签名 App Bundle (ad-hoc)..."
        codesign --force --deep --sign - \
            --entitlements "Resources/${APP_NAME}.entitlements" \
            "${APP_BUNDLE}" 2>/dev/null || echo "  警告: 签名失败 (ad-hoc)，应用仍可本地运行"
    fi

    # 6. 验证 Bundle 结构
    echo "  验证 Bundle 结构..."
    local ok=true
    for f in "${contents}/Info.plist" "${contents}/PkgInfo" "${macos_dir}/${APP_NAME}"; do
        if [ ! -f "$f" ]; then
            echo "    缺失: $f"
            ok=false
        fi
    done
    if $ok; then
        echo "  Bundle 结构完整"
    fi

    local app_size
    app_size=$(du -sh "${APP_BUNDLE}" | cut -f1)
    echo "  App 大小: ${app_size}"
    echo ""
}

# ──────────────── 打 ZIP（用于自动更新通道）────────────────
create_zip() {
    echo "=== 创建 ZIP 自动更新包 ==="
    rm -f "${ZIP_NAME}"
    /usr/bin/ditto -c -k --keepParent "${APP_BUNDLE}" "${ZIP_NAME}"
    local zip_size
    zip_size=$(du -sh "${ZIP_NAME}" | cut -f1)
    echo "  ZIP 大小: ${zip_size}"
    echo ""
}

# ──────────────── 公证（仅 Developer ID 路径）────────────────
notarize_artifact() {
    local artifact="$1"
    if [ -z "${DEV_ID_APPLICATION}" ] || [ -z "${NOTARY_PROFILE}" ]; then
        return 0
    fi
    echo "  公证 ${artifact}..."
    xcrun notarytool submit "${artifact}" \
        --keychain-profile "${NOTARY_PROFILE}" \
        --wait
    echo "  staple ${artifact}..."
    xcrun stapler staple "${artifact}"
}

# ──────────────── 创建美化 DMG ────────────────
create_dmg() {
    echo "=== 创建 DMG 安装包 ==="

    rm -rf "${DMG_TEMP}" "${DMG_RW}" "${DMG_NAME}"
    mkdir -p "${DMG_TEMP}"

    # 复制 App 到临时目录
    cp -R "${APP_BUNDLE}" "${DMG_TEMP}/"

    # 创建 Applications 快捷方式
    ln -s /Applications "${DMG_TEMP}/Applications"

    # DMG 窗口尺寸
    local win_w=540
    local win_h=380

    # 生成 DMG 背景图
    echo "  生成 DMG 背景图..."
    mkdir -p "${DMG_TEMP}/.background"
    python3 - "${DMG_TEMP}/.background/bg.png" ${win_w} ${win_h} <<'BGEOF'
import sys, struct, zlib

out_path = sys.argv[1]
W, H = int(sys.argv[2]), int(sys.argv[3])

raw = b''
for y in range(H):
    raw += b'\x00'
    for x in range(W):
        # 浅灰白渐变背景
        ratio = y / H
        v = int(248 - ratio * 18)
        raw += struct.pack('BBB', v, v, v)

def chunk(ctype, data):
    c = ctype + data
    return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)

sig = b'\x89PNG\r\n\x1a\n'
ihdr = struct.pack('>IIBBBBB', W, H, 8, 2, 0, 0, 0)
idat = zlib.compress(raw, 9)
png = sig + chunk(b'IHDR', ihdr) + chunk(b'IDAT', idat) + chunk(b'IEND', b'')

with open(out_path, 'wb') as f:
    f.write(png)
print("  背景图已生成")
BGEOF

    # 1. 创建可读写 DMG
    echo "  创建临时 DMG..."
    hdiutil create -srcfolder "${DMG_TEMP}" \
        -volname "${DMG_VOLUME_NAME}" \
        -fs HFS+ \
        -format UDRW \
        -size 100m \
        "${DMG_RW}" -quiet

    # 2. 挂载并美化
    echo "  美化 DMG 窗口布局..."
    local mount_dir
    mount_dir=$(hdiutil attach "${DMG_RW}" -readwrite -noverify -noautoopen | grep -o '/Volumes/.*' | tail -1)

    # 等待挂载完成
    sleep 1

    # 用 AppleScript 设置 Finder 窗口样式
    osascript <<ASEOF
tell application "Finder"
    tell disk "${DMG_VOLUME_NAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, $((200 + win_w)), $((120 + win_h))}

        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 80
        set text size of viewOptions to 13
        set background picture of viewOptions to file ".background:bg.png"

        -- App 图标位置（左侧）
        set position of item "${APP_NAME}.app" of container window to {150, 185}
        -- Applications 快捷方式位置（右侧）
        set position of item "Applications" of container window to {390, 185}

        close
        open
        update without registering applications

        delay 1
        close
    end tell
end tell
ASEOF

    # 确保 Finder 写入完成
    sync
    sleep 1

    # 3. 卸载
    hdiutil detach "${mount_dir}" -quiet 2>/dev/null || hdiutil detach "${mount_dir}" -force -quiet

    # 4. 转换为压缩只读 DMG
    echo "  压缩为最终 DMG..."
    hdiutil convert "${DMG_RW}" \
        -format UDZO \
        -imagekey zlib-level=9 \
        -o "${DMG_NAME}" -quiet

    local dmg_size
    dmg_size=$(du -sh "${DMG_NAME}" | cut -f1)
    echo "  DMG 大小: ${dmg_size}"
    echo ""
}

# ──────────────── 清理临时文件 ────────────────
cleanup() {
    echo "=== 清理临时文件 ==="
    rm -rf build_tmp
    echo ""
}

# ──────────────── 输出结果 ────────────────
print_result() {
    echo "============================================"
    echo "  构建完成!"
    echo "============================================"
    echo ""
    echo "  产物:"
    echo "    ${SCRIPT_DIR}/${APP_BUNDLE}"
    echo "    ${SCRIPT_DIR}/${DMG_NAME}     (首次手动安装)"
    echo "    ${SCRIPT_DIR}/${ZIP_NAME}     (内置自动更新通道)"
    echo ""
    echo "  Release 上传两个产物：DMG 给首装用户，ZIP 给自动更新流程。"
    echo ""
    echo "  安装方式:"
    echo "    1. 双击 ${DMG_NAME}"
    echo "    2. 将 ${APP_NAME}.app 拖入 Applications 文件夹"
    echo "    3. 从 Launchpad 或 Applications 启动 ${APP_NAME}"
    echo ""
    if [ -n "${DEV_ID_APPLICATION}" ]; then
        echo "  Developer ID 签名 + 公证已启用，首次运行无需特殊操作。"
    elif [ -n "${SELF_SIGN_IDENTITY}" ]; then
        echo "  首次运行注意 (自签名: ${SELF_SIGN_IDENTITY}):"
        echo "    - Gatekeeper 仍会提示「无法验证开发者」，走「系统设置 > 隐私与安全性 > 仍要打开」一次"
        echo "    - 屏幕录制权限：系统设置 > 隐私与安全性 > 屏幕录制"
        echo "    - 升级版本后权限会保留（前提：始终用同一张证书签名）"
    else
        echo "  首次运行注意 (ad-hoc 签名):"
        echo "    - 系统会提示「无法验证开发者」"
        echo "    - macOS 15+ 必须走「系统设置 > 隐私与安全性 > 仍要打开」"
        echo "    - 屏幕录制权限：系统设置 > 隐私与安全性 > 屏幕录制"
        echo "    - 升级版本后屏幕录制权限会被重置（ad-hoc 签名局限，配置 SELF_SIGN_IDENTITY 或 Developer ID 可根治）"
    fi
    echo ""
    echo "  快捷键: Ctrl+Shift+A (可在设置中自定义)"
    echo "============================================"
}

# ──────────────── 主流程 ────────────────
main() {
    echo ""
    echo "╔══════════════════════════════════════╗"
    echo "║    Snap² Screenshot Tool Builder     ║"
    echo "║           v${VERSION}                    ║"
    echo "╚══════════════════════════════════════╝"
    echo ""

    check_environment
    clean_previous
    build_project
    generate_icon
    create_app_bundle
    create_zip
    notarize_artifact "${APP_BUNDLE}"
    create_dmg
    notarize_artifact "${DMG_NAME}"
    cleanup
    print_result
}

main "$@"
