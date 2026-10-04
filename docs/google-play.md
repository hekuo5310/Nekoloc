# Google Play 签名构建与上传

Android 包名：`net.zerexa.nekoloc`。

仓库的 **Google Play** 工作流按需运行，完成测试、上传密钥签名、AAB 签名与签名证书验证，并按所选模式上传内部测试草稿。它只允许从 `main` 运行，不自动向正式版发布，也不会在普通 PR 构建中读取密钥。

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
3. `mode` 选 `build-only`；`version_code` 填正整数，必须大于 Play 已使用的所有版本号。当前源码的默认 versionCode 是 11，未上传过时可用 12；若已用过 12，应选更大的数。运行失败前也可能已上传成功，重试上传应先检查控制台。
4. 下载运行页面 Artifacts 中的 `Nekoloc-Play-<version_code>`，解压得到 `app-release.aab`，手动上传到 Play Console 的内部测试新版本。首次上传将建立包名和上传证书关联。
5. 完成 Play Console 要求的应用资料和账号验证。商店资料、数据安全及内容分级等声明需要由维护者根据实际情况填写。

`build-only` 不需要服务账号 JSON，适合先完成首次手动上传。

## 3. 开通自动上传

1. 在 Google Cloud 项目启用 **Google Play Android Developer API**。
2. 创建服务账号并下载 JSON 密钥，保存到 `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`。
3. 在 Play Console **用户和权限**中邀请 JSON 内 `client_email` 对应的服务账号，仅授予 Nekoloc 的查看应用和发布到测试轨道所需权限，不需要财务、管理员或正式版发布权限。
4. 再运行 **Google Play**，将 `mode` 选为 `internal-draft`，使用新的 `version_code`。
5. 工作流上传到 `internal` 轨道，状态固定为 `draft`。成功后到 Play Console 检查草稿、填写更新说明，并手动提交测试发布。

工作流执行期间的 Artifacts 始终保存签名 AAB；若 Play 上传失败，无须重新编译即可手动上传该文件。不要把既有草稿和新的 API 编辑同时修改，以免产生编辑冲突。

## 与普通构建的区别

**Build Apps** 工作流和历史 GitHub Release 仍沿用原来的构建方式，不使用你的上传密钥。上架请选择 **Google Play** 工作流的签名 AAB，不能把旧 Release 中名为 `playstore.aab` 的文件当作已经正确配置正式上传签名的包。

Google 生成的应用签名密钥与上传密钥通常不同。因此，Play 安装的版本与 GitHub 分发的 APK 可能无法互相覆盖安装。

## 常见错误

- `Package not found`：先用 `build-only` 构建并手动上传一次，确认包名为 `net.zerexa.nekoloc`。
- `Missing GitHub Secrets`：检查上表名称，大小写必须一致。
- 密钥库校验失败：检查 JKS、密钥库密码和 alias；构建签名失败还需检查密钥密码。
- `versionCode` 已使用：选择更大的整数，不能重复使用。
- 权限不足：检查 API 已启用，且服务账号有 Nekoloc 的测试发布权限。

参考：[Flutter Android 发布](https://docs.flutter.dev/deployment/android)、[Google Play API 设置](https://developers.google.com/android-publisher/getting_started)、[上传 Action](https://github.com/r0adkll/upload-google-play)。
