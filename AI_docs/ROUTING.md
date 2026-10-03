# ROUTING（任务 → 必读材料）

> 用法：**先读基线**（读取集与顺位 = 根 `AGENTS.md`「会话角色与最小读取集」），再按本表取**对应一行**，**不通读**其余台账。
> 本表是任务材料的唯一路由入口；`ARCHITECTURE.md` 只写结构事实，不含路由。
> 引用约定（本文件的编号一律按台账名读写，不在此逐条展开）：`ADR-###` = `DECISION_LOG.md` 的架构决策条目；`R-###` = `RISK_REGISTER.md` 的未关闭风险；条目号 `E<n>` = `INVARIANTS.md` E 区条目。

| 任务涉及 | 必读 | 基线之外的补充 |
|---|---|---|
| 读取层（`ExcelDiff/`：解析/行列语义/扩展名分发） | `INVARIANTS.md` B 区（读取层硬约束） + `DECISION_LOG.md` ADR-019（单一版本裁决：读取层只有一条实现） | `ARCHITECTURE.md` §6.2；R-001（读取盲区风险行）；改算法路径跑 `AI_Script/verify.ps1`（31 用例） |
| 差异算法（`NetDiff/`：EditGraph/DiffUtil） | `INVARIANTS.md` F 区（F3 前沿守卫） + ADR-010（EditGraph 不重写裁决） | R-002（病态大表风险行）；`ARCHITECTURE.md` §6.3（NetDiff 与 FastWpfGrid）|
| 常驻生命周期 / IPC / 托盘（`App.xaml.cs`、`SingleInstance.cs` 等） | `INVARIANTS.md` C 区（IPC 高危区） | `ARCHITECTURE.md` §5、§6.4（启动链与两条调用链）；`.agents/skills/exceldiff-workflow/SKILL.md`（本工程操作规范通道） |
| 本地化（resx/lang/语言切换） | `INVARIANTS.md` D 区 | `ARCHITECTURE.md` §9（本地化管线与语言解析顺序）；`GenerateLangJson.ps1`（resx → lang json 生成脚本）；`AI_Script/verify.ps1` 的 lang 同步段 |
| 安装器（`ExcelDiff.Installer/`：打包/卸载/回滚/COM） | `INVARIANTS.md` E 区（E7–E14 安装链硬约束） + `DECISION_LOG.md` ADR-017（自研 WPF 安装器）与 ADR-018（卸载移交语义）| `ARCHITECTURE.md` §7（部署布局与两条链路）；`AI_Script/verify-installer.ps1`（发布门禁）；`.agents/skills/exceldiff-workflow/SKILL.md`「安装包发布」 |
| 部署 / 常驻重启（Deploy-And-Restart） | `ARCHITECTURE.md` §4、§7 | ADR-011（提权部署裁决）；`INVARIANTS.md` F4；`.agents/skills/exceldiff-workflow/SKILL.md`「构建与部署」 |
| 网格渲染（`FastWpfGrid/`） | `INVARIANTS.md` F 区 | `ARCHITECTURE.md` §6.3；`AI_docs/DOSSIER/` 无档案时现场取证 |
| CLI 参数 / difftool 接入 | `DECISION_LOG.md` ADR-015（CLI 归一化）与 ADR-016（移除 -k、最近文件恒记）| 根 `README.md`（用户向 CLI 说明）；INVARIANTS C6（坏参数不打死常驻） |
| 构建失败 / 编译报错 | `ARCHITECTURE.md` §4（构建命令全文与必需参数） | 仓库根 `ProjectPaths.ps1` 路径自查（`powershell -File ProjectPaths.ps1 -Print`） |
| 对比测试 / 回归取证 | `ARCHITECTURE.md` §8（测试与验证口径） | `ProjectPaths.ps1` 的 `$TestDataRepoPath`；`.agents/skills/exceldiff-workflow/SKILL.md`「对比测试数据源」 |
| 规划 / 盘点 / 进度查询（无代码改动） | 基线已足（`PROJECT_STATUS.md` 当前状态 + `EXECUTION_PLAN.md` §8 当前切片队列 + §1 统一验收标准） | 任务队列是唯一清单，勿另建清单 |
| 风险 / 已知坑 / 未关闭项 | `RISK_REGISTER.md` | `MODULE_REGISTER.md` 对应行；`PROJECT_STATUS.md` 阻塞 |
| 画图 / 架构可视化（调用链 / 分层 / 时序） | `.agents/skills/diagram-mermaid/SKILL.md`（mermaid 图表纪律与渲染入口） | 对应模块现场取证；产物落本地 Diagrams/（gitignored，不入库） |
| 派发子任务 / 分档 | `AI_docs/ORCHESTRATION/MODEL_ROUTING.md` + `TASK_LIST_TEMPLATE.md`（编排纪律与派发单模板） | 对应 DOSSIER（无档案时主会话内联材料） |
| 结构事实（程序集/构建链/启动链/部署布局） | `AI_docs/ARCHITECTURE.md` 对应章节 | 代码锚点见 `CODE_INDEX.md` |
| 历史追溯（代码/提交/旧写法） | git log / git blame / git show | — |
