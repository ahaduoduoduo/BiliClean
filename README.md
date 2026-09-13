# BiliClean

为哔哩哔哩 iOS 客户端提供赞助片段跳过、广告过滤、完整视频下载和界面整理的插件。

## 安装

从本仓库 **Releases → Assets** 下载 `BiliClean_版本号.dylib`，使用 IPA 注入工具将它加入哔哩哔哩安装包，完成签名后安装。注入环境需要提供 MobileSubstrate 兼容支持。

安装后，打开 **哔哩哔哩 → 我的 → 设置 → BiliClean**，即可调整功能开关。

- 构建包含 `arm64`、`arm64e` 两种架构，最低部署版本为 iOS 14。
- 当前测试通过版本：哔哩哔哩 **8.76.0**

## 功能

| 功能 | 使用体验 |
| --- | --- |
| 赞助片段跳过 | 根据小电视空降助手的社区标注自动跳过赞助片段，可调整跳过提前量、设置不重复跳过 |
| 完整视频下载 | 下载当前分 P 的完整视频，自动选择账号可获取的最高普通画质，音视频无损合并后保存到照片 |
| 广告过滤 | 移除开屏、信息流和播放器广告，按需过滤带货内容、相关推荐广告及片尾推荐 |
| 关键词屏蔽 | 按普通关键词或正则表达式过滤内容，每条规则可分别用于推荐、动态和评论 |
| 播放速度 | 设置默认倍速，在常见倍速列表中增加 3 倍速 |
| CDN 加速 | 测试播放节点速度，自动选择较快节点，也可手动选择和调整优先顺序 |
| TAB 管理 | 自由选择首页频道、顶部与底部导航项目，单独控制底部发布入口 |
| 界面整理 | 按需隐藏首页直播、图文推荐、竖屏模式、推荐理由、互动弹幕及“我的”页不常用服务 |

## 使用

### 下载完整视频

1. 在视频播放页打开分享面板。
2. 点击 **下载视频**。原来的“下载分享”会被替换；面板没有该入口时，插件会在第三个位置添加按钮。
3. 面板关闭后，顶部半透明胶囊显示下载、合并和保存进度。可以返回列表或切换视频继续观看。
4. 保存成功后显示实际保存位置和完成动画，随后自动隐藏。

下载选择普通 SDR 视频，遇到 HDR 或杜比视界时使用接口提供的普通画质。音视频合并不重新编码，保留完整时长。

有可用相册权限时，视频归入 **BiliBili** 相册；只有“仅添加”权限时，直接保存到系统照片库。保存不要求完整照片访问权限。iOS 15 及以上的有限访问模式支持操作 App 自己创建的相册。

一次下载一个视频，胶囊上的关闭按钮可以取消任务。视频保存失败后，点击胶囊即可重试保存，无需重新下载。任务支持 App 内切换页面；退出进程后不保留任务。

### 跳过赞助与调整播放

在 **BiliClean → 播放** 中开启赞助跳过，设置提前量和默认倍速。片段数据来自 [小电视空降助手](https://bsbsb.top/) 的社区标注。

进入 **CDN 加速** 页面运行测速，选择节点或拖动调整顺序。这里的节点设置用于播放；完整视频下载使用接口返回的原始主备地址。

### 过滤内容与整理界面

在 **屏蔽** 分组中选择要移除的广告类型，并添加关键词规则。在 **首页**、**界面** 分组中调整推荐内容、TAB 和服务入口。不同过滤功能可单独开关，也可通过总开关统一控制。

## 从源码构建

使用 macOS、Xcode 和 [Theos](https://theos.dev/docs/installation-macos)，配置好 `THEOS` 环境变量后运行：

```bash
make clean release
```

输出文件：

```text
dist/BiliClean_1.0.28.dylib
dist/BiliClean_1.0.28.dylib.sha256
packages/com.imlr.bilibilisp_1.0.28_iphoneos-arm.deb
```

版本号取自 `control`。业务代码使用 Objective-C / Logos，音视频合并和相册保存使用系统 AVFoundation、Photos 框架。

维护者在 GitHub 发布与 `control` 版本一致的 Release（例如 `v1.0.28`）后，发布工作流会自动构建并上传 **dylib 和 SHA-256 校验文件**。

## 鸣谢

- [TouchFriend / BiliBiliTweak](https://github.com/TouchFriend/BiliBiliTweak)：广告过滤、设置入口及播放功能的代码参考，原项目采用 MIT 许可证，作者版权声明保留在 [LICENSE](LICENSE) 中。
- [小电视空降助手](https://bsbsb.top/)及其社区贡献者：提供 B站赞助片段数据和 API。
- [bilibili-api-collect](https://github.com/bilibili-plugins/bilibili-api-collect)：提供播放接口、protobuf 字段和音视频流结构资料。
- [yt-dlp](https://github.com/yt-dlp/yt-dlp)：下载功能调研时参考了 B站提取器对 DASH 音视频和画质的处理。
- [Theos](https://github.com/theos/theos)、[Cydia Substrate](https://www.cydiasubstrate.com/) 和 [Frida](https://frida.re/)：提供插件构建、运行时 Hook 与真机调试工具。

## 项目信息

由 **ahaduoduoduo** 维护，主要代码由 AI 辅助编写。

采用 [MIT 许可证](LICENSE)。欢迎通过 Issue 反馈使用体验，或通过 [Buy Me a Coffee](https://www.buymeacoffee.com/ahaduoduoduo) 支持维护。
