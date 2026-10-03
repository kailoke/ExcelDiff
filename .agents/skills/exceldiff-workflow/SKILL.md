---
name: exceldiff-workflow
description: 本工程操作规范通道与机器事实：构建命令与必需参数、构建=部署=重启的固化流程、提权与完整性级别口径、安全启动（禁 -Wait）、模态弹窗识别、安装包发布门禁、对比测试数据源规则、推送闸门。凡任务涉及构建、部署重启、拉起对比窗口冒烟、安装包发布、常驻 IPC/托盘取证、对比回归取证时必须先读本技能，避免误用通道。
---

# ExcelDiff 工作流（本机事实 + 通道决策）

## 机器事实

- 构建工具链：本机只有 `dotnet SDK 8.0`（无独立 msbuild），构建命令全文唯一出处 = `AI_docs/ARCHITECTURE.md` §4；**必须**传 `/p:FrameworkPathOverride`（值 = 仓库根 `ProjectPaths.ps1` 的 `$RefAssemblyPath`，路径单一事实源，不写盘符）。
- 手动构建前先 `dotnet restore <proj> --configfile <repo>\.nuget\NuGet.Config`；日常走脚本（已内置 restore）。
- 权威验收腿 = `AI_Script/verify.ps1`（构建 + NetDiff 31 用例 + lang↔resx 同步 + 坑扫描）；`verify-scope.ps1 -Compile` 内部调它，无第二实现。
- 机器路径自查：`powershell -ExecutionPolicy Bypass -File ProjectPaths.ps1 -Print`。

## 构建与部署（通道唯一出处）

- **用户口述"构建" = `AI_Script/Deploy-And-Restart.ps1` 全流程**（构建 → 部署 → 重启常驻）。原因：常驻进程从部署目录启动并锁住 exe，仅本地编译不会让运行中的进程拿到新二进制。
- 提权部署：`Start-Process -Verb RunAs` **不带 `-Wait`**（会挂起，实测），父进程轮询部署日志 `deploy_edr.log` 出现 `DONE`/`FAIL`；`-ArgumentList` 数组元素对含空格路径必须**内嵌双引号**，否则目标路径在第一个空格处被截断、部署静默落到错误目录。
- 完整性级别：口径是"常驻与交互桌面**同级**"，不是"必须非提权"。UAC 关闭的机器上 explorer 与终端全是 High；`Deploy-And-Restart.ps1` 拉起常驻后实测完整性 SID，不一致即杀掉并判失败。**不要写"降级启动"分支**（用 explorer 降级会假成功；按管理员身份一刀切拒绝在 UAC 关闭机器上是误伤）。
- lang 部署坑：对已存在目标 `lang` 目录做 `-Recurse` 复制会嵌套成 `lang\lang`（顶层文件不更新）；脚本已改为复制前先删目标 `lang` 目录。
- 日志：`deploy_edr.log`（复制段）/ `deploy_all.log`（全流程总出口），都在仓库根。

## 安全启动与模态弹窗

- **绝不对转发进程 `Start-Process -Wait`**：无常驻时转发器自己变成常驻、永不退出。等待对比会话用 `AI_Script/Invoke-ExcelDiff.ps1`（fire-and-forget + 轮询窗口；`-WaitClose` 等关闭）。入库脚本由 `verify.ps1` 坑扫描自动拦截违规写法（INVARIANTS C4：转发进程不驻留）。
- 两类强制模态会阻断脚本（`AI_docs/ARCHITECTURE.md` §6.4、ADR-008（无差异弹窗自绘裁决））：
  - **无差异弹窗 `NoDiffWindow`**：无系统标题栏、顶部绿条；关闭 = 点右上角 ✕（仅关弹窗，对比窗口还在）或 ESC；红色"退出"按钮是 `IsDefault`（回车触发）会连对比窗口一起关，脚本注意区分。
  - **语言切换重启确认 MessageBox**：点"确定/OK"后应用关对比窗口，下次 diff 命令以新语言重建（ADR-005，语言切换关窗重建裁决）。
- 远程命令在模态存在时会被 `DismissModalWindows` 强关后生效（INVARIANTS C5），脚本预期"新命令总能打断旧模态"。

## 安装包发布

- 打包链唯一：`powershell -ExecutionPolicy Bypass -File ExcelDiff.Installer/Build-Setup.ps1`（隔离构建 → 载荷 zip → `ExcelDiff.Installer/Release/ExcelDiffSetup-<版本>.exe`）；`-SkipBuild` 复用 stage 重打。
- 发布门禁 = `AI_Script/verify-installer.ps1`：静态检查恒跑；`-Install` 追加 A–Q 十七个真实用例（**需管理员；先备份 `%APPDATA%\ExcelDiffEDR.GUI` 与 HKCU Run**；机器上留有安装记录或该 CLSID 已被占用时拒绝运行）。退出码表：0 成功 / 1 失败 / 2 帮助 / 3 无载荷 / 4 参数非法 / 130 取消 / 100 卸载已移交（移交语义见 INVARIANTS E13）。
- 交互式卸载向导只能人工验收（脚本点不了向导），清单见 `AI_docs/DECISION_LOG.md` ADR-018（卸载入口与移交语义裁决）后果段。

## 对比测试数据源

- 外部 xlsx 数据仓路径 = `ProjectPaths.ps1` 的 `$TestDataRepoPath`（环境变量 `EXCELDIFF_TESTDATA_REPO` 可覆盖）；仓库本地样例放 `TestExcel/`（gitignored）。
- **严格规则：只用同名文件的工作区版 VS git HEAD 版对比**（HEAD 版用 `git show` 二进制安全提取），严禁跨文件组合；制造差异前必须征得用户同意，测完可 `git checkout -- <path>` 恢复。
- 输出回归用 `DiffHarness/`（headless diff 输出工具，确定性文本；构建需先 restore + `FrameworkPathOverride`）。

## 提交与推送闸门

- **AI 不直接 commit**；改动完成后给 Commit subject / description 供用户审查，提交经用户当轮授权后执行（`AI_docs/AGENT_WORK_PROTOCOL.md`「Git 提交与追踪」）。
- **推送永远由业主本人执行**：Fork GUI 的 Push 按钮（左上角或 Ctrl+Shift+P）、或独立终端直接 `git push`——人类环境直接放行，无需任何变量。
- **推送闸门 = `.githooks/pre-push`**：只拦 AI 会话环境（检测编码宿主注入的 `ZCODE_*`/`ZAI_*` 环境变量）。业主在 AI 工具的集成终端里手动推时，用一次性豁免 `EXCELDIFF_ALLOW_PUSH=1`（PowerShell：`$env:EXCELDIFF_ALLOW_PUSH='1'; git push origin master`；Git Bash：`EXCELDIFF_ALLOW_PUSH=1 git push origin master`）。**AI 会话不得清除环境标记、不得设置该变量、也不得用 `--no-verify` 绕过**。

## 纪律提醒

- 禁改区/谨慎区以 `AI_Script/protected-paths.json` 为准；改动前跑 `/gate`。
- 部署后按 `AI_docs/EXECUTION_PLAN.md` §7（运行时验收清单）逐项冒烟。
