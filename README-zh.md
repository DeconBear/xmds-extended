# xmds-extended

[English](README.md) | [中文 (简体中文)](README-zh.md)

[Project Site](https://deconbear.github.io/xmds-extended/) | [项目网站](https://deconbear.github.io/xmds-extended/zh/)

`xmds-extended` 是基于 XMDS2 的非官方衍生仓库，当前首先聚焦于跨平台维护，其中最重要的第一步是 Windows 原生支持。

## 上游来源

当前仓库源自 XMDS2 项目：

- 上游项目页：https://sourceforge.net/projects/xmds/
- 上游文档站：https://xmds.sourceforge.net/

当前仓库不是 XMDS2 官方仓库。

## 当前分支增加了什么

- 不依赖 MSYS / WSL 的 Windows 原生支持
- Windows 便携式安装与发布打包
- Windows 便携安装的升级与卸载流程
- Windows / Linux / macOS 持续集成
- 中英双语项目页面与教程材料

## Windows 快速开始

Windows 用户推荐直接从 GitHub Release 下载便携安装包：

1. 下载最新的 `xmds-extended-windows-portable-*.zip`
2. 解压到一个临时目录
3. 运行：

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\install_windows.ps1
   ```

4. 选择一个尽量短的安装目录，例如 `D:\xmds`
5. 按需决定是否把安装目录加入 `PATH`

安装完成后：

- 可以在任意目录执行：

  ```powershell
  run_xmds C:\path\to\simulation.xmds
  ```

- 升级时重新运行新的 `install_windows.ps1`，并选择同一个安装目录即可
- 卸载时执行：

  ```powershell
  uninstall_xmds
  ```

当前便携安装器默认要求目标机器已经安装好 Conda 或 Miniforge。

## 教程

当前仓库的完整双语教程放在 [`tutorials/`](tutorials/) 目录：

- 英文教程：[`tutorials/README.md`](tutorials/README.md)
- 中文教程：[`tutorials/README-zh.md`](tutorials/README-zh.md)

教程内容结合了 XMDS 官方文档和当前分支的实际工作流，覆盖 Windows 便携安装、`run_xmds`、升级、卸载以及基于官方示例的学习路径。

## GitHub Pages

当前仓库会通过 GitHub Pages 发布中英双语项目页面：

- 英文页：https://deconbear.github.io/xmds-extended/
- 中文页：https://deconbear.github.io/xmds-extended/zh/

Pages 会介绍当前分支、提供 Release 入口，并给出双语教程入口。

## 自动化

当前 GitHub Actions 负责：

- Windows / Linux / macOS 的持续集成
- Windows 便携包生成
- `v*` 标签的 GitHub Release 发布
- `site/` 目录的 GitHub Pages 部署

Release 说明维护在 [`release-notes/`](release-notes/) 目录。

## 许可证与署名

XMDS2 仍然是上游项目，原始代码的版权归原作者所有。

当前仓库保留了 XMDS2 的原始许可证与版权说明：

- [`COPYING`](COPYING)
- [`COPYRIGHT`](COPYRIGHT)

具体条款请以这些文件为准。
