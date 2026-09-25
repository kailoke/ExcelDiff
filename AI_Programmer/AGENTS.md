# AGENTS.md — 工程操作手册（AI 代理 / 开发者入口）

> **开始任何工作前先读本文 + `ARCHITECTURE.md`**。本文是操作手册（怎么构建、怎么改、有什么坑），
> `ARCHITECTURE.md` 是工程蓝图（结构、数据流、生命周期、设计约束）。两者互补，改动代码前都要过一遍。
> 本文件刻意保持精简，深水区一律指向 ARCHITECTURE.md 相应章节。

## 0. 会话开工清单（快速上手）

> 开工前按序执行；详细说明见对应章节。

1. 在**仓库根目录**工作（不假设盘符；先 `git rev-parse --show-toplevel` 确认）。先读本文件（会指引 ARCHITECTURE.md / CODEX.md / INVARIANTS.md / ADR.md）。
2. **路径配置**：所有机器相关/仓库派生路径集中在根目录 `ProjectPaths.ps1`（唯一来源）。自查解析结果：`powershell -ExecutionPolicy Bypass -File ProjectPaths.ps1 -Print`。换机器或换盘符只改这一个文件（或用其中的环境变量覆盖）。
3. **版本状态**：读 `PROJECT_STATE.md` 获取当前分支 / HEAD / 最近提交（单一事实源，由 `AI_Script\refresh_state.ps1` 生成，勿手改）；仍 `git status` / `git log --oneline -3` 自确认。
4. **验收**：改完跑 `powershell -ExecutionPolicy Bypass -File AI_Script\verify.ps1` 必须全绿（EDR 主版本编译 + NetDiff 31 用例 + lang↔resx 同步 + 坑扫描）；动 IPC/生命周期/读取层先核对 `INVARIANTS.md`。EDN（NPOI）为保留保底代码、不参与日常门禁（如需 EDN/EDR 对照，可手工跑 `DiffHarness\run_diff_compare.ps1`）。
5. **提交**：AI 不直接 commit；改动完成后给出 Commit subject/description 供审查，由用户决定是否提交（§7.10）。
6. **约束**：遵循 §10 编码规范；不主动加注释（核心/易错/算法处除外）；UI 文本走 Resources.*；不动 backup_installed_*。
7. **部署**：提权写 Program Files 用 `Start-Process -Verb RunAs`（**不带 -Wait**）+ 轮询日志 DONE（ADR-011）；每次部署后立即重启常驻（--startup）。

> 本文所有命令都以仓库根为工作目录、一律使用仓库相对路径。需要绝对路径处（如 `FrameworkPathOverride`）用 `<repo>` 占位，实际值取 `ProjectPaths.ps1` 的解析结果。

## 1. 项目一句话

ExcelDiff：Windows 桌面 GUI 差异对比工具（xls/xlsx/csv/tsv），可作 Git/Mercurial difftool。
WPF (.NET Framework 4.6.2) + Prism 6.3 + Unity 4.0.1 + YamlDotNet + AvalonDock。
同一份源码可编译出**两套产品**，其中 **EDR（ExcelDataReader 读取，读取效率约 +72%）** 为**主版本**——唯一的构建 / 部署 / 门禁目标；**EDN（NPOI 读取）** 代码保留作保底对照（语义最全、EDR 盲区兜底），但**退出日常门禁 / 构建 / 部署 / 重启流程**。进程/程序集/配置/显示名全隔离。

## 2. 必读文档

> 以下文档统一放在 `AI_Programmer\` 目录（本文件也在其中）；根目录 `AGENTS.md` 仅作跳转指针。
> 命令中的仓库相对路径（如 `AI_Script\verify.ps1`、`ExcelDiff.GUI\...`）以**仓库根**为工作目录；机器相关绝对路径一律出自 `ProjectPaths.ps1`，不写在脚本或文档里。

| 文档 | 作用 |
|------|------|
| `ARCHITECTURE.md` | 工程蓝图：解决方案结构、编译矩阵、模块职责、Diff 数据流、生命周期、部署布局、回归方法 |
| `AGENTS.md`（本文） | 操作手册：已验证命令、编码规范、方法论、陷阱、项目状态 |
| `CODEX.md` | 代码级索引：核心类公开方法、两条关键调用链、线程模型（类级导航） |
| `INVARIANTS.md` | 工程硬约束清单（改动前逐条核对，违反=阻断提交） |
| `ADR.md` | 架构决策记录（关键决策的 why，避免重开争论） |
| `PROJECT_STATE.md` | **项目与 git 版本状态单一事实源**（分支/HEAD/最近提交；由 `AI_Script\refresh_state.ps1` 生成，勿手改） |
| `ProjectPaths.ps1` | **路径单一事实源**（Program Files 基目录、安装目录名/部署目录、外部测试数据仓、refs/NuGet.Config/WiX manifest/csc）；脚本 dot-source 它，`-Print` 自查 |
| `AI_Script\refresh_state.ps1` | 刷新 `PROJECT_STATE.md` 的脚本 |
| `AI_Script\refresh_codex.ps1` | 校准 `CODEX.md` 关键符号行号的脚本 |
| `AI_Script\verify.ps1` | 一键验证门禁：构建 EDR 主版本 + NetDiff 单测 + lang↔resx 同步 + WIP 快照 |
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
  SingleInstance.cs              #   命名管道 server/client（channel id 由 exe 名派生，EDN/EDR 互不干扰）
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
DiffHarness\                     # headless diff 对比工具（库层直调，EDN/EDR 输出对比，见 §7.9）
FastWpfGrid\                     # 高性能虚拟化网格控件 + WriteableBitmapEx 位图扩展
ExcelDiff.ShellExtension\       # COM 外壳扩展（资源管理器右键菜单）
ExcelDiff.Installer\            # MSI 打包（WiX v4，见 §4；旧 vdproj 已废弃不参与构建）
lang\                            # 外置语言文件 en-US.json / zh-CN.json（UTF-8，随 exe 目录部署）
packages\refs\                   # .NET Framework 参考程序集（构建必需，见 §4）
backup_installed_*/              # 部署前快照，勿动
Build\Release\                   # WriteableBitmapEx 产物（gitignore）
AI_Script\                       # AI 工作流脚本（见 §2）：verify.ps1 验收门禁 / Deploy-And-Restart.ps1 部署重启 / Invoke-ExcelDiff.ps1 安全启动 / refresh_state.ps1 状态刷新 / refresh_codex.ps1 行号校准
.githooks\                       # git 钩子（core.hooksPath=.githooks）：pre-commit 提交前刷新并并入本次提交 / post-checkout、post-merge 后刷新 + 条件校准 CODEX.md
GenerateLangJson.ps1             # resx → lang\*.json 生成脚本
ProjectPaths.ps1                 # 路径单一事实源（机器相关值 + 仓库派生路径），工作流脚本 dot-source 它
README.md / README.en            # 用户文档（中/英）；media\ 截图；LICENSE（MIT，含 Kailoke 版权）
AI_Programmer\                    # AI 上下文（见 §2）：AGENTS/ARCHITECTURE/CODEX/INVARIANTS/ADR/PROJECT_STATE
```

依赖关系：`GUI → ExcelDiff → NetDiff`；`GUI → FastWpfGrid → WriteableBitmapEx.Wpf`。

## 4. 构建工具链

- 本机仅有 `dotnet SDK 8.0`（`dotnet` 已在 PATH，用 `Get-Command dotnet` 确认），**没有独立 msbuild**，用 `dotnet msbuild`。
- `<repo>` = 仓库根目录绝对路径（`git rev-parse --show-toplevel`），在文档命令里作占位；脚本内一律取 `ProjectPaths.ps1` 的 `$RepoRootPath` / `$RefAssemblyPath`，不写盘符。
- 关键：.NET Framework 参考程序集不在本机 SDK 里，**必须**传 `/p:FrameworkPathOverride="<repo>\packages\refs\.NETFramework\v4.7.2"`（旧属性名 `TargetFrameworkRootPath` 已弃用）。三个 csproj 现为 SDK-style（`<Project Sdk="Microsoft.NET.Sdk">`），依赖走 `PackageReference`（原 `packages.config` 已删除，`dotnet restore` 还原）。GUI 构建还依赖 `ExcelDiff.GUI.csproj` 内的 `EnsureNetStandardForMarkupCompile` 目标（net472 标记编译器需 `netstandard` 桥接程序集）与 `AppendTargetFrameworkToOutputPath=false`（输出保持扁平 `bin\Release\`，兼容部署脚本）。

- `ExcelDiff.ShellExtension` 当前 `SignAssembly=false`，可由 `dotnet msbuild` 构建；旧 PFX 不参与现行构建。强名称与发布用 Authenticode 是两件事，MSI 脚本会对未签名成品给出警告，正式分发前仍需使用可信代码签名证书签署 MSI/EXE/ShellExtension。
- 下列命令均已在本机验证可编译（Release, AnyCPU）。SDK-style 依赖走 `PackageReference`，**手动 `dotnet msbuild` 前需先 `dotnet restore <proj> --configfile <repo>\.nuget\NuGet.Config`**（日常走 `verify.ps1` / `Deploy-And-Restart.ps1` 已内置 restore）。

### EDR（主版本，ExcelDataReader 读取）— 产物 `ExcelDiffEDR.GUI.exe`

```
dotnet msbuild ExcelDiff.GUI/ExcelDiff.GUI.csproj /p:Configuration=Release /p:EdrRead=true /p:FrameworkPathOverride="<repo>\packages\refs\.NETFramework\v4.7.2" /p:IncludePackageReferencesDuringMarkupCompilation=false /p:GenerateResourceMSBuildArchitecture=CurrentArchitecture /p:GenerateResourceMSBuildRuntime=CurrentRuntime /t:Build /v:m /nologo
```

> **会话约定（固化）**：用户在本会话中说"构建"时，**即执行整条"构建 → 部署 → 重启"流程**，而非仅本地编译。直接用固化脚本 `AI_Script\Deploy-And-Restart.ps1`（内部已串联构建 EDR + 部署 + 按“与桌面同一完整性级别”拉起常驻并实测校验，且仅对复制步骤自提权、父进程轮询日志；见 §7.6）。原因：常驻进程从部署目录（`ProjectPaths.ps1` 的 `$EdrDeployPath`）启动并锁住 exe，仅本地 `dotnet msbuild` 不会让运行中的进程拿到新二进制——必须部署覆盖后再重启才生效。验证/排查前的纯本地编译可用上面的 `dotnet msbuild` 命令，但用户口述"构建"一律走脚本全流程。

### EDN（保底版，NPOI 读取，代码保留 / 不参与日常构建）— 产物 `ExcelDiff.GUI.exe`

同上，去掉 `/p:EdrRead=true`（默认）。仅在需要 EDN 保底对照验证时手工构建。

### 只构建核心库（快速验证读取层改动）

```
dotnet msbuild ExcelDiff/ExcelDiff.csproj /p:Configuration=Release /p:FrameworkPathOverride="<repo>\packages\refs\.NETFramework\v4.7.2" /t:Build /v:m /nologo
```

### NetDiff 单测（离线 runner，零第三方依赖）

本机无 VS/vstest，MSTest 程序集不在 `packages\refs`；`NetDiff.TestRunner` 用自带 MSTest shim + 反射执行 `NetDiff.Test\Test.cs` 的 31 个用例。

```
dotnet msbuild NetDiff/NetDiff.TestRunner/NetDiff.TestRunner.csproj /p:Configuration=Release /p:FrameworkPathOverride="<repo>\packages\refs\.NETFramework\v4.7.2" /t:Build /v:m /nologo
& "NetDiff\NetDiff.TestRunner\bin\Release\NetDiff.TestRunner.exe"
```

### MSI 安装包（WiX v4）

本机无 VS/InstallShield/WiX v3，旧 `ExcelDiff.Installer.vdproj`（需 VS + Installer Projects 扩展）已废弃。改用仓库 `.config\dotnet-tools.json` 固定的 **WiX Toolset 4.0.6**，脚本自动 `dotnet tool restore`，纯 CLI 产出标准 MSI。

```
powershell -ExecutionPolicy Bypass -File ExcelDiff.Installer\Build-Installer.ps1            # 构建 EDR + ShellExtension → ExcelDiff.Installer\Release\ExcelDiffEDRSetup.msi
powershell -ExecutionPolicy Bypass -File ExcelDiff.Installer\Build-Installer.ps1 -SkipBuild  # 跳过 msbuild，复用 obj\stage 的上次隔离构建
powershell -ExecutionPolicy Bypass -File ExcelDiff.Installer\Build-Installer.ps1 -Version 2.0.0   # 显式 -Version 仅在前三段与主 EXE FileVersion 一致时才通过校验
powershell -ExecutionPolicy Bypass -File ExcelDiff.Installer\Build-Installer.ps1 -SkipValidation # 仅受限本地环境；该产物不得发布
powershell -ExecutionPolicy Bypass -File ExcelDiff.Installer\Build-Installer.ps1 -SkipBuild -Wizard # 带安装向导 UI 的包（见下方向导条目）
```

- 脚本内部：清理并构建 EDR GUI + ShellExtension 到专用 `ExcelDiff.Installer\obj\stage\{app,shell}` → **用 `csc.exe` 和 staged `SharpShell.dll` 编译 `SrmRegistrar\SrmRegistrar.cs`**（替代与 SharpShell 2.7.2 不匹配的旧 srm.exe 2.2.0.0）→ 只枚举 staging app 文件并按相对路径排序 → 生成 `AppFiles.generated.wxs`（组件 GUID 按规范化相对路径稳定派生，ID 带哈希防碰撞，该文件 gitignore）→ 仓库固定的 WiX 4.0.6 `build -arch x64` → `wix msi validate`。
- 静态源 `ExcelDiffEDR.Installer.wxs`：包定义（Name=ExcelDiffEDR、Manufacturer=skanmera、UpgradeCode、Scope=perMachine、装到 `[ProgramFiles64Folder]$(var.InstallDirName)`，目录名出自 `ProjectPaths.ps1`）、.NET Framework 4.7.2 启动条件（`RegistrySearch Type=raw` 返回 `#十六进制`，条件必须与 `&quot;#461808&quot;` 比较）、ShellExtension COM 注册（deferred + Impersonate=no）及成对 rollback 动作、`MajorUpgrade Schedule=afterInstallInitialize`、安装目录记忆、开始菜单快捷方式、产品图标。
- **版本规则**：默认从 staged `ExcelDiffEDR.GUI.exe` 的 FileVersion 派生 MSI 三段版本；显式 `-Version` 的前三段必须与主 EXE 一致。Windows Installer 升级不依赖第四段 revision，发新版必须提升前三段之一。ProductCode 由 `UpgradeCode + MSI 三段版本` 稳定派生：同版本重建保持相同 ProductCode，新版本自动变化。**升版只动产品自有三件**（`ExcelDiff.GUI` / `ExcelDiff` / `ExcelDiff.ShellExtension`），vendored 上游库（FastWpfGrid / NetDiff / NetDiff.Test）与 `NetDiff.nuspec` 的 `Diff4Net` 版本保持自身口径（INVARIANT E12 / ADR-014）。
- EDR 仍需随包携带 NPOI 及其依赖：虽然读取主路径是 EDR，但 `ExcelUtility.CreateWorkbook/GetWorkbookTypeStrict` 仍使用 NPOI；未替换这些功能前不得从 MSI 强行排除 NPOI。
- 未打包 `open_readme.vbs`。默认包**无安装向导 UI**（双击即按默认目录静默装完）。
- **安装向导：框架已通，步骤待设计**。`-Wizard` 启用 `WixToolset.UI.wixext` 的 `WixUI_InstallDir`——`ExcelDiffEDR.Installer.wxs` 里该元素被 `<?if $(var.EnableWizard) = "yes" ?>` 包住，打包脚本注入 `-d EnableWizard=yes|no` 并仅在 `-Wizard` 时传 `-ext`（所以默认构建不依赖网络）。实测 `-SkipBuild -Wizard`：构建通过、`wix msi validate` 通过，包内出现 `WelcomeDlg`/`InstallDirDlg`/`VerifyReadyDlg`/`ProgressDlg`/`MaintenanceTypeDlg`，体积 5,398,528 → 5,697,536 字节。**这套对话框只是占位验证**：页面清单与顺序、要不要 EULA 页、是否暴露修复/卸载入口、横幅与对话框图片、中英双语文案、默认目录取 `[ProgramFiles64Folder]` 还是 `ProjectPaths.ps1` 的 `$EdrDeployPath`，都必须先出设计再定稿。
- **WiX 扩展版本必须与 wix 主工具一致**：`wix extension add WixToolset.UI.wixext`（不带版本）会拉 NuGet 最新版，实测装成 7.0.0 后 `extension list` 标 `damaged`、4.0.6 的 CLI 用不了；且 `wix extension remove <id>/<ver>` 会按包名把该包所有版本一起删掉。脚本因此从 `.config\dotnet-tools.json` 读钉住的 wix 版本，拼 `WixToolset.UI.wixext/<version>` 安装，并以 `extension list` 的实际条目（而非 `add` 的退出码——重复添加时它非 0 且无输出）判定可用性。扩展装在用户目录、不入库 → 新机器首次 `-Wizard` 需联网。
- **INSTALLFOLDER 可被命令行覆盖并跨 major upgrade 记忆**：`msiexec /i x.msi INSTALLFOLDER="<绝对目录>"`；安装值持久化到 HKLM，升级 AppSearch 在目录定价前恢复（显式命令行值优先）。
- **默认安装目录名 = `ProjectPaths.ps1` 的 `$EdrInstallDirName`**（打包时经 `-d InstallDirName=` 注入 `ExcelDiffEDR.Installer.wxs`），与 `Deploy-And-Restart.ps1` **只有目录名同源**；基目录不同源（MSI 走 WiX 的 `[ProgramFiles64Folder]` = 本机 Program Files，脚本走 `$ProgramFilesBasePath`），两者不一致时会落成两个目录（本机即如此，用户已裁定“读工程配置文件、无需在意”）。
- `wix msi validate` 是发布硬门禁；`-SkipValidation` 只允许生成本地诊断包。脚本会警告 MSI 尚未 Authenticode 签名，正式分发必须在发布流水线签名并复验签名。
- 卸载文件删除正常（`msiexec /x` 验证通过）。若测试中出现"卸载后文件残留"，是测试时**手动删 `Classes\Installer\Products` 而未清 `UserData\S-1-5-18\{Products,Components}`** 导致组件 refcount 混乱，非 MSI 固有 bug。

### 一键验证门禁

```
powershell -ExecutionPolicy Bypass -File AI_Script\verify.ps1        # 构建 EDR 主版本 + 单测 + lang 同步 + WIP 快照
powershell -ExecutionPolicy Bypass -File AI_Script\verify.ps1 -SkipBuild   # 只查单测 + lang 同步 + WIP
```

## 5. 编译开关矩阵（双版本隔离的机制）

> **日常门禁/构建/部署只针对 EDR（`EdrRead=true`）**；EDN（默认空）代码保留作保底对照，退出日常流程。

| MSBuild 属性 | 效果（GUI 与库联动） |
|------|------|
| `EdrRead=true`（EDR 主版本） | GUI `AssemblyName=ExcelDiffEDR.GUI`、定义 `EDR_READ`、`DisplayName=ExcelDiffEDR`；库**不**定义 `NPOI_READ`（走 EDR） |
| `EdrRead`（默认空，EDN 保底，保留源码不日常构建） | GUI `AssemblyName=ExcelDiff.GUI`、`DisplayName=ExcelDiff`；库定义 `NPOI_READ`（NPOI 读取） |
| `EnablePerfTiming=true` | GUI 与库同时定义 `PERF_TIMING`，注入分段计时 |

- 配置目录天然隔离：`%APPDATA%\ExcelDiff.GUI\`（EDN） vs `%APPDATA%\ExcelDiffEDR.GUI\`（EDR）。
- 代码里 `#if NPOI_READ`（库）与 `#if EDR_READ`（GUI）分支读取/显示名。

## 6. 模块设计速查（“改什么功能 → 动哪些文件”）

| 需求 | 入口文件 | 说明 |
|------|---------|------|
| 新增文件类型解析 | `ExcelDiff/ExcelWorkbook.cs`、`CsvReader.cs`/`TsvReader.cs` | 按扩展名分发，EDR 主版本要过 |
| 差异算法调整 | `NetDiff/NetDiff/EditGraph.cs`、`DiffUtil.cs` | 行级/单元格级共用；改后跑 `NetDiff.Test` |
| 差异提取规则/日志格式 | `ExcelDiff/ExcelSheetDiff.cs`、`ExcelSheetDiffConfig.cs`、`DiffExtractionSettingWindow*` | |
| UI 字符串/本地化 | `Properties/Resources*.resx` → 跑 `GenerateLangJson.ps1` → `lang\*.json` | 见 §7 本地化流程 |
| 差异配色 | `GUI/Styles/EMColor.cs` | |
| 单元格渲染/网格性能 | `FastWpfGrid/FastWpfGrid/FastGridControl_Render.cs` | |
| 设置项新增/持久化 | `GUI/Settings/ApplicationSetting.cs` + 对应窗口/VM | YAML，注意 UTF-8 陷阱 |
| 单实例/托盘/生命周期 | `GUI/App.xaml.cs`、`SingleInstance.cs`、`TrayIconManager.cs`、`StartupHelper.cs` | 常驻进程逻辑 |

## 7. 开发方法论

1. **主版本 EDR**：任何 UI/读取/行为改动必须 EDR（`EdrRead=true`）编译通过。EDN（NPOI）代码保留作保底对照，**不在日常门禁中编译**（仅需对照验证时手工 build，见 §4）。
2. **本地化流程**：字符串改动进 `Resources.resx`（en-US 中性）+ `Resources.zh-CN.resx`（仅 zh/en 两语言，默认 zh-CN）→ 运行 `GenerateLangJson.ps1` 重新生成 `lang\*.json`（UTF-8 BOM）。`{x:Static Resources.*}` 在窗口加载时固化 → 语言切换通过 `App.CloseMainWindowForLanguageChange()` 关窗，下次 diff 命令以新语言重建。
3. **测试**：NetDiff 算法改动用 `NetDiff.TestRunner`（31 用例，命令见 §4）。GUI 层回归用手工/脚本冒烟（见 ARCHITECTURE.md §9）。任何改动完成后跑 `AI_Script\verify.ps1` 一键门禁。
4. **回归比对**：对比对象必须是**同一文件的两个版本**（git HEAD vs 工作区），严禁拿两个不同文件对比。测试数据源见 §7.7。
5. **读取层定位**：**EDR=ExcelDataReader 主版本**（读取快约 72%）；**EDN=NPOI 保底对照**（NPOI 语义最全，代码保留、不日常构建）。EDR 读不到“仅样式无值”单元格 → 列对齐漂移 → 这正是 EDN 保底代码保留的意义，**不得移除 EDN 代码**。基准测试以 EDR 为准，EDN 代码仅作保底对照验证。
6. **构建与部署次序**：只构建/部署 **EDR 主版本**（构建 EDR → 部署 EDR → 重启 EDR 常驻；EDN 保底代码不参与，见陷阱 §8.2）。**每次构建部署后必须立即重启对应常驻进程**（杀进程 → 从部署路径 `--startup` 拉起），保证新构建即时生效。原因：常驻进程从 Program Files 启动且锁住 exe——不杀进程无法覆盖部署，且旧进程仍在内存运行，测试结果会失真。**部署动作（提权写 Program Files）**：用 `Start-Process powershell -Verb RunAs`（**不带 `-Wait`**）启动提权脚本 → 轮询其日志文件出现 `DONE` → 再重启常驻（见陷阱 §8.6）。**⚠️ `Start-Process -ArgumentList` 数组拼接不会自动给含空格路径加引号**——含空格的目标路径（部署目录一般在 `...\Program Files\...` 下）必须在数组元素里**手动内嵌引号**（`"-Dst","`"<部署目录>`""`），否则会被截断（见陷阱 §8.7）。
   - **固化脚本 `AI_Script\Deploy-And-Restart.ps1`**（可人工双击 / `powershell -File` 执行，也可由临时命令调用）：自动完成“构建 EDR→部署→重启 EDR 常驻”。**约束是"常驻与交互桌面同一完整性级别"**（级别不同则桌面起的 Fork 通过命名管道连不上、托盘点不动，UIPI 拦截）——注意这是"同级"而不是"非提权"：本机 `HKLM\...\Policies\System\EnableLUA = 0`（UAC 关闭），explorer / Fork / 本脚本实测全是 High，此时从提权终端跑反而是正确的。脚本**仅对复制步骤自提权**：一律用 `Start-Process -Verb RunAs`（不带 `-Wait`；已是管理员时不再弹 UAC）拉起一个提权子进程仅做“杀进程释放锁 + 复制”，父进程轮询 `deploy_edr.log` 出现 `DONE`/`FAIL`；提权数组元素对含空格路径内嵌引号（§8.7）；杀进程按进程名 `ExcelDiffEDR.GUI`（经提权父进程启动的进程 `Path` 可能为空，须按 `Name` 而非 `Path` 匹配）；复制前删目标 `lang` 目录规避 `lang\lang` 嵌套坑（ARCHITECTURE §8）；复制后校验目标 exe 已落盘；**重启常驻由父进程 `Start-Process`（不带 `-Wait`）拉起，随后实测常驻进程与 `explorer` 的完整性 SID，不一致即判失败**（不再假设"必须非提权"）。开关：`-NoBuild`（仅部署当前 bin）、`-NoRestart`（部署后不拉起常驻）；`-Src`/`-Dst`/`-LogDir` 默认值全部来自根目录 `ProjectPaths.ps1`（仓库内 bin\Release / `$EdrDeployPath` / 仓库根），脚本内不写盘符。人工/临时命令执行范例：`powershell -ExecutionPolicy Bypass -File AI_Script\Deploy-And-Restart.ps1`。
7. **对比测试数据源**：xlsx 配置表所在的**外部 git 仓**（不属本仓库、不入库），路径出自 `ProjectPaths.ps1` 的 `$TestDataRepoPath`（可用 `EXCELDIFF_TESTDATA_REPO` 或 harness 的 `-Repo` 覆盖）。该值可以指仓根或数据子目录（现配置为数据子目录），`run_diff_compare.ps1` 会向上找 `.git` 定出仓根并把子目录拼进 `-RelPath`（**不要**解析 `git rev-parse` 的文本来拿路径：中文路径在 PS 5.1 的 GBK 控制台解码下会错位）。**严禁**在脚本里写死盘符默认值，换机器只改 `ProjectPaths.ps1`。**严格规则：只用同名文件的 Unstaged（工作区）VS HEAD 做对比**——工作区文件直接引用，HEAD 版用 `cmd /c "git -C <repo> show HEAD:<相对路径> > <tmp>"` 提取（二进制安全），禁止跨文件/跨版本组合。**若某文件两版无差异而需要制造差异时，修改工作区文件前必须先征得用户同意**；测试后可用 `git checkout -- <path>` 恢复。常用测试文件：`$TestDataRepoPath` 所指目录（现配置为数据子目录 `Data_POP`，其下 81 个 xlsx 被 git 跟踪、无 `Config/Data` 层级；默认 `-RelPath Artifact.xlsx`；实际盘符值用 `powershell -File ProjectPaths.ps1 -Print` 查，文档不写死）。旧文档里的 `Config/Data/Level.xlsx` / `PostMatchDefeat.xlsx` 属上一台机器的 baggame 仓，已不适用；当前 `Data_POP` 无未提交改动，故 HEAD 版与工作区版相同，harness 只验证 EDN/EDR 两变体输出一致。
   - **本地样例文件夹 `TestExcel/`**（仓库根目录）：本地对比用的样例 Excel/CSV/TSV 放置处，供手动拉起 Fork / 对比验证（如大表弹窗、差异驱动省内存等行为）使用。
8. **测试模态弹窗注意事项**（自动化/脚本测试会被强制阻塞）：
   - **无差异弹窗 `NoDiffWindow`**：两文件无差异且 `NotifyEqual` 开启时，由 `DiffView.ExecuteDiff` `ShowDialog` 弹出（模态）。识别：无系统标题栏（`WindowStyle=None`）、顶部绿色条（`#FF43A047`）带自定义"✕"、正文为 `Message_NoDiffFormat`（如"左[...] - 右[...] = 没有区别"）。**关闭 = 点右上角"✕"**（`CloseButton_Click`：仅关弹窗、不关对比窗口；ESC 等效）；红色"退出"按钮是 `IsDefault`（回车触发）会连对比窗口一起关，脚本注意区分。
   - **重启确认 MessageBox**：切换多语言后由 `App.UpdateResourceCulture` 弹出（`Message_Reboot`：en "ExcelDiff will close to change the language." / zh "ExcelDiff将关闭以变更语言"）。**处理 = 点"确定/OK"**；确认后应用关对比窗口，下次 diff 命令以新语言重建。
   - 两者均为强制模态，会阻断后续命令；脚本需先探测（窗口/文案特征）再处理，否则测试挂起。
9. **headless diff harness（EDN/EDR 对照诊断工具，保留、非门禁必需）**：`DiffHarness\` 零第三方离线对比，直接调库层（`ExcelWorkbook.Create` → `ExcelSheet.Diff` → `CreateSummary`）输出确定性 diff 文本，以 EDR（主版本）为准、EDN（保底）作验证对照。用法：`powershell -ExecutionPolicy Bypass -File DiffHarness\run_diff_compare.ps1 -RelPath Artifact.xlsx`（`-RelPath` 相对 `$TestDataRepoPath` 所指目录；自动提取 HEAD → 构建/运行双变体 → 比对，忽略 READER 行）；可用 `-NoBuild` 跳过重编译。产出 `DiffHarness.exe`（NPOI）/ `DiffHarnessEDR.exe`（EDR），输出 UTF-8。**配置对齐**：harness 默认读取配置 = GUI 默认 `ApplicationSetting`（4 项 trim 均 false）；复现 GUI 场景必须传一致参数——`--skip-first-blank-rows/columns`、`--trim-last-blank-rows/columns`（对应 `Setting.SkipFirstBlankRows/...`）、`--src-header N`/`--dst-header N`（列头对齐）。注意 harness 只验证"两变体一致"，不验证"diff 绝对正确"（与 GUI 共用 `ExcelSheet.Diff` 引擎），真实结果用 `VerifyRead` 双读 + EDN 对照。
10. **Git 提交准则（硬性）**：**AI 不可直接 commit**。改动完成后，说明本次改动的 **Commit subject / description**，并从版本控制角度给出提交建议；实际提交由用户决定，且用户需先审查 subject/description 再提交。

## 8. 已知陷阱（务必遵守）

1. **UTF-8 破坏**：PowerShell 5.1 的 `Get-Content`/`Set-Content -Encoding UTF8` 按 ANSI 读写，破坏含中文的 YAML/JSON → 解析崩溃。改写非 ASCII 文件必须用文件写入工具（UTF-8 无 BOM）或 `[System.IO.File]::WriteAllText` + 显式 UTF8。
   - **反向坑（.ps1 需要 BOM）**：含非 ASCII 字面量的 `.ps1` 若存成 **UTF-8 无 BOM**，PS 5.1 会按系统 ACP（本机 936/GBK）解码 → 中文路径变乱码、`Test-Path` 静默 False（实测：中文目录名被读成乱码后整条路径失效）。因此脚本里写中文路径的文件必须存 **UTF-8 带 BOM**（`ProjectPaths.ps1` 即如此）；纯 ASCII 的脚本不需要。
2. **MSBuild 增量互删**：不能在同一条命令里连续构建两个变体——增量构建会把另一变体的 exe 当过期输出清掉。仅在手工同时构建 EDR/EDN 两变体时才需分步（日常门禁只构建 EDR，无此问题）。
3. **`-Wait` 挂起**：对转发进程 `Start-Process -Wait` 会挂起（无常驻进程时转发器变常驻永不退出）。
   - **检测**：`AI_Script\verify.ps1` 已内置坑扫描——任一入库 `*.ps1`（注释除外）出现 `Start-Process ... -Wait ... ExcelDiff` 即门禁失败（verify.ps1 自身排除）。
   - **预防**：需要等待 diff 会话完成时用 `AI_Script\Invoke-ExcelDiff.ps1`（fire-and-forget 启动 + 轮询主窗口出现/关闭，绝不 `-Wait` 等进程退出）；禁止手工对转发进程 `-Wait`。
4. **IPC 不得阻塞**：管道线程只能用 `Dispatcher.BeginInvoke` 投递，绝不能同步等待模态框，否则模态框存在时死锁。
5. **`bin`/`obj`/`Build` 均 gitignore**：构建产物不入库，改代码后构建不污染 git 状态。`backup_installed_*` 是部署前快照，勿动。
6. **提权部署 `-Wait` 挂起**：`Start-Process powershell -Verb RunAs -Wait` 在 UAC 提权 + msbuild 子进程场景下**不返回**，bash 会卡到超时（部署实际 10-30 秒已完成）。预防：提权启动**不带 `-Wait`** → 轮询部署脚本写出的日志文件（出现 `DONE`）再继续，然后重启常驻。
7. **`-ArgumentList` 空格路径截断**：`Start-Process -ArgumentList` 把数组拼接成命令行字符串时**不会**自动给含空格参数加引号。给部署脚本传 `-Dst "<ProgramFilesBase>\ExcelDiffEDRTool"`（Program Files 路径必含空格）若写成普通数组元素，实际拼接为 `-Dst <ProgramFilesBase>\ExcelDiffEDRTool` → 目标在第一个空格处被截断，部署静默落到错误目录。预防：**数组元素内嵌双引号**（`"-Dst","`"$EdrDeployPath`""`），部署后核对目标 exe 的 LastWriteTime/Length 已更新再重启常驻。
8. **"常驻必须非提权"是错的口径**（2026-09-25 实测纠正）：真正的约束是**常驻与交互桌面同一完整性级别**（不同级则桌面起的 Fork 连不上命名管道、托盘无响应）。本机 `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\EnableLUA = 0`（UAC 关闭），`explorer`、`Fork`、Windows Terminal 与 agent 终端实测全是 `S-1-16-12288`（High）——此时"普通权限"根本拿不到（Task Scheduler 即使 `RunLevel=Limited` + `LogonType=InteractiveToken` 拉出来仍是 High），而同级启动本来就完全能用。更早的 `Start-Process explorer.exe "<exe>" --startup` 降级分支是**静默不拉起却照样写 DONE**（真·假成功）；随后加固的 `IsInRole(Administrator)` 一刀切版本恰好相反——复制已成功但重启步骤抛错、`deploy_all.log` 记 `FAIL`，在 UAC 关闭的机器上属于误伤。**现在的行为**：`Start-Resident` 一律由父进程拉起，再取常驻与 `explorer` 的完整性 SID 比对，不一致才告警并判失败。核对：`$env:WINDIR\System32\whoami.exe /groups | Select-String Mandatory`（必须用 System32 版，git-bash 里的 `whoami` 是 coreutils，不认 `/groups`）。

## 9. 项目状态

> **动态 git 状态（分支 / HEAD / 最近提交）以 `PROJECT_STATE.md` 为单一事实源**（`AI_Script\refresh_state.ps1` 刷新）。

- **版本定位**：EDR=ExcelDataReader 主版本（读取快约 72%）；EDN=NPOI 保底代码保留、不日常构建（见 §7.5 / ADR-012）。
- **部署目录**（EDR 主版本）= `ProjectPaths.ps1` 的 `$EdrDeployPath`（= `$ProgramFilesBasePath` + `$EdrInstallDirName`，可用 `EXCELDIFF_PROGRAM_FILES` / `EXCELDIFF_DEPLOY_DIR` 或 `-Dst` 覆盖）。实际值用 `powershell -File ProjectPaths.ps1 -Print` 查，文档/脚本不写死盘符。
- **自动刷新**：git 钩子（`.githooks\` + `core.hooksPath=.githooks`）：`pre-commit` 提交前刷新 `PROJECT_STATE.md`（本次提交触及 C# 源码时并校准 `CODEX.md`）并 `git add` 回本次提交；`post-checkout` / `post-merge` 在操作后刷新。一次性启用：`git config core.hooksPath .githooks`。
- 改动前先 `git status` / `git log --oneline -3` 确认；任何改动完成后跑 `AI_Script\verify.ps1`；动 IPC/生命周期/读取层先核对 `INVARIANTS.md`。

## 10. 编码规范（沿用既有代码）

- .NET Framework 4.6.2，C# 老式写法（无 nullable reference、无 target-typed new、无文件级 namespace；`using` 顶部、`{}` 内部成对）。
- 命名空间 = 目录名（`ExcelDiff.GUI.ViewModels`、`ExcelDiff.GUI.Settings` 等）。
- ViewModel 继承 Prism `BindableBase`；设置类走 `Setting<T>`（继承 `SerializableBindableBase`）+ `IgnoreEqualAttribute`。
- 条件编译用 `#if NPOI_READ / EDR_READ / PERF_TIMING`，不引入新第三方依赖（除非有充分理由并在 `ExcelDiff.GUI.csproj`/`ExcelDiff.csproj`/`ExcelDiff.ShellExtension.csproj` 的 `PackageReference` 中同步；原 `packages.config` 已弃用）。
- 字符串一律走 `Resources.*`（经 `LocalizationManager` 桥接），禁止硬编码 UI 文本。
- **不主动添加代码注释**；改动遵循现有代码风格与既有模式（核心算法/易错/设计动机处应保留或补充注释，见 ADR-010 对 EditGraph 的注释处理）。

## 11. 工程负责人职责（AI 会话共同遵循）

AI 会话以资深主程序视角工作，对整体工程质量负责：
1. **框架与维护**：改动前读本文 + ARCHITECTURE + CODEX + INVARIANTS + ADR；保持架构一致性，不引入与既有模式冲突的方案。
2. **代码性能**：改动后评估性能影响（diff 管道、渲染、事件、持久化）；触及 `#if` 双版本/读取层/网格渲染等热路径先核对 INVARIANTS F 区与性能项清单。
3. **测试纪律**：任何功能改动跑完整测试（`AI_Script\verify.ps1` + DiffHarness 双文件回归），见 §0 开工清单 / §4 门禁；动 IPC/生命周期/读取层先核对 INVARIANTS。
4. **指导其他会话**：本文件 + ARCHITECTURE/CODEX/INVARIANTS/ADR 即权威上下文；其他会话直接读本文件（§0 开工清单）；发现文档与代码不一致时修正文档。
5. **质量门**：不擅自提交 git（§7.10）；改动给出 commit subject/description 供审查；高危区（diff 算法、读取层、生命周期）改动需在提交说明中注明测试证据。
