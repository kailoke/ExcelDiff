# AGENTS.md — 工程操作手册（AI 代理 / 开发者入口）

> **开始任何工作前先读本文 + `ARCHITECTURE.md`**。本文是操作手册（怎么构建、怎么改、有什么坑），
> `ARCHITECTURE.md` 是工程蓝图（结构、数据流、生命周期、设计约束）。两者互补，改动代码前都要过一遍。
> 本文件刻意保持精简，深水区一律指向 ARCHITECTURE.md 相应章节。

## 0. 会话开工清单（快速上手）

> 开工前按序执行；详细说明见对应章节。

1. 在 `D:\ExcelDiff` 工作。先读本文件（会指引 ARCHITECTURE.md / CODEX.md / INVARIANTS.md / ADR.md）。
2. **版本状态**：读 `PROJECT_STATE.md` 获取当前分支 / HEAD / 最近提交 / 未提交改动（单一事实源，由 `AI_Script\refresh_state.ps1` 生成，勿手改）；仍 `git status` / `git log --oneline -3` 自确认。
3. **验收**：改完跑 `powershell -ExecutionPolicy Bypass -File AI_Script\verify.ps1` 必须全绿（EDE 主版本编译 + NetDiff 31 用例 + lang↔resx 同步 + 坑扫描）；动 IPC/生命周期/读取层先核对 `INVARIANTS.md`。ED（NPOI）为保留保底代码、不参与日常门禁（如需 ED/EDE 对照，可手工跑 `DiffHarness\run_diff_compare.ps1`）。
4. **提交**：AI 不直接 commit；改动完成后给出 Commit subject/description 供审查，由用户决定是否提交（§7.10）。
5. **约束**：遵循 §10 编码规范；不主动加注释（核心/易错/算法处除外）；UI 文本走 Resources.*；不动 backup_installed_*。
6. **部署**：提权写 Program Files 用 `Start-Process -Verb RunAs`（**不带 -Wait**）+ 轮询日志 DONE（ADR-011）；每次部署后立即重启常驻（--startup）。

## 1. 项目一句话

ExcelDiff：Windows 桌面 GUI 差异对比工具（xls/xlsx/csv/tsv），可作 Git/Mercurial difftool。
WPF (.NET Framework 4.6.2) + Prism 6.3 + Unity 4.0.1 + YamlDotNet + AvalonDock。
同一份源码可编译出**两套产品**，其中 **EDE（ExcelDataReader 读取，读取效率约 +72%）** 为**主版本**——唯一的构建 / 部署 / 门禁目标；**ED（NPOI 读取）** 代码保留作保底对照（语义最全、EDR 盲区兜底），但**退出日常门禁 / 构建 / 部署 / 重启流程**。进程/程序集/配置/显示名全隔离。

## 2. 必读文档

> 以下文档统一放在 `AI_Programmer\` 目录（本文件也在其中）；根目录 `AGENTS.md` 仅作跳转指针。
> 命令中的仓库相对路径（如 `AI_Script\verify.ps1`、`ExcelDiff.GUI\...`）仍以仓库根 `D:\ExcelDiff` 为工作目录。

| 文档 | 作用 |
|------|------|
| `ARCHITECTURE.md` | 工程蓝图：解决方案结构、编译矩阵、模块职责、Diff 数据流、生命周期、部署布局、回归方法 |
| `AGENTS.md`（本文） | 操作手册：已验证命令、编码规范、方法论、陷阱、项目状态 |
| `CODEX.md` | 代码级索引：核心类公开方法、两条关键调用链、线程模型（类级导航） |
| `INVARIANTS.md` | 工程硬约束清单（改动前逐条核对，违反=阻断提交） |
| `ADR.md` | 架构决策记录（关键决策的 why，避免重开争论） |
| `PROJECT_STATE.md` | **项目与 git 版本状态单一事实源**（分支/HEAD/最近提交/未提交改动；由 `AI_Script\refresh_state.ps1` 生成，勿手改） |
| `AI_Script\refresh_state.ps1` | 刷新 `PROJECT_STATE.md` 的脚本 |
| `AI_Script\refresh_codex.ps1` | 校准 `CODEX.md` 关键符号行号的脚本 |
| `AI_Script\verify.ps1` | 一键验证门禁：构建 EDE 主版本 + NetDiff 单测 + lang↔resx 同步 + WIP 快照 |
| `README.md` | 用户向使用说明（CLI 参数、快捷键、外部命令） |

## 3. 目录结构（解决方案 = `ExcelDiff.sln`）

```
ExcelDiff.sln                  # 解决方案（VS2015 格式，dotnet msbuild 可构建）
ExcelDiff\                      # 类库：工作簿/工作表/单元格读取、Diff 模型构建、CSV/TSV 解析
  ExcelWorkbook.cs               #   入口工厂：按扩展名分发读取（#if NPOI_READ → NPOI，否则 EDR）
  ExcelSheet.cs / ExcelSheetDiff.cs / ExcelRowDiff.cs / ExcelCellDiff.cs
  ExcelReader.cs / ExcelUtility.cs / ExcelWorkbookType.cs
  CsvReader.cs / TsvReader.cs    #   自研解析器，无第三方依赖
ExcelDiff.GUI\                  # WPF 可执行：UI、命令层、设置、IPC、托盘、本地化、常驻生命周期
  App.xaml.cs                    #   入口/生命周期（SingleInstance、托盘、远程命令路由、DisplayName 随 EDR_READ 切换）
  SingleInstance.cs              #   命名管道 server/client（channel id 由 exe 名派生，ED/EDE 互不干扰）
  TrayIconManager.cs             #   托盘常驻（隐藏/恢复/退出）
  StartupHelper.cs               #   开机自启（Run 键）管理
  Timing.cs                      #   PERF_TIMING 分段计时
  Commands\                      #   CommandFactory / DiffCommand / CommandLineOption / ICommand / CommandType
  Models\                        #   DiffGridModel（行状态预计算 + minimap 优化）、DiffType
  ViewModels\                    #   DiffViewModel / MainWindowViewModel / 各设置窗口 VM
  Views\                         #   MainWindow / DiffView / NoDiffWindow / ProgressWindow / 设置系列窗口
  Views\DiffViewEvent\           #   事件分发器/监听器/处理器
  Settings\                      #   ApplicationSetting（YamlDotNet → %APPDATA%\<程序集名>\<程序集名>.yml）
  Localization\                  #   LocalizationManager（外置 lang\<culture>.json，缺键回落 Resources）
  Styles\EMColor.cs              #   差异配色（单元格高亮）
  Shell\                         #   PowerShellHost / PowerShellInvocation（内置控制台）
  Properties\Resources*.resx     #   资源字符串源（en-US 中性 / zh-CN），lang\*.json 由此生成
NetDiff\NetDiff\                 # 类库：Myers/EditGraph 文本差异算法
NetDiff\NetDiff.Test\            # MSTest 单元测试源码（Test.cs，31 个用例）
NetDiff\NetDiff.TestRunner\      # 离线测试 runner（MSTest shim + 反射执行，零第三方依赖，见 §4）
DiffHarness\                     # headless diff 对比工具（库层直调，ED/EDE 输出对比，见 §7.9）
FastWpfGrid\                     # 高性能虚拟化网格控件 + WriteableBitmapEx 位图扩展
ExcelDiff.ShellExtension\       # COM 外壳扩展（资源管理器右键菜单）
ExcelDiff.Installer\            # VDProj MSI 打包（不参与日常构建）
lang\                            # 外置语言文件 en-US.json / zh-CN.json（UTF-8，随 exe 目录部署）
packages\refs\                   # .NET Framework 参考程序集（构建必需，见 §5）
backup_installed_*/              # 部署前快照，勿动
Build\Release\                   # WriteableBitmapEx 产物（gitignore）
AI_Script\                       # AI 工作流脚本（见 §2）：verify.ps1 验收门禁 / Deploy-And-Restart.ps1 部署重启 / Invoke-ExcelDiff.ps1 安全启动 / refresh_state.ps1 状态刷新 / refresh_codex.ps1 行号校准
.githooks\                       # git 钩子（core.hooksPath=.githooks）：pre-commit 提交前刷新并并入本次提交 / post-checkout、post-merge 后刷新 + 条件校准 CODEX.md
GenerateLangJson.ps1             # resx → lang\*.json 生成脚本
README.md / README.en            # 用户文档（中/英）；media\ 截图；LICENSE（MIT，含 Kailoke 版权）
AI_Programmer\                    # AI 上下文（见 §2）：AGENTS/ARCHITECTURE/CODEX/INVARIANTS/ADR/PROJECT_STATE
```

依赖关系：`GUI → ExcelDiff → NetDiff`；`GUI → FastWpfGrid → WriteableBitmapEx.Wpf`。

## 4. 构建工具链

- 本机仅有 `dotnet SDK 8.0`（`C:\Program Files\dotnet\dotnet.exe`），**没有独立 msbuild**，用 `dotnet msbuild`。
- 关键：.NET Framework 引用程序集不在本机 SDK 里，**必须**传 `TargetFrameworkRootPath="D:\ExcelDiff\packages\refs"`。
- 下列命令均已在本机验证可编译（Release, AnyCPU）。

### EDE（主版本，EDR 读取）— 产物 `ExcelDiffEDR.GUI.exe`

```
dotnet msbuild ExcelDiff.GUI/ExcelDiff.GUI.csproj /p:Configuration=Release /p:EdrRead=true /p:TargetFrameworkRootPath="D:\ExcelDiff\packages\refs" /p:IncludePackageReferencesDuringMarkupCompilation=false /p:GenerateResourceMSBuildArchitecture=CurrentArchitecture /p:GenerateResourceMSBuildRuntime=CurrentRuntime /t:Build /v:m /nologo
```

> **会话约定（固化）**：用户在本会话中说"构建"时，**即执行整条"构建 → 部署 → 重启"流程**，而非仅本地编译。直接用固化脚本 `AI_Script\Deploy-And-Restart.ps1`（内部已串联构建 EDE + 部署 + 非提权拉起常驻，且仅对复制步骤自提权、父进程轮询日志；见 §7.6）。原因：常驻进程从 `D:\Program Files\ExcelDiffEDRTool` 启动并锁住 exe，仅本地 `dotnet msbuild` 不会让运行中的进程拿到新二进制——必须部署覆盖后再重启才生效。验证/排查前的纯本地编译可用上面的 `dotnet msbuild` 命令，但用户口述"构建"一律走脚本全流程。

### ED（保底版，NPOI 读取，代码保留 / 不参与日常构建）— 产物 `ExcelDiff.GUI.exe`

同上，去掉 `/p:EdrRead=true`（默认）。仅在需要 ED 保底对照验证时手工构建。

### 只构建核心库（快速验证读取层改动）

```
dotnet msbuild ExcelDiff/ExcelDiff.csproj /p:Configuration=Release /p:TargetFrameworkRootPath="D:\ExcelDiff\packages\refs" /t:Build /v:m /nologo
```

### NetDiff 单测（离线 runner，零第三方依赖）

本机无 VS/vstest，MSTest 程序集不在 `packages\refs`；`NetDiff.TestRunner` 用自带 MSTest shim + 反射执行 `NetDiff.Test\Test.cs` 的 31 个用例。

```
dotnet msbuild NetDiff/NetDiff.TestRunner/NetDiff.TestRunner.csproj /p:Configuration=Release /p:TargetFrameworkRootPath="D:\ExcelDiff\packages\refs" /t:Build /v:m /nologo
& "NetDiff\NetDiff.TestRunner\bin\Release\NetDiff.TestRunner.exe"
```

### 一键验证门禁

```
powershell -ExecutionPolicy Bypass -File AI_Script\verify.ps1        # 构建 EDE 主版本 + 单测 + lang 同步 + WIP 快照
powershell -ExecutionPolicy Bypass -File AI_Script\verify.ps1 -SkipBuild   # 只查单测 + lang 同步 + WIP
```

## 5. 编译开关矩阵（双版本隔离的机制）

> **日常门禁/构建/部署只针对 EDE（`EdrRead=true`）**；ED（默认空）代码保留作保底对照，退出日常流程。

| MSBuild 属性 | 效果（GUI 与库联动） |
|------|------|
| `EdrRead=true`（EDE 主版本） | GUI `AssemblyName=ExcelDiffEDR.GUI`、定义 `EDR_READ`、`DisplayName=ExcelDiffEDR`；库**不**定义 `NPOI_READ`（走 EDR） |
| `EdrRead`（默认空，ED 保底，保留源码不日常构建） | GUI `AssemblyName=ExcelDiff.GUI`、`DisplayName=ExcelDiff`；库定义 `NPOI_READ`（NPOI 读取） |
| `EnablePerfTiming=true` | GUI 与库同时定义 `PERF_TIMING`，注入分段计时 |

- 配置目录天然隔离：`%APPDATA%\ExcelDiff.GUI\`（ED） vs `%APPDATA%\ExcelDiffEDR.GUI\`（EDE）。
- 代码里 `#if NPOI_READ`（库）与 `#if EDR_READ`（GUI）分支读取/显示名。

## 6. 模块设计速查（“改什么功能 → 动哪些文件”）

| 需求 | 入口文件 | 说明 |
|------|---------|------|
| 新增文件类型解析 | `ExcelDiff/ExcelWorkbook.cs`、`CsvReader.cs`/`TsvReader.cs` | 按扩展名分发，EDE 主版本要过 |
| 差异算法调整 | `NetDiff/NetDiff/EditGraph.cs`、`DiffUtil.cs` | 行级/单元格级共用；改后跑 `NetDiff.Test` |
| 差异提取规则/日志格式 | `ExcelDiff/ExcelSheetDiff.cs`、`ExcelSheetDiffConfig.cs`、`DiffExtractionSettingWindow*` | |
| UI 字符串/本地化 | `Properties/Resources*.resx` → 跑 `GenerateLangJson.ps1` → `lang\*.json` | 见 §7 本地化流程 |
| 差异配色 | `GUI/Styles/EMColor.cs` | |
| 单元格渲染/网格性能 | `FastWpfGrid/FastWpfGrid/FastGridControl_Render.cs` | |
| 设置项新增/持久化 | `GUI/Settings/ApplicationSetting.cs` + 对应窗口/VM | YAML，注意 UTF-8 陷阱 |
| 单实例/托盘/生命周期 | `GUI/App.xaml.cs`、`SingleInstance.cs`、`TrayIconManager.cs`、`StartupHelper.cs` | 常驻进程逻辑 |

## 7. 开发方法论

1. **主版本 EDE**：任何 UI/读取/行为改动必须 EDE（`EdrRead=true`）编译通过。ED（NPOI）代码保留作保底对照，**不在日常门禁中编译**（仅需对照验证时手工 build，见 §4）。
2. **本地化流程**：字符串改动进 `Resources.resx`（en-US 中性）+ `Resources.zh-CN.resx`（仅 zh/en 两语言，默认 zh-CN）→ 运行 `GenerateLangJson.ps1` 重新生成 `lang\*.json`（UTF-8 BOM）。`{x:Static Resources.*}` 在窗口加载时固化 → 语言切换通过 `App.CloseMainWindowForLanguageChange()` 关窗，下次 diff 命令以新语言重建。
3. **测试**：NetDiff 算法改动用 `NetDiff.TestRunner`（31 用例，命令见 §4）。GUI 层回归用手工/脚本冒烟（见 ARCHITECTURE.md §9）。任何改动完成后跑 `AI_Script\verify.ps1` 一键门禁。
4. **回归比对**：对比对象必须是**同一文件的两个版本**（git HEAD vs 工作区），严禁拿两个不同文件对比。测试数据源见 §7.7。
5. **读取层定位**：**EDE=EDR 主版本**（读取快约 72%）；**ED=NPOI 保底对照**（NPOI 语义最全，代码保留、不日常构建）。EDR 读不到“仅样式无值”单元格 → 列对齐漂移 → 这正是 ED 保底代码保留的意义，**不得移除 ED 代码**。基准测试以 EDE 为准，ED 代码仅作保底对照验证。
6. **构建与部署次序**：只构建/部署 **EDE 主版本**（构建 EDE → 部署 EDE → 重启 EDE 常驻；ED 保底代码不参与，见陷阱 §8.2）。**每次构建部署后必须立即重启对应常驻进程**（杀进程 → 从部署路径 `--startup` 拉起），保证新构建即时生效。原因：常驻进程从 Program Files 启动且锁住 exe——不杀进程无法覆盖部署，且旧进程仍在内存运行，测试结果会失真。**部署动作（提权写 Program Files）**：用 `Start-Process powershell -Verb RunAs`（**不带 `-Wait`**）启动提权脚本 → 轮询其日志文件出现 `DONE` → 再重启常驻（见陷阱 §8.6）。**⚠️ `Start-Process -ArgumentList` 数组拼接不会自动给含空格路径加引号**——含空格的目标路径（如 `D:\Program Files\...`）必须在数组元素里**手动内嵌引号**（`"-Dst","`"D:\Program Files\ExcelDiffTool`""`），否则会被截断（见陷阱 §8.7）。
   - **固化脚本 `AI_Script\Deploy-And-Restart.ps1`**（可人工双击 / `powershell -File` 执行，也可由临时命令调用）：自动完成“构建 EDE→部署→重启 EDE 常驻”。**必须非提权运行**（GUI 须以普通用户 IL 运行，否则与 Fork 等非提权 difftool 客户端的命名管道 IPC / 托盘交互会因 UIPI 失败）。脚本**仅对复制步骤自提权**：未以管理员运行时用 `Start-Process -Verb RunAs`（不带 `-Wait`）拉起一个提权子进程仅做“杀进程释放锁 + 复制”，父进程（非提权）轮询 `deploy_edr.log` 出现 `DONE`/`FAIL`；提权数组元素对含空格路径内嵌引号（§8.7）；杀进程按进程名 `ExcelDiffEDR.GUI`（经提权父进程启动的进程 `Path` 可能为空，须按 `Name` 而非 `Path` 匹配）；复制前删目标 `lang` 目录规避 `lang\lang` 嵌套坑（ARCHITECTURE §8）；复制后校验目标 exe 已落盘；**重启常驻由非提权父进程 `Start-Process`（不带 `-Wait`）拉起**以保普通用户 IL。开关：`-NoBuild`（仅部署当前 bin）、`-NoRestart`（部署后不拉起常驻）。人工/临时命令执行范例：`powershell -ExecutionPolicy Bypass -File AI_Script\Deploy-And-Restart.ps1`。
7. **对比测试数据源**：`D:\P\BackPack\baggame\Config\Data`（git 管理的 xlsx 配置表目录）。**严格规则：只用同名文件的 Unstaged（工作区）VS HEAD 做对比**——工作区文件直接引用，HEAD 版用 `cmd /c "git -C <repo> show HEAD:<相对路径> > <tmp>"` 提取（二进制安全），禁止跨文件/跨版本组合。**若某文件两版无差异而需要制造差异时，修改工作区文件前必须先征得用户同意**；测试后可用 `git checkout -- <path>` 恢复。常用测试文件：`Level.xlsx`（**有差异**）、`PostMatchDefeat.xlsx`（**无差异**）。
8. **测试模态弹窗注意事项**（自动化/脚本测试会被强制阻塞）：
   - **无差异弹窗 `NoDiffWindow`**：两文件无差异且 `NotifyEqual` 开启时，由 `DiffView.ExecuteDiff` `ShowDialog` 弹出（模态）。识别：无系统标题栏（`WindowStyle=None`）、顶部绿色条（`#FF43A047`）带自定义"✕"、正文为 `Message_NoDiffFormat`（如"左[...] - 右[...] = 没有区别"）。**关闭 = 点右上角"✕"**（`CloseButton_Click`：仅关弹窗、不关对比窗口；ESC 等效）；红色"退出"按钮是 `IsDefault`（回车触发）会连对比窗口一起关，脚本注意区分。
   - **重启确认 MessageBox**：切换多语言后由 `App.UpdateResourceCulture` 弹出（`Message_Reboot`：en "ExcelDiff will close to change the language." / zh "ExcelDiff将关闭以变更语言"）。**处理 = 点"确定/OK"**；确认后应用关对比窗口，下次 diff 命令以新语言重建。
   - 两者均为强制模态，会阻断后续命令；脚本需先探测（窗口/文案特征）再处理，否则测试挂起。
9. **headless diff harness（ED/EDE 对照诊断工具，保留、非门禁必需）**：`DiffHarness\` 零第三方离线对比，直接调库层（`ExcelWorkbook.Create` → `ExcelSheet.Diff` → `CreateSummary`）输出确定性 diff 文本，以 EDE（主版本）为准、ED（保底）作验证对照。用法：`powershell -ExecutionPolicy Bypass -File DiffHarness\run_diff_compare.ps1 -RelPath Config/Data/Level.xlsx`（自动提取 HEAD → 构建/运行双变体 → 比对，忽略 READER 行）；可用 `-NoBuild` 跳过重编译。产出 `DiffHarness.exe`（NPOI）/ `DiffHarnessEDR.exe`（EDR），输出 UTF-8。**配置对齐**：harness 默认读取配置 = GUI 默认 `ApplicationSetting`（4 项 trim 均 false）；复现 GUI 场景必须传一致参数——`--skip-first-blank-rows/columns`、`--trim-last-blank-rows/columns`（对应 `Setting.SkipFirstBlankRows/...`）、`--src-header N`/`--dst-header N`（列头对齐）。注意 harness 只验证"两变体一致"，不验证"diff 绝对正确"（与 GUI 共用 `ExcelSheet.Diff` 引擎），真实结果用 `VerifyRead` 双读 + ED 对照。
10. **Git 提交准则（硬性）**：**AI 不可直接 commit**。改动完成后，说明本次改动的 **Commit subject / description**，并从版本控制角度给出提交建议；实际提交由用户决定，且用户需先审查 subject/description 再提交。

## 8. 已知陷阱（务必遵守）

1. **UTF-8 破坏**：PowerShell 5.1 的 `Get-Content`/`Set-Content -Encoding UTF8` 按 ANSI 读写，破坏含中文的 YAML/JSON → 解析崩溃。改写非 ASCII 文件必须用文件写入工具（UTF-8 无 BOM）或 `[System.IO.File]::WriteAllText` + 显式 UTF8。
2. **MSBuild 增量互删**：不能在同一条命令里连续构建两个变体——增量构建会把另一变体的 exe 当过期输出清掉。仅在手工同时构建 EDE/ED 两变体时才需分步（日常门禁只构建 EDE，无此问题）。
3. **`-Wait` 挂起**：对转发进程 `Start-Process -Wait` 会挂起（无常驻进程时转发器变常驻永不退出）。
   - **检测**：`AI_Script\verify.ps1` 已内置坑扫描——任一入库 `*.ps1`（注释除外）出现 `Start-Process ... -Wait ... ExcelDiff` 即门禁失败（verify.ps1 自身排除）。
   - **预防**：需要等待 diff 会话完成时用 `AI_Script\Invoke-ExcelDiff.ps1`（fire-and-forget 启动 + 轮询主窗口出现/关闭，绝不 `-Wait` 等进程退出）；禁止手工对转发进程 `-Wait`。
4. **IPC 不得阻塞**：管道线程只能用 `Dispatcher.BeginInvoke` 投递，绝不能同步等待模态框，否则模态框存在时死锁。
5. **`bin`/`obj`/`Build` 均 gitignore**：构建产物不入库，改代码后构建不污染 git 状态。`backup_installed_*` 是部署前快照，勿动。
6. **提权部署 `-Wait` 挂起**：`Start-Process powershell -Verb RunAs -Wait` 在 UAC 提权 + msbuild 子进程场景下**不返回**，bash 会卡到超时（部署实际 10-30 秒已完成）。预防：提权启动**不带 `-Wait`** → 轮询部署脚本写出的日志文件（出现 `DONE`）再继续，然后重启常驻。
7. **`-ArgumentList` 空格路径截断**：`Start-Process -ArgumentList` 把数组拼接成命令行字符串时**不会**自动给含空格参数加引号。给部署脚本传 `-Dst "D:\Program Files\ExcelDiffTool"` 若写成普通数组元素，实际拼接为 `-Dst D:\Program Files\ExcelDiffTool` → 目标被截断成 `D:\Program`，部署静默落到错误目录。预防：**数组元素内嵌双引号**（`"-Dst","`"D:\Program Files\ExcelDiffTool`""`），部署后核对目标 exe 的 LastWriteTime/Length 已更新再重启常驻。

## 9. 项目状态

> **动态 git 状态（分支 / HEAD / 最近提交 / 未提交改动）以 `PROJECT_STATE.md` 为单一事实源**（`AI_Script\refresh_state.ps1` 刷新）。

- **版本定位**：EDE=EDR 主版本（读取快约 72%）；ED=NPOI 保底代码保留、不日常构建（见 §7.5 / ADR-012）。
- **部署目录**：`D:\Program Files\ExcelDiffEDRTool`（EDE 主版本）。
- **自动刷新**：git 钩子（`.githooks\` + `core.hooksPath=.githooks`）：`pre-commit` 提交前刷新 `PROJECT_STATE.md`（本次提交触及 C# 源码时并校准 `CODEX.md`）并 `git add` 回本次提交；`post-checkout` / `post-merge` 在操作后刷新。一次性启用：`git config core.hooksPath .githooks`。
- 改动前先 `git status` / `git log --oneline -3` 确认；任何改动完成后跑 `AI_Script\verify.ps1`；动 IPC/生命周期/读取层先核对 `INVARIANTS.md`。

## 10. 编码规范（沿用既有代码）

- .NET Framework 4.6.2，C# 老式写法（无 nullable reference、无 target-typed new、无文件级 namespace；`using` 顶部、`{}` 内部成对）。
- 命名空间 = 目录名（`ExcelDiff.GUI.ViewModels`、`ExcelDiff.GUI.Settings` 等）。
- ViewModel 继承 Prism `BindableBase`；设置类走 `Setting<T>`（继承 `SerializableBindableBase`）+ `IgnoreEqualAttribute`。
- 条件编译用 `#if NPOI_READ / EDR_READ / PERF_TIMING`，不引入新第三方依赖（除非有充分理由并同步 packages.config）。
- 字符串一律走 `Resources.*`（经 `LocalizationManager` 桥接），禁止硬编码 UI 文本。
- **不主动添加代码注释**；改动遵循现有代码风格与既有模式（核心算法/易错/设计动机处应保留或补充注释，见 ADR-010 对 EditGraph 的注释处理）。

## 11. 工程负责人职责（AI 会话共同遵循）

AI 会话以资深主程序视角工作，对整体工程质量负责：
1. **框架与维护**：改动前读本文 + ARCHITECTURE + CODEX + INVARIANTS + ADR；保持架构一致性，不引入与既有模式冲突的方案。
2. **代码性能**：改动后评估性能影响（diff 管道、渲染、事件、持久化）；触及 `#if` 双版本/读取层/网格渲染等热路径先核对 INVARIANTS F 区与性能项清单。
3. **测试纪律**：任何功能改动跑完整测试（`AI_Script\verify.ps1` + DiffHarness 双文件回归），见 §0 开工清单 / §4 门禁；动 IPC/生命周期/读取层先核对 INVARIANTS。
4. **指导其他会话**：本文件 + ARCHITECTURE/CODEX/INVARIANTS/ADR 即权威上下文；其他会话直接读本文件（§0 开工清单）；发现文档与代码不一致时修正文档。
5. **质量门**：不擅自提交 git（§7.10）；改动给出 commit subject/description 供审查；高危区（diff 算法、读取层、生命周期）改动需在提交说明中注明测试证据。
