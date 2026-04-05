# XMDS Extended 教程

[English](README.md) | [中文 (简体中文)](README-zh.md)

这份教程面向当前的 `xmds-extended` 仓库，内容结合了 XMDS 上游官方文档和当前分支新增的 Windows 原生工作流。

## 1. XMDS 是什么

XMDS2 是一个用于求解常微分方程、偏微分方程和随机微分方程的代码生成框架。你先写一个 `.xmds` 模型描述文件，XMDS 再把它转换成 C++、编译，并运行最终生成的程序。

官方资料入口：

- 总览首页：https://xmds.sourceforge.net/
- 安装文档：https://xmds.sourceforge.net/installation.html
- Worked Examples：https://xmds.sourceforge.net/worked_examples.html
- XML 结构参考：https://xmds.sourceforge.net/reference_schema.html

## 2. 当前分支做了什么

XMDS 官方文档对 Linux 和 macOS 的覆盖更成熟，而当前分支主要补上了 Windows 原生使用路径：

- 不依赖 MSYS / WSL 的 Windows 原生支持
- Windows 便携安装与 GitHub Release 分发
- 一条命令完成编译和运行的 `run_xmds`
- 便携安装的升级与卸载
- Windows / Linux / macOS 持续集成

## 3. 推荐学习顺序

如果你刚开始接触 XMDS，建议按这个顺序上手：

1. 先装好 Windows 便携版
2. 先跑通 `examples/lorenz.xmds`
3. 再去读这个 `.xmds` 文件的结构
4. 再看官方的 worked examples
5. 最后从修改已有示例开始，而不是一开始完全从零写脚本

## 4. Windows 安装

Windows 下最推荐的方式是直接用 GitHub Release 里的便携安装包。

### 前提条件

- Windows PowerShell
- 目标机器已经安装好 Conda 或 Miniforge
- 选择一个较短的安装路径，例如 `D:\xmds`

### 安装步骤

1. 从 Releases 下载最新的 `xmds-extended-windows-portable-*.zip`
2. 解压到一个临时目录
3. 在解压目录打开 PowerShell
4. 运行：

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\install_windows.ps1
   ```

5. 选择安装目录
6. 决定是否把安装目录加入 `PATH`

### 升级

升级已有便携安装时：

1. 下载新版 zip
2. 运行新版里的 `install_windows.ps1`
3. 选择和旧版本相同的安装目录

### 卸载

- 如果安装目录已经加入 `PATH`：

  ```powershell
  uninstall_xmds
  ```

- 如果没有加入 `PATH`：

  ```powershell
  <InstallDir>\uninstall_xmds.cmd
  ```

## 5. 第一次成功运行

安装完成后，最推荐先跑仓库自带的 Lorenz 示例。

### 如果 `run_xmds` 已在 PATH 中

```powershell
run_xmds E:\path\to\xmds-extended\examples\lorenz.xmds
```

### 如果没有加入 PATH

```powershell
<InstallDir>\run_xmds.cmd E:\path\to\xmds-extended\examples\lorenz.xmds
```

这一条命令内部会完成：

1. 准备运行环境
2. 调用 `xmds2` 处理 `.xmds`
3. 生成 C++ 源码
4. 编译仿真程序
5. 运行生成的 `.cmd` 启动器

运行后通常会看到这些文件：

- `lorenz.cc`
- `lorenz.exe`
- `lorenz.cmd`
- `lorenz.h5`
- `lorenz.xsil`

## 6. 这些生成文件分别是什么

- `.xmds`：模型描述文件
- `.cc`：XMDS 生成的 C++ 源码
- `.exe`：编译后的仿真程序
- `.cmd`：Windows 启动包装器，会先补好 DLL 路径再启动 `.exe`
- `.xsil`：XMDS 输出描述和元数据
- `.h5` / `.dat`：实际数值输出

在 Windows 下，通常应优先运行生成的 `.cmd`，而不是直接双击 `.exe`。

## 7. 如何读懂一个简单的 XMDS 脚本

当前仓库里最适合入门的例子之一是 [`../examples/lorenz.xmds`](../examples/lorenz.xmds)。

里面最关键的块包括：

- `<simulation>`：根元素
- `<name>`：仿真名称
- `<features>`：全局常量和额外特性
- `<geometry>`：传播维度和空间维度
- `<vector>`：需要演化的变量和初始值
- `<sequence>`：积分器与方程本体
- `<output>`：输出哪些量

对 `lorenz.xmds` 来说：

- 传播维度是时间 `t`
- 演化变量是 `x`、`y`、`z`
- 积分算法是 `ARK89`
- 输出保存的是 `xR`、`yR`、`zR`

它的优点是规模小、结构完整，而且和 Lorenz 系统一一对应，特别适合第一次读 XMDS 输入格式。

## 8. 如何在任意目录工作

安装完成后，你并不需要在仓库目录里工作。

例如：

```powershell
run_xmds D:\Simulations\my_case.xmds
```

XMDS 会在 `my_case.xmds` 所在目录中生成：

- `.cc`
- `.cmd`
- `.exe`
- 输出文件

这也是当前 Windows 便携版最推荐的工作方式。

## 9. 绘图与 Python 辅助脚本

如果你有读取 XMDS 输出并绘图的 Python 脚本，可以用：

```powershell
run_plot D:\Simulations\plot_result.py
```

这个入口会使用安装好的 runtime，并处理 `PYTHONPATH` 和绘图后端设置。

## 10. 如何继续学习 XMDS 本身

真正学习 XMDS 语言本体，最好的资料仍然是官方文档。

建议优先看这些页面：

- 官方首页：https://xmds.sourceforge.net/
- Worked Examples：https://xmds.sourceforge.net/worked_examples.html
- 安装文档：https://xmds.sourceforge.net/installation.html
- XML 结构参考：https://xmds.sourceforge.net/reference_schema.html

其中 worked examples 特别重要，因为它是按难度逐步展开的，从简单系统一路到 PDE、随机系统、FFT、MPI 和更复杂的基变换。

## 11. 新项目建议工作流

对于当前分支，比较稳妥的工作流是：

1. 先找到一个最接近你问题的现有示例
2. 复制并重命名
3. 修改 globals、vectors、operators 和 output
4. 用 `run_xmds` 反复编译和运行
5. 拿结果和已有基准对比
6. 需要时再补绘图脚本

## 12. 常见问题

### `run_xmds` 无法识别

安装后请开一个新终端，或者直接用完整路径：

```powershell
<InstallDir>\run_xmds.cmd C:\path\to\simulation.xmds
```

### HDF5 / FFTW / DLL 相关报错

优先运行生成的 `.cmd` 启动器，不要直接执行 `.exe`。

### 提示找不到 MPI

这只代表当前环境没有 MPI 能力。普通单进程脚本仍然可以正常使用。

### 安装路径太长

请改用更短的安装目录。当前捆绑的 Windows 工具链在短路径下更稳定。

## 13. 当前仓库里的相关资料

- 项目总览：[`../README.md`](../README.md)
- 英文教程：[`README.md`](README.md)
- Windows 原生使用说明：[`../docs/windows-native-guide-zh.md`](../docs/windows-native-guide-zh.md)
- 便携安装设计：[`../docs/windows-portable-installer-design-zh.md`](../docs/windows-portable-installer-design-zh.md)
- 升级设计：[`../docs/windows-portable-upgrade-design-zh.md`](../docs/windows-portable-upgrade-design-zh.md)

## 14. 资料来源说明

这份教程主要依据：

- XMDS2 上游官方文档站
- XMDS 自带 worked examples 与示例脚本
- 当前仓库已经实现并验证的 Windows 原生工作流
