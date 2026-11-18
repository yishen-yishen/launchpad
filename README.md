# LaunchDock

Swift 6、SwiftUI、AppKit 原生 macOS 应用启动器，最低 macOS 26.0。当前是开发版本，尚未达到规范全部验收门槛；状态见 [进度](docs/Progress.md)。不使用 WebView，不上传数据，不要求额外隐私权限。

安装预览版：打开 `dist/LaunchDock-0.0.1-beta-universal.dmg`，将 LaunchDock 拖到 Applications。要求 macOS 26.0+，包含 Apple Silicon/Intel 两种架构，无需安装开发工具或第三方依赖。当前仅本地 ad-hoc 签名，未做 Developer ID 签名与 Apple 公证，首次打开可能需要在“隐私与安全性”中确认。详情见 [安装与发行](docs/Release.md)。重新打包：`sh scripts/package-release.sh`。

打开 `LaunchDock.xcodeproj`，选择共享 `LaunchDock` scheme。初始工程由仓库确定性脚本生成；改动生成器后执行 `python3 scripts/generate-project.py`。核心库作为本地 Swift package 依赖，无外部依赖。

```sh
xcodebuild -project LaunchDock.xcodeproj -scheme LaunchDock -destination 'platform=macOS,arch=arm64' -configuration Debug -derivedDataPath /tmp/launchdock-derived CODE_SIGNING_ALLOWED=NO build
swift test
swift run CoreChecks
```

构建后的本地应用位于 `/tmp/launchdock-derived/Build/Products/Debug/LaunchDock.app`。上述不签名的 Debug 构建用于开发；给他人的独立预览包使用下文打包脚本。共享 scheme 已接入原生逻辑测试 target，也可执行 `xcodebuild -project LaunchDock.xcodeproj -scheme LaunchDock -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO test`。UI 自动化尚未实现。

已验证工具链：Xcode 27.2 (27B52)，macOS 26.6.2 arm64；初始 CLT Swift 6.3.3 编译亦通过一次，但不包含 Testing 模块。Swift 语言模式为 6，部署目标 26.0。

数据：`~/Library/Application Support/app.launchdock.LaunchDock/` 内保存 `catalog.json`、`layout.json`、3 份布局备份和恢复保留文件。偏好当前使用 bundle 域 UserDefaults。调试重置前退出应用，将整个数据目录改名备份，随后重新打开。设置中“重置为字母顺序”会清除文件夹，执行前确认并保留备份。不要直接删除真实布局。

Dock 打开、菜单栏或 Option+Space 唤起；首次打开扫描本机标准目录。图标右键可在访达中显示；空白处右键可设置、重启或退出。直接拖动可排序、合并文件夹与拖出成员；拖出文件夹停留300ms自动回到主页面，松手前仅显示跟随鼠标的图标。设置可重新扫描、恢复隐藏、导入导出和配置登录启动。当前限制见 [Known-Limitations](docs/Known-Limitations.md)，发行步骤见 [Release](docs/Release.md)。

原生回归检查（先运行上述 Debug 构建）：`sh scripts/check-native.sh`。此检查打开独立测试窗口，验证全宽居中、直接拖拽整理与外层滚轮路由，不写用户布局。不要把合成事件检查替代真实拖动和多屏验收。

触发角：在“设置 → 通用”下拉选择一个角，默认关闭，不要求 Option。此功能为应用内配置，不向系统触发角菜单注入动作；如冲突，请关闭系统对应角。背景由应用独立绘制并模糊：普通图片优先读取壁纸文件，动态/代理资源通过桌面背景窗口专用兼容接口读取；每次打开刷新一次，显示期间固定。不使用 ScreenCaptureKit、不申请录屏权限，也不隐藏或恢复其他应用。读取不可用时回退到有效壁纸文件主图或纯色。macOS 27 的私有兼容分支尚待真机验证，接口变化时退回文件方案。

新版本按扫描根下实体目录建立初始启动器文件夹，并在后续扫描保留手动移出/改名；显示名跟随 Finder 文件显示名称。空白处横拖超过60pt后释放翻页，单击抬起才隐藏；整页滑动而非单图标动画。

当前 `sh scripts/check-native.sh` 默认执行聚焦交互检查，并要求完整结束标记。扩展生命周期模式 `LAUNCHDOCK_CHECK_LIFECYCLE=1 sh scripts/check-native.sh` 已通过本机原生回归；系统级触发角、浏览器视频全屏和多屏仍需单独验收。

2026-11-07：触发角为单选；启用时以30ms间隔读取指针状态，关闭后不运行检测计时器。独立定时回归：`sh scripts/check-hot-corner.sh`（先Debug构建）。应用标签已隐藏.app；可选名称字段与实值见 [App-Name-Options.md](docs/App-Name-Options.md)，原始数据见 App-Name-Values.json。

当前名称策略已按用户选择固定为A：真实应用文件名去.app。触发角后台唤起已用当前Mac左上角真实系统指针验证。Debug诊断在 `/tmp/launchdock-corner-<pid>.json`，仅记录状态与计数；Release不写该文件。启用触发角期间保持允许空闲睡眠的用户活动token，关闭后释放。

触发角最新规则：进入立即切换显示/隐藏，取消驻留等待，离开再进入才能再次触发。文件夹以独立浮层呈现，根网格保留同一实例和独立分页容量。

本地开发包可使用 `sh scripts/build-dev.sh` 构建，输出仓库下 `build/Development/LaunchDock.app`（当前绝对路径 `/Users/yishen/project/launchpad/build/Development/LaunchDock.app`）。不要从 `/tmp` 运行需要隐私授权的开发包：该位置的应用可能无法由 Launch Services 按 Bundle ID 解析。脚本对整个 App bundle 做本地 ad-hoc 签名并校验，绑定 Info.plist 与资源，并注册和验证应用路径；不使用 Developer ID、不公证。当前版本无需录屏授权；本地 ad-hoc 签名不等于 Developer ID 发行签名。

免录屏壁纸验证：`sh scripts/check-wallpaper-no-permission.sh` 会创建全新 Bundle ID 的独立测试 App，通过 Launch Services 启动，断言其录屏预检为false且读到非黑色桌面背景。验证图片和数值保存在脚本打印的临时目录，仅用于检查壁纸，不包含普通应用窗口。

0.0.1-beta：通用页提供隐藏菜单栏图标、隐藏 Dock 图标，以及单选触发角下拉菜单；移除 Option 限制与测试入口。外观跟随系统，不再提供独立浅深色选项。打开文件夹后点击顶部标题即可改名，Enter 保存、Esc 取消，布局会持久化。

2026-11-13 开发版：点击应用先显示图标放大反馈，随后隐藏启动器，应用启动不再阻塞关闭。图标使用版本化磁盘缓存，首次建立后跨启动复用；后台检查包/图标资源变化并热更新，不在格子渲染时同步读取系统图标。此轮尚未更新 dist 中的0.0.1-beta安装包。
