# 用户指令记忆

本文件记录了用户的指令、偏好和教导，用于在未来的交互中提供参考。

## 格式

### 用户指令条目
用户指令条目应遵循以下格式：

[用户指令摘要]
- Date: [YYYY-MM-DD]
- Context: [提及的场景或时间]
- Instructions:
  - [用户教导或指示的内容，逐行描述]

### 项目知识条目
Agent 在任务执行过程中发现的条目应遵循以下格式：

[项目知识摘要]
- Date: [YYYY-MM-DD]
- Context: Agent 在执行 [具体任务描述] 时发现
- Category: [运维部署|构建方法|测试方法|排错调试|工作流协作|环境配置]
- Instructions:
  - [具体的知识点，逐行描述]

## 去重策略
- 添加新条目前，检查是否存在相似或相同的指令
- 若发现重复，跳过新条目或与已有条目合并
- 合并时，更新上下文或日期信息
- 这有助于避免冗余条目，保持记忆文件整洁

## 条目

[Swift 工具链与 SDK 匹配]
- Date: 2026-08-15
- Context: Agent 在执行界面扁平化重构与构建验证时发现（更正 2026-05-30 的旧记录）
- Category: 构建方法
- Instructions:
  - 本机 swift 工具链可用（Xcode 6.3.3，`swift build` 直接可用）。旧记录"无 swift 命令"已过时。
  - `xcrun --show-sdk-path` 会解析到 CommandLineTools 的 SDK（Swift 6.4 构建），与 PATH 里的 Xcode 6.3.3 编译器不匹配，直接 `make app` 报 "this SDK is not supported by the compiler"。
  - Makefile 已内置错配防护（编译器来自 Xcode 且 SDK 落在 CLT 时自动切 Xcode 平台 SDK）；必要时也可显式 `make app SDK=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk`。
  - HUD 界面验证不需要模拟鼠标：`./build_output/Snap2 --demo-annotating` 直接进入标注模式；`--demo-capture` / `--demo-recording` 走热键同款通知路径。截图用 `screencapture -x`。
