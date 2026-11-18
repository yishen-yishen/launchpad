# 技术设计基线

来源：仓库规范 B 部分；实现偏差与风险见 ADR、Known-Limitations.md。

 技术设计文档

## B1. 工具链与工程约定

- Xcode 26 或更高且包含 macOS 26 SDK；Swift 6 语言模式与严格并发检查。具体补丁版本以机器实际安装为准并写入 README。
- 原生 Xcode App 工程，包含 App、Core 单元测试、UI 测试 target；共享 scheme `LaunchDock`。
- 支持目标 SDK 仍支持的 arm64／x86_64 架构；首要测试 Apple Silicon。不得声称未测试的 Intel 已验证。
- Bundle ID 开发默认 `com.example.LaunchDock`，集中配置方便用户替换。公开发行前修改签名团队、标识、版权信息。
- 无第三方运行依赖；若确需引入依赖，先记录原因、版本和许可证，不以拉库取代核心布局实现。
- 中文简体为默认展示文案，同时提供英文 String Catalog；不把用户文件夹名参与翻译。

## B2. 架构与目录

```text
LaunchDock/
  LaunchDock.xcodeproj
  LaunchDock/
    App/                 # App entry, delegate, lifecycle, dependency composition
    Features/
      Launcher/          # window coordinator, root view, focus, presentation
      Grid/              # collection view bridge, paging, layout, drag session
      Search/            # text bridge, index, results
      Folders/           # folder container, rename
      Settings/          # settings scenes and view models
    Domain/
      Models/            # catalog and layout value types
      Layout/            # reducer, invariants, projection, reconciliation
      Search/            # normalized search documents and ranking
    Services/
      Catalog/           # discovery, metadata, watcher
      Workspace/         # icon, launch, Finder integration
      Persistence/       # versioned atomic files and recovery
      HotKey/            # register/unregister and recorder
      LoginItem/         # SMAppService integration
    Resources/           # assets, localization
  LaunchDockTests/
  LaunchDockUITests/
  docs/                  # requirements, ADRs, manual QA, known limitations
  scripts/               # build/test/archive instructions or small helpers
```

### B2.1 明确分工

| 组件 | 责任 | 不应承担 |
|---|---|---|
| AppCoordinator | 生命周期与依赖组装 | 扫描文件、计算拖动索引 |
| LauncherWindowCoordinator | 覆盖窗口、屏幕、激活、隐藏原因 | 持久化布局 |
| LauncherStore（MainActor） | UI 状态、选择、发起意图 | 阻塞 IO |
| LayoutEngine（纯值类型） | 布局事务、校验、投影 | 调用 AppKit、写盘 |
| CatalogService（actor） | 扫描、身份匹配、变更快照 | 直接重排界面 |
| SearchIndex（actor 或轻量纯类型） | 规范化、检索、排名 | 持有 NSView／NSImage |
| IconService（MainActor facade） | 获取系统图标、内存缓存 | 在每次 cell 绘制时重复读盘 |
| PersistenceService（actor） | 串行版本化读写、恢复 | 操作窗口 |
| HotKeyService | 注册生命周期、冲突错误 | 通用按键记录 |

AppKit 对象与 NSImage 按 SDK 隔离要求留在主线程／MainActor。跨 actor 传递 Sendable 值类型；必要时传 URL、元数据、编码后的图像字节，不用 `@unchecked Sendable` 掩盖问题。不要在 MainActor 上递归遍历目录。

## B3. 窗口实现

使用可成为 key/main 的自定义无边框 NSWindow，通过 NSHostingView 承载 SwiftUI 外壳。覆盖背景为 AppKit NSVisualEffectView 桥接，网格采用 NSCollectionView 桥接；设置、搜索装饰、文件夹外壳用 SwiftUI。复杂滚动和拖动统一由一个输入协调器控制，不让 SwiftUI 与 AppKit 各自移动同一套布局。

- 使用 screen.frame 设置窗口覆盖范围，单独计算内容安全区。窗口层级仅提升至满足启动器需求的合理层级；禁止使用屏保级别压过锁屏或系统安全界面。
- 可透明背景、无标题栏，隐藏不销毁常用视图；图标懒加载。
- 不调用 toggleFullScreen。collectionBehavior 根据 M0 验证选择兼容组合，并以 ADR 记录；不要盲目叠加全部 flags。
- 保持默认 regular activation policy；如果确实必须改策略，先验证 Dock、快捷键、设置和登录启动的全部行为并记录原因。
- 窗口显示后接收文本输入，分开处理 first responder 与网格语义选择。
- show/hide 必须可重入。动画期间重复请求由 presentation 状态机收敛到最新目标，不能同时创建第二个窗口。
- 使用 HideReason：cancel、externalDeactivation、launchTarget、screenRemoved、termination，决定是否恢复原前台应用。
- 打开设置前隐藏覆盖窗口，设置成为前台窗口；关闭设置不自动重新展开启动器。

## B4. 数据模型与不变量

建议使用下面的逻辑结构；可调整 Swift 命名，但必须保留语义。

```swift
struct AppRecord: Identifiable, Codable, Sendable {
    let id: UUID                       // 本地安装实例的持久身份
    var bundleIdentifier: String?
    var canonicalPath: String
    var fileIdentity: FileIdentity?     // 卷身份 + 可序列化文件资源标识
    var displayName: String
    var bundleName: String
    var version: String?
    var availability: Availability
    var lastSeenAt: Date
    var missingSince: Date?
}

struct LayoutDocument: Codable, Sendable {
    var schemaVersion: Int
    var revision: UInt64
    var rootItems: [RootItem]           // app(UUID) 或 folder(UUID)
    var folders: [FolderRecord]
    var hiddenAppIDs: Set<UUID>
    var updatedAt: Date
}

struct FolderRecord: Identifiable, Codable, Sendable {
    let id: UUID
    var name: String
    var appIDs: [UUID]
}
```

FileIdentity 必须通过实际 URL resource values 的可支持格式编码，不能直接假设所有资源标识都能强转成字符串或跨卷稳定。实现前做移动／更新实验。Availability 至少包括 available、missing、inaccessible；完整状态编码与日期统一使用明确的版本化策略。

不变量：

1. 每个应用最多属于根或一个文件夹；隐藏只是可见性状态，不产生第二份应用引用。
2. 每个文件夹只能在根出现一次，不能嵌套；根引用的文件夹必须存在。
3. 根和文件夹项目不能重复引用同一个安装实例。
4. 已确认的新应用追加到根尾部；同 bundle 的两个安装副本不合并。
5. 正常提交后文件夹至少有两个实际成员；解散在事务中统一处理。
6. 不可用应用可以保留引用，但必须有对应 catalog tombstone／导入占位记录。
7. 页面与选中索引不是持久身份；用 ID 锚定，重新投影后求索引。
8. revision 单调增加，只有已接受的文档变更才产生新 revision。

### B4.1 身份匹配顺序

同卷 fileIdentity 精确唯一匹配 → canonicalPath 与 bundle 信息匹配 → 旧位置确认缺失且新候选 bundleIdentifier 唯一时可建议／执行受约束重定位。若旧副本仍存在，不能因 bundleIdentifier 相同吞并新副本。若候选多个，按新实例加入，原实例保持不可用状态，提供后续人工处理。

同路径 bundleIdentifier 意外变更，作为新安装实例处理，防止把完全不同应用绑定到旧身份。无 Bundle ID 时仍可按可靠文件身份及路径识别。

## B5. 应用发现与同步

基础实现为 FileManager 枚举与公开 bundle 元数据，Spotlight 不作为唯一来源。目录扫描返回 `CatalogScanResult(records, successfulRoots, failedRoots, generation)`，失败根内旧记录不能标缺失。

- 启动读取缓存后后台完整扫描。
- 对默认来源建立 FSEvents 或等效公开文件变化监听，事件防抖约 800 ms；监听子目录变化，不能仅监听目录文件描述符后假设覆盖所有后代。
- 观察 workspace 的相关应用通知作为补充，不把启动／退出通知误当完整安装通知。
- 应用被唤起时，如果距上次完整成功扫描超过 60 秒，后台补扫；设置“重新扫描”可立即执行。没有常驻高频轮询。
- 睡眠恢复／事件丢失／监听重建时重新完整扫描。
- 遍历时支持任务取消，扫描 generation 新旧隔离；旧扫描不得覆盖新结果。
- 接受 catalog 差异后通过 LayoutEngine.reconcile 合并；交互事务期间延迟合并。

图标使用 NSWorkspace 的公开图标获取能力；缓存键至少包含安装 ID、修改版本、显示尺寸和 backing scale。优先加载当前页与相邻页，不先解码全部最高分辨率图标。限制 NSCache 成本，内存压力时淘汰。

## B6. 网格、分页与拖动引擎

选用 NSCollectionView 承担 cell 复用和可访问元素。分页容器／布局负责将连续逻辑序列投影为水平页；不能依赖 NSTabView 的默认页面切换实现跟手拖动。先用确定性 GridGeometry 计算每页容量、cell frame、命中区与边缘区，再将数据交给视图。

至少提供纯逻辑操作：

```text
project(layout, visibility, geometry, anchor) -> Pages
moveApp(id, destination, insertionIndex)
moveFolder(id, rootInsertionIndex)
createFolder(sourceAppID, targetAppID)
insertAppIntoFolder(id, folderID, insertionIndex)
moveAppOutOfFolder(id, rootInsertionIndex)
renameFolder(id, name)
reconcile(scanDelta)
validate(document) -> violations
```

索引定义：所有 destination insertionIndex 表示“从源容器移除源项目之后”的目标容器插入索引；同容器移动需转换一次，不能两次减一。悬停预览与最终 drop 必须调用同一套索引转换，避免释放时跳位。

DragSession 包含源 ID、源容器、原始布局快照 revision、鼠标位置、当前候选目标、悬停开始时间、临时投影。draggingEntered／updated 只改投影，performDrop 验证后一次提交。交互期间 catalog 变化先排队，提交／取消后再 reconcile。事务期间进入不可用目标时取消或拒绝 drop，不通过数组下标继续执行。

计时使用可取消 Task 或单一调度器；离开目标、隐藏、取消、屏幕改变都取消任务。测试中注入时钟，避免 sleep 测试。

## B7. 状态与输入路由

不能使用一个互斥 enum 同时表示所有 UI 状态，因为搜索、窗口动画和文件夹状态存在正交关系。建议：

```text
PresentationState = hidden | appearing | visible | disappearing
ContentContext = root(anchor) | folder(folderID, anchor)
InteractionState = browsing | editing | dragging(DragSession) | renaming(folderID)
SearchState = inactive | active(query, resultIDs, selection, generation)
FocusTarget = searchText | grid | folderName | otherControl
```

允许关系：搜索 active 时只能 browsing，不能拖动或重命名；开始编辑关闭搜索；文件夹可以 browsing 或 editing；隐藏必须终止交互、清理临时任务和文本组合。

事件由一个路由入口按优先级处理，保证按键一次只被消费一次；不要给整个应用装多个互相竞争的 NSEvent monitor。必须兼容原生菜单 tracking、右键菜单和 NSTextInputClient marked text；搜索控件优先选 NSSearchField／NSTextField 的桥接以便明确处理文本和网格焦点。

全局快捷键优先采用公开组合快捷键注册机制（可评估 SDK 仍提供的 RegisterEventHotKey），隔离到 HotKeyService。只用来注册指定组合，不用事件 tap 捕获所有输入；SDK 可用性、弃用情况、键盘布局和 Secure Input 行为须在 M0 验证。不可假设“注册成功”代表与所有系统快捷键完全无冲突。

## B8. 启动应用

通过 `NSWorkspace.openApplication(at:configuration:)` 或 SDK 对应的公开异步接口打开确切安装 URL。不要 shell 执行 open，不靠显示名称查找应用。

- 启动前检查当前可用路径，不因扫描 stale 直接移除布局。
- 启动期间防重复触发同一项目，视觉反馈不超过必要范围。
- 成功后隐藏启动器，HideReason=launchTarget，不恢复之前前台应用。
- 失败保持／恢复启动器，显示应用名称和可理解错误，允许重试或重新扫描。
- 目标应用已经运行时请求系统激活，不创建不必要的新实例。
- 系统启动回调成功仅表示系统接受／启动应用，不保证其主窗口已就绪；不轮询其他应用窗口，不申请辅助功能来监控。

## B9. 持久化、恢复与迁移

默认目录：`~/Library/Application Support/<bundle-id>/`；图标磁盘缓存如使用则放 Caches，可随时重建。文件：catalog.json、layout.json、preferences.json，以及最近 3 份 layout 备份。

- catalog、layout 各有 schemaVersion；catalog 可重建，layout 不可静默重建。
- 串行写入，临时文件与目标同目录，成功写完再原子替换；备份在替换前保留已验证版本。
- 保存队列按 revision 合并，旧异步保存不能覆盖新 revision；布局提交后 300 ms 防抖，退出前尝试有界刷新并报告失败。
- catalog 与 layout 不是跨文件原子事务，崩溃后通过 reconcile 恢复；悬空引用成为占位，而非无声删除。
- 读取失败先保留损坏文件，尝试有效备份并提示恢复结果。没有有效备份时提示“创建新布局”或选择导入，不能自动抹掉文件夹。
- 遇到比当前更高 schemaVersion 时禁止覆盖，进入恢复／只读提示；已知旧版本通过显式迁移函数转换并备份。
- 每次迁移、导入、重置都先校验输入和不变量；设置合理大小上限（导入默认 5 MB、最多 10000 条引用），拒绝恶意深层结构或不支持的字段语义。
- JSON 编码采用明确日期格式、稳定排序用于调试；不要存储 NSImage 或任意对象归档。

## B10. 登录启动、权限与分发

登录启动使用 ServiceManagement 提供的 SMAppService；主应用或 helper 的选择由 M0 实验决定。读取真实 service status，在需要用户允许时显示对应说明，不把本地 toggle 值当成系统状态。

核心功能应无需辅助功能／输入监控／录屏／完全磁盘访问。访问用户额外目录时使用原生选择器和公开授权机制；初期不为扫描所有磁盘添加权限。自动删除／权限提升／使用私有 LaunchServices 数据库均不允许。

开发构建提供无开发者证书也能在本机运行的说明。发行构建采用 Hardened Runtime、Developer ID、公证和 stapling；需要真实证书或账号的步骤由用户在具备凭据的 Mac 上执行，代码阶段准备命令和检查表，不伪造签名产物。Mac App Store／Sandbox 另立 ADR 与验证计划。

## B11. 日志与可诊断性

使用 OSLog 分类 window、catalog、layout、search、launch、persistence。路径和名称默认按私有数据处理；不记录完整搜索词、不上传日志。关键耗时加 signpost。错误提示使用本地化文本，详细错误保留在诊断日志。

提供 debug-only 模拟目录与 300／1000 项数据注入能力，禁止 Release 默认加载演示应用。提供 debug 状态视图显示扫描状态、布局 revision、当前页与交互状态，不能污染正式主界面。

