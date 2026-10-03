# MODULE_REGISTER（模块现状）

> 引用约定（本文件的编号一律按台账名读写，不在此逐条展开）：`ADR-###` = `DECISION_LOG.md` 的架构决策条目；`R-###` = `RISK_REGISTER.md` 的未关闭风险；`§N` = 文件章节号（跨文件引用时写明文件名）。

> 每个被多会话改动的模块一行"现状 + lock"；lock 与 `EXECUTION_PLAN.md` §8（当前切片队列）的 lock 列对应——编辑他人 lock 的模块前先去队列行认领。

## 运行时模式与入口

- 两种使用形态，同一套产品（无版本开关）：① **常驻模式**——首个实例驻留托盘并起命名管道 server（`--startup` 自启走此形态）；② **difftool 模式**——`exe <src> <dst>` 或 git/Mercurial difftool 调起，已有常驻则转发命令即退，无常驻则自己成为常驻。入口 = `ExcelDiff.GUI/App.xaml.cs` 的 `App.Main`（启动链见 `ARCHITECTURE.md` §5）。

## 模块分区（一区一模块）

- **ExcelDiff（读取 + 差异模型）**：入口 `ExcelDiff/ExcelWorkbook.cs`（扩展名分发工厂）。现状 = ExcelDataReader 唯一读取实现 + csv/tsv 自研解析器；已知盲区 R-001。边界：不做 UI、不做持久化。
- **NetDiff（差异算法）**：入口 `NetDiff/NetDiff/EditGraph.cs` + `DiffUtil.cs`。现状 = 类 Myers 算法 + Limit=2000 守卫（ADR-010）；31 用例钉住行为。边界：通用文本差异，不懂表格语义。
- **ExcelDiff.GUI（主程序）**：入口 `ExcelDiff.GUI/App.xaml.cs`。现状 = 常驻 + difftool 双形态、IPC 非阻塞、YAML 设置原子写、外置 lang 本地化。高危区：`SingleInstance.cs`（命名管道）、`Views/DiffViewEvent/`（静态事件分发器）、`Settings/ApplicationSetting.cs`（原子写）。边界：diff 逻辑全部下沉到 ExcelDiff/NetDiff。
- **FastWpfGrid（虚拟化网格）**：入口 `FastWpfGrid/FastWpfGrid/FastGridControl_Render.cs`。现状 = vendored 上游库 + `WriteableBitmapEx` 依赖，不随产品升版（ADR-014）。边界：上游库，改动要克制（只动渲染护栏类问题）。
- **ExcelDiff.Installer（安装器）**：入口 `ExcelDiff.Installer/Build-Setup.ps1`（打包）+ 工程 `InstallEngine`/`ShellRegistrar`/`WizardWindow`。现状 = 自研 WPF setup exe（ADR-017/ADR-018），卸载移交语义 + 归属闸门；发布门禁 `AI_Script/verify-installer.ps1`（静态 + `-Install` A–Q 用例）。边界：不碰产品运行时逻辑。
- **ExcelDiff.ShellExtension（外壳扩展）**：COM 右键菜单（`ContextMenuExtension.cs`）。现状 = SharpShell，注册/反注册必须走子进程。边界：不在 `ExcelDiff.sln` 内构建路径的关键链上（setup 打包时隔离构建）。
- **DiffHarness（headless 输出工具）**：入口 `DiffHarness/DiffHarness.csproj`。现状 = 库层直调、确定性文本，供跨版本输出回归。边界：不是门禁必需品，不参与产品载荷。
- **lang（外置语言文件）**：`lang/en-US.json` / `lang/zh-CN.json`。现状 = 由根目录 `GenerateLangJson.ps1` 从两份 resx 生成（生成物，手改会被再生成冲掉，改字符串走 resx）。

## 机器可校验断言

- lang↔resx 同步与 resx 键集对齐：`AI_Script/verify.ps1`（lang 同步检查段，双向 + 并集比对）。
- 安装器载荷/身份/文案键集：`AI_Script/verify-installer.ps1`（静态段；E7/E8/双语键集与占位符/新鲜度）。
- XAML 硬编码文本与 `-Wait` 转发坑：`AI_Script/verify.ps1`（对应 INVARIANTS D1 / C4 的机检）。
- 代码锚点健康：`AI_Script/refresh-code-index.ps1` + `AI_docs/CODE_INDEX.md`（未解析锚点 > 0 即 FAIL，挂在 verify-scope 与 pre-commit）。
