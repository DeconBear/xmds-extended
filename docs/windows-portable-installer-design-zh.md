# XMDS Windows 便携式安装版设计 v1

本设计面向当前仓库的 Windows 原生版本，目标是做出第一版“下载 zip、解压、运行安装脚本、完成本地安装”的便携式安装方案。

本设计只覆盖 Windows。
Linux 和 macOS 继续沿用上游和当前仓库已有流程，不纳入这一版安装器范围。

## 1. 目标

第一版需要做到：

- 用户下载 zip 后无需先 `git clone`
- 用户在解压目录中运行安装脚本
- 安装脚本以终端交互方式引导用户完成安装
- 用户可以选择安装目录
- 用户可以选择是否把命令入口加入 `PATH`
- 安装完成后，用户可以在任意目录运行 `run_xmds`
- `run_xmds` 一条命令完成：
  - 环境准备
  - 必要时 XMDS 配置检查
  - `.xmds` 编译
  - 生成程序运行

## 2. 非目标

第一版暂不做这些事：

- 不做 MSI / Inno Setup / NSIS 图形安装器
- 不做 VS Code 插件集成
- 不做 PyPI 发布
- 不做 Linux / macOS 安装器
- 不做自动升级器
- 不做 GUI 配置界面

## 3. 用户体验

### 3.1 分发方式

用户拿到的内容是一个 zip 包，例如：

```text
xmds-extended-windows-portable-v1.zip
```

用户操作流程：

1. 下载 zip
2. 解压到任意临时目录
3. 在解压目录打开 PowerShell
4. 运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\install_windows.ps1
```

### 3.2 安装脚本交互

安装脚本需要至少询问两件事：

1. 安装目录
2. 是否将 `run_xmds` 命令加入 `PATH`

额外约束：

- 安装目录必须尽量短。第一版建议优先使用默认目录，或使用类似 `C:\XMDS-Extended` 这样的短路径。过深路径可能导致捆绑的 MinGW 工具链在 Windows 下无法正确解析头文件。

推荐交互文案：

```text
XMDS Windows Portable Installer v1

Install directory [default: D:\XMDS-Extended]:
Add run_xmds command to PATH? [Y/n]:
Proceed with installation? [Y/n]:
```

### 3.3 安装后使用方式

如果用户没有选择加入 `PATH`：

```powershell
D:\XMDS-Extended\run_xmds.cmd D:\cases\thlcp.xmds
```

如果用户选择加入 `PATH`：

```powershell
run_xmds D:\cases\thlcp.xmds
```

## 4. 目录结构设计

安装包解压后的目录结构建议如下：

```text
xmds-extended-windows-portable/
  install_windows.ps1
  payload/
    app/
      bin/
      docs/
      examples/
      xpdeint/
      README.md
      COPYING
      COPYRIGHT
      run_tests.py
    tools/
      bootstrap/
    manifests/
      install-manifest.json
```

安装完成后的目标目录结构建议如下：

```text
XMDS-Extended/
  run_xmds.cmd
  run_xmds.ps1
  run_plot.cmd
  uninstall_windows.ps1
  app/
    bin/
    docs/
    examples/
    xpdeint/
    README.md
    COPYING
    COPYRIGHT
    run_tests.py
  runtime/
  state/
    install.json
```

说明：

- `app/` 放 XMDS 仓库内容
- `runtime/` 放安装好的本地运行环境
- `run_xmds.cmd` 放在安装目录根部，作为稳定入口
- `state/install.json` 记录安装参数，便于卸载和将来升级

## 5. 环境与依赖策略

第一版建议使用“安装时创建本地 Conda 环境”的方式，而不是在 zip 中直接内置整个环境。

原因：

- zip 体积会明显更小
- 环境路径可以和最终安装目录一致
- 便于后续重新生成和维护
- 第一版实现成本低于预打包完整 runtime

默认环境路径建议：

```text
<InstallDir>\runtime
```

例如：

```text
D:\XMDS-Extended\runtime
```

安装脚本负责在这个路径下创建环境并安装依赖：

- Python 3.11
- Cheetah3
- pyparsing
- mpmath
- numpy
- lxml
- h5py
- hdf5
- fftw
- setuptools
- m2w64-toolchain

## 6. PATH 策略

### 6.1 不暴露内部 `bin`

第一版不建议把下面这个内部目录加入 `PATH`：

```text
<InstallDir>\app\bin
```

原因：

- 这是内部实现目录，不是稳定用户接口
- 后续如果内部布局调整，兼容压力大
- 用户不需要直接接触 `xmds2`

### 6.2 暴露稳定入口

如果用户选择加入 `PATH`，应加入以下两种之一：

1. 安装目录根部
2. 专门的 shim 目录

第一版建议直接加入安装目录根部。

也就是说加入：

```text
<InstallDir>
```

这样用户得到的稳定命令是：

- `run_xmds`
- `run_plot`

而不是内部命令：

- `xmds2`
- `xsil2graphics2`

## 7. `run_xmds` 入口设计

`run_xmds.cmd` 是面向用户的主入口。

### 7.1 功能职责

它应完成这些工作：

1. 接收一个 `.xmds` 文件路径
2. 定位安装目录
3. 激活安装目录中的 `runtime`
4. 设置必要环境变量
5. 切换到 `.xmds` 文件所在目录
6. 调用 `app\bin\xmds2` 编译
7. 自动运行生成的同名 `.cmd`

### 7.2 命令格式

第一版建议支持：

```powershell
run_xmds <path-to-xmds>
```

例如：

```powershell
run_xmds D:\cases\Morgan_01_20240523\thlcp.xmds
```

### 7.3 返回码约定

- 编译失败：返回非零
- 运行失败：返回非零
- 全流程成功：返回零

## 8. 安装脚本职责

`install_windows.ps1` 建议承担这些职责：

1. 检查 PowerShell 和系统基础条件
2. 检查 `conda` 是否可用
3. 询问安装目录
4. 询问是否加入 `PATH`
5. 复制 `payload/app` 到目标目录
6. 在 `<InstallDir>\runtime` 创建 Conda 环境
7. 安装依赖
8. 生成 `run_xmds.cmd` / `run_xmds.ps1` / `run_plot.cmd`
9. 写入 `state/install.json`
10. 如果用户选择加入 `PATH`，将 `<InstallDir>` 加入用户级 `PATH`
11. 输出安装后的使用说明

## 9. XMDS 配置策略

第一版建议不在安装阶段强制跑一次全局 `--reconfigure`。

更稳的做法是：

- 安装阶段只准备好环境
- 第一次执行 `run_xmds` 时自动检查并按需配置

原因：

- 安装阶段不一定已经有用户要编译的实际脚本
- 按需配置更贴近真实运行场景
- 可以减少首次安装失败点

### 9.1 配置目录

默认继续使用 XMDS 当前逻辑：

```text
%USERPROFILE%\.xmds
```

这是第一版的默认方案。

第二版可以考虑把配置重定向到：

```text
<InstallDir>\state\xmds-home
```

但第一版先不改，避免引入额外行为差异。

## 10. 卸载策略

第一版建议提供：

```text
uninstall_windows.ps1
```

它负责：

- 删除安装目录中的应用与环境
- 如果安装时加入了 `PATH`，则移除安装目录

第一版不自动删除：

```text
%USERPROFILE%\.xmds
```

因为这属于用户配置和缓存，删除风险更高。

## 11. 风险与限制

第一版需要明确告知用户这些限制：

- 仍然依赖本机可用的 Conda
- 安装时需要联网下载依赖
- 首次创建环境时间可能较长
- 安装路径过深或特殊字符路径可能增加老工具链问题概率
- 如果用户手动移动安装目录，且此前已加入 `PATH`，需要重新修复入口

## 12. 第一版实现拆分

建议按 4 个小阶段实现：

### 阶段 1：安装脚本骨架

- `install_windows.ps1`
- 交互式目录选择
- 交互式 PATH 选择
- 复制 payload 到目标目录

### 阶段 2：环境创建

- 在 `<InstallDir>\runtime` 创建 Conda 环境
- 安装 XMDS 依赖
- 记录安装状态

### 阶段 3：命令入口

- 生成 `run_xmds.cmd`
- 生成 `run_xmds.ps1`
- 完成任意路径下的 `.xmds` 编译与运行

### 阶段 4：PATH 与卸载

- 可选加入 `<InstallDir>` 到用户 PATH
- 提供 `uninstall_windows.ps1`
- 补充安装后帮助信息

## 13. 第一版验收标准

只有满足下面这些条件，才算第一版设计落地成功：

1. 用户只下载 zip，不需要先 clone 仓库
2. 用户运行 `install_windows.ps1` 后能完成安装
3. 用户可以自定义安装目录
4. 用户可以选择是否加入 PATH
5. 用户在任意目录执行 `run_xmds <script.xmds>` 能成功编译并运行
6. 安装器不会把内部 `app\bin` 直接暴露给用户

## 14. 推荐下一步

基于这份设计，建议下一步直接开始实现：

1. `install_windows.ps1` 骨架
2. `run_xmds.cmd` 骨架
3. `state/install.json` 结构
4. `payload/` 的最小发布内容整理

这样后续就可以从“设计”直接进入“第一版安装器实现”。
