# AGENTS.md — 工程操作手册（AI 代理 / 开发者入口）

> **开始任何工作前先读本文 + `ARCHITECTURE.md`**。本文是操作手册（怎么构建、怎么改、有什么坑），
> `ARCHITECTURE.md` 是工程蓝图（结构、数据流、生命周期、设计约束）。两者互补，改动代码前都要过一遍。
> 本文件刻意保持精简，深水区一律指向 ARCHITECTURE.md 相应章节。

## 1. 项目一句话

ExcelDiff：Windows 桌面 GUI 差异对比工具（xls/xlsx/csv/tsv），可作 Git/Mercurial difftool。
WPF (.NET Framework 4.6.2) + Prism 6.3 + Unity 4.0.1 + YamlDotNet + AvalonDock。
同一份源码可编译出**两套产品**：**EME（优先/基准版，ExcelDataReader 读取，读取效率约 +72%）**与 **EM（保底版，NPOI 读取）**，进程/程序集/配置/显示名全隔离。**开发与基准测试以 EME 为准，EM 作保底验证对照**。

## 2. 必读文档

| 文档 | 作用 |
|------|------|
| `ARCHITECTURE.md` | 工程蓝图：解决方案结构、编译矩阵、模块职责、Diff 数据流、生命周期、部署布局、回归方法 |
| `AGENTS.md`（本文） | 操作手册：已验证命令、编码规范、方法论、陷阱、当前工作区状态 |
| `CODEX.md` | 代码级索引：核心类公开方法、两条关键调用链、线程模型（类级导航） |
| `INVARIANTS.md` | 工程硬约束清单（改动前逐条核对，违反=阻断提交） |
| `ADR.md` | 架构决策记录（关键决策的 why，避免重开争论） |
| `verify.ps1` | 一键验证门禁：构建双版 + NetDiff 单测 + lang↔resx 同步 + WIP 快照 |
| `README.md` | 用户向使用说明（CLI 参数、快捷键、外部命令） |

## 3. 目录结构（解决方案 = `ExcelDiff.sln`）

```
ExcelDiff.sln                  # 解决方案（VS2015 格式，dotnet msbuild 可构建）
ExcelDiff\                      # 类库：工作簿/工作表/单元格读取、Diff 模型构建、CSV/TSV 解析
  ExcelWorkbook.cs               #   入口工厂：按扩展名分发读取（#if NPOI_READ → NPOI，否则 EDR）
  ExcelSheet.cs / ExcelSheetDiff.cs / ExcelRowDiff.cs / ExcelCellDiff.cs
  ExcelReader.cs / ExcelUtility.cs / ExcelCellValueComparer.cs / ExcelWorkbookType.cs
  CsvReader.cs / TsvReader.cs    #   自研解析器，无第三方依赖
ExcelDiff.GUI\                  # WPF 可执行：UI、命令层、设置、IPC、托盘、本地化、常驻生命周期
  App.xaml.cs                    #   入口/生命周期（SingleInstance、托盘、远程命令路由、DisplayName 随 EDR_READ 切换）
  SingleInstance.cs              #   命名管道 server/client（channel id 由 exe 名派生，EM/EME 互不干扰）
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
  Properties\Resources*.resx     #   资源字符串源（en-US 中性 / zh-CN / ja-JP），lang\*.json 由此生成
NetDiff\NetDiff\                 # 类库：Myers/EditGraph 文本差异算法
NetDiff\NetDiff.Test\            # MSTest 单元测试源码（Test.cs，31 个用例）
NetDiff\NetDiff.TestRunner\      # 离线测试 runner（MSTest shim + 反射执行，零第三方依赖，见 §4）
DiffHarness\                     # headless diff 对比工具（库层直调，EM/EME 输出对比，见 §7.9）
FastWpfGrid\                     # 高性能虚拟化网格控件 + WriteableBitmapEx 位图扩展
ExcelDiff.ShellExtension\       # COM 外壳扩展（资源管理器右键菜单）
ExcelDiff.Installer\            # VDProj MSI 打包（不参与日常构建）
lang\                            # 外置语言文件 en-US.json / zh-CN.json（UTF-8，随 exe 目录部署）
packages\refs\                   # .NET Framework 参考程序集（构建必需，见 §5）
backup_installed_*/              # 部署前快照，勿动
Build\Release\                   # WriteableBitmapEx 产物（gitignore）
verify.ps1                       # 一键验证门禁（构建双版 + 单测 + lang 同步 + §8.3 坑扫描 + WIP 快照）
Invoke-ExcelDiffDiff.ps1        # 安全启动 GUI diff（fire-and-forget + 轮询窗口，替代 -Wait，见 §8.3）
CODEX.md / INVARIANTS.md / ADR.md# 代码索引 / 硬约束清单 / 决策记录（见 §2）
GenerateLangJson.ps1             # resx → lang\*.json 生成脚本
```

依赖关系：`GUI → ExcelDiff → NetDiff`；`GUI → FastWpfGrid → WriteableBitmapEx.Wpf`。

## 4. 构建工具链（已验证 2026-08-23）

- 本机仅有 `dotnet SDK 8.0`（`C:\Program Files\dotnet\dotnet.exe`），**没有独立 msbuild**，用 `dotnet msbuild`。
- 关键：.NET Framework 引用程序集不在本机 SDK 里，**必须**传 `TargetFrameworkRootPath="D:\ExcelDiff\packages\refs"`。
- 下列命令均已在本机验证可编译（Release, AnyCPU）。

### EME（优先/基准版，EDR 读取）— 产物 `ExcelDiffEDR.GUI.exe`

```
dotnet msbuild ExcelDiff.GUI/ExcelDiff.GUI.csproj /p:Configuration=Release /p:EdrRead=true /p:TargetFrameworkRootPath="D:\ExcelDiff\packages\refs" /p:IncludePackageReferencesDuringMarkupCompilation=false /p:GenerateResourceMSBuildArchitecture=CurrentArchitecture /p:GenerateResourceMSBuildRuntime=CurrentRuntime /t:Build /v:m /nologo
```

### EM（保底版，NPOI 读取）— 产物 `ExcelDiff.GUI.exe`

同上，去掉 `/p:EdrRead=true`（默认）。

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
powershell -ExecutionPolicy Bypass -File verify.ps1        # 构建双版 + 单测 + lang 同步 + WIP 快照
powershell -ExecutionPolicy Bypass -File verify.ps1 -SkipBuild   # 只查单测 + lang 同步 + WIP
```

## 5. 编译开关矩阵（双版本隔离的机制）

| MSBuild 属性 | 效果（GUI 与库联动） |
|------|------|
| `EdrRead=true`（EME 优先/基准） | GUI `AssemblyName=ExcelDiffEDR.GUI`、定义 `EDR_READ`、`DisplayName=ExcelDiffEDR`；库**不**定义 `NPOI_READ`（走 EDR） |
| `EdrRead`（默认空，EM 保底） | GUI `AssemblyName=ExcelDiff.GUI`、`DisplayName=ExcelDiff`；库定义 `NPOI_READ`（NPOI 读取） |
| `EnablePerfTiming=true` | GUI 与库同时定义 `PERF_TIMING`，注入分段计时 |

- 配置目录天然隔离：`%APPDATA%\ExcelDiff.GUI\`（EM） vs `%APPDATA%\ExcelDiffEDR.GUI\`（EME）。
- 代码里 `#if NPOI_READ`（库）与 `#if EDR_READ`（GUI）分支读取/显示名。

## 6. 模块设计速查（“改什么功能 → 动哪些文件”）

| 需求 | 入口文件 | 说明 |
|------|---------|------|
| 新增文件类型解析 | `ExcelDiff/ExcelWorkbook.cs`、`CsvReader.cs`/`TsvReader.cs` | 按扩展名分发，EM/EME 都要过 |
| 差异算法调整 | `NetDiff/NetDiff/EditGraph.cs`、`DiffUtil.cs` | 行级/单元格级共用；改后跑 `NetDiff.Test` |
| 差异提取规则/日志格式 | `ExcelDiff/ExcelSheetDiff.cs`、`ExcelSheetDiffConfig.cs`、`DiffExtractionSettingWindow*` | |
| UI 字符串/本地化 | `Properties/Resources*.resx` → 跑 `GenerateLangJson.ps1` → `lang\*.json` | 见 §7 本地化流程 |
| 差异配色 | `GUI/Styles/EMColor.cs` | |
| 单元格渲染/网格性能 | `FastWpfGrid/FastWpfGrid/FastGridControl_Render.cs` | |
| 设置项新增/持久化 | `GUI/Settings/ApplicationSetting.cs` + 对应窗口/VM | YAML，注意 UTF-8 陷阱 |
| 单实例/托盘/生命周期 | `GUI/App.xaml.cs`、`SingleInstance.cs`、`TrayIconManager.cs`、`StartupHelper.cs` | 常驻进程逻辑 |

## 7. 开发方法论

1. **双版同步**：任何 UI/读取/行为改动必须 EM + EME 两版都编译通过（`EdrRead` 空 / `true` 各 build 一次）。
2. **本地化流程**：字符串改动进 `Resources.resx`（en-US 中性）+ `Resources.zh-CN.resx`（仅 zh/en 两语言，默认 zh-CN）→ 运行 `GenerateLangJson.ps1` 重新生成 `lang\*.json`（UTF-8 BOM）。`{x:Static Resources.*}` 在窗口加载时固化 → 语言切换通过 `App.CloseMainWindowForLanguageChange()` 关窗，下次 diff 命令以新语言重建。
3. **测试**：NetDiff 算法改动用 `NetDiff.TestRunner`（31 用例，命令见 §4）。GUI 层回归用手工/脚本冒烟（见 ARCHITECTURE.md §9）。任何改动完成后跑 `verify.ps1` 一键门禁。
4. **回归比对**：对比对象必须是**同一文件的两个版本**（git HEAD vs 工作区），严禁拿两个不同文件对比。测试数据源见 §7.7。⚠️ 特定开发需求曾用的 SHA 基线对比（diffcompare 7 对基线）**不作为通用准则**；后续若有必须的回归对比，单独建文件记录。
5. **读取层定位**：**EME=EDR 优先/基准**（读取快约 72%）；**EM=NPOI 保底对照**（NPOI 语义最全）。EDR 读不到“仅样式无值”单元格 → 列对齐漂移 → 这正是 EM 保底存在的意义，**不得移除 EM**。基准测试以 EME 为准，EM 作保底验证。
6. **构建与部署次序**：构建 EME → 部署 EME → 构建 EM → 部署 EM，分步进行（见陷阱 §8.2）。**每次构建部署后必须立即重启对应常驻进程**（杀进程 → 从部署路径 `--startup` 拉起），保证新构建即时生效。原因：常驻进程从 Program Files 启动且锁住 exe——不杀进程无法覆盖部署，且旧进程仍在内存运行，测试结果会失真。
7. **对比测试数据源**：`D:\P\BackPack\baggame\Config\Data`（git 管理的 xlsx 配置表目录）。**严格规则：只用同名文件的 Unstaged（工作区）VS HEAD 做对比**——工作区文件直接引用，HEAD 版用 `cmd /c "git -C <repo> show HEAD:<相对路径> > <tmp>"` 提取（二进制安全），禁止跨文件/跨版本组合。**若某文件两版无差异而需要制造差异时，修改工作区文件前必须先征得用户同意**；测试后可用 `git checkout -- <path>` 恢复。
8. **测试模态弹窗注意事项**（自动化/脚本测试会被强制阻塞）：
   - **无差异弹窗 `NoDiffWindow`**：两文件无差异且 `NotifyEqual` 开启时，由 `DiffView.ShowDiff` `ShowDialog` 弹出（模态）。识别：无系统标题栏（`WindowStyle=None`）、顶部绿色条（`#FF43A047`）带自定义"✕"、正文为 `Message_NoDiffFormat`（如"左[...] - 右[...] = 没有区别"）。**关闭 = 点右上角"✕"**（`CloseButton_Click`：仅关弹窗、不关对比窗口；ESC 等效）；红色"退出"按钮是 `IsDefault`（回车触发）会连对比窗口一起关，脚本注意区分。
   - **重启确认 MessageBox**：切换多语言后由 `App.UpdateResourceCulture` 弹出（`Message_Reboot`：en "ExcelDiff will close to change the language." / zh "ExcelDiff将关闭以变更语言"）。**处理 = 点"确定/OK"**；确认后应用关对比窗口，下次 diff 命令以新语言重建。
   - 两者均为强制模态，会阻断后续命令；脚本需先探测（窗口/文案特征）再处理，否则测试挂起。
9. **headless diff harness（L1 主测试工具）**：`DiffHarness\` 零第三方离线对比，直接调库层（`ExcelWorkbook.Create` → `ExcelSheet.Diff` → `CreateSummary`）输出确定性 diff 文本，以 EME（基准）为准、EM（保底）作验证对照。用法：`powershell -ExecutionPolicy Bypass -File DiffHarness\run_diff_compare.ps1 -RelPath Config/Data/Level.xlsx`（自动提取 HEAD → 构建/运行双变体 → 比对，忽略 READER 行）；可用 `-NoBuild` 跳过重编译。产出 `DiffHarness.exe`（NPOI）/ `DiffHarnessEDR.exe`（EDR），输出 UTF-8。**配置对齐**：harness 默认读取配置 = GUI 默认 `ApplicationSetting`（4 项 trim 均 false）；复现 GUI 场景必须传一致参数——`--skip-first-blank-rows/columns`、`--trim-last-blank-rows/columns`（对应 `Setting.SkipFirstBlankRows/...`）、`--src-header N`/`--dst-header N`（列头对齐）。注意 harness 只验证"两变体一致"，不验证"diff 绝对正确"（与 GUI 共用 `ExcelSheet.Diff` 引擎），真实结果用 `VerifyRead` 双读 + EM 对照。

## 8. 已知陷阱（务必遵守，全部踩过坑）

1. **UTF-8 破坏**：PowerShell 5.1 的 `Get-Content`/`Set-Content -Encoding UTF8` 按 ANSI 读写，破坏含中文的 YAML/JSON → 解析崩溃。改写非 ASCII 文件必须用文件写入工具（UTF-8 无 BOM）或 `[System.IO.File]::WriteAllText` + 显式 UTF8。
2. **MSBuild 增量互删**：不能在同一条命令里连续构建两个变体——增量构建会把另一变体的 exe 当过期输出清掉。必须分步（EM 与 EME 分开 build/部署）。
3. **`-Wait` 挂起**：对转发进程 `Start-Process -Wait` 会挂起（无常驻进程时转发器变常驻永不退出）。
   - **检测**：`verify.ps1` 已内置坑扫描——任一入库 `*.ps1`（注释除外）出现 `Start-Process ... -Wait ... ExcelDiff` 即门禁失败（verify.ps1 自身排除）。
   - **预防**：需要等待 diff 会话完成时用根目录 `Invoke-ExcelDiffDiff.ps1`（fire-and-forget 启动 + 轮询主窗口出现/关闭，绝不 `-Wait` 等进程退出）；禁止手工对转发进程 `-Wait`。
4. **IPC 不得阻塞**：管道线程只能用 `Dispatcher.BeginInvoke` 投递，绝不能同步等待模态框，否则模态框存在时死锁。
5. **`bin`/`obj`/`Build` 均 gitignore**：构建产物不入库，改代码后构建不污染 git 状态。`backup_installed_*` 是部署前快照，勿动。

## 9. 当前工作区状态（并行开发须知）

当前分支 `master`。**此前未提交的 WIP（常驻 + 本地化 + EDR 特性集）已拆成两个基线提交**：
`12ac86d`（代码基线：EDR 双读变体 / 单实例 IPC / 托盘 / 窗口持久化 / 外置 JSON 本地化 / NetDiff.TestRunner）、`9fa3d8d`（工程文档 + verify.ps1）。
新开分支/功能请基于 `master` 最新提交，改动前仍先 `git status`/`git log --oneline -5` 确认基线。

WIP 特性集涉及的文件（现已入库）：
- **单实例 + IPC + 托盘常驻**：`App.xaml.cs`、`SingleInstance.cs`、`TrayIconManager.cs`、`StartupHelper.cs`
- **外置 JSON 本地化（中文）**：`Localization/`、`LocalizationManager.cs`、`lang/`、`Resources*.resx`、`GenerateLangJson.ps1`
- **EDR 双读变体 EME**：`ExcelWorkbook.cs`、`ExcelSheet.cs`、`ExcelReader.cs`、`ExcelUtility.cs`、`ExcelSheetDiff.cs`、`ExcelDiff.csproj`、`packages.config`（+ExcelDataReader 3.9.0）
- **窗口状态持久化 / 无差异窗口 / 计时**：`ApplicationSetting.cs`、`MainWindow.xaml(.cs)`、`NoDiffWindow.xaml(.cs)`、`Timing.cs`、`DiffGridModel.cs`、`DiffView.xaml.cs`、`FastGridControl_Render.cs`

## 10. 编码规范（沿用既有代码）

- .NET Framework 4.6.2，C# 老式写法（无 nullable reference、无 target-typed new、无文件级 namespace；`using` 顶部、`{}` 内部成对）。
- 命名空间 = 目录名（`ExcelDiff.GUI.ViewModels`、`ExcelDiff.GUI.Settings` 等）。
- ViewModel 继承 `SerializableBindableBase`；设置类走 `Setting<T>` + `IgnoreEqualAttribute`。
- 条件编译用 `#if NPOI_READ / EDR_READ / PERF_TIMING`，不引入新第三方依赖（除非有充分理由并同步 packages.config）。
- 字符串一律走 `Resources.*`（经 `LocalizationManager` 桥接），禁止硬编码 UI 文本。
- **不主动添加代码注释**；改动遵循现有代码风格与既有模式。
