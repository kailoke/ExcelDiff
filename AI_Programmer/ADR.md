# ADR — 架构决策记录（Architecture Decision Records）

> 记录关键决策的**背景、权衡、结论**，避免后续对话重开争论。
> 每条约：状态 / 背景 / 决策 / 后果 / 备选被否原因。反向指向 INVARIANTS/ARCHITECTURE 对应条。

## ADR-001 双版本 EDN/EDR 用条件编译而非分支

- **状态**：已定（生效中）
- **背景**：需要"主版本读取（EDR）"与"保底读取（NPOI）"两套交付，又要保证行为同步。
- **决策**：一份源码，MSBuild 属性 `EdrRead` 驱动 `AssemblyName` + `DefineConstants`（GUI `EDR_READ`、库 `NPOI_READ`），代码内 `#if` 分支。配置/IPC/显示名按程序集名派生隔离。
- **后果**：EDR 主版本必须编译通过（INVARIANT A2）；EDN 代码保留不删（A3）。
- **被否**：两个 git 分支——差异会漂移，回归成本翻倍；两套 csproj——文件级重复。

## ADR-002 EDR（ExcelDataReader）为主版本，EDN（NPOI）保底对照

- **状态**：已定
- **背景**：EDR 读取效率约提升 72%（约 1.8MB 文件读取耗时约为 NPOI 的 28%），未来潜力大；NPOI 语义最全但较慢。
- **决策**：EDR（ExcelDataReader）**主版本**，开发与基准测试以 EDR 为准；EDN=NPOI **保底对照**（EDR 盲区兜底、验证）。EDR 路径尽力对齐 NPOI 语义（跳空行、裁尾空列）。
- **后果**：EDN 保底不得移除（INVARIANT B1）；EDR 盲区（仅样式无值单元格）场景用 `VerifyRead` 双读比对 + EDN 对照（INVARIANT B3）。
- **被否**：EDN 权威路线（速度劣势）；EDR 唯一读取器（会漏报差异，保底缺失不可接受）。

## ADR-003 单实例 + 命名管道 IPC + 托盘常驻

- **状态**：已定
- **背景**：作 Git difftool 时每 diff 会启动新进程；希望多次 diff 复用常驻进程、快速响应。
- **决策**：`Mutex` 判单实例；首个实例驻留托盘并起命名管道 server；后续进程转发 CLI 参数后退出；channel id 用 exe 名派生（EDN/EDR 可并存）。
- **后果**：管道线程必须非阻塞（INVARIANT C1）；转发进程退出即走（C4）。
- **被否**：每 diff 一次冷启动全量进程——读取慢，托盘体验差。

## ADR-004 外置 JSON 本地化（可热替换）

- **状态**：已定
- **背景**：社区/用户要改中文翻译，不应等发布新版。
- **决策**：`lang\<culture>.json` 外置在 exe 目录（自研 JSON 解析器，无第三方依赖）；`Resources.Designer.cs` 桥接 `LocalizationManager.GetString`，缺键回落编译期资源。
- **后果**：改字符串要改 resx + 跑 `GenerateLangJson.ps1`（INVARIANT D2）；JSON 必须 UTF-8（D3）。
- **被否**：仅 resx——需重编译；引入 JSON.NET——Core 库增依赖、与零第三方风格冲突。

## ADR-005 语言切换=关窗+下次命令重建

- **状态**：已定
- **背景**：`{x:Static Resources.*}` 在 XAML 加载时固化，切换语言必须重建所有已加载窗口；重建窗口会同步重跑整个 diff，冻结 UI。
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
- **决策**：`ReadWorkbooks` 内 `Task.Run`×2 并行读，结果回 UI 线程组装。
- **后果**：读取层必须线程安全（ExcelWorkbook.Create 是纯函数，无共享状态，安全）；`#if PERF_TIMING` 注入分段计时。
- **被否**：串行读——慢一倍；多核并行整体管道——进度/取消复杂度高。

## ADR-008 自定义 NoDiffWindow 替代 MessageBox

- **状态**：已定
- **背景**：无差异提示需支持"关对比窗口"与"仅关提示"两种关闭语义，MessageBox 表达不了；IPC 场景还需能被远程命令强关。
- **决策**：自绘模态窗（`NoDiffWindow`）：ESC=仅关提示；红色退出按钮=连对比窗口一起关；`DismissModalWindows` 可强关。
- **后果**：`NotifyEqual` 分支用 `ShowDialog` 且持有引用供强关（DiffView.xaml.cs:588）。
- **被否**：MessageBox——无按钮语义定制、无法强制关闭。

## ADR-009 ESC 用 Win32 WndProc 钩子处理

- **状态**：已定
- **背景**：焦点移到非输入面板后，WPF 路由键事件不再送达窗口，ESC 关窗不可靠。
- **决策**：`MainWindow.OnSourceInitialized` 挂 `HwndSource.AddHook(WndProc)`；ESC 在消息级处理：下拉框/菜单打开时让路，输入控件聚焦时先移焦点，否则关窗/隐藏。
- **后果**：与 NoDiffWindow 自己的 ESC 处理共存（NoDiff 用 PreviewKeyDown，职责分离）。
- **被否**：仅 `KeyDown`——焦点问题无法解决；全局键盘钩子——过度、有系统副作用。

## ADR-010 EditGraph 不重写，用 Limit 前沿守卫兜底

- **状态**：已定
- **背景**：`EditGraph` 是 Myers 启发式 BFS，最坏 O(D²) 节点分配（病态"两表几乎全不同"时 1 万行 ≈ 10⁸ 节点 → OOM/冻结）。经典 Myers V-array 重写可降到 O((N+M)D)。
- **决策**：**不重写算法**，在 `ExcelSheet.Diff` 行级 diff 调用处设 `option.Limit = 2000`（复用现有 beam 截断）：前沿超阈值后保留单路径，退化为 O(D) 快速搜索，结果有效但可能非最小。正常差异（数百行变更）前沿远低于阈值，路径不变。
- **后果**：31 个 NetDiff 测试（编码当前路径平局规则，尤其 `CaseMultiSameScore_*`）不被破坏；病态输入 2 秒内完成且 EDN/EDR 一致。若未来出现真实的全不同大表崩溃报告，再走"独立分支 + 差分 oracle（新旧算法跑随机输入比对 `CreateSrc/CreateDst` 还原）"路线重写。
- **被否**：直接重写——会改变平局路径选择导致测试失败；改测试期望则形成自证循环；收益仅限病态场景，对日常 Excel 差异（多数行匹配，D 小）无感。

## ADR-011 提权部署禁止 `-Wait`

- **状态**：已定
- **背景**：`Start-Process powershell -Verb RunAs -Wait` 在 UAC 提权 + msbuild 子进程场景下不返回，bash 卡到超时（部署实际 10-30 秒已完成）。
- **决策**：提权启动**不带 `-Wait`**（fire-and-forget），轮询提权脚本写出的日志文件出现 `DONE` 后再继续；随后杀进程、部署、`--startup` 重启常驻。
- **后果**：部署命令秒回、不挂起。写 `Program Files` 需提权（UAC），部署脚本必须输出日志供轮询。
- **被否**：`-Wait`——挂起；同步提权后直接部署——与 UAC 生命周期冲突。

## ADR-012 EDR 成为唯一构建/部署/门禁目标，EDN 代码保留退出日常流程

- **状态**：已定
- **背景**：EDR（ExcelDataReader）读取效率高；EDN（NPOI）双版本并存使每次改动需双版编译/部署，门禁与部署成本翻倍。
- **决策**：EDR 定为**主版本**，是唯一构建/部署/门禁目标（`verify.ps1` 只构建 EDR；`Deploy-And-Restart.ps1` 只部署/重启 EDR）。EDN 代码（`#if NPOI_READ` 分支、`ExcelDiff.GUI` 程序集名、相关配置路径）**完整保留**，相关版本说明文档（ARCH §3 编译矩阵、ADR-001/002、INVARIANTS A/B）一并保留，仅在需 EDR 盲区兜底/对照验证时手工 build。
- **后果**：日常门禁只验证 EDR（INVARIANT A2 "主版本必编译"）；EDN 保底对照退化为可选诊断（DiffHarness 保留）；若未来 EDR 出现对比 bug 需要对照，可随时手工构建 EDN 恢复保底验证（INVARIANT A3 保证 EDN 代码不删）。
- **被否**：删除 EDN 代码——失去 EDR 盲区兜底与对照基准，不可接受；维持双版同步编译/部署——日常成本翻倍且近期无收益。

## ADR-013 EDR MSI 使用隔离、确定且可回滚的 WiX v4 打包链

- **状态**：**已废止（2026-09-25，被 ADR-017 取代）**——整条 WiX/MSI 打包链已删除，隔离输入 / 稳定身份 / 可回滚事务 / 发布门禁这四条要求由 ADR-017 在 setup exe 上重新实现（INVARIANTS E7–E10 同步改写）。
- **背景**：从共享 `bin\Release` 收集文件会混入历史构建残留；全局 WiX 和随机 ProductCode 使同版本重建不可复现；ShellExtension 外部 EXE 自定义动作没有 rollback 时会在安装失败后留下损坏的 COM 状态。
- **决策**：WiX 4.0.6 用仓库 tool manifest 固定；EDR GUI/ShellExtension 构建到 installer 专用 staging；MSI 三段版本取自主 EXE FileVersion，ProductCode 按 `UpgradeCode + 版本` 稳定派生，文件组件 GUID 按规范化相对路径稳定派生；major upgrade 排在 `InstallInitialize` 后，COM 注册/反注册均配套 rollback；ICE validation 为发布硬门禁。
- **后果**：同版本重建保持产品身份，新版本自动触发 major upgrade；失败安装/卸载可恢复 ShellExtension 注册；`-SkipBuild` 只能复用 staging，`-SkipValidation` 产物只能用于本地诊断；正式分发仍需外部可信证书完成 Authenticode 签名。
- **被否**：扫描共享输出——无法证明包内容干净；每次随机 ProductCode——同版本可能形成重复产品注册；无 rollback 的 EXE CA——失败后注册表与文件状态不一致；依赖全局最新版 WiX——构建行为会随机器漂移。

## ADR-014 版本标签 ED/EDE 改为 EDN/EDR，产品自有程序集升 2.0.0.0

- **状态**：已定（2026-09-25，用户裁决）
- **背景**：标签沿革是 EM/EME → ED/EDE（见提交 `098121e`），"EDE" 既不表意也与产品名 `ExcelDiffEDR` 对不上；同时产品版本自 2018 年 `ver1.3.4` 起从未提升（HEAD 已领先 65+ 提交），MSI 版本与主 EXE 同源，导致同版本无法互相升级、产物与源码无法对应。
- **决策**：主版本标签 **EDE → EDR**（与 `ExcelDiffEDR` / `EDR_READ` / `Release-EDR` 一致），保底版标签 **ED → EDN**（N=NPOI，避免与 EDR 只差一字母时误读）。版本只升**产品自有、且被部署/安装链路消费**的三个程序集 —— `ExcelDiff.GUI`（主 EXE，MSI 版本源）、`ExcelDiff`（产品核心库）、`ExcelDiff.ShellExtension`（COM，进 MSI）—— 的 `AssemblyVersion` 与 `AssemblyFileVersion` 到 **2.0.0.0**；**vendored 上游库保持自身版本**（`FastWpfGrid 1.3.3.0`、`NetDiff 1.2.0.0`、`NetDiff.Test 1.2.0.0`，`WriteableBitmapEx.Wpf` 无版本属性）。MSI 版本随主 EXE 自动变为 2.0.0。
- **后果**：全仓标签字样一次性改名（`EDE` 137 处 + 独立 `ED` 104 处 = 241 处，按 ASCII 词边界统计——用 `\b` 会把紧贴中文的出现漏掉；覆盖文档/脚本输出/代码注释/harness 局部变量名），机械替换产生的同义反复（如 "EDR=EDR 主版本"）手改为 "EDR=ExcelDataReader 主版本" 等显式写法；版本机制不变（仍是 `AssemblyInfo.cs` 单一来源 + MSI 派生），本次只改落值。旧 git tag 保留不动。
- **被否**：① 六个程序集全部统一 2.0.0.0 —— 我一度按"全部修改"这么做过，被用户驳回：FastWpfGrid / NetDiff 有各自的库版本身份（NetDiff 还带对外包 `Diff4Net` 的 nuspec），跟产品版本绑死会丢掉"这颗 DLL 是哪一版上游库"的信息；② 只改文档不改代码注释/变量名 —— 同一事实两处口径，后续会话仍会看到混用；③ 保留 ED/EDE —— "EDE" 无表意且与产品名不一致，改名成本只会随提交数继续上升。
- **刻意未改**：`NetDiff/NetDiff/NetDiff.nuspec` 的 `<version>1.2.0</version>`（对外包 `Diff4Net` 自己的发布标识）；`ExcelDiff.Installer.vdproj`（ED 时代废弃安装包，`ProductName=ExcelDiff`、`ProductVersion 1.3.4` 与冻结的依赖快照，且仍挂在 `ExcelDiff.sln` 里 —— 建议后续从解决方案移除并删文件）；FastWpfGrid 的 `FastWpfGridTest` / `FastWpfGridSyncTest` / `FastWpfGridUnitTest` 三个工程 `1.0.0.0`（上游自带示例/测试，不在 `ExcelDiff.sln` 内）；`app.manifest` 的 `version="1.0.0.0"`（VS 模板默认值，`name="MyApplication.app"`，不承载产品版本）。
- **后续（2026-09-25，ADR-017）**：`ExcelDiff.Installer.vdproj` 连同 `ExcelDiff.sln` 里的条目已随 MSI 链一并删除，上面那条"建议移除"已执行；本 ADR 的版本口径结论仍然有效，只有被点名的 vdproj 不再存在。

## ADR-015 CLI 接受裸位置文件参数，归一化在解析前单点完成

- **状态**：已定（2026-09-25，用户裁决"设计可行就直接改代码"）
- **背景**：外部工具（Fork 的 External Diff Tools）调用要写 `diff -s "$REMOTE" -d "$LOCAL"`，希望简化成 `"$REMOTE" "$LOCAL"`。**实测**（反射驱动构建产物内的真解析器，CommandLine 2.9.1）：`CommandLineOption` 只有一个位置槽 `Value(0)`（命令词），所以 `diff A B` 被判为**解析成功并静默丢弃** A/B（`Parsed=True Src=[] Dst=[]`）；`A B` 则把 A 当命令词，`Enum.Parse` 抛 `ArgumentException`（非 `ExcelDiffException`），绕过 `Invalid argument.` 友好路径，落到 `CurrentDomain_UnhandledException` 的 `Execute external command?` 框 + `Exit(-1)`。空 Src/Dst 的后果（左右两张空表、无任何提示）按 `DiffViewModel.cs:221-256` 的 `File.Exists("")` 分支推得，未实跑 UI。
- **决策**：不放宽 DTO，在 `CommandLineParser` **之前**加纯函数 `CommandLineArguments.Normalize`：首参命中 `CommandType` 名（忽略大小写）→ 命令词；值选项 `-s/-d/-c/-e`（含长名）连同其值、开关 `-i/-w/-v` 按原序保留；其余不认识的 `-` 开头 token 原样透传（`--help` / `--version` / `--startup` 仍由解析器裁决）；剩下的位置参数按序改写成 `-s` / `-d`。多于两个位置参数、位置参数与显式 `-s`/`-d` 混用、空 token、值选项缺值 → 一律抛既有 `ExcelDiffException(true, "Invalid argument.\nargument:\n…")`。接入点两处：首实例 `CreateCommand` 与远程转发 `TryParseOption`，**两条入口必须过同一函数**。
- **后果**：`exe A B`、`exe diff A B`、`exe -s A -d B`、`exe -s A`（右键菜单单文件用法）等价可用；原先可用的写法归一化后 token 序列不变（20 组参数矩阵实测，含 Mercurial 全串与含空格路径）。复用现有错误文案，不新增 UI 字符串 → 不触发 resx/lang 再生成。"写错就静默空白"这一类失败换成显式报错。代价是位置参数只认两个、且首参恰为命令词时按命令解释：名为 `diff` 的相对路径文件会被吃掉，difftool 场景（绝对临时文件路径）不可能命中，README 已写明该规则。
- **被否**：① 只改文档、继续要求写全 `diff -s -d` —— 保留了"少写一个 `-d` 就静默出空表"的陷阱；② DTO 里加 `[Value(1)]/[Value(2)]` 并让 `Command` 兼任左表 —— 需要"这个 token 是命令还是路径"的推断，且 `-s A B`（漏 `-d`）仍会静默变成错误的单侧对比；③ 归一化放进 `DiffCommand.ValidateOption` —— 远程转发路径 `RouteCommand` 不调 `ValidateOption`，两条入口会分叉（首次调用创建常驻、后续调用转发，语法不一致）。

## ADR-016 移除 `-k` / `--keep-file-history`，最近文件改为恒常记录

- **状态**：已定（2026-09-25，用户裁决"-k 去除功能和参数；等待后续统一更新 README"）
- **背景**：`-k` 的长名与行为正好相反 —— `DiffView.xaml.cs` 的判据是 `if (!App.Instance.KeepFileHistory) UpdateRecentFiles(...)`，即"传了 `-k` 就不记录"，而名字读作"保留历史"。裁决是整条去除，而不是改个名继续留着。
- **决策**：删除整条链，不留兼容别名、不加替代开关 —— `CommandLineOption` 的 `[Option('k', "keep-file-history")]` 属性、`App.KeepFileHistory` 转发属性、`DiffView` 的条件判断（改为无条件记录）、`CommandLineArguments.SwitchOptions` 里的 `-k`。README.md / README.en 的选项表、Git difftool 与 Mercurial 示例同步去掉 `-k`。
- **后果**：最近文件表无条件写入（上限 20 条，`App.UpdateRecentFiles`），difftool 场景会把 Fork/git 的临时路径灌进历史并挤掉真实记录 —— 这是本次裁决明确接受的代价。仍在参数里带 `-k` 的外部工具配置会立刻拿到 `Invalid argument.` 弹窗（`-k` 退化为未知选项，由解析器裁决），而不是被静默忽略；本机 `~/.gitconfig` 实测只有 `[user]` 段，故 git 侧无受影响配置，Fork 条目需使用者自查。
- **被否**：① 改名 `--no-file-history` 保留等价能力 —— 裁决是去除功能而非修正命名，留着开关就还得维护"名字与方向"的第二处真值；② 参数保留但变成 no-op —— 对外承诺一个不再兑现的选项，比直接报错更难排查。

## ADR-017 安装程序改为自研 WPF setup exe，删除整条 MSI/WiX 链

- **状态**：已定（2026-09-25，业主裁定"不要用 MSI 的方案了，用 exe 的构建方案吧，把整个 MSI 的构建方案全部删掉"）
- **背景**：需求是"向导第一步选语言，默认按机器显示语言"。实测该要求在 MSI 里物理不可实现：界面语言由数据库代码页与 `String` 表决定，二者在 `wix build -culture` 时烘死，`.mst` 语言转换也在 `msiexec` 打开库、第一个对话框画出来之前就选定；钉住的 `WixToolset.UI.wixext 4.0.6` 内嵌 wixlib 解包后 `Language`/`Rtg`/`LCID`/`SelectLanguage` 命中数为 0，28 个对话框中没有语言对话框，295 个控件里**没有任何 ComboBox**；带语言下拉的 Burn 需要 `WixToolset.BootstrapperApplications.wixext`、`WixToolset.Util.wixext`、`WixToolset.BootstrapperCore.dll`，本机三者都不存在且这台机器连不上 GitHub（Inno/NSIS 同样未安装）。
- **决策**：删除 `ExcelDiffEDR.Installer.wxs`、`Build-Installer.ps1`、`SrmRegistrar/`、`ExcelDiff.Installer.vdproj`、`.config\dotnet-tools.json` 以及文档/不变量里的 MSI 口径，改为 `ExcelDiff.Installer` WPF 工程产出单个 `ExcelDiffSetup.exe`：应用载荷打成 zip 以 manifest resource 内嵌（`EmbeddedResource` 带 `Condition="Exists(...)"`，无载荷时工程仍可编译，不污染 `verify.ps1`）；页面为 语言 / 位置与组件 / 确认 / 进度 / 完成；COM 注册用 `/shell-op:` 子进程；删除按 `install-manifest.txt`；重装是"移动旧目录 + undo 栈回滚"；`AI_Script\verify-installer.ps1` 取代 `wix msi validate` 成为发布门禁。程序侧配套改掉 `ApplicationSetting` 两处硬编码（无条件 `Culture = "zh-CN"`，以及每次启动都按 `startOnBoot = true` 重写 HKCU Run），改为读 setup 写在 `HKLM\SOFTWARE\ExcelDiffEDR` 的 `SetupCulture` / `SetupStartOnBoot` 种子。
- **后果**：语言页成为可能且立即生效（实测本机中文默认，当时窗口标题 `ExcelDiff 安装向导`，2026-09-26 名称统一后为 `ExcelDiffEDR 安装向导`）；离线可构建、零外部工具依赖。代价是安装器语义从此由本仓库自己承担：升级、卸载、回滚、提权、杀软与 SmartScreen 对未签名 exe 的拦截都要自己测；失去 Windows Installer 的 ICE 校验与 `msiexec` 的企业分发语义。实测记录：`verify-installer.ps1 -Install` 由 50 项扩到 **88 项 / A–K 十一个真实用例**全绿（含"占住旧主 EXE 再安装 → 安装失败且旧安装完好""目标目录安装前已存在且中途失败 → 目录内无关文件仍在""无 `/dir` 且注册表被清 → 拒绝卸载，绝不回落到默认目录""装好后删掉 `install-manifest.txt` → 卸载返回 1 且文件与 HKLM 记录俱在，把清单放回则返回 0""盘符根目标 `/dir=Q:\` 与 `/dir=Q:` 返回 1 且不写注册表"）；产品版本按裁定保持 2.0.0.0，因此同版本再安装语义上是"重装"而不是"升级"。
- **裁定追加（2026-09-26）**：① 用户可见名**全统一为 `ExcelDiffEDR`**（ARP / 开始菜单 / 右键菜单 / 向导与程序文案 / 注册表键），仅保留 git 配置里用户自写的 `[difftool "ExcelDiff"]` 标签与 EDN 历史名；② 卸载**默认保留**当前用户的 `%APPDATA%\ExcelDiffEDR.GUI`，清理改为显式 opt-in（`/clearsettings` 或向导复选框），取代此前"卸载时清理配置"的口径。
- **本轮踩到的三个坑（已进门禁）**：首轮的另一对坑 —— 进程内 `LoadFrom` 锁死扩展 DLL 导致卸载残留、`/dir="…\"` 结尾反斜杠被解析成转义引号 —— 仍记在 AGENTS §4；下面是后面的三个。① 命令行解析失败时按 `options.Silent` 决定弹不弹窗，而 `/silent=1` 这类非法写法本身就让 `Silent=false` → 脚本调用被模态框挂死（实测 10 分钟无退出）。拒绝路径从此只写日志 + 退出码 `4`，一律不弹窗；`RunSetup` 增加 180s 超时，"弹了窗"会变成一条具名 FAIL 而不是无限等待。② `Get-ChildItem -LiteralPath … -Include` 的 `-Include` 实际被忽略（实测把 `.pdb`/`.exe`/`obj` 全列进来），所以"产物比源码新"的断言必须手写扩展名过滤，否则测的是构建产物自己的时间戳。③ 目录校验写成"先 `Path.GetFullPath` 再问 `Path.IsPathRooted`"，于是那条相对路径分支**永远走不到**（反射实测：`Tools` → 仓库目录下、`..\Tools` → 仓库外、`C:Tools` → `C:\Tools`，全都被"接受"），而双语 `err.badTarget` 早已向用户承诺拒绝相对路径 —— 是代码没兑现文案，不是文案写错。改为在 `GetFullPath` **之前**判定调用方写下的原文（`X:` + 分隔符，或 UNC `\\server\share\`；裸 `X:`/`X:Tools` 属驱动器相对，不算绝对），并把这道校验上移到 `Options.Parse`，坏形态返回 `4` 而不是抛异常掉到 `1`，因为它属于命令行参数问题、且不该在触盘之后才发现；实测由 K 用例覆盖。
- **被否**：① 单 MSI + 第一页语言按钮 —— 后续内置页仍是构建期语言，产出半翻译向导；② `wix msi transform` 做多语言 MST —— 语言转换改不了代码页、WiX 没有声明转换的元素、需构建后用 COM 回写 SummaryInformation 且会打乱 E10"validate 是最后一步"的顺序，未经证实；③ 极小启动器 exe 探测语言再拉起对应 MSI —— 确实满足"机器决定"，但多一个签名对象与自制引导器的长期维护面；④ 升 WiX 大版本换 Burn —— 需要联网，且是整条打包链与 wxs schema 的重写，属独立 ADR；⑤ MSI 链保留、另加一套 exe 安装包 —— 两个安装包各存一份安装身份，违背"一个事实一个归属层"。
