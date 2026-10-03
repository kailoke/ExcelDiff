# PROJECT_STATUS（当前状态）

> 状态唯一回写点：代码事实/进度/阻塞只写这里，与代码**同一笔**提交（`.githooks/pre-commit` 强制同笔，见 `AGENT_WORK_PROTOCOL.md`「Git 提交与追踪」）。历史查 git log；切片详情在 `EXECUTION_PLAN.md` §8（当前切片队列）。

## 阶段与焦点

- 当前阶段：AI 协作框架切换期——框架已按「文档纪律 + 门禁脚本 + 双宿主命令/技能 + 编排模板」重建并入库（提交 `962f928`；`AI_docs/` + `AI_Script/` + `.agents/` + `.zcode`/`.qoder` 薄指针 + `.githooks`），台账经代码事实审计，产品代码零改动；部署冒烟已过（见下方运行时基线）。
- 当前焦点：推送闸门改版（pre-push 只拦 AI 会话环境、人类操作直接放行）待入库。

## 阻塞 / 待决（一行一任务 ID；切片详情见 `EXECUTION_PLAN.md` §8 当前切片队列）

> 只放"正在挡路"的项：等待裁决 / 等待人工 / 等待外部条件。解除后整行删除，不留在案。

- （无）

## 当前验证基线

> 只写快照：哪些判据此刻是绿的。不写验证过程与日期流水。

- 门禁：`verify-scope.ps1`（SCOPE + 锚点 + 文档 lint）当前结论 = PASS（40 个改动文件、27 个 caution 待确认，均属本框架重建任务自身）
- 编译：`verify-scope.ps1 -Compile`（即 `verify.ps1` 全量）当前结论 = PASS（EDR 构建 + setup 构建 + NetDiff 31 用例 + lang↔resx 同步 + 坑扫描；产品代码此后零改动，结论仍有效）
- 文档 lint：`lint-docs.ps1` 双 PS 版本（PS7 + 5.1）当前结论 = PASS（0 错 0 警，26 个文件）
- 运行时：`EXECUTION_PLAN.md` §7（运行时验收清单）当前通过项 = 第 1、2 项（部署后常驻完整性级别与桌面一致；difftool 链路拉起对比窗口）；第 3～5 项未跑（模态弹窗/语言切换为人工路径）
