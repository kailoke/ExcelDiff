# CODEX — 代码级索引与关键调用链

> 面向 AI 代理/开发者的**类级导航**：核心类型的公开方法、两条关键调用链、线程模型。
> 文件级地图见 `AGENTS.md` §3，架构蓝图见 `ARCHITECTURE.md`，硬约束见 `INVARIANTS.md`。
> 行号随代码改动会漂移，跑 `AI_Script\refresh_codex.ps1` 自动校准。

## 1. 两条关键调用链（先看时序，再看单类）

### 链路 A：启动 / Git difftool → Diff 管道（UI 线程为主）

```
exe diff -s <src> -d <dst> ...
  └─ App.Main()                                   App.xaml.cs:28    加载 Setting、EnsureCulture、UpdateResourceCulture、Run
  └─ App.OnStartup()                              App.xaml.cs:57    TryAcquire() 失败→转发给常驻实例后退出
       ├─ SingleInstance.StartServer(OnRemoteCommand)               后台管道线程
       ├─ InitializeTray() → TrayIconManager                        托盘常驻
       ├─ StartupHelper.SetEnabled(Setting.StartOnBoot)             Run 键
       └─ CreateCommand(args) → CommandFactory.Create               解析 CLI → ICommand
  └─ DiffCommand.Execute()                        DiffCommand.cs:22
       ├─ new MainWindow() + new DiffView() + VMs，互设 DataContext
       ├─ App.CurrentDiffView = diffView；window.Show()
       └─ window.Closed → diffView.RemoveEventListeners()           防静态分发器泄漏
  └─ DiffView 内（用户点“显示差异”或启动即跑）
       ├─ ReadWorkbooks()                          DiffView.xaml.cs:458
       │     Task.Run×2 并行 → ExcelWorkbook.Create(src/dst)        读层 = EDE:EDR / ED:NPOI
       ├─ ExecuteDiff(ExcelSheet,ExcelSheet)     DiffView.xaml.cs:533
       │     ProgressWindow.DoWorkWithModal → ExcelSheet.Diff(src,dst,config)
       └─ ExecuteDiff(bool isStartup=false)      DiffView.xaml.cs:550
             ├─ 选 sheet → ExecuteDiff → DiffGridModel(diff, Type)
             ├─ GetViewModel().UpdateDiffSummary(summary)
             ├─ NotifyEqual 且无差异 → NoDiffWindow.ShowDialog()     （原 MessageBox）
             └─ FocusFirstDiff → MoveNextModifiedCell()
```

### 链路 B：IPC 远程命令路由（常驻进程收到第二次启动）

```
新进程 exe diff ... → SingleInstance.TryAcquire()==false
  └─ SingleInstance.SendToRunningInstance(args)   SingleInstance.cs:75   命名管道 client（channel=exe 名）
  └─ 常驻进程管道线程 ServerLoop()                SingleInstance.cs:113   server 收包 → handler(args)
  └─ App.OnRemoteCommand(args)                    App.xaml.cs:161
       ├─ Dispatcher.BeginInvoke(...)                                      管道线程绝不阻塞/同步等待
       ├─ CurrentDiffView.DismissModalWindows()                            强关 NoDiffWindow 等模态
       ├─ ShowMainWindow()                                                保留最大化状态恢复窗口
       └─ RouteCommand(option)                    App.xaml.cs:207
             ├─ CurrentDiffView==null → new DiffCommand(option).Execute()
             └─ 否则 CurrentDiffView.ApplyDiff(option)  DiffView.xaml.cs:405
```

## 2. GUI 关键类型（ExcelDiff.GUI）

| 类型 | 位置 | 关键成员 / 职责 |
|------|------|-----------------|
| `App` | App.xaml.cs:14 | 生命周期中枢。`Setting`、`CommandLineOption`、`CurrentDiffView`、`DisplayName`（`#if EDR_READ`）、`HideToTray/ShowMainWindow/ExitApplication`、`UpdateResourceCulture`（语言切换=关窗）、`UpdateRecentFiles`、`GetRecentFiles*` |
| `SingleInstance` | SingleInstance.cs:14 | `TryAcquire`（Mutex，Local\exe名-用户SID）、`SendToRunningInstance`（管道 out，3s 超时）、`StartServer`（后台线程）+`ServerLoop` |
| `TrayIconManager` | TrayIconManager.cs:10 | `Show/Hide/Dispose`；图标=exe 关联图标；双击→onOpen；右键菜单（打开/退出，`Resources.Word_Open/Exit`） |
| `StartupHelper` | StartupHelper.cs:10 | `SetEnabled(bool)` → `HKCU\...\Run` 写 `"exe" --startup` |
| `Timing` | Timing.cs:12 | `[Conditional("PERF_TIMING")] Mark/Log`，写 `%TEMP%\em_open_timing.log`；正式版编译期裁掉 |
| `DiffCommand` | Commands/DiffCommand.cs:8 | 组装 MainWindow+DiffView+VM；`ValidateOption`（`-e empty-file-name`→`EnsureFile`，扩展名校验）；`DefaultEnabledExtensions` |
| `CommandFactory` | Commands/CommandFactory.cs:3 | `Create(option)` → DiffCommand |
| `CommandLineOption` | Commands/CommandLineOption.cs:7 | CLI 参数绑定（`-s/-d/-c/-i/-w/-v/-e/-k`）；`MainCommand`（首参→`CommandType`） |
| `MainWindow` | Views/MainWindow.xaml.cs:11 | PowerShell 宿主；窗口状态持久化（600ms 去抖 timer）；`OnClosing`（托盘/退出二分）；`WndProc` ESC 钩子；`RestoreWindowState/SaveWindowState` |
| `DiffView` | Views/DiffView.xaml.cs:25 | 对比视图核心。`InitializeEventListeners`（静态分发器注册 src/dst 两个 handler）、`ReadWorkbooks`、`ExecuteDiff`（双重载）、`ApplyDiff`、`DismissModalWindows`、`RemoveEventListeners`；`#if PERF_TIMING` 分段计时 |
| `NoDiffWindow` | Views/NoDiffWindow.xaml.cs:15 | 无差异模态窗；ESC=仅关本窗；红色"退出"按钮连对比窗口一起关 |
| `ProgressWindow` | Views/ProgressWindow.xaml.cs | `DoWorkWithModal(Action<ProgressReporter>)`，后台执行+进度 UI |
| `DiffGridModel` | Models/DiffGridModel.cs | `FastGridModelBase` 派生；ctor 预计算 `modifiedRows/addedRows/removedRows` 三个 HashSet；`GetCellColor`（minimap 轻量路径）；`IsModifiedRow/IsAddedRow/IsRemovedRow` |
| `DiffViewModel` | ViewModels/DiffViewModel.cs | sheet 名加载（`ExcelWorkbook.GetSheetNames`）、选择、命令 |
| `MainWindowViewModel` | ViewModels/MainWindowViewModel.cs | 主菜单命令、最近文件、`OpenFileSetCommand` |
| `LocalizationManager` | Localization/LocalizationManager.cs:23 | `SetCulture`（载入 `lang\<culture>.json`，自研 JSON 解析器）、`GetString(key, rm, culture)`（缺键回落 Resources）、`GetAvailableLanguages` |
| `EMColor` | Styles/EMColor.cs | 差异配色常量/方法 |

## 3. 核心库 ExcelDiff（读取 + Diff 模型）

| 类型 | 位置 | 关键成员 / 职责 |
|------|------|-----------------|
| `ExcelWorkbook` | ExcelWorkbook.cs:10 | `Create(path,config)` 扩展名分发（csv/tsv/`#if NPOI_READ`→`CreateUsingNpoi`，否则 EDR `CreateFromExcel`）；`VerifyRead` 双读比对（`#if PERF_TIMING \|\| NPOI_READ`）；`GetSheetNames`（xlsx 走 zip 直读 `xl/workbook.xml`，其余 NPOI） |
| `ExcelSheet` | ExcelSheet.cs | `Create(ISheet/rows/Csv/Tsv)` 多入口；`Diff(src,dst,config)`：列对齐（`CreateColumnStatusMap` 用 NetDiff 对列）→ 行内空白补齐 → 行匹配（`DiffUtil.Diff/Order(LazyDeleteFirst)/OptimizeCaseDeletedFirst`）→ `DiffCells`；>10000 条结果抽样 |
| `ExcelSheetDiff` | ExcelSheetDiff.cs:6 | `Rows: SortedDictionary<int,ExcelRowDiff>`；`CreateRow`；`CreateSummary`（Added/Removed/Modified 行列计数） |
| `ExcelRowDiff` | ExcelRowDiff.cs | `IsModified/IsAdded/IsRemoved/ModifiedCellCount` |
| `ExcelCellDiff` | ExcelCellDiff.cs | 单元格差异条目 |
| `ExcelSheetDiffConfig` | ExcelSheetDiffConfig.cs | 提取/忽略规则、header 索引 |
| `ExcelSheetReadConfig` | ExcelSheetReadConfig.cs | 读取配置（跳首空行/列、去尾空行/列） |
| `ExcelUtility` | ExcelUtility.cs | `GetWorkbookType`、`CreateWorkbook`（空文件模板） |
| `CsvReader` / `TsvReader` | CsvReader.cs / TsvReader.cs | 自研解析器，无第三方依赖 |
| `ExcelReader` | ExcelReader.cs | 读取配置入口 |

## 4. NetDiff（差异算法）

| 类型 | 文件 | 职责 |
|------|------|------|
| `DiffUtil` | NetDiff/NetDiff/DiffUtil.cs | `Diff(IEnumerable,IEnumerable,DiffOption<T>)`；`Order`（Greedy/Lazy × Insert/Delete First）；`OptimizeCaseDeletedFirst`；`CreateSrc/CreateDst`（还原） |
| `EditGraph` | NetDiff/NetDiff/EditGraph.cs | 类 Myers 算法核心 |
| `DiffResult<T>` / `DiffStatus` / `DiffOrderType` / `DiffOption<T>` | NetDiff/NetDiff/ | 结果/状态/排序/选项 |
| `NetDiff.Test` | NetDiff/NetDiff.Test/Test.cs | 31 个 MSTest 用例；**本机用 `NetDiff.TestRunner` 跑**（见 AGENTS.md §4/AI_Script\verify.ps1） |

## 5. FastWpfGrid（虚拟化网格）

| 类型 | 文件 | 职责 |
|------|------|------|
| `FastGridControl` | FastWpfGrid/FastWpfGrid/FastGridControl_*.cs | 海量单元格虚拟化渲染（分文件：Render/Arrange/Input/Selection/Invalidation/DependencyProps） |
| `FastGridModelBase` / `IFastGridModel` | FastWpfGrid/FastWpfGrid/ | 模型接口，`DiffGridModel` 继承/实现 |
| `FastWpfGridUnitTest` | FastWpfGrid/FastWpfGridUnitTest/GridTest.cs | 网格单元测试 |

## 6. 线程模型（改生命周期/IPC 前必读）

```
UI 线程（Dispatcher）          : 所有 WPF 控件、命令、Diff 管道、窗口生命周期
管道后台线程 (ServerLoop)      : 只收包→BeginInvoke 投递到 UI 线程；禁止同步等待模态框（死锁）
Task.Run (ReadWorkbooks) : 读取工作簿并行化，结果回到 UI 线程组装模型
```

- `#if PERF_TIMING` 代码在正式构建（未传 `EnablePerfTiming=true`）时全部裁掉，不影响线上。
- 静态事件分发器（`*EventDispatcher.Instance`）是进程级单例：窗口关闭必须 `RemoveEventListeners`，否则新窗口事件会派发到已关闭视图（`container==null`）。
