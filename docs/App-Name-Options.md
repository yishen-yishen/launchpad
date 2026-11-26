# 应用名称字段

当前应用标签采用文件名去掉 `.app` 扩展名。例如 `Example.app` 显示为 `Example`。

可用于分析名称差异的元数据包括：文件名、Finder 显示名、`CFBundleDisplayName`、`CFBundleName`、`CFBundleExecutable`、`CFBundleIdentifier`，以及应用提供的本地化名称。它们可能不同，并非每个应用都包含全部字段。

本地分析脚本：`xcrun swift scripts/inspect-app-names.swift`，可附加应用路径。真实应用的采样结果包含安装路径和应用信息，仅保留在本地，不随源码公开。
