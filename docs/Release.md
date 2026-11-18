# 安装包与发行

当前可以执行 `sh scripts/package-release.sh` 制作独立 Release 预览包：

- `dist/LaunchDock.app`：可直接复制到“应用程序”。
- `dist/LaunchDock-0.0.1-beta-universal.dmg`：内含 App、Applications 快捷方式和安装说明。
- `dist/LaunchDock-0.0.1-beta-universal.zip`：备选压缩包。
- `dist/SHA256SUMS.txt`、`dist/Verification.json`：文件校验值和架构/依赖检查结果。

要求 macOS 26.0+，通用二进制包含 arm64 和 x86_64。用户无需 Xcode、Swift 工具链、Homebrew 或任何第三方运行依赖；Swift 标准库由支持的 macOS 提供，核心库静态链接到主应用。验证脚本检查两个架构的所有 Mach-O 依赖，仅允许系统库路径。

本包使用本地 ad-hoc 签名，**没有 Developer ID 发行签名，也没有 Apple 公证**。当前钥匙串没有可用的发行签名身份，不能声称他人下载后通过 Gatekeeper。网络下载后的首次打开可能需要先尝试打开，再在“系统设置 → 隐私与安全性 → 仍要打开”中由用户确认；受管理设备可能禁止。无需关闭 Gatekeeper 或移除安全属性。见 [Apple 首次打开说明](https://support.apple.com/102445)。

安装：先退出旧版，打开 DMG，把 LaunchDock 拖到 Applications，弹出镜像，再从“应用程序”启动。ZIP 解压后同样复制 App。替换 App 不删除 `~/Library/Application Support/app.launchdock.LaunchDock/` 内的个人布局。此包是预览版，不代表规范全部验收完成。

## Developer ID 正式发行

要让其他用户下载后按正常发行流程打开，需要真实 **Developer ID Application** 证书及私钥、对应 Apple Developer 团队和公证凭据。不需要把这些凭据写入仓库；公证可使用本机钥匙串 profile。未提供时继续交付以上本地可安装预览包。

在最终 App 内容固定后签名、公证，再重新生成 ZIP 和 DMG；签名后不能修改 Info.plist、图标或二进制：

```sh
codesign --force --options runtime --timestamp \
  --sign 'Developer ID Application: YOUR NAME (TEAMID)' dist/LaunchDock.app
codesign --verify --deep --strict --verbose=2 dist/LaunchDock.app
ditto -c -k --sequesterRsrc --keepParent dist/LaunchDock.app build/LaunchDock-notary.zip
xcrun notarytool submit build/LaunchDock-notary.zip --keychain-profile YOUR_PROFILE --wait
xcrun stapler staple dist/LaunchDock.app
xcrun stapler validate dist/LaunchDock.app
spctl --assess --type execute --verbose=4 dist/LaunchDock.app
```

仅在公证结果为 Accepted、stapler 和 Gatekeeper 检查通过后，才能标记为正式签名公证包。现有 package-release.sh 明确生成 ad-hoc 预览版；不要再运行该脚本覆盖已公证包。应以已 stapled 的 App 重新准备拖拽目录、创建 DMG，给 DMG 签名并公证/staple，重新生成校验值。流程参见 [Apple 发行说明](https://developer.apple.com/macos/distribution/) 和 [公证文档](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。

最终仍需在没有开发环境的干净 Mac 上测试网络下载后的 Gatekeeper、拖拽安装、登录启动、真实扫描与应用启动。当前 Apple Silicon 本机运行不能替代 Intel 真机、多屏和所有全屏视频场景验收；没有编造已签名、公证或跨机器验证结果。
