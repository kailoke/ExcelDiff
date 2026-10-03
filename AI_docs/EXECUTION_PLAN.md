# EXECUTION_PLAN（阶段方案 + 当前切片队列）

> 任务队列唯一清单 = §8；本文件其余各节是相对稳定的方案与口径。历史查 git log。
> 引用约定（本文件的编号一律按台账名读写，不在此逐条展开）：`ADR-###` = `DECISION_LOG.md` 的架构决策条目；`R-###` = `RISK_REGISTER.md` 的未关闭风险；`§N` = 本文件章节号。

## 0. 目标与范围

- 当前阶段目标：产品（安装器 + 常驻 + diff 管线）处于稳定维护期；AI 协作框架按新体系运转（纪律/门禁/台账/脚本），后续任务按 §8 队列推进。
- 非目标：不新增第二读取实现或版本开关（ADR-019）；不做 MSI/WiX 安装链（ADR-017）；不做全面测试覆盖替代关键性验收（验收口径见根 `AGENTS.md`）。

## 1. 统一验收标准（所有子会话必须全部满足）

- 改动落在派发单/任务声明的范围内；禁改区零触碰。
- `AI_Script/verify-scope.ps1` 全绿（SCOPE / 锚点 / 文档 lint）；有代码改动时 `-Compile` 过一次（即 `AI_Script/verify.ps1` 全量：构建 + NetDiff 31 用例 + lang 同步 + 坑扫描）。
- 台账同笔：代码改动必须与 `PROJECT_STATUS.md` 同一笔提交。
- 验收只做功能关键性项（能证明该功能成立的最小项），人工验收统一排最后阶段。
- 触及 `INVARIANTS.md` 所列高危区（B 读取层 / C 生命周期 IPC / D 本地化 / E 安装链 / F 性能渲染）时，逐条核对对应区。

## 2. 阶段与出口验收（静态）

| 阶段 | 内容 | 出口判据 |
|---|---|---|
| 稳定维护期 | 按任务修复/小步演进；安装器与常驻行为变更必须过对应门禁 | `verify.ps1` 全绿；动安装链加 `verify-installer.ps1` 静态段全绿（`-Install` 用例在发布前跑） |

## 3. 交叉验证方案

- diff 行为：`DiffHarness`（headless diff 输出工具，确定性文本）对同一对入参跨版本比对输出。
- 安装器行为：`verify-installer.ps1 -Install`（真实安装/卸载/重装/回滚用例，A–Q 十七个，需管理员）。
- 常驻/IPC 行为：部署后按 §7 运行时验收清单冒烟（含模态强关、托盘、完整性级别）。

## 4. 人工确认暂停点

- 提交与推送：AI 不直接 commit（提交经用户当轮授权后执行）；推送永远由业主本人执行（Fork 的 Push 按钮或独立终端），闸门只拦 AI 会话环境（`AGENT_WORK_PROTOCOL.md`「Git 提交与追踪」）。
- 权威数据判定：外部 xlsx 数据仓内容、用户 git 配置（`[difftool "ExcelDiff"]` 标签）不可改动；制造测试差异前征得用户同意。
- 不可逆操作：卸载/删除目录、注册表清理类动作只走 `verify-installer.ps1` 的隔离用例，不对真实安装执行。

## 5. 门禁与验收命令

| 场景 | 命令 |
|---|---|
| 每轮改动（轻量） | `powershell -NoProfile -ExecutionPolicy Bypass -File "AI_Script/verify-scope.ps1"` |
| 改码轮次（含编译+单测） | `powershell -NoProfile -ExecutionPolicy Bypass -File "AI_Script/verify-scope.ps1" -Compile` |
| 产品一键验收 | `powershell -NoProfile -ExecutionPolicy Bypass -File "AI_Script/verify.ps1"`（`-SkipBuild` 跳过构建） |
| 日终批量 | `powershell -NoProfile -ExecutionPolicy Bypass -File "AI_Script/verify-day.ps1"`（`-SkipCompile` 只做静态审计） |
| 文档一致性 | `powershell -NoProfile -ExecutionPolicy Bypass -File "AI_Script/lint-docs.ps1"`（PS7 与 PS 5.1 各跑一次） |
| 安装包发布 | `powershell -NoProfile -ExecutionPolicy Bypass -File "AI_Script/verify-installer.ps1"`（`-Install` 追加真实用例，需管理员） |
| 构建→部署→重启 | `powershell -NoProfile -ExecutionPolicy Bypass -File "AI_Script/Deploy-And-Restart.ps1"` |

## 6. 收货与提交

- 收货 = 一条命令（§5 门禁与验收命令）+ `MODEL_ROUTING.md` §4（交叉验收门：主会话收货清单）逐项过。
- 提交纪律见 `AGENT_WORK_PROTOCOL.md`「Git 提交与追踪」：AI 不直接 commit，改完停在"待入库"，给出提交信息供用户执行。

## 7. 运行时验收清单（人工/半自动门禁）

> 编译门禁绿 ≠ 闭环通过。部署（`Deploy-And-Restart.ps1`）后逐项核对；证据来源 = 脚本输出 / 界面可见结果 / 日志文件。

| # | 验收项 | 判定依据 |
|---|---|---|
| 1 | 常驻拉起且完整性级别与桌面一致 | `Deploy-And-Restart.ps1` 输出 `resident pid=… IL=… desktop IL=…` 两值相同，脚本总出口 `deploy_all.log` = DONE |
| 2 | difftool 链路可用 | `AI_Script/Invoke-ExcelDiff.ps1`（安全启动封装：fire-and-forget + 轮询窗口）exit 0，对比窗口出现且差异渲染正常 |
| 3 | 无差异路径 | 对两个相同文件拉起 → `NoDiffWindow` 弹出；点右上角 ✕ 只关弹窗、对比窗口仍在 |
| 4 | 语言切换生效 | 切换语言 → 弹重启确认 → 点确定后对比窗口关闭；下一条 diff 命令以新语言重建 |
| 5 | 模态不阻塞远程命令 | `NoDiffWindow` 开着时再发起一条 diff 命令 → 模态被强关、新对比生效（INVARIANTS C5） |

## 8. 当前切片队列（唯一任务清单）

> 一行一切片；状态值见 `AGENT_WORK_PROTOCOL.md`「状态值规范」。完成即整行删除（零历史）。lock 列写 `MODULE_REGISTER.md` 里的模块名；交接文件落 `AI_docs/HANDOFFS/`。

| 切片 | 内容一句话 | 档位 | 状态 | lock | 交接文件 |
|---|---|---|---|---|---|
