# ADR — 架构决策记录（Architecture Decision Records）

> 记录关键决策的**约束、结论、后果**，避免后续对话重开争论。
> 每条约：状态 / 约束（为什么是这个方案）/ 决策 / 后果。落选路线不再记录。
> 已被取代的条目只留一行去向；**编号与标题保留**，因为 INVARIANTS / ARCHITECTURE / AGENTS 按编号交叉引用。

## ADR-001 双版本 EDN/EDR 用条件编译而非分支

- **状态**：已被 ADR-019 取代。仓库里没有版本类条件编译，也没有第二套读取实现。

## ADR-002 EDR（ExcelDataReader）为主版本，EDN（NPOI）保底对照

- **状态**：已被 ADR-019 取代。ExcelDataReader 是唯一读取实现，NPOI 不在工程里，"保底对照"这个概念同时不存在。

## ADR-003 单实例 + 命名管道 IPC + 托盘常驻

- **状态**：已定
- **约束**：作 Git difftool 时每次 diff 都会启动新进程；多次 diff 要复用常驻进程快速响应。
- **决策**：`Mutex` 判单实例；首个实例驻留托盘并起命名管道 server；后续进程转发 CLI 参数后立即退出；channel id 由 exe 名派生，于是不同程序集名互不串台。
- **后果**：管道线程必须非阻塞（INVARIANT C1）；转发进程退出即走（C4）。常驻的完整性级别要与桌面一致（AGENTS 陷阱 §8.8）。

## ADR-004 外置 JSON 本地化（可热替换）

- **状态**：已定
- **约束**：使用者要能自行改中文翻译，不等发新版。
- **决策**：`lang\<culture>.json` 外置在 exe 目录（自研 JSON 解析器，零第三方依赖）；`Resources.Designer.cs` 桥接 `LocalizationManager.GetString`，缺键回落编译期资源。
- **后果**：改字符串要改 resx + 跑 `GenerateLangJson.ps1`（INVARIANT D2）；JSON 必须 UTF-8（D3）。

## ADR-005 语言切换=关窗+下次命令重建

- **状态**：已定
- **约束**：`{x:Static Resources.*}` 在 XAML 加载时固化，切换语言必须重建所有已加载窗口；而重建窗口会同步重跑整个 diff，冻结 UI。
- **决策**：语言变更时 `CloseMainWindowForLanguageChange()` 立即关窗（`IsClosingMainWindow` 放行 `OnClosing`），下次 diff 命令新建窗口即用新语言。
- **后果**：切换语言后需重新发起对比（INVARIANT D4）。

## ADR-006 窗口状态持久化到 YAML 设置

- **状态**：已定
- **约束**：difftool 高频使用，位置/大小/最大化要跨会话、跨重启保持。
- **决策**：`WindowLeft/Top/Width/Height/WindowState` 存入 `ApplicationSetting`（YAML）；最大化时保存 `RestoreBounds`；移动/缩放 600ms 去抖保存；启动 Show 后延迟应用最大化（防错位）。
- **后果**：窗口首次 Show 前的几何访问要防御 `double.NaN` / 虚拟屏越界（`MainWindow.xaml.cs` 的 `RestoreWindowState`）。设置写入必须原子（INVARIANT C7）。

## ADR-007 并行读取工作簿

- **状态**：已定
- **约束**：大文件打开慢，而 src/dst 读取彼此独立。
- **决策**：`ReadWorkbooks` 内 `Task.Run` ×2 并行读，结果回 UI 线程组装。
- **后果**：读取层必须线程安全（`ExcelWorkbook.Create` 是纯函数，无共享状态）；`#if PERF_TIMING` 注入分段计时。

## ADR-008 自定义 NoDiffWindow 替代 MessageBox

- **状态**：已定
- **约束**：无差异提示要区分"仅关提示"与"连对比窗口一起关"两种关闭语义，MessageBox 表达不了；IPC 场景下还要能被远程命令强关。
- **决策**：自绘模态窗 `NoDiffWindow`：ESC=仅关提示；红色退出按钮（`IsDefault`，回车触发）=连对比窗口一起关；`DismissModalWindows` 可强关。
- **后果**：`NotifyEqual` 分支用 `ShowDialog` 并持有引用供强关（DiffView.xaml.cs:588）。

## ADR-009 ESC 用 Win32 WndProc 钩子处理

- **状态**：已定
- **约束**：焦点移到非输入面板后，WPF 路由键事件不再送达窗口，ESC 处理不可靠。
- **决策**：`MainWindow.OnSourceInitialized` 挂 `HwndSource.AddHook(WndProc)`，在消息级处理 ESC：下拉框/菜单打开时让路，输入控件聚焦时先移焦点，否则隐藏到托盘（`RunInBackground=false` 时才 `Close()`）。
- **后果**：与 `NoDiffWindow` 自己的 ESC 处理共存（NoDiff 用 `PreviewKeyDown`，职责分离）。

## ADR-010 EditGraph 不重写，用 Limit 前沿守卫兜底

- **状态**：已定
- **约束**：`EditGraph` 是 Myers 启发式 BFS，最坏 O(D²) 节点分配（病态"两表几乎全不同"时 1 万行 ≈ 10⁸ 节点 → OOM/冻结）。经典 Myers V-array 重写可降到 O((N+M)D)。
- **决策**：**不重写算法**，在 `ExcelSheet.Diff` 行级 diff 调用处设 `option.Limit = 2000`（复用现有 beam 截断）：前沿超阈值后保留单路径，退化为 O(D) 快速搜索，结果有效但可能非最小。正常差异（数百行变更）前沿远低于阈值，路径不变。
- **后果**：31 个 NetDiff 测试（编码当前路径平局规则，尤其 `CaseMultiSameScore_*`）不被破坏；病态输入 2 秒内完成。若真出现"几乎全不同大表"的崩溃报告，再走"独立分支 + 差分 oracle（新旧算法跑随机输入比对 `CreateSrc`/`CreateDst` 还原）"路线重写。核心算法处的注释按既有约定保留。

## ADR-011 提权部署禁止 `-Wait`

- **状态**：已定
- **约束**：`Start-Process powershell -Verb RunAs -Wait` 在 UAC 提权 + msbuild 子进程场景下不返回，调用方卡到超时（部署实际 10-30 秒就完成了）。
- **决策**：提权启动**不带 `-Wait`**（fire-and-forget），轮询提权脚本写出的日志出现 `DONE` 后再继续；随后杀进程、部署、`--startup` 重启常驻。
- **后果**：部署命令秒回、不挂起。写 `Program Files` 需提权，所以部署脚本必须输出日志供轮询（INVARIANT F4）。

## ADR-012 EDR 成为唯一构建/部署/门禁目标，EDN 代码保留退出日常流程

- **状态**：已被 ADR-019 取代。"唯一构建 / 部署 / 门禁目标"这条结论保留；被保留的 EDN 代码本身已不存在。

## ADR-013 EDR MSI 使用隔离、确定且可回滚的 WiX v4 打包链

- **状态**：已废止，被 ADR-017 取代。它的四条要求——隔离输入 / 稳定身份 / 可回滚事务 / 发布门禁——现在由 setup exe 实现（INVARIANTS E7–E10）。

## ADR-014 版本标签 ED/EDE 改为 EDN/EDR，产品自有程序集升 2.0.0.0

- **状态**：已定
- **约束**：只有**产品自有、且被部署/安装链路消费**的程序集才该跟随产品版本；vendored 上游库有自己的版本身份（`NetDiff` 还带对外包 `Diff4Net` 的 nuspec），跟产品版本绑死就会丢"这颗 DLL 是哪一版上游库"的信息。
- **决策**：版本落值 **2.0.0.0** 只覆盖 `ExcelDiff.GUI`（主 EXE，setup 版本源）、`ExcelDiff`、`ExcelDiff.ShellExtension`、`ExcelDiff.Installer`（按 E8 与主 EXE 对齐）。`FastWpfGrid` / `NetDiff` / `NetDiff.Test` / `WriteableBitmapEx.Wpf` 保持自身版本，**不随产品升版**。版本单一来源是各工程的 `AssemblyInfo.cs`。
- **刻意未改**：`NetDiff/NetDiff/NetDiff.nuspec` 的 `<version>`（对外包 `Diff4Net` 自己的发布标识）；FastWpfGrid 的 `FastWpfGridTest` / `FastWpfGridSyncTest` / `FastWpfGridUnitTest` 三个工程（上游自带示例/测试，不在 `ExcelDiff.sln` 内）；`app.manifest` 的 `version="1.0.0.0"`（VS 模板默认值，`name="MyApplication.app"`，不承载产品版本）。旧 git tag 不动。
- **后果**：口径见 INVARIANTS E12。

## ADR-015 CLI 接受裸位置文件参数，归一化在解析前单点完成

- **状态**：已定
- **约束**：外部 difftool 想写 `"$REMOTE" "$LOCAL"` 这种最短形态。而 `CommandLineOption` 只有一个位置槽 `Value(0)`（命令词），所以裸文件参数要么被"解析成功并静默丢弃"（`diff A B` → `Parsed=True Src=[] Dst=[]`），要么把首参当命令词去 `Enum.Parse` 抛 `ArgumentException`，绕过 `Invalid argument.` 友好路径落到"是否执行外部命令"的框再 `Exit(-1)`。（取证手法：反射驱动构建产物里的真解析器，CommandLineParser 2.9.1。）
- **决策**：不放宽 DTO，在 `CommandLineParser` **之前**加纯函数 `CommandLineArguments.Normalize`：首参命中 `CommandType` 名（忽略大小写）→ 命令词；值选项 `-s/-d/-c/-e`（含长名）连同其值、布尔开关按原序保留；选项名与"是否带值"由 `CommandLineOption` 的属性**反射派生**，不手写第二份名单；内联写法只接受 `=` 且必须带非空值（`:` 与"开关赋值"拒绝）；其余不认识的 `-` 开头 token 原样透传（`--help` / `--startup` 仍由解析器裁决）；剩下的位置参数按序改写成 `-s` / `-d`，且不与显式 `-s`/`-d` 混用。多于两个位置参数、混用、空 token、值选项缺值 → 一律抛既有 `ExcelDiffException(true, "Invalid argument.\nargument:\n…")`；参数值的路径合法性在归一化末尾判掉。**两条入口（首实例与远程转发）必须过同一函数。**
- **后果**：`exe A B`、`exe diff A B`、`exe -s A -d B`、`exe -s A`（右键菜单单文件用法）等价可用；既有写法归一化后 token 序列不变（参数矩阵实测含 Mercurial 全串与含空格路径）。帮助文本由同一批属性生成（`DescribeOptions`），不再有第二份说明。复用现有错误文案，不新增 UI 字符串 → 不触发 resx/lang 再生成。"少写一个 `-d` 就静默出空表"换成显式报错。代价：位置参数只认两个，且首参恰为命令词时按命令解释——名为 `diff` 的相对路径文件会被吃掉，difftool 场景（绝对临时文件路径）不可能命中，README 已写明该规则。常驻收到坏参数只弹可见提示、不退出（INVARIANT C6）。

## ADR-016 移除 `-k` / `--keep-file-history`，最近文件改为恒常记录

- **状态**：已定
- **约束**：`-k` 的长名与行为方向相反——判据是"传了 `-k` 就不记录"，而名字读作"保留历史"。裁定是整条去除，而不是改名继续留着。
- **决策**：这个选项现在**不存在**：`CommandLineOption` 里没有对应属性，`App` 没有转发属性，`DiffView` 无条件记录最近文件，两份 README 的选项表与 Git / Mercurial 示例里也没有它。不留兼容别名，不加替代开关。
- **后果**：最近文件表无条件写入（上限 20 条，`App.UpdateRecentFiles`），difftool 场景会把 Fork/git 的临时路径灌进历史并挤掉真实记录——这是明确接受的代价。仍在参数里带 `-k` 的外部工具配置会立刻拿到 `Invalid argument.` 弹窗（退化为未知选项，由解析器裁决），而不是被静默忽略；使用者自己的 git / Fork 配置需自查。

## ADR-017 安装程序改为自研 WPF setup exe，删除整条 MSI/WiX 链

- **状态**：已定
- **约束**：需求是"向导第一步选语言，默认按机器显示语言"。这在 MSI 里物理不可实现：界面语言由数据库代码页与 `String` 表决定，二者在 `wix build -culture` 时烘死，`.mst` 语言转换也在 `msiexec` 打开库、第一个对话框画出来之前就选定；`WixToolset.UI.wixext 4.0.6` 内嵌 wixlib 解包后 `Language`/`Rtg`/`LCID`/`SelectLanguage` 命中数为 0，28 个对话框里没有语言对话框，295 个控件中**没有任何 ComboBox**；带语言下拉的 Burn 需要 `WixToolset.BootstrapperApplications.wixext`、`WixToolset.Util.wixext`、`WixToolset.BootstrapperCore.dll`，本机三者都不存在且离线取不到（Inno/NSIS 同样未安装）。
- **决策**：`ExcelDiff.Installer` WPF 工程产出单个 `ExcelDiffSetup.exe`：应用载荷打成 zip 以 manifest resource 内嵌（`EmbeddedResource` 带 `Condition="Exists(...)"`，无载荷时工程仍可编译，不污染 `verify.ps1`）；页面为 语言 / 位置与组件 / 确认 / 进度 / 完成；COM 注册用 `/shell-op:` 子进程；删除按 `install-manifest.txt`；重装是"移动旧目录 + undo 栈回滚"；发布门禁是 `AI_Script\verify-installer.ps1`。程序侧配套：`ApplicationSetting` 不硬编码语言，也不再每次启动无条件重写 HKCU Run，而是读 setup 写在 `HKLM\SOFTWARE\ExcelDiffEDR` 的 `SetupCulture` / `SetupStartOnBoot` 种子。仓库里没有任何 `.wxs` / `vdproj` / tool manifest / MSI 构建脚本。
- **后果**：语言页成为可能且立即生效（向导标题 `ExcelDiffEDR 安装向导`）；离线可构建、零外部工具依赖。代价是安装器语义由本仓库自己承担：升级、卸载、回滚、提权、杀软与 SmartScreen 对未签名 exe 的拦截都要自己测；失去 Windows Installer 的 ICE 校验与 `msiexec` 的企业分发语义。同版本再安装的语义是"重装"而不是"升级"。命名与配置口径：用户可见名一律 `ExcelDiffEDR`（ARP `DisplayName`、开始菜单、右键菜单文字、向导与程序文案、注册表键），唯一例外是写在用户 git 配置里的 `[difftool "ExcelDiff"]` 标签；卸载**默认保留** `%APPDATA%\ExcelDiffEDR.GUI`，清理是显式 opt-in（`/clearsettings` 或向导复选框）。

### 进门禁的三条机制（都有先红后绿的用例）

1. **命令行解析失败时不许按 `options.Silent` 决定弹不弹窗**：`/silent=1` 这类非法写法本身就让 `Silent=false`，于是脚本调用被模态框挂死（实测 10 分钟无退出）。拒绝路径只写日志 + 退出码 `4`，一律不弹窗；`RunSetup` 带 180s 超时，"弹了窗"变成一条具名 FAIL 而不是无限等待。
2. **`Get-ChildItem -LiteralPath … -Include` 的 `-Include` 会被忽略**（实测把 `.pdb`/`.exe`/`obj` 全列进来），所以"产物比源码新"这类断言必须手写扩展名过滤（现在是 `.cs/.xaml/.txt/.csproj/.manifest`），否则测的是构建产物自己的时间戳。
3. **目录形态校验必须看调用方写下的原文、在 `Path.GetFullPath` 之前**：先解析再问 `IsPathRooted` 永远为真，相对值会静默落到进程的工作目录（反射实测：`Tools` → 仓库目录下、`..\Tools` → 仓库外、`C:Tools` → `C:\Tools` 全被"接受"），而 `err.badTarget` 双语文案早已承诺拒绝相对路径——是代码没兑现文案。现在这道校验在 `Options.Parse` 层，坏形态返回 `4` 而不是抛异常掉到 `1`，且不触碰机器；盘符根与 UNC 分享根由 `ValidateTargetDir` 的两条**不重叠**判据各抓一半（`C:\` 靠"补分隔符"那半，UNC 分享根因为 `GetFullPath` 不给它加分隔符，只有 `root == full` 那半能拒），所以 K 用例专门钉一条 `/dir=\\server\share` 返回 4。

## ADR-018 安装目录内的产物改名为 Uninstall.exe，控制面板卸载走交互向导

- **状态**：已定
- **约束**：ARP 的 `UninstallString` 与 `QuietUninstallString` 若同串（都带 `/silent`），控制面板点卸载就全程无界面、无确认，也没有决定是否删用户配置的入口；而目录里那个入口若叫 `ExcelDiffSetup.exe`，双击进的是**安装**向导，会把用户自己的安装目录整体改名挪走重装——可发现性坏，且方向反了。
- **本机对照（口径可复现，换机器数字会变）**：遍历 `HKLM\...\Uninstall` 与 `...\WOW6432Node\...` 两个视图、只算带 `DisplayName` 的条目 → 309 条，其中 `UninstallString` 指向 `.exe` 的 125 条（即"非 MSI 且自带卸载程序"的分母）；这 125 条里卸载器文件名含 `uninst` 的 29 条、提供 `QuietUninstallString` 的 28 条。开始菜单 `CommonPrograms` + 用户 `Programs` 两棵树共 134 条 `.lnk`，名字含 "Uninstall"/"卸载" 的 12 条。取证坑：`Get-ChildItem -LiteralPath '...\Uninstall\*'` 的 `*` 被当字面量（实测返回 0 条），必须 `Test-Path` 后用不带通配符的 `-LiteralPath` 取子键。
- **决策**：① `ProductInfo.UninstallerName = "Uninstall.exe"`，目录里只此一份（进清单）；② 角色由**文件名**决定，优先级 显式 `/uninstall` > 显式 `/install` > argv[0] 文件名 > 安装，`/shell-op:` 子进程与 `%TEMP%` 转发副本不做名字推断；③ `UninstallString` 不带 `/silent`（交互向导：语言页 → 确认页 → 进度 → 完成，清配置的复选框只在向导上生效），`QuietUninstallString` 带 `/silent`；④ 卸载模式补语言页、标题 `app.uninstallTitle`、确认页摘要只列版本/目录/语言/是否清设置、完成页说明配置目录留/删；⑤ ARP 写在所有**可失败**的写操作之后、`manifest.Save()` 之前（清单最后落盘，否则一次失败的回滚会把"已装好"的清单留在盘上），并有 `RegistryStore.SnapshotArp/RestoreArp` 兜底——它不在 undo 栈里，因为栈里那条 `ClearRegistry()` 会连整棵 ARP 一起删掉，必须在回滚完成之后再执行。产物文件名不受"用户可见名一律 `ExcelDiffEDR`"的口径约束。
- **硬机制（四条，均已进门禁）**：
  1. **跨 `%TEMP%` 转发时角色必须以显式开关携带**——转发把镜像复制成 `ExcelDiffSetup-<guid>.exe`，名字判定随之失效；不补 `/uninstall` 时子进程按安装角色走（用例 L 当场红）。
  2. **从安装目录内发起的卸载是移交式的**——父进程正跑着子进程要删的那个映像，`WaitForExit` 等于把它锁住，症状是"主 exe 删掉了、目录和注册表还在、退出码 1"（`remaining>0` 走拒绝分支，注册表按 E9 保留）。所以 `Process.Start` 后立即返回专属码 `100`（语义"已移交"，`0` 只代表真做完），临时副本自身用 `MoveFileEx(..., DELAY_UNTIL_REBOOT)` 登记删除；门禁 L/M 因此**轮询效果**（`WaitForGone`/`WaitForGoneKey`）而不是信退出码。
  3. **移交的用例必须另外断言"转明确实发生了"**——父进程的移交码会替一个立刻失败的子进程背书（漏掉 `/log:` 前缀时子进程按未知开关返回 4，目录与注册表原地不动而父进程照样报移交）。只查最终效果分不清"没转发"与"转发后子进程失败"，所以 D 用例同时要求只有转发才会新建的 `*.relay.log` 与恰好一个 `.old-*` 备份。
  4. **转发前父进程要 `Directory.SetCurrentDirectory(%TEMP%)`，子进程的 `WorkingDirectory` 要显式给**——双击进来的进程 CWD 就是安装目录，`UseShellExecute=false` 的子进程默认继承它（实测 `cmd /c cd` 打印出父进程目录），而活动进程的当前目录既删不掉也 `Move` 不走（实测 `Directory.Delete` 报"正在被另一个进程使用"），症状是"文件全删、`TryDeleteEmptyDir` 静默 warn、仍报成功，Program Files 里永久留下一个空目录"。从仓库根 `Start-Process` 时 CWD 从来不是安装目录，所以工作目录本身要当被测形状传进去（L/M/D 都传）。
- **后果**：卸载入口与主流一致，并新增两条以前没被覆盖的路径进门禁——L（**从安装目录里**只带 `/silent` 跑 `Uninstall.exe`，端到端卸干净）与 M（**照 ARP 存的命令串原样执行**，串里没有 `/dir`，走 `ResolveUninstallDir()` 读 HKLM 记录的分支）。两条的覆盖口径要分清：`/dir` 缺失的读记录分支 L 与 M 都命中，M 独有的是"串本身拼得对不对"（引号、路径、开关）；**交互式 `UninstallString` 只有形状断言**（A 查值），执行覆盖只能人工做，清单在 AGENTS §4。代价：重装入口变成"重新下载安装包或显式带 `/install`"，目录里不再有安装器命名的文件（`finish.noshell`、`err.noUninstallTarget` 文案同步）。当前门禁规模：**A–O 十五个用例 / 139 项断言**（静态检查另计）。反向证伪的做法要留着：临时注释掉第 4 条那两行重跑，门禁会红在 D（重装返回 1、载荷未被重写、无 `.old-*`）与 L/M（目录 90 秒后仍在）；加判据时同理，先让它红一次。

## ADR-019 删除 EDN 变体与 NPOI，EDR 成为唯一版本

- **状态**：已定
- **取代**：ADR-001（条件编译双版本）、ADR-002（EDR 主 / EDN 保底）、ADR-012（EDN 代码不得移除）、ADR-014 里的 EDN 标签；INVARIANTS A 区与 B1/B3/B4 按这个口径写。
- **约束**：保住 EDN 的理由一直是"EDR 盲区兜底 + 对照基准不可失去"。动手前实测：兜底手段 `ExcelWorkbook.VerifyRead` 与 `CreateUsingNpoi` 在整个仓库里**没有任何调用方**（只有文件内部自引用），也就是说那份"保底对照"从来没接进任何流程——保住的是要走手工构建才存在的路径，不是真在用的保险。另一侧代价是实打实的：双变体让每个改动都要考虑条件编译矩阵，载荷里常年背着 4 个 NPOI dll 加 2 个传递依赖。
- **决策**：① 没有 `EdrRead` 属性，也没有 `NPOI_READ` / `EDR_READ` 条件编译，程序集名固定 `ExcelDiffEDR.GUI`，`DisplayName` / `AssemblyTitle` / HKLM 种子键（`SOFTWARE\ExcelDiffEDR`）不分分支；② 没有 NPOI 专用读取实现（`ExcelReader.cs`、`ExcelSheet.Create(ISheet,…)` 重载、`CreateUsingNpoi`、`VerifyRead` 都不存在）；③ **NPOI 依赖彻底退出**，它剩下的两处活用途换成无依赖实现：`ExcelWorkbook.GetSheetNames` 走**同一个 reader 枚举**（sheet 名单与 `Create` 的字典键同源），`ExcelUtility.CreateWorkbook`（差异一侧文件不存在时生成的空工作簿）**手写 OOXML 五个部件**；④ 只为 NPOI 存在的 `GetWorkbookTypeStrict` / `GetWorkboolTypeStrict` / `IsXLS` / `IsXLSX` 不存在；⑤ `DiffHarness` 是单变体确定性输出工具，仓库里没有双变体对照脚本；⑥ 门禁：`Build-Setup.ps1` 不过滤"EDN 三件套"，E7 改为断言这些库不得出现在成品载荷里（陈旧 bin 会活过重建，所以断言打在字节上）。**不许再引入第二条读取实现或版本开关**；需要时先开 ADR。
- **现状**：读取层只有 ExcelDataReader 一条路径；空工作簿由 `ExcelUtility.CreateWorkbook` 手写 OOXML；`GetSheetNames` 对 xlsx 走 zip 直读 `xl/workbook.xml`，其余扩展名用同一个 reader 枚举，csv/tsv 直接返回文件名并结束（`yield break` 在位，不会掉进枚举分支——这个缺陷曾在 csv/tsv 分支上炸出 `HeaderException`，`GetSheetNames` 的行列语义见 INVARIANTS B2）。
- **取证**（反射探针 + 一个临时控制台探针，对着构建出的 `ExcelDiff.dll` 跑 8 项）：sheet 名单一致性——4 个真实 xlsx 上 zip 直读与 reader 枚举**结果与顺序都相同**；真 .xls（BIFF8，本机 Excel 16 生成，两个 sheet `Alpha`/`Beta`）`GetSheetNames` 返回 `[Alpha|Beta]`、`Create` 拿到两个 sheet 3 行；手写空工作簿 1512 字节，自家 reader 读出 `[Sheet1]` 1 sheet 0 行，**再用真 Excel 打开同一个文件**确认 sheets=1 / name=Sheet1（不是只有我们自己读得动）；csv / tsv 分支正常。
- **后果**：读取层只有一条实现，也就**没有兜底读取器**——"仅样式无值单元格读不到 → 列漂移 → 漏报差异"这个固有盲区只能如实说明，或另开 ADR 去修读取层本身（INVARIANTS B3）。基准对比手段收窄为：NetDiff 单测 + harness 的确定性输出 + 拿 Excel 人工对照。工程侧收益：没有变体矩阵、没有条件编译、少 6 个第三方 dll；载荷 50 文件 / 7.5 MB，setup exe 2.8 MB。
