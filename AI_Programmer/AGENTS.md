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
| `ProjectPaths.ps1` | **路径单一事实源**（Program Files 基目录、安装目录名/部署目录、外部测试数据仓、refs/NuGet.Config）；脚本 dot-source 它，`-Print` 自查 |
| `AI_Script\refresh_state.ps1` | 刷新 `PROJECT_STATE.md` 的脚本 |
| `AI_Script\refresh_codex.ps1` | 校准 `CODEX.md` 关键符号行号的脚本 |
| `AI_Script\verify.ps1` | 一键验证门禁：构建 EDR 主版本 + NetDiff 单测 + lang↔resx 同步 + 安装器工程编译 + WIP 快照 |
| `AI_Script\verify-installer.ps1` | 安装包发布门禁（E10）：静态检查载荷/资源/版本/双语键集与占位符/新鲜度；`-Install` 追加 A–K 共 11 个真实安装用例（失败回滚保住目录内无关文件、无目标/错路径/**清单被删**时拒绝卸载并保住文件与记录、从安装目录内运行、自启联动、`/clearsettings`、非法参数退出码 4、盘符根目标被拒），机器上留有安装记录或该 CLSID 已被占用时拒绝运行 |
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
ExcelDiff.Installer\            # setup exe 打包（自研 WPF 向导安装器，见 §4；MSI/WiX 链已删除）
lang\                            # 外置语言文件 en-US.json / zh-CN.json（UTF-8，随 exe 目录部署）
packages\refs\                   # .NET Framework 参考程序集（构建必需，见 §4）
backup_installed_*/              # 部署前快照，勿动
Build\Release\                   # WriteableBitmapEx 产物（gitignore）
AI_Script\                       # AI 工作流脚本（见 §2）：verify.ps1 验收门禁 / verify-installer.ps1 安装包门禁 / Deploy-And-Restart.ps1 部署重启 / Invoke-ExcelDiff.ps1 安全启动 / refresh_state.ps1 状态刷新 / refresh_codex.ps1 行号校准
.githooks\                       # git 钩子（core.hooksPath=.githooks）：pre-commit 刷新状态+（仅本次提交含 C# 时）校准 CODEX.md 并 add 回提交 / post-checkout 刷新状态 / post-merge 刷新状态并校准 CODEX.md / pre-push 默认拒绝推送（§7.10）
GenerateLangJson.ps1             # resx → lang\*.json 生成脚本
ProjectPaths.ps1                 # 路径单一事实源（机器相关值 + 仓库派生路径），工作流脚本 dot-source 它
README.md / README.en            # 用户文档（中/英）；media\ 截图；LICENSE（MIT，含 Kailoke 版权）
AI_Programmer\                    # AI 上下文（见 §2）：AGENTS/ARCHITECTURE/CODEX/INVARIANTS/ADR/PROJECT_STATE
```

依赖关系：`GUI → ExcelDiff → NetDiff`；`GUI → FastWpfGrid → WriteableBitmapEx.Wpf`。

## 4. 构建工具链

- 本机仅有 `dotnet SDK 8.0`（`dotnet` 已在 PATH，用 `Get-Command dotnet` 确认），**没有独立 msbuild**，用 `dotnet msbuild`。
- `<repo>` = 仓库根目录绝对路径（`git rev-parse --show-toplevel`），在文档命令里作占位；脚本内一律取 `ProjectPaths.ps1` 的 `$RepoRootPath` / `$RefAssemblyPath`，不写盘符。
- 关键：.NET Framework 参考程序集不在本机 SDK 里，**必须**传 `/p:FrameworkPathOverride="<repo>\packages\refs\.NETFramework\v4.7.2"`（旧属性名 `TargetFrameworkRootPath` 已弃用）。五个 csproj 现为 SDK-style（`<Project Sdk="Microsoft.NET.Sdk">`：`ExcelDiff`、`ExcelDiff.GUI`、`ExcelDiff.ShellExtension`、`ExcelDiff.Installer`、`DiffHarness`），依赖走 `PackageReference`（原 `packages.config` 已删除，`dotnet restore` 还原）。GUI 构建还依赖 `ExcelDiff.GUI.csproj` 内的 `EnsureNetStandardForMarkupCompile` 目标（net472 标记编译器需 `netstandard` 桥接程序集）与 `AppendTargetFrameworkToOutputPath=false`（输出保持扁平 `bin\Release\`，兼容部署脚本）。

- `ExcelDiff.ShellExtension` 当前 `SignAssembly=false`，可由 `dotnet msbuild` 构建；旧 PFX 不参与现行构建。强名称与发布用 Authenticode 是两件事，`Build-Setup.ps1` 会对未签名成品给出警告，正式分发前仍需使用可信代码签名证书签署 `ExcelDiffSetup.exe` 与 `ExcelDiff.ShellExtension.dll`（E10）。
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

### 安装程序（自研 WPF 向导 setup exe）

MSI/WiX 路线已于 2026-09-25 **整体删除**（ADR-017）：`ExcelDiffEDR.Installer.wxs`、`Build-Installer.ps1`、`SrmRegistrar/`、`ExcelDiff.Installer.vdproj`、`.config\dotnet-tools.json` 都不在了。废弃的直接原因是产品要求做不到：**MSI 的界面语言在 `msiexec` 打开库的那一刻就固定**（数据库代码页与 `String` 表都是构建期烘进去的，`.mst` 转换也在第一个对话框画出来之前选定），而 WiX 4.0.6 的 UI 扩展里没有任何语言对话框、295 个控件中**一个 ComboBox 都没有**；唯一带语言下拉的 Burn 需要本机没有、且离线取不到的 `WixToolset.BootstrapperApplications.wixext`。

```
powershell -ExecutionPolicy Bypass -File ExcelDiff.Installer\Build-Setup.ps1              # 隔离构建 EDR+ShellExtension → 载荷 zip → Release\ExcelDiffSetup-<版本>.exe
powershell -ExecutionPolicy Bypass -File ExcelDiff.Installer\Build-Setup.ps1 -SkipBuild   # 复用 obj\stage，只重打载荷与 setup exe
powershell -ExecutionPolicy Bypass -File AI_Script\verify-installer.ps1                   # 静态门禁：载荷内容/嵌入资源/版本一致/双语键集
powershell -ExecutionPolicy Bypass -File AI_Script\verify-installer.ps1 -Install          # 追加 A–K 十一个真实安装/卸载/重装/回滚/拒绝用例（需管理员）
```

- **产物是单个 exe**：`ExcelDiffSetup.exe`（net472 WPF，`app.manifest` = `requireAdministrator`）。应用载荷由脚本打成 zip，再以 manifest resource `ExcelDiff.Setup.Payload.zip` 嵌入；`.csproj` 里该 `EmbeddedResource` 带 `Condition="Exists(...)"`，所以没有载荷时工程仍能编译、运行时给明确错误——打包链不污染 `verify.ps1`。
- **向导五页**：① 语言（默认按 `CultureInfo.InstalledUICulture`，`zh*`→中文、其余英文；点选后整个向导立即换语言）② 安装位置 + 组件勾选 ③ 确认 ④ 进度（真实步骤日志，日志文件 `%TEMP%\ExcelDiff-Setup-<时间戳>.log`）⑤ 完成（用法提示）。**故意不放"立即运行"**：setup 是提权进程，它拉起的常驻是高完整性级别，桌面侧 difftool 连不上命名管道（见 §7.6 / §8.8）。
- **文案在 `ExcelDiff.Installer\Strings\{zh-CN,en-US}.txt`**（`key=value`，UTF-8 无 BOM，读取端显式 `UTF8Encoding`）。两份键集必须一致，`verify-installer.ps1` 比对；PowerShell 侧读它们**必须 `-Encoding UTF8`**，否则 5.1 按 GBK 解码会把中文尾字节与后面的 ASCII 合成一行（实测假报 19 个键缺失）。
- **注册表与命名口径（业主裁定）**：产品键 `HKLM\SOFTWARE\ExcelDiffEDR`（`InstallFolder` / `InstallVersion` / `SetupCulture` / `SetupStartOnBoot` / `ShellExtRegistered`），ARP 键 `HKLM\...\Uninstall\ExcelDiffEDR`。**用户可见名一律 `ExcelDiffEDR`**（2026-09-26 统一）：ARP `DisplayName`、开始菜单目录与快捷方式、资源管理器右键菜单文字（`ContextMenuExtension.cs`）、向导标题与文案、程序窗口标题与托盘提示。唯一保留 `ExcelDiff` 的是**用户自己写在 git 配置里的 difftool 标签**（`[difftool "ExcelDiff"]`，改它会破坏既有配置）以及 EDN 变体的历史名字。`SetupCulture` / `SetupStartOnBoot` 是**给程序读的种子**：`ApplicationSetting.EnsureCulture()` 的解析顺序是「用户显式选过 > HKLM 种子 > 系统显示语言 > zh-CN」，`Load()` 每次比对 `InstallerSeedApplied` 签名，只在签名变化时重新播种（安装器刚跑过）且此后用户的显式选择永久优先。必须这样改，因为程序原先每次启动都按 `startOnBoot = true` 重写 HKCU Run，安装器的勾选会被冲掉。`Build-Setup.ps1` 会断言两侧字面量逐字一致。
- **COM 注册必须在子进程里做**：`ShellRegistrar.RunChild("register|unregister", dir)` 用 `/silent /shell-op:… /dir="…"` 重新拉起自己。实测教训：在 setup 进程内 `Assembly.LoadFrom` 扩展 DLL 会把它锁到进程退出，卸载时 3 个 DLL 删不掉、目录残留。另注意 `/dir="…\"` 这种**结尾反斜杠紧跟引号**会被 Windows 命令行解析成转义引号，拼参数前要去掉尾分隔符。
- **删除一律清单驱动**：安装时写 `install-manifest.txt`（文件 / 快捷方式 / 注册表值与键 / 目录，且清单把自己也记进去），卸载按清单删、只删空目录，绝不递归删未知目录；**清单缺失就拒绝卸载**（早先"只删已知文件名"的回落会在 `/dir` 打错时删到别的东西）。实测由 `verify-installer.ps1` 的 J 用例覆盖：真装一份 → 删掉 `install-manifest.txt` → 卸载必须返回 1、文件与 HKLM 记录都还在；把清单放回去，同一条卸载返回 0（正向对照，证明那句"失败"不是"这里本来就什么都没装"）。文件被占用则保留清单与注册表、返回失败，提示"重启资源管理器后再卸载一次"。`ProductName` 改名前留下的快捷方式（`Programs\ExcelDiff\ExcelDiff.lnk`、桌面 `ExcelDiff.lnk`）由 `RemoveLegacyLinks()` 在安装与卸载时清掉。
- **重装=先卸后装带回滚**：旧目录 `Directory.Move` 成 `<dir>.old-<时间戳>`（同卷），任一步失败按 undo 栈还原并把 HKLM 状态写回 `RegistryStore.Snapshot()` 的快照。实测：占住旧 `ExcelDiffEDR.GUI.exe` 再执行安装 → 安装报失败、旧安装仍可运行、无 `.old-*` 残留。
- **静默参数**：`/silent|/quiet`、`/uninstall`、`/culture:zh-CN|en-US`、`/dir=<绝对路径>`（`:` 与 `=` 都接受，值保留原大小写；必须是 `D:\…`、`D:/…` 或 UNC `\\server\share\…`，**相对路径与盘符根一律拒绝**，判定看调用方写下的原文、在 `GetFullPath` 之前 —— 先解析再判 `IsPathRooted` 等于永远为真）、`/components:shell,desktop,autostart|none|all`、`/clearsettings`、`/log:<path>`、`/?`。默认勾选：桌面 ✓ / 自启 ✓ / 右键菜单 ✗（业主裁定）。**退出码**（`App.Main` 的返回值，脚本据此判成败，勿只看 0/非 0）：`0` 成功 / `1` 操作失败或异常 / `2` 显示了帮助（`/silent` 下只把帮助写进日志，同样返回 2） / `3` 载荷缺失（无 payload 的 setup exe）/ `4` 命令行参数非法（**含非法 `/dir` 形态：空值、相对路径、盘符根**；只写日志与退出码，绝不弹窗，否则卡住脚本）/ `130` 用户取消或关窗。非法参数在解析阶段就收集进 `Options.Errors`，`/silent=1` 这类"给布尔开关赋值"同样拒绝；目录形态也在 `Options.Parse` 这一层拒掉，所以坏 `/dir` 根本走不到碰机器的那一步（实测由 `verify-installer.ps1` 的 K 用例覆盖：`/dir=Q:\`、`/dir=Q:`、`/dir=Tools` 全部返回 4，且不留下解析出来的目录）。
- **卸载默认保留用户配置**（业主 2026-09-26 裁定"加开关，默认不清"）：只有传 `/clearsettings` 或向导上勾 `uninstall.clearsettings` 复选框时，`ClearUserSettings()` 才删除 `%APPDATA%\ExcelDiffEDR.GUI`；其余情况只删文件/快捷方式/注册表项，并记日志 `log.settingskept`。实测由 `verify-installer.ps1` 的 G 用例覆盖（默认卸载后设置目录仍在；带 `/clearsettings` 才消失）。跑 `-Install` 时仍备份 `%APPDATA%` 与 `HKCU\...\Run`（防回归，注意 `Environment.GetFolderPath(ApplicationData)` 不认临时的 `$env:APPDATA` 覆盖）。
- 版本口径不变：setup exe 的 FileVersion 必须等于 staged `ExcelDiffEDR.GUI.exe` 的 FileVersion（E8，脚本会校验），产品保持 2.0.0.0（业主裁定本轮不升）。NPOI 及其依赖仍必须随包（`ExcelUtility.CreateWorkbook/GetWorkbookTypeStrict` 仍在用），`open_readme.vbs` 仍不打包。
- 发布前必须外部 Authenticode 签名（E10）：setup exe 与它自己复制进安装目录的 `ExcelDiffSetup.exe` 同源，未签名会触发 SmartScreen。

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
2. **本地化流程**：字符串改动进 `Resources.resx`（en-US 中性）+ `Resources.zh-CN.resx`（仅 zh/en 两语言）→ 运行 `GenerateLangJson.ps1` 重新生成 `lang\*.json`（UTF-8 BOM，键取两份 resx 的**并集**，所以只在 zh 侧加键会让 en 侧出现空值——加键必须两边同时加）。**两份 resx 都只是编写源**：`ExcelDiff.GUI.csproj` 里 `EnableDefaultItems=false` 且只声明了 `Resources.resx` 为 `EmbeddedResource`，`Resources.zh-CN.resx` 不编译进程序、运行时不加载，真正的运行时文本是 `lang\*.json`（`Resources.Designer.cs` 的每个属性都走 `LocalizationManager.GetString`，外置 JSON 优先、缺失才回落 resx）。默认语言不再是写死的 zh-CN：解析顺序为「用户在程序里显式选过 > 安装器写入的 HKLM `SetupCulture` > 系统显示语言 > zh-CN」（`ApplicationSetting.EnsureCulture` / `ApplyInstallerSeed`）。`{x:Static Resources.*}` 在窗口加载时固化 → 语言切换通过 `App.CloseMainWindowForLanguageChange()` 关窗，下次 diff 命令以新语言重建。
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
9. **headless diff harness（EDN/EDR 对照诊断工具，保留、非门禁必需）**：`DiffHarness\` 零第三方离线对比，直接调库层（`ExcelWorkbook.Create` → `ExcelSheet.Diff` → `CreateSummary`）输出确定性 diff 文本，以 EDR（主版本）为准、EDN（保底）作验证对照。`DiffHarness.csproj` 必须是 **SDK-style**：旧式工程拿不到 `ExcelDiff` 的 `PackageReference` 传递依赖，EDN 变体运行时会缺 `ICSharpCode.SharpZipLib`（NPOI 读 xlsx 必需）并报版本加载失败；手工构建前先 `dotnet restore DiffHarness/DiffHarness.csproj`，并用 `/p:FrameworkPathOverride=<repo>\packages\refs\.NETFramework\v4.7.2`（`run_diff_compare.ps1` 两者已内置）。用法：`powershell -ExecutionPolicy Bypass -File DiffHarness\run_diff_compare.ps1 -RelPath Artifact.xlsx`（`-RelPath` 相对 `$TestDataRepoPath` 所指目录；自动提取 HEAD → 构建/运行双变体 → 比对，忽略 READER 行）；可用 `-NoBuild` 跳过重编译。产出 `DiffHarness.exe`（NPOI）/ `DiffHarnessEDR.exe`（EDR），输出 UTF-8。**配置对齐**：harness 默认读取配置 = GUI 默认 `ApplicationSetting`（4 项 trim 均 false）；复现 GUI 场景必须传一致参数——`--skip-first-blank-rows/columns`、`--trim-last-blank-rows/columns`（对应 `Setting.SkipFirstBlankRows/...`）、`--src-header N`/`--dst-header N`（列头对齐）。注意 harness 只验证"两变体一致"，不验证"diff 绝对正确"（与 GUI 共用 `ExcelSheet.Diff` 引擎），真实结果用 `VerifyRead` 双读 + EDN 对照。
10. **Git 提交与推送准则（硬性）**：**AI 不可直接 commit**。改动完成后，说明本次改动的 **Commit subject / description**，并从版本控制角度给出提交建议；实际提交由用户决定，且用户需先审查 subject/description 再提交。**推送（`git push` 及任何写远端的操作：`push --force`、`tag` 推送、改 PR 分支等）在用户没有当轮明确指令的前提下永远不执行**（2026-09-26 业主定的全域纪律）；"提交"只授权到本地提交为止，二者不是同一件事，需分别取得指令。

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
- **自动刷新**：git 钩子（`.githooks\` + `core.hooksPath=.githooks`）：`pre-commit` 提交前刷新 `PROJECT_STATE.md`（本次提交触及 C# 源码时**才**校准 `CODEX.md`）并 `git add` 回本次提交；`post-checkout` 只刷新状态；`post-merge` 刷新状态并**无条件**校准 `CODEX.md`。一次性启用：`git config core.hooksPath .githooks`。
- **`pre-push` 是推送闸门（失败关闭）**：任何 `git push` 都会被拒绝，除非执行者自己确认过授权并带上一次性豁免变量。PowerShell 里是两条语句（`VAR=value cmd` 那种内联写法只有 POSIX shell 认）：
  - PowerShell / cmd：`$env:EXCELDIFF_ALLOW_PUSH='1'; git push origin master`（cmd 用 `set EXCELDIFF_ALLOW_PUSH=1 && git push origin master`）
  - Git Bash：`EXCELDIFF_ALLOW_PUSH=1 git push origin master`
  这条钩子是 §7.10 的机械防线 —— **AI 会话不得设置该变量、也不得用 `--no-verify` 绕过它**，绕过等于替业主决定。三点诚实的限制：① `core.hooksPath` 不随克隆传播，所以闸门只在这台机器/已执行过一次性配置（`git config core.hooksPath .githooks`）的克隆上有效；② `--no-verify` 照样能绕过，它是摩擦不是保证；③ 本仓库 `core.fileMode=false`，Windows 上 git 用自己的 sh 拉起钩子所以能跑，POSIX 克隆需要索引里有可执行位 —— 2026-09-26 已把四个钩子全部置为 `100755`（`git ls-files -s .githooks` 实测；此前都是 `100644`，也就是 Mac/Linux 克隆上四个都不生效）。
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
5. **质量门**：不擅自提交 git、**永不擅自推送远端**（§7.10，推送需当轮明确指令）；改动给出 commit subject/description 供审查；高危区（diff 算法、读取层、生命周期）改动需在提交说明中注明测试证据。
6. **证据纪律（不迎合）**：结论只能来自实测输出或代码本身。不得为了让回答贴合提问口径（"能不能用""是不是 X"）而调整判断，也不得在既定使用场景之外附带个人偏好推荐；与提问者预设冲突时，先把冲突点和反例摆出来交其裁决。未取证的事实一律标注"未实测"，不得写进结论；自己的报告文字同受本条约束。
