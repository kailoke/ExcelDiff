---
name: bom-encoding-gate
description: UTF-8 BOM 编码漂移的归一与门禁负测试流程，含逐字节实测现状、区分"含非 ASCII 的 .ps1 必须有 BOM"与"文档 md/json 必须无 BOM"两个方向、带断言的字节手术或整份重写归一、规则成文加门禁机检、收尾负测试闭环。当出现 git diff 无端多出一行首行被改、Write 整写后 BOM 丢失、.ps1 在 Windows PowerShell 5.1 下中文乱码或 ParserError、需要为编码口径新增机检规则、或需要验证门禁编码规则真的会拦截时使用。
---

# BOM 编码归一与门禁负测试

## Overview

处理 UTF-8 BOM 漂移的标准动作。BOM 掉/加会造成两类噪声（git diff 无端多一行"首行被改"、PS 5.1 误读无 BOM 的 .ps1），而错误的修复手法本身会损坏文件内容。核心纪律：先逐字节实测、归一用带断言的字节手术或整份重写、新增门禁规则后必须做"种违规→确认拦截→复跑归绿"的负测试。

## 编码口径（两个方向，成对出现）

| 对象 | 要求 | 理由 |
|---|---|---|
| 文档类 md / json（`AGENTS.md`、`AI_docs/**`、`.agents/**`、`AI_Script` 顶层的 md 与 json） | UTF-8 **无 BOM** | 整写通道一律按无 BOM 写；带 BOM 的文件每被整写一次就掉一次，git diff 平白多一行 `-<BOM>首行` / `+首行` 的无关变更 |
| 含非 ASCII 的 .ps1 | UTF-8 **必须有 BOM** | Windows PowerShell 5.1 把无 BOM 的 UTF-8 按 ANSI 读 → 中文注释乱码 → ParserError；纯 ASCII 的 .ps1 无 BOM 合法 |
| 技能/命令 frontmatter md | 无 BOM 且首行严格 `---` | 首字节带 BOM 时宿主前言解析错位（description 被读成 `---`） |

两个方向的规则必须同时成文并各有机检——只规定一个方向，漂移就会朝另一个方向发生。

## 谁剥 BOM、谁加 BOM（实测工具行为）

| 通道 | 行为 |
|---|---|
| Write 工具整份重写 | 剥掉 BOM |
| Edit 工具定点替换 | 保留原文件的 BOM（改首行也保留） |
| PS 5.1 的 `Set-Content -Encoding UTF8` / `Out-File` | **写入即带 BOM**（"给甲文件还原 BOM 顺手给乙文件加上"的漂移主源） |
| PS 7 默认写入 | 无 BOM |
| .NET `[IO.File]::WriteAllText($p,$t,(New-Object Text.UTF8Encoding($false)))` | 无 BOM；构造参数 `$true` 则带 BOM（生成器脚本的写法决定漂移方向） |

## 流程（六步，按序执行）

### 1. 实测现状（动手前必须重测）

- 用 `scripts/scan_bom.py` 逐字节清点工作副本；在 git 仓库里加 `--git` 同时查 HEAD blob，两边差异能指出是哪条通道在加/剥。
- 共享工作区里并行会话可能先于你提交、把 BOM 集合整个挪位（实测发生过"台账丢 BOM"与"另外三份文档加 BOM"出现在同一笔提交里）——**写盘前一刻再核一次 `git log` / `git status`**。
- 枚举 tracked 文件必须 `git -c core.quotepath=off ls-files -z`，否则非 ASCII 文件名被加引号前缀会导致**整批漏扫**（实测踩过；scan 脚本已按原始字节处理规避）。

### 2. 分类对象

按上表分成"该有 / 该无 / 现状合法"三类。别的会话有未提交改动的文件不要碰——只归一本任务范围内的对象。

### 3. 归一

- tracked 文件可用 `scripts/bom_surgery.py --mode strip|add`——内置断言"新字节 == 旧字节去前 3"与"正文严格 UTF-8 可解码"，任一断言失败即拒写并还原；完成后 `git diff --numstat` 每文件应恰好 1/1（只有首行）。
- 该脚本的断言保护的是"整 3 字节前缀运算本身不出错"（严格解码 + 写后回读比对 + 失败还原），**不是"能查出文件曾被吞掉别的字节"**——别把跑绿当成内容无损的凭据，末了仍要复核首行是不是人可读的标题（本步末条）。
- **gitignored 接力件（没有 `git show` 可复核）一律整份按目标编码重写，不做字节手术**——实测事故：手工 BOM 手术吃掉 1 个字节，`HANDOFF` 变 `ANDOFF`、汉字"黄"的首字节 `0xE9` 被吞成两个替换符，且无 git 可回滚。被禁的是这种**无断言的手工截取**；补 BOM 本身走 `--mode add`（整 3 字节前缀 + 写后回读），不碰正文。
- 修完复核三件：严格 UTF-8 解码 0 替换符、首行仍是人可读的标题、BOM 状态符合目标口径。

### 4. 规则成文 + 机检（配套，缺一不可）

- 规则本体（口径 + 理由 + 正确剥法一句话）写进仓库规约文档（本仓 = 根 `AGENTS.md`「文档状态纪律 · 文件编码」条）。
- 机检规则加进门禁脚本（本仓 = `AI_Script/lint-docs.ps1`：E18 = **git 已跟踪**的文档 md 与 json 禁 BOM，未入库草稿不判；E10 = .ps1 必须有 BOM；E17 = 技能/命令 frontmatter 禁 BOM；E20 = **git 已跟踪**的文本扩展名文件按**字节**禁真实存储的替换符 `EF BB BD`——按解码后的 `U+FFFD` 扫会把 GBK 这类非 UTF-8 文件误当证据）。
- 门禁里凡是"重导/覆盖一份数据文件"的子命令（本仓 = `lint-docs.ps1 -WriteBaseline`，重导引用免追诉基线），要额外满足两条：输出跨 PowerShell 版本**逐字节一致**（两版 `ConvertTo-Json` 的缩进、冒号空格、键序都不同，`Set-Content -Encoding UTF8` 在 5.1 下还会加 BOM ⇒ 手写确定性序列化）；扫描面异常缩小时**拒绝写出**并非零退出（枚举带 `SilentlyContinue` 时可整批发空，空结果一旦入库，下一版本按空基线判就满盘误报）。
- 确认扫描面覆盖所有会写这类文件的通道（工具链、仓内生成器脚本），否则门禁会被自家生成器跑红。
- 门禁脚本自身的编码按 .ps1 规则办（含中文则保留 BOM），编辑后验证首 3 字节仍是 `efbbbf`。

### 5. 负测试闭环（必做收尾，"工具没报错" ≠ "门禁生效"）

1. 在工作副本故意种一个违规（如给扫描面内一份 md 加 BOM）；
2. **种完先自己读回前 3 字节确认已落盘**，再跑门禁——跨进程紧邻读取可能拿到旧内容，不读回就会把"规则没拦"当成事实（本轮实测：给 json 种 BOM 后立刻跑门禁报 0 error，加这一步后同一条命令报红 exit 1）；
3. 跑门禁，**必须看到它命中该文件并报 ERROR**——这一行输出就是防线存在的见证；
4. 剥掉违规，逐字节确认文件回到种入前状态；
5. **PowerShell 7 与 Windows PowerShell 5.1 双版本**各跑一次归绿——单版本通过不算通过（实测事故：PS7 读得了无 BOM 文件，交付"LINT 0"在 5.1 下实为 ParserError）。

违规只在本地种、验完即剥，绝不进入提交。

### 6. 收尾提交

- 逐文件显式路径暂存；提交前用 `git status` 核对每处改动的归属，并行会话的未提交改动不混入、不重置。
- 长中文提交信息走 `git commit -F <文件>`（Git Bash 会把 `-m` 的长中文/引号参数拆坏）；临时信息文件用完即删。
- 提交后复核入库 blob：`git cat-file` / `git show` 确认 BOM 状态正确、首行完好。

## 环境坑速查（Windows + Git Bash + 双 PowerShell）

| 坑 | 处置 |
|---|---|
| Write/Read 工具不认 msys `/tmp` 路径 | 先 `cygpath -w /tmp/...` 换成 Windows 路径再传给工具 |
| bash 里内联 python / PowerShell 长脚本引号炸 | 落成 `.py` / `.ps1` 文件再执行，禁止内联长代码 |
| python 向 GBK 控制台打印 U+FFFD 抛 UnicodeEncodeError | `sys.stdout.reconfigure(encoding='utf-8', errors='replace')`（本技能脚本已内置） |
| pwsh 安装路径因人而异且含空格 | 先用 `where` / `ls` 探测实际路径，调用时整体加引号 |
| git 输出里非 ASCII 文件名带引号转义 | `git -c core.quotepath=off` + `-z` 按 NUL 分隔 |
| 上一个进程刚写的字节，下一个进程读到旧内容（写盘与判定跨进程时） | 写方自己读回前 3 字节断言（必要时稍等片刻）再交给门禁判断；负测试不读回就可能得出反的结论（见第 5 节第 2 步） |
| 目录枚举瞬时返回空（并行会话正在写，且收集通道带 `SilentlyContinue`） | 测量/导出类子命令必须 fail-closed：扫描面小于阈值就拒绝写出、非零退出，绝不让空结果入库 |

## Resources

- `scripts/scan_bom.py`：BOM 现状清点（工作副本 + HEAD blob 双通道、md/json/ps1 分类、报违规与中段 BOM / 非 UTF-8 损坏）。
- `scripts/bom_surgery.py`：去/补 BOM（带严格 UTF-8 解码与 tail-identical 断言，失败自动还原，支持 `--dry-run`）。