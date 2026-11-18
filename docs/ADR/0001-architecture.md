# ADR 0001：平台、身份与存储

状态：采用开发实现，系统体验待验证。

窗口用单个 NSWindow/NSHostingView，NSCollectionView 负责网格。floating 层级避免覆盖系统安全界面；moveToActiveSpace/fullScreenAuxiliary 不作为全屏兼容性证据。Dock reopen 只显示，快捷键和菜单栏切换。

身份：优先卷 NSNumber + fileResourceIdentifier NSData 编码；不支持的资源标识不强转字符串，回退到 canonical path + bundle ID。唯一 bundle ID 且旧位置实际消失时才重定位。公开资源身份的移动/更新稳定性仍待实验。目录递归遇 .app 停止；解析链接并限制在扫描根内；失败路径旧记录保留。

全局快捷键：Carbon RegisterEventHotKey，主线程隔离。只处理所注册组合，不安装输入事件 tap。注册成功后才注销旧键；设置录制键只接收本控件焦点事件。实际系统抢占需手测。

登录启动：先采用 SMAppService.mainApp + Apple event 登录标记。该选择尚未通过真实登录实验，必要时替换独立 helper；未宣称 FR-001/AC-14 已完成。

持久化：schemaVersion=1 JSON，ISO8601 日期，稳定键排序；actor 串行保存，revision 防旧写覆盖，300 ms 防抖，同目录 Data.atomic 写入，三个有效版本备份。损坏布局保留并回退备份；无有效备份/高版本只读。未定义虚构旧格式，因此暂无迁移函数。偏好临时采用系统 UserDefaults，偏离规范 preferences.json，后续需要显式版本化。catalog/layout 跨文件不是原子事务，启动 reconcile 恢复。

测试：标准 Swift Testing + 独立 CoreChecks，后者用于无 Testing 的 CLT 环境。Xcode scheme 包含 App build/run/archive 和独立逻辑测试 target；另可 swift test。UI target 尚未实现。

2026-11-06 用户修订背景行为：改用系统公开桌面壁纸 URL 渲染，避免背景混入前台应用。此修改覆盖初始实时模糊优先建议；无需截屏或隐藏其他应用。不可解码时材质回退，视频壁纸不播放。分页转场使用本应用网格位图快照，不含其他窗口画面。

2026-11-06 当前桌面修订：实际NSWorkspace壁纸URL返回系统默认图片，无法表示本机正在显示的生成式壁纸。改为临时隐藏原本可见的其他regular进程，在透明覆盖窗口后显示系统真实桌面，dismiss/settings/termination恢复已记录进程。不是静态壁纸猜测、不是截屏、不是强切Space。不隐藏后台agent，也不将原已隐藏应用恢复。隔离测试禁止实际隐藏用户应用；真实桌面恢复需手测。设置改由显式NSWindow持有，不依赖失效responder selector。合并命中改整枚实际图标且不再等待650ms，依用户新指令。

2026-11-06 修订：背景恢复系统模糊但强制深色hud材质，避免浅色泛白。触发角采用自有mouseMoved观察+一次性dwell任务，默认禁用；未找到公开系统菜单扩展，未注入或修改系统配置。文件夹外drop由NSWindow的NSDraggingDestination处理，统一事务后校验当前folder ID仍存在。

目录分组为一次性布局升级（可选directoryGroupingVersion），物理来源提示保存在本地catalog/自动文件夹，便携导出移除。首次分组只处理根散列项，保留用户自建文件夹；后续扫描不强行重组已移动应用。名称按FileManager文件显示名，Bundle本地化名称只供搜索。分页使用整页出入两张快照，空白点击延迟到mouseUp以让拖动优先。

2026-11-07：用户选择A，显示/搜索主名改为实际文件名去.app，保留其他名称作搜索别名。触发角的真实系统指针测试揭示回调后窗口未上屏，show显式unhide并使用SDK支持的activate(ignoringOtherApps:)与orderFrontRegardless。该激活路径目前公开可用但已注明未来弃用方向，后续SDK升级需重新验证；不使用私有激活API。仅启用触发角时持有允许空闲睡眠的用户活动token作后台调度加固，关闭释放。

2026-11-07用户修订：触发角从“驻留后仅显示”改为“进入立即切换显示/隐藏”，30ms指针采样加离开解锁；系统隐藏通知同步展示意图。根NSCollectionView常驻，文件夹独立浮层，根/文件夹容量分别缓存，根几何不参与文件夹展开动画；仅整体透明度变化。此策略避免共享容量和视图重建造成的根布局闪烁。
