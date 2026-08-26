# VolX

一个本地 macOS 菜单栏小工具，用来统一控制多个输出设备的音量。

## 下载

从 [GitHub Releases](https://github.com/tpxcer/VolX/releases/latest) 下载：

- `VolX-0.3.4-arm64.dmg`：磁盘映像安装包。
- `VolX-0.3.4-arm64.zip`：压缩版 App。

当前安装包为 Apple 芯片 `arm64` 版本，要求 macOS 14 或更高版本。App 使用 ad-hoc 临时签名，尚未使用 Developer ID 签名或通过 Apple 公证；首次打开时可能需要在 Finder 中右键 VolX 并选择“打开”。

当前目标设备：

- `BenQ MA270UP`：通过 `m1ddc` 走 DDC/CI 控制显示器内部音量。
- `CX31993 384Khz HIFI AUDIO`：通过 CoreAudio 控制 USB 声卡音量。
- `显示器+音箱`：如果系统已有这个多输出设备，App 会在双输出模式下把它设为默认输出。

## 功能

- `F10`：静音/取消静音。
- `F11`：统一减小音量。
- `F12`：统一增大音量。
- 点击菜单栏 VolX 图标：弹出原生玻璃材质的声音面板、设备选择和音量滑块；面板左边缘与图标左边缘对齐。
- 拖动音量滑块时，滑块会展开为约 `28 x 22` 点的透明 Liquid Glass 椭圆，内部能透出蓝色和灰色轨道；松开后恢复 16 点白色圆点。
- 点击面板滑块左侧的喇叭：静音或取消静音，且不会再额外弹出 HUD。
- 点单个设备会切换到该输出，点 `显示器 + 音箱` 会恢复双输出。
- 切换单个设备或组合输出时不显示音量 HUD，面板保持原位。
- 在 macOS 系统面板切换本机输出后，VolX 会在约 0.5 秒内同步选中状态和控制目标。
- 自动发现同一网络中的 AirPlay 扬声器；点击远程设备会打开系统声音设置，由 macOS 完成全局输出切换。
- 使用快捷键调节音量或静音时：只显示一个紧凑的 macOS 风格玻璃 HUD，HUD 左边缘与菜单栏 VolX 图标左边缘对齐。
- 使用 F11/F12 调节音量时播放 macOS 原生音量反馈音，并遵循系统的“更改音量时播放反馈”开关；面板滑块在松开时播放一次。
- 首次打开辅助功能权限后，App 会自动建立独占按键拦截，不需要再次退出重开。
- 菜单栏使用原创 VolX 图标的白色单色轮廓，App 使用完整彩色双路音频图标。
- 右键点击菜单栏图标可以开启或关闭登录时启动，也可以退出 VolX。

## 构建

```bash
scripts/build-app.sh
open .build/VolX.app
```

Release 优化构建：

```bash
CONFIGURATION=release scripts/build-app.sh
```

## 安装到应用程序

```bash
scripts/install-app.sh
open /Applications/VolX.app
```

## 验证命令

一键体检：

```bash
scripts/doctor.sh
```

完整手动验证：

```bash
swift build
.build/debug/MultiOutputVolume --check-devices
.build/debug/MultiOutputVolume --doctor
.build/debug/MultiOutputVolume --activate-aggregate
.build/debug/MultiOutputVolume --select-preferred-group
.build/debug/MultiOutputVolume --select-output CX31993
.build/debug/MultiOutputVolume --apply-default-volume
.build/debug/MultiOutputVolume --volume-up
.build/debug/MultiOutputVolume --volume-down
.build/debug/MultiOutputVolume --toggle-mute
.build/debug/MultiOutputVolume --check-permissions
.build/debug/MultiOutputVolume --check-airplay
.build/debug/MultiOutputVolume --check-hotkeys
.build/debug/MultiOutputVolume --check-interface
.build/debug/MultiOutputVolume --self-test-hotkeys
.build/debug/MultiOutputVolume --observe-hotkeys 10
.build/debug/MultiOutputVolume --hotkey-log
```

`--check-hotkeys` 输出里：

- `accessibilityTrusted=true` 表示辅助功能权限已通过。
- `eventTapCreated=true` 表示底层按键监听已创建。
- `globalMonitorCreated=true` 表示全局媒体键监听兜底已创建。
- `carbonRegisteredIDs=[10, 11, 12]` 表示 F10、F11、F12 注册成功。

`--self-test-hotkeys` 会直接走 App 内部的热键处理链路，触发一次增大和一次减小，用来区分“热键没有收到”和“收到后音量处理失败”。物理键是否被系统送到 App，仍以真实按下 `F10/F11/F12` 后的 HUD 和日志为准。

本地构建使用临时签名。更新安装版后，如果快捷键只出现系统原生提示，请在“系统设置 -> 隐私与安全性 -> 辅助功能”里把 `VolX` 关闭再打开一次；App 会自动建立独占拦截，不需要退出重开。

`--doctor` 会一次性检查默认输出、多输出设备、目标设备、DDC 后端、音量写入和热键监听注册，最后输出 `DOCTOR_RESULT=PASS` 或 `DOCTOR_RESULT=FAIL`。`--check-interface` 会检查 HUD/面板尺寸、原生玻璃层和单 HUD 策略，最后输出 `INTERFACE_RESULT=PASS` 或 `INTERFACE_RESULT=FAIL`。`--check-airplay` 会扫描 5 秒并列出 VolX 实际发现的 AirPlay 设备。

`--observe-hotkeys 10` 会监听 10 秒并打印原始键盘事件，最后的数字可以改成 `30`、`60`，最多 120 秒。运行后马上按 `F10/F11/F12`，如果有 `source=... action=increase/decrease/mute`，说明系统已把按键送到 App；如果 `observedRawEvents=0`，问题在 macOS 权限、键盘设置或按键没有作为 F10/F11/F12 发出。

## 依赖

BenQ 显示器控制依赖 `m1ddc`：

```bash
brew install m1ddc
```

如果缺少 `m1ddc`，App 仍可控制 CoreAudio 支持的设备，但不能直接写入 BenQ 显示器音量。

## 权限

首次运行后，如果 `F10/F11/F12` 没有反应，请到：

`系统设置 -> 隐私与安全性 -> 辅助功能`

允许 `VolX`。部分系统还会要求在“输入监控”里允许。

首次启用 AirPlay 发现时，macOS 还会询问是否允许 VolX 查找本地网络设备。点“允许”后，无线扬声器才会显示在 VolX 面板中。

## 已知限制

- `BenQ MA270UP` 的 CoreAudio 音量属性不可写，本工具通过 DDC/CI 写显示器音量。
- 这台 BenQ 的 DDC `get volume` 读回偶尔会返回 `0`，所以 App 的界面以内部统一音量为准；写入命令返回成功后通常会实际改变显示器音量。
- BenQ 静音不用 DDC mute 命令，因为实测 `m1ddc set mute off` 会让该显示器音量读回异常；本工具用“音量设 0 / 恢复音量”模拟静音。
- macOS 没有向第三方应用公开全局 AirPlay 输出的直接切换接口；VolX 可发现并显示远程扬声器，点击后交给系统声音设置完成真实路由。

## 许可证

MIT License。详见 `LICENSE`。
