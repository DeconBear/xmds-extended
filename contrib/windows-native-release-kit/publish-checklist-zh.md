# 发布前清单

- 确认保留 `COPYING` 和 `COPYRIGHT`
- 确认 README 中写明 `unofficial`, `based on XMDS2`, `original licensing preserved`
- 确认不要把生成物 `.exe`, `.h5`, `.xsil`, `.jpg` 当作源码主体发布
- 确认说明里写清楚测试环境
- 确认说明里写清楚验证结果
- 确认说明里区分“已验证”和“未验证”的范围
- 如果给上游投稿，附上一句授权声明：
  - `I agree to license my contributions under the GPL v2 license.`

## 建议附带的验证摘要

- `python bin\\xmds2 examples\\lorenz.xmds`
- `.\lorenz.cmd`
- 顶层测试组逐组跑通
- 用户示例 `test_example\\Morgan_01_20240523` 在 Windows 原生环境下数值复现成功

## 最后检查

- 看一遍仓库首页，确保一个第一次访问的人能在 30 秒内看明白：
  - 这是什么
  - 不是官方什么
  - 你做了什么
  - 现在能用到什么程度
