# AGENTS.md

> AI 编程上下文已统一整理到 `AI_Programmer\` 目录。

开工入口：先读 [`AI_Programmer\AGENTS.md`](AI_Programmer/AGENTS.md)（操作手册，会指引 `ARCHITECTURE.md` / `CODEX.md` / `INVARIANTS.md` / `ADR.md`）。

项目与 git 版本状态（分支 / HEAD / 最近提交）：读 [`AI_Programmer\PROJECT_STATE.md`](AI_Programmer/PROJECT_STATE.md)（由 `AI_Script\refresh_state.ps1` 自动生成）。

AI 工作流脚本统一在 [`AI_Script\`](AI_Script)（`verify.ps1` 验收门禁 / `verify-installer.ps1` 安装包门禁 / `Deploy-And-Restart.ps1` 部署 / `Invoke-ExcelDiff.ps1` 安全启动 / `refresh_state.ps1` 状态刷新 / `refresh_codex.ps1` 行号校准）。

---

## 单元格渲染问题的排查思路（历史笔记，插桩已不在仓库里）

2026-09-30 实测核对（`git log --all -S`，全仓）：

- `EnableCellTrace`、`edr_celltrace.log` 在 `.cs` / `.csproj` 里命中 **0**；在 git 全部历史里也只出现在本文件的文字中（`003469d`）。也就是说本节原先写的"构建时传 `/p:EnableCellTrace=true` 就能拿到追踪日志"**从来没有可执行的对象** —— 那是某次一次性插桩的笔记，插桩本身没进提交。要再用这套步骤必须先自己加插桩。
- 原先记在这里的"修复"（`columnCount` 改为 `Cells.Keys.Max() + 1`）在代码里同样不存在：`ExcelDiff.GUI/Models/DiffGridModel.cs:77` 至今是 `SheetDiff.Rows.Max(r => r.Value.Cells.Count)`，而 `ExcelRowDiff.Cells` 是只装差异单元格的 `SortedDictionary<列号, ExcelCellDiff>`（`ExcelDiff/ExcelRowDiff.cs:28`）。所以那条要么属于那次未提交的改动，要么当时的判断本身不成立 —— **未取证，不要当结论用**。

仍然成立、值得留下的一点：网格渲染到第几列由 `columnCount` 决定（`DiffGridModel.cs:554` 的循环上界），遇到"某个差异单元格根本不出现"，先看这个值怎么算出来的，再去看取值逻辑。
