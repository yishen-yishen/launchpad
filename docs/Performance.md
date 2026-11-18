# 性能

所有性能目标均未测量，不宣称达标。环境：arm64、macOS 26.6.2，Xcode 27.2；具体芯片型号、内存和屏幕刷新率待测量时补录。

Release 构建后，用 Instruments Points of Interest/Time Profiler/Allocations/Energy Log 记录：300 个实际应用，预热后唤起 30 次 P95、100 个词本地搜索 P95、拖动/翻页/文件夹帧耗时、初扫时间、隐藏 5 分钟 CPU、稳态和峰值内存。原始 trace 与采样设置一并留存。当前尚未接入完整 signpost，不能输出规范要求的延迟结论。

图标 NSCache 上限 24 MB，按可见 cell 获取；文件事件监听使用 FSEvents，800 ms 防抖，无高频轮询。搜索转写预计算。缓存上限是配置值，不是实际内存结果。
