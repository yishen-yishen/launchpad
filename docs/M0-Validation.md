# M0 技术验证

2026-11-06：Mac mini arm64，macOS 26.6.2 (25G83)。启动时仅 CLT，随后系统提供 Xcode 27.2 (27B52)。没有改动系统许可或安装开发工具。

实际执行：Swift 编译、Xcode Debug App 构建、逻辑测试；尚未通过 GUI 检查窗口。编译成功只证明所用 SDK 接受接口，不证明系统体验。

| 项目 | 实现与可执行验证 | 状态 |
|---|---|---|
| 覆盖窗口 | borderless nonactivating NSPanel，canJoinAllSpaces / canJoinAllApplications / fullScreenAuxiliary，statusBar level。打开 App，Esc 隐藏，Dock 再打开 | 待交互验证 |
| 双屏安全区 | 鼠标全局坐标选屏，屏幕变化重设 frame；双屏不同缩放并拔屏，检查刘海和内容 | 待真机验证；安全区尚需改进 |
| Space / Stage Manager | 独立原生全屏 helper 已实测 3 次显示/搜索/隐藏，保持 Space 与前台应用；分别手测 Chrome/Safari 视频与 Stage Manager。禁止强切 Space | 原生 helper 通过；浏览器视频、Stage Manager、多屏待人工验证 |
| 中文 IME | NSSearchField，marked text 时不消费命令；候选中 Enter/Esc/左右键 | 待人工输入法验证 |
| 快捷键 | RegisterEventHotKey，仅指定组合；设置可录制，注册失败保留旧值 | SDK 编译通过，冲突/释放待测 |
| 启动 | NSWorkspace.openApplication 确切 URL；分别测缺失、已运行、正常 App | 未实际启动用户应用 |
| 登录 | SMAppService.mainApp，启动 Apple event 判断登录标记 | 待重登录验证；如事件不足改 helper，不用延时 |
| 材质 | NSVisualEffectView，不截图；切换浅深色/降低透明度 | 待目视/辅助功能检查 |

在普通桌面不能覆盖时使用 Dock 和菜单栏入口。2026-11-12：独立全屏原生 helper 覆盖回归通过；不能将其等同于 Chrome 视频、DRM 或所有全屏应用均支持。
