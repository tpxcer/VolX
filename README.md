# VolX 0.3.6-fixed.1（源码修复版）

针对 Mac 内置扬声器与 External Headphones 的 CoreAudio 音量控制修复。
基于上游 `23415069cd2e3198212185553686cd3440873f88`；不是上游官方二进制发行版。

**交付的是源码，不是已验证的 Mac 安装包。** 已在 Linux 使用真实 Swift 6.1.3 编译运行共享业务核心测试；没有 macOS SDK 类型检查、Mac 应用构建或硬件验收。不能将语法检查当成 Mac 编译通过。

## 一条命令构建并安装

要求：macOS 14+；完整 Xcode 26+（现有玻璃 UI 引用 macOS 26 SDK；低版本运行时使用旧材质），且 `xcrun --sdk macosx --show-sdk-version` 显示 26 或更新。使用本机架构构建，无第三方 Swift 包依赖。

解压源码并在目录内执行：

```bash
bash scripts/install-app.sh
```

该命令先执行便携测试和 Mac XCTest，再 release 构建、ad-hoc 签名，安装到 `~/Applications/VolX.app`，**不使用 sudo**。请先退出旧版。已有安装会保留带时间戳的备份；不会替换 `/Applications` 内的旧版，请勿同时运行两份。

```bash
open "$HOME/Applications/VolX.app"
```

没有 Developer ID 签名或 Apple 公证。Gatekeeper 拦截时请只对自己审核并构建的应用使用 Finder「打开」或系统设置中的「仍要打开」；不要关闭全局安全检查。辅助功能授权可能需要删除旧条目并重新添加新路径。

## 修复行为

- 启动、刷新、切换输出只读取实际音量与硬件静音，不回放旧的音量/静音设置。
- 每台设备独立记录静音前音量，按 UID 持久保存；仅明确取消静音时恢复。硬件已有正音量优先于旧恢复值。
- 写入后逐通道读回；任一失败都不宣称全部成功。面板可滚动状态文本和 HUD 列出未确认的设备。多输出保留所有声明成员；枚举缺失的成员视为未知并以 UID 报告未确认，不误报全部静音。
- 取消静音先写入目标音量，确认后才解除硬件静音，避免突然恢复到未知大音量。
- 仅拦截原生 NX 音量媒体事件；普通 F10/F11/F12、其他按键和 Shift/Control/Option/Command 组合交给系统。不注册 Carbon F 键，不使用会重复写入的全局监听兜底。
- 没有权限时不拦截；系统原生音量处理仍可用。授权后会重试建立 event tap。没有普通键码日志。
- **DDC 完全禁用**：不调用 m1ddc/ddcctl、不猜测显示器映射；不要为本版安装这些工具。
- Bonjour 默认关闭。只有显式设置 `enableBonjourDiscovery` 或执行 `--check-airplay` 才扫描局域网。
- 默认输出及系统提示音输出都写入并读回成功才报告完整切换；部分切换明确提示。

## 权限与原生音量键

「系统设置 → 隐私与安全性 → 辅助功能」允许当前安装路径的 VolX；若 macOS 要求输入监控也需允许。键盘设置若将顶排当作普通 F 键，请使用能产生原生音量事件的 Fn 组合。普通 F 键故意不接管。

## 自动测试

```bash
bash scripts/test-portable.sh          # Linux/macOS；直接编译应用真实 SafeVolumeCore.swift 和 AudioDevice.swift
swift test                             # 仅 Mac：VolumeModel fake-store 集成及 NSEvent 事件测试
swiftc -frontend -parse Sources/MultiOutputVolume/*.swift Tests/Mac/*.swift
```

`SWIFTC=/path/to/swiftc bash scripts/test-portable.sh` 可选择工具链。39 项便携检查覆盖声明成员枚举缺失、实际状态观察、部分静音失败、独立恢复、持久恢复、通道部分写入、读回不一致、媒体键筛选、重复静音、部分输出切换。Mac 测试尚未在本次环境执行。

只读设备检查：

```bash
"$HOME/Applications/VolX.app/Contents/MacOS/MultiOutputVolume" --check-devices
```

`--observe-hotkeys 10` 只输出识别出的音量动作，但会暂时消费音量键，不调节硬件；不要与正常 VolX 同时运行。旧版 `--doctor` 在本修复版改为只读设备/权限报告。`--volume-up`、`--volume-down`、`--toggle-mute` 和输出切换命令仍会改变声音；不要把它们当只读诊断。

## Mac 验收（尚未执行）

先降低音量，逐项检查：

1. 系统先静音再启动 VolX，不能解除静音；重启也不能改变硬件音量。
2. 内置扬声器、External Headphones 分别操作增减、静音、恢复；与系统设置读数及实际声音一致。
3. 连按/长按音量键每次只处理一次；长按静音不能反复切换；普通及组合 F 键不被拦截。
4. 在系统中切换输出、插拔耳机、睡眠唤醒后再按键，控制当前输出，不写旧设备。
5. 多输出如需同时播放，必须由「音频 MIDI 设置」创建真实多输出设备；本工具不创建音频路由。不同 Mac 的内置扬声器与耳机接口可能互斥，不能保证同时输出。
6. 多设备中断开/禁用某一成员，确认失败设备可见且不错误报告全部静音。
7. 静音后退出并重开，取消静音恢复每台设备自己的原始音量。

限制：CoreAudio 不支持或无法读回的设备会显示未确认；不支持显示器 DDC 或仅有逐通道硬件静音的设备。立即读回可能对延迟更新的驱动保守报告失败。尚无物理 Mac 验证。

## 许可证

MIT；保留上游版权，见 `LICENSE`。
