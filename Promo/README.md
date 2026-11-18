# LaunchDock 横屏宣传片

成片：`media/LaunchDock-Promo-1080p.mp4`。28 秒，1920×1080，30 fps，H.264 视频 + AAC 立体声。中文字幕直接合成进画面；无旁白。配乐由 `Render.swift` 合成原创正弦波和弦与琶音，没有使用外部曲库或采样。

## 内容

| 时间 | 画面与信息 |
| --- | --- |
| 0–3 秒 | 品牌、图标与“让常用应用，触手可及” |
| 3–8 秒 | 原生应用网格与翻页 |
| 8–14 秒 | 输入 Calc，筛选 Calculator，启动反馈 |
| 14–23 秒 | 拖拽归类，创建并打开“常用工具”文件夹 |
| 23–28 秒 | 快速搜索、拖拽整理、触发角唤起；作者邮箱 |

## 素材来源

`Capture.swift` 直接编译仓库真实 LauncherView、Grid 和 LayoutEngine，扫描本机实际安装应用，使用临时目录建立演示布局。24 个演示应用来自真实扫描结果，不是模拟应用清单；用户自己的排列、文件夹和配置不参与写入。背景为专门绘制的紫蓝渐变，不包含私人桌面或其他窗口。

录制通过脚本驱动真实搜索控件、页面状态、拖拽目标处理和应用启动路径。后期叠加了说明文字、拖拽指针和浮动图标，便于观看；它不是全程人工鼠标操作录像。Calculator 会被实际打开；录制前已经运行的 Calculator 保持运行，否则录制完成后退出本次启动的 Calculator。触发角只在片尾列为功能，没有单独录制触发角场景。

## 重新生成

需要 macOS 26+、Xcode 命令行工具，以及已有 `build/Development/LaunchDockCore.o` 与 Swift 模块、`dist/LaunchDock.app/Contents/Resources/LaunchDock.icns`。不依赖 ffmpeg、Python 扩展包或云服务。

```sh
# 已有素材：重新渲染并验证
sh scripts/make-promo.sh

# 重新录制真实原生窗口，再渲染并验证
sh scripts/make-promo.sh --capture
```

视频生成与验证源码位于 `Promo/`，素材位于 `media/launchdock-promo/frames/`，抽帧与完整解码报告位于 `media/launchdock-promo/qa/`。成片 SHA-256 位于 `media/launchdock-promo/SHA256SUMS.txt`。

验证包括视频时长、画幅、帧率、840 帧完整解码、音频完整解码及电平，以及关键画面的人工目视检查。未进行外部视频平台上传或不同设备的播放器兼容性验证。
