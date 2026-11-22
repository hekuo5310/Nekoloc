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
| InboxScreen / ChatConversationScreen | 部分 | 频道、消息、实时推送、编辑删除、图片附件、成员、离开频道已有；线程与群管理（设置成员、角色）待做 |
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
