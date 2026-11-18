# BuhoLaunchpad免录屏权限背景研究

日期：2026-11-12。对象：用户指定的/Applications/BuhoLaunchpad.app，版本2.0.2。只读检查，没有启动、注入、修改该应用或绕过其许可，也未修改/构建LaunchDock。静态线索不能替代对当前显示路径的动态验证。

## 官网与公开系统说明

官网介绍背景图片/模糊等能力，但未披露实现：https://www.drbuho.com/buholaunchpad 。

Apple WWDC19 Advances in macOS Security明确介绍：桌面背景图像（不包括桌面图标）、菜单栏和应用自身窗口，是旧CGWindowListCreateImage屏幕权限规则中的例外；按窗口层级而非窗口名称查找背景windowID可不依赖录屏批准。该说明是Catalina时代的设计说明，不等于保证每个新系统/新SDK行为完全相同。
https://developer.apple.com/videos/play/wwdc2019/701/ （Transcript约231—244行、视频约14分钟）。

当前Xcode SDK27.2 CGWindow.h将CGWindowListCreateImage标为SCREEN_CAPTURE_OBSOLETE(10.5,14.0,15.0)，不能当作现代macOS26 Swift项目中的普通可用API直接调用。Apple macOS15发行说明还提示旧捕获API可能触发系统提示：https://developer.apple.com/documentation/macos-release-notes/macos-15-release-notes 。

## 本地静态证据

主要逻辑位于Contents/MacOS/BuhoLaunchpadServer.app/Contents/MacOS/BuhoLaunchpadServer，外层BuhoLaunchpad是另一个可执行文件。

确认存在：

- desktopImageURLForScreen:、WallpaperState、systemWallpaper、wallpaperChanged。
- 文件解码调用CGImageSourceCreateWithURL、CGImageSourceGetPrimaryImageIndex、CGImageSourceCreateThumbnailAtIndex。
- 窗口元数据调用CGWindowListCopyWindowInfo及kCGWindowLayer/kCGWindowBounds。
- 图像捕获调用CGWindowListCreateImage；Server还弱链接私有SkyLight及CGSHWCaptureWindowList、CGSMainConnectionID。
- 未在该Server的依赖中看到ScreenCaptureKit；这不是“绝无动态加载”的证明。

arm64调用点（用于复核，不复制整段程序）：

- 0x10007420c起检查系统版本27.0.0；27分支0x100074228调用0x10000208c兼容包装，该包装0x1000020d4实际调用CGSHWCaptureWindowList。较旧系统分支0x1000744fc实际调用CGWindowListCreateImage，使用includingWindow选项和windowID。
- 0x1000761b4调用窗口查找函数0x10015cb6c；随后的分支具有NSWorkspace/desktopImageURLForScreen:文件回退线索。
- 窗口查找函数调用CGWindowListCopyWindowInfo，检查layer/bounds，含层级常数0xffffffff80000018（-2147483624）及目标屏幕点包含判断。不要把这个硬编码层级误称为所有系统统一的desktopWindow值。

因此其具备两类能力：读取壁纸文件、读取特定桌面窗口的图像；macOS27还有私有兼容捕获分支。与用户“未授予录屏也能显示背景”的现象相符，但未动态追踪用户当前那一次展示，不能精确声称走了哪条路径。

## DefaultDesktop.heic核实

系统路径不是无效图片：

/System/Library/CoreServices/DefaultDesktop.heic
→ /System/Library/Wallpapers/.default/DefaultAerial.heic

当前机器上文件可读，ImageIO返回count=1、primaryIndex=0，实际缩略图是太浩湖湖景。临时缩略图/tmp/launchdock-default-wallpaper-check.png已目视检查。这个事实不证明它匹配当前桌面动态帧，也不能因为名字有Default就一概判错。LaunchDock现有按此文件名拒绝加载的策略过于粗糙，应在后续实现选择时改为基于有效资源/实际匹配情况判断；本轮未修改运行代码。

## 对LaunchDock的结论

“读取当前背景必须使用ScreenCaptureKit和录屏权限”不成立。可以优先读取有效壁纸文件；兼容旧桌面背景window图像路径是另一个方向。后者在新SDK中涉及过时API，Buho本地实现还包含私有SkyLight分支，须作为兼容研究项单独评估，不能等同于稳定公开API方案。当前已授权LaunchDock包保持原样，未重编译/重签名/重置权限。
