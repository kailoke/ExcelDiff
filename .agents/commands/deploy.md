---
description: 构建→部署→重启常驻一条龙（Deploy-And-Restart.ps1；用户口述"构建"即指本流程）
---
用 Bash 执行项目根下的固化部署脚本：

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File "AI_Script/Deploy-And-Restart.ps1"
```

- 内部串联：restore + 构建 EDR → 提权复制到部署目录（仅复制步骤自提权，`-Verb RunAs` 不带 `-Wait`，父进程轮询 `deploy_edr.log` 出现 DONE/FAIL）→ 父进程拉起常驻 `--startup` 并实测其与 `explorer` 的完整性 SID（不一致即判失败）。
- 常驻进程锁着部署目录里的 exe——仅本地 `dotnet msbuild` 不会让运行中的进程拿到新二进制，必须部署覆盖后再重启；所以"构建"口径 = 本命令，不做纯本地编译替代。
- 开关：`-NoBuild`（只部署当前 bin）、`-NoRestart`（部署后不拉起常驻）。总出口日志 = 仓库根 `deploy_all.log`。
- 完整性级别、引号截断、lang 嵌套等坑的口径唯一出处 = `.agents/skills/exceldiff-workflow/SKILL.md`「构建与部署」；部署后按 `AI_docs/EXECUTION_PLAN.md` §7（运行时验收清单）冒烟。
