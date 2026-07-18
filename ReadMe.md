# 灵屿 Lingyu

灵屿是一个面向 macOS 刘海屏的个人效率工具，把媒体控制、应用启动、剪贴板、文件 Shelf、番茄钟、系统监控和 Codex 状态集中在屏幕顶部。

本项目是在 [Atoll](https://github.com/Ebullioscopic/Atoll) 基础上持续修改的 GPLv3 衍生版本，并保留其上游项目与 boring.notch 等项目的版权和许可说明。当前版本主要面向个人开发和自用。

## 当前改动

- 更紧凑、圆润的刘海展开界面和深色设置页。
- 顶部功能图标支持触控板横向滚动。
- 长按顶部图标进入排序状态，拖动后保存自定义顺序。
- 收起后重新展开时恢复上次使用的页面；APP 搜索页作为临时页面，不覆盖记录。
- APP Finder 支持搜索、最近使用、收藏、键盘选择和回车启动。
- 独立媒体、系统监控、Codex、剪贴板、Shelf 与番茄钟页面。
- 图片剪贴板支持重新复制和拖放到支持文件上传的应用。
- 下载、音乐、番茄钟和 Shelf 实时活动根据最近主动访问项目决定优先显示。
- Codex 本地任务概览和订阅续费提醒。
- 系统状态与日常关怀提醒。

## 系统要求

- macOS 14.6 或更高版本。
- 推荐带刘海的 Apple Silicon MacBook。
- Xcode 15 或更高版本；当前开发环境使用 Xcode 26。

## 从源码运行

1. 克隆仓库并进入目录。
2. 用 Xcode 打开 `DynamicIsland.xcodeproj`。
3. 等待 Swift Package 依赖解析完成。
4. 选择 `DynamicIsland` Scheme 和 `My Mac`，按 `Command + R`。

也可以双击仓库根目录的 `构建并运行 灵屿.command`。脚本会编译 Debug 版本、完整同步到 `~/Applications/Lingyu.app` 并启动。首次切换到这个统一名称后，macOS 可能会要求重新授予一次辅助功能权限。

## 顶部导航使用方法

- 鼠标放在顶部图标区域，触控板双指左右滑动，可查看被实体刘海遮挡或超出宽度的图标。
- 点击图标切换功能页面，选中的图标会自动滚动到可见区域。
- 长按任一图标约 0.45 秒，出现橙色标记后进入排序状态；再拖动图标到目标位置，松手即保存。
- 在页面记忆开启时，收起后重新展开会回到上次使用的常规页面。

## 测试

```bash
xcodebuild \
  -project DynamicIsland.xcodeproj \
  -scheme DynamicIsland \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData \
  -disableAutomaticPackageResolution \
  CODE_SIGNING_ALLOWED=NO \
  test
```

## 权限说明

部分功能会按需申请辅助功能、日历、提醒事项、摄像头、下载文件夹等 macOS 权限。开发版更新时应保持应用路径和 Bundle ID 稳定，否则 macOS 可能把它识别为另一份应用并重新请求授权。

## 许可证与上游归属

灵屿继续采用 [GNU General Public License v3.0](LICENSE)。分发修改版时必须同时提供相应源代码并保留许可证与版权说明。

- 上游项目：[Ebullioscopic/Atoll](https://github.com/Ebullioscopic/Atoll)
- Atoll 的基础来源：[TheBoredTeam/boring.notch](https://github.com/TheBoredTeam/boring.notch)
- 其他依赖和致谢见 [NOTICE](NOTICE) 以及源码中的版权头。
