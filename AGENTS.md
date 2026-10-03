# 本仓库 AI 规约（首读入口）

**AI 工具自动加载本文件**：只写"任何动作前必须知道"的内容——文档状态纪律、硬护栏、引用与表达纪律、读取集与导航。结构事实按需读 `AI_docs/ARCHITECTURE.md`（架构事实快照）；工程硬约束清单 = `AI_docs/INVARIANTS.md`（改动前逐条核对的 A–F 六区）；操作程序见 `AI_docs/AGENT_WORK_PROTOCOL.md`（开工/实施/门禁/回写/提交的工作程序）。个人协作风格（要不要先写方案、验证做到哪一步）不在仓库定义。

## 项目一句话（开工速览）

ExcelDiff：Windows 桌面 GUI 差异对比工具（xls/xlsx/csv/tsv），可作 Git/Mercurial difftool。WPF（net472）+ Prism，读取层唯一实现是 ExcelDataReader，只有一套产品 `ExcelDiffEDR.GUI`（程序集名 / 配置目录 / IPC channel / 显示名都由 exe 名派生）。任何改动完成后跑 `powershell -NoProfile -ExecutionPolicy Bypass -File AI_Script/verify.ps1`（一键验收门禁：构建 + 单测 + lang 同步 + 坑扫描）必须全绿。用户口述"构建" = `AI_Script/Deploy-And-Restart.ps1`（构建→部署→重启常驻一条龙）。凡任务涉及部署重启、拉起对比窗口、安装包发布、常驻 IPC 取证，先读 `.agents/skills/exceldiff-workflow/SKILL.md`（本工程操作规范通道：命令、坑与判读）。

## 文档状态纪律（所有会话、所有文档适用）

所有 AI 文档（本文件、`AI_docs/**`）**只描述当前有效状态**：

- 被取代的内容**直接删除或改写成最新口径**，禁止保留旧口径，禁止追加"已完成/历史/验证流水"条目；禁止"已退役/待回填"一类标注。**零历史**：已裁决 + 已执行完成（含验证）的任务，在台账/队列/交接件中整条删除（唯一存档处 = git log）；永久规则以最终态描述留存。
- 状态类文件是**快照**：`AI_docs/PROJECT_STATUS.md`（当前状态回写点）、`AI_docs/EXECUTION_PLAN.md` §8（当前切片队列，唯一任务清单）、`AI_docs/DECISION_LOG.md`（当前生效决策）、`AI_docs/RISK_REGISTER.md`（未关闭风险）、`AI_docs/MODULE_REGISTER.md`（模块现状与 lock）——写入即覆盖对应条目，任务完成即出队/删除。
- 一个事实只在一处成文，其余位置只能是指针；新增文档前先判断能否并入既有单一事实源。`AI_docs/PROJECT_STATE.md` 与 `AI_docs/CODE_INDEX.md` 是生成件（勿手改，来源见 `AI_Script/README.md`）。
- **文件编码**：`AGENTS.md`、`AI_docs/**`、`.agents/**`、`AI_Script/` 顶层的 .md 与 .json 一律 **UTF-8 无 BOM**；`AI_Script/*.ps1` 含非 ASCII 时**必须带 BOM**（否则 Windows PowerShell 5.1 按 ANSI 读，中文乱码）。机械防线 = `AI_Script/lint-docs.ps1` 的编码组检查（E10 = 含非 ASCII 的 .ps1 必须带 BOM；E17 = 技能/命令前言禁 BOM；E18 = 文档 md/json 禁 BOM；E20 = 已跟踪文本文件禁真实存储的替换符字节）。归一与负测试流程 = `.agents/skills/bom-encoding-gate/SKILL.md`（BOM 编码归一与门禁负测试）。
- 记录只留四类：反复踩的坑、特殊实现、歧义/待裁决、用户要求备注。

## 硬护栏（默认不变；要改必须是明确需求，不能是重构/修 bug 的副产物）

**禁改区**（glob 机器正典 = `AI_Script/protected-paths.json`，下列各条与正典逐条一致，门禁 E10 查对）：

- `packages/*`（NuGet 还原的参考程序集与三方包，删除后可由 `dotnet restore` 恢复）
- `Build/*`（WriteableBitmapEx 构建产物）
- `ExcelDiff.Installer/Release/*`（setup 打包产物，由 `ExcelDiff.Installer/Build-Setup.ps1` 再生成）

**默认不变点**（工程硬约束的逐条正典 = `AI_docs/INVARIANTS.md`，此处只列族）：

- **单一版本**：只有一套产品、一条读取实现（ADR-019，单一版本裁决：读取层只有 ExcelDataReader 一条路径）；不许新增版本类条件编译，需要第二种实现时先在 `AI_docs/DECISION_LOG.md` 开新决策条目。
- **生命周期/IPC/设置写入**：管道线程非阻塞、转发进程不驻留、模态强关、设置原子写（INVARIANTS C 区）。
- **UI 表现与交互**、用户配置目录与派生命名规则（A3）。
- **权威数据**：外部 xlsx 测试数据仓内容、用户 git 配置里的 `[difftool "ExcelDiff"]` 标签——归属用户，AI 不改；其合理性由人判定。
- **未决项裁决**：歧义/待裁决/需求未明项，一律等用户明确指令；需要决策时先列可选处置、各自后果与推荐项，再停在该项等待，不得以"按惯例/默认值"先行落地。
- **证据与结论**：现状结论必须来自本轮现场取证（全仓检索、运行输出、门禁结果），不得取自文档表述或会话记忆；"没有报错"不等于通过——必须先陈述该通道为何能观察到错误，无见证的结论只能是 UNKNOWN。不得为贴合提问口径调整判断（不迎合）。
- **工作区**：不执行破坏性命令（`git reset --hard`、批量删除）；只处理本任务相关文件，不重置、不混入他人修改；不做大范围格式化。
- **代码组织护栏**：net472 老式 C#（无 nullable、无 target-typed new、命名空间 = 目录名）；可见文本一律走 `Resources.*` 字符串表（INVARIANTS D 区）；注释只写在关键逻辑、核心问题、反复犯错处三处，类头/方法注释不留任务溯源与历史叙述；条件编译只有 `PERF_TIMING`。
- **验收口径**：AI 只做功能关键性验收（能证明该功能成立的最小项）；人工验收统一排最后阶段一次性进行。

## 引用与表达纪律

**代码引用**：文档引用代码只写稳定锚点（`路径/File.cs <!-- anchor:ID -->`），不裸写行号；锚点注册表 = `AI_Script/code-anchors.json`，改代码后跑 `AI_Script/refresh-code-index.ps1`（锚点行号重解析与文档行号回写）。门禁命令清单 = `.agents/commands/`（brief / gate / gate-compile / day-gate / deploy）；脚本清单与触发时机唯一出处 = `AI_Script/README.md`。

**读文件的方式（按目的选，不许一律 grep）**：

| 目的 | 用什么 | 为什么 |
|---|---|---|
| 查"某符号/参数有没有消费方"、全仓引用点、唯一写入口 | grep / glob | 存在性取证，检索式就是正确工具 |
| **改纪律、修文档、清洗过时口径、判断"哪一处该改"** | **直接精读整份文件** | 判断依赖上下文与前后关系；grep 只给孤立命中行，依据片段改文档必然漏改误改 |

**精读的边界**：任务涉及几份文件就读那几份全文（大文件分批读完再动笔）；目标文件之外的旁证检索才用 grep。发现两份文档不一致时两处都改（同一事实只留一处成文，另一处改指针）。

**指针的内容要求（索引/路由/目录类文本一律适用；会被人看到的必须三样俱全）**：① 被引用物的标题（它叫什么）；② 一句核心解释（它是干什么的、为什么与当前话题有关）；③ 把"要不要打开、打开看哪一节"就地办完。指针给"标题 + 一句话 + 去哪看"，不给事实本体。

**加技能 / 加命令的硬性条件（多宿主兼容）**：新增技能或命令时，必须同时为现存每个宿主建薄指针——现存宿主 = `.zcode`（commands/skills）与 `.qoder`（skills）两处，`.agents/` 是唯一事实源。指针三要素：① 指向源文件的相对路径；② frontmatter `description` 与源逐字一致；③ 技能另需 `name` 与目录名一致。机械防线 = `AI_Script/lint-docs.ps1` 的 E6（宿主薄指针漏一个即拒提）。禁止留下没有源对应的空技能目录。

**对用户/业主的输出**：

- **引用自带解释**：凡"名字看不出是什么"的东西，第一次出现就地补一句"它是什么"（括号里一句人话）。适用穷举：AI 文件与脚本（`AI_docs/**`、`AI_Script/**`、`.agents/**`）、决策编号（`ADR-###`，`AI_docs/DECISION_LOG.md` 即当前生效的架构决策册）、风险编号（`R-###`，`AI_docs/RISK_REGISTER.md` 即未关闭风险册）、任务/切片编号、章节号（`§N`，某文件的第 N 节）、配置参数名与代码符号；同一份输出内后续再提不重复。**每一轮对话都是一份独立交付**——本轮出现的编号/文件名/术语都要本轮自带解释（"上一轮说过"不算）。
- **发前自查（每轮必做）**：① 按 `AI_docs/AGENT_WORK_PROTOCOL.md`「回复前自查」的四组机械扫描逐组过草稿（编号 / 路径与文件 / 英文缩写与代码符号 / 中文黑话）；② 跑 `AI_Script/lint-reply.ps1 -Path <草稿>` 复核。机械门禁 E14/E15（引用无解释检查）只扫文件、扫不到对话回复——不许把"文件里是绿的"当成"回复也合规"。
- **大白话优先**：默认读者不懂程序，先用日常语言讲清"发生了什么、为什么、对使用有什么可见影响"；禁止自造复合词代替人话。能用表格或 Mermaid 图讲清的不堆文字；图表纪律 = `.agents/skills/diagram-mermaid/SKILL.md`（mermaid 图表纪律与渲染入口）。

## 会话角色与最小读取集

**按角色只读下表最小集**，不预读全部台账（档位与派发纪律见 `AI_docs/ORCHESTRATION/MODEL_ROUTING.md`）：

| 角色 | 开工读取集（按序） |
|---|---|
| 主会话（编排/验收） | `AI_docs/PROJECT_STATUS.md` → `AI_docs/EXECUTION_PLAN.md` §8（当前切片队列）→ `AI_docs/ROUTING.md`（取本任务一行）→ `AI_docs/ORCHESTRATION/MODEL_ROUTING.md` → 按该行加载材料 |
| 强档子任务 | 派发单（含入口锚点）+ 按锚点自查代码；不预读台账 |
| 省档子任务 | 仅派发单（材料已内联）；禁止读台账、禁止全仓探索 |

- 动态状态唯一回写点 = `AI_docs/PROJECT_STATUS.md`（与代码**同一笔**提交，pre-commit 强制同笔；应急 `--no-verify` 须补跟随笔并注明原因）。
- **提交授权**：**AI 不直接 commit**——改动完成后给出 Commit subject / description 供用户审查执行；**推送（`git push` 及任何写远端的操作）在用户当轮明确指令前永不执行**，机械防线 = `.githooks/pre-push`（推送闸门，失败关闭；一次性豁免变量 `EXCELDIFF_ALLOW_PUSH`，AI 会话不得设置、不得用 `--no-verify` 绕过）。
- **派发闸门**（判据唯一权威 = `AI_docs/ORCHESTRATION/MODEL_ROUTING.md` §3）：写派发单前先一句话回答两问——① 主会话并行在做什么（答"等着"即不成立）；② 并行收益是否抵得过返工风险。任一应不上 ⇒ 弃单，主会话直接实施。

## 导航（按需加载，不预读）

- 架构事实（技术栈/程序集/构建链/启动链/模块地图/部署布局）：`AI_docs/ARCHITECTURE.md`。
- 任务材料路由（任务 → 必读一行）：`AI_docs/ROUTING.md`。
- 工作程序（开工/实施/门禁脚本/回写/决策/状态值/Git）：`AI_docs/AGENT_WORK_PROTOCOL.md`。
- 编排：`AI_docs/ORCHESTRATION/MODEL_ROUTING.md`（档位）+ `AI_docs/ORCHESTRATION/TASK_LIST_TEMPLATE.md`（派发单模板）；子任务素材：`AI_docs/DOSSIER/`（模块档案）。
- 台账：`AI_docs/MODULE_REGISTER.md`（模块现状与 lock）、`AI_docs/DECISION_LOG.md`（当前生效决策）、`AI_docs/RISK_REGISTER.md`（未关闭风险）、`AI_docs/CODE_INDEX.md`（锚点索引，生成·勿手改）、`AI_docs/INVARIANTS.md`（硬约束 A–F）。
- 分支/upstream 快照：`AI_docs/PROJECT_STATE.md`（生成件）；提交状态直接问 git（`git rev-parse HEAD` / `git log`），文档不维护副本。
- 本工程操作通道（构建/部署/安全启动/安装包/测试数据）：`.agents/skills/exceldiff-workflow/SKILL.md`。
- 固化命令单一事实源：`.agents/commands/`（brief / gate / gate-compile / day-gate / deploy）；技能单一事实源：`.agents/skills/`。宿主侧一律薄指针转发，不复制正文；脚本清单与触发时机 = `AI_Script/README.md`。
