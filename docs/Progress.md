# LaunchDock 进度

更新：2026-11-06。仓库初始仅有规范，无 AGENTS.md、无源码、无 Git 元数据；保留原始规范。以下区分代码接入、实际检查和验收，全部阶段尚未统一验收完成。

| 阶段 | 已实现 | 实际测试 | 未验证 / 未完成 |
|---|---|---|---|
| M0 | 单窗口、材质、激活、鼠标选屏、Carbon 组合键、SMAppService 接入 | CLT Swift 编译、Xcode Debug/Release 本地构建；系统接受 open 请求 | GUI 检查工具超时；输入法、多屏、全屏、登录实验未完成 |
| M1 | 标准目录真实递归扫描、链接范围/去重、Bundle 过滤、系统图标、NSCollectionView、分页、Dock/菜单栏、确切 URL 启动 | 真实扫描两轮身份测试、同 ID 副本测试；本地 App 构建 | 实际启动目标应用和缺失启动失败未 GUI 测试；同名来源标签缺少 |
| M2 | NSSearchField marked text 路由、规范化排名、全局文件夹应用搜索、键盘选择/Return/Esc | 英文、全角、中文拼音、排名、空白查询测试通过 | 中文候选手测、Tab/跨页边缘选择、搜索滚动焦点待完善 |
| M3 | 纯值事务引擎、移动/建文件夹/解散/改名、菜单辅助整理、拖动延迟提交/悬停/边缘翻页 | 同容器索引、B/A 文件夹顺序、解散、取消无效事务、隐藏归属、1000 次随机操作通过 | 完整拖动投影/临时页/自动展开/拖出根、长按和居中文件夹容器未完成 |
| M4 | FSEvents 子树监听/防抖、唤醒与过期补扫、交互排队、缺失保留、actor 原子 JSON/3备份/恢复/高版本保护、原生设置 | 损坏恢复、旧 revision 防覆盖、高版本不写回通过 | 权限失败/7天时钟矩阵、UI自动化、VoiceOver/性能/完整诊断、版本偏好未完成 |
| M5 | 拼音、20 次撤销、隐藏恢复、路径隔离导入导出/预览、废纸篓限制、发行文档 | 拼音、隐藏邻接、导入匹配/占位/大小上限测试通过 | P0 尚未完整验收；P1 GUI验收与正式图标、Developer ID/公证均未完成 |

## FR / AC 对照

| 要求 | 状态 |
|---|---|
| FR-001–003 / AC-02,10,11,14 | 代码接入；后台登录、焦点恢复、安全区/多屏待验证/完善 |
| FR-010–011 / AC-01,07,08 | 真实扫描、身份、缺失处理已实现；同名来源 UI、失败根与7天矩阵待补 |
| FR-020–021 / AC-05 | 适配与离散分页已接入；跟手分页和完整跨页拖动未完成 |
| FR-030–031 / AC-03,04 | 搜索逻辑已测；输入法/键盘全矩阵未验收 |
| FR-040–042 / AC-06,13 | 布局事务测试通过；复杂拖动与文件夹容器不完整 |
| FR-050 / AC-09,14 | 设置和备份恢复代码/测试具备；版本偏好、登录真机验证待完成 |
| FR-051 / AC-17,18 | 代码接入；部分纯逻辑通过，系统文件操作未实际执行 |
| FR-060–061 / AC-12,13 | 基本材质/按钮语义；图标/辅助功能完整验收未完成 |
| NFR-001 | 未测量，见 Performance.md |
| AC-15,16 | 没有权限提升/事件 tap；干净账户与应用启动矩阵未验收 |

## 实际检查记录

- 初始 CLT 构建被缓存权限阻止，获授权后编译通过；CLT 缺少 Testing，随后新增独立 CoreChecks。
- 系统工具链在执行期间切换为 Xcode 27.2 (27B52)，macOS 26.6.2 arm64。
- 修复过的实际失败：损坏 JSON 在进入备份恢复前抛异常、本地 package 缺少核心 library product、Debug 架构不匹配、跨 actor 目录属性访问、目录测试初始化。
- `swift test --scratch-path /tmp/launchdock-xcode-tests`：10 项 Swift Testing 测试全部通过，包括真实扫描与 1000 次确定性操作。XCTest 外壳的“0 tests”不是最终测试数。
- Xcode Debug App 构建通过；Release arm64 本地无签名构建通过（后续最终检查见下）。`plutil -lint` 工程通过。
- 系统 `open` 返回成功；界面检查工具 30 秒超时，无截图/交互通过结论。
- 未签名、公证、stapling；未声称性能或全屏兼容性达标。

详细缺口见 Known-Limitations.md。研究项独立记录，不算实现。没有将 UI 预览、模拟列表或空实现当作完成。

最终检查：

- 共享 scheme `xcodebuild ... Debug ... test` 退出码 0；`xcresulttool get test-results summary` 确认 **10 passed / 0 failed / 0 skipped**，Mac mini arm64、macOS 26.6.2。结果包：`/tmp/launchdock-derived/Logs/Test/Test-LaunchDock-2026.11.06_12-39-44-+0800.xcresult`。工具先因缓存权限失败，获授权后读取成功。
- 最终源码 `xcodebuild ... Release ... ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO build` 退出码 0。未验证 universal Release，未生成已签名发行包。
- 当前 Debug 应用：`/tmp/launchdock-derived/Build/Products/Debug/LaunchDock.app`。

## 问题修复：全屏、长按整理、滚轮（2026-11-06）

用户截图显示内容仅占屏幕左侧、菜单条可见、无法长按整理和滚轮翻页。本轮保留数据文件与已有代码，修复如下：

- SwiftUI VStack/网格外壳撑满窗口并居中；NSHostingView 关闭内容尺寸反向约束；OverlayWindow 使用完整 screen.frame 且不按菜单条约束缩小。显示期间设置 hideDock + hideMenuBar，隐藏/失焦恢复原 presentationOptions，不创建新 Space。
- 实际网格 viewport 决定列数、行数、单元尺寸与分页容量；最多7×5；避免原生 FlowLayout 排9列、逻辑却按7列分页。根浏览取消竖向滚动条，搜索仍允许滚动。
- 鼠标按下后500ms进入整理，移动6pt启动原生拖动，不再在 mouseDown 后立即启动应用。拖动中央650ms后生成建文件夹/移入文件夹目标；550ms边缘停留翻页、700ms冷却。释放后才提交布局。拖动中推迟扫描合并。
- 外层 PagingScrollView 接收滚轮并统一路由到 PageScroll。普通滚轮按事件间隔累积，使用独立冷却；触控板一次手势只翻一次，忽略惯性。搜索正常滚动，输入法组合/拖动时不翻页。

实际检查：

- Xcode Debug build + test 成功；新加两项纯逻辑滚轮累积/冷却/方向反转和触控板手势/惯性测试，共12项通过。
- `sh scripts/check-native.sh` 实际运行独立 AppKit 窗口，断言1920×1080全宽内容、网格居中、7列35项分页、650ms按住进入整理、外层滚轮三次翻一页，输出 PASS。不启动用户应用、不写入用户布局。
- 屏幕自动检查工具再次超时；真实屏幕菜单条隐藏、物理鼠标拖动/中央悬停合并/跨页仍需按手工步骤验收，不用合成事件冒充完整 GUI 验收。

手工复查：重新打开本次 Debug 产物，确认搜索和网格位于屏幕中央、菜单条隐藏；长按图标直到出现“完成”和编辑底色，拖到其他格边缘排序；在另一个图标中央停650ms后释放建文件夹；滚轮向下翻后页、向上翻前页；Esc退出编辑后再Esc隐藏，确认菜单条/Dock恢复。暂未完成的跟手连续分页等功能仍见 Known-Limitations.md。

最终结果包 `Test-LaunchDock-2026.11.06_12-55-19-+0800.xcresult` 摘要确认12 passed / 0 failed / 0 skipped。原生检查输出：`PASS: full-width hosting, centered 7×5 grid, 500ms long press, outer-scroll wheel paging`。AppleScript 按 bundle ID 请求退出旧进程时未能解析应用，改用 NSWorkspace 的精确 bundle ID 查询，不操作其他应用。

## 问题修复：壁纸、整理样式、文件夹合并、动画（2026-11-06）

- 背景：显示时通过 NSWorkspace.desktopImageURL(for:) 读取目标屏幕壁纸文件，等比铺满并轻微压暗；不再透出前台应用的模糊内容。未读取截图、未请求录屏权限。无法读取壁纸时保留材质回退；视频/动态壁纸仅使用系统返回文件可解码的静态画面，未实现视频播放或桌面 Space 独立壁纸同步。
- 样式：移除编辑单元格蓝底和选择蓝框；键盘选择用标签加粗表达。合并就绪时只降低目标图标透明度，不绘制整格色块；文件夹显示最多9个成员的小图标预览。
- 合并：替换默认 collection 插入目标代理为 GridCollection 自己的原生拖放 destination；根据真实 imageView 的中央50%命中，单一40ms定时器在 eventTracking/common runloop 持续计算静止悬停650ms。释放才提交建文件夹/移入事务，离开、取消、结束和隐藏清理计时器，拖动期间队列化扫描。
- 动画：显示220ms淡入、隐藏200ms淡出，generation 防旧隐藏回调关闭已重新显示的窗口。翻页250ms滑动淡出旧网格快照、淡入新页；快照只来自应用自己的网格，不包含桌面/其他应用，不接收输入。减少动态效果开启时即时切换。

实际检查：

- Xcode Debug build/test 退出码0，最终结果包 `Test-LaunchDock-2026.11.06_13-05-57-+0800.xcresult`。
- 原生检查脚本在独立临时数据目录通过：全宽居中、7×5分页、500ms长按、外层滚轮；静止悬停低于阈值不合并，超过阈值生成目标且revision不变，drop提交后B/A顺序正确；追加第三项到已有文件夹成功；无边框；实际壁纸文件加载；显示/隐藏动画结束状态、快速重入不被旧回调关闭、presentationOptions恢复；翻页快照动画存在。
- 新增动画断言曾暴露CATransition被AppKit刷新清除的问题，已替换为非交互网格快照转场，重跑通过。
- 检查是原生视图/拖放事务路径的合成测试，不等于物理鼠标完整拖拽事件或视觉手感验收。尚未目视确认动画流畅度、动态壁纸、多屏与系统全屏Space。

最终 Xcode 摘要：12 passed / 0 failed / 0 skipped。NSWorkspace 正常退出旧 LaunchDock 返回 true，随后系统 open 接受新 Debug 构建打开请求。

## 交互修订：直接松手合并、当前桌面、可打开的设置（2026-11-06）

用户修订覆盖此前650ms合并默认值：

- 拖入另一应用/文件夹的实际图标矩形，立即优先作为合并/移入目标；无需等待。标签、格边缘与其他位置用于排序；文件夹本身仍不能嵌套。松手才提交，离开目标取消合并候选。保留边缘翻页的独立计时器。
- 本机实测 NSWorkspace.desktopImageURL 返回 `/System/Library/CoreServices/DefaultDesktop.heic`，与用户所见生成式Sequoia桌面不符。移除该静态背景替换，改用真实桌面透出的原生材质：显示启动器时临时hide原本可见的其他regular应用，隐藏/设置/退出时unhide同一批仍存在的进程，不恢复原本已隐藏的应用，不重新启动进程，不请求录屏权限。动态壁纸与当前Space来自系统实际桌面。该实现有临时隐藏其他应用窗口的明确行为变化；没有宣称从公开API取到了精确动态壁纸文件。
- 设置不再发送失效的 `showSettingsWindow:` 字符串selector。AppCoordinator直接持有可重复使用的原生设置NSWindow，菜单栏、网格齿轮、Cmd+,统一入口；关闭不销毁，再次打开同一窗口。打开设置立即隐藏覆盖窗口并恢复菜单/Dock及其他应用。

实际检查：

- Xcode Debug build/test退出码0，结果包 `Test-LaunchDock-2026.11.06_13-18-06-+0800.xcresult`。
- 原生隔离检查通过：立即创建文件夹B/A、立即移入已有文件夹、hover不提交、边缘区域排序不合并；设置窗口可见、可接受key、关闭后重新打开同一实例；显示隐藏/重入、翻页动画、长按/滚轮继续通过。测试数据只写临时目录，测试禁用临时隐藏用户应用。
- 设置焦点的强断言在工具进程中失败，诊断为应用未被系统激活（active=false），但窗口visible=true、canKey=true。因此未将系统前台激活记为通过；真实菜单点击的焦点仍待人工验证。
- 当前桌面显露/其他应用隐藏恢复需用户桌面目视验收，未用禁止的截屏或全局输入权限替代。

## 修复关闭恢复与图一视觉比例（2026-11-06）

- 不再用hide()的即时Bool返回过滤原先可见的应用；在发出任何hide请求前，DesktopVisibility先取得完整所有权快照。dismiss一开始即unhide，不依赖动画completion；150ms间隔重复8次，等待异步隐藏/恢复收敛，恢复失败条目保持所有权直到后续恢复，终止前也重试。快速show/hide不覆盖所有权；原本已隐藏的应用不进入快照。取消启动器恢复原前台应用，启动目标应用或外部失焦不抢回旧焦点。
- 参照用户图一：移除会让背景发白的fullScreenUI材质，使用真实桌面上的24%黑色透明遮罩，不获取/猜测默认壁纸。默认图标从72pt提高到128pt，旧尺寸偏好56/72/88迁移到112/128/144。标签白色，搜索改为256×34pt半透明胶囊，无蓝色焦点框，设置入口收进搜索栏末尾圆形省略号。
- 网格宽度为屏幕70%，最多7列×4行，行距随屏幕高度比例分布；网格顶部约屏高12%，页面圆点保留底部。只改变密度/分页，不改布局全局顺序。文件夹缩略图按新尺寸绘制。

实际检查：

- Xcode Debug build/test退出0，12项逻辑回归通过，结果包 `Test-LaunchDock-2026.11.06_13-46-18-+0800.xcresult`。
- 原生检查通过128pt图标、白标签、7×4网格、居中、长按、滚轮、动画、立即合并/移入与边缘排序、设置重复打开。
- 专用FakeDesktopApp检查覆盖：hide返回false但实际隐藏、首次unhide失败后重试、原已隐藏应用不恢复、快速进出所有权不丢失。
- 额外实际构建并运行两个临时AppKit helper进程，用NSRunningApplication实际hide/unhide：原可见helper恢复可见、原隐藏helper仍隐藏，通过；随后退出两个helper。不操作用户应用来冒充测试。
- 本轮原生检查设置诊断visible=true/key=true/active=true；之前工具进程前台激活失败的结果保留历史，不再作为本次通过结论。
- 物理多屏/全屏Space、图一像素级视觉一致性仍需目视验收。旧进程已经丢弃的隐藏记录无法从新进程准确重建，本次不擅自unhide全部用户应用。

最终源码复测：`Test-LaunchDock-2026.11.06_13-48-56-+0800.xcresult` 对应Xcode test成功；原生窗口检查与两个真实helper隐藏恢复再次通过，设置visible/key/active均为true。

## 修复文件夹浮层、空白点击/滚轮和搜索重叠（2026-11-06）

- 文件夹改为居中圆角半透明面板，标题位于上方，宽度屏幕88%；根据成员数显示1–3行，内部独立分页。打开时移除根网格/搜索交互树，关闭返回根页面；支持减少动态效果的展开/收起转场。容器内空白不会退出，容器外点击只关闭文件夹。
- OverlayWindow统一路由本窗口的leftMouseDown/scrollWheel，不使用全局监听。根网格未命中条目的空白与四周边缘均可隐藏启动器。LauncherRegion原生布局标记保护搜索、按钮、分页、提示和整个文件夹面板，避免父层手势吞控件事件。
- 窗口四周的滚轮统一发给当前网格的同一PageScroll聚合器，根/文件夹均生效；搜索结果保留原生纵向滚动，输入法组合与拖动保护继续有效，不双重翻页。
- LauncherSearchCell显式划分放大镜14pt矩形、文字从27pt起的编辑矩形和右侧清除按钮；正常与编辑状态使用同一布局，保留原生NSSearchField和IME路由。

实际检查：

- Xcode Debug build/test退出码0，结果包 `Test-LaunchDock-2026.11.06_13-57-26-+0800.xcresult`，核心测试12项。
- `sh scripts/check-native.sh`通过窗口sendEvent的边缘空白关闭、四周滚轮翻页、打开32成员文件夹后边缘滚轮翻其内部页；面板内点击不关闭、面板外首次点击仅关闭文件夹、再点击退出根；面板宽/高非全屏且根搜索不残留。
- 搜索放大镜与文字区域保持至少6pt间距，实际fieldEditor坐标也通过不重叠断言。
- 本应用自己的NSHostingView渲染图 `/tmp/launchdock-folder-panel-check.png` 已检查：居中标题、宽圆角面板、成员左起排列；测试用临时应用条目，不当作真实产品清单完成证据。未捕获桌面或其他应用窗口。
- 真实AppKit helper隐藏/恢复及此前布局、动画、立即合并/移入/排序、设置重复打开回归通过。物理输入、多屏和真实壁纸上的最终视觉仍需用户目视验收。

## 背景模糊、触发角、拖出文件夹与解散修复（2026-11-06）

- 真实桌面背景上加入公开NSVisualEffectView behindWindow模糊，使用hudWindow并明确darkAqua外观，叠加12%暗罩，避免之前浅色fullScreenUI泛白。未截屏、未请求录屏权限；系统降低透明度由原生材质处理，实际模糊强度/色彩待目视验收。
- 应用设置新增触发角页：四角独立启用，默认全关闭，进入5pt角落停留350ms唤起，可要求Option；每次进入只触发一次，离开后重新解锁；按鼠标按钮/拖动不触发。不注册全局键盘监听，不请求辅助功能或输入监控；仅启用时观察本地/全局mouseMoved，停留计时仅在角落活跃，无常驻轮询。回调直接注入设置视图，不依赖NSApp.delegate强转。
- 未发现受支持的系统触发角第三方动作注册接口，按用户备选采用应用内配置，不注入系统设置、不写Dock私有偏好。系统功能与自定义触发角可能同时响应，设置中说明改角或使用Option。参考：[Apple触发角说明](https://support.apple.com/en-za/guide/mac-help/mchlp3000/mac)。未宣称支持系统菜单扩展。
- OverlayWindow注册拖放目的地：来自当前文件夹的app在面板外、窗口内释放时，提交同一LayoutEngine移出事务，放到原文件夹根位置之后并返回根网格；面板内和窗口外不作为移出。目的地接入依据[AppKit Dragging Destinations](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/DragandDrop/Concepts/dragdestination.html)。
- 所有成功布局事务/扫描reconcile之后统一修复当前内容上下文：原文件夹消失时立即关闭浮层，因此两项拖出一项后不会残留“没有可用应用”。菜单移出/撤销导致解散也走同一修复。

实际检查：触发角纯状态机的停留/修饰键/拖动排除/单次触发已通过；原生面板外接收区域、移出位置、二变一解散、任意事务解散关闭上下文通过。物理鼠标跨面板拖放、系统全局触发角唤起、系统角冲突、背景视觉仍待人工验收。

## 保留磁盘目录、Finder名称、整页动画与鼠标拖动翻页（2026-11-06）

- catalog记录应用所在扫描根下的第一层普通目录（遇.app仍停止递归），扫描UI中按真实目录建立同名启动器文件夹，例如Utilities，不再首次扫描全部摊平。深层子目录成员并入第一层，不建立嵌套启动器文件夹；单成员继续遵守既有单项解散规则。
- 对既有散列布局执行一次有版本标记的目录分组，保留用户自建文件夹；之后只将新应用追加到对应来源文件夹，手动移出和重命名不会被后续扫描撤销。保存仍保留旧版本备份。新增字段均为可选兼容已有JSON；便携导出移除物理目录路径，导入不信任路径。
- 显示名改用FileManager.displayName(atPath:)，即Finder文件显示名称；Bundle本地化名与旧名称保留为搜索别名。本机查询Terminal的文件显示名为Terminal.app，与之前应用包名字来源不同。
- 分页转场改成两张完整网格快照：旧页向整页宽度滑出、新页从另一侧滑入，300ms统一缓动；不对cell分别动画、不再80pt位移加淡入。快照仅来自本应用，忽略鼠标命中，背景/搜索保持固定，减少动态效果时即时切换，重复翻页generation隔离。
- 空白mouseDown只保留手势起点，不立即隐藏；横向移动60pt后松手翻一页，发生移动后即使回到起点也不当单击。小范围单击在mouseUp时才隐藏/关闭文件夹，竖向/短距离拖动取消不隐藏；图标和标签仍用于启动/整理，搜索和按钮受保护。根页边界拖动只夹紧，不误关。

最终验证：

- Xcode Debug build/test退出0，共16项；结果包 `Test-LaunchDock-2026.11.06_17-09-43-+0800.xcresult`。
- 新增测试覆盖目录分组/新增应用追加/保留手动移出和改名、导出无来源路径、真实临时bundle扫描与Finder名/别名、鼠标点击/左右拖动/回原点/垂直拖动优先级。扫描路径断言曾因/var与/private/var同一目录的别名失败，改为真实目录inode验证后通过，未把路径字符串当安装身份。
- `sh scripts/check-native.sh`聚焦检查输出ALL NATIVE CHECKS PASSED；覆盖窗口鼠标按下不关闭、横拖翻页、抬起单击关闭、旧/新两张整页快照、文件夹浮层/分页/搜索编辑框间距、拖出及二变一关闭。仅写临时数据。
- 原生检查曾正常提前退出而只输出部分记录，现在脚本强制检查完成标记，不再仅凭退出码0通过。默认运行聚焦交互检查；旧生命周期/设置/真实helper恢复检查分为LAUNCHDOCK_CHECK_LIFECYCLE=1可选运行，本轮该扩展模式未通过（AppKit激活/动画/关窗过程提前终止），不记作通过。此前历史通过记录保留，但不替代本轮结果。
- 多屏、实际物理输入、视觉一致性、触发角系统级效果仍需人工验收；未签名或公证。

## 触发角单选与可用性、去除.app、名称属性列表（2026-11-07）

- 触发角改为单选radioGroup：关闭/左上/右上/左下/右下。旧bitmask迁移到hotCornerSelection，只保留第一个已启用角；原选择只有右上角时继续保留右上。Option独立开关不受影响。
- 移除依赖后台mouseMoved投递的触发链，改为仅启用时以100ms定时器读取公开NSEvent指针位置/修饰键/按键状态，Timer加入RunLoop.common，容差25ms。精确屏幕边界同样命中，350ms驻留判定和离开解锁保持；禁用立即销毁Timer。无需辅助功能/输入监控，未获取普通键盘输入。此可靠性选择相对原“无轮询”设计有明确偏差：启用时每秒最多约10次轻量指针取样，性能尚未实测。
- AppRecord新增只读label，去除name末尾.app（大小写不敏感），不截断中间的.app字符串。主网格/文件夹/隐藏应用列表使用label，catalog原始name及身份路径保留。
- 名称来源暂时仍为Finder显示名，仅去后缀，等待用户选择。新增scripts/inspect-app-names.swift、docs/App-Name-Values.json和docs/App-Name-Options.md，列出本机Terminal/VSCode/WeChat/ChatGPT的文件名、Finder名、raw/localized/effective CFBundleDisplayName/CFBundleName、显式简体中文资源、localizedName、可执行名和bundle ID。缺字段标—，未虚构；本次读取进程英文值与显式中文值分开。

实际检查：

- Xcode Debug build/test退出0，新增标签后缀用例，总计17项逻辑测试；最终结果包见当日12:03构建。
- 独立scripts/check-hot-corner.sh使用真实同步RunLoop及Timer、隔离UserDefaults和可注入指针，验证：旧选择迁移、静止精确边界触发实际action回调、驻留不连发、重新进入触发、Option门槛、拖动抑制、改角不响应旧角、关闭销毁Timer。输出PASS。不移动真实鼠标、不改用户偏好或系统触发角。
- 最初把定时器检查塞入旧异步窗口检查后，该进程在后续阶段仍提前退出；不记完整原生检查通过。现使用独立同步RunLoop程序完成本轮触发角实际定时链检查，旧生命周期检查限制仍保留。
- 真实桌面鼠标触角唤起/系统触发角冲突及能耗仍待手工确认，未宣称该全局场景已经通过。

最终摘要：`Test-LaunchDock-2026.11.07_12-03-25-+0800.xcresult` 确认17 passed / 0 failed / 0 skipped。旧进程正常退出返回true，随后系统接受新Debug构建打开请求。

## 名称选择A与真实触发角后台唤起修复（2026-11-07）

- 用户已选择A。AppRecord.label从真实.app路径取文件名并删除扩展名，例如Visual Studio Code.app → Visual Studio Code；不可用导入占位或非.app测试记录回退已有名称。搜索主名称/拼音和字母重置排序同步使用label，原Finder/Bundle名称保留别名搜索，不重排现有用户布局。App-Name-Options.md已标记已选A。
- 读取实际用户偏好：本轮选中左上角（selection=0）、Option关闭。新增仅Debug的/tmp/launchdock-corner-<pid>.json状态诊断，仅记录触发/运行计数与窗口状态，不记录搜索词/应用名称；用于区分计时器、角落命中、回调和窗口显示。
- 真实失败复现：指针在左上角停稳后fires从0增加为1，但进程inactive且屏幕上无覆盖窗口。因此此前仅模拟回调通过无法证明后台唤起成功。
- show明确执行NSApp.unhide、当前SDK仍支持的activate(ignoringOtherApps: true)、orderFrontRegardless及makeKeyAndOrderFront；不再仅调用activate()并假设显示成功。触发guard同时检查真实visible/alpha，避免wantsVisible陈旧值阻止唤起。Debug记录shown/hidden最终状态。
- 启用触发角期间保留userInitiatedAllowingIdleSystemSleep活动，禁用时释放，作为后台定时器调度加固；不能将App Nap视为本次唯一已证实原因（真实诊断显示定时器已在运行，失败发生在窗口显示环节）。[Apple ActivityOptions说明](https://developer.apple.com/documentation/foundation/processinfo/activityoptions/userinitiatedallowingidlesystemsleep)指出此选项仍允许系统空闲睡眠；未禁用系统睡眠或修改全局电源设置。

实际验证：

- 最终Xcode Debug build/test结果 `Test-LaunchDock-2026.11.07_12-17-47-+0800.xcresult`：18 passed / 0 failed / 0 skipped。
- 独立check-hot-corner.sh的真实同步RunLoop定时回调检查继续通过。
- RuntimeCornerProbe.swift在本机实际运行：先确认当前所选左上角没有系统动作，记录/恢复原鼠标位置；隐藏LaunchDock，使用公开CGWarpMouseCursorPosition将系统实际指针短暂停在左上角（非注入service假坐标），检查Debug诊断与CGWindowList窗口元数据，不截图、不请求输入监控。
- 修复前真实链FAIL；修复后两次真实链验证，最终fires 0→1，isActive=true，isHidden=false，2560×1440、layer=3、alpha=1覆盖窗口在屏幕列表中，shown状态visible/wantsVisible/active/opaqueEnough全部true，输出PASS: real pointer -> background timer -> action -> on-screen overlay。脚本失败返回非零，且恢复指针；未修改用户触发角选择或系统角动作。
- 此实测覆盖当前Mac单屏左上角；其他角、修饰键由独立状态机/定时回调覆盖，其他显示器/系统全屏Space与能耗未实测。

## 触发角立即切换与文件夹根网格稳定（2026-11-07）

- 进入选中触发角立即调用toggle：已显示则隐藏、隐藏则显示；取消原350ms驻留，首个有效采样即触发。启用时采样改为30ms、容差5ms，保持离开后重入才再次触发，防止停在角落反复开关。设置说明同步，不承诺系统调度延迟为零。
- toggle结合wantsVisible、window.isVisible及NSApp.isHidden判断；新增applicationDidHide状态同步，避免系统隐藏应用后仍有旧显示意图，导致首次触角被错误当作关闭。保留后台显式unhide/激活/orderFrontRegardless的显示修复。
- 根网格不再通过if/else与文件夹互相替换，保持原NSCollectionView及cells；仅整体淡出并禁止命中/辅助功能访问，文件夹作为单独浮层叠加。根网格和文件夹分别缓存容量与根页位置，文件夹的7/21项容量不再覆盖根28项投影；移除根子树的隐式几何动画，仅对整体显隐/文件夹浮层做动画。
- 隐藏根网格的区域标记与搜索不再参与窗口点击保护和焦点查找；窗口事件始终查找当前active context的grid。扫描/真正布局事务仍可更新缓存，单纯开关文件夹不重新分配根应用。

实际验证：

- 最终Xcode Debug test退出0，结果包 `Test-LaunchDock-2026.11.07_12-41-23-+0800.xcresult`，18项回归。
- check-hot-corner.sh将首个检查窗口缩短到90ms，实际RunLoop定时action立即触发，驻留不连发/Option/拖动/切换角/关闭清理继续通过。
- check-native.sh最终输出ALL NATIVE CHECKS PASSED；新增断言确认文件夹开/关前后根collection对象、首cell对象、容量、项目序列和首cell frame全部不变，旧根context不参与查找，浮层内外点击/分页/拖出/解散回归通过。测试在前一排序事务渲染稳定后才记录对照值，避免把未提交的UI刷新误当开文件夹重排。
- 用户当前改选右上角，原先只允许左上角的真实探针拒绝运行后已扩展为读取所选角并检查对应系统动作，不改用户设置。首次动态实测暴露系统隐藏的旧状态残留，修复didHide后重跑通过。
- RuntimeCornerProbe实际系统指针移入右上角：fires 0→1，进程active=true、hidden=false，layer3/2560×1440/alpha1覆盖窗口在屏幕列表中；离开再进入fires=2，覆盖窗口从屏幕列表消失，输出PASS: leave and reenter corner toggles visible launcher off; parked pointer never repeats。结束恢复原指针；不截图、不修改系统触发角。
- 根网格不重建已有结构检查，但动画的像素级视觉/其他显示器仍待目视验收。启用时更短采样间隔能耗未测量。

## 文件夹开关尺寸跳变及关闭滚动条闪现（2026-11-07）

原因与修复：

- 旧文件夹transition包含scale(0.96)，本身就会在开/关时改变显示长宽；现改为纯opacity，宽度保持屏宽88%，高度仅根据该文件夹真实成员行数和屏幕可用高度计算。
- SwiftUI保留退场视图约200ms，旧代码继续读取store.visible/pages/capacity，此时这些字段已切回根上下文。现独立FolderPanel持有对应Folder值，页数直接按其自身几何计算，所选页只在该folder活跃时同步；不会在退场期间误读根应用总数而增高面板/出现页点。
- GridCollection绑定folderContextID。对应文件夹不再活跃时，updateNSView和fitViewport冻结，保留原项目、尺寸和布局，不向退场grid灌入根页数据。分页document高度不再保留旧大高度，只与当前viewport匹配。
- PagingScrollView明确管理滚动条策略：仅搜索结果允许纵向滚动，根/文件夹分页禁用横纵滚动条和弹性，并在AppKit布局后重新应用策略；非搜索时忽略flashScrollers。初次原生断言发现仅在update中设置仍不足，已增加layout后策略并去除会影响状态的nil scroller赋值。

验证：

- 最终Xcode Debug test成功，结果包 `Test-LaunchDock-2026.11.07_12-54-09-+0800.xcresult`，核心测试18项。
- 原生检查关闭动画期间12次持续采样，确认退场folder.items、scroll frame.size恒定，横纵hasScroller始终false，显式flashScrollers不启用滚动条；关闭后root collection/cell实例及容量/坐标保持不变。完整结束标记ALL NATIVE CHECKS PASSED。
- 初次检查有一次提前结束，不记通过；退出旧LaunchDock进程后重跑完整通过。测试只用临时数据；未用截图或搜索词日志替代界面行为验证。
- 其他原生回归：浮层内/外点击、窗口边缘滚轮、搜索编辑区间距、立即合并、拖出/解散关闭继续通过。像素级视觉与不同系统滚动条偏好仍待用户目视确认。

## 恢复可靠的文件夹开关动画（2026-11-07）

- 用户反馈此前SwiftUI隐式过渡实际无动画。改为常驻FolderOverlayView，通过私有原生container的显式CABasicAnimation(opacity)驱动220ms淡入淡出，不依赖SwiftUI的transition事务；内层布局仍可禁止动画，不会连带取消外层fade。
- 原生host在关闭时保留旧FolderPanel到fade结束后再隐藏，尺寸/内容冻结及滚动条策略保留；不使用缩放。关闭立即停止该浮层命中，旧区域标记不拦根页操作；重新打开从当前presentation opacity续接，generation与可取消completion防旧任务隐藏新显示层。减少动态效果时遵循系统即时切换。
- host按实际folder/宽高变化才更新rootView，页码在同文件夹重新打开时与store同步，避免保留上次页点。

实际验证：

- Xcode Debug test成功：`Test-LaunchDock-2026.11.07_13-00-39-+0800.xcresult`，18项逻辑回归。
- 本机reduceMotion=false（另行读取确认），check-native.sh在打开约70ms、关闭约60ms分别读取container.layer.presentation.opacity，断言均严格介于0和1，且存在folderFade动画；证明检查没有只看终态、也没有因减少动态而跳过动画断言。
- 同一测试继续确认退场尺寸/内容恒定、无滚动条闪现、根collection/cell不重建，输出ALL NATIVE CHECKS PASSED；文件夹移出/解散、内外点击、分页与搜索间距回归通过。
- 视觉曲线/不同显示刷新率仍待用户目视，本轮未运行完整扩展生命周期或多屏验收。

## 精简图标右键菜单（2026-11-12）

- 根据最新用户要求，图标右键菜单仅保留「在访达中显示」并新增「设置…」，删除整理、前后移动、移出、重命名、隐藏、废纸篓及创建/移入文件夹菜单入口及其旧处理器。拖动手势不变。
- 「设置…」通过 LauncherStore.showSettings 回调进入 AppCoordinator 现有设置窗口流程，根页、搜索结果及文件夹内图标共用该动作。
- 「在访达中显示」使用应用路径；扫描生成的目录文件夹使用 sourceDirectory。用户创建的虚拟文件夹没有 Finder 路径，该项禁用。

实际验证：

- Xcode Debug build 成功（CODE_SIGNING_ALLOWED=NO）。首次沙箱构建因用户缓存写入受限退出74，提升权限后构建通过。
- 新增原生交互断言：真实图标坐标取得 NSMenu，确认只有两个项目、无子菜单，核对应用路径；通过 NSApp.sendAction 实际分发「设置…」，确认设置回调调用一次。
- 原始 check-native.sh 链接现有 LaunchDockCore.o 时遇到覆盖率运行库缺失；尝试 CLANG_ENABLE_CODE_COVERAGE=NO 构建未消除。使用 /tmp 临时脚本为检查程序增加 -profile-generate 并将 profile 输出定向 /tmp 后，完整输出 ALL NATIVE CHECKS PASSED。文件夹开关动画/尺寸/滚动条、拖出解散、空白点击/全窗滚轮、搜索间距既有检查同时通过。仓库检查脚本未改动。
- 未自动调用 Finder 打开用户路径；设置窗口实际呈现与焦点切换待目视确认（本轮验证到设置动作回调分发）。未运行可选完整生命周期、多屏检查；未生成签名发行产物。

构建产物补充：同名 scheme 的首次 build 实际生成 Swift Package 可执行文件，原 /tmp/launchdock-derived/Build/Products/Debug/LaunchDock.app 不存在。随后明确指定原生 target 构建成功：`xcodebuild -quiet -project LaunchDock.xcodeproj -target LaunchDock -configuration Debug CONFIGURATION_BUILD_DIR=/tmp/launchdock-app-products CODE_SIGNING_ALLOWED=NO build`，App 产物为 `/tmp/launchdock-app-products/LaunchDock.app`。

## 按实际内容区分图标与空白右键菜单（2026-11-12）

已实现：

- 修复以整个网格单元格作为右键命中范围的问题。仅图标矩形与居中的实际名称文字区域触发 item 菜单，单元格内边距、名称左右留白及窗口边缘属于空白区域；裁剪视口外与非活跃文件夹上下文不命中。
- item 菜单仅「在访达中显示」。窗口统一路由右键，空白处的应用菜单为「设置…」「重启」「退出」，包含网格外的窗口空白及文件夹外区域。右键不会执行左键空白关闭逻辑。
- 三项分别连接现有设置窗口、重启、标准退出流程。重启先 flush 布局；临时 helper 等待旧进程退出，再用 /usr/bin/open -n 打开当前 App bundle（最多等待30秒），让旧进程先完成桌面恢复与快捷键释放。启动 helper 失败时保留当前进程并显示错误。

实际验证：

- 明确构建原生 target 成功：`xcodebuild -quiet -project LaunchDock.xcodeproj -target LaunchDock -configuration Debug CONFIGURATION_BUILD_DIR=/tmp/launchdock-app-products CODE_SIGNING_ALLOWED=NO build`。
- `sh scripts/check-native.sh /tmp/launchdock-app-products` 退出0并输出 ALL NATIVE CHECKS PASSED，无需上轮的临时覆盖率脚本。
- 新增真实坐标命中断言：图标/名称只产生 Finder 项；单元格内边距、名称左侧留白、窗口边缘只产生三项应用菜单。通过 NSApp.sendAction 验证设置、重启、退出分别调用对应回调且各一次，避免测试误退出当前进程。
- 文件夹动画/固定几何/无滚动条、拖出解散、空白点击、全窗滚轮及搜索间距回归继续通过。
- 待实际界面验证：空白菜单选择重启后进程替换、布局恢复和全局快捷键重新注册；退出后桌面恢复。本轮不把回调分发测试当作完整重启/退出生命周期验证。可执行步骤：移动鼠标到图标旁留白右键，应出现三项；点设置打开设置窗口；重新显示后选重启，检查应用恢复、布局不变且触发角/快捷键可用；再选退出检查进程结束和原窗口恢复。

## 根页面全宽翻页与两侧留白（2026-11-12）

已实现：

- 根页 CollectionGrid 视口从窗口宽70%扩展为100%，快照裁剪边界与横向翻页距离均使用窗口全宽。图标内容仍占中间70%，通过 collection layout 的左右对称 sectionInset 留出各约15%空白；列数、容量和图标大小按内容宽度计算，避免扩大视口后图标变密/放大。
- 两张页面快照均包含空白边距，图标可经过原中间网格边界，一直到窗口边缘才裁切。搜索框和页点保持固定。文件夹面板保留自身尺寸及布局。
- 翻页统一使用快照 layer 上显式 position.x 动画（300ms easeInEaseOut），以整页为单位移动，不逐图标动画。保留 generation 清理和系统减少动态效果行为。

实际验证：

- 原生 Xcode App target Debug build 成功，产物 `/tmp/launchdock-app-products/LaunchDock.app`；未签名。
- `sh scripts/check-native.sh /tmp/launchdock-app-products` 最终退出0，ALL NATIVE CHECKS PASSED。新断言在1920宽窗口验证视口/两张快照宽均1920，两边留白各约288，列数7、容量28保持不变；同时读取 presentation layer，验证两张页面确实处于平移中间帧且间距维持1920。
- 首次动画断言误以为 AppKit view.frame 应立即等于终点，失败后改查真实中间帧；进一步采样发现旧 NSAnimationContext 在检查中仅显示起点。改显式 Core Animation 后，真实呈现中间帧及页间距断言通过，未把“存在快照”当作动画已验证。
- 右键命中/菜单动作、文件夹开关中间帧/尺寸/滚动条、拖出解散、空白点击、全窗滚轮和搜索间距既有回归通过。
- 待目视验证：实际屏幕整页滑入滑出观感及多显示器/不同缩放比；本轮未运行完整重启/退出生命周期检查。验证步骤：在根页以滚轮、空白横拖或页点翻页，应看到图标穿过原70%区域边界，直到窗口边缘才退出，并且新页两侧留白不变。

## 两处右键菜单使用浅色外观（2026-11-12）

- 图标 item 菜单与空白区域应用菜单均显式设置 NSMenu.appearance 为 Aqua，使用原生浅色菜单背景和深色文字，不再继承启动器的 dark 外观。原生悬停高亮和禁用项样式由系统绘制。
- 实际验证：原生 Xcode App target Debug build 成功（CODE_SIGNING_ALLOWED=NO），产物 `/tmp/launchdock-app-products/LaunchDock.app`。本轮仅外观修改，未新增测试或重跑交互套件。
- 未验证：不同壁纸下系统菜单材质的实际视觉效果。可在图标及空白处分别右键，确认均为浅色背景/深色文字；系统深色模式下也应保持浅色菜单。

## 搜索框无法点击输入（2026-11-12）

已实现：

- 原生检查复现：原自定义 NSSearchFieldCell(textCell:) 安装后，搜索框可编辑/可选择标志为false。现用标准搜索 cell 初始化，并显式启用 isEditable、isSelectable；装饰性胶囊描边关闭命中，避免影响搜索点击。
- LauncherSearchField 在鼠标、selectText 和程序取得焦点时配置实际 field editor 的文字内边距。无边框搜索框使用全尺寸编辑器，不能只依赖 searchTextRect 绘制占位文字；实际输入文字同样在图标右侧留出27pt，避免重叠。
- 原先检查在 currentEditor 存在时才检查间距，无法发现不可编辑问题。现要求点击必须生成编辑器并成为第一响应者；通过窗口 keyDown 输入1、delegate 更新query、真实网格显示筛选结果，再删除恢复根页，且全过程不触发空白关闭。
- 原生检查主入口改为在 NSApplication.run 事件循环内执行异步检查。原 async main 在启用真实文本输入后曾提前退出且无完成标记，不记通过；修正事件循环后完整回归成功。

实际验证：

- 原生 App Debug build 退出0：`xcodebuild -quiet -project LaunchDock.xcodeproj -target LaunchDock -configuration Debug CONFIGURATION_BUILD_DIR=/tmp/launchdock-app-products CODE_SIGNING_ALLOWED=NO build`。
- 最终 `sh scripts/check-native.sh /tmp/launchdock-app-products` 退出0，打印搜索点击/窗口键入/过滤/清空恢复的PASS及 ALL NATIVE CHECKS PASSED。完整保留右键菜单动作、全宽页面平移中间帧、文件夹开关/固定几何/无滚动条、拖出解散、空白点击和全窗滚轮回归。
- 尚未验证真实中文输入法候选与组合输入、多显示器焦点切换、完整重启/退出生命周期。真机步骤：显示启动器，点击搜索输入英文/中文并删除；切换到网格后再次点击搜索，确认可重新输入、候选期间不误启动应用。

## 移除搜索清空图标（2026-11-12）

- 按用户要求移除搜索框右侧清空按钮：cancelButtonCell 设为nil，cancelButtonRect返回zero，不绘制也不保留按钮点击区域。文字输入、键盘删除和设置按钮保留。
- 实际验证：原生 Xcode App target Debug build退出0（CODE_SIGNING_ALLOWED=NO），产物 `/tmp/launchdock-app-products/LaunchDock.app`。本轮为局部按钮移除，未新增测试或重跑交互套件。
- 待目视确认：输入非空搜索词时不再出现清空图标，键盘删除仍可清空内容。

## 独立壁纸快照，删除隐藏桌面应用方案（2026-11-12）

已实现：

- 删除DesktopVisibility.swift、项目引用、隐藏/恢复回调和重试任务；显示、关闭、设置、退出均不对其他应用hide/unhide。关闭时也不主动激活原应用。保留NSApp.unhide仅作用于LaunchDock自身。
- 独立WallpaperService：按目标屏幕读取壁纸文件并应用缩放/裁剪/填充；HEIC、多图资源或不可读来源在已有录屏权限时以ScreenCaptureKit仅捕获壁纸窗口。无视频播放/定时后台采集，每次打开刷新一张、显示期间固定。
- 背景改为自绘壁纸+24pt模糊+暗色遮罩，并有不透明纯色底，移除behindWindow真实桌面材质。准备好图片后再显示，取消及presentation generation防晚到截图重开窗口。
- 当前环境只读核实：NSWorkspace返回/System/Library/CoreServices/DefaultDesktop.heic，CGPreflightScreenCaptureAccess=false；窗口元数据显示Wallpaper为desktopWindow-2（-2147483625）。筛选已覆盖此情况并排除Dock、Finder图标、普通应用；不把DefaultDesktop默认路径冒充当前画面。
- 设置 → 外观加入主动录屏授权按钮及当前背景来源/降级状态。应用不自动申请权限；未授权优先可信文件静态画面，否则纯色。更新README、Known-Limitations、Manual-QA与ADR0002，替代旧背景说明。

实际测试：

- 完整 `LAUNCHDOCK_CHECK_LIFECYCLE=1 sh scripts/check-native.sh /tmp/launchdock-app-products` 最终退出0，ALL NATIVE CHECKS PASSED。包含静态图片实际像素与屏幕尺寸、未授权不截图、截图失败降级、单次截图且不持续采集、取消不发布、截图等待期间关闭不重开窗口。
- 两个可见、一个已隐藏的专用真实AppKit helper：开关启动器期间各12次采样，确认可见性及两个可见窗口的CGWindowID相对顺序不变。设置窗口开关重用、presentation恢复、显示/关闭/重入回归通过。
- 搜索真实点击/键入/删除恢复、菜单命中及动作、全宽页面中间帧、文件夹淡入淡出/固定尺寸/无滚动条、拖出解散、空白点击与全窗滚轮继续通过。
- 开发中修复Swift6非Sendable NSScreen跨隔离闭包声明；图片测试初用命名色导致日志警告，换设备RGB夹具；像素精确阈值因系统色彩管理失败，改为验证有意义的红色像素特征并保留显式图片尺寸后通过。未将早期失败或仅检查图片尺寸当作绘制已验证。

未验证：

- 本机尚无录屏授权，没有调用真实ScreenCaptureKit截图；动态壁纸截图测试使用注入提供器，窗口层级筛选通过只读元数据核实。须用户通过设置授权后实测当前画面、无图标/应用混入、不同屏幕/Space。未授权的当前环境会显示纯色，这是显式降级而非当前壁纸已读取成功。
- 像素级模糊观感、不同显示器缩放和动态壁纸提供器差异待Manual-QA步骤验证。未创建已签名发行产物。

最终原生Xcode App target Debug构建成功（退出0）：`xcodebuild -quiet -project LaunchDock.xcodeproj -target LaunchDock -configuration Debug CONFIGURATION_BUILD_DIR=/tmp/launchdock-app-products CODE_SIGNING_ALLOWED=NO build`。产物 `/tmp/launchdock-app-products/LaunchDock.app`。

## 修复壁纸授权按钮再次点击无响应（2026-11-12）

- 原按钮仅调用CGRequestScreenCaptureAccess，后续申请被系统记住时没有导航动作。新增ScreenCapturePermission：用户点击时检查/申请权限后，无论返回结果均显式打开屏幕录制设置页；该URL打开失败再退回隐私与安全性，全部失败显示手动路径。
- 按钮改名「打开屏幕录制设置…」，授权状态在设置出现及NSApplication.didBecomeActive时刷新；已允许时不再请求权限，但仍可打开系统设置。状态提示区分已允许与需要授权/重启。
- 实际验证：原生Xcode App target Debug build退出0（CODE_SIGNING_ALLOWED=NO）；`sh scripts/check-native.sh /tmp/launchdock-app-products`退出0并输出ALL NATIVE CHECKS PASSED。新增注入测试验证连续两次未授权点击均导航、授权后仍可导航且不重复申请、返回后refresh状态、专页失败退回隐私页及全部失败提示。既有壁纸、搜索、整页动画、文件夹和菜单回归通过。
- 未实际更改用户的录屏授权，也未用测试中的模拟导航宣称系统设置专页已目视验证。真机步骤：点击按钮，关闭系统设置，回到应用再次点击，应再次打开；开启LaunchDock录屏权限后返回，确认状态更新，若系统需重启则重启LaunchDock再检查壁纸。测试构建未使用真实签名证书，跨构建权限持续性仍受系统签名身份识别影响。

## Quit & Reopen后背景仍为纯色的排查与修正（2026-11-12）

- 用户已明确是“启动器能打开，但背景仍是纯色”。未重编译前只读检查确认旧进程实际运行/private/tmp/launchdock-app-products/LaunchDock.app，进程采样未见卡死；签名检查显示旧Identifier=LaunchDock、Info.plist not bound、仅链接器临时签名。系统设置读取工具超时，未据此推断用户授权状态；未访问/修改TCC数据库、未重置权限。
- 发现并修复真实代码错误：SDK SCStream.h明确说明SCContentFilter(display:including:)排除桌面背景。现在使用desktopIndependentWindow捕获覆盖目标显示器的壁纸窗口，增加窗口坐标系裁剪和覆盖率检查，不捕获普通应用、不隐藏应用。
- 不再吞掉截图错误。设置显示上次背景结果及具体错误域/码，Debug日志和/tmp/launchdock-wallpaper-PID.json记录permissionGranted、hasImage及status，不保存截图/窗口标题。
- 新增scripts/build-dev.sh：固定开发输出路径、对完整bundle做本地ad-hoc签名、codesign --verify --strict。实际运行脚本成功，Identifier=app.launchdock.LaunchDock，Info.plist entries=21，资源已封存。无Developer ID证书、无公证；ad-hoc每次内容变化仍可能需要重新授权，不能称已修复跨构建授权稳定性。
- 原生构建成功；sh scripts/check-native.sh /tmp/launchdock-app-products退出0、ALL NATIVE CHECKS PASSED。新增多显示器窗口坐标裁剪与具体失败原因断言，既有授权导航、壁纸降级/取消、搜索、全宽动画、文件夹和菜单回归通过。未以这些注入测试冒称真实SCK成功。
- 修复版实际启动PID65514，自身状态明确报告permissionGranted=false、hasImage=false、动态壁纸截图需要屏幕录制授权。已告知用户当前实际仍无授权，并提供移除旧项、重新添加相同路径新开发包、开启并Quit & Reopen步骤；本轮后续不再编译，以免再次改变签名身份。
- 等待用户在系统设置完成授权后，读取新进程状态验证实际SCK结果。当前不能宣称真实动态壁纸捕获完成或背景视觉验证通过。

## 重新授权后仍未生效：临时目录注册问题（2026-11-12）

- 用户重新授权并重启后，实际PID72309仍permissionGranted=false。未重新编译/重签名；codesign --verify --strict通过，指定要求哈希保持fbdb64f3…/215c42d1…。
- 只读系统TCC日志给出明确证据：Failed to match existing code requirement，记录仍为旧构建b5219c97…/e5862fe9…；同时failed to find an Application URL for bundle ID / failed to construct bundle。未读取或修改TCC数据库、未重置隐私权限。
- 对/tmp现有包调用公开LSRegisterURL返回0，但NSWorkspace按Bundle ID解析前后均nil。原样ditto复制到仓库build/Development/LaunchDock.app，签名验证通过，LSRegisterURL返回0且NSWorkspace立即解析到该固定路径。修正此前推荐/tmp开发授权路径的错误。
- 已关闭临时目录实例、打开固定目录同一签名包；PID75124路径正确，仍因旧授权记录为false，已请求用户针对固定目录包移除旧项、重新添加并Quit & Reopen。没有借此再编译或签名。
- 更新build-dev.sh默认输出到仓库build/Development，并新增LSRegisterURL及解析路径一致性检查；脚本sh -n通过，本轮故意不执行完整构建以保留用户正在授权的签名身份。更新README与Manual-QA。历史/tmp产物仍保留供对照，但不再推荐用于授权。
- 当前待用户完成固定目录授权后再读真实结果；没有宣称截图成功。

## 固定目录再次授权后的确认与定向重置（2026-11-12）

- 用户完成固定目录授权重启，新PID78322路径与注册均正确，但进程仍报告permissionGranted=false、hasImage=false。
- 只读TCC日志明确确认：授权修改事件发生后，系统ScreenCapture记录仍要求旧b5219c97…/e5862fe9…，当前实际fbdb64f3…/215c42d1…；AUTHREQ_RESULT为拒绝。此时注册问题已解决，不能继续归因于用户未添加/未重启。
- 通过系统官方工具定向执行 `tccutil reset ScreenCapture app.launchdock.LaunchDock`，退出0且系统确认 Successfully reset ScreenCapture approval status for app.launchdock.LaunchDock。只清除此应用的失效录屏授权记录，没有全局reset、没有修改其他应用权限，也没有直接编辑隐私数据库。
- 已请求用户从当前固定目录版本的设置按钮重新申请/允许并Quit & Reopen，以生成当前代码身份的新授权记录。本轮没有再编译、签名或换路径；真实截图结果仍待这次全新授权后读取。

## 授权成功后实际缺少壁纸窗口，改用系统合成桌面（2026-11-12）

真实结果：

- 用户清旧记录后重新允许并重启，固定目录PID81881终于报告permissionGranted=true。hasImage=false的原因明确是“权限已允许，但系统未提供可捕获的壁纸窗口”。授权问题已经分离，不再让用户为这同一版本重复授权。
- 先前CGWindowList中存在Wallpaper层并不保证它出现在SCShareableContent；实际系统结果证实独立窗口策略不可用。按SDK SCStream.h定义改用display/excludingApplications/exceptingWindows：排除全部可共享应用，例外为空，保留系统合成的桌面背景。

已实现：

- 捕获过滤器includeMenuBar=false，配置showsCursor=false、capturesAudio=false、ignoreShadowsDisplay=true。不再要求壁纸窗口出现在SC列表，不再使用display-including过滤器。
- 显示器排除过滤器仍包含系统Dock，故在截图准备期间激活LaunchDock并应用自身hideDock/hideMenuBar选项，取消/关闭恢复；其他应用不hide/unhide。仍每次打开取一张并固定，准备时取消不重开窗口。
- Info.plist用途说明改用明确的Config/LaunchDock-Info.plist模板。发现仅INFOPLIST_KEY自定义键未进入最终产物，已修复并用PlistBuddy实际读取验证。build-dev.sh签名前检查该键，使用固定中间目录及本机架构，消除切换构建输出路径时SwiftDriver“exit0但无输出”的增量诊断。
- 在候选目录先完成完整原生回归，退出0、ALL NATIVE CHECKS PASSED，包括真实helper窗口层级/可见性连续采样、取消截图准备恢复及搜索/翻页/文件夹/菜单。之后固定开发包最终构建/本地签名/校验/注册成功，并检查二进制实际包含新的excludingApplications选择器和captureStrategy。
- 代码变化产生新哈希，已按事先说明仅清理LaunchDock自己的旧ScreenCapture记录，未影响其他应用。最终用途模板构建在该次reset之后完成，但没有在中间构建期间启动或授权；不存在需保留的中间授权记录。
- 更新README、ADR、Known-Limitations；最终包仍为/Users/yishen/project/launchpad/build/Development/LaunchDock.app。真实新策略截图待最终包重新授权后核实；不把候选/注入测试当作实际截图成功。

最终固定目录产物的完整验证：`LAUNCHDOCK_CHECK_LIFECYCLE=1 sh scripts/check-native.sh /Users/yishen/project/launchpad/build/Development`退出0，ALL NATIVE CHECKS PASSED（包含真实helper窗口顺序持续采样）。已打开最终包PID90225，诊断captureStrategy=display-excluding-all-applications，授权前permissionGranted=false，符合旧记录已清理的预期。已请用户针对这份最终包允许并Quit & Reopen；此后不再改动包内容或签名。

## 最终壁纸实际捕获成功（2026-11-12）

用户为最终包允许并Quit & Reopen后，只读检查真实进程PID90823，路径/Users/yishen/project/launchpad/build/Development/LaunchDock.app。进程自身诊断明确报告：permissionGranted=true、hasImage=true、captureStrategy=display-excluding-all-applications、status=动态壁纸：本次打开时的截图，显示期间固定。至此该机器当前屏幕的系统截图调用与图片取得已实际成功，非注入测试结果。

本轮验证未重新编译、签名、复制应用包或更改系统权限。保留当前包身份。尚未目视验证截图中桌面图标/Dock完全排除、壁纸模糊色彩一致性、多显示器及不同Space；这些仍按Manual-QA验证，不由hasImage=true推断全部视觉验收通过。

## 用户反馈截图仍黑：排除所有应用误排除壁纸进程（2026-11-12）

- 用户截图证明此前“hasImage=true”的验收不足：图片可能是黑色。已向用户明确纠正过早的成功报告。此问题不再归因于录屏授权。
- 只读背景元数据证实Wallpaper PID504、bundle com.apple.wallpaper.agent、layer -2147483625；排除全部应用恰好把壁纸像素来源也排除了。并非SwiftUI模糊必然渲染黑色。
- 修复过滤：从CG窗口元数据获取目标屏幕桌面层及以下背景ownerPID/windowID，保留提供者，排除其他应用；提供者拥有的非桌面窗口作为exceptingWindows排除，防其设置面板、Dock等普通窗口混入。保留既有自身Dock/菜单栏展示管理及光标/音频排除。
- 添加真实像素统计（32×32），纯黑/近透明动态截图不再作为成功。Debug状态增加capturePixelStatistics.peakRGB/meanRGB/meanAlpha，策略display-preserving-desktop-providers。无截图持久化，只有数值和状态。纯黑动态壁纸会保守降级，作为已知限制；静态黑图文件正常显示。
- 候选目录构建退出0。`LAUNCHDOCK_CHECK_LIFECYCLE=1 sh scripts/check-native.sh /tmp/launchdock-wallpaper-review`退出0，ALL NATIVE CHECKS PASSED。新增黑图失败断言、背景提供者/非背景窗口/其他屏幕分类断言；实际NSHostingView缓存渲染采样确认彩色壁纸经过模糊与遮罩仍有色。搜索、菜单、整页动画、文件夹及真实helper层级/可见性连续采样回归通过。
- `sh scripts/build-dev.sh`最终固定目录构建、本地ad-hoc签名、签名校验及路径注册成功；包内容SHA256=7f1bd5c702bfb5b2cf3f4ac807ba7c8c9d96c9af2e20d66e1603527a2a57f7d2（Contents/MacOS/LaunchDock）。为避免新代码哈希与旧授权冲突，仅清理LaunchDock自己的ScreenCapture记录，系统确认成功；已打开新包并请用户允许、Quit & Reopen。
- 等待这份包的真实截图像素数据，不能将候选测试或image非nil称为壁纸视觉成功。未重新引入隐藏/恢复其他应用。

黑屏修复版真实运行验证：用户重新允许并重启后，PID2713、固定路径正确，permissionGranted=true、hasImage=true、captureStrategy=display-preserving-desktop-providers。实际截图像素统计meanAlpha=1、meanRGB=0.56648029003267975、peakRGB=1，证明这次实际图片不透明且不是纯黑，已通过新增内容检查。此轮未重新编译或更改签名。桌面壁纸匹配、Dock/图标无混入和最终模糊观感仍需用户目视确认，不能由平均RGB推出完整视觉一致性。

## 研究BuhoLaunchpad免录屏背景（2026-11-12）

按用户指定官网及本地2.0.2包只读研究，未修改/构建运行应用或权限。发现Server可执行文件同时具有desktopImageURLForScreen文件读取、CGWindowListCopyWindowInfo桌面窗口查找、CGWindowListCreateImage图像捕获，以及macOS27分支的私有SkyLight/CGSHWCaptureWindowList调用；已追到实际调用点，不能只凭导入符号断言当前运行分支。Apple WWDC19官方说明桌面背景（不含图标）是旧CG捕获权限的例外，解释了不授录屏也能得到背景的机制；现代SDK已废止旧API，私有兼容需另行评估。

同时核实DefaultDesktop.heic是有效软链接，实际指向DefaultAerial.heic，ImageIO可读，主图是太浩湖图片。更正此前仅凭Default文件名一概拒绝的判断：是否匹配用户当前壁纸仍需核实。详细证据、地址和来源记录在docs/Research/BuhoLaunchpad-Wallpaper.md。本轮不更改现有LaunchDock实现、不重编译/重签名，不影响已完成的录屏授权。

## 按Buho类似路线实现免录屏壁纸（2026-11-12）

已实现：

- 移除ScreenCaptureKit、显示器截图过滤、CGPreflight/CGRequestScreenCaptureAccess、ScreenCapturePermission及其设置按钮、录屏用途声明。生产代码不再查询或申请录屏授权，也没有其他应用hide/unhide。
- 新增隔离的DesktopWallpaperReader：只读取目标显示器完整桌面背景层窗口，优先Dock背景面；macOS26动态解析已废止CoreGraphics桌面图像接口，macOS27隔离SkyLight私有兼容分支。绝不传入普通应用、桌面图标、小窗口或其他屏幕窗口ID；未知未来系统/符号不可用时回退文件，不发起录屏申请。
- 普通静态图优先文件，HEIC/动态代理/不可读资源优先桌面背景图像；文件回退使用ImageIO主图索引，DefaultDesktop有效资源不再按名字拒绝。保持每次打开刷新、显示期间固定，以及实际非黑像素检查。
- 设置仅显示背景状态及自动回退说明；删除旧授权操作文案。更新README、Manual-QA、Known-Limitations，新增ADR0003；macOS27私有兼容为明确未真机验证项。

实际测试：

- 候选构建成功。完整 `LAUNCHDOCK_CHECK_LIFECYCLE=1 sh scripts/check-native.sh /tmp/launchdock-no-permission-products`退出0，ALL NATIVE CHECKS PASSED；覆盖文件实际像素、有效DefaultDesktop资源回退、桌面窗口范围、黑图拒绝、关闭准备取消、真实SwiftUI模糊颜色、搜索、菜单、整页动画、文件夹及真实helper层级/可见性持续采样。
- 新增可重复 `sh scripts/check-wallpaper-no-permission.sh`：全新Bundle ID、Launch Services独立启动、从未授录屏，实际screenRecordingGranted=false，同时desktop-window-coregraphics得到hasContent=true、meanAlpha=1、meanRGB≈0.548981、peakRGB≈0.996078。此为真实系统接口结果，不是注入图片或依赖宿主已授权的命令行结果。第一次裸CLI探针preflight=true不计免权限通过，随后改独立App解决身份归属并验证false。
- 独立探针输出壁纸预览/tmp/launchdock-wallpaper-probe.WNtdh8/wallpaper-preview.png，已用view_image目视确认实际粉紫/蓝几何壁纸，无菜单栏、Dock、桌面图标或应用窗口。预览仅用于诊断，不是应用后台持久化策略。
- 最终 `sh scripts/build-dev.sh`构建、本地ad-hoc签名和固定路径注册成功。包级检查确认无ScreenCaptureKit链接、无CGRequest/CGPreflight符号、无NSScreenCaptureUsageDescription。
- 使用系统tccutil只撤销LaunchDock自己的旧ScreenCapture批准，系统确认成功；此后主应用PID34924重新启动仍hasImage=true、requiresScreenRecording=false、strategy=desktop-window-no-recording，像素meanRGB≈0.548981、meanAlpha=1。无需用户重新授权。
- 最终固定目录产物完整回归 `LAUNCHDOCK_CHECK_LIFECYCLE=1 sh scripts/check-native.sh /Users/yishen/project/launchpad/build/Development`再次退出0、ALL NATIVE CHECKS PASSED。

未验证：

- 当前主机macOS26.6.2已完成免录屏实际读取与预览；macOS27私有ABI、Intel硬件、多显示器/不同Space与缩放的实际匹配仍须真机验收。未来系统文件回退已实现，但未宣称所有提供器都能匹配实时动态帧。
- 完整主界面的最终模糊视觉仍可由用户确认；彩色背景原生渲染测试通过。未使用真实发行证书或公证，没有编造签名发行产物。

## 禁用文件夹及应用名称文字选择（2026-11-12）

- 根页图标名称使用的wrappingLabelWithString默认可选择；AppCell现显式设置isSelectable=false、isEditable=false，名称只作为展示标签。应用与文件夹共用此标签，搜索框保持可编辑。
- 实际验证：sh scripts/build-dev.sh退出0，构建、本地签名与注册成功；sh scripts/check-native.sh /Users/yishen/project/launchpad/build/Development退出0并输出ALL NATIVE CHECKS PASSED，名称区域菜单命中、长按、搜索编辑、文件夹开关/拖出、分页和背景回归通过。
- 上次记录/重启复合命令因自动审批额度限制未执行，此次继续补记。未新增仅复述属性赋值的测试；真实鼠标悬停的光标样式仍待目视确认。验证步骤：悬停/拖动名称不应选中文字或出现文字编辑光标，正常点击与长按图标仍应可用。

## 修复全屏 Space 唤起与原生测试崩溃（2026-11-12）

已实现：

- 启动器改为创建时带 nonactivatingPanel 的 NSPanel，支持 key/search、禁止 main，不再通过激活 LaunchDock 唤起；使用公开的跨应用全屏面板行为，移除 moveToActiveSpace，保留当前 Space。切换 Space 或失去 key 时关闭。设置窗口按用户操作正常激活。详见 ADR0004。
- 用户贴出的崩溃属于 launchdock-native-checks，而非 LaunchDock 主应用；旧 precondition 在全屏 helper 未就绪时触发 SIGTRAP。改为带文件/行号的 throwing 检查，正常打印 FAIL 并返回 1，保留严格失败条件，确保 defer 执行。
- 测试初始分页等待实际数据投影完成，避免只等待容量赋值就立即检查旧 grid。滚轮路由使用单次跨阈值事件，避免多个耗时快照处理跨过翻页节流周期后仍假设只翻一页。
- 每轮脚本使用独立源码副本/可执行文件/日志；默认构建目录修正为 build/Development。退出/中断写 quit 标记，helper 也有 120 秒超时保护。
- 全屏专项驱动改为 Launch Services 独立 App。裸 Cocoa CLI 运行时实际前台仍为 Codex，helper 前置条件超时；独立 App 后 helper 确实完成全屏。open -W 不传播 App 退出状态，因此另外要求原子写入结果文件，缺失结果也必须失败。

实际测试：

- sh -n scripts/check-native.sh scripts/check-fullscreen.sh 通过。
- 普通原生回归 /tmp/launchdock-space-products 退出 0，ALL NATIVE CHECKS PASSED：背景像素、搜索、菜单、分页、文件夹动画及拖出/解散通过。
- 故意失败检查返回 1 并打印 FAIL，无 SIGTRAP。独立 App 模式故意失败写出 result=1；未把 open -W 的 0 当作测试成功。
- 全屏前置条件超时的一轮正常返回 1，已确认 helper PID65285 退出、quit 标记存在；未弹测试断言崩溃。
- 修复独立应用身份后 sh scripts/check-fullscreen.sh /tmp/launchdock-space-products 退出 0。真实 helper PID66717：entered=true/fullscreen=true/onActiveSpace=true/active=true；3 次启动器显示、搜索键盘输入与关闭保持原 Space/frontmost，ALL NATIVE CHECKS PASSED。helper 随后已退出。
- sh scripts/build-dev.sh 退出 0，固定目录构建、本地 ad-hoc 签名与注册成功。没有真实发行证书或公证。

未验证：Chrome/Safari 实际视频全屏、DRM、Stage Manager、多显示器 Space 仍需人工验收，步骤已补充 Manual-QA。原生全屏 helper 通过不等于这些场景均通过。

补充最终验证：`LAUNCHDOCK_CHECK_LIFECYCLE=1 sh scripts/check-native.sh /Users/yishen/project/launchpad/build/Development` 在滚轮事件修正后退出 0、ALL NATIVE CHECKS PASSED；设置开关重开、真实辅助应用窗口可见性与层级持续采样均通过。上一轮滚轮检查失败已明确保留为测试时序问题，没有将失败记录算作通过。

## 恢复可见的启动器与文件夹开关动画（2026-11-12）

已实现：

- 实测当前系统 accessibilityDisplayShouldReduceMotion=false。启动器由隐式 NSWindow animator 改为主线程显式驱动 alpha：打开 300ms、关闭 260ms，smoothstep 缓动；关闭完成才 orderOut。快速反向开关从当前透明度继续，取消旧任务并保留 presentationGeneration 防过期完成回调。减少动态效果时使用短淡变，不做空间运动。
- 文件夹保持持久容器与冻结布局，加入 280ms 居中 0.94→1 / 1→0.94 缩放并保留淡入淡出。缩放仅作用于合成图层，不改 NSView/网格布局尺寸；关闭后才隐藏。首次打开强制从 0.94 开始，修复初版因 presentation layer 为单位变换而没有实际缩放的问题。
- 增加真实中间帧检查：文件夹 scale/opacity、启动器窗口 alpha 均须在开关过程中处于端点之间，继续检查尺寸、滚动条、根网格稳定和反向开关。
- 生命周期测试也统一通过 Launch Services 独立 App 启动。裸 CLI 一轮虽动画检查通过，但辅助窗口可见性检查未就绪；独立身份后完整回归通过，不把失败轮计为通过。

实际测试：

- sh scripts/build-dev.sh 退出 0，固定目录应用构建、本地 ad-hoc 签名和注册成功。
- LAUNCHDOCK_CHECK_LIFECYCLE=1 sh scripts/check-native.sh 退出 0，ALL NATIVE CHECKS PASSED，日志 /tmp/launchdock-window-checks.WnSAK1/check.log。包含动画真实中间帧、文件夹尺寸稳定、无滚动条、根网格复用、快速反向开关、设置重开及其他应用窗口层级保持。

未验证：用户实际观看的动画流畅度、多屏不同刷新率和减少动态效果开关后的视觉仍待人工验收；不以代码中存在动画或仅有最终状态代替中间帧验证。

补充最终验证：`sh scripts/check-fullscreen.sh` 在最终 build/Development 上退出 0、ALL NATIVE CHECKS PASSED（/tmp/launchdock-window-checks.5CAv1p/check.log），3 次真实独立全屏 Space 开关与搜索均保持原 Space/frontmost。没有将原生 helper 结果泛化为所有浏览器/DRM 场景。

## 修复多个文件夹交替打开时内容残留（2026-11-12）

已实现：FolderOverlayView 继续复用外层原生动画容器，内部 FolderPanel 以 folder.id 标识身份。原先 SwiftUI 复用了第一个 CollectionGrid，而其 folderContextID 只在创建时绑定；打开第二个文件夹时旧网格被防关闭闪烁逻辑冻结，残留前一个内容。现在不同文件夹重建内部网格和局部分页状态，同一文件夹数据更新仍复用，根页面不重建。

实际测试：新增两个真实布局文件夹交替打开 4 次，检查 active grid 的文件夹 ID、实际成员顺序和已渲染名称；每次只等待关闭 60ms 就打开另一文件夹，覆盖动画中断。修改前稳定复现 FAIL: Opening another folder must expose its active grid，修改后此检查通过。原动画中间帧、面板尺寸、无滚动条、根网格复用、拖出及解散也通过。

sh scripts/build-dev.sh 退出 0，固定目录构建与本地 ad-hoc 签名成功。第一次完整生命周期检查在上述项目均通过后，因辅助窗口尚未可见而失败，未算作整套通过；该检查已改为最多 5 秒等待实际窗口就绪，保留严格窗口数量与层级断言。

未验证：用户已有布局下大量文件夹、不同页数与多屏视觉仍需人工确认；未改用户布局数据，也未添加权限。

最终完整回归：`LAUNCHDOCK_CHECK_LIFECYCLE=1 sh scripts/check-native.sh` 退出 0、ALL NATIVE CHECKS PASSED，日志 /tmp/launchdock-window-checks.8HJx0l/check.log；交替文件夹、关闭动画中断、窗口层级及设置生命周期均通过。

## 独立通用 App 与安装镜像（2026-11-12）

已实现：

- 新增 scripts/package-release.sh：明确构建 Xcode App target 的 Release arm64+x86_64 通用二进制；同名共享 scheme 实际解析为 package 命令行可执行程序的问题已发现并避开，不把其成功退出当作 App 打包成功。
- 生成 dist/LaunchDock.app、LaunchDock-1.0.0-universal-preview.dmg、同名 ZIP、中文安装说明、SHA256SUMS.txt 与 Verification.json。DMG 内含 Applications 拖拽目标，App 可直接复制安装；不需要 Xcode、Homebrew 或第三方运行环境。
- 原创网格图标由系统 AppKit 渲染为 ICNS，加入 App 后统一 ad-hoc + hardened runtime 签名。新增 scripts/verify-release.py 检查真实 App 结构、最低版本、图标、两个架构和所有 Mach-O 动态依赖，当前只依赖 /System/Library 与 /usr/lib 系统库，核心库静态链接。
- 更新 README、Release.md 和随包安装/升级/卸载说明。最低 macOS26.0，预览版不宣称规范所有验收通过。

实际测试：

- sh scripts/package-release.sh 退出 0，codesign --verify --deep --strict 通过；lipo 确认 x86_64、arm64；两种架构依赖验证 externalDependencies=[]。
- hdiutil verify 对最终 DMG 返回 VALID；实际只读挂载后对包内 App 重跑验证，通过并复制到独立安装位置。ZIP 用系统 ditto 解压，再次验证签名、架构和依赖通过。
- dist 内 shasum -a 256 -c SHA256SUMS.txt：DMG、ZIP 均 OK。第一次从仓库根执行相对路径校验失败，改在 dist 正确目录后通过，未将失败算作包损坏或通过。
- codesign 实际为 Signature=adhoc、TeamIdentifier=not set；spctl --assess 实际 rejected。security find-identity 返回 0 个有效身份，当前没有可用 Developer ID，未公证；不会把本地签名当成互联网发行签名。

未验证/限制：

- Intel 真机、没有 Xcode 的干净 Mac、实际网络下载后的首次打开及管理设备策略仍需外机验收。通用架构与系统库检查不等于这些实际验收已完成。
- 他人可复制安装，但下载后可能需按 Apple 官方流程在“隐私与安全性 → 仍要打开”确认。要提供 Gatekeeper 正常放行的发行包，还需要用户提供 Developer ID Application 证书与公证账号/profile；本轮没有编造签名、公证或已接受的发行产物，也未关闭系统安全检查。

补充安装启动实测：从只读 DMG 复制到 /tmp/launchdock-package-qa/Installed/LaunchDock.app，经 Launch Services 独立启动，实际 PID91025、bundleURL 对应复制位置、isTerminated=false、visibleWindows=1；随后退出安装副本并恢复原开发版。探针先以 activates=true 启动时受前台激活切换影响而隐藏（进程未退出、无可见窗口），临时探针还曾因顶层 throws 自身报 SIGTRAP，均未计为应用启动通过。探针改为正常报错与非激活启动方式后实际通过。该主机仍安装有 Xcode，不能将这项复制路径实测冒充干净外机已验收；无开发路径依赖结论另由两个架构的动态库检查支撑。

交付文件：dist/LaunchDock-1.0.0-universal-preview.dmg（约2MB）与ZIP，校验值见dist/SHA256SUMS.txt。可安装预览版已完成，Developer ID/Apple 公证发行仍缺真实账号证书，未谎称完成。

## 设置精简、图标可见性与文件夹标题编辑（1.0.1，2026-11-12）

已实现：

- 通用页新增“隐藏菜单栏图标”“隐藏 Dock 图标”，默认均关闭，AppStorage 持久保存并立即生效；菜单栏通过 NSStatusItem.isVisible，Dock 通过 regular/accessory 激活策略切换，启动时恢复选择。保留快捷键、触发角及访达打开入口，不调用其他应用 hide/unhide。
- 移除独立“触发角”tab，通用页使用关闭/四角单选下拉菜单。移除 Option 选项与采样限制，refresh 清理旧 hotCornerOption 偏好，旧版开启者不会留下隐形限制。
- 删除“测试显示入口”和外观浅色/深色选择，移除主视图、文件夹和搜索控件强制 dark 外观。系统外观自然继承，壁纸上的图标标签与标题仍为白色。
- 仅打开文件夹时顶部标题可点击改名；原生文本编辑支持 Enter 保存、Esc 取消、失焦/离开提交，沿用 LayoutEngine 的 1–40 字校验、去首尾空白及版本化持久化。根网格标签仍不可编辑或选择。修复重复设置原生焦点会提前结束编辑的问题，并在 field editor 结束回写后恢复规范化/取消的名称。
- build-dev.sh 对已安装同 Bundle ID 副本不再强行要求 Launch Services 优先指向开发目录；校验显式包的注册、Bundle ID 和可执行文件。以前安装了副本会误报注册失败，现在正常提示并支持按路径打开，不改用户已安装副本。
- 打包脚本版本更新至 1.0.1 / build2026111202，更新安装说明、README 与 Manual-QA。

实际测试：

- sh scripts/build-dev.sh 退出0，本地构建、ad-hoc签名及包验证成功。
- sh scripts/check-hot-corner.sh 退出0：真实计时器、单选迁移、即时触发、重入锁存、旧 Option 清理、拖动抑制、关闭检测全部通过。
- LAUNCHDOCK_CHECK_LIFECYCLE=1 sh scripts/check-native.sh 退出0，ALL NATIVE CHECKS PASSED（/tmp/launchdock-window-checks.OOoE6x/check.log）：真实标题点击/原生输入/Return提交/空白修剪/Esc取消/空名称拒绝/磁盘重载通过；实际 NSStatusItem 与 NSApplication Dock 策略隐藏恢复通过；文件夹交替内容、动画中间帧、尺寸稳定、拖出/解散、设置重开及其他应用层级回归通过。
- 初始标题测试两次失败、后续诊断确认重复 makeFirstResponder + selectText 使编辑提前结束；修复后原断言通过，未放宽到只检查最终任一名称。首次编译后的注册失败为已安装副本选择误报，未宣称此前脚本成功。
- sh scripts/package-release.sh 退出0：dist/LaunchDock-1.0.1-universal-preview.dmg 与 ZIP 生成；arm64/x86_64、系统库依赖、ad-hoc签名、hdiutil镜像校验通过。dist 内 SHA256SUMS.txt 的两项校验均OK。

未验证：

- 尝试 NSHostingView 设置页截图缓存只得到空画面，未计作视觉验证，已删除无效截图输出；实际设置窗口可见/可聚焦测试通过。系统浅深切换的最终视觉、中文候选输入、VoiceOver、多屏与隐藏图标后的手动重启仍待用户/真机目视验收，步骤已写入 Manual-QA。
- 安装包仍为 ad-hoc 未公证预览版，不宣称新增功能已完成 Intel 外机、干净机器或所有浏览器 DRM 场景验收。

补充全屏验证：首次把测试驱动过早改为 accessory，辅助应用未取得前台（实际 frontmost=Chrome），20秒前置条件超时，正常退出1，未计为通过。调整为先由常规驱动向真正全屏 helper 交接激活，再把被测启动器设为 accessory 后，`sh scripts/check-fullscreen.sh` 退出0、ALL NATIVE CHECKS PASSED（/tmp/launchdock-window-checks.6VjJnr/check.log）。隐藏 Dock 图标模式下连续3次真实独立全屏 Space 显示、搜索与关闭，Space/frontmost 均保持。Chrome/DRM与多屏人工场景仍未泛化。

## 移除 CoreServices 应用来源及精简设置（2026-11-12）

已实现：默认扫描目录移除 /System/Library/CoreServices/Applications，并在扫描入口显式排除该路径及子项。旧 catalog 在加载及扫描合并时过滤相应记录，旧布局通过现有 reconcile 清理引用，避免七天缺失保留期仍显示这些应用；其他来源与用户布局继续保留。图标大小移动到通用页，删除“上次背景”和自动壁纸说明；外观页已无其他内容，整体移除。

实际检查：sh scripts/build-dev.sh 退出0，编译、本地签名及显式包验证成功。源码定向检查确认图标大小仅在通用页，旧外观页和两段背景说明已移除。

按用户最新要求：本轮不执行完整测试用例，不生成或更新 DMG/ZIP；仅构建并重启开发应用。已有 dist 安装包仍是上一轮内容。目视设置布局、其他目录扫描与完整交互回归未重跑。

## 访达定位时隐藏启动器（2026-11-12）

已实现：根网格及文件夹共用的 item 菜单“在访达中显示”取得有效目标 URL 后，先调用现有 hide 回调开始关闭启动器，再让 NSWorkspace 定位目标；无有效 URL 时不隐藏，菜单原有可用性规则保留。

实际检查：sh scripts/build-dev.sh 退出0，编译、本地签名及包验证通过。按用户要求仅构建并重启，不执行完整测试、不实际替用户打开访达目标、不更新 DMG；菜单点击后的目视效果待用户确认。

## 首次系统应用归类与文件夹按数量增高（2026-11-12）

已实现：

- AppRecord 通过系统应用路径识别内置应用，兼容系统 Cryptex 应用位置及 Safari 固定位置，不仅凭 com.apple Bundle ID 判定；另行安装的 Xcode/Pages 等不会因此算作内置。
- 全新空布局首次 reconcile 时，把非常用内置应用归入“系统工具”，默认排除系统设置、终端、App Store、Safari、预览，保留在根页面。先做系统归类再做实体目录归类，避免终端又被 Utilities 文件夹收走。新增可兼容旧数据的可选 systemAppGroupingVersion，后续扫描不重新聚合用户移出的项目，已有非空布局不自动重排。
- FolderGridGeometry 按项目数、列数及屏幕可用高度算行数；移除文件夹固定3行与55%屏高上限。宽度仍为88%，高度逐行增加，接近屏幕限制时压缩行距，容纳不下才横向分页。标题、内边距、页码和屏幕边距预留共240pt；原生 collection 与面板共用行数上限，避免容量/页码不一致。
- 容量异步回写绑定 folderContextID，快速切换文件夹时前一文件夹不能覆盖后一文件夹的容量；关闭时继续冻结旧内容与几何。

实际检查：轻量聚焦逻辑检查通过：初始化系统归类、常用应用留根、非内置 Apple 应用排除、已有布局不重排、手动移出后扫描不重组；2/14/21/28/70项目高度与容量一致，较高屏幕可达6行并超过旧3行限制。sh scripts/build-dev.sh 最终退出0，编译、本地签名和包验证通过。

按用户要求未执行完整测试、未更新DMG/ZIP。现有用户布局未重置，新初始化规则只在新布局生效；当前布局的系统工具可继续手动整理。真实窗口下多种图标大小、不同屏幕/缩放、分页动画与关闭防闪烁未重跑完整原生检查，待目视验收。随后重启开发App加载新代码。

## 文件夹重新打开直接显示第一页（2026-11-12）

已实现：每次打开文件夹生成新的内部 presentationID，重建该次 FolderPanel 的分页状态与原生 collection，避免同一文件夹保留的 lastRenderedPage=第二页在重新打开时把归零误判成翻页。外层动画容器和根网格仍复用，正常文件夹开关动画、打开后的手动翻页动画保留。folder 切换到不同ID时也统一归零，覆盖直接从一个文件夹切到另一个的情况。

验证范围：按用户要求仅构建并重启，未运行完整测试或更新DMG；实际多页关闭重开、快速反向重开及分页动画视觉待用户确认。

本轮 sh scripts/build-dev.sh 退出0，编译、本地签名及包验证通过；旧进程保存退出后已打开新开发版。

## 已卸载应用扫描后立即清理（2026-11-12）

原因证据：实际缓存 /Applications/Trae.app 已有 missingSince，inaccessible=false，磁盘路径也不存在；说明扫描已执行，但旧合并逻辑会保留7天，并在任意其他扫描失败时继续保留，导致手动重扫/重启仍显示空白图标。

已实现：所属目录可读且未发现的旧应用立即删除，不再标记后保留七天；只对失败路径及其子项保留 inaccessible 记录，其他目录失败不影响已卸载项清理。无磁盘路径的显式导入占位仍保留。扫描期间再次请求不再直接丢弃，改为排队补扫；拖动期间仍延迟扫描。按 Bundle ID 排除所有 LaunchDock 自身副本并清理相应旧缓存，修复运行开发版时安装副本出现在网格的问题。Requirements 对应规则已按用户反馈更新，原始附件未改。

验证范围：本轮只做临时目录聚焦验证、构建、重启，不执行完整测试、不更新DMG；真实 FSEvents 卸载事件时序与扫描中再次点击按钮未做完整原生验收。没有删除、移动或卸载任何用户应用。

实际结果：临时目录聚焦检查退出0，卸载即时清理、无关目录失败不阻止清理、不可读目录保护、恢复读取、自身副本排除与布局 reconcile 均通过。sh scripts/build-dev.sh 退出0。保存退出旧进程并重启后读取真实持久化 catalog，Trae 与 LaunchDock 自身副本剩余0项，目录共80条，layout revision=133；不是仅根据构建成功推断已清理。

## 完整自动化回归与菜单栏应用扫描修复（1.0.2，2026-11-12）

新增问题证据：本机 /Applications/Raycast.app（com.raycast.macos）与 /Applications/iRightMouse Pro.app（cn.better365.iRightMousePro）均为 APPL、LSUIElement=true、未设置 LSBackgroundOnly，被旧的 LSUIElement 全量过滤误排除。现允许正常菜单栏应用，仅过滤纯后台应用、隐藏项目、排除来源及自身副本；不需要更改第三方 App 或申请权限。Requirements 相应条款同步更新。

本轮完整自动化检查：

- 更新前 Swift 测试18项通过；新增有行为意义的回归后，swift test --scratch-path build/SwiftTests 全部22项通过。新增覆盖菜单栏应用可发现/搜索、纯后台与自身排除、卸载即时清理及权限失败隔离、初始化系统归类/常用排除/已有布局保留、文件夹高度与容量一致。日志 /tmp/launchdock-full-swift-tests.log。
- swift run --scratch-path build/SwiftTests CoreChecks 退出0，6个核心场景、1000次确定性布局操作通过；日志 /tmp/launchdock-full-corechecks.log。
- sh scripts/build-dev.sh 构建、本地签名及包验证通过。
- LAUNCHDOCK_CHECK_LIFECYCLE=1 sh scripts/check-native.sh 退出0，ALL NATIVE CHECKS PASSED（/tmp/launchdock-window-checks.Xyc1P1/check.log）。保留文件夹实际尺寸范围断言并按新自适应高度需求更新旧65%上限；新增多页关闭后重开第一页且无PageSnapshot横滑检查，包含关闭未完成就重开。搜索、菜单、改名持久化、动画中间帧、根网格稳定、拖出/解散、设置及图标可见性切换、真实辅助窗口层级全部通过。
- sh scripts/check-hot-corner.sh 退出0，实际计时器回归通过。
- sh scripts/check-fullscreen.sh 退出0，ALL NATIVE CHECKS PASSED（/tmp/launchdock-window-checks.TbAzQt/check.log）。真实独立全屏helper entered/onActiveSpace/active=true，隐藏Dock图标模式连续3次显示、搜索和关闭保持Space与前台。
- sh scripts/check-wallpaper-no-permission.sh 退出0；新应用身份 screenRecordingGranted=false、hasContent=true、meanAlpha=1、meanRGB≈0.40456。已查看真实壁纸预览，粉紫蓝几何壁纸无应用窗口、图标、菜单或Dock混入；目录 /tmp/launchdock-wallpaper-probe.5RBHRv。

未验证：完整自动化通过不等于Intel/干净外机、不同屏幕和刷新率、Stage Manager、中文IME/VoiceOver及所有浏览器DRM全屏的人工验收完成。当前仍无Developer ID身份（实际查询0个），不会声称Apple公证发行。

1.0.2 最终交付验证：sh scripts/package-release.sh 退出0，通用 Release（arm64+x86_64）无外部动态库依赖，ad-hoc + hardened runtime 签名校验通过，DMG hdiutil verify VALID。实际只读挂载DMG并复制App、解压ZIP后分别再做签名/架构/依赖验证，均通过；dist 内 SHA256SUMS.txt 两项均OK。

从DMG复制的App实际启动成功（build/ReleaseValidation/Installed/LaunchDock.app），校验其真实窗口可见。随后读取实际持久化 catalog/layout 并构建搜索索引，确认 com.raycast.macos 和 cn.better365.iRightMousePro 均存在、处于可见布局且可按名称搜索；不是仅用模拟清单推断。运行验证记录 build/ReleaseValidation/runtime.json。验证副本正常退出后，已打开 dist/LaunchDock.app 最终1.0.2版。

交付：dist/LaunchDock-1.0.2-universal-preview.dmg，2157550字节；同目录有ZIP、校验值和Verification.json。当前没有Developer ID身份，仍为未公证预览包；不声称干净外机/Intel人工验收、Gatekeeper公证或全部规范验收完成。

## 应用启动反馈与跨启动图标缓存（2026-11-13）

已实现：

- 修复点击后等待 NSWorkspace 启动完成才隐藏的问题：先触发图标 1→1.2 放大，140ms 后调用现有隐藏动画，启动请求转到独立任务；成功回调只清除 pending，不再关闭用户后来重开的启动器。保留重复点击抑制，启动失败会带错误重新显示。搜索/键盘启动同样走此流程，减少动态效果时不放大。
- 图标添加256px PNG磁盘缓存与版本化 index-v1.json，默认位于 ~/Library/Caches/app.launchdock.LaunchDock/Icons-v1。启动先恢复 catalog 和缓存压缩图片，再扫描；可见格子从内存字节创建图像，不在 cell 渲染时同步访问 NSWorkspace 或文件。避免显示入口在缓存恢复前抢先扫描。测试/独立 dataDirectory 使用各自临时图标目录。
- actor 后台串行检查包路径、版本、目录/Info.plist/图标资源/Assets.car 的大小及精确修改时间，只在变更时提取。优先读取声明图标资源，其他格式回退系统图标接口；仅 PNG Data 跨执行器，图标读取与绘制实测非主线程。旧图持续显示至新图就绪，相同像素不重复通知，32ms合并更新，64MB解码缓存；内存图像被淘汰时仍可从压缩字节立即恢复。
- 缓存原子写入、版本检查、尺寸及解码有效性校验，损坏图片自动重取，缓存不可写时仍可显示新图。刷新请求遇到正在加载的同一图标会排队补查，不丢热更新请求。保留用户布局/来源/排序，不改用户其他App。
- 新增 IconCache.swift 和 NativeChecks/LaunchIconChecks.swift，仅向 Xcode 工程增加对应源文件，不整体重生成现有工程。更新原生检查编译列表。

实际检查：sh scripts/check-native.sh 最终退出0、ALL NATIVE CHECKS PASSED；日志 /tmp/launchdock-launch-icon-check.log。新增验证覆盖后台渲染256px、跨缓存实例磁盘复用、未变化不重复提取、真实PNG资源热更新、损坏回退、慢启动完成前已经隐藏、重复请求、失败反馈，以及原生图标放大的真实中间帧。原搜索、菜单、改名/落盘、文件夹开关/高度/重开第一页/拖出和分页检查均通过。

检查修正记录：首次新检查将 await 放进同步断言 autoclosure，编译失败，已改为先读取actor结果；PNG夹具先使用动态系统色导致无效色彩空间，随后改为明确RGB。色彩管理后红色RGB为1/0.149/0，原过严数值断言失败，改按红绿主色及分量差验证，保留实际像素与热更新断言，未把失败轮计为通过。

未验证：尚未重启操作系统来测真正冷开机性能；第一次升级没有旧磁盘图标时需后台建立缓存，之后才可跨启动复用。不同屏幕色彩配置、特殊资产目录/图标提供器、超大量应用和长时间压力仍待人工验收。本轮不生成新的DMG，已有dist/1.0.2安装包不包含这些修改。

最终构建 sh scripts/build-dev.sh 退出0，已保存退出旧版并重启开发App。实际用户缓存目录已写入86份PNG，合计3106880字节，index版本1；随后再次重启，观察86份既有PNG全部保持原修改时间，未重新提取/覆盖。此为真实进程重启复用验证，仍不能替代操作系统冷开机时延测量。

## 作者邮箱与0.0.1-beta安装包（2026-11-13）

已实现：“关于”新增一行“作者信息：yishen@mdashen.com”，邮箱使用SwiftUI Link指向mailto:yishen@mdashen.com。显示版本由LaunchDockDisplayVersion读取，设置为0.0.1-beta；系统CFBundleShortVersionString及Xcode MARKETING_VERSION使用合法数字0.0.1，打包build为2026111301。工程生成器同步默认数字版本，但未整体重生成工程。

实际验证：sh scripts/package-release.sh退出0；通用Release包含arm64/x86_64和最新启动反馈/图标缓存代码。签名严格验证、系统库依赖验证、hdiutil镜像完整性均通过；实际挂载最终DMG，再次验证包内显示版本0.0.1-beta、数字版本0.0.1和编译进二进制的mailto作者链接，全部通过。DMG及ZIP的SHA256SUMS校验均OK。

交付：dist/LaunchDock-0.0.1-beta-universal.dmg及同名ZIP。仍为本地ad-hoc未公证包，无Developer ID发行签名。本轮修改为作者信息/版本及打包，没有重跑完整交互测试，也没有实际打开邮箱或发送任何邮件；关于页链接交互与最终目视待用户确认。

重启时发现旧开发进程PID63876未能正常退出。只读sample确认其主线程停在AppCoordinator.restart()异步任务中的NSApplication.terminate，等待terminateLater；新的MainActor保存/回复任务无法在该任务阻塞时完成。restart()在此之前已await store.flush()，已对新包增加restartAlreadySaved分支，保存完成后的重启直接停止服务并返回terminateNow，不再重复等待第二次保存。普通退出仍保留原保存流程。已重新构建beta包纳入修复；当前旧进程没有被强制结束，也没有声称已打开新beta。采样保存在/tmp/launchdock-quit-sample.txt。

## 横屏宣传视频（2026-11-14）

已实现：生成 `media/LaunchDock-Promo-1080p.mp4`，28秒、1920×1080、30fps，H.264/AAC。采用简洁的紫蓝品牌画面、中文字幕及原创合成轻配乐，介绍网格浏览、搜索启动、拖拽建文件夹；片尾简述触发角，并展示作者邮箱。素材直接录制仓库真实原生LauncherView，使用86个真实扫描结果中的24个应用，在临时目录建立演示布局，没有修改用户的排列或偏好。搜索、启动和文件夹变更由脚本驱动真实控件/引擎，后期叠加演示指针；不是模拟UI。源码与可重复生成脚本保存在Promo/和scripts/make-promo.sh，详见Promo/README.md。未改动应用产品源码、未重打DMG。

实际验证：最终生成脚本退出0；对最终MP4完整解码840帧视频及2688000个音频采样，视频/音频均completed。时长28秒、画幅1920×1080、帧率约30；音频峰值0.2089、RMS0.05087，无削波。抽取8个时间点的画面，目视检查了品牌、网格、搜索结果、拖拽与文件夹、片尾等关键画面；最终MP4的moov在mdat之前，支持渐进播放；文件8920001字节。脚本语法检查通过，SHA-256及结构化报告保存在media/launchdock-promo/。

未验证：不同设备/外部视频平台的播放器适配、配乐人工听感。没有上传或发布至外部平台。触发角仅以片尾功能文字呈现，未录制触发角操作；视频使用专用渐变背景，不包含私人桌面。

## 移除整理模式（2026-11-18）

已实现：删除LauncherStore.editing状态、完成按钮、500ms长按任务、longPressed标记及其点击拦截。正常点击/按住后松手直接执行应用启动或文件夹打开；移动超过既有6pt阈值仍进入原生拖拽。保留拖拽排序、合并/移入文件夹、文件夹内移出、搜索时禁止拖拽，以及拖拽事件监听器取消逻辑。Esc现在依次清空搜索、关闭文件夹、隐藏启动器。隐藏流程和宣传素材录制源码中的整理模式引用一并删除；文件夹名称编辑等独立文本编辑功能保留。

实际验证：sh scripts/build-dev.sh退出0，Debug编译与ad-hoc签名严格验证通过；源码检索确认无store.editing、pressTask或longPressed残留。已通过NSRunningApplication正常退出/Applications/LaunchDock.app旧进程并打开build/Development/LaunchDock.app开发版本，随后检查运行路径。未跑完整测试、未重新打DMG；真实鼠标拖拽、长按释放和Esc交互的人工回归待确认。

## 文件夹拖出时自动回到主页面（2026-11-18）

已实现：原生拖拽会话移动到文件夹外后启动500ms计时；在外部停留满500ms即执行移出事务并关闭文件夹，保留原NSDraggingSession和跟随鼠标的拖动图像。期间回到文件夹内或结束拖动会取消计时；计时使用common/eventTracking运行循环，支持鼠标停住等待。主页面可接收同一store的文件夹来源会话，继续排序、创建或移入其他文件夹；四周空白的窗口级落点也会转发主页面。拖动结束时清理来源及主页面目标高亮。两项文件夹移出一项后仍由LayoutEngine自动解散并关闭面板。

实际验证：新增NativeChecks/FolderDragChecks.swift及scripts/check-folder-drag.sh，在独立临时布局和真实原生视图上检查500ms前保持、移回取消、到时移出且拖动状态保持、主页面继续合并、结束拖动取消计时，以及两项文件夹解散，全部通过。最终Debug构建、ad-hoc签名严格验证和脚本语法检查通过；已正常退出旧开发进程并重启新开发版。未跑完整测试、未打DMG；专项检查驱动拖拽生命周期/坐标与真实目标提交，未替代人工按住鼠标跨视图持续拖动的手感验证。

## 拖动时只显示鼠标跟随图标（2026-11-18）

已实现：拖出文件夹的停留延时由500ms改为300ms。Store增加仅用于交互展示的全局draggedItem，覆盖根页面、文件夹及跨页面重新加载的单元格；拖动中将原位置的图标和文字整体隐藏，保留布局占位，避免额外挤动。移出文件夹后主页面的对应单元格同样隐藏，拖动结束/取消才恢复，拖动图像在隐藏来源之前完成快照以保证跟随图像正常。文件夹缩略图也暂不绘制正在拖动的应用，避免重复。拖动状态不参与持久化。

实际验证：sh scripts/check-folder-drag.sh退出0；验证300ms之前不移出、移回取消、满时自动移出，来源/主页面/重新加载单元格alpha=0、结束后alpha=1、取消根页面拖动恢复，以及继续合并文件夹和两项文件夹解散。sh scripts/build-dev.sh退出0，Debug编译及签名严格验证通过。已正常退出并重启开发版本；未跑完整测试、未打包DMG，人工鼠标拖拽与释放时视觉手感仍待确认。
