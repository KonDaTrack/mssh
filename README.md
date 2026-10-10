# mssh — 手机上的远程开发台

**中文** · [English](README.en.md)

一个 Flutter 手机 App，把「VS Code Remote-SSH」精简到手机上：连你自己的一台台机器，看它们的
文件系统、预览文件、开终端跑命令——**终端里也能用手机输入法的语音说话**，所以你完全可以用嘴
去指挥远程机器上的 agent CLI。

组网交给 Tailscale，这个 App 只管 SSH。**目标机器零安装、零服务端**：手机自带 SSH 客户端
（`dartssh2`），直接连过去。

---

## 下载安装（Android）

从 [**Releases**](https://github.com/KonDaTrack/mssh/releases) 页面下载最新的 `mssh-*.apk`，
传到手机点击安装即可（首次需允许「安装未知来源应用」）。iOS 需要自己用 Xcode 构建，见下文。

> APK 用 debug 密钥签名（Flutter 模板默认），自用没问题；要上架请自行配置签名。

## 功能

- **主机管理**：添加 / 编辑 / 删除主机，密码或 PEM 私钥登录。私钥和密码存在系统安全存储
  （Android Keystore / iOS Keychain），不进明文。
- **文件浏览**：可展开折叠的目录树，懒加载；点文件在**右侧预览**——文本带行号、图片可缩放、
  二进制给十六进制。
- **上传 / 下载**（类 VS Code 侧边栏）：**长按文件** → 「下载到本机」，**长按目录** →
  「上传文件到此目录」/「下载此文件夹到本机」；预览页右上角也有下载按钮，顶栏有「上传到主目录」。
  带进度条。
- **Tailscale 联动**：添加主机时可**下拉选择 tailnet 里已上线的设备**，自动填入地址；
  没配 Key 或网络不通就手动填 IP。
- **终端**：多标签，每个标签一条独立 shell；新建终端时可填**启动命令**（比如 `claude`），
  连上就自动执行。
- **键盘 / 语音**：终端工具栏的「⌨ 键盘」按钮控制手机键盘的**弹起与收起**；用键盘自带的
  麦克风说话即可输入。软键盘敲不出的键（回车 / Esc / 方向键 / `^C` / 竖线等）也都在工具栏上。

## 界面结构

```
主机列表 ──点击某台主机──▶ 工作区
                            ├─ 文件：左树 | 右预览   （窄屏自动变成树↔预览切换）
                            └─ 终端：标签条 + xterm 终端 + 软键工具栏
```

- 宽屏（≥720dp，横屏 / 平板）文件页左右分栏；竖屏手机点文件后预览整屏、左上角返回。
- 终端底部工具栏：`esc tab ↑ ↓ ← → ^C ^D ^Z ^L / -` + 大号 `⌨ 键盘` 和 `⏎`。

## 键盘与语音输入

1. 进「终端」，点右下角 **⌨ 键盘** → 手机输入法弹出（再点一次即收起）。
2. 点输入法键盘上的**麦克风**，说话 → 识别成文字进入终端输入行。
3. 点工具栏 **⏎** 回车。

因为用的是系统输入法自己的语音，中文识别准确度、是否离线，都取决于你手机装的输入法
（Gboard / 讯飞 / 搜狗 / 微信键盘等都行）。跑 `claude` 这类 TUI 一样适用：说话等于打字，
回车等于提交。

## 上传 / 下载怎么用

- **下载**：长按文件 → 「下载到本机」；或点右侧预览页右上角的 ⬇。
  小于 64 MB 会直接弹系统「另存为」；更大的会流式落到临时文件再弹分享面板（可"保存到文件"，
  也可直接发给别的 App），避免把大文件读进内存。
- **上传**：长按目标**目录** → 「上传文件到此目录」；或点顶栏 ⬆ 上传到主目录。可多选。
- **下载文件夹**：长按目录 → 「下载此文件夹到本机」——会在远端打包（有 `zip` 用 `zip`，
  否则退回 `tar.gz`）后再下载，临时压缩包用完即删。
- 传输过程有进度条，完成后文件树只刷新对应目录，展开状态不变。

## Tailscale 下的用法

App 不关心你在不在内网——能 SSH 到就行。Tailscale 开着时，**主机名直接填机器的 MagicDNS 名**
（例如 `my-desktop` 或 `my-desktop.tailnet-xxxx.ts.net`），手机在同一个 tailnet 里就能直连，
不用记 IP。

**自动列出在线设备**：在「添加主机」页可以下拉选择 tailnet 里已上线的设备，自动填入地址。
手机端读不到本机 `tailscaled`（Tailscale App 不对外暴露），所以这需要一把 Tailscale
**API Key**（后台 Settings → Keys → Generate access token，只读 devices 权限即可），
填一次存在系统安全存储里。不配置也没关系——手动填主机名 / IP 一样用；Key 失效或网络不通时
会自动回退到手动输入。

## 构建与安装

前置：Flutter SDK（3.29+，本仓库在 3.47.7 上验证）、Android SDK / Xcode。

国内网络下拉依赖建议挂镜像：

```bash
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
```

### Android

```bash
flutter pub get
flutter build apk --release
# 产物：build/app/outputs/flutter-apk/app-release.apk
adb install build/app/outputs/flutter-apk/app-release.apk   # 或拷到手机点安装
```

> 默认 release 用 debug 密钥签名（Flutter 模板行为），自己用完全够。要上架再配
> `android/app/build.gradle.kts` 的 `signingConfigs`。

### iOS

需要 macOS + Xcode：

```bash
flutter build ios --release
# 再用 Xcode 打开 ios/Runner.xcworkspace 做签名、装到手机（个人免费证书即可）
```

### 开发调试

```bash
flutter run        # 连着的设备上热重载
flutter analyze    # 静态检查
flutter test       # 单测 + 编译冒烟
```

## 代码结构

```
lib/
├── main.dart                 入口：挂 HostStore，起 App
├── app.dart                  MaterialApp + 主题
├── theme.dart                深色 UI 主题
├── terminal_theme.dart       xterm 调色板
├── models/                   host / credential / remote_entry
├── services/
│   ├── host_store.dart       主机持久化（元数据 SharedPreferences，密钥安全存储）
│   ├── ssh_service.dart      SSHClient 封装：连接、shell+PTY、exec、SFTP
│   └── file_service.dart     SFTP 封装：列目录、限长读文件
├── screens/                  hosts / host_edit / workspace
├── widgets/                  file_tree / file_preview / terminal_pane
└── util/format.dart          路径拼接、大小/时间格式化、图标
```

## 依赖

| 包 | 用途 |
|----|------|
| [`dartssh2`](https://pub.dev/packages/dartssh2) | 纯 Dart 的 SSH2 客户端（连接 / shell / SFTP） |
| [`xterm`](https://pub.dev/packages/xterm) | Flutter 终端模拟器 |
| `flutter_secure_storage` | 密码 / 私钥的安全存储 |
| `shared_preferences` | 主机列表持久化 |
| `provider` | 状态管理 |

## 安全说明

- 密码与私钥**只**写进系统安全存储，主机列表里不含机密。
- 私钥仅在本机解析用于认证，不外传。
- 目前**不校验服务器 host key**（方便首次连接）。要更严可后续接 known-hosts 机制。

## 已知限制 / 路线图

- 还不能在远端**编辑 / 删除**文件（上传、下载已支持）。
- 未做服务器指纹校验（见上）。
- 未内置本地语音识别——刻意如此，直接用系统输入法最省事、中文也最准。
