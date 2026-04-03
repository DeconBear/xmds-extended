# XMDS Windows 原生使用教程

本教程适用于当前仓库的 Windows 原生用法。

目标：

- 不使用 MSYS
- 不使用 WSL
- 直接在 Windows PowerShell 中编译和运行 XMDS 脚本

## 1. 当前方案说明

本仓库已经针对 Windows 原生环境做过兼容处理，主要包括：

- 修复旧版 waf 在现代 Windows/Python 环境下的兼容问题
- 修复 Python 3.13 相关兼容问题
- 自动发现本地 HDF5 和 FFTW 库
- 为 Windows 生成 `.cmd` 启动器，自动补齐运行时 `PATH`
- 修复部分 POSIX 接口在 Windows 下的兼容问题，例如 `bzero`、`gettimeofday`
- 调整 Windows 下的默认优化策略，优先保证稳定编译

## 2. 推荐环境

建议使用下面这类环境：

- Windows PowerShell
- Python 3
- MinGW-w64 的 `g++`
- HDF5 和 FFTW 原生 Windows 库

当前仓库已经支持自动优先检测仓库根目录下的：

```text
.conda-xmds-libs
```

如果这个目录中已经包含以下文件，通常不需要再额外指定路径：

- `Library/include/hdf5.h`
- `Library/include/hdf5_hl.h`
- `Library/include/fftw3.h`
- `Library/lib/hdf5.lib`
- `Library/lib/hdf5_hl.lib`
- `Library/lib/fftw3.lib`
- `Library/lib/fftw3f.lib`

## 3. Python 依赖

建议安装这些 Python 依赖：

```powershell
python -m pip install Cheetah3 pyparsing!=2.0.0 mpmath numpy lxml h5py
```

说明：

- `Cheetah3` 用于代码模板生成
- `lxml`、`pyparsing`、`mpmath`、`numpy` 是 XMDS 运行和测试常用依赖
- `h5py` 用于读取和校验 HDF5 输出

## 4. 首次配置

在仓库根目录打开 PowerShell，然后执行：

```powershell
python bin\xmds2 --reconfigure
```

如果本地 `.conda-xmds-libs` 准备完整，配置阶段通常会看到：

- `Checking for HDF5 ... : yes`
- `Checking for FFTW3 ... : yes`

如果缺少 MPI，配置里会提示找不到 `mpic++` 或 `mpiicpc`。这不影响单进程脚本的使用。

## 5. 编译一个示例

例如编译 `lorenz`：

```powershell
python bin\xmds2 examples\lorenz.xmds
```

成功后会生成类似文件：

```text
lorenz.cc
lorenz.exe
lorenz.cmd
```

其中：

- `.cc` 是生成的 C++ 源码
- `.exe` 是编译后的可执行文件
- `.cmd` 是 Windows 下推荐使用的启动包装器

## 6. 运行生成的程序

在 Windows 下推荐直接运行 `.cmd`：

```powershell
.\lorenz.cmd
```

这样做的原因是：

- `.cmd` 会自动把 HDF5/FFTW 所需 DLL 目录加入 `PATH`
- 可以避免直接执行 `.exe` 时出现找不到 DLL 的问题

运行成功后通常会生成：

- `lorenz.h5`
- `lorenz.xsil`

## 7. 编译你自己的脚本

假设你的脚本叫：

```text
my_simulation.xmds
```

编译方式：

```powershell
python bin\xmds2 my_simulation.xmds
```

运行方式：

```powershell
.\my_simulation.cmd
```

## 8. 运行测试

### 8.1 跑单个测试目录

例如：

```powershell
python run_tests.py geometry
python run_tests.py operators
python run_tests.py io
```

### 8.2 跑全部测试

```powershell
python run_tests.py
```

说明：

- 顶层测试套件可以逐组运行
- 如果机器缺少可选能力，例如 MPI、CBLAS，相关测试会被自动跳过
- 跳过不代表主功能不可用，只表示当前环境没有安装对应可选组件

## 9. 已验证的结果

当前仓库在 Windows 原生环境下已经完成过这些验证：

- `examples\lorenz.xmds` 可以成功编译
- `.\lorenz.cmd` 可以成功运行
- 顶层测试目录已经逐组验证通过

已逐组通过的测试目录包括：

- `fast`
- `features`
- `geometry`
- `integrators`
- `io`
- `mpi`
- `openmp`
- `operators`
- `runtime_lattice`
- `stochastic`
- `transforms`
- `vectors`

其中部分目录中的某些用例会因为缺少可选库而被跳过，这属于预期行为。

## 10. 常见问题

### 10.1 提示找不到 HDF5 或 FFTW

先执行：

```powershell
python bin\xmds2 --reconfigure
```

然后检查：

- 仓库根目录下是否有 `.conda-xmds-libs`
- 该目录下是否包含 `Library/include` 和 `Library/lib`
- `hdf5.lib`、`hdf5_hl.lib`、`fftw3.lib`、`fftw3f.lib` 是否存在

### 10.2 直接运行 `.exe` 报 DLL 相关错误

优先改用：

```powershell
.\simulation_name.cmd
```

不要直接双击或直接执行 `.exe`。

### 10.3 提示找不到 MPI

这表示当前机器没有安装可用的 MPI 编译器或运行时。

影响：

- MPI 脚本不能编译
- MPI 相关测试会被跳过
- 普通单进程脚本不受影响

### 10.4 控制台出现 AutoRun 相关提示

如果看到类似 Windows `AutoRun` 注册表的提示，通常是本机 `cmd` 环境问题，不是 XMDS 本身运行失败。只要程序退出码正常、输出文件生成正常，就可以视为 XMDS 正常工作。

## 11. 推荐使用习惯

- 先在 PowerShell 中运行 `python bin\xmds2 --reconfigure`
- 编译时用 `python bin\xmds2 your_file.xmds`
- 运行时优先用 `.\your_file.cmd`
- 遇到库检测变化后重新执行 `--reconfigure`
- 跑测试时优先逐组跑，便于定位问题

## 12. 小结

当前仓库已经可以在 Windows 原生环境中完成：

- 配置
- 编译
- 运行
- 回归测试

并且不依赖 MSYS 或 WSL。
