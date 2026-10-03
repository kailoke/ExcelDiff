# ARCHITECTURE（架构事实快照）

> 引用约定（本文件的编号一律按台账名读写，不在此逐条展开）：`ADR-###` = `DECISION_LOG.md` 的架构决策条目；`R-###` = `RISK_REGISTER.md` 的未关闭风险；`§N` = 本文件章节号（跨文件引用时写明文件名）。

> 本文件只写**当前有效的结构事实**（技术栈/程序集/目录/构建链/启动链/模块地图/部署布局），不含路由（路由 = `ROUTING.md`）、状态（状态 = `PROJECT_STATUS.md`）与硬约束（硬约束 = `INVARIANTS.md`）。

## 1. 项目一句话与技术栈

- 用途：Windows 桌面 GUI 差异对比工具（xls/xlsx/csv/tsv），可作 Git/Mercurial difftool。
- 技术栈：WPF（.NET Framework 4.7.2，`net472`）+ Prism 6.3 + Unity 4.0.1（容器）+ YamlDotNet + AvalonDock/Extended.Wpf.Toolkit + ExcelDataReader 3.9.0。
- **只有一套产品**：`ExcelDiffEDR.GUI`，读取层唯一实现是 ExcelDataReader；不许新增第二套读取实现或版本类条件编译（ADR-019，单一版本裁决：读取层只有一条实现，需要第二种时先开新决策条目）。程序集名 / 配置目录 / IPC channel id / 显示名一律由 exe 名派生。

## 2. 程序集与依赖方向（自研代码的组织单元）

| 项目 | 类型 | 职责 |
|---|---|---|
| `ExcelDiff` | 类库 | 工作簿/工作表/单元格读取、Diff 模型构建、CSV/TSV 自研解析 |
| `ExcelDiff.GUI` | WPF 可执行 | UI、命令入口、设置、IPC、托盘、本地化、常驻生命周期 |
| `NetDiff` | 类库 | 通用文本差异算法（类 Myers/EditGraph） |
| `FastWpfGrid` | 类库 | 高性能虚拟化网格控件 |
| `WriteableBitmapEx.Wpf` | 类库 | FastWpfGrid 依赖的位图扩展 |
| `ExcelDiff.ShellExtension` | COM 外壳扩展 | 资源管理器右键菜单入口 |
| `ExcelDiff.Installer` | WPF setup exe | 安装向导与打包（载荷 zip 内嵌 manifest resource） |

解决方案 = `ExcelDiff.sln`（VS2015 格式，`dotnet msbuild` 可构建）。依赖方向：

```
ExcelDiff.GUI ──> ExcelDiff ──> NetDiff
      │                │
      └──> FastWpfGrid ──> WriteableBitmapEx.Wpf
ExcelDiff ──> ExcelDataReader 3.9.0（唯一读取实现）
```

不在 `ExcelDiff.sln` 内的辅助工程：`NetDiff.TestRunner`（离线单测 runner）、`DiffHarness`（headless diff 输出工具）、FastWpfGrid 上游自带的三个测试工程。五个产品工程为 SDK-style（`PackageReference`，`dotnet restore` 走 `.nuget/NuGet.Config`）。

## 3. 顶层目录职责

| 目录 | 职责 |
|---|---|
| `ExcelDiff/` | 读取与差异模型类库 |
| `ExcelDiff.GUI/` | WPF 主程序（入口 `App.xaml.cs`） |
| `NetDiff/` | 差异算法 + 单测（`NetDiff.Test/Test.cs` 31 用例）+ 离线 runner |
| `FastWpfGrid/` | 虚拟化网格 + WriteableBitmapEx |
| `ExcelDiff.ShellExtension/` | COM 外壳扩展 |
| `ExcelDiff.Installer/` | setup exe 工程（`Build-Setup.ps1` 打包；文案在 `ExcelDiff.Installer/Strings/*.txt`） |
| `DiffHarness/` | headless diff 输出工具（库层直调，确定性文本） |
| `lang/` | 外置语言文件 `en-US.json` / `zh-CN.json`（由 `GenerateLangJson.ps1` 从 resx 生成，随 exe 部署） |
| `packages/refs/` | .NET Framework 4.7.2 参考程序集（构建必需；`FrameworkPathOverride` 指向此处） |
| `TestExcel/` | 本地对比样例（gitignore，只留目录） |
| `AI_docs/` | AI 生产文档唯一存放地 |
| `AI_Script/` | AI 工作流脚本唯一存放地（清单见其 `README.md`） |
| `.agents/` | 技能与命令唯一事实源（宿主目录只放薄指针） |
| `.githooks/` | git 钩子（`core.hooksPath` 指向此处） |

## 4. 构建工具链

- 本机无独立 msbuild，构建统一走 `dotnet msbuild`（SDK 版本以 `dotnet --version` 现查为准，文档不锁版本号）。`.NET Framework` 参考程序集不在 SDK 里，**必须**传 `/p:FrameworkPathOverride="<repo>\packages\refs\.NETFramework\v4.7.2"`（路径值取根目录 `ProjectPaths.ps1` 的 `$RefAssemblyPath`，脚本/文档不写盘符）。
- 手动构建前先 `dotnet restore <proj> --configfile <repo>\.nuget\NuGet.Config`（日常走 `verify.ps1` / `Deploy-And-Restart.ps1`，已内置 restore）。
- 产品构建命令全文（产物 `ExcelDiffEDR.GUI.exe`）：

```
dotnet msbuild ExcelDiff.GUI/ExcelDiff.GUI.csproj /p:Configuration=Release /p:FrameworkPathOverride="<refs>" /p:IncludePackageReferencesDuringMarkupCompilation=false /p:GenerateResourceMSBuildArchitecture=CurrentArchitecture /p:GenerateResourceMSBuildRuntime=CurrentRuntime /t:Build /v:m /nologo
```

- GUI 构建依赖 `ExcelDiff.GUI.csproj` 内的 `EnsureNetStandardForMarkupCompile` 目标与 `AppendTargetFrameworkToOutputPath=false`（输出保持扁平 `bin\Release\`，兼容部署脚本）。
- 编译开关矩阵只有一个：`EnablePerfTiming=true` → 定义 `PERF_TIMING`（分段计时，`ExcelDiff.GUI/Timing.cs`）。**不许新增别的条件编译**，尤其不许按读取实现分版本（ADR-019）。
- **会话约定（固化）**：用户口述"构建" = 执行整条"构建 → 部署 → 重启"流程，走 `AI_Script/Deploy-And-Restart.ps1`（常驻进程锁着部署目录里的 exe，仅本地编译不会让运行中的进程拿到新二进制）。
- `ExcelDiff.ShellExtension` 当前 `SignAssembly=false`，可由 `dotnet msbuild` 构建；正式分发前需 Authenticode 签署 setup exe 与扩展 DLL。

## 5. 启动链与常驻生命周期

1. `App.Main`：加载设置 → `EnsureCulture` → `UpdateResourceCulture` → `Run`。
2. `OnStartup`：`SingleInstance.TryAcquire()`（Mutex）失败 → 把参数经命名管道转发给常驻进程 → 立即退出（转发进程不驻留）。
3. 首个实例成为常驻：启动 IPC server + 托盘（`TrayIconManager`）；`--startup`（登录自启）→ 仅驻留托盘。
4. 远程命令：管道线程 → `Dispatcher.BeginInvoke` 回 UI 线程 → `DismissModalWindows()`（强关无差异等模态）→ `ShowMainWindow`（保留最大化状态）→ `RouteCommand`（已有对比窗口走 `ApplyDiff`，否则新建 `DiffCommand`）。
5. 关窗语义：`RunInBackground=true` → 隐藏到托盘；语言切换 → `CloseMainWindowForLanguageChange()` 真正关窗，下一条 diff 命令以新语言重建；`ExitApplication` → 退出。
6. 常驻的**完整性级别必须与交互桌面一致**（不一致则桌面 difftool 连不上命名管道、托盘无响应——UIPI 拦截）。口径是"同级"而非"非提权"：UAC 关闭的机器上 explorer 与终端全是 High，从提权终端拉起反而是正确的。`Deploy-And-Restart.ps1` 拉起后实测常驻与 `explorer` 的完整性 SID，不一致即判失败。

## 6. 核心模块地图与两条关键调用链

### 6.1 ExcelDiff.GUI

| 模块 | 关键文件 | 职责一句话 |
|---|---|---|
| 入口/生命周期 | `ExcelDiff.GUI/App.xaml.cs` | ShutdownMode、单实例判断、托盘、远程命令路由、`DisplayName` 常量 `ExcelDiffEDR` |
| 命令层 | `ExcelDiff.GUI/Commands/` | `CommandFactory`→`DiffCommand`；`CommandLineArguments.Normalize` 在解析前把裸位置参数归一成 `-s`/`-d`（ADR-015，CLI 归一化裁决：两条入口过同一函数）；`CommandLineOption` 承载 CLI 参数 |
| 单实例/IPC | `ExcelDiff.GUI/SingleInstance.cs` | 命名管道 server/client；channel id 由 exe 名派生；管道线程非阻塞 |
| 托盘 | `ExcelDiff.GUI/TrayIconManager.cs` | 常驻托盘：显示/隐藏/退出 |
| 自启 | `ExcelDiff.GUI/StartupHelper.cs` | HKCU Run 键按 exe 名单槽位管理 |
| 设置 | `ExcelDiff.GUI/Settings/ApplicationSetting.cs` | YamlDotNet → `%APPDATA%\ExcelDiffEDR.GUI\ExcelDiffEDR.GUI.yml`，写入走"临时文件 + File.Replace"原子路径 |
| 本地化 | `ExcelDiff.GUI/Localization/LocalizationManager.cs` | 外置 `lang\<culture>.json` 优先、缺键回落 resx；`Resources.Designer.cs` 桥接 |
| 视图 | `ExcelDiff.GUI/Views/` | `MainWindow`（PowerShell 宿主 + ESC 的 Win32 钩子）、`DiffView`（对比网格核心）、`NoDiffWindow`、`ProgressWindow`、设置系列窗口 |
| 模型 | `ExcelDiff.GUI/Models/DiffGridModel.cs` | 行状态预计算（三个 HashSet）、minimap 轻量路径；`ColumnCount` 决定网格列数 |
| 事件 | `ExcelDiff.GUI/Views/DiffViewEvent/` | 事件分发器（进程级静态单例）/监听器/处理器 |
| 配色 | `ExcelDiff.GUI/Styles/EMColor.cs` | 差异单元格配色 |
| 计时 | `ExcelDiff.GUI/Timing.cs` | `#if PERF_TIMING` 分段计时 |

### 6.2 ExcelDiff（读取 + 差异模型）

| 模块 | 职责一句话 |
|---|---|
| `ExcelWorkbook` | 入口工厂：按扩展名分发（csv/tsv 走 `CsvReader`/`TsvReader` 自研解析器，其余 = ExcelDataReader 唯一实现）；读取跳整空行、裁尾空单元格（diff 行列对齐建立在这两条上）；`GetSheetNames` 对 xlsx 走 zip 直读 `xl/workbook.xml`，与 `Create` 同源 |
| `ExcelSheet` | 按 sheet 构建行集合；`Diff(src,dst,config)`：列对齐 → 行匹配（NetDiff）→ 单元格级比对 |
| `ExcelSheetDiff` | 差异结果容器（`Rows` 有序字典）+ `CreateSummary` 计数 |
| `ExcelUtility` | 工作簿类型判定；`CreateWorkbook` 手写 OOXML 五部件生成空工作簿（差异一侧文件缺失时用，零第三方依赖，ADR-019） |

### 6.3 NetDiff 与 FastWpfGrid

- `NetDiff/NetDiff/EditGraph.cs`：类 Myers 算法核心；`DiffUtil` 提供入口与排序策略；31 个 MSTest 用例在 `NetDiff/NetDiff.Test/Test.cs`，本机用 `NetDiff.TestRunner`（MSTest shim + 反射，零第三方依赖）运行。
- `FastWpfGrid/FastWpfGrid/FastGridControl_Render.cs`：虚拟化渲染，百 MB 级工作簿可用的前提；对比视图的单元格高亮（EMColor 配色）依赖它。

### 6.4 两条关键调用链

链路 A（启动 / difftool → Diff 管道，UI 线程为主）：

```
exe <src> <dst>  →  App.OnStartup（TryAcquire 失败即转发退出）
  → SingleInstance.StartServer + TrayIconManager + StartupHelper
  → CommandFactory.Create（Normalize → 解析）→ DiffCommand.Execute
  → DiffView：ReadWorkbooks（Task.Run×2 并行 → ExcelWorkbook.Create）
  → ExecuteDiff（ProgressWindow 模态 → ExcelSheet.Diff）
  → DiffGridModel → FastWpfGrid 渲染；无差异且 NotifyEqual → NoDiffWindow
```

链路 B（IPC 远程命令，常驻收到第二次启动）：

```
新进程 → TryAcquire()==false → SendToRunningInstance（命名管道，channel=exe 名）
  → 常驻 ServerLoop 收包 → App.OnRemoteCommand
  → Dispatcher.BeginInvoke → DismissModalWindows → ShowMainWindow → RouteCommand
```

线程模型：UI 线程承载全部 WPF 与 Diff 管道；管道后台线程只收包后 `BeginInvoke` 投递（禁同步等待模态框）；读取层 `Task.Run` 并行、结果回 UI 线程组装。

## 7. 部署布局与两条链路

```
<ProjectPaths.ps1 的 $EdrDeployPath>     → 本地覆盖式部署目录（Deploy-And-Restart.ps1 目标）
%ProgramFiles%\ExcelDiffEDRTool          → setup 默认安装目录（目录名与 ProjectPaths.ps1 同源）
%APPDATA%\ExcelDiffEDR.GUI\              → 用户配置目录（由程序集名派生）
HKLM\SOFTWARE\ExcelDiffEDR               → 安装身份（InstallFolder/SetupCulture/SetupStartOnBoot 等种子）
HKLM\...\Uninstall\ExcelDiffEDR          → ARP 条目（DisplayName/DisplayVersion/UninstallString）
```

- **两条链路各自决定自己的目录，不需要对齐**：`Deploy-And-Restart.ps1` 复制的是仓库 `bin\Release`（目录里没有 `Uninstall.exe`、没有安装身份）；setup 载荷由 `ExcelDiff.Installer/Build-Setup.ps1` 隔离构建进 `ExcelDiff.Installer/obj/stage` 后打成 zip 内嵌（E7，载荷隔离断言：不得含 `.pdb`/NPOI 系/SharpZipLib/BouncyCastle/srm.exe，断言打在成品字节上）。本机 `$ProgramFilesBasePath` ≠ `%ProgramFiles%` 时两处目录不同是预期行为。
- setup exe（ADR-017，自研 WPF 安装器决策：MSI/WiX 因"向导首步选语言"物理不可实现而整体删除）五页向导：语言 → 位置与组件 → 确认 → 进度 → 完成；文案在 `ExcelDiff.Installer/Strings/zh-CN.txt` 与 `en-US.txt`（键集与占位符必须一致，`verify-installer.ps1` 比对）。安装器侧口径详见 `INVARIANTS.md` E 区（安装链硬约束）。
- `lang\*.json` 部署坑：部署脚本若对已存在目标 `lang` 目录做 `-Recurse` 复制会嵌套成 `lang\lang`，`Deploy-And-Restart.ps1` 已改为复制前先删目标 `lang` 目录。
- 部署/重启的完整流程、提权方式与完整性级别实测 = `AI_Script/Deploy-And-Restart.ps1`（头注释）与 `.agents/skills/exceldiff-workflow/SKILL.md`（本工程操作规范通道）。

## 8. 测试与验证口径

- **一键验收门禁**：`AI_Script/verify.ps1`（构建产品 + NetDiff 31 用例 + lang↔resx 双向同步 + resx 键集对齐 + `-Wait` 坑扫描 + XAML 硬编码文本扫描 + WIP 快照）。任何改动完成后必须全绿。
- **范围/锚点/文档门禁**：`AI_Script/verify-scope.ps1`（SCOPE + ANCHORS + LINT；`-Compile` 追加 verify.ps1 全量）。
- **安装包发布门禁**：`AI_Script/verify-installer.ps1`（静态检查恒跑；`-Install` 追加 A–Q 真实安装/卸载/重装/回滚用例，需管理员）。
- **部署冒烟**：`Deploy-And-Restart.ps1` 后跑 `EXECUTION_PLAN.md` §7 运行时验收清单（`AI_Script/Invoke-ExcelDiff.ps1` 安全拉起对比窗口）。
- **算法回归**：改 `NetDiff/NetDiff/EditGraph.cs` / `DiffUtil.cs` 后必须过 31 用例；输出回归用 `DiffHarness`（确定性文本，同一对入参跨版本比对）。
- **对比测试数据源**：外部 xlsx 数据仓，路径出自 `ProjectPaths.ps1` 的 `$TestDataRepoPath`（环境变量 `EXCELDIFF_TESTDATA_REPO` 可覆盖）。**严格规则：只用同名文件的工作区版 VS git HEAD 版对比**（HEAD 版用 `git show` 提取），严禁拿两个不同文件对比；制造差异前先征得用户同意。

## 9. 本地化管线

- 字符串改动进 `ExcelDiff.GUI/Properties/Resources.resx`（en-US 中性）+ `Resources.zh-CN.resx`，**两份 resx 都只是编写源**（不编译进程序）；运行时文本 = `lang\*.json`，改完必须跑根目录 `GenerateLangJson.ps1` 再生成（键取并集，加键必须两边同时加）。
- 语言解析顺序：用户显式选择 > HKLM `SetupCulture` 种子 > 系统显示语言 > zh-CN（`ApplicationSetting.EnsureCulture`）；`{x:Static Resources.*}` 在 XAML 加载时固化 → 语言切换通过关窗 + 下次命令重建生效（ADR-005，语言切换关窗重建裁决）。
