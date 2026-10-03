# CODE_INDEX（代码锚点索引）

> 本文件由 `AI_Script/refresh-code-index.ps1` 自动生成，请勿手改。每次修改代码后运行该脚本刷新行号。

生成时间：2026-10-02 23:56:18

解析成功：26 个锚点

| 锚点 ID | 文件 | 行号 | 说明 |
|---|---|---:|---|
| App.Class | ExcelDiff.GUI/App.xaml.cs | 16 | 生命周期中枢：托盘、语言切换、最近文件 |
| App.Main | ExcelDiff.GUI/App.xaml.cs | 30 | 进程入口：加载设置、EnsureCulture、UpdateResourceCulture、Run |
| App.OnRemoteCommand | ExcelDiff.GUI/App.xaml.cs | 173 | 常驻收到远程命令：BeginInvoke 投递、强关模态、恢复窗口、路由 |
| App.OnStartup | ExcelDiff.GUI/App.xaml.cs | 52 | 单实例判定：TryAcquire 失败即转发参数并退出 |
| App.RouteCommand | ExcelDiff.GUI/App.xaml.cs | 270 | 已有对比窗口走 ApplyDiff，否则新建 DiffCommand |
| CommandFactory.Class | ExcelDiff.GUI/Commands/CommandFactory.cs | 3 | 命令工厂：Create(option) → DiffCommand |
| CommandLineArguments.Class | ExcelDiff.GUI/Commands/CommandLineArguments.cs | 14 | 解析前归一化：位置参数改写 -s/-d，两条入口共用 |
| CommandLineOption.Class | ExcelDiff.GUI/Commands/CommandLineOption.cs | 7 | CLI 参数绑定（-s/-d/-c/-i/-w/-v/-e） |
| DiffCommand.Class | ExcelDiff.GUI/Commands/DiffCommand.cs | 8 | 命令实现：ValidateOption 与默认扩展 |
| DiffCommand.Execute | ExcelDiff.GUI/Commands/DiffCommand.cs | 22 | 组装 MainWindow+DiffView+VM 并执行对比 |
| DiffView.ApplyDiff | ExcelDiff.GUI/Views/DiffView.xaml.cs | 392 | 远程命令对已有窗口复用：换文件重跑对比 |
| DiffView.Class | ExcelDiff.GUI/Views/DiffView.xaml.cs | 25 | 对比视图核心：事件监听注册/卸载、模态强关 |
| DiffView.ExecuteDiff | ExcelDiff.GUI/Views/DiffView.xaml.cs | 520 | 进度模态内跑 ExcelSheet.Diff |
| DiffView.ExecuteDiffStartup | ExcelDiff.GUI/Views/DiffView.xaml.cs | 537 | 选 sheet → 建模型 → 摘要 → 无差异弹窗 → 聚焦首差异 |
| DiffView.ReadWorkbooks | ExcelDiff.GUI/Views/DiffView.xaml.cs | 445 | Task.Run×2 并行读取两个工作簿（唯一读取实现） |
| ExcelSheetDiff.Class | ExcelDiff/ExcelSheetDiff.cs | 6 | 差异结果容器与摘要计数 |
| ExcelWorkbook.Class | ExcelDiff/ExcelWorkbook.cs | 9 | 读取入口工厂：按扩展名分发（ExcelDataReader 唯一实现 + csv/tsv 自研） |
| LocalizationManager.Class | ExcelDiff.GUI/Localization/LocalizationManager.cs | 23 | 外置 lang json 加载与缺键回落 |
| MainWindow.Class | ExcelDiff.GUI/Views/MainWindow.xaml.cs | 11 | 主窗口：PowerShell 宿主、窗口状态持久化、ESC 的 Win32 钩子 |
| NoDiffWindow.Class | ExcelDiff.GUI/Views/NoDiffWindow.xaml.cs | 15 | 无差异模态窗：✕ 仅关提示，红色退出按钮连窗口一起关 |
| SingleInstance.Class | ExcelDiff.GUI/SingleInstance.cs | 14 | Mutex 单实例 + 命名管道 server/client，channel id 由 exe 名派生 |
| SingleInstance.SendToRunningInstance | ExcelDiff.GUI/SingleInstance.cs | 75 | 命名管道 client：转发参数给常驻（3s 超时） |
| SingleInstance.ServerLoop | ExcelDiff.GUI/SingleInstance.cs | 113 | 常驻管道后台线程：收包后交 handler，禁阻塞 |
| StartupHelper.Class | ExcelDiff.GUI/StartupHelper.cs | 10 | HKCU Run 键按 exe 名单槽位自启管理 |
| Timing.Class | ExcelDiff.GUI/Timing.cs | 12 | PERF_TIMING 分段计时（正式构建裁掉） |
| TrayIconManager.Class | ExcelDiff.GUI/TrayIconManager.cs | 10 | 托盘常驻：显示/隐藏/退出，双击恢复窗口 |

