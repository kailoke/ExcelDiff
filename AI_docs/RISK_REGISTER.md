# RISK_REGISTER（未关闭风险）

> 引用约定（本文件的编号一律按台账名读写，不在此逐条展开）：`ADR-###` = `DECISION_LOG.md` 的架构决策条目；`R-###` = 本册（未关闭风险）；条目号 `E<n>` = `INVARIANTS.md` E 区条目。

> 只登记**未关闭**风险，关闭即删除整行（历史查 git log）。等级：P0 阻塞核心闭环 / P1 影响里程碑 / P2 可延后。

| ID | 等级 | 风险 | 触发/影响 | 当前处置 | 状态 |
|---|---|---|---|---|---|
| R-002 | P2 | `EditGraph`（NetDiff 算法核心）最坏 O(D²) 节点分配（ADR-010：不重写算法、用 Limit 守卫的裁决） | "两表几乎全不同"的病态大表 → 内存/冻结风险 | 行级 `Limit=2000` 前沿守卫兜底；31 用例钉住路径；崩溃报告出现再评估重写 | 开放 |
| R-003 | P2 | 推送闸门（`.githooks/pre-push`，检测 AI 会话环境标记并拒绝的钩子）只在本机克隆有效 | `core.hooksPath` 不随克隆传播；`--no-verify` 可绕过；环境标记可被蓄意清除 | 新克隆执行 `git config core.hooksPath .githooks`；钩子是摩擦不是保证，靠纪律补位 | 开放 |
| R-004 | P2 | 未签名 setup exe 触发 SmartScreen/杀软拦截 | 对外分发未签名产物 → 用户侧安装被拦 | 发布前流水线 Authenticode 签名（INVARIANTS E10）；开发期本机安装不受影响 | 开放 |
| R-005 | P1 | 列对齐丢列：两侧各有对方没有的列时（真删+真加并存），合并列映射条目数超过有效列数触发按索引尾裁（`ExcelDiff/ExcelSheet.cs` 的 `Diff`/`GetEffectiveColumnCount`），行重排不消费行尾残余格子、`UpdateCells` 整行替换 → 单侧尾列连同数据从报告中消失 | 已实测复现（DiffHarness，headless diff 输出工具）：src 三列 h1,h2,h3 → dst 三列 h2,h3,h4，dst 的 h4 列及其数据零出现、src 的 h2 列被误报整列删除；复现件与机理链 = `AI_docs/HANDOFFS/R-005-repro-header-pair.md` | 修复方向待业主裁决（伪列判定收尾裁 / 拼接循环吞残余）；动 `ExcelSheet.cs` 前跑 `AI_Script/verify.ps1`（31 用例，INVARIANTS F3） | 开放 |
