# AI_Script（Agent 脚本区）

> 所有 Agent 生产的脚本统一放这里；**脚本清单与触发时机唯一出处 = 本文件**；重复性操作一律固化为脚本，不在文档里重复描述步骤。用法与退出码细节以各脚本头注释为准。

## 脚本清单

### 框架门禁（多会话纪律的机械层）

| 脚本 | 用途（细节见脚本头注释） | 触发时机 |
|---|---|---|
| `session-brief.ps1` | 会话开工简报：git 摘要 + 范围/锚点健康 + 切片队列（`EXECUTION_PLAN.md` §8） | 每次会话开工 |
| `verify-scope.ps1` | 交叉验收门禁：SCOPE + ANCHORS + DOCS LINT（`-Compile` 追加 `verify.ps1` 全量；`-ReadOnly` 不写盘）；**`-TaskBrief <派发单>` 追加 TASK SCOPE（改动必须落在派发单机读 `SCOPE:` 行 ∪ 台账面内）；派发时同一参数加 `-WriteScopeBaseline` 记基线，收货时只校验基线之后的新增改动** | 每轮改动跑轻量段；`-Compile` 仅在该轮有代码改动时跑一次（日终 `/day-gate` 兜底）；派发/收货各一次 |
| `verify-day.ps1` | 日终批量门禁：时间窗内提交逐笔**静态审计**（禁改区/范围 + 台账同笔，纯 git 读，不逐提交编译）+ HEAD 重量段（`verify-scope -Compile`）；`-Since` / `-SkipCompile` | 日终 / 批量复核（`/day-gate`）；重量段不必每会话重跑 |
| `pre-commit-check.ps1` | 提交前门禁：禁改区/锚点/CODE_INDEX 重暂存/台账同笔/文档 lint（由 `.githooks/pre-commit` 触发）。**只读档**：`-Changed`（检工作区全部未提交改动，含未跟踪文件）或 `-Paths a.md,b.cs`（只检列出的路径）——改动集取自磁盘、锚点走 `-IndexOnly`、**绝不执行 git add**，用于"不提交就把同一套检查跑一遍" | 每次 `git commit`（钩子自动）；以及任何想在提交前自证的时刻（手动只读档） |
| `refresh-code-index.ps1` | 重解析锚点行号 + 重写 `CODE_INDEX.md` + 修复文档 `#Lnnn` 漂移；`-IndexOnly` 只重建索引、不改任何 AI 文档（给只读检查档用，避免动到并行会话正在写的台账） | 每次改代码后 |
| `lint-docs.ps1` | AI 文档一致性门禁（纯读；检查项 E1–E22 见脚本头（E11 预留未启用），含**章节号交叉引用 E9**、**编码/正典 E10**、**历史叙述指纹 E12**、**引用自带解释 E14/E15**、**自相矛盾/残留状态 E16**、**技能/命令 frontmatter 禁 BOM E17**、**已跟踪文档 md 与 json 禁 BOM E18**、**悬空编号 E19**、**字节级替换符 E20**）；`-Quiet` 只出结论、`-All` 打全部命中（默认只打 40 条）；E14/E15/E16 的旧文档免追诉清单 = `AI_Script/lint-docs-e14-baseline.json`（**必须入库**，否则免追诉失效、全仓旧引用一律判错；新写/改写的段落必须过）；`-WriteBaseline` 重导该清单——输出跨 PS 版本逐字节一致；**须 PS7 与 PS 5.1 双版本各跑一次** | 文档或 `.agents` 改动后（已挂 verify-scope 与 pre-commit） |
| `lint-reply.ps1` | **回复侧**引用自查：给"要发给用户/业主的正文"跑一遍裸编号检查（编号族与判据见脚本头；`-Path <草稿>` / `-Text` / 管道，命中 exit 1）。`lint-docs.ps1` 的 E14/E15 **只扫文件、扫不到对话回复** ⇒ 回复侧靠这一步；步骤 = `AI_docs/AGENT_WORK_PROTOCOL.md`「回复前自查」 | 每轮回复发出前（正文里出现 `ADR-###`/`R-###`/切片号/§N 等编号时） |
| `mermaid-render.ps1` | mermaid 图渲染封装：调用本仓固定版 `@mermaid-js/mermaid-cli`（装于 `AI_Script/tools/mermaid/`）把 `.mmd` 渲成 svg/png/pdf；`-Check` 只校验语法不留产物，`-Install` 新机装依赖 + Chromium | 画/改本地 `Diagrams/` 图表（入口 `.agents/skills/diagram-mermaid/SKILL.md`）；产物不入库 |
| `check-ai-deps.ps1` | 新机依赖自检（`-Install` 自动补 hooksPath） | 新克隆 / 新机器 |
| `code-anchors.json` / `protected-paths.json` / `lint-docs-e14-baseline.json` | 数据与模板（锚点注册表 / 禁改规则 / E14–E16 存量基线） | 见各自用途 |

> mermaid 渲染第三方依赖固定在 `AI_Script/tools/mermaid/`（`package.json` + `package-lock.json` 入库，`node_modules` 不入库），入口 = `mermaid-render.ps1`，纪律见 `.agents/skills/diagram-mermaid/SKILL.md`。

### 工程脚本（项目事实，框架复用它们）

| 脚本 | 用途（细节见脚本头注释） | 触发时机 |
|---|---|---|
| `verify.ps1` | 一键验收门禁（唯一权威编译腿）：构建产品 `ExcelDiffEDR.GUI.exe` + NetDiff 31 用例 + lang↔resx 双向同步 + resx 键集对齐 + `-Wait` 坑扫描 + XAML 硬编码文本扫描 + WIP 快照；`-SkipBuild` 只跑检查段 | 任何代码改动完成后；`verify-scope.ps1 -Compile` 与 `/gate-compile` 内部调它 |
| `verify-installer.ps1` | 安装包发布门禁：静态检查恒跑（载荷/嵌入资源/版本一致/双语键集与占位符/新鲜度/产物名取自源码）；`-Install` 追加 A–Q 十七个真实安装/卸载/重装/回滚/拒绝用例（需管理员） | 安装链改动后 / 发布前 |
| `Deploy-And-Restart.ps1` | 构建 → 部署 → 重启常驻一条龙（仅复制步骤自提权、fire-and-forget + 轮询日志 `deploy_edr.log`、完整性级别实测）；`-NoBuild` / `-NoRestart` / `-Src` / `-Dst` / `-LogDir` | 用户说"构建"时（固化口径）；部署冒烟前 |
| `Invoke-ExcelDiff.ps1` | 安全启动对比窗口：fire-and-forget + 轮询窗口出现/关闭，绝不 `-Wait` 等进程退出（INVARIANTS C4） | 冒烟/回归需要拉起对比时 |
| `refresh_state.ps1` | 重新生成 `AI_docs/PROJECT_STATE.md`（分支/upstream 快照；提交状态问 git 不入文档） | `.githooks/pre-commit` / `post-checkout` / `post-merge` 自动 |

> 机器相关路径（Program Files 基目录、部署目录、外部测试数据仓）唯一出处 = 仓库根 `ProjectPaths.ps1`（`-Print` 自查）；本目录脚本 dot-source 它，不写盘符。

## 新增脚本约定

1. 放本目录，用 `.ps1`；含中文必须 **UTF-8 带 BOM**（PS 5.1 按 ANSI 读无 BOM 的 `.ps1` 会乱码）。文档 `.md` 相反，一律无 BOM（口径见根 `AGENTS.md`「文档状态纪律 · 文件编码」）。归一/自检工具 = `.agents/skills/bom-encoding-gate/SKILL.md`（BOM 编码归一与门禁负测试流程）及其 `scripts/`。
2. 在本文件登记用途与触发时机；脚本头写清 `.USAGE` 与 `.EXITCODE`。
3. 幂等、只读优先；写操作只落在约定目录。
4. **公共函数放 `AI_Script/lib/`**（dot-source 引入，如 `. (Join-Path $scriptDir 'lib\common.ps1')`）；不要复制 git 捕获 / 禁改规则 / 代码改动判据。
