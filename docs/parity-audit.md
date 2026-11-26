# 与参考客户端（nodeloc-android）的功能对照

状态：`已有` 已实现；`部分` 实现了主要路径；`待做` 尚未实现。

| 参考页面 | 状态 | 备注 |
| --- | --- | --- |
| FeedScreen / TopicList | 已有 | |
| ReaderScreen（嵌套回复树） | 已有 | 阅读器顶部开关切换嵌套视图，可按热门、最新、最早排序并逐楼展开 |
| ComposeScreen | 已有 | 含红包、抽奖、GIF、图片编辑 |
| ImageEditorScreen | 已有 | 旋转、翻转、裁剪、缩放 |
| VideoEditorScreen / VideoFeed | 待做 | 需要平台媒体管线 |
| NodesScreen / CreateNodeScreen | 已有 | |
| NodeDetailScreen | 已有 | 介绍、成员数、加入退出、子节点 |
| NodeGroupScreen | 已有 | 子节点列表已合并进节点详情 |
| NodeSearchScreen | 已有 | |
| SearchScreen | 已有 | |
| ProfileScreen / PublicProfileScreen | 已有 | |
| ProfileEditScreen | 已有 | |
| UpgradeProgressScreen | 已有 | |
| BadgesScreen（徽章与头衔） | 已有 | 徽章列表；头衔可在资料编辑中从可用徽章中选择 |
| 关注者列表 | 不适用 | 参考项目只显示数量，没有列表页 |
| BlockedUsersScreen | 已有 | |
| PostSourceScreen（发帖设备信息） | 已有 | 设置中的档位 |
| InboxScreen / ChatConversationScreen | 已有 | 频道、消息、实时推送、编辑删除、图片附件、线程、成员、离开频道、通知级别已有。参考客户端没有添加或移除成员、设置角色的接口，因此不提供 |
| MessagesScreen（私信） | 已有 | |
| NotificationsScreen | 已有 | |
| NotificationPreferencesScreen | 已有 | 偏好页 |
| EmailSettingsScreen | 已有 | 偏好页 |
| PrivacySettingsScreen | 已有 | 偏好页 |
| PushSettingsScreen | 已有 | 设置中的类别开关 |
| InterfaceSettingsScreen | 部分 | 主题在设置中；字号等待做 |
| AssociatedAccountsScreen | 已有 | 安全页中查看与解除关联 |
| SecurityScreen（两步验证） | 已有 | 备用码、添加、关闭 |
| 会话与登录令牌撤销 | 已有 | 安全页中查看设备、退出单个或其他设备 |
| LoginScreen | 已有 | 账号密码与浏览器授权 |
| WelcomeScreen | 部分 | 登录页承担欢迎页的作用，入口为注册与找回密码 |
| SignupUsername / Email / Password / Gender / Interests | 部分 | 合并为一页：账号信息、站点要求的字段（如性别，从站点设置读取）、兴趣节点（随机 8 个，激活后可加入）。仍是单页，不是分步 |
| ActivationScreen（账号激活） | 已有 | 激活页提示查收邮件并返回登录；激活链接由站点邮件发送，应用内不提供重发 |
| 找回密码 | 已有 | |
| AppsScreen / AppDetailScreen | 已有 | 站点小程序在应用内运行（Android、iOS） |
| WebPageScreen | 已有 | 通过 WebView 打开外部页面 |
| 后台推送 | 部分 | Android 后台定时拉取；iOS 与桌面仅运行时提醒 |
| 自定义信息流（custom-feeds） | 不适用 | 参考项目定义了接口但界面未使用 |

## 已知限制（已确认接受）

以下三项需要原生环境，在当前开发环境中无法构建或验证，经确认作为已知限制收尾：

- **视频剪辑与封面**：参考项目支持视频裁剪和封面选取，需要平台原生媒体管线。本客户端目前没有视频上传流程。
- **iOS 后台推送**：需要 BGTaskScheduler 注册与 Info.plist 配置。当前只在 Android 上做后台定时拉取，iOS 仅在应用运行时提醒。
- **桌面后台推送**：Windows、macOS、Linux 没有对应的后台任务机制，仅在应用运行时提醒。

## 登录状态下的线上核对（2026-11-26）

用真实账号对以下只读接口逐一取了线上响应，再交给客户端自己的解析代码比对：

- `/me`、`/notifications`、`/me/blocks`（结构为 `{users:[{username,…}]}`）、`/me/settings`、`/chat`、私聊与群聊消息、群成员、`/checkin`、`/points`、`/points/history`、`/me/reputation`、`/me/sessions`、`/me/identities`、`/saved`、登录状态下的话题详情（`permissions`、`viewer_vote`、`viewer_bookmarked`）——字段与解析一致。
- 据此修正两处：系统通知没有 `topic_id`，改从 `data.path`（如 `/t/119445`）取话题，点击才能打开；登录设备列表原来把整串 User-Agent 当设备名、IP 当系统名，改为显示「浏览器 · 系统（本机）」与「IP …」。
- 搜索：线上只有 `sort=new` 与 `node=` 会改变结果，`@用户`、`in:title`、`order:`、`tag:` 都只按普通文字匹配，相应筛选已移除，标签改走 `/topics?tag=`。

写操作经账号所有者授权，在 `test` 节点的话题 107256 上用客户端自己的接口代码实测，测试内容均注明「本内容为账号所有者授权的 Nekoloc 客户端功能测试」并已撤销：

- 赞成票与撤销：分数 0 → 1 → 0，正常。
- 收藏与取消收藏：出现在「我的收藏」中，取消后消失，正常。
- 回复与删除：回复成功；删除成功，楼层变为已删除。实测站点对自己刚发的回复给出 `can_delete=false`，删除请求却能成功，因此客户端对自己的回复（一楼除外）总是显示「删除帖子」。删除功能此前缺失，已补上。
- 签到：今天已签到，站点返回「今天已经签到过了」，客户端如实提示。
- 私信：站点拒绝给自己发私信（「不能给自己发私信」），客户端如实提示；没有向他人发送测试私信。

仍未核对：向他人发送私信与聊天消息、发新话题，以及真机上的视频播放与界面表现。
