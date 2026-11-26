# Nekoloc

[![Build Apps](https://github.com/hekuo5310/Nekoloc/actions/workflows/build.yml/badge.svg)](https://github.com/hekuo5310/Nekoloc/actions/workflows/build.yml)

**Nekoloc**（neko（猫） + loc（NodeLoc））是 [NodeLoc](https://www.nodeloc.com)（自由、平等、友好、开放、有趣的互联网交流社区）的**第三方开源猫咪主题客户端**，基于 Flutter 构建，一套代码覆盖 **Android / iOS / Windows / macOS / Linux**。

界面遵循 NodeLoc 官方品牌风格：暖黑背景 + 松石绿 / 橘橙双色主色调（提取自官网主题配色方案），并在品牌设计中融入猫元素：猫耳字标、甩尾加载动画、猫爪空态与黑底猫面图标。

> 本项目为社区驱动的非官方第三方客户端，站点地址固定为 `https://www.nodeloc.com`，与 NodeLoc 官方无关。

## 功能

- **登录**
  - 账号密码登录（用户名 / 邮箱 + 密码），自动识别并支持 2FA 动态口令
  - 浏览器登录：在内置浏览器中打开站点登录页完成登录（PKCE），支持 GitHub、X 等**第三方账号、两步验证和人机验证**，完成后自动返回应用
  - 凭据仅保存在设备本地，不上传任何第三方服务器
- **话题流**：最新 / 热门 / 新帖 / 未读，下拉刷新 + 无限滚动
- **分类浏览**：分类与子分类，点击进入分类话题列表
- **话题详情**：Discourse 原生 HTML 富文本渲染（引用块、代码块、图片、链接等），楼层分页加载；**图片全屏查看器**（双指缩放 / 双击缩放 / 多图左右切换 / 页码指示）
- **互动**：赞成 / 反对票（站点的“赞”即赞成票），回复楼层，发起新话题（Markdown，需选择节点）
- **投票与写作工具**：帖子内单选 / 多选投票及撤回；Markdown 格式工具与本机预览、投票区块插入；搜索按标题 / 作者 / 标签 / 排序筛选和分页；逐楼收藏、收藏分页与取消收藏
- **官方客户端互动功能**：帖子举报（站点动态理由）、标签话题列表、帖子赞成 / 反对投票、公开用户资料与关注 / 忽略；编辑器本机草稿自动恢复
- **图片上传**：编辑器中选择本地图片，上传后自动以 Markdown 语法插入正文
- **私信与聊天**：私信即一对一聊天（含群聊），公开聊天频道，图片消息，实时推送
- **收藏**：话题一键收藏 / 取消收藏，收藏列表统一管理
- **阅读进度同步**：自动上报阅读时间，与网页版共享已读 / 未读状态
- **通知中心**：回复、引用、提及、点赞等通知，点击跳转话题、一键全部已读
- **个人中心**：资料、发帖 / 徽章统计、我的主题、我的收藏、退出登录
- **搜索**：全文搜索
- **自适应布局**：手机端底部导航栏，桌面端侧边导航栏
- **桌面体验**：Windows / macOS 自定义标题栏（拖拽移动、最小化 / 最大化 / 关闭），默认窗口尺寸与居中
- **品牌加载动画**：猫耳立起 → "nekoloc" 字标逐笔写出 → 甩尾的描边动画（3.5s 循环），取代全局所有整页加载占位、启动页与列表加载更多状态；启动页首次加载完整播完一轮动画再进入应用
- **猫咪元素彩蛋**：空态默认猫爪图标，设置页关于标题连点 5 次有惊喜
- **自动更新检查**：启动时后台检查 GitHub Releases，发现新版本在首页顶部展示横幅并打开对应平台安装包下载

## 下载安装

### 方式一：Actions 构建产物（最新代码）

每次推送代码后，[Actions](https://github.com/hekuo5310/Nekoloc/actions/workflows/build.yml) 会自动编译全部平台。进入最新的 `Build Apps` 运行记录，在页面底部 **Artifacts** 区域下载：

| 产物 | 平台 | 说明 |
|---|---|---|
| `nodeloc-android` | Android | 通用 APK、按 ABI 拆分的 APK、AAB |
| `nodeloc-linux` | Linux x64 | tar.gz（解压后运行 `bundle/Nekoloc`） |
| `nodeloc-windows` | Windows x64 | zip（解压后运行 `Nekoloc.exe`） |
| `nodeloc-macos` | macOS (Apple Silicon) | zip（含 .app） |
| `nodeloc-ios` | iOS | **未签名** IPA，需自签后安装 |

### 方式二：Releases（正式版本）

推送 `v*` 标签（如 `v1.2.1`）后，CI 会自动构建全部平台并发布到 [Releases](https://github.com/hekuo5310/Nekoloc/releases)：

```bash
git tag v1.2.1
git push origin v1.2.1
```

### 各平台注意事项

- **Android**：直接安装 APK（universal 版兼容所有架构；arm64 版体积更小）。上架 Google Play 需使用独立签名工作流，见 [Google Play 配置](docs/google-play.md)。
- **iOS**：CI 产出的 IPA 未签名（苹果要求付费开发者账号）。可通过 [AltStore](https://altstore.io)、[Sideloadly](https://sideloadly.io)、爱思助手等工具自签安装，或 fork 后用个人证书在 Xcode 中直接构建
- **macOS**：首次打开若被 Gatekeeper 拦截，在终端执行 `xattr -cr /Applications/Nekoloc.app`，或到「系统设置 - 隐私与安全性」点击「仍要打开」
- **Linux**：需要 GTK3 与 webkit2gtk 运行库（主流发行版自带；Arch 系执行 `sudo pacman -S gtk3 webkit2gtk-4.1`，Debian 系执行 `sudo apt install libgtk-3-0 libwebkit2gtk-4.1-0`）
- **Windows**：内置浏览器登录需要 WebView2 运行时（Windows 10 / 11 一般已预装，缺失时可在微软官网安装）

## 登录与 API 说明

NodeLoc 已从 Discourse 迁移到自建后端，旧的 Discourse 路径对客户端一律返回 410。自 2.0 起，本应用全部改用站点原生接口 **`/api/v1`**（接口与行为参照官方客户端 [nodeloc/nodeloc-android](https://github.com/nodeloc/nodeloc-android) 的 `api-v1` 分支）：

- **鉴权**：Bearer token，只保存在本机；请求只带给站点本身，外站图片等请求不会携带
- **账号密码登录**：`POST /api/v1/auth/login`，支持动态码 / 备用码与“受信任设备”。站点开启人机验证（hCaptcha）时，Android / iOS 在应用内弹出验证；桌面端请使用浏览器登录
- **浏览器登录**：在内置浏览器打开站点登录页（PKCE），登录后站点跳转 `nodeloc://auth?code=…`，应用拦截后用 `POST /api/v1/auth/app/exchange` 换取 token。密码、动态码、人机验证、GitHub / X 等第三方账号都在站点页面里完成；Google 不允许在应用内页面登录
- **实时推送**：服务端事件流 `GET /api/v1/notifications/stream`（SSE）：新通知、新聊天消息即时到达
- **错误**：统一为 `{"error":{"code","message","fields"}}`，站点文案原样展示，状态码不进入界面
- **新版站点没有的功能已隐藏**：表情反应、打赏、聊天消息编辑与线程、私信话题（私信并入聊天）、发帖设备信息、自定义注册字段

## Google Play 发布

`main` 普通提交自动上传 Google Play **公开测试（beta）**，版本名称取提交号后六位；推送 `v*` 标签自动上传 **正式版（production）**。数字 versionCode 自动生成。首次上架仍可手动运行 `build-only` 下载签名 AAB。密钥配置及详细步骤见 [发布指南](docs/google-play.md)。

## 本地开发

Android 软件包名称（applicationId）：`net.zerexa.nekoloc`。生成平台工程后，必须运行下方的平台补丁步骤。

```bash
# 1. 克隆
git clone https://github.com/hekuo5310/Nekoloc.git
cd Nekoloc

# 2. 生成平台工程（平台目录不入库，按本地 Flutter 版本生成）
flutter create . --platforms=android,ios,linux,macos,windows \
  --org com.nodeloc --project-name nodeloc_app

# 3. 打补丁（Android 网络权限、应用名、图标、macOS 沙盒权限等）
python3 -m pip install pillow cairosvg   # 补丁依赖（图标已固定为设计稿，无需重跑 make_icon.py）
python3 scripts/patch_platforms.py

# 4. 运行
flutter pub get
flutter run
```

Linux 构建另需：`sudo apt install cmake ninja-build libgtk-3-dev libwebkit2gtk-4.1-dev`

### 项目结构

```
├── .github/workflows/build.yml   # 五平台自动编译 + tag 自动发版
├── assets/
│   ├── icon/                  # 图标与原始 SVG 字标
│   └── animations/             # 品牌加载动画（animated WebP）
├── scripts/
│   ├── patch_platforms.py        # 平台工程补丁（权限/名称/图标）
│   └── make_icon.py              # 图标生成（渐变底 + 白色字标）
├── lib/
│   ├── api/discourse_api.dart    # 站点 API 客户端（/api/v1，Bearer token）
│   ├── api/v1_mapping.dart       # 新版接口响应 → 界面模型的纯映射
│   ├── models.dart               # 数据模型
│   ├── app_state.dart            # 全局状态（会话/主题/浏览器登录）
│   ├── theme.dart                # NodeLoc 品牌主题
│   ├── oauth/                    # 浏览器登录（PKCE）+ 人机验证弹窗
│   ├── desktop_window.dart       # 桌面窗口与自定义标题栏
│   ├── update_checker.dart       # GitHub Releases 更新检查
│   ├── widgets/                  # 通用组件（含品牌加载动画）
│   └── screens/                  # 各界面
└── pubspec.yaml
```

## License

[MPL-2.0](./LICENSE)


### 桌面安装包（v1.3.8 起）

在 Releases 中，Windows 下载 `Nekoloc-Windows-Setup.exe`，macOS 下载 `Nekoloc-macOS-Installer.pkg`。Windows 默认安装到当前用户目录，支持开始菜单快捷方式和卸载；macOS 安装到 `/Applications/Nekoloc.app`。旧的 ZIP 便携包仍可下载。macOS 包暂未进行 Developer ID 签名与公证，系统可能要求手动允许打开。
