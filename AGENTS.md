# AGENTS.md

> AI 编程上下文已统一整理到 `AI_Programmer\` 目录。

开工入口：先读 [`AI_Programmer\AGENTS.md`](AI_Programmer/AGENTS.md)（操作手册，会指引 `ARCHITECTURE.md` / `CODEX.md` / `INVARIANTS.md` / `ADR.md`）。

分支 / upstream 状态：读 [`AI_Programmer\PROJECT_STATE.md`](AI_Programmer/PROJECT_STATE.md)（由 `AI_Script\refresh_state.ps1` 自动生成）。提交状态（HEAD、历史）直接问 git（`git rev-parse HEAD` / `git log`），文档里不维护副本。

AI 工作流脚本统一在 [`AI_Script\`](AI_Script)（`verify.ps1` 验收门禁 / `verify-installer.ps1` 安装包门禁 / `Deploy-And-Restart.ps1` 部署 / `Invoke-ExcelDiff.ps1` 安全启动 / `refresh_state.ps1` 状态刷新 / `refresh_codex.ps1` 行号校准）。
