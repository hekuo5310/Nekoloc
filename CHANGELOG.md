# 更新日志（Changelog）

Nekoloc（前身 NodeLoc APP）—— [NodeLoc](https://www.nodeloc.com) 第三方开源猫咪主题客户端的全部版本变更记录。

各版本安装包与详细说明见 [Releases](https://github.com/hekuo5310/Nekoloc/releases)。

---

## [v1.3.3] — 2026-09-26 · 日常使用与可靠性

- 支持编辑服务端允许修改的帖子，保留原始 Markdown；支持设置话题的关注、追踪、普通和静音级别。
- 修复浏览器授权后的写入与图片上传、分类颜色、搜索竞态、收藏记录匹配和楼层加载。
- 站内普通话题链接在客户端打开，楼层专属链接保留浏览器的精确定位。
- 修复 CSRF 失效时登录递归、错误信息展示及应用更新检查的旧仓库地址。
- 新增回归测试，Android、iOS、macOS、Windows 和 Linux 构建通过。

**详细对比**：[v1.3.2...v1.3.3](https://github.com/hekuo5310/Nekoloc/compare/v1.3.2...v1.3.3)

---

## [v1.3.2] — 2026-09-05 · 发帖设备信息

### 📱 新功能：发帖显示设备信息（对齐官方 APP）

移动端发帖 / 回复时，帖子下方显示设备徽章（如「Pixel 8 Pro」），与 NodeLoc 官方 APP 的 `mobile_source` 功能一致。

- **等级开关**：设置页新增四档开关 —— 关闭 / 仅平台 / 品牌 / 完整型号（默认完整型号），并实时预览当前设备将显示的徽章文本
- **Android**：按官方逻辑识别子品牌（iQOO / Redmi / POCO / realme / HONOR / Nothing），未命中子品牌时显示厂商名（Build.MANUFACTURER）
- **iOS**：硬件标识（utsname.machine）自动转换为友好型号名，如 `iPhone16,2` → 「iPhone 15 Pro Max」；未收录的新机型回退为泛称
- **隐私边界**：桌面端（Windows / macOS / Linux）与 Web 不发送任何设备信息；私信不携带设备信息，仅公开帖与回复生效

### 🔧 内部改进

- 新增 `device_info_plus` 依赖（读取设备品牌 / 型号）
- 发帖（`createTopic`）与回复（`createReply`）请求体自动合并 `mobile_source_*` 字段
- 设置项持久化（SharedPreferences `post_source_level`），升级保留用户选择
- 单元测试覆盖等级语义 / 子品牌识别 / iOS 型号映射（12 用例）

**详细对比**：[v1.3.1...v1.3.2](https://github.com/hekuo5310/Nekoloc/compare/v1.3.1...v1.3.2)

---

## [v1.3.1] — 2026-08-31 · 品牌打磨

### 🎨 新图标

- 应用图标更换为新设计稿：黑底猫面字标（双行 neko/loc 排版 + 猫耳 + 胡须 + 翘尾），全平台同步

### 🐛 修复

- **Windows 顶栏透明**：无边框窗口下自绘标题栏缺少背景色导致透出桌面，现填充主题色并加底部分隔线
- 原生窗口背景改为暖黑色（#12100D），启动不再闪白
- 补齐 v1.3.0 遗漏的品牌改名：窗口标题、标题栏文字、登录授权页标题、User-Agent、授权应用名、个人页版本行、Android 更新包名 —— 全部统一为 Nekoloc

> 仓库已更名为 hekuo5310/Nekoloc，旧地址自动重定向，无需更换书签。

**详细对比**：[v1.3.0...v1.3.1](https://github.com/hekuo5310/Nekoloc/compare/v1.3.0...v1.3.1)

---

## [v1.3.0] — 2026-08-29 · Nekoloc 品牌重塑

本客户端正式更名为 **Nekoloc**（neko 猫 + loc NodeLoc）—— 一只爱逛 NodeLoc 的第三方猫咪客户端，与 NodeLoc 官方无关。

### 🎨 品牌设计（猫元素全面融入）

- **新字标**：neko（绿）+ loc（橙），顶部两只猫耳，结尾一条甩出的 S 形猫尾
- **新应用图标**：绿橙渐变底 + 白色猫耳字标（各平台启动器名称同步改为 Nekoloc）
- **新加载动画**：猫耳先立起 → "nekoloc" 逐笔写出 → 猫尾甩出（3.5s 循环），全局加载态焕新
- **猫爪空态**：所有「空空如也」页面换上猫爪图标
- **彩蛋**：设置页「关于」标题连点 5 次，有惊喜 🐾

### ✨ 体验与新功能

- **开屏动画完整播放**：启动页第一次加载会完整播完一轮品牌动画再进入应用
- **全屏图片查看器**：帖子图片点击全屏查看，双指缩放、双击放大、多图左右切换、页码指示

### 🔧 其他

- 应用 User-Agent 更新为 `Nekoloc/x.y.z`；更新检查、设置页关于信息同步 Nekoloc 品牌与第三方免责声明
- 安装包文件名改为 `Nekoloc-*`（Android）；修复模板测试为真实冒烟测试

**详细对比**：[v1.2.1...v1.3.0](https://github.com/hekuo5310/Nekoloc/compare/v1.2.1...v1.3.0)

---

## [v1.2.1] — 2026-08-29 · 品牌加载动画

### 品牌加载动画

- 全新「nodeloc」字标加载动画：绿橙双色字母逐笔写出 → 悬停 → 淡出，3.5 秒循环
- 取代全部整页加载占位（9 个屏幕）、启动页与列表「加载更多」状态
- 按钮内的忙碌小菊花保留（尺寸语义更适合）

### 内部改进

- 修复全部静态分析告警（flutter analyze 0 issue）
- 版本号 1.2.0 → 1.2.1

**详细对比**：[v1.2.0...v1.2.1](https://github.com/hekuo5310/Nekoloc/compare/v1.2.0...v1.2.1)

---

## [v1.2.0] — 2026-08-24 · 表情反应 + 自动更新检查

### 🎭 表情反应（discourse-reactions 插件）

- 话题详情支持 5 种表情：红心 / 赞同 / 哈哈 / 惊讶 / 庆祝
- 单击点赞按钮 = 快速红心；长按或点小箭头 = 打开 5 表情选择器
- 端点逆向自站点前端 JS：`PUT /discourse-reactions/posts/{id}/custom-reactions/{emoji}/toggle.json`

### 🔄 自动更新检查

- 启动后台查询 GitHub Releases 最新版本并比较版本号
- 首页顶部新版本横幅 + 更新说明对话框；设置页「检查更新」一键手动检查
- 下载按钮直达对应平台安装包（Android = universal APK，Windows/macOS/Linux = 对应压缩包，iOS = Release 页）

### 内部改进

- 版本号 1.1.0 → 1.2.0

**详细对比**：[v1.1.0...v1.2.0](https://github.com/hekuo5310/Nekoloc/compare/v1.1.0...v1.2.0)

---

## [v1.1.0] — 2026-08-23 · Roadmap 全部功能

### ✨ 新功能

- **浏览器授权登录（User API Key 流程）**：RSA-2048 + PKCS1v15，内置 webview 打开授权页并拦截 `discourse://` 回调；支持第三方 OAuth（LinuxDo Connect 等）、邮箱登录链接、2FA 等站点提供的全部登录方式
- **私信**：会话列表 / 多收件人新建 / 回复（`target_usernames[]` 数组格式）
- **图片上传**：编辑器选择本地图片上传（`/uploads.json`），自动以 Markdown 插入正文
- **收藏**：新版 `bookmarkable_id` / `type=Post` API，话题内一键收藏 / 取消
- **阅读进度同步**：离开话题时静默上报阅读时间（`/topics/timings`），与网页版共享已读状态
- **桌面端自定义标题栏**：window_manager；Windows 无边框 + 自绘按钮，macOS 隐藏原生标题栏

### 🔧 变更

- 站点固定为 www.nodeloc.com，移除多站点切换
- 许可证 MIT → **MPL-2.0**
- CI：Linux 增加 webkit2gtk 依赖；macOS 沙盒增加文件选择权限

---

## [v1.0.x] — 2026-08-23 · 首个版本（初始开发期）

> 首个可用版本，尚未发布正式 Release（正式发版自 v1.1.0 起）。

### ✨ 核心功能

- Flutter 单代码库覆盖 **Android / iOS / Windows / macOS / Linux** 五平台
- Discourse 用户级 API：账号密码登录（支持 2FA 动态口令，CSRF / Cookie 会话管理）
- 话题流（最新 / 热门 / 新帖 / 未读）、分类浏览、话题详情（HTML 富文本渲染）、发帖 / 回复、点赞、通知中心、搜索、个人中心
- NodeLoc 官方品牌配色（暖黑 + 松石绿 + 橘橙），深浅双主题

### 🐛 发布前关键修复

- 点赞端点修正为 `POST /post_actions`（PUT 返回 404）
- 分类支持子分类展平；发帖分类选择器只列子分类（顶级分类为容器不可发帖）
- 已用真实账号全流程验证：登录 / 浏览 / 发帖 / 回复 / 点赞 / 通知 / 搜索

### 🔧 基础设施

- GitHub Actions 五平台自动编译工作流 + tag 自动发版（含 macOS ditto 打包、Windows 控制台 UTF-8、绝对路径打包等一系列构建修复）

---

## 版本时间线总览

| 版本 | 日期 | 主题 |
|---|---|---|
| v1.0.x | 2026-08-23 | 首个五平台版本（未发正式 Release） |
| v1.1.0 | 2026-08-23 | Roadmap 全部功能：授权登录 / 私信 / 上传 / 收藏 / 进度同步 |
| v1.2.0 | 2026-08-24 | 表情反应 + 自动更新检查 |
| v1.2.1 | 2026-08-29 | 品牌加载动画 |
| v1.3.0 | 2026-08-29 | 品牌重塑 Nekoloc（猫主题 + 图片查看器） |
| v1.3.1 | 2026-08-31 | 新 1:1 猫面图标 + Windows 顶栏修复 |
| v1.3.2 | 2026-09-05 | 发帖设备信息（对齐官方 APP） |
