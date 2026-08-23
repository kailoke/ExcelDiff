在 D:\ExcelDiff 工作。开工前先读 AGENTS.md（必读入口，会指引 ARCHITECTURE.md / CODEX.md / INVARIANTS.md）。
基线：master 已含 WIP 提交，开工前先 git status / git log --oneline -3 确认。
验收：改完跑 powershell -ExecutionPolicy Bypass -File verify.ps1 必须全绿（双版编译 + NetDiff 31 用例 + lang↔resx 同步）；动 IPC/生命周期/读取层先核对 INVARIANTS.md。
提交：AI 不直接 commit；改动完成后给出 Commit subject/description 供审查，由用户决定是否提交（AGENTS.md §7.10）。
约束：遵循 AGENTS.md §10 编码规范；不主动加注释；UI 文本走 Resources.*；不动 backup_installed_*。
