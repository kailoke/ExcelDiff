在 D:\ExcelDiff 工作。开工前先读 AI_Programmer\AGENTS.md（必读入口，会指引 ARCHITECTURE.md / CODEX.md / INVARIANTS.md / ADR.md）。
版本状态：读 AI_Programmer\PROJECT_STATE.md 获取当前分支 / HEAD / 最近提交 / 未提交改动（单一事实源，由 AI_Script\refresh_state.ps1 生成，勿手改）；开工前仍 `git status` / `git log --oneline -3` 自确认。
验收：改完跑 powershell -ExecutionPolicy Bypass -File AI_Script\verify.ps1 必须全绿（EDE 主版本编译 + NetDiff 31 用例 + lang↔resx 同步 + 坑扫描）；动 IPC/生命周期/读取层先核对 AI_Programmer\INVARIANTS.md。ED（NPOI）为保留保底代码、不参与日常门禁（如需 ED/EDE 对照，可手工跑 `DiffHarness\run_diff_compare.ps1`）。
提交：AI 不直接 commit；改动完成后给出 Commit subject/description 供审查，由用户决定是否提交（AGENTS.md §7.10）。
约束：遵循 AGENTS.md §10 编码规范；不主动加注释（核心/易错/算法处除外）；UI 文本走 Resources.*；不动 backup_installed_*。
部署：提权写 Program Files 用 `Start-Process -Verb RunAs`（**不带 -Wait**）+ 轮询日志 DONE（ADR-011）；每次部署后立即重启常驻（--startup）。
