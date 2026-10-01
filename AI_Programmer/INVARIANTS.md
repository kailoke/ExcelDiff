# INVARIANTS — 工程硬约束清单

> 改动任何代码前逐条核对。**违反任一条 = 阻断提交/部署。**
> 来源：ARCHITECTURE.md、AGENTS.md、CODEX.md（各条标注出处）。

## A. 单一版本（EDR 是唯一版本）

- [ ] **A1 只有一个构建目标**：产品就是 `ExcelDiffEDR.GUI`（读取层唯一实现 = ExcelDataReader）。双版本机制已于 2026-09-30 整体移除（ADR-019）：`EdrRead` 属性、`NPOI_READ` / `EDR_READ` 条件编译、`ExcelDiff.GUI` 程序集名、NPOI 及其传递依赖都不许再被请回来 —— 需要第二种读取实现时另开 ADR，不要在源码里留影子。
- [ ] **A2 门禁即构建**：`AI_Script\verify.ps1` 编译的产品必须通过；不再有"主版本/保底版本"的区分，也没有只属于某个变体的手工构建路径。（AGENTS §4）
- [ ] **A3 身份仍按程序集名派生**：配置目录、IPC channel id、显示名继续从 exe 名派生（不要硬编码共享）。这条留着的理由不再是"两版隔离"，而是历史部署与用户配置目录（`%APPDATA%\ExcelDiffEDR.GUI`）都按这个名字绑定。（ARCH §7.8、CODEX 链路B）

## B. 读取层（核心库 ExcelDiff）

- [ ] **B1 读取层只有一条实现**：`ExcelWorkbook.Create` 对 xls/xlsx 走 ExcelDataReader，csv/tsv 走自研解析器。约 72% 的读取效率优势是当年选它的理由，也是现在唯一实现的前提。（ARCH §5、ADR-019）
- [ ] **B2 行列语义**：读取路径必须跳整空行、裁剪尾空单元格，每行的单元格列表止于最后一个有值的列 —— diff 的行/列对齐就建在这两条上。（ExcelWorkbook.cs 的 `CreateFromExcel`）
- [ ] **B3 已知盲区（无兜底，别再承诺兜底）**：ExcelDataReader 读不到"仅样式无值"的单元格 → 空列被吞 → 列对齐漂移 → 漏报真实变更。原先的"用 `VerifyRead` 双读 / EDN 保底对照"整条已随 NPOI 移除（实测：`VerifyRead`/`CreateUsingNpoi` 在删除前已无任何调用方，即那套兜底从来没接上过线）。现在遇到该场景只能如实告知用户，或另开 ADR 设计校验手段。（ARCH §9.6）
- [ ] **B4 回归比对（可选）**：`DiffHarness` 是单变体的 headless 输出工具；比对必须**严格用同名文件的 Unstaged（工作区）VS HEAD**，严禁跨文件对比。（AGENTS §7.4/§7.7）
- [ ] **B5 扩展名分发**：新增文件类型解析在 `ExcelWorkbook.Create` 里统一分发，CSV/TSV 保持自研零依赖。

## C. 生命周期 / IPC（GUI 高危区）

- [ ] **C1 IPC 非阻塞**：管道线程只能用 `Dispatcher.BeginInvoke` 投递，**绝不同步等待模态框**，否则模态框存在时死锁。（ARCH §6.4、AGENTS §8.4）
- [ ] **C2 事件分发器**：`*EventDispatcher.Instance` 是进程级单例；窗口真正关闭时必须 `DiffView.RemoveEventListeners()`，防泄漏/防派发到 `container==null` 的旧视图。（DiffCommand.cs:37）
- [ ] **C3 关窗语义**：`RunInBackground=true` → 关窗仅隐藏到托盘；`IsClosingMainWindow`（语言切换）→ 允许真正关；`ExitApplication` 置 `IsExiting` 后 `Shutdown`。（MainWindow.xaml.cs:122）
- [ ] **C4 转发进程不驻留**：对转发进程 `Start-Process -Wait` 会挂起（无常驻时转发器变常驻）。等待会话用 `AI_Script\Invoke-ExcelDiff.ps1`（fire-and-forget + 轮询窗口）；入库脚本由 `AI_Script\verify.ps1` 坑扫描自动拦截 `Start-Process ... -Wait ... ExcelDiff`。（AGENTS §8.3）
- [ ] **C5 模态强关**：远程命令生效前 `CurrentDiffView.DismissModalWindows()` 强关无差异等模态，再 `ShowMainWindow`。（App.xaml.cs:181-185）

## D. 本地化

- [ ] **D1 字符串唯一来源**：可见文本一律走字符串表（GUI：`Resources.*` 经 `LocalizationManager` 桥接；安装器：`Strings\*.txt` 由 `WizardWindow.ApplyTexts` 按 key 填），XAML 里不得写死。实测教训的方向要说对：`NoDiffWindow.xaml` 曾写死 `Text="确定"`，于是**英文态显示中文**（`4b71c9a` 改为 `{x:Static Resources.Word_OK}`，en=`OK`/zh=`确定`）。机械扫描在 `AI_Script\verify.ps1` 6b，扫整个 solution 的 `*.xaml`，抓两类字面量：**CJK/假名/全角**，以及**品牌名 `ExcelDiff*`**（名字的归属层是 `ProductInfo` 与字符串表，XAML 里复制一份会静默躲过改名；目前实测命中 0 处，这条是预防，不是已复现事故的回归测试）。扫描的已知盲区（别宣称更多）：`Style`/`Setter Value="…"`、附加或限定属性（如 `TextBlock.ToolTip=`）、跨行的属性值与跨行的元素文本；语言无关符号（`DiffView.xaml` 用箭头字形标快捷键按钮）有意不纳入。两表之间的**值**不一致（把英文写进 zh 表）不是字面量，现有门禁不查，只能靠 `verify-installer.ps1` 的键集/占位符比对与人工验收。（AGENTS §10 / §4 / §7.2）
- [ ] **D2 resx→json 再生成**：改 `Resources*.resx` 后必须跑 `GenerateLangJson.ps1` 再生成 `lang\*.json`，二者保持同步（构建期 `CopyLangFiles` 自动部署，但生成是人工/脚本步骤）。（AGENTS §7.2）
- [ ] **D3 非 ASCII 编码**：改写含中文/日文的 YAML/JSON/resx 用文件写入工具（UTF-8 无 BOM）或 `[System.IO.File]::WriteAllText` + 显式 UTF8；PowerShell 5.1 `Set-Content -Encoding UTF8` 会按 ANSI 破坏。（AGENTS §8.1）
- [ ] **D4 语言切换**：`{x:Static}` 在 XAML 加载时固化 → 语言变更通过"关窗+下次命令重建"生效，不要试图热替换已加载窗口的静态资源。（App.xaml.cs:327-332）
- [ ] **D5 缺键回落**：`lang\<culture>.json` 缺键必须回落编译期资源（en-US），不得抛异常。（LocalizationManager.cs:56-63）

## E. 工程 / 流程

- [ ] **E1 构建产物不入库**：`bin/`、`obj/`、`Build/` 均 gitignore；改代码后构建不污染 git 状态。（AGENTS §8.5）
- [ ] **E2 快照勿动**：`backup_installed_*` 是部署前快照，禁止改动/删除。（AGENTS §3）
- [ ] **E3 编码规范**：.NET Framework 4.7.2（net472）老式 C#（无 nullable、无 target-typed new、无文件级 namespace）；命名空间=目录名；VM 继承 Prism `BindableBase`，设置类走 `Setting<T>`。（AGENTS §10）
- [ ] **E4 不主动加注释**：沿用既有代码风格，改动不添加新注释（除非必须解释架构决策）。
- [ ] **E5 NetDiff 算法**：改动 `EditGraph.cs`/`DiffUtil.cs` 后必须跑通 `NetDiff.TestRunner`（31 用例）。（AGENTS §7.3）
- [ ] **E6 本地构建命令**：必须传 `/p:FrameworkPathOverride="<repo>\packages\refs\.NETFramework\v4.7.2"`（`<repo>`=仓库根，实际值取 `ProjectPaths.ps1` 的 `$RefAssemblyPath`；.NET Framework 引用程序集不在 SDK 里；旧属性名 `TargetFrameworkRootPath` 已弃用）。（AGENTS §4）
- [ ] **E7 安装输入隔离**：setup 载荷只能来自 `ExcelDiff.Installer\obj\stage` 的专用构建（禁止扫描共享 `bin\Release`），且不得含 `.pdb` 与任何辅助注册工具；退役读取层留下的库（`NPOI*`、`ICSharpCode.SharpZipLib`、`BouncyCastle`）也不得再出现在载荷里 —— 陈旧 bin 目录会活过重建，所以这条断言打在**成品字节**上而不是源码上。（AGENTS §4 / ADR-017 / ADR-019）
- [ ] **E8 安装身份一致**：`ExcelDiffSetup.exe` 的 FileVersion 必须等于 staged 主 EXE `ExcelDiffEDR.GUI.exe` 的 FileVersion，ARP `DisplayVersion` 取同一值；同版本重装必须复用同一注册表键与目录，不得产生第二份"应用和功能"条目。（`Build-Setup.ps1` 校验 / ADR-017）
- [ ] **E9 安装事务完整**：ShellExtension 的 COM 注册/注销必须成对且**在子进程里执行**（进程内 `LoadFrom` 会锁住扩展 DLL 导致卸载删不掉）；重装必须先 `Directory.Move` 旧目录并保留 undo 栈，任一步失败要还原旧目录、恢复 HKLM 状态快照；文件删除只能按 `install-manifest.txt` 逐项执行，**清单缺失一律拒绝卸载**（不做"按已知文件名删"的回落，那会在 `/dir` 打错时删到别一份安装；实测：删掉清单后卸载返回 1、文件与 HKLM 记录俱在，放回清单才返回 0），绝不递归删未知目录——目标目录安装前已存在时，回滚只按清单删自己放下去的东西；卸载有文件删不掉时**必须返回失败且不清注册表/ARP/用户配置**，禁止"提示再卸载一次"却报成功；安装与卸载的目标目录必须在**参数层**判定为绝对路径且非盘符根（判定要看过 `Path.GetFullPath` 之前的原文 —— 解析之后再问 `IsPathRooted` 永远为真，相对值会静默落到进程的工作目录），坏形态返回退出码 4 而不是 1，这样根本不触碰机器。（ADR-017）
- [ ] **E10 安装发布门禁**：正式分发前必须 `AI_Script\verify-installer.ps1 -Install` 全绿（静态检查 + A–M 十三个真实安装/卸载/重装/回滚/拒绝用例），并在发布流水线完成 Authenticode 签名；未签名产物不得对外。（AGENTS §4 / ADR-017 / ADR-018）
- [ ] **E11 路径不写死**：脚本/文档不得出现机器相关绝对路径（盘符）。Program Files 基目录、安装目录名/部署目录、外部测试数据仓一律经根目录 `ProjectPaths.ps1`（可用其标注的环境变量或脚本参数覆盖）。（AGENTS §0.2 / §9）
- [ ] **E12 版本口径**：只有**产品自有且被部署/安装链路消费**的程序集跟随产品版本 —— `ExcelDiff.GUI`（主 EXE，setup 版本源）、`ExcelDiff`、`ExcelDiff.ShellExtension`，以及 `ExcelDiff.Installer`（setup exe 自身，按 E8 与主 EXE 对齐）。vendored 上游库（`FastWpfGrid` / `NetDiff` / `NetDiff.Test` / `WriteableBitmapEx.Wpf`）与对外包清单（`NetDiff.nuspec` 的 `Diff4Net`）保持自身版本，**不得随产品升版**。（ADR-014 / ADR-017）
- [ ] **E13 卸载入口可发现且角色不含糊**（ADR-018）：安装目录里必须有名字即语义的卸载器 `ProductInfo.UninstallerName`（`Uninstall.exe`，进清单）；运行它的默认动作是卸载（角色由文件名判定，优先级 显式 `/uninstall` > 显式 `/install` > 文件名 > 安装），卸载**必须有确认页**、取消即 130。ARP 两条串各表其义：`UninstallString` 交互（不带 `/silent`，让用户能在复选框上决定是否删配置）、`QuietUninstallString` 静默。四条硬规则：① **跨 `%TEMP%` 转发时角色必须以显式开关携带**（转发会改镜像名，名字判定随之失效）；② **从安装目录内发起的卸载是移交式的**（父进程持有子进程要删的那个映像，等待就会把卸载做成"部分删除 + 保留注册表 + 退出码 1"，已实测），所以它的退出码 0 只代表已移交，成败看目录/ARP；自动化断言要轮询效果，不看退出码。③ **移交的用例必须另外断言"转明确实发生了"**：父进程的 0 会替一个立刻失败的子进程背书（本轮实测：转发漏了 `/log:` 前缀，子进程按未知开关返回 4，目录与注册表原地不动而父进程报成功），只查最终效果分不清"没转发"与"转发后子进程失败"，所以门禁 D 同时要求只有转发才会新建的 `*.relay.log` 与恰好一个 `.old-*` 备份。④ **转发前父进程要 `Directory.SetCurrentDirectory(%TEMP%)`，子进程的 `WorkingDirectory` 要显式给**：双击进来的进程 CWD 就是安装目录，`UseShellExecute=false` 的子进程默认继承它，而活动进程的当前目录删不掉也移不走（两条均已实测），症状正是"文件全删、目录留下、仍报成功"。产物名里**决定角色的那一个**（`UninstallerName`）不得在门禁里写死字面量，必须从 `ProductInfo.cs` 正则读出后再用（门禁同时断言它是裸 `.exe` 名、且不等于主程序名，并要求 `err.noUninstallTarget`/`finish.noshell` 两条文案在两种语言里都提到它）—— 改名要连带动角色判定与用户指引，所以这里是唯一必须同源的名字；其余纯文件名（`ExcelDiffEDR.GUI.exe` 等）在门禁里仍是字面量，属可接受。ARP 写入必须在所有可失败的写操作之后、`manifest.Save()` 之前，且恢复动作在 undo 栈跑完之后再执行（栈里的 `ClearRegistry()` 会连 ARP 一起删）。（AGENTS §4）

## F. 性能 / 渲染（FastWpfGrid）

- [ ] **F1 虚拟化不回归**：对比视图依赖 FastWpfGrid 虚拟化，百 MB 级工作簿可用的前提；DiffGridModel 的行状态用预计算 HashSet，避免逐行字典查询热路径。（DiffGridModel.cs:67-93）
- [ ] **F2 PERF_TIMING 隔离**：计时代码放 `#if PERF_TIMING` 或 `[Conditional("PERF_TIMING")]`，正式构建必须裁掉。
- [ ] **F3 EditGraph 前沿守卫**：行级 diff 的 `option.Limit = 2000` 必须保留（EditGraph 最坏 O(D²)，Limit 兜底病态全不同大表）。正常差异（<数百行）前沿远低于阈值；`CaseMultiSameScore_*` 等 31 测试编码当前路径平局规则，**重写 EditGraph 前必须评估测试契约**（ADR-010）。
- [ ] **F4 提权部署禁 `-Wait`**：`Start-Process powershell -Verb RunAs -Wait` 会挂起（UAC + msbuild 子进程）。提权部署必须 fire-and-forget + 轮询日志 `DONE`。（ADR-011 / AGENTS §8.6）
