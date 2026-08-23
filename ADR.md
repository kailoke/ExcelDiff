# ADR — 架构决策记录（Architecture Decision Records）

> 记录关键决策的**背景、权衡、结论**，避免后续对话重开争论。
> 每条约：状态 / 背景 / 决策 / 后果 / 备选被否原因。反向指向 INVARIANTS/ARCHITECTURE 对应条。

## ADR-001 双版本 ED/EDE 用条件编译而非分支

- **状态**：已定（生效中）
- **背景**：需要"权威读取（NPOI）"与"性能验证读取（ExcelDataReader）"两套交付，又要保证行为同步。
- **决策**：一份源码，MSBuild 属性 `EdrRead` 驱动 `AssemblyName` + `DefineConstants`（GUI `EDR_READ`、库 `NPOI_READ`），代码内 `#if` 分支。配置/IPC/显示名按程序集名派生隔离。
- **后果**：任何改动必须双版都编译（INVARIANT A2）；构建/部署分步（A3）。
- **被否**：两个 git 分支——差异会漂移，回归成本翻倍；两套 csproj——文件级重复。

## ADR-002 EDE（EDR）为优先/基准版本，ED（NPOI）保底对照

- **状态**：已定（2026-08-23 由"ED 权威"调整为"EDE 优先/基准"）
- **背景**：EDR 读取效率约提升 72%（约 1.8MB 文件读取耗时约为 NPOI 的 28%），未来潜力大；NPOI 语义最全但较慢。
- **决策**：EDE=EDR **优先/基准**，开发与基准测试以 EDE 为准；ED=NPOI **保底对照**（EDR 盲区兜底、验证）。EDR 路径尽力对齐 NPOI 语义（跳空行、裁尾空列）。
- **后果**：ED 保底不得移除（INVARIANT B1）；EDR 盲区（仅样式无值单元格）场景用 `VerifyRead` 双读比对 + ED 对照（INVARIANT B3）。
- **被否**：ED 权威路线（被 EDE 取代，速度劣势）；EDR 唯一读取器（会漏报差异，保底缺失不可接受）。

## ADR-003 单实例 + 命名管道 IPC + 托盘常驻

- **状态**：已定
- **背景**：作 Git difftool 时每 diff 会启动新进程；希望多次 diff 复用常驻进程、快速响应。
- **决策**：`Mutex` 判单实例；首个实例驻留托盘并起命名管道 server；后续进程转发 CLI 参数后退出；channel id 用 exe 名派生（ED/EDE 可并存）。
- **后果**：管道线程必须非阻塞（INVARIANT C1）；转发进程退出即走（C4）。
- **被否**：每 diff 一次冷启动全量进程——读取慢，托盘体验差。

## ADR-004 外置 JSON 本地化（可热替换）

- **状态**：已定
- **背景**：社区/用户要改中文翻译，不应等发布新版。
- **决策**：`lang\<culture>.json` 外置在 exe 目录（自研 JSON 解析器，无第三方依赖）；`Resources.Designer.cs` 桥接 `LocalizationManager.GetString`，缺键回落编译期资源。
- **后果**：改字符串要改 resx + 跑 `GenerateLangJson.ps1`（INVARIANT D2）；JSON 必须 UTF-8（D3）。
- **被否**：仅 resx——需重编译；引入 JSON.NET——Core 库增依赖、与零第三方风格冲突。

## ADR-005 语言切换=关窗+下次命令重建

- **状态**：已定（替代早期"重建窗口"）
- **背景**：`{x:Static Resources.*}` 在 XAML 加载时固化，切换语言必须重建所有已加载窗口；早期实现会同步重跑整个 diff，冻结 UI。
- **决策**：语言变更时 `CloseMainWindowForLanguageChange()` 立即关窗（`IsClosingMainWindow` 放行 `OnClosing`），下次 diff 命令新建窗口即用新语言。
- **后果**：切换语言后需重新发起对比（INVARIANT D4）。
- **被否**：`RebuildMainWindow`（同步重跑 diff）——UI 冻结；热替换已加载 `x:Static`——WPF 不支持。

## ADR-006 窗口状态持久化到 YAML 设置

- **状态**：已定
- **背景**：difftool 高频使用，用户期望位置/大小/最大化跨会话保持。
- **决策**：`WindowLeft/Top/Width/Height/WindowState` 存入 `ApplicationSetting`（YAML）；最大化保存 `RestoreBounds`；移动/缩放 600ms 去抖保存；启动 Show 后延迟应用最大化（防错位）。
- **后果**：窗口首次 Show 前的几何访问要防御 `double.NaN`/虚拟屏越界（MainWindow.xaml.cs RestoreWindowState）。
- **被否**：不持久化——体验差；注册表——与 YAML 设置体系割裂。

## ADR-007 并行读取工作簿

- **状态**：已定
- **背景**：大文件打开慢，src/dst 读取彼此独立。
- **决策**：`CreateWorkbookTuple` 内 `Task.Run`×2 并行读，结果回 UI 线程组装。
- **后果**：读取层必须线程安全（ExcelWorkbook.Create 是纯函数，无共享状态，安全）；`#if PERF_TIMING` 注入分段计时。
- **被否**：串行读——慢一倍；多核并行整体管道——进度/取消复杂度高。

## ADR-008 自定义 NoDiffWindow 替代 MessageBox

- **状态**：已定
- **背景**：无差异提示需支持"关对比窗口"与"仅关提示"两种关闭语义，MessageBox 表达不了；IPC 场景还需能被远程命令强关。
- **决策**：自绘模态窗（`NoDiffWindow`）：ESC=仅关提示；红色退出按钮=连对比窗口一起关；`DismissModalWindows` 可强关。
- **后果**：`NotifyEqual` 分支用 `ShowDialog` 且持有引用供强关（DiffView.xaml.cs:557）。
- **被否**：MessageBox——无按钮语义定制、无法强制关闭。

## ADR-009 ESC 用 Win32 WndProc 钩子处理

- **状态**：已定
- **背景**：焦点移到非输入面板后，WPF 路由键事件不再送达窗口，ESC 关窗不可靠。
- **决策**：`MainWindow.OnSourceInitialized` 挂 `HwndSource.AddHook(WndProc)`；ESC 在消息级处理：下拉框/菜单打开时让路，输入控件聚焦时先移焦点，否则关窗/隐藏。
- **后果**：与 NoDiffWindow 自己的 ESC 处理共存（NoDiff 用 PreviewKeyDown，职责分离）。
- **被否**：仅 `KeyDown`——焦点问题无法解决；全局键盘钩子——过度、有系统副作用。
