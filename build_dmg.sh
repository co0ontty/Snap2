#!/bin/bash
#
# Snap² 一键构建脚本（双架构）
#
# 编译 arm64 + x86_64 两份二进制，再 lipo 合一份 universal：
#   - Snap2-arm64.dmg     （Apple Silicon 单架构 .app，体积小）
#   - Snap2-x86_64.dmg    （Intel 单架构 .app）
#   - Snap2.zip           （universal .app，自动更新通道，跨架构通吃）
#
# 用法: chmod +x build_dmg.sh && ./build_dmg.sh
#

set -euo pipefail

# ──────────────── 配置 ────────────────
APP_NAME="Snap2"
DISPLAY_NAME="Snap²"
BUNDLE_ID="com.chuer.snap2"
ZIP_NAME="${APP_NAME}.zip"
DMG_VOLUME_NAME="${DISPLAY_NAME}"
APP_BUNDLE="${APP_NAME}.app"            # universal .app（zip 通道）
BUILD_DIR="build_output"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 支持的架构
ARCHS=("arm64" "x86_64")

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

    if ! command -v lipo &>/dev/null; then
        echo "错误: 未找到 lipo（双架构合并需要）"
        exit 1
    fi

    if ! command -v iconutil &>/dev/null; then
        echo "警告: 未找到 iconutil，将跳过图标生成"
    fi

    local swift_version
    swift_version=$(swift --version 2>&1 | head -1)
    echo "  Swift: ${swift_version}"
    echo "  macOS: $(sw_vers -productVersion)"
    echo "  目标架构: ${ARCHS[*]} + universal"
    echo ""
}

# ──────────────── 清理 ────────────────
clean_previous() {
    echo "=== 清理上次构建产物 ==="
    rm -rf "${APP_BUNDLE}"
    rm -rf "${APP_NAME}-arm64.app" "${APP_NAME}-x86_64.app"
    rm -f "${APP_NAME}.dmg" "${APP_NAME}-arm64.dmg" "${APP_NAME}-x86_64.dmg" "${ZIP_NAME}"
    rm -rf build_tmp "${BUILD_DIR}"
    mkdir -p build_tmp
    echo ""
}

# ──────────────── 编译（双架构 + 合并 universal）────────────────
build_project() {
    echo "=== 编译项目 (Release, 双架构) ==="
    mkdir -p "${BUILD_DIR}"
    local sources
    # shellcheck disable=SC2207
    sources=( $(find Sources -name "*.swift") )
    local sdk
    sdk="$(xcrun --show-sdk-path)"

    for arch in "${ARCHS[@]}"; do
        echo "  编译 ${arch}..."
        # 不再 tail 截断 stderr，否则 CI 上失败时根因被吞
        swiftc -o "${BUILD_DIR}/${APP_NAME}-${arch}" \
            -target "${arch}-apple-macosx14.0" \
            -sdk "${sdk}" \
            -swift-version 5 \
            -O \
            "${sources[@]}"
    done

    echo "  合并 universal binary (lipo)..."
    lipo -create \
        "${BUILD_DIR}/${APP_NAME}-arm64" \
        "${BUILD_DIR}/${APP_NAME}-x86_64" \
        -output "${BUILD_DIR}/${APP_NAME}-universal"
    lipo -info "${BUILD_DIR}/${APP_NAME}-universal" | sed 's/^/    /'
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
# arg1: 二进制路径
# arg2: 输出 .app 路径
build_app_bundle() {
    local binary_path="$1"
    local app_path="$2"

    echo "=== 创建 App Bundle: ${app_path} ==="

    rm -rf "${app_path}"
    local contents="${app_path}/Contents"
    local macos_dir="${contents}/MacOS"
    local resources_dir="${contents}/Resources"

    mkdir -p "${macos_dir}" "${resources_dir}"

    # 1. 复制二进制文件
    cp "${binary_path}" "${macos_dir}/${APP_NAME}"
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
    sign_bundle "${app_path}"

    # 6. 验证 Bundle 结构
    echo "  验证 Bundle 结构..."
    local ok=true
    for f in "${contents}/Info.plist" "${contents}/PkgInfo" "${macos_dir}/${APP_NAME}"; do
        if [ ! -f "$f" ]; then
            echo "    缺失: $f"
            ok=false
        fi
    done
    $ok && echo "  Bundle 结构完整"

    # 打印架构信息（debug 友好）
    echo "  二进制架构:"
    lipo -archs "${macos_dir}/${APP_NAME}" | sed 's/^/    /'

    local app_size
    app_size=$(du -sh "${app_path}" | cut -f1)
    echo "  App 大小: ${app_size}"
    echo ""
}

# ──────────────── 签名 ────────────────
sign_bundle() {
    local app_path="$1"

    if [ -n "${DEV_ID_APPLICATION}" ]; then
        echo "  签名 (Developer ID + Hardened Runtime)..."
        # 内层二进制先签，再签 .app
        find "${app_path}/Contents" -type f \( -perm -u+x -o -name "*.dylib" \) \
            -not -path "${app_path}/Contents/MacOS/${APP_NAME}" -print0 \
            | xargs -0 -I {} codesign --force --options runtime --timestamp \
                --sign "${DEV_ID_APPLICATION}" \
                --entitlements "Resources/${APP_NAME}.entitlements" \
                "{}" 2>/dev/null || true
        codesign --force --options runtime --timestamp \
            --sign "${DEV_ID_APPLICATION}" \
            --entitlements "Resources/${APP_NAME}.entitlements" \
            "${app_path}/Contents/MacOS/${APP_NAME}"
        codesign --force --options runtime --timestamp \
            --sign "${DEV_ID_APPLICATION}" \
            --entitlements "Resources/${APP_NAME}.entitlements" \
            "${app_path}"
        echo "  验证签名..."
        codesign --verify --deep --strict --verbose=2 "${app_path}"
    elif [ -n "${SELF_SIGN_IDENTITY}" ]; then
        echo "  签名 (Self-signed: ${SELF_SIGN_IDENTITY})..."
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
            "${app_path}"
        echo "  验证签名..."
        codesign --verify --deep --strict --verbose=2 "${app_path}"
        echo "  designated requirement:"
        codesign -d --requirements - "${app_path}" 2>&1 | sed 's/^/    /'
    else
        echo "  签名 (ad-hoc)..."
        codesign --force --deep --sign - \
            --entitlements "Resources/${APP_NAME}.entitlements" \
            "${app_path}" 2>/dev/null || echo "  警告: 签名失败 (ad-hoc)，应用仍可本地运行"
    fi
}

# ──────────────── 打 ZIP（用于自动更新通道，universal）────────────────
create_zip() {
    echo "=== 创建 ZIP 自动更新包 (universal) ==="
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

# ──────────────── 卸载同名残留卷 ────────────────
# 在 CI 上多次 create+attach 后，可能出现 "/Volumes/Snap²"、"/Volumes/Snap² 1" 等残留
# 会让下一次 hdiutil create 静默失败（被 -quiet 吞掉只剩 exit 1）
detach_stale_volumes() {
    local prefix="$1"
    # /Volumes/Snap² /Volumes/Snap² 1 …
    while IFS= read -r vol; do
        [ -z "$vol" ] && continue
        echo "  卸载残留卷: $vol"
        hdiutil detach "$vol" -force 2>&1 | sed 's/^/    /' || true
    done < <(ls -d "/Volumes/${prefix}"* 2>/dev/null || true)
}

# ──────────────── 创建美化 DMG ────────────────
# arg1: 源 .app 路径
# arg2: 输出 .dmg 路径
create_dmg_for_app() {
    local source_app="$1"
    local dmg_out="$2"

    echo "=== 创建 DMG: ${dmg_out} ==="

    local stage="${SCRIPT_DIR}/build_tmp/dmg_$(basename "${dmg_out}" .dmg)"
    local rw_path="${stage}/rw.dmg"

    rm -rf "${stage}" "${dmg_out}"
    mkdir -p "${stage}/staging"

    # 清理上一次构建残留的同名挂载（CI 上常见）
    detach_stale_volumes "${DMG_VOLUME_NAME}"

    # 把源 .app 改名成统一的 Snap2.app 放进 dmg，免得拖到 Applications 后出现两份不同 bundle id
    cp -R "${source_app}" "${stage}/staging/${APP_BUNDLE}"

    # 创建 Applications 快捷方式
    ln -s /Applications "${stage}/staging/Applications"

    # DMG 窗口尺寸
    local win_w=540
    local win_h=380

    # 生成 DMG 背景图
    echo "  生成 DMG 背景图..."
    mkdir -p "${stage}/staging/.background"
    python3 - "${stage}/staging/.background/bg.png" ${win_w} ${win_h} <<'BGEOF'
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
    # 不再用 -quiet，否则 CI 上失败时根因被吞（之前 x86_64 步骤就是这么哑掉的）
    if ! hdiutil create -srcfolder "${stage}/staging" \
        -volname "${DMG_VOLUME_NAME}" \
        -fs HFS+ \
        -format UDRW \
        -size 200m \
        "${rw_path}"; then
        echo "  hdiutil create 失败，当前挂载状态："
        hdiutil info | sed 's/^/    /' || true
        exit 1
    fi

    # 2. 挂载并美化
    echo "  美化 DMG 窗口布局..."
    local mount_dir
    mount_dir=$(hdiutil attach "${rw_path}" -readwrite -noverify -noautoopen | grep -o '/Volumes/.*' | tail -1)
    # 从 mount_dir 反推真实卷名：上次同名卷未卸干净时 macOS 会自动改名为 "Snap² 1" 之类
    local mounted_volume_name
    mounted_volume_name=$(basename "${mount_dir}")

    # 等待挂载完成
    sleep 1

    # 用 AppleScript 设置 Finder 窗口样式
    osascript <<ASEOF
tell application "Finder"
    tell disk "${mounted_volume_name}"
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
        set position of item "${APP_BUNDLE}" of container window to {150, 185}
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

    # 3. 卸载（先正常 detach，失败再 force；保留输出以便排查）
    if ! hdiutil detach "${mount_dir}" 2>&1 | sed 's/^/    /'; then
        echo "  正常 detach 失败，尝试 force..."
        hdiutil detach "${mount_dir}" -force 2>&1 | sed 's/^/    /' || true
    fi
    # 再扫一遍同名卷，防止本次 detach 没真正卸干净影响下一个 DMG
    detach_stale_volumes "${DMG_VOLUME_NAME}"

    # 4. 转换为压缩只读 DMG
    echo "  压缩为最终 DMG..."
    hdiutil convert "${rw_path}" \
        -format UDZO \
        -imagekey zlib-level=9 \
        -o "${dmg_out}"

    local dmg_size
    dmg_size=$(du -sh "${dmg_out}" | cut -f1)
    echo "  DMG 大小: ${dmg_size}"
    echo ""
}

# ──────────────── 清理临时文件 ────────────────
cleanup() {
    echo "=== 清理临时文件 ==="
    rm -rf build_tmp
    rm -rf "${APP_NAME}-arm64.app" "${APP_NAME}-x86_64.app"
    echo ""
}

# ──────────────── 输出结果 ────────────────
print_result() {
    echo "============================================"
    echo "  构建完成!"
    echo "============================================"
    echo ""
    echo "  产物:"
    echo "    ${SCRIPT_DIR}/${APP_BUNDLE}                (universal .app)"
    echo "    ${SCRIPT_DIR}/${APP_NAME}-arm64.dmg     (Apple Silicon)"
    echo "    ${SCRIPT_DIR}/${APP_NAME}-x86_64.dmg    (Intel)"
    echo "    ${SCRIPT_DIR}/${ZIP_NAME}              (universal, 自动更新通道)"
    echo ""
    echo "  Release 上传：两个 dmg 给首装用户对架构挑选；zip 走自动更新流程，跨架构通吃。"
    echo ""
    echo "  安装方式:"
    echo "    1. 双击对应架构的 dmg（Apple Silicon 选 arm64；Intel 选 x86_64）"
    echo "    2. 将 ${APP_BUNDLE} 拖入 Applications 文件夹"
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

    # 三个 .app：单架构两份用于 dmg，universal 一份用于 zip
    local arm_app="${APP_NAME}-arm64.app"
    local x64_app="${APP_NAME}-x86_64.app"

    build_app_bundle "${BUILD_DIR}/${APP_NAME}-arm64"     "${arm_app}"
    build_app_bundle "${BUILD_DIR}/${APP_NAME}-x86_64"    "${x64_app}"
    build_app_bundle "${BUILD_DIR}/${APP_NAME}-universal" "${APP_BUNDLE}"

    create_zip
    notarize_artifact "${APP_BUNDLE}"

    create_dmg_for_app "${arm_app}" "${APP_NAME}-arm64.dmg"
    create_dmg_for_app "${x64_app}" "${APP_NAME}-x86_64.dmg"

    notarize_artifact "${APP_NAME}-arm64.dmg"
    notarize_artifact "${APP_NAME}-x86_64.dmg"

    cleanup
    print_result
}

main "$@"
