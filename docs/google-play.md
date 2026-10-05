# Google Play 签名构建与上传

Android 包名：`net.zerexa.nekoloc`。

仓库的 **Google Play** 工作流自动完成测试、上传密钥签名、AAB 签名与签名证书验证，然后按触发方式选择发布轨道。普通 PR 不会执行 Play 上传或读取真实密钥。

| 触发方式 | Play 轨道 | 版本名称 / 发布名称 |
|---|---|---|
| 推送普通提交到 `main` | 公开测试 `beta` | 提交 SHA 的最后六位，例如 `d05a86` |
| 推送 `v*` 标签 | 正式版 `production` | 去掉 `v` 的版本名称，例如 `1.3.7`；发布名称为 `v1.3.7` |
| `[release]` 提交在 CI 中自动生成标签 | 正式版 `production` | 与上面的标签版本相同 |
| 手动运行 `build-only` | 不上传，保存签名 AAB | 根据所选 `main` / `v*` 标签生成 |
| 手动运行 `auto` | 根据所选 `main` / `v*` 标签选择公开测试 / 正式版 | 同上 |

上传状态为 `completed`，按所选轨道提交发布，仍须遵守 Google Play 的审核和应用发布要求。公开测试是 `beta`，不是内部测试轨道。

**无需填写 versionCode。** 工作流在串行发布任务开始后，使用“从 2020-01-01 UTC 起经过的秒数”自动生成递增整数，测试版和正式版共用这套编号。显示给用户的 versionName 独立于这个整数：`1.3.6` 或提交号都不能用作 versionCode。数字范围在脚本中校验，所有发布共用并发组，运行失败后重新启动工作流会生成新的编号。

若其他发布工具已经使用了比当前时间编号更大的 versionCode，需统一编号策略后再启用此工作流。密集推送时 GitHub 的并发队列可能仅保留最新的等待任务。

## 1. 添加 GitHub Secrets

进入仓库 **Settings → Secrets and variables → Actions → New repository secret**，添加：

| Secret 名称 | 内容 |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `upload-keystore.jks` 文件的 Base64 文本 |
| `ANDROID_KEYSTORE_PASSWORD` | 创建密钥库时的密码 |
| `ANDROID_KEY_ALIAS` | 密钥别名；按教程创建通常为 `upload` |
| `ANDROID_KEY_PASSWORD` | 密钥密码；可能与密钥库密码相同 |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | Google Cloud 下载的服务账号 JSON 文件完整原文（不是 Base64） |

Windows PowerShell 将 JKS 转为 Base64 并复制到剪贴板：

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path '.\upload-keystore.jks').Path)) | Set-Clipboard
```

将剪贴板内容粘贴到 `ANDROID_KEYSTORE_BASE64`。JKS、JSON 和密码不要提交到 Git，上传密钥应另行备份。工作流仅在临时目录还原 JKS，构建后删除；密码通过环境变量读取，不写入 Gradle 文件。

## 2. 首次上架

1. 在 Play Console 创建 Nekoloc；启用 Play 应用签名，让 Google 管理应用签名密钥。工作流使用你自己的**上传密钥**。
2. 打开仓库 **Actions → Google Play → Run workflow**，选择 `main`。
3. `mode` 选 `build-only`，无需填写数字版本号。
4. 下载运行页面 Artifacts 中的 `Nekoloc-Play-<release_name>-<version_code>`，解压得到 `app-release.aab`，手动上传到 Play Console 的公开测试新版本。首次上传将建立包名和上传证书关联。上传到首次手动发布所需轨道，并完成控制台要求的发布流程。
5. 完成 Play Console 要求的应用资料和账号验证。商店资料、数据安全及内容分级等声明需要由维护者根据实际情况填写。

`build-only` 不需要服务账号 JSON，适合先完成首次手动上传。

## 3. 开通自动上传

1. 在 Google Cloud 项目启用 **Google Play Android Developer API**。
2. 创建服务账号并下载 JSON 密钥，保存到 `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`。
3. 在 Play Console **用户和权限**中邀请 JSON 内 `client_email` 对应的服务账号，授予 Nekoloc 的查看应用、发布到测试轨道和发布到正式版所需权限；不需要财务或管理员权限。
4. 在 Play Console 配置公开测试和发布国家 / 地区，并确认账号具备公开测试与正式版发布资格，应用已完成首次发布、资料及审核要求。
5. 之后推送 `main` 自动更新公开测试版；推送 `v*` 标签自动提交正式版。也可手动运行 **Google Play**，将 `mode` 选为 `auto`。

```bash
# 普通提交：公开测试；Play 版本名称为提交号后六位
git push origin main

# 版本标签：正式版；Play 版本名称为 1.3.7
git tag v1.3.7
git push origin v1.3.7
```

这两个 push 是两次发布事件，先推普通提交再补标签会分别提交测试版和正式版。使用仓库原有的 `[release]` 自动发版提交时，Play 会等待 GitHub Release 创建标签后直接提交正式版，避免先发布该提交的测试版。自动创建标签使用的 GITHUB_TOKEN 不会再次触发 push 工作流，所以由 Build Apps 显式调用 Play 工作流。

失败日志中的旧工作流不可通过重跑升级；应在 Actions → Google Play → Run workflow 发起使用新代码的运行。

工作流执行期间的 Artifacts 始终保存签名 AAB；若 Play 上传失败，无须重新编译即可手动上传该文件。不要把既有草稿和新的 API 编辑同时修改，以免产生编辑冲突。

## 与普通构建的区别

**Build Apps** 工作流和历史 GitHub Release 仍沿用原来的构建方式，不使用你的上传密钥。上架请选择 **Google Play** 工作流的签名 AAB，不能把旧 Release 中名为 `playstore.aab` 的文件当作已经正确配置正式上传签名的包。

Google 生成的应用签名密钥与上传密钥通常不同。因此，Play 安装的版本与 GitHub 分发的 APK 可能无法互相覆盖安装。

## 常见错误

- `Package not found`：先用 `build-only` 构建并手动上传一次，确认包名为 `net.zerexa.nekoloc`。
- `Missing GitHub Secrets`：检查上表名称，大小写必须一致。
- 密钥库校验失败：检查 JKS、密钥库密码和 alias；构建签名失败还需检查密钥密码。
- `versionCode` 已使用：先确认是否有其他工具使用更大的编号，再重新启动工作流；同一个编号不能重复上传。
- 权限不足：检查 API 已启用，且服务账号有 Nekoloc 对应轨道的发布权限。
- `Only releases with status draft may be created on draft app`：应用仍为草稿；先用 `build-only` 构建，并在控制台完成首次手动发布。
- 公开测试 / 正式版资格或审核未完成：先完成 Play Console 提示的要求，工作流不能绕过这些限制。

参考：[Flutter Android 发布](https://docs.flutter.dev/deployment/android)、[Google Play API 设置](https://developers.google.com/android-publisher/getting_started)、[上传 Action](https://github.com/r0adkll/upload-google-play)。

## 当前权限报错

如果签名构建已成功，上传步骤返回 `The caller does not have permission`，请核对 JSON 中的 `client_email`：在 Play Console 的“用户和权限”里添加该服务账号，并让它可以访问 Nekoloc (`net.zerexa.nekoloc`)。自动发布需要查看应用信息、发布到测试轨道以及发布到正式版的对应权限。仅在 Google Cloud 中赋予 IAM 角色不能替代 Play Console 的应用权限。还需确认该项目已启用 Google Play Android Developer API。

权限生效后，可在 **Google Play → Run workflow → main → auto** 发起新任务，不再填写 versionCode。若仍报错，应继续检查服务账号所属开发者账号、包名和应用访问范围。
