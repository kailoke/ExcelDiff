# AI_docs 结构与回写

> 引用约定（本文件的编号一律按台账名读写，不在此逐条展开）：`ADR-###` = `DECISION_LOG.md` 的架构决策条目；`R-###` = `RISK_REGISTER.md` 的未关闭风险；`§N` = 本文件章节号（跨文件引用时写明文件名）。

> 本目录 = 全部 AI 生产文档的唯一存放地；本文件只描述**目录结构与回写规则**。

## 文档结构

| 文件 | 用途 | 类别 |
|---|---|---|
| `ARCHITECTURE.md` | 结构事实：技术栈/程序集/目录/构建链/启动链/模块地图/部署布局 | 事实 |
| `ROUTING.md` | 任务 → 必读材料（一行一路由，`ARCHITECTURE` 不含路由） | 事实 |
| `PROJECT_STATUS.md` | 当前状态唯一回写点（阶段/阻塞/验证基线） | 快照 |
| `PROJECT_STATE.md` | 分支/upstream 快照（`AI_Script/refresh_state.ps1` 生成·勿手改；提交状态问 git） | 生成 |
| `EXECUTION_PLAN.md` | 阶段方案 + 门禁命令 + **§8 当前切片队列（唯一任务清单）** + §7（运行时验收清单） | 快照 |
| `DECISION_LOG.md` | 当前生效的架构决策（ADR-### 编号体系，只留当前有效条目） | 快照 |
| `INVARIANTS.md` | 工程硬约束清单（A–F 六区；改动前逐条核对，违反 = 阻断提交；`AI_Script/verify.ps1` 内嵌其中 D1/C4 两条的机检） | 规范 |
| `RISK_REGISTER.md` | 未关闭风险 | 快照 |
| `MODULE_REGISTER.md` | 模块现状与 lock | 快照 |
| `ORCHESTRATION/MODEL_ROUTING.md` | 档位判定、派发纪律、交叉验收、并行会话 | 程序 |
| `ORCHESTRATION/TASK_LIST_TEMPLATE.md` | 子任务派发单模板（文件名取 UPPER_SNAKE 风格；对应技能目录名为小写 `task-list-template`，不随文件名大小写变化） | 程序 |
| `DOSSIER/*.md` | 模块档案（每个深改目标模块一份"现场事实"档案，写法见该目录 `README.md`） | 素材 |
| `glossary.json` | 术语规范表（旧写法 → 现写法），供 `AI_Script/lint-docs.ps1` 消费 | 规范 |
| `HANDOFFS/*.md` | 按任务交接文件（本地接力件，gitignored） | 本地 |
| `CODE_INDEX.md` | 代码锚点索引 **（生成·勿手改）** | 生成 |

## 回写规则（单一事实源）

| 变化 | 回写到 |
|---|---|
| 代码事实/进度/阻塞 | `PROJECT_STATUS.md` |
| 任务/切片状态 | `EXECUTION_PLAN.md` §8（当前切片队列；完成即出队） |
| 当前生效的架构决策 | `DECISION_LOG.md`（只留当前有效口径） |
| 未关闭风险 | `RISK_REGISTER.md`（关闭即删除） |
| 模块现状/lock | `MODULE_REGISTER.md` |
| 结构性事实（新程序集/模块/构建链/启动链变更） | `ARCHITECTURE.md` |
| 硬约束新增/收紧 | `INVARIANTS.md`（配机检的同步改 `AI_Script/verify.ps1` 或相关脚本） |
| 重复性操作 | 固化为 `AI_Script/` 脚本（禁口头描述步骤） |
