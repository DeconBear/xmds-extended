# XMDS Windows Native GitHub 发布建议

## 推荐方式

最稳妥的方式不是把整个 XMDS 重新包装成你的项目，而是发布一个明确说明来源的成果仓库。

我建议优先用下面两种方式之一：

1. `patch + docs` 仓库
   - 只公开这次 Windows 原生兼容涉及的修改文件、说明文档、测试结果和上游投稿记录。
   - 这是最容易突出你个人贡献的方式。
2. 明确标注来源的 fork
   - 如果你希望别人可以直接 checkout 后使用，可以在 GitHub 放一个 fork 或镜像分支。
   - 必须保留原始许可证和版权声明。

## 为什么优先推荐 `patch + docs`

- 可见性更强，别人一眼就能看见你具体做了什么。
- 观感更好，不容易被理解成“搬运整个项目”。
- 即使上游长期没有响应，你也已经有一份完整、可展示、可引用的公开成果。

## 仓库标题建议

- `xmds2-windows-native-support`
- `xmds2-windows-compatibility`
- `xmds2-native-windows-patches`

## 仓库描述建议

`Native Windows compatibility work for XMDS2, including build fixes, runtime fixes, tests, and reproducible validation results.`

## 一定要保留的内容

- 原项目名称 `XMDS2`
- 来源说明
- 原始许可证文件 `COPYING`
- 原始版权文件 `COPYRIGHT`
- 明确说明这是非官方仓库或补丁集合

## README 里建议写清楚的点

- 这项工作的目标是让 XMDS2 在 Windows 原生环境下可编译、可运行、可测试
- 这不是 XMDS 官方仓库
- 原项目版权归 XMDS 作者所有
- 本仓库只公开基于 GPL 条款允许的修改和再分发内容
- 你已经验证过哪些示例和测试组

## 不建议的做法

- 不要把 XMDS 写成“你的原创项目”
- 不要删掉原始许可证文件
- 不要给整个派生源码重新套一个闭源许可证
- 不要省略“非官方”说明

## 最简单的公开方案

1. 用这个目录里的 `export_release_bundle.ps1` 导出一份干净的源文件包
2. 新建 GitHub 仓库
3. 上传 `bundle/source` 下的文件
4. 上传 `bundle/docs` 下的说明材料
5. README 使用 `README-template-en.md` 作为起点
6. 仓库首页显眼位置写明：
   - based on XMDS2
   - unofficial patch set
   - original licensing preserved

## 和上游联动的写法

如果你后面准备投稿到 XMDS 上游，可以在 README 中加一句：

`This work is intended to be proposed upstream to the XMDS2 maintainers via the SourceForge xmds-devel mailing list.`
