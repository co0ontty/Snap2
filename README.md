# Snap²

一款简洁、可爱的 macOS 截图与标注工具。命名灵感来自我家加菲猫"初二"——`²` 既是上标 2，也是初二的"二"。

> 区域截图 → 实时标注 → 一键复制 / 保存

## 功能

- 区域截图（默认快捷键 `Ctrl + Shift + A`，可在设置中自定义）
- 标注工具：箭头、矩形、椭圆、自由画、文字、高亮
- 回车键：复制到剪贴板 或 保存到指定目录（可在设置中切换）
- 菜单栏常驻，开机自启动可选
- 纯 Swift + AppKit，无外部依赖

## 系统要求

- macOS 14 (Sonoma) 或更高版本
- Apple Silicon

## 安装

从 [Releases](https://github.com/co0ontty/Snap2/releases) 下载最新 `Snap2.dmg`，挂载后将 `Snap2.app` 拖入 `Applications`。

### 首次启动：绕过「无法验证开发者」提示

由于尚未使用 Apple Developer ID 签名 + 公证，首次打开会出现「Apple 无法验证 Snap2 是否包含恶意软件」的安全提示。按以下步骤放行：

1. 双击 `Snap2.app` —— 系统会拦下并显示警告
2. 打开「系统设置 → 隐私与安全性」
3. 滚到底部找到「Snap2 已被阻止」一条，点击右侧的「仍要打开」
4. 在弹出的二次确认中再点「打开」

> macOS 15 (Sequoia) 起，旧的 Finder「右键 → 打开」绕过路径已经收紧，必须走「系统设置」一次。完成一次后，后续启动不会再提示。

### 屏幕录制权限

首次启动后，需要在「系统设置 → 隐私与安全性 → 屏幕录制」中勾选 Snap²。

> ⚠️ 由于使用的是 ad-hoc 签名，每次升级版本后系统会把新版本视为不同 app，**屏幕录制权限需要重新授予**。这是 macOS TCC 的设计：跨版本保留权限需要 Apple Developer ID 证书签名 + 公证。

## 从源码构建

```bash
# 仅构建二进制
make build

# 构建完整 .app（含图标）
make app

# 构建并打包为 DMG
./build_dmg.sh
```

构建依赖：Xcode Command Line Tools、Python 3 + Pillow（用于生成图标）。

## 发布流程

打 tag 即触发 GitHub Actions 自动构建并发布到 Release：

```bash
git tag v1.0.0
git push origin v1.0.0
```

## 许可

MIT
