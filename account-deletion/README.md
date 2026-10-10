# Nekoloc 账户注销入口

固定公开地址：**https://closeac.d-dos.cc/delete-account**。此地址不包含用户名占位符，供 Google Play 数据安全性表单填写。

此入口按 NodeLoc 的人工注销流程提供引导：跳转到 `https://www.nodeloc.com/u/{真实用户名}/preferences/account`，提示用户点击页面下方“请求归档”，由 NodeLoc 管理员手动处理注销。页面不会代替用户提交注销请求，也不会承诺即时删除。

## 登录流程

1. 点击“使用 NodeLoc 登录”，通过 NodeLoc 官方 OAuth 授权。
2. 服务端换取访问令牌并从 UserInfo 获取 `preferred_username`，不把昵称或用户 ID 当用户名。
3. 回调返回不带授权码的固定入口，展示用户名、人工注销说明和 3 秒倒计时；用户可取消自动跳转或立即前往。
4. 自动登录未配置或暂时失败时，用户仍可输入自己的 NodeLoc 用户名使用相同的跳转流程。

仅申请 `openid profile`，不申请邮箱、不建立本地用户数据库、不保存访问令牌。用于跳转的用户名暂存于最长 5 分钟的 HttpOnly 加密 Cookie，展示时立即清除。OAuth 授权码和用户名的查询字符串不应记录到访问日志。

## OAuth 配置

在 NodeLoc OAuth 应用配置中登记精确的回调地址：

`https://closeac.d-dos.cc/auth/nodeloc/callback`

将应用的 `NODELOC_CLIENT_ID` 和 `NODELOC_CLIENT_SECRET` 配置为 Cloudflare Worker `nekoloc-account-deletion` 的 Secret。Client Secret 不应放入前端、仓库或 URL。已有 Wiki 应用若不能登记多个回调地址，需要为此入口创建独立应用。

Cookie 加密密钥 `SESSION_SECRET` 为 32 字节随机数据的 base64url 编码，首次部署已单独生成并保存为 Worker Secret。自行部署时可用 `node -e "console.log(require('crypto').randomBytes(32).toString('base64url'))"` 生成，再用 `npx wrangler secret put SESSION_SECRET` 保存。

NodeLoc 发现文档：https://www.nodeloc.com/oauth-provider/.well-known/openid-configuration

官方端点：

- 授权：`https://www.nodeloc.com/oauth-provider/authorize`
- 令牌：`https://www.nodeloc.com/oauth-provider/token`
- 用户信息：`https://www.nodeloc.com/oauth-provider/userinfo`

## 开发与验证

```sh
npm ci
npm test
npm run typecheck
npm run build:check
```

本地开发复制 `.dev.vars.example` 为 `.dev.vars` 并填入测试配置；不要提交 `.dev.vars`。Worker 仅接受指定正式域名的请求，本地集成测试须使用同样的 Host / Origin。

部署后验证公开入口可无登录访问、真实 OAuth 登录、错误/取消授权、3 秒倒计时与取消跳转，并使用自己的账号确认 NodeLoc 人工注销说明。不要为测试点击 NodeLoc 的真实“请求归档”按钮。
