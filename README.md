# Nekoloc

[![Build Apps](https://github.com/hekuo5310/Nekoloc/actions/workflows/build.yml/badge.svg)](https://github.com/hekuo5310/Nekoloc/actions/workflows/build.yml)

**Nekoloc**（neko（猫） + loc（NodeLoc））是 [NodeLoc](https://www.nodeloc.com)（自由、平等、友好、开放、有趣的互联网交流社区）的**第三方开源猫咪主题客户端**，基于 Flutter 构建，一套代码覆盖 **Android / iOS / Windows / macOS / Linux**。

界面遵循 NodeLoc 官方品牌风格：暖黑背景 + 松石绿 / 橘橙双色主色调（提取自官网主题配色方案），并在品牌设计中融入猫元素：猫耳字标、甩尾加载动画、猫爪空态与黑底猫面图标。

> 本项目为社区驱动的非官方第三方客户端，站点地址固定为 `https://www.nodeloc.com`，与 NodeLoc 官方无关。

## 功能

- **登录**
  - 账号密码登录（用户名 / 邮箱 + 密码），自动识别并支持 2FA 动态口令
  - 浏览器授权登录：在内置浏览器中完成站点登录后授权，支持**第三方账号（LinuxDo Connect 等）、邮箱登录链接、2FA 等**站点提供的全部登录方式，授权后凭 RSA 加密的一次性凭据（User API Key）自动返回应用
  - 凭据仅保存在设备本地，不上传任何第三方服务器
- **话题流**：最新 / 热门 / 新帖 / 未读，下拉刷新 + 无限滚动
- **分类浏览**：分类与子分类，点击进入分类话题列表
- **话题详情**：Discourse 原生 HTML 富文本渲染（引用块、代码块、图片、链接等），楼层分页加载；**图片全屏查看器**（双指缩放 / 双击缩放 / 多图左右切换 / 页码指示）
- **互动**：表情反应（红心 / 赞同 / 哈哈 / 惊讶 / 庆祝 五种表情，长按点赞按钮或点击小箭头展开选择器），回复楼层，发起新话题（Markdown）
- **投票与写作工具**：帖子内单选 / 多选投票及撤回；Markdown 格式工具与本机预览、投票区块插入；搜索按标题 / 作者 / 标签 / 排序筛选和分页；逐楼收藏、收藏分页与取消收藏
- **官方客户端互动功能**：帖子举报（站点动态理由）、标签话题列表、帖子赞成 / 反对投票、公开用户资料与关注 / 忽略；编辑器本机草稿自动恢复
- **发帖设备信息**：对齐官方 APP 的 `mobile_source` 功能 —— 移动端发帖 / 回复时在帖子下方显示设备徽章（如「Pixel 8 Pro」），支持 关闭 / 仅平台 / 品牌 / 完整型号 四档设置；Android 按官方逻辑识别子品牌（Redmi / POCO / iQOO / realme / HONOR / Nothing），iOS 输出友好型号名；桌面端不发送
- **图片上传**：编辑器中选择本地图片，上传后自动以 Markdown 语法插入正文
- **私信**：会话列表、新建私信（多收件人）、回复私信
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

本应用全部使用 **Discourse 普通用户端点**（与浏览器访问网页版一致的会话 / 授权机制），不涉及管理员 API Key：

- 账号密码登录：`GET /session/csrf.json` 获取令牌，`POST /session` 登录（自动携带 2FA 字段），Cookie 会话持久化在本机
- 浏览器授权登录：走 Discourse 官方 **User API Key** 流程——应用生成一次性 RSA-2048 密钥对，在内置浏览器中打开 `/user-api-key/new` 授权页（未登录时先跳转站点登录页，此时可使用任意登录方式），授权后站点把加密凭据重定向到 `discourse://` 协议，应用拦截并解密得到 API Key，之后以 `User-Api-Key` 请求头访问只读 / 写入端点
- 其余均为常规端点（`/latest.json`、`/t/{id}.json`、`/posts`、`/post_actions`、`/bookmarks`、`/uploads.json`、`/topics/timings`、`/notifications.json` 等）

## Google Play 发布

在 Actions 中运行 **Google Play**：首次选择 `build-only` 下载签名 AAB；完成首次手动上传后，可选择 `internal-draft` 自动上传内部测试草稿。密钥配置及详细步骤见 [发布指南](docs/google-play.md)。

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
│   ├── api/discourse_api.dart    # Discourse 用户级 API 客户端（Cookie / User-Api-Key 双模式）
│   ├── models.dart               # 数据模型
│   ├── app_state.dart            # 全局状态（会话/主题/浏览器授权登录）
│   ├── theme.dart                # NodeLoc 品牌主题
│   ├── oauth/                    # RSA 工具 + 内置浏览器授权登录
│   ├── desktop_window.dart       # 桌面窗口与自定义标题栏
│   ├── update_checker.dart       # GitHub Releases 更新检查
│   ├── reactions.dart            # 表情反应定义（discourse-reactions）
│   ├── widgets/                  # 通用组件（含品牌加载动画）
│   └── screens/                  # 各界面
└── pubspec.yaml
```

## License

[MPL-2.0](./LICENSE)
