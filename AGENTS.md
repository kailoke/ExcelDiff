# AGENTS.md

> AI 编程上下文已统一整理到 `AI_Programmer\` 目录。

开工入口：先读 [`AI_Programmer\AGENTS.md`](AI_Programmer/AGENTS.md)（操作手册，会指引 `ARCHITECTURE.md` / `CODEX.md` / `INVARIANTS.md` / `ADR.md`）。

项目与 git 版本状态（分支 / HEAD / 最近提交）：读 [`AI_Programmer\PROJECT_STATE.md`](AI_Programmer/PROJECT_STATE.md)（由 `AI_Script\refresh_state.ps1` 自动生成）。

AI 工作流脚本统一在 [`AI_Script\`](AI_Script)（`verify.ps1` 验收门禁 / `Deploy-And-Restart.ps1` 部署 / `Invoke-ExcelDiff.ps1` 安全启动 / `refresh_state.ps1` 状态刷新 / `refresh_codex.ps1` 行号校准）。

---

## 调试工具：单元格渲染追踪

### 启用方式

构建时传递 `EnableCellTrace=true` 参数：

```powershell
dotnet msbuild ExcelDiff.GUI/ExcelDiff.GUI.csproj /p:Configuration=Release /p:EdrRead=true /p:EnableCellTrace=true /t:Rebuild /v:m /nologo
```

或通过 `Deploy-And-Restart.ps1` 部署（需先修改脚本传递此参数）。

### 日志位置

启用后，追踪日志写入 `%TEMP%\edr_celltrace.log`。

### 日志内容

- `[GetCell]` - FastGrid 请求渲染的每个单元格（row/col/direct/gridType）
- `[TryGetCellDiff]` - 查找单元格差异的结果（包括 NOT FOUND 的情况）
- `[GetCellText]` - 实际返回的文本值（status/text length）
- `[TraceCell]` - Modified 单元格的详细信息（src/dst 值长度）

### 典型问题诊断

**问题：修改的单元格不显示文本**

1. 启用追踪：`/p:EnableCellTrace=true`
2. 部署并重现问题
3. 读取日志：
   ```powershell
   Get-Content "$env:TEMP\edr_celltrace.log" | Select-String "col=2"
   ```
4. 分析：
   - 如果日志中没有 `col=2` 的记录 → 渲染循环未到达该列 → 检查 `columnCount` 计算
   - 如果有 `col=2` 但 `TryGetCellDiff NOT FOUND` → 单元格未正确创建 → 检查 `DiffCellsCaseEqual`
   - 如果有 `GetCellText` 但 text=NULL → 单元格值为空 → 检查数据源

**案例：columnCount 计算错误（已修复）**

- 症状：修改的单元格在第 2 列，但只渲染到第 0 列
- 日志：`[GetCell] col=0` 大量出现，无 `col=2`
- 根因：`columnCount = SheetDiff.Rows.Max(r => r.Value.Cells.Count)` 计算的是差异单元格数量（1），而非最大列索引+1（3）
- 修复：改为 `SheetDiff.Rows.Max(r => r.Value.Cells.Keys.Max() + 1)`
