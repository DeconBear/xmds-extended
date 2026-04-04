# GitHub Release 与自动打包说明

本文档说明当前仓库如何通过 GitHub Actions 自动生成 Windows 便携安装包，并在需要时发布 GitHub Release。

## 1. 发布渠道选择

当前仓库对 Windows 用户的推荐分发方式是：

- GitHub Releases

不优先使用：

- GitHub Packages

原因很简单：

- 当前交付物是一个用户直接下载的 Windows 便携 zip
- 用户下载后需要解压并运行 `install_windows.ps1`
- 这更符合 Release asset 的分发模型，而不是包管理器模型

## 2. 自动化目标

自动化链路分成两层：

### 2.1 开发阶段

当代码推送到 `main` 分支时：

- 现有 CI 继续执行跨平台 smoke test
- Windows 便携打包 workflow 自动生成 zip
- zip 作为 workflow artifact 上传

这一步的作用是：

- 让维护者在每次 push 后都能拿到最新可下载的便携包
- 不需要每次都手工本地打包

### 2.2 正式发版

当推送符合 `v*` 的 tag，例如：

```text
v0.1.0
```

workflow 会：

- 在 GitHub Windows runner 上重新构建 Windows 便携 zip
- 自动做一次安装器 smoke test
- 将 zip 作为 Release asset 发布到 GitHub Release 页面

## 3. 当前 workflow 约定

自动打包与发布的 workflow 文件是：

- `.github/workflows/windows-portable.yml`

其行为约定如下：

- `push` 到 `main`
  生成 artifact，不直接发 Release
- `push` tag `v*`
  生成 artifact，并自动发 Release
- `workflow_dispatch`
  允许手动触发构建

## 4. 版本命名策略

建议约定：

- 开发中版本：
  - 由 workflow 自动生成为 `main-<shortsha>`
- 正式版本：
  - 使用语义化 tag，例如 `v0.1.0`

对应 zip 文件名为：

```text
xmds-extended-windows-portable-v0.1.0.zip
```

## 5. 推荐发布流程

### 5.1 日常开发

1. 本地修改代码
2. 提交到 `main`
3. GitHub Actions 自动跑 CI
4. GitHub Actions 自动生成 Windows 便携 zip artifact

### 5.2 正式发版

1. 确认 `main` 上 CI 和打包 workflow 通过
2. 创建 tag，例如：

```powershell
git tag v0.1.0
git push origin v0.1.0
```

3. 等待 `windows-portable.yml` 在 tag 上跑完
4. GitHub 自动生成 Release 页面与 zip 附件

## 6. 用户获取方式

最终用户应从这里获取 Windows 版本：

- GitHub Releases 页面

用户不需要：

- 自己执行本地打包脚本
- 自己进入 workflow artifact 页面找临时构建

artifact 更适合维护者测试，Release asset 才是面向用户的正式下载入口。

## 7. 当前限制

当前自动发布仍有这些前提：

- Release asset 只覆盖 Windows 便携安装版
- 目标机器仍需预先安装 Conda 或 Miniforge
- 安装目录必须尽量短，避免 MinGW 深路径问题

## 8. 后续演进建议

后续可以继续做这些增强：

- 发布说明里自动附带 Windows 安装指引
- 把升级说明链接自动写入 Release notes
- 引入校验值，例如 SHA256
- 后续如果安装体验成熟，再考虑：
  - PyPI 命令行前端
  - winget
  - Scoop
  - 真正的 Windows 安装器
