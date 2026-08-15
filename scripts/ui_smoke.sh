#!/bin/bash
# UI 截图冒烟：构建 → 依次截「设置窗 / 欢迎窗 / 标注 HUD」三张图并归档。
# 依赖 --demo-annotating 调试参数（见 AppDelegate）。
#
# 用法：scripts/ui_smoke.sh [输出目录]
#      输出默认在 build_output/ui_smoke/<时间戳>/，直接用图片查看器翻看即可。
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-build_output/ui_smoke/$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUT"

# 记住用户原本的引导标记，跑完恢复，不污染状态
ORIG_ONBOARDING=$(defaults read com.chuer.snap2 hasCompletedOnboarding 2>/dev/null || echo 1)
restore() {
    defaults write com.chuer.snap2 hasCompletedOnboarding -bool "$([ "$ORIG_ONBOARDING" = "1" ] && echo true || echo false)"
    pkill -x Snap2 2>/dev/null || true
}
trap restore EXIT

kill_app() { pkill -x Snap2 2>/dev/null || true; sleep 1; }

echo "[1/4] 构建..."
make app >/dev/null

echo "[2/4] 设置窗..."
kill_app
defaults write com.chuer.snap2 hasCompletedOnboarding -bool true
open Snap2.app
sleep 2.5
screencapture -x "$OUT/settings.png"

echo "[3/4] 欢迎窗..."
kill_app
defaults write com.chuer.snap2 hasCompletedOnboarding -bool false
open Snap2.app
sleep 2.5
screencapture -x "$OUT/welcome.png"

echo "[4/4] 标注 HUD（demo）..."
kill_app
defaults write com.chuer.snap2 hasCompletedOnboarding -bool true
open Snap2.app --args --demo-annotating
sleep 3.5
screencapture -x "$OUT/annotation_hud.png"
kill_app

echo "完成：$OUT"
ls -l "$OUT"
