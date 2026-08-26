# INVARIANTS — 工程硬约束清单

> 改动任何代码前逐条核对。**违反任一条 = 阻断提交/部署。**
> 来源：ARCHITECTURE.md、AGENTS.md、CODEX.md（各条标注出处）。

## A. 双版本（ED/EDE）隔离（EDE 为主版本）

- [ ] **A1 单一代码源**：ED/EDE 由同一份源码 + `#if NPOI_READ / EDR_READ` 编译产出，禁止复制两套实现。（AGENTS §5）
- [ ] **A2 主版本必编译**：EDE（`EdrRead=true`）必须编译通过；ED（`EdrRead` 空）代码保留作保底对照、**不参与日常门禁**（仅对照验证时手工 build）。（AGENTS §7.1 / ADR-012）
- [ ] **A3 ED 代码不得移除**：ED（NPOI）分支、`ExcelDiff.GUI` 程序集名、`%APPDATA%\ExcelDiff.GUI\` 配置路径等保留，作为 EDR 盲区兜底与对照验证。（AGENTS §7.5 / ARCH §10）
- [ ] **A4 隔离派生**：配置目录/IPC channel/显示名均按程序集名（exe 名）派生，ED/EDE 天然隔离，不要硬编码共享。（ARCH §7.5、CODEX 链路B）

## B. 读取层（核心库 ExcelDiff）

- [ ] **B1 版本定位**：EDE=EDR **主版本**（读取快约 72%）；ED=NPOI **保底对照**（语义最全，代码保留、不日常构建）。基准测试以 EDE 为准；**ED 代码不得移除**（EDR 盲区兜底）。（ARCH §5/§10、ADR-012）
- [ ] **B2 EDR 语义对齐**：EDR 路径必须跳整空行、裁剪尾空单元格，保持与 NPOI 行/列语义一致。（ExcelWorkbook.cs:132-141）
- [ ] **B3 EDR 已知盲区**：EDR 读不到"仅样式无值"单元格 → 列漂移 → 漏报真实变更。涉及该场景用 `ExcelWorkbook.VerifyRead` 双读校验 / ED（NPOI）保底对照。（ARCH §9.6）
- [ ] **B4 回归比对（可选）**：ED/EDE 输出比对（如需对照）必须**严格用同名文件的 Unstaged（工作区）VS HEAD**，严禁跨文件/跨版本互比。（AGENTS §7.4/§7.7）
- [ ] **B5 扩展名分发**：新增文件类型解析在 `ExcelWorkbook.Create` 里统一分发，CSV/TSV 保持自研零依赖。

## C. 生命周期 / IPC（GUI 高危区）

- [ ] **C1 IPC 非阻塞**：管道线程只能用 `Dispatcher.BeginInvoke` 投递，**绝不同步等待模态框**，否则模态框存在时死锁。（ARCH §6.4、AGENTS §8.4）
- [ ] **C2 事件分发器**：`*EventDispatcher.Instance` 是进程级单例；窗口真正关闭时必须 `DiffView.RemoveEventListeners()`，防泄漏/防派发到 `container==null` 的旧视图。（DiffCommand.cs:37）
- [ ] **C3 关窗语义**：`RunInBackground=true` → 关窗仅隐藏到托盘；`IsClosingMainWindow`（语言切换）→ 允许真正关；`ExitApplication` 置 `IsExiting` 后 `Shutdown`。（MainWindow.xaml.cs:122）
- [ ] **C4 转发进程不驻留**：对转发进程 `Start-Process -Wait` 会挂起（无常驻时转发器变常驻）。等待会话用 `AI_Script\Invoke-ExcelDiff.ps1`（fire-and-forget + 轮询窗口）；入库脚本由 `AI_Script\verify.ps1` 坑扫描自动拦截 `Start-Process ... -Wait ... ExcelDiff`。（AGENTS §8.3）
- [ ] **C5 模态强关**：远程命令生效前 `CurrentDiffView.DismissModalWindows()` 强关无差异等模态，再 `ShowMainWindow`。（App.xaml.cs:181-185）

## D. 本地化

- [ ] **D1 字符串唯一来源**：UI 文本一律 `Resources.*`（经 `LocalizationManager` 桥接），禁止硬编码。（AGENTS §10）
- [ ] **D2 resx→json 再生成**：改 `Resources*.resx` 后必须跑 `GenerateLangJson.ps1` 再生成 `lang\*.json`，二者保持同步（构建期 `CopyLangFiles` 自动部署，但生成是人工/脚本步骤）。（AGENTS §7.2）
- [ ] **D3 非 ASCII 编码**：改写含中文/日文的 YAML/JSON/resx 用文件写入工具（UTF-8 无 BOM）或 `[System.IO.File]::WriteAllText` + 显式 UTF8；PowerShell 5.1 `Set-Content -Encoding UTF8` 会按 ANSI 破坏。（AGENTS §8.1）
- [ ] **D4 语言切换**：`{x:Static}` 在 XAML 加载时固化 → 语言变更通过"关窗+下次命令重建"生效，不要试图热替换已加载窗口的静态资源。（App.xaml.cs:327-332）
- [ ] **D5 缺键回落**：`lang\<culture>.json` 缺键必须回落编译期资源（en-US），不得抛异常。（LocalizationManager.cs:56-63）

## E. 工程 / 流程

- [ ] **E1 构建产物不入库**：`bin/`、`obj/`、`Build/` 均 gitignore；改代码后构建不污染 git 状态。（AGENTS §8.5）
- [ ] **E2 快照勿动**：`backup_installed_*` 是部署前快照，禁止改动/删除。（AGENTS §3）
- [ ] **E3 编码规范**：.NET Framework 4.6.2 老式 C#（无 nullable、无 target-typed new、无文件级 namespace）；命名空间=目录名；VM 继承 Prism `BindableBase`，设置类走 `Setting<T>`。（AGENTS §10）
- [ ] **E4 不主动加注释**：沿用既有代码风格，改动不添加新注释（除非必须解释架构决策）。
- [ ] **E5 NetDiff 算法**：改动 `EditGraph.cs`/`DiffUtil.cs` 后必须跑通 `NetDiff.TestRunner`（31 用例）。（AGENTS §7.3）
- [ ] **E6 本地构建命令**：必须传 `TargetFrameworkRootPath="D:\ExcelDiff\packages\refs"`（.NET Framework 引用程序集不在 SDK 里）。（AGENTS §4）

## F. 性能 / 渲染（FastWpfGrid）

- [ ] **F1 虚拟化不回归**：对比视图依赖 FastWpfGrid 虚拟化，百 MB 级工作簿可用的前提；DiffGridModel 的行状态用预计算 HashSet，避免逐行字典查询热路径。（DiffGridModel.cs:67-93）
- [ ] **F2 PERF_TIMING 隔离**：计时代码放 `#if PERF_TIMING` 或 `[Conditional("PERF_TIMING")]`，正式构建必须裁掉。
- [ ] **F3 EditGraph 前沿守卫**：行级 diff 的 `option.Limit = 2000` 必须保留（EditGraph 最坏 O(D²)，Limit 兜底病态全不同大表）。正常差异（<数百行）前沿远低于阈值；`CaseMultiSameScore_*` 等 31 测试编码当前路径平局规则，**重写 EditGraph 前必须评估测试契约**（ADR-010）。
- [ ] **F4 提权部署禁 `-Wait`**：`Start-Process powershell -Verb RunAs -Wait` 会挂起（UAC + msbuild 子进程）。提权部署必须 fire-and-forget + 轮询日志 `DONE`。（ADR-011 / AGENTS §8.6）
