# 0004：在当前全屏 Space 使用非激活面板

2026-11-12。

旧启动器是普通 NSWindow，显示时激活 LaunchDock，可能让系统切回该应用所在桌面。改用创建时带 nonactivatingPanel 的 NSPanel；允许 key 和搜索输入，不成为 main window。使用 canJoinAllSpaces、canJoinAllApplications、fullScreenAuxiliary 组合及 transient/ignoresCycle，statusBar 层级覆盖菜单栏；移除 moveToActiveSpace 和显示入口的 NSApp.activate/unhide。设置窗口仍按用户操作正常激活。

用户切换 Space 或面板失去 key 时关闭启动器。不调用私有 Space 接口，不创建启动器自己的全屏 Space，也不隐藏其他应用。

验证使用经 Launch Services 启动的独立测试 App 和原生全屏 helper。要求 helper 已收到 didEnterFullScreen、仍在 active Space 且为 frontmost，才开始测试；连续三次显示/搜索/隐藏，逐次采样 frontmost、isOnActiveSpace、key 与搜索值。2026-11-12 本机 macOS26.6.2 实测通过。裸 CLI 驱动曾因前台仍是 Codex 使前置条件超时，不计为产品失败或成功。

Chrome 全屏视频、DRM、Stage Manager、多显示器独立 Space 仍需人工验收；以上 flags 与原生 helper 通过不能替代这些结论。保持系统允许的行为，不强制切换用户 Space。
