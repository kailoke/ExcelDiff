# ExcelDiff 框架索引与模块设计

> 本文档为资深主程序视角的工程蓝图：解决方案结构、编译矩阵、模块职责、核心数据流、
> 生命周期、关键设计约束、部署布局与回归验证方法。修改代码前先读本文，保证改动符合架构。
> **先读 `AGENTS.md`（操作手册：已验证构建命令、方法论、陷阱、当前 WIP 状态），再读本文。**

## 1. 项目概览

- 用途：Excel/CSV/TSV 的 GUI 差异对比工具，可作 Git/Mercurial difftool。
- 技术栈：WPF (.NET Framework 4.6.2, WinExe) + Prism 6.3 + Unity 4.0.1 + YamlDotNet + AvalonDock/Extended.Wpf.Toolkit。
- 核心库：ExcelDiff（读取/解析）、NetDiff（差异算法）、FastWpfGrid（虚拟化网格）。
- 双构建：同一份源码可编译出**优先/基准版 EDE**（ExcelDataReader 读取）与**保底版 ED**（NPOI 读取），进程/程序集/配置/显示名完全隔离。开发与基准测试以 EDE 为准，ED 作保底验证对照。

## 2. 解决方案结构

| 项目 | 类型 | 职责 |
|------|------|------|
| `ExcelDiff` | 类库 | 读取工作簿/工作表/单元格；构建 Diff 模型；CSV/TSV 解析 |
| `ExcelDiff.GUI` | WPF 可执行 | UI、命令入口、设置、IPC、托盘、本地化、常驻生命周期 |
| `NetDiff` | 类库 | 通用文本差异（Myers/EditGraph 风格） |
| `FastWpfGrid` | 类库 | 高性能虚拟化网格控件 |
| `WriteableBitmapEx.Wpf` | 类库 | FastWpfGrid 依赖的位图扩展 |
| `ExcelDiff.ShellExtension` | COM 外壳扩展 | 资源管理器右键菜单入口 |
| `ExcelDiff.Installer` | VDProj | MSI 打包（未参与日常构建） |

依赖关系：

```
ExcelDiff.GUI ──> ExcelDiff ──> NetDiff
      │                │
      └──> FastWpfGrid ──> WriteableBitmapEx.Wpf
      └──> NetDiff
ExcelDiff ──> NPOI 2.5.6, ExcelDataReader 3.9.0 (代码级条件编译)
```

## 3. 编译矩阵（关键约束）

由 MSBuild 属性开关决定，GUI 项目 `AssemblyName`/`DefineConstants` 联动：

| 属性 | `EdrRead=true`（EDE，优先/基准） | `EdrRead` 未指定（ED，保底） |
|------|------------------------------|------------------------------|
| GUI 程序集 | `ExcelDiffEDR.GUI` | `ExcelDiff.GUI` |
| GUI 定义 | `EDR_READ` | 无 `EDR_READ` |
| 库定义 | 无（EDR 读取） | `NPOI_READ`（NPOI 读取） |
| 显示名 | `ExcelDiffEDR` | `ExcelDiff` |
| 常驻/IPC | channel 基于 exe 名，互不干扰 | 同左 |
| 配置目录 | `%APPDATA%\ExcelDiffEDR.GUI\ExcelDiffEDR.GUI.yml` | `%APPDATA%\ExcelDiff.GUI\ExcelDiff.GUI.yml` |

- `EnablePerfTiming=true` → 编译期定义 `PERF_TIMING`，注入阶段计时（GUI 与库同步开关）。
- 构建命令（GUI 必须携带 workaround 参数，见 `AGENTS.md` 摘要）：
  - EDE：`dotnet msbuild ExcelDiff.GUI/ExcelDiff.GUI.csproj /p:Configuration=Release /p:EdrRead=true /p:TargetFrameworkRootPath="D:\ExcelDiff\packages\refs" /p:IncludePackageReferencesDuringMarkupCompilation=false /p:GenerateResourceMSBuildArchitecture=CurrentArchitecture /p:GenerateResourceMSBuildRuntime=CurrentRuntime`
  - ED：同上，去掉 `/p:EdrRead=true`（默认）
- 依赖顺序：库→FastWpfGrid→GUI。`ExcelDiff.csproj` 中 `EdrRead != true` 才定义 `NPOI_READ`。

## 4. 模块划分与职责

### 4.1 ExcelDiff.GUI

| 模块 | 关键文件 | 职责与要点 |
|------|---------|-----------|
| 入口/生命周期 | `App.xaml.cs` | `ShutdownMode.OnExplicitShutdown`；`SingleInstance` 判断主/转发进程；托盘常驻；远程命令路由；未处理异常兜底；`DisplayName` 常量随 `EDR_READ` 切换 |
| 命令层 | `Commands/` | `CommandFactory`→`DiffCommand`；`CommandLineOption` 承载 CLI 参数（src/dst/external-cmd/keep-history…）；`RouteCommand` 对已存在窗口走 `CurrentDiffView.ApplyDiff`，否则新建 `DiffCommand` |
| 单实例/IPC | `SingleInstance.cs` | 命名管道 server/client；channel id 由 exe 名派生，保证 ED/EDE 独立；远程命令经 `Dispatcher.BeginInvoke` 回到 UI 线程，非阻塞管道线程（模态框存在时不死锁） |
| 托盘 | `TrayIconManager.cs` | 显示/隐藏、文本 = `App.DisplayName`、双击恢复窗口、右键菜单（显示/退出） |
| 设置 | `Settings/` | `ApplicationSetting : Setting<T>`（YamlDotNet 序列化到 `%APPDATA%\<程序集名>\<程序集名>.yml`）；`Ensure()` 缺省补齐；`IgnoreEqual`/`DeepClone` 提供脏检查 |
| 本地化 | `Localization/` `LocalizationManager.cs` | 外置 `lang\<culture>.json`（自定义 JSON 解析器，UTF-8）；`Resources.Designer.cs` 桥接到 `LocalizationManager.GetString`；`{x:Static Resources.*}` 在窗口加载时固化 → 语言变更需重建窗口（`App.RebuildMainWindow`） |
| 视图 | `Views/` | `MainWindow`（含 PowerShell 控制台宿主）；`DiffView`（对比网格 + 差异导航 + 搜索 + 日志输出）；`NoDiffWindow`（无差异提示，`CloseResultButton.IsDefault` 支持回车关闭）；`ProgressWindow`；设置/外部命令系列窗口 |
| ViewModel | `ViewModels/` | `MainWindowViewModel`、`DiffViewModel`、各设置窗口 VM，基于 Prism `BindableBase` |
| 模型 | `Models/` | `DiffGridModel`（行状态预计算、按需刷新 minimap 优化）；`DiffType` |
| 事件 | `Views/DiffViewEvent/` | 事件分发器/监听器/处理器 |
| 行为/转换器 | `Behaviors/` `ValueConverters/` | 拖放文件、条件转换器等 |
| 计时 | `Timing.cs` | `PERF_TIMING` 下的分段计时输出 |
| 外壳 | `Shell/` | `PowerShellHost`/`PowerShellInvocation`（内置控制台，供日志/扩展命令脚本） |

### 4.2 ExcelDiff（读取 + 差异模型）

| 模块 | 职责 |
|------|------|
| `ExcelWorkbook` | 入口工厂：按扩展名分发；`#if NPOI_READ` 走 `CreateUsingNpoi`，否则 `CreateFromExcel`(EDR)；EDR 路径跳过整空行、裁剪尾空单元格以对齐 NPOI 语义；`GetSheetNames` 对 xlsx 走 zip 直读 `xl/workbook.xml`（毫秒级）；`VerifyRead` 双读对比（开发期校验） |
| `ExcelSheet`/`Create` | 按 sheet 构建行集合；`#if PERF_TIMING \|\| NPOI_READ` 下暴露 NPOI 路径 |
| `ExcelSheetDiff` | 列对齐 + 行匹配（NetDiff）+ 单元格级差异；`ExcelSheetDiffConfig` 控制提取/忽略规则 |
| `ExcelRowDiff`/`ExcelCellDiff` | 行/单元格差异条目（Added/Removed/Modified/None） |
| `ExcelReader`/`ExcelUtility` | 读取配置、工作簿类型判定、创建空工作簿 |
| CSV/TSV | `CsvReader`/`TsvReader`（自研解析器，无第三方依赖） |

### 4.3 NetDiff

`EditGraph`（类 Myers 算法）、`DiffUtil`、`DiffResult`/`DiffStatus`/`DiffOrderType`/`DiffOption`，供行级/单元格级差异复用。
单测：`NetDiff.Test\Test.cs`（31 用例，MSTest）。本机无 VS/vstest 时用 `NetDiff.TestRunner`（MSTest shim + 反射执行，零第三方依赖）离线运行，命令见 `AGENTS.md` §4。

### 4.4 FastWpfGrid

虚拟化网格，`FastGridControl` 渲染海量单元格，是百 MB 级工作簿可用的前提。对比视图的单元格绘制（`EMColor` 配色、差异高亮）依赖它。

## 5. 核心数据流（Diff 管道）

```
CLI/difftool ─> CommandLineOption ─> DiffCommand
   → ExcelWorkbook.Create(src) + Create(dst)   [读取：NPOI 或 EDR]
   → ExcelSheet.Diff（NetDiff 行匹配 + 单元格比对，行级前沿 Limit=2000 守卫）
   → DiffViewModel/DiffGridModel（行状态预计算、延迟 minimap）
   → FastWpfGrid 渲染 + NoDiffWindow/进度提示
```

- 读取层是唯一差异来源（EDE=EDR 优先/基准；ED=NPOI 保底对照）。两版输出需用 diff 输出对比回归，以 EDE 为准。
- 已知限制：EDR 读不到仅含样式无值的单元格 → 列错位 → 漏报真实变更。这正是 ED（NPOI）保底对照存在的意义，ED 不得移除。

## 6. 生命周期与常驻机制

1. 启动 `App.Main`：加载设置 → `EnsureCulture` → `UpdateResourceCulture` → `Run`。
2. `OnStartup`：`SingleInstance.TryAcquire()` 失败 → 转发参数给常驻进程 → 立即退出。
3. 首个实例成为常驻：启动 IPC server + 托盘。`--startup`（登录自启）→ 仅驻留托盘。
4. 远程命令：管道线程 → `Dispatcher.BeginInvoke` → `DismissModalWindows()`（强制关闭无差异等模态）→ `ShowMainWindow`（保留最大化状态）→ `RouteCommand`。
5. 关闭窗口：`RunInBackground=true` → 隐藏到托盘；`IsClosingMainWindow` 时允许真正关闭（语言切换重建）；`ExitApplication` 置 `IsExiting` 后 `Shutdown`。

## 7. 关键设计决策与约束

1. **双版本隔离**：EDE 优先/基准（EDR，读取快约 72%），ED 保底（NPOI）。任何 UI/行为改动必须两版同步编译、部署；基准测试以 EDE 为准，ED 作保底验证对照。
2. **本地化热替换**：语言文件外置可改；`{x:Static}` 在 XAML 加载时固化。语言变更时**不重建窗口**（重建会同步重跑整个 diff，导致 UI 冻结约 5 秒），而是弹"重启确认"→ 点确定后由 `App.CloseMainWindowForLanguageChange()` 立即关闭对比窗口（实测 274ms），并置空 `MainWindow`/`CurrentDiffView`；下一条 diff 命令创建的新窗口即用新语言（无需整机重启）。
3. **DiffView 事件监听器生命周期（易崩溃点）**：`DiffViewEventDispatcher` 是进程级静态单例，`DiffView` 构造时把 `srcEventHandler`/`dstEventHandler` 加入其 `Listeners`。若 DiffView 关闭后不移除，后续新建 DiffView 时，XAML 加载中 `ShowAllRadioButton_Checked`（此时该视图的 `container` 字段尚未初始化）会分发到旧处理器 → `e.Container.ResolveAll<FastGridControl>()` 空引用崩溃。**必须**在窗口真正关闭（`window.Closed`）时调用 `DiffView.RemoveEventListeners()` 卸载监听。另：radio 处理器对 `container==null` 做了防护。
4. **两类聚焦态对话框（非真正模态，需正确处置）**：① 无差异弹窗 `NoDiffWindow`——关闭按钮 `IsDefault`，回车可关，右上角 X 亦可；X 按钮使用带白色描边+悬停高亮样式的圆角按钮以增强可视度；② 重启确认弹窗——点"确定"。
5. **主窗口 ESC（两段式）**：用 `HwndSource` 钩子（`MainWindow.WndProc`）在 Win32 层拦截 WM_KEYDOWN/VK_ESCAPE——WPF 路由键事件在焦点移出输入框后不再送达窗口，故不能靠 `KeyDown/PreviewKeyDown`。行为：① 焦点在 `TextBox`/`PasswordBox`/`RichTextBox`/`ComboBox`(收起) → `MainGrid.Focus()` 退出输入框焦点；② 焦点在窗口（Grid/null）→ 直接 `App.HideToTray()`（**不可用 `Close()`**：从窗口自身 WndProc 内调用 `Close()` 存在重入问题，窗口不会隐藏；尊重 `RunInBackground=false` 时用 `Close()` 退出）。ComboBox 下拉展开或菜单(MenuItem/Menu)聚焦时，ESC 交由控件自行处理。
6. **窗口状态持久化**：`WindowLeft/Top/Width/Height/WindowState` 存于 `ApplicationSetting`；最大化时保存 `RestoreBounds`；移动/缩放去抖 600ms 保存；启动延迟到 Show 后再最大化。
7. **常驻 IPC 不得阻塞**：管道线程只用 `BeginInvoke` 投递，绝不能同步等待模态框。
8. **配置分离**：`ApplicationSetting.Location` 用 `Assembly.GetExecutingAssembly().GetName().Name` 派生命名空间，ED/EDE 天然隔离；`lang` 目录同理按 exe 目录隔离。
9. **测试准则**：回归用仓库内真实文件（git 可回滚），禁止伪造缓存文件；特定需求回归用的 SHA 基线对比不作为通用准则，后续若有必须的回归对比单独建文件记录。

## 8. 部署布局

```
D:\Program Files\ExcelDiffEDRTool\     → EDE（ExcelDiffEDR.GUI.exe + ExcelDiff.dll[EDR] + lang\）
D:\Program Files\ExcelDiffTool\        → ED（ExcelDiff.GUI.exe + ExcelDiff.dll[NPOI_READ] + lang\）
%APPDATA%\ExcelDiffEDR.GUI\        → EDE 配置
%APPDATA%\ExcelDiff.GUI\           → ED 配置
```

- NGEN 已对两版 exe 预编译。
- Git difftool：`difftool.ExcelDiff`（ED）、`difftool.ExcelDiffEDR`（EDE）。
- **lang 部署坑**：构建时 `CopyLangFiles` 会把仓库 `..\lang\*.json` 复制到 `bin\Release\lang`（自动、正确）；但部署脚本用 `Copy-Item -Recurse` 复制整个 `lang` 目录到已存在的目标时会**嵌套成 `lang\lang`**，顶层文件不更新。部署后必须单独校验/同步 `lang\*.json`（或先删目标 `lang` 目录再 `-Recurse` 复制）。

## 9. 回归验证方法

0. **一键门禁**：任何改动完成后先跑 `powershell -ExecutionPolicy Bypass -File verify.ps1`（构建 ED+EDE、NetDiff 31 用例、lang↔resx 同步、§8.3 坑扫描、WIP 快照），全部通过再进入下述手工回归。
1. 编译两版（见 §3 命令），管理员部署到 §8 两目录。**坑**：不得在同一条命令里连续构建两个变体——MSBuild 增量会把另一变体的 exe 当过期输出清掉。必须"构建 EDE→部署 EDE→构建 ED→部署 ED"分步进行。**每次构建部署后立即重启对应常驻进程**（杀进程 → 从部署路径 `--startup` 拉起），否则旧进程仍锁住 exe、跑旧代码，测试结果失真。
2. 常驻进程重启后做 4 项冒烟：无差异窗口聚焦回车关闭；窗口状态跨会话/跨重启保持；语言切换后对比窗口重建生效；模态框存在时新命令强制生效。**注意**：无差异弹窗（`NoDiffWindow`）与语言切换重启确认 MessageBox 都是强制模态，会阻断脚本，识别与关闭方式见 `AGENTS.md` §7.8。
3. 对比对必须**严格用同名文件的 Unstaged（工作区）VS HEAD**（git `HEAD` vs 工作区），严禁拿两个不同文件互相对比。用 `cmd /c "git -C <repo> show HEAD:<path> > <tmp>"` 提取 HEAD 版（二进制安全），工作区文件直接引用。测试数据源见 `AGENTS.md` §7.7。
4. **坑**：对转发进程使用 `-Wait` 会挂起——当常驻进程不在时，转发器会变成新的常驻进程永不退出。改用 fire-and-forget（`Start-Process` 不带 `-Wait`）再定时轮询窗口。
5. diff 输出回归：对比 ED/EDE 两版的 modified 单元格输出，对比对象必须是同一文件的两个版本（见本条 3）。GUI 摘要只显示当前工作表，与全表输出对比时按 sheet 对齐。
6. 单点读取校验：`ExcelWorkbook.VerifyRead(path, config)` 双读对比（EDR vs NPOI 值级一致）。
7. **坑**：PowerShell 5.1 的 `Get-Content`/`Set-Content -Encoding UTF8` 会按 ANSI 读入再写回，破坏 UTF-8 中文 → YAML 解析崩溃（`YamlDotNet.Core.SemanticErrorException`）。改写含非 ASCII 的 YAML 必须用文件写入工具（UTF-8 无 BOM）或 `[System.IO.File]::WriteAllText` + 显式 UTF8。

## 10. 已知限制 / 风险

- EDR 无法识别仅样式单元格（`s=` 无 `<v>`），导致空列被吞 → 列对齐漂移 → 漏报真实差异。EDR 盲区由 ED（NPOI）保底对照兜底，ED 不得移除。
- `EditGraph`（NetDiff）为 Myers 启发式 BFS，最坏 O(D²) 节点分配（病态"两表几乎全不同"大表）。已用行级 `Limit=2000` 前沿守卫兜底（ADR-010）；不重写（31 测试编码当前路径平局规则）。
- `backup_installed_*` 目录为部署前快照，勿改动。
- `ExcelDiff.Installer.vdproj` 未纳入当前构建流程。
- `%APPDATA%\ExcelDiff\`、`%APPDATA%\ExcelDiffTest.GUI\` 为旧名残留，孤儿数据待清理。
