# LaunchDock：macOS 原生 Launchpad 替代应用

需求规格、技术设计与 Codex 开发任务书 · v1.0 · 2026-11-06

> 本文是可执行的开发基线。LaunchDock 是暂定名称；不是 Apple 产品。目标是在 macOS 26 上重建旧 Launchpad 的主要使用体验，并遵循 macOS 26 的界面规范。本文中的尺寸、阈值和性能数值是项目设计目标，不是 Apple 官方规范或已完成的测量结果。所有系统 API 均须以开发机器所安装 SDK 的声明为准。

## 0. 给开发执行者的总指令

使用 Swift、SwiftUI、AppKit 开发真实可运行的 macOS 桌面应用，最低系统版本 macOS 26.0。不得用网页、Electron、Tauri 或图片演示替代。先执行 M0 技术验证，再按 M1—M5 逐步完成；每个阶段都必须能够构建和运行。不要完成 M1 后就将整个项目标记完成。遇到普通实现选择按本文默认值推进；遇到系统能力限制记录证据和降级结果，不得使用占位实现冒充完成。

本文分为三个部分：A 是产品需求，B 是技术设计，C 是实施与验收。需求冲突时，优先顺序为用户的新指令、本文明确的功能行为、本文技术建议。实现细节可以调整，但须在 ADR 中解释，不得静默缩减需求。

默认分发：站外分发、Developer ID 签名与公证；开发期允许本地签名运行。默认不启用 App Sandbox。不得擅自申请管理员权限、辅助功能、输入监控、录屏、完全磁盘访问。以后上架 Mac App Store 是独立评估任务。

# A. 产品需求文档

## A1. 产品目标与完成定义

用户可以像旧 Launchpad 一样，快速唤起全屏应用网格、查找并启动应用、横向翻页、拖动排序、创建和整理文件夹。主要操作应无需离开键盘或触控板。启动器不是普通 Finder 列表，也不是 Spotlight 搜索面板。

核心成功标准：

1. 首次启动能列出本机标准应用目录中的可启动应用。
2. Dock 或快捷键唤起后，用户能立即输入、搜索并启动应用。
3. 分页、顺序、文件夹在退出或重启后保持一致。
4. 扫描应用变化不会重置用户布局。
5. 搜索、中文输入法、拖动、多显示器不相互破坏。
6. 界面采用系统字体、原生菜单、适当的系统材质，并支持系统辅助功能设置。

### A1.1 范围分级

| 级别 | 内容 | 完成要求 |
|---|---|---|
| P0 核心 | 应用发现、图标、启动、搜索、分页、键盘、排序、文件夹、持久化 | v1 必须完成 |
| P0 系统体验 | Dock 唤起、全局快捷键、菜单栏、登录启动、标准多屏行为 | v1 必须完成；受系统限制的场景需明确降级 |
| P1 增强 | 拼音搜索、撤销整理、布局导入导出、隐藏应用、移到废纸篓 | 核心完成后按顺序实现，独立验收 |
| 研究项 | 系统原版捏合手势、旧 Launchpad 数据迁移、App Store 安装进度 | 不计入 v1 完成门槛，不得宣称已经支持 |

旧 Launchpad 的系统特权能力不等于第三方应用的公开能力。“体验一致”在本文中指明确列出的交互，不表示完全替换系统组件。

### A1.2 v1 不包含

不包含自动分类推荐、云同步、账户、AI 功能、插件平台、应用更新管理、自动更新器、清理卸载残留、iPhone 镜像应用、嵌套文件夹、访问其他用户的应用目录。没有任何网络后端或分析上报。

## A2. 启动、常驻与唤起

### FR-001 进程与 Dock

- 默认显示 Dock 图标并提供菜单栏入口。默认使用普通应用激活策略，Info.plist 不设置 LSUIElement=true。
- 用户直接打开应用或单击已有 Dock 图标：隐藏时显示启动器；启动器已经显示时再次点击 Dock 保持显示。Dock 点击不切换隐藏，避免误触。
- 全局快捷键和菜单栏“显示/隐藏启动器”是切换操作。
- 关闭启动器只是隐藏覆盖窗口，不退出进程；Cmd+Q 或菜单栏“退出”结束进程。
- 登录启动默认关闭。登录启动启用后只进入后台常驻，不自动显示覆盖窗口。登录启动与手动打开的区分必须真机验证并记录实现方式；必要时以独立登录启动 helper 实现，不可用固定延时猜测。
- 第一次手动打开直接显示网格，不设置阻塞式欢迎向导。

### FR-002 唤起屏幕

- 默认出现在鼠标所在显示器；取鼠标全局坐标匹配屏幕 frame。无法匹配时使用当前主屏。
- 同时只显示一个启动器窗口，不镜像到所有屏幕。
- 显示期间鼠标移到其他屏幕不迁移窗口；下次显示重新决定屏幕。
- 窗口覆盖目标屏幕，内容避开刘海和系统安全区域；不创建新的原生全屏 Space。
- 当前桌面 Space 必须可用。其他应用的全屏 Space、Stage Manager、显示器具有单独空间开关，纳入 M0 真机验证，不能仅通过设置 collectionBehavior 就认定支持。
- 系统不允许在某全屏场景覆盖时，维持系统允许的行为，不强切用户 Space；记录限制并提供 Dock／退出全屏后的正常入口。
- 屏幕断开时，取消拖动，将窗口移到可用屏幕重新布局；没有可用屏幕则隐藏。

### FR-003 退出与焦点

- 点击主网格空白背景隐藏；图标标签、分页按钮、搜索框、菜单和文件夹容器内部不算空白背景。
- 失去应用激活时隐藏，原生菜单、应用自己的设置窗口、文件选择器与确认对话框不应被误认为外部失焦。
- 搜索框显示后可立即输入；焦点恢复需在窗口成为 key window 后完成。
- 取消启动器时可恢复唤起前仍存在的前台应用；启动目标应用时不得把焦点恢复给原应用。
- 隐藏时清空搜索、退出编辑、关闭文件夹；保留根页面位置。
- 首次显示为第一页；后续显示回到上次浏览的根页面。

## A3. 应用目录与生命周期

### FR-010 默认来源

扫描以下目录及其中普通子目录：`/Applications`、`~/Applications`、`/System/Applications`、`/System/Library/CoreServices/Applications`。允许不存在的目录。隐藏项目、无读取权限项目跳过并记录诊断。

找到 `.app` bundle 后停止向 bundle 内递归，避免列出嵌套 helper。仅接受声明为应用的有效 bundle；排除明确 `LSUIElement=true`、`LSBackgroundOnly=true` 的后台应用和启动器自身。不能依靠应用名称黑名单识别 helper。符号链接需要解析、去重、防止循环；默认只纳入目标位于授权扫描根范围的链接。外部目录通过 P1 自定义来源单独处理。

- 读取本地化显示名称，回退到 bundle display name、bundle name、文件名。
- 使用系统解析后的应用图标，不统一重画第三方图标。
- 不要求覆盖所有由 Spotlight 索引或受保护系统机制提供的应用。
- 同名不同安装路径的应用可以同时存在；同 Bundle ID 的不同副本也可以存在，名称下或辅助说明标明来源以便区分。
- 扫描期间展示已有缓存；首次空库展示“正在查找应用”。扫描完成为零展示重试和打开设置入口。

### FR-011 变化处理

- 新安装应用添加在根布局尾部，不重新排序已有项目。
- 同位置应用更新保留原位置和文件夹归属。
- 应用移动时尽量保持身份；不唯一的匹配不得猜测合并。
- 临时扫描失败、目录不可读、外接路径离线，不能被当作用户卸载。
- 确认缺失的应用先标记不可用，不立即丢弃布局位置。成功完整扫描确认缺失后保留 7 天；期间显示变暗图标和“应用不可用”，启动时提供重新扫描、在访达中定位或移除条目。7 天后再次完整扫描仍缺失才清理。
- 扫描异常期间暂停自动清理；更新时间和缺失状态不计为布局操作，不产生撤销项。
- 外部变化发生在拖动／重命名期间时，先排队，交互结束后合并。

## A4. 布局、分页与浏览

### FR-020 网格规则

根布局是一条有序的应用／文件夹项目序列。页面是按当前屏幕容量生成的视图，不保存固定屏幕坐标。默认目标为 7 列 × 5 行；小屏降至 6×4 或 5×4，具体根据安全内容区与最小单元格计算。大屏不无限增加列数，网格最大宽度建议 1280 pt，内容居中。

- 默认图标视觉尺寸 72 pt，允许根据可用空间在 56–88 pt 内调整。
- 单元格目标 136×112 pt，最小 104×96 pt；不足时继续降低列／行数，保证至少 1×1，不允许内容溢出。
- 标签系统字体约 13 pt，最多两行，末尾省略；辅助功能读取完整名称。
- 排布使用逻辑 pt，不能直接使用物理像素。
- 根布局紧凑连续，不保留手工空格，不支持自定义空白页。
- 切换显示器可能改变分页边界，但全局顺序不变。尽量保持之前的首个可见条目仍在当前页。
- 安装变化不改变正在看的内容锚点；当前页消失时夹紧到最后一页。

### FR-021 翻页

- 横向触控板滑动跟随手指，结束时吸附到目标页；一次手势最多移动一页。
- 有 phase／momentumPhase 的连续事件按一次手势聚合，惯性不能重复触发翻页。
- 传统纵向滚轮用于根页面翻页，累积阈值和冷却防止连跳；文件夹内部同样生效，搜索结果区域则按纵向滚动处理。
- 点击分页圆点切页；首尾边界有轻微阻尼，不循环翻页。
- 没有第二页时不展示多余分页圆点。
- 输入法组合、文本编辑、拖动状态下不得把滚动误处理为普通翻页。

## A5. 搜索与键盘

### FR-030 搜索语义

- 浏览状态可以直接输入文本进入搜索，使用真实文本输入控件，不监听全局按键拼接字符串。
- 空字符串恢复搜索前页面、选择和布局；仅空白视为空查询。
- P0 支持本地化名称、bundle 名称、文件名、Bundle ID 的大小写和宽度不敏感匹配；显示名称精确匹配优先，其次前缀、单词前缀、子串、其他字段。
- 同等级结果按用户根布局展开后的顺序稳定排列。文件夹内应用参与全局搜索，不把文件夹本身作为可启动结果；显示所属文件夹名称。
- 搜索结果为连续纵向网格，可滚动，不显示根分页圆点；不能拖动整理。
- 用户输入后默认选择第一项，回车启动。无结果显示“未找到应用”，回车不执行。
- 点击清除按钮清空查询并恢复根页面；输入法存在 marked text 时，不执行启动、Esc 退出或翻页，交由输入法优先处理。
- 组合输入期间可保留前一次结果，待文本提交后更新。异步检索必须忽略过期查询的结果。
- P1 拼音：缓存全拼与首字母，使用系统转写能力并验证中文多音字限制；不承诺语言学完全准确。搜索词不持久化、不上传。

### FR-031 键盘表

| 按键 | 行为 |
|---|---|
| 普通字符 | 正常浏览时转入搜索；编辑名称时输入名称 |
| 方向键 | 网格移动选择，网格键盘导航时不插入搜索文本 |
| 左右键在文本编辑时 | 移动文本光标；不得同时切换网格选择 |
| Tab / Shift+Tab | 按原生焦点顺序访问搜索框、网格、分页和可用控件 |
| Return | 网格模式启动所选应用／打开文件夹；重命名时提交 |
| PageUp / PageDown | 浏览状态上一页／下一页；搜索时按结果视图处理 |
| Esc | 按下列优先级返回 |
| Cmd+, | 打开设置 |
| Cmd+Q | 退出进程 |

焦点模型：初次唤起搜索框为文本输入焦点；按下箭头进入网格键盘选择模式并选择第一项，后续左右键移动网格选择。网格模式输入可打印字符回到搜索控件，正确转交输入法事件，不手动模拟组合文本。搜索框仍有文本编辑焦点时，左右键保留原生光标行为。

Esc 优先级：输入法处理 → 取消重命名 → 取消拖动并恢复快照 → 关闭菜单／弹窗 → 搜索非空时清空搜索 → 退出编辑模式 → 关闭文件夹 → 隐藏启动器。一个按键只处理一个层级。

根网格左右越过边界可移动到相邻页并选择对应边缘条目；上下越过根首尾保持选择。搜索结果上下移动时自动滚动保持可见。空网格不能发生索引越界。

## A6. 整理与文件夹

### FR-040 编辑模式

- 长按图标 500 ms 进入编辑模式；右键菜单“整理应用”也能进入。
- 编辑时轻微晃动或等效编辑状态反馈，减少动态效果开启时不晃动。
- 编辑时单击图标只选择，不启动；双击不绕过编辑模式启动。
- 顶部显示“完成”，点击或 Esc 退出。删除系统应用的按钮不得因进入编辑模式出现。
- 浏览状态允许直接拖动：移动超过 6 pt 后进入拖动，避免所有整理都必须长按。

### FR-041 拖动与重排

拖动图标产生浮起预览和原位占位。悬停单元格边缘表示插入位置，悬停应用中心区域达到 650 ms 表示创建文件夹；中心区域默认是图标矩形中央 50%，而不是整个单元格。

- 在中央悬停未达到阈值时不创建文件夹；边缘插入与创建文件夹视觉反馈互斥。
- 跨页：距离网格左右边缘 40 pt 范围停留 550 ms 翻一页；继续翻页需要冷却 700 ms；禁止重复定时器累积。
- 从满页插入后，按全局顺序将后续项目推到后页；移走项目后自动补位。
- 末页边缘拖动可显示一个临时新页；只有确实放入项目才保留对应序列变化，取消不创建空页。
- 释放到窗口外／无效区域取消，恢复拖动开始前快照；不能删除应用。
- Esc、失焦、屏幕断开取消拖动；磁盘保存失败显示未保存状态并保留内存布局，不能假装保存成功。
- 拖动过程中只生成临时投影；成功 drop 后一次性提交布局事务并写盘。

### FR-042 文件夹规则

- 应用 A 叠放到应用 B：文件夹占据 B 的位置，内部顺序 B、A，移除 A 原位置，根序列重新紧凑。
- 默认名称“文件夹”；有重名时添加序号。支持 1–40 个用户感知字符，去除首尾空白；空名称恢复原值。
- 默认不自动按应用类别命名，避免依赖分类数据。
- 点击文件夹打开居中容器，背景压暗；容器使用标准材质，工具控件可采用玻璃效果。
- 文件夹内部按同一网格规则适配，分页不受固定项目数量限制；预览最多显示前 9 个小图标。
- 应用拖到已有文件夹中央停留 650 ms 后自动展开，可在内部定位后放入；放到折叠文件夹时追加到末尾。
- 从文件夹拖到容器外，进入根网格投影，再选择放置位置；取消恢复原位置。
- 不支持文件夹内放文件夹，也不支持两个文件夹自动合并；文件夹之间可在根布局中重排。
- 文件夹剩 1 个应用时，提交事务后自动解散，以该应用替代文件夹原根位置；变空时移除文件夹。
- 文件夹名双击／上下文菜单“重命名”进入文本编辑；Enter 提交、Esc 取消。重命名不影响内部排序。
- 搜索文件夹中的应用并启动，不改变文件夹结构或根页面。

## A7. 设置与附加功能

### FR-050 P0 设置

原生设置窗口：通用（登录启动、快捷键）、外观（跟随系统／浅色／深色、图标大小档位）、应用（重新扫描、索引状态）、关于（版本、开源许可）。布局重置为字母顺序需要确认，并在执行前保存备份。应用图标大小改变仅调整展示密度，不改变全局排序。

全局快捷键默认尝试 Option+Space，须允许录制其他组合。不能宣称任何组合一定无冲突。注册失败保持旧配置并提示；若系统接受注册但某系统功能优先拦截，应在设置提供测试入口和更换建议。只录制组合键，不保存用户普通输入。未设置成功时 Dock 和菜单栏仍可使用。

### FR-051 P1 功能

1. 拼音搜索。
2. 撤销最近 20 次布局事务，包括重排、建文件夹、重命名、解散、隐藏。会话内有效，不撤销应用安装卸载或系统移到废纸篓操作。
3. 隐藏应用：只改变启动器可见性，可在设置恢复。隐藏应用保留其逻辑占位引用；投影忽略隐藏条目，恢复后仍位于其原逻辑邻接位置。文件夹可见数量按可见项计算，但解散判断按实际成员数计算。
4. 布局导入导出：版本化 JSON，不含二进制图标、搜索词和机器标识。通过安装身份提示匹配当前清单；不可将导入路径当成可信任可启动 URL。导入前校验并备份，匹配结果预览后确认覆盖；未匹配应用形成不可用占位。
5. “移到废纸篓”：普通可写第三方应用才显示候选入口；需确认应用名称和路径；运行中应用提示先自行退出，不强制终止；系统目录、自身、不可写目标禁止；调用系统文件操作，失败显示错误，不使用 sudo 或递归删除。

## A8. 视觉、辅助功能与性能

### FR-060 视觉基线

- 核心为大图标网格，不添加不必要的分类侧栏和推荐区域。
- 标准材质用于背景和文件夹内容，Liquid Glass 主要用于搜索／浮动控制层，避免每个应用图标后都放一块玻璃。
- 背景优先使用实时系统模糊视图，不截取桌面、不请求录屏权限。系统限制导致无法模糊时回退到自适应纯色／标准材质。
- 适配浅色、深色、增加对比度、降低透明度；用系统语义色，保证文字和选择环清晰。
- 动画建议：显示／隐藏 180–240 ms，分页 220–300 ms，文件夹 180–240 ms。减少动态效果时用淡入淡出或即时变换，不能只关闭一部分动画。
- 图标设计使用独立原创资产，可后续通过 Icon Composer 打磨；开发占位图标必须明显标记，发布前替换。

### FR-061 辅助功能

应用图标提供名称、按钮角色、运行／不可用状态；文件夹提供名称、成员数量、展开状态。拖动之外必须有键盘可访问的“移到前面／后面”“移入文件夹／移出文件夹”菜单操作，且走同一布局事务。VoiceOver 可访问搜索、网格、分页、文件夹和完成按钮；焦点不会进入隐藏页或被遮挡根网格。选择状态不能只靠颜色。

### NFR-001 目标与测量

以 Apple Silicon、16 GB、macOS 26、300 个应用为基准；记录实际机型、系统、构建模式、样本量。以下为验收目标，不得当成已实现承诺。

| 指标 | 目标 | 测量方式 |
|---|---|---|
| 预热后唤起至可输入 | P95 ≤150 ms | Release，30 次，os_signpost + Instruments |
| 本地缓存搜索 | P95 ≤50 ms | 不含输入法组合和系统事件分发，300 应用，100 词 |
| 交互流畅 | 60 Hz 屏幕大部分帧在 16.7 ms 预算内 | 拖动、翻页、展开，用 Instruments 记录卡顿 |
| 标准目录初扫 | 目标 ≤3 秒 | 无网络卷；单独报告慢盘和权限失败 |
| 隐藏时资源 | 稳定后接近空闲，无持续动画和高频轮询 | 5 分钟 Energy／CPU 观察，报告实际数值 |
| 内存 | 稳态目标 ≤150 MB | 300 应用完成缓存后，记录峰值与稳态 |

不因达不到某个目标伪造数字；记录原因和优化计划。500、1000 条模拟应用用于压力测试，不冒充真实目录扫描结果。

# B. 技术设计文档

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

# C. 实施计划、验收与交付

## C1. M0：技术验证（先完成）

产出最小可运行工程与 `docs/M0-Validation.md`，验证：

1. 无边框窗口在当前 Space 的显示、隐藏、再次激活和焦点。
2. 双屏、拔屏、刘海屏安全区，鼠标屏幕选择。
3. 全屏 Safari／其他原生应用与 Stage Manager；记录系统开关、观察和降级。
4. 中文拼音输入候选、marked text、Esc、Enter，不误启动应用。
5. 指定组合快捷键注册、释放、修改、失败提示。
6. NSWorkspace 启动不存在、已运行及正常应用。
7. 登录启动如何与普通打开区分，后台启动不会弹网格。
8. 模糊背景不使用截图或录屏权限，深浅色与降低透明度。

M0 可以使用模拟应用作窗口验证，但 M1 必须换成真实扫描。环境没有 macOS/Xcode 时，可创建工程和纯逻辑代码，但 M0 标记“待真机验证”，不能声称已通过；仍继续可完成的任务。记录阻塞点和可执行的验证步骤。

## C2. 阶段任务与退出条件

| 阶段 | 实现内容 | 退出条件 |
|---|---|---|
| M1 浏览启动 | 真实扫描、图标、基础网格、分页、Dock／菜单栏／快捷键、启动、隐藏 | 实机可搜索前先浏览并打开真实应用，状态可恢复 |
| M2 搜索键盘 | 检索索引、中文输入、键盘导航、选择与 Esc | 完成搜索测试与输入法手工矩阵，无误启动 |
| M3 整理 | 拖动、跨页、文件夹、重命名、取消、辅助操作 | 所有布局不变量测试通过，重启位置不变 |
| M4 稳定与外观 | 增量扫描、缺失状态、恢复备份、设置、登录启动、辅助功能、材质 | P0 验收矩阵通过，性能测量和限制记录齐全 |
| M5 增强交付 | 按 A7 实现 P1、文档、发行配置 | P1 各自验收；签名凭据缺失可列为发行待办 |

每阶段结束运行相关测试并更新进度记录。不能用暂时不可验证的研究项阻塞可完成的 P0。最终报告逐项区分“已实现”“已实测”“待真机验证”“明确不支持”。

## C3. 自动化测试

测试纯逻辑的重要行为，避免仅验证字段赋值或重复实现。

### UT-Layout

- 同页向前／向后移动，源移除后的插入索引与预期顺序一致。
- 满页向另一页插入，后续项目顺序完整且无重复。
- 建文件夹根位置和 B、A 内部顺序正确。
- 拖出最后两项之一时文件夹自动解散；空文件夹删除。
- 文件夹重排、应用跨文件夹移动，不产生双重归属。
- 所有取消路径恢复快照；无效 drop 不增加 revision。
- 隐藏／恢复后邻接顺序保持；单个可见成员不错误解散实际多人文件夹。
- 对随机操作序列反复 validate，固定随机种子可复现；不要求引入属性测试库。

### UT-Catalog / Search / Storage

- 同 Bundle ID 两个副本不会合并；同位置更新保持身份；明确移动保持身份；歧义不猜测。
- 失败扫描根不删除旧记录；7 天清理仅由有效完整扫描触发，使用注入时钟。
- 中文、英文、大小写、全角、空白、排名和稳定顺序；过期搜索结果不覆盖新结果。
- 损坏 JSON、旧版本迁移、高版本只读、原子保存失败、旧 revision 保存被丢弃。
- 导入重复 ID、嵌套文件夹、过大输入和未匹配应用的处理。

### UI 自动化

使用专用临时数据目录和可注入应用启动器；测试不实际打开／删除用户应用。覆盖：显示、输入、清除、无结果、方向选择、Esc 层级、文件夹打开／重命名、基本拖动完成与取消。系统全局快捷键、输入法候选、多屏和全屏行为仍需手工测试，不用 UI 自动化通过替代真机结论。

## C4. 手工验收矩阵

| ID | 操作／场景 | 预期 |
|---|---|---|
| AC-01 | 首次打开，300 应用 | 不白屏卡死；逐步显示真实图标，扫描有状态 |
| AC-02 | Dock、菜单栏、快捷键多次操作 | 窗口不重复创建；Dock 保持显示，快捷键可切换 |
| AC-03 | 拼音输入中文应用名，候选状态按 Enter／Esc | 输入法优先，无误启动或误关闭 |
| AC-04 | 搜索文件夹内应用并启动 | 正确打开，文件夹与排序不变 |
| AC-05 | 拖动跨三页、悬停边缘、取消 | 每次阈值只翻一页；取消完整恢复 |
| AC-06 | 创建／改名／拖入／拖出／解散文件夹 | 所有规则符合 A6，重启后保持 |
| AC-07 | 新装、更新、移动、删除应用 | 新项目追加；身份匹配合理；旧位置不被重排 |
| AC-08 | 扫描根暂时无权限 | 不误删应用和文件夹 |
| AC-09 | 写盘失败或 layout.json 损坏 | 明确提示；保留数据；可用备份恢复 |
| AC-10 | 双屏不同缩放、拔屏、全屏 Space | 不出屏、不失去可操作入口；限制有记录 |
| AC-11 | 快速反复显示隐藏、打开设置、弹出菜单 | 无焦点循环、残留蒙层或错误隐藏 |
| AC-12 | 减少动态、降低透明度、增加对比度 | 全部主要状态可读、可操作 |
| AC-13 | VoiceOver 与纯键盘整理 | 能选择、启动、进出文件夹并整理，无隐藏页焦点 |
| AC-14 | 登录启动与手动打开 | 登录仅常驻；手动打开显示网格 |
| AC-15 | 没有权限授权的干净用户环境 | 核心功能不主动索要额外隐私权限 |
| AC-16 | 普通应用退出／启动器启动失败 | 能重试，不丢布局，不恢复错误前台应用 |
| AC-17 | P1 废纸篓取消、失败、运行中、系统应用 | 不误删；不强杀；系统目标不能操作 |
| AC-18 | P1 布局导入跨机器、重复和非法文档 | 校验、预览、备份明确，绝不信任导入路径直接启动 |

## C5. 构建与交付要求

仓库必须包含完整可打开的 Xcode 工程、共享 scheme、源码、资源和测试。README 至少包含：工具链版本、最低系统、打开工程步骤、构建与测试命令、实际数据路径、重置调试数据方法、已知限制、发行配置步骤。

参考命令，开发者应按实际工程验证后写回 README：

```bash
xcodebuild -project LaunchDock.xcodeproj -scheme LaunchDock -destination 'platform=macOS' -configuration Debug build
xcodebuild -project LaunchDock.xcodeproj -scheme LaunchDock -destination 'platform=macOS' test
```

未具备签名凭据时可为本地验证添加适当构建配置，但不得把禁用签名当作可分发方案。禁止提交本机证书、私钥、账号 token、个人绝对目录、DerivedData。

最终必须提交：

- 代码与可构建工程，不只是示例片段。
- `docs/Requirements.md` 和 `docs/TechnicalDesign.md`：将本文 A／B 部分落入仓库并随实现更新。
- `docs/Progress.md`：M0—M5 与 FR／AC 对照状态。
- `docs/M0-Validation.md`：实机配置、观察、截图或步骤、降级结论。
- `docs/Manual-QA.md`、`docs/Performance.md`、`docs/Known-Limitations.md`。
- ADR：窗口／Space 策略、应用身份匹配、登录启动、全局快捷键、持久化格式。
- 测试结果、构建结果与未执行原因。无法在当前环境运行时明确写“未运行”，不得写“测试通过”。

## C6. 可复制给 Codex 的启动指令

```text
请在当前仓库实现 macOS 原生应用 LaunchDock，遵循附件 LaunchDock-Codex-Spec.md。

先读取仓库 AGENTS.md 和已有代码，保留用户已有改动；新仓库则创建完整 Xcode App 工程。
按文档 M0—M5 持续推进，每阶段保持可构建，先完成 P0 再完成 P1；研究项单独记录。
使用 Swift 6、SwiftUI、AppKit，macOS 26.0+，不使用 WebView/Electron/Tauri。
核心采用可测试的 LayoutEngine、独立 catalog、版本化持久化；按文档实现真实扫描和应用启动。
不要把 UI 预览、模拟应用清单、TODO 或空实现当作完成。
不要仅输出计划，请直接修改文件、运行适用检查，并持续处理发现的问题。
未提供真实签名证书时继续完成本地工程和发行说明，不编造已签名产物。
当前环境没有 Mac/Xcode 时继续实现可完成部分，明确列出待真机验证项与可执行验证步骤。
每次阶段报告写明已实现内容、实际测试、未验证项，并更新 docs/Progress.md。
普通实现选择按文档默认值执行；只有会改变产品范围或需要外部账号凭据时再询问。
```

## C7. 官方参考与使用说明

以下链接为实现入口，不能替代本机 SDK 声明。Apple 文档可能动态更新；开发者要记录所使用的 SDK 和 API availability，特别关注窗口 collectionBehavior、全局快捷键和新材质 API。本文的技术架构、阈值和数据协议是项目建议，不是从官方文档直接给出的完整解决方案。

- [Liquid Glass 概览](https://developer.apple.com/documentation/technologyoverviews/liquid-glass)
- [材质设计规范](https://developer.apple.com/design/human-interface-guidelines/materials)
- [SwiftUI glassEffect](https://developer.apple.com/documentation/swiftui/view/glassEffect(_:in:))
- [NSVisualEffectView](https://developer.apple.com/documentation/appkit/nsvisualeffectview)
- [NSGlassEffectView](https://developer.apple.com/documentation/appkit/nsglasseffectview)
- [NSCollectionView](https://developer.apple.com/documentation/appkit/nscollectionview)
- [NSWindow.CollectionBehavior](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct)
- [canJoinAllApplications](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallapplications)
- [NSWorkspace](https://developer.apple.com/documentation/appkit/nsworkspace)
- [启动应用接口](https://developer.apple.com/documentation/appkit/nsworkspace/openapplication(at:configuration:completionhandler:))
- [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)

