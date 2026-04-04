# XMDS Windows 便携安装版升级设计 v1

本文档定义 Windows 便携安装版在“用户已经安装过一次，之后需要升级”时的目标行为。

它服务于下一阶段实现，不直接改变当前安装器行为。

## 1. 设计目标

升级方案需要做到：

- 用户继续使用同一个入口：
  `powershell -ExecutionPolicy Bypass -File .\install_windows.ps1`
- 安装器自动识别“首次安装”还是“升级安装”
- 用户可以把新版本安装到原来的同一个目录
- 已有 PATH 选择尽量保留，不要求用户重复做无意义选择
- 已有 `runtime` 能复用时尽量复用，减少重新下载安装时间
- 新版本需要额外依赖时，安装器能补齐
- 遇到不兼容升级时，安装器能明确提示并切换到“重建 runtime”模式
- 升级失败时，不把安装目录留在半损坏状态

## 2. 非目标

第一版升级设计暂不追求这些能力：

- 不做二进制增量补丁
- 不做自动联网检查最新版本
- 不做后台静默升级
- 不做多版本并行切换器
- 不保证任意旧版本都能一跳升级到任意新版本

## 3. 升级入口与用户体验

升级仍然沿用安装入口：

```powershell
powershell -ExecutionPolicy Bypass -File .\install_windows.ps1
```

如果用户把新 zip 解压后，选择一个已经存在 XMDS 安装的目录，例如：

```text
D:\xmds
```

安装器应先检测：

- 目标目录是否存在
- 目标目录下是否存在 `state\install.json`
- 该 `install.json` 是否属于本项目的便携安装版

如果检测到旧安装，交互应变成：

```text
Detected an existing XMDS Extended installation.
Installed version: v1
Package version: v2
Install directory: D:\xmds

Upgrade this installation? [Y/n]:
```

如果用户确认，再进入升级流程。

## 4. 安装状态文件扩展

当前已有的安装状态文件是 `state/install.json`，其中已经包含：

- `install_dir`
- `runtime_dir`
- `toolchain_dir`
- `add_install_dir_to_path`
- `package.version`
- `package.app_revision`

升级设计建议把 `state/install.json` 的语义扩展为：

```json
{
  "installed_at": "2026-04-04T22:17:40",
  "install_dir": "D:\\xmds",
  "runtime_dir": "D:\\xmds\\runtime",
  "toolchain_dir": "D:\\xmds\\toolchain\\mingw64",
  "add_install_dir_to_path": true,
  "package": {
    "name": "xmds-extended-windows-portable",
    "version": "v2",
    "app_revision": "abcdef0"
  },
  "runtime": {
    "python_version": "3.11",
    "spec_hash": "sha256:...",
    "provisioner_version": 1
  },
  "history": {
    "previous_version": "v1",
    "last_upgrade_at": "2026-05-01T10:23:00"
  }
}
```

这里最关键的是：

- `runtime.spec_hash`
  用来判断新旧包的依赖集合是否一致
- `runtime.python_version`
  用来判断是否需要重建 runtime
- `history.previous_version`
  用来在升级提示和排障时给出更明确信息

## 5. 升级类型

升级逻辑建议分成 4 类。

### 5.1 同版本重装

场景：

- `package.version` 相同
- `app_revision` 相同或用户主动覆盖安装

处理：

- 允许继续
- 主要用于修复损坏安装、重新生成入口脚本、重新修复 PATH

### 5.2 仅应用层升级

场景：

- `package.version` 变化
- `runtime.spec_hash` 不变
- `python_version` 不变
- `toolchain` 策略不变

处理：

- 覆盖 `app/`
- 覆盖入口脚本
- 覆盖 `toolchain/`
- 保留 `runtime/`
- 更新 `install.json`

这是最理想、最轻量的升级。

### 5.3 运行时补依赖升级

场景：

- `runtime.spec_hash` 变化
- 但仍兼容当前 Python 主次版本和工具链

处理：

- 先对现有 `runtime/` 执行增量依赖同步
- 成功后继续覆盖 `app/`、入口脚本和 `toolchain/`

推荐策略：

```text
conda install -y -p <InstallDir>\runtime <new package specs>
```

这类升级比完全重建快，但要允许失败后回退到“重建 runtime”。

### 5.4 破坏性升级

场景：

- Python 主次版本变化，例如 `3.11 -> 3.12`
- 工具链 ABI 或布局变化
- 依赖升级不再兼容旧 runtime

处理：

- 明确提示用户当前升级需要重建 `runtime`
- 先备份旧 `runtime`
- 再创建新 `runtime`

推荐提示：

```text
This upgrade requires rebuilding the local runtime environment.
The existing runtime will be replaced after a backup is created.
Continue? [Y/n]
```

## 6. 升级决策流程

建议流程如下：

1. 读取目标目录下的 `state\install.json`
2. 判断是否属于 XMDS 便携安装
3. 读取新包的 `install-manifest.json`
4. 对比：
   - `package.version`
   - `package.app_revision`
   - `runtime.conda_packages`
   - Python 版本
   - 工具链策略
5. 归类为 4 种升级类型之一
6. 向用户输出升级摘要
7. 用户确认后执行升级

升级摘要建议包含：

- 旧版本
- 新版本
- 是否复用 runtime
- 是否需要补装依赖
- 是否需要重建 runtime
- PATH 设置是否保持不变

## 7. 文件覆盖策略

升级时建议把安装目录中的内容分成三类处理。

### 7.1 始终覆盖

- `app/`
- `toolchain/`
- `run_xmds.cmd`
- `run_xmds.ps1`
- `run_plot.cmd`
- `run_plot.ps1`
- `uninstall_windows.ps1`
- `state/install.json`

### 7.2 尽量复用

- `runtime/`

只有在满足兼容条件时才复用；否则重建。

### 7.3 必须保留

- `state/xmds-home/`
  里面可能已有本安装实例使用过的配置缓存
- 用户手动放到安装目录之外的仿真案例目录

## 8. 失败恢复策略

升级设计不能默认“边覆盖边赌成功”。建议使用简化的两阶段策略。

### 8.1 升级前备份

在 `state/backups/<timestamp>/` 下保存：

- 旧 `install.json`
- 旧入口脚本
- 可选：旧 `app/` 和 `toolchain/` 的目录快照或重命名副本

第一版实现里可以用更简单的做法：

- 升级前把旧 `app/` 改名为 `app.backup.<timestamp>`
- 旧 `toolchain/` 改名为 `toolchain.backup.<timestamp>`

如果升级成功，再删除备份。

### 8.2 升级失败

如果在这些阶段失败：

- 依赖补装失败
- runtime 重建失败
- app 覆盖失败
- 启动器生成失败

安装器应：

- 停止继续覆盖
- 还原已有备份
- 输出“升级失败，已恢复旧版本”或“升级失败，请手动恢复”的明确结果

## 9. PATH 策略

升级时不应默认重复询问 PATH，建议逻辑是：

- 如果旧安装 `add_install_dir_to_path = true`
  默认继续保持
- 如果旧安装未加入 PATH
  默认继续不加入
- 只有当用户显式传参，或者交互式选择发生变化时，才修改 PATH

这能减少升级过程中的无谓干扰。

## 10. 版本兼容策略

建议把升级兼容性声明分成 3 档。

### 10.1 可直接升级

- 同一主线版本内的小版本升级
- 同一 Python 主次版本
- 同一工具链布局

### 10.2 需要重建 runtime

- Python 主次版本变化
- conda 依赖集合变化较大
- HDF5 / FFTW / 工具链策略变化

### 10.3 不保证在线升级

- 很旧的历史包升级到很新的包
- 便携安装结构本身发生重大调整

这种情况可提示用户：

```text
In-place upgrade is not supported for this version jump.
Please install to a new directory or perform a clean reinstall.
```

## 11. 推荐实现阶段

### 阶段 1：升级识别

- 识别已有安装
- 区分首次安装和升级安装
- 输出升级摘要

### 阶段 2：同目录覆盖升级

- 覆盖 `app/`
- 覆盖 `toolchain/`
- 覆盖入口脚本
- 保留 `runtime/`

### 阶段 3：runtime 增量升级

- 计算 `spec_hash`
- 对已有 `runtime/` 补装缺失依赖
- 更新 `install.json`

### 阶段 4：runtime 重建与恢复

- 引入 runtime 备份
- 引入失败回滚
- 支持破坏性升级

## 12. 验收标准

升级设计落地后，至少要满足这些验收条件：

1. 旧版本安装目录被正确识别
2. 同目录重新安装时不会误判为全新安装
3. 应用层升级后 `run_xmds` 仍能工作
4. PATH 选择在升级前后保持一致
5. 需要重建 runtime 时，用户会收到明确提示
6. 升级失败时，不会留下无法启动的半损坏安装

## 13. 当前最实用的临时规则

在正式升级逻辑实现前，当前版本最安全的用户规则仍然是：

1. 下载新的 zip
2. 解压
3. 运行新的 `install_windows.ps1`
4. 选择原来的同一个安装目录
5. 如遇依赖变化或异常，删除旧 `runtime/` 后重装

这是一种“覆盖安装式升级”，能工作，但它还不是完整升级器。
