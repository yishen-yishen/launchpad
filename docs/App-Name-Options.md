# 应用名称字段实际值

采集日期：2026-11-07。只读取本机应用元数据；动态本地化字段受读取进程语言影响。本次工具进程使用英文，显式简体中文字段单独读取应用自带资源。`—` 表示字段不存在，不代表最终标签应为空；选定后需按回退规则处理。

用户已于2026-11-07选择A，当前展示采用文件名去.app。A/B 为处理后标签，I保留原始扩展名作对照，J/K通常不适合作为用户标签。

| 选项 | 来源 | Terminal | Visual Studio Code | WeChat | ChatGPT |
|---|---|---|---|---|---|
| A | 文件名（去 .app，已选） | Terminal | Visual Studio Code | WeChat | ChatGPT |
| B | Finder 显示名（去 .app） | Terminal | Visual Studio Code | WeChat | ChatGPT |
| C | Info.plist CFBundleDisplayName | Terminal | Code | WeChat | ChatGPT |
| D | 按当前进程语言解析 CFBundleDisplayName | Terminal | Code | WeChat | ChatGPT |
| E | 显式简体中文 CFBundleDisplayName | 终端 | — | 微信 | — |
| F | Info.plist CFBundleName | Terminal | Code | WeChat | ChatGPT |
| G | 按当前进程语言解析 CFBundleName | Terminal | Code | WeChat | ChatGPT |
| H | 显式简体中文 CFBundleName | 终端 | — | 微信 | — |
| I | URLResourceValues.localizedName（原始值） | Terminal.app | Visual Studio Code.app | WeChat.app | ChatGPT.app |
| J | CFBundleExecutable（可执行文件名） | Terminal | Electron | WeChat | ChatGPT |
| K | CFBundleIdentifier（安装标识） | com.apple.Terminal | com.microsoft.VSCode | com.tencent.xinWeChat | com.openai.codex |

脚本：`xcrun swift scripts/inspect-app-names.swift`，可附加多个应用路径。完整原始值见 App-Name-Values.json。选定名称策略后，建议缺失字段回退到文件名；简体中文资源并非每个应用都提供。
