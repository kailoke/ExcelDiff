在 D:\ExcelDiff 工作。开工前先读 AGENTS.md（必读入口，会指引 ARCHITECTURE.md / CODEX.md / INVARIANTS.md / ADR.md）。
基线：master 已含审计优化基线（bug 修复 84c17db / 性能 d1c9f3a / 可读性 cf1f295 / EqualizeColumnCount b5294dc / EditGraph Limit 守卫 1d02aab），开工前先 git status / git log --oneline -3 确认。
验收：改完跑 powershell -ExecutionPolicy Bypass -File verify.ps1 必须全绿（双版编译 + NetDiff 31 用例 + lang↔resx 同步 + 坑扫描）；功能改动另跑 DiffHarness 回归——`DiffHarness\run_diff_compare.ps1 -RelPath Config/Data/Level.xlsx`（有差异）与 `.../PostMatchDefeat.xlsx`（无差异），两者 ED/EDE 输出必须一致；动 IPC/生命周期/读取层先核对 INVARIANTS.md。
提交：AI 不直接 commit；改动完成后给出 Commit subject/description 供审查，由用户决定是否提交（AGENTS.md §7.10）。
约束：遵循 AGENTS.md §10 编码规范；不主动加注释（核心/易错/算法处除外）；UI 文本走 Resources.*；不动 backup_installed_*。
部署：提权写 Program Files 用 `Start-Process -Verb RunAs`（**不带 -Wait**）+ 轮询日志 DONE（ADR-011）；每次部署后立即重启常驻（--startup）。
