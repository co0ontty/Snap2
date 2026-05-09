# 自签名证书签名指南

为什么要用自签名证书：ad-hoc 签名（`codesign --sign -`）的"身份"由二进制 cdhash 推导得到，重新编译就会变。
macOS TCC 会因此把每次升级都当成"新 app"，强制用户重新授予屏幕录制等权限。
配上一张稳定的自签名 Code Signing 证书后，TCC 用证书指纹 + Bundle ID 作为身份，跨版本权限就能保留。

> 注意：自签证书解决不了 Gatekeeper 警告（"无法验证开发者"）。要彻底干净，仍需要 Apple Developer ID + notarization。

## 一次性准备

### 1. 在本机创建自签名 Code Signing 证书

通过 GUI（**推荐**）：

1. 打开 **Keychain Access** → 菜单栏 `Keychain Access` → `Certificate Assistant` → `Create a Certificate...`
2. 字段填写：
   - **Name**: `Snap2 Self Sign`（这个值就是后面要用的 `SELF_SIGN_IDENTITY`，记住）
   - **Identity Type**: `Self Signed Root`
   - **Certificate Type**: `Code Signing`
   - 勾选 **Let me override defaults**
3. 一直点 Continue，期间可以把 **Validity Period (days)** 改成 `3650`（10 年），免得到期又得换。
4. 完成后能在 `login` keychain 里看到一张同名证书。

> 也可以用命令行 + openssl 走 PKCS#12 流程，但 GUI 最简单，一次性的事。

### 2. 验证证书可用于 codesign

```bash
security find-identity -v -p codesigning
# 输出里应当能看到一行带有 "Snap2 Self Sign" 的 identity
```

### 3. 导出为 .p12（CI 要用）

1. Keychain Access 里找到这张证书，**展开**它（左侧三角），能看到下方挂着私钥。
2. 选中**证书 + 私钥两条**（Cmd 多选）→ 右键 → `Export 2 items...`
3. 文件格式 `Personal Information Exchange (.p12)`，保存到 `~/Snap2-SelfSign.p12`
4. 设一个导出密码（这个密码后面要放进 GitHub secret `SELF_SIGN_P12_PASSWORD`）
5. 系统可能再要求输入登录 keychain 密码，输一下放行

> **务必**也把 .p12 + 导出密码备份到密码管理器或冷存储。证书丢了就要重新签发，所有用户都要重授权一次。

### 4. 把 .p12 编码成 base64 文本

```bash
base64 -i ~/Snap2-SelfSign.p12 -o ~/Snap2-SelfSign.p12.base64
# 内容会成为 GitHub secret SELF_SIGN_P12_BASE64
```

### 5. 配置 GitHub repo secrets

仓库 → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**，依次新建：

| Secret 名 | 值 |
|---|---|
| `SELF_SIGN_P12_BASE64` | `~/Snap2-SelfSign.p12.base64` 文件**全部内容** |
| `SELF_SIGN_P12_PASSWORD` | 步骤 3 里设的导出密码 |
| `SELF_SIGN_IDENTITY` | `Snap2 Self Sign`（和证书 Common Name 严格一致） |

配完后下次打 tag 的 release 流就会自动用这套证书签 .app；CI 日志里会打印 designated requirement，每次发版前对一眼指纹是否一致即可。

## 本地构建也要走自签

```bash
export SELF_SIGN_IDENTITY="Snap2 Self Sign"
./build_dmg.sh
```

`build_dmg.sh` 会自动从 login keychain 找这张证书。

## 验证签名是否稳定

签完包后可以查看 designated requirement，多次构建之间这一行应当**完全一致**：

```bash
codesign -d --requirements - Snap2.app
# 期望输出形如：
# designated => identifier "com.chuer.snap2" and certificate leaf = H"AABB...CCDD"
```

只要 `H"..."` 那段证书指纹不变，TCC 就会认。

## 切换到自签后用户的体感

| 场景 | 体验 |
|---|---|
| 新用户首装 | Gatekeeper 拦截一次（"系统设置 > 仍要打开"），然后授屏幕录制权限一次 |
| 从 ad-hoc 旧版升级到自签新版 | 仍会被 TCC 当作新 app，需要重授权屏幕录制**一次** |
| 自签版本之间互升（v1.5.5 → v1.5.6 …） | 屏幕录制权限保留 ✅ |

## 想撤回到 ad-hoc

直接把仓库里 3 个 secret 删掉即可，CI 会自动回退到 ad-hoc 路径，构建流不会失败。
