<#
.SYNOPSIS
    AI 文档一致性门禁（纯读）：术语 / 损坏指纹 / 悬空路径 / 裸行号 / 薄指针 / JSON / 脚本语法。

.DESCRIPTION
    扫描范围：AGENTS.md、AI_docs/**、.agents/**、宿主薄指针（.zcode/.qoder）、AI_Script/code-anchors.json。参数：-Quiet 只出结论；-WriteBaseline 只导出 E14/E15/E16 存量基线后退出。
    排除：AI_docs/HANDOFFS（本地接力）与 __pycache__ 等非 AI 文档面。

    检查项与级别：
      E1 术语：AI_docs/glossary.json 的 forbidden 旧写法（词边界匹配，例外：glossary.json 自身）。
      E2 损坏指纹：U+FFFD / 零宽字符 / 中段 BOM / 定定|位位 / C.agents|CAI_… / Ofg|OONFIG 等。
      E3 悬空路径：反引号内以 AI_docs|AI_Script|.agents|工程源码目录|lang|opencode.json|AGENTS.md 开头的路径必须存在
         （跳过通配/占位符/packages/Build/Release/HANDOFFS）。
      E4 裸行号：`文件.ext:123` 形式（引用纪律要求锚点）；扫工程源码目录与 AI 目录。
      E5 历史层：文档出现 `~~删除线~~`。
      E6 薄指针（现存宿主全量）：.agents/commands/*.md 必须在 .zcode/commands、.qoder/skills 有同名指针；
         .agents/skills/*/SKILL.md 必须在 .zcode/.qoder 的
         skills/ 各有指针（现存宿主目录一个都不能漏，命令与技能同此要求；新增宿主 = 三处同步：宿主薄指针 + 本清单 + 根 AGENTS.md「加技能 / 加命令的硬性条件」）。每个指针校验三项：存在性、正文指向该源文件、frontmatter description 与源逐字同文
         （技能另校验 name 与目录名一致）。
      E7 JSON：关键 JSON 可解析。
      E8 脚本语法：AI_Script/*.ps1 通过 PSParser。
      E9 章节号引用：`X.md` §N / 本文件 §N 必须在该文件真实存在（防指向不存在章节的过期引用）；
         仅校验"文件名 + 数字章节号"配对；解析不到的横线内路径记 WARN 不报错。
         **命中即 ERROR（用户裁决：维持严格档）**——这是该类过期引用唯一的机械防线，不得为省事降为 WARN。
      E12 历史叙述指纹（零历史纪律，规则本体 = AGENTS.md 文档状态纪律）：正文禁止"取代早先/旧口径/
         已作废/已退役/待回填/裁决日期（用户裁决 YYYY-MM-DD）"式过程叙述——已裁决+已执行完成的记录
         整条删除或改写成最终态描述，历史唯一存放处 = git log。命中即 ERROR（生成物 CODE_INDEX.md 与
         glossary.json 除外；规则定义行以"零历史/禁止出现/git log"字样自免）。
（规则本体 = AGENTS.md「引用与表达纪律 · 引用自带解释」）：文档**首次**出现 D-### / R-### 编号时，
          该编号所在行必须自带一句"它是什么"（解释标记 = 冒号/等号/破折号/是/即/指/见）。指针块
          （"不在本文件成文/唯一正文/口径见/正文 ="）**只豁免它自己那一行**——不再整份豁免：一行"引用约定"就能把
          整份文档的 E14 关掉，等于把纪律关在了最需要它的台账上（对话回复没有文件可扫，文件侧是这里唯一的机械防线）。
          旧文档的存量引用免追诉，清单 = `lint-docs-e14-baseline.json`
          （实测数低于基线时记 WARN 提示收紧）；**新写/改写的段落一律要过**。命中超出基线即 ERROR。
      E15 引用无解释（编号族）：与 E14 同一规则本体，覆盖 ST-n / S3-n / §N / E<n> / B<nn>。
       E16 自相矛盾 / 残留状态指纹（规则本体 = AGENTS.md「文档状态纪律」）：六类机械判据 ——
           ① 同一文件重复的 ## 标题；② 同一小节内重复的表格行；③ 同一行"待裁决"与"已裁决"并存；
           ④ 正文残留流程状态标记（已实施/已落地/已修复/已验证…，只允许出现在台账与队列）；
           ⑤ 自指指针（"口径见/唯一正文"配"见本文件/本节"）；⑥ "已删除/已退场"却仍按活着描述。
           E16 **不套用**"顶部有指针块即整份跳过"（那会让指针块多的文档整份免疫）。
       E14/E15/E16 的存量基线 = lint-docs-e14-baseline.json（**由本脚本 -WriteBaseline 生成，勿手算**）；
       已知误报：编号出现在**文件路径**里时，解说在路径中，探测器仍会命中（当前基线里留有 1 条）。
            E10 编码与正典：含非 ASCII 的 .ps1 必须带 UTF-8 BOM（否则 PS 5.1 按 ANSI 读会乱码/ParserError）；
         AGENTS.md 禁改 glob 必须与 protected-paths.json 一致（消灭第二份路径表漂移）。
      E17 技能/命令 frontmatter 编码：.agents/.zcode/.qoder 下 skills/**/SKILL.md 与
         命令指针 .md 首字节禁 UTF-8 BOM 且首行必须为 `---`（带 BOM 时宿主前言解析错位——历史事故：技能列表
         description 显示成 `---`）。与 E10a 相反：.ps1 要 BOM，技能/命令 .md 禁 BOM。命中即 ERROR。
      E18 AI 文档编码：**git 已跟踪**的 AGENTS.md、AI_docs/**、.agents/**、AI_Script 顶层的 .md/.json 首字节禁
         UTF-8 BOM（规则本体 = AGENTS.md「文档状态纪律 · 文件编码」；整写文件的工具链一律按无 BOM 写，带 BOM 的
         文件每次重写都掉一次 BOM，git diff 平白多出一行"首行被改"的无关变更）。命中即 ERROR。
      E19 悬空编号：正文引用的 ADR-### / D-### / R-### 必须在定义行存在（决策册的 `- **ADR-xxx**` 行、风险册表格首列 `| R-xxx |`）；台账正面也纳入扫描，定义行自身由"编号已在定义集"放行；本项不给存量基线。
      E20 字节级替换符：**git 已跟踪**的文本扩展名文件（清单见实现处注释）里不得出现真实存储的 EF BB BD
         三字节——那是"按 UTF-8 读 + 替换坏字节"式坏转码的残留，内容已损坏且不可复原。按**字节**扫而不是按
         解码后的 U+FFFD 扫：非 UTF-8 文件（GBK 等）按 UTF-8 解码本来就会出现 U+FFFD，那不是存储的替换符。
         当前全仓命中为 0，无需存量基线。命中即 ERROR。

    执行环境口径（自检纪律）：本脚本自带 E8/E10 语法与编码自检，但仍应以 **PowerShell 7 与 Windows PowerShell 5.1 双版本**跑一次再下"LINT 通过"结论；
    单版本通过不等于通过（历史事故：PS7 能读无 BOM 文件 → 交付"LINT 0"在 PS 5.1 下实为 ParserError）。

.USAGE
    .\AI_Script\lint-docs.ps1            # 全量检查
    .\AI_Script\lint-docs.ps1 -Quiet     # 只输出汇总与失败项
    .\AI_Script\lint-docs.ps1 -All       # 打全部命中（修文件/收紧基线时用）
    .\AI_Script\lint-docs.ps1 -WriteBaseline   # 重导存量基线：输出跨 PS7/PS5.1 逐字节一致（手写序列化：2 空格缩进、
                                               #   键按 Ordinal 升序、LF、UTF-8 无 BOM）；扫描面 .md 少于 10 时拒绝导出并非零退出

    注意：本脚本**只扫文件**。给用户/策划的回复正文没有文件可扫，用 `AI_Script/lint-reply.ps1` 自查
    （步骤 = `AI_docs/AGENT_WORK_PROTOCOL.md`「回复前自查」）。

.EXITCODE
    0 = 通过（可能有 WARN）；1 = 存在 ERROR。
#>
param([switch]$Quiet, [switch]$WriteBaseline, [switch]$All)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$scriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir

# git 输出统一走公共库的 Invoke-GitCapture：受限环境（Harness 的 Windows ACL 沙箱）里 PowerShell 捕获子进程
# stdout 这条路径起不来，会让下面 E10a/E18 的扫描面判据静默退化（成因与实测见该函数注释）。
. (Join-Path $scriptDir 'lib\common.ps1')

$errors = New-Object System.Collections.ArrayList
$warns  = New-Object System.Collections.ArrayList
function Add-Err([string]$m) { [void]$errors.Add($m) }
function Add-Warn([string]$m) { [void]$warns.Add($m) }

# ---------- 收集扫描文件 ----------
$scanFiles = New-Object System.Collections.ArrayList
[void]$scanFiles.Add((Join-Path $projectRoot 'AGENTS.md'))
foreach ($d in @('AI_docs', '.agents')) {
    # 注意：不用 -Include（PS5.1 下会把 .py 等误匹配进来），改显式扩展名过滤，保证 PS7/PS5.1 扫描面一致
    Get-ChildItem -LiteralPath (Join-Path $projectRoot $d) -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in @('.md', '.json') } |
        Where-Object { $_.FullName -notmatch '\\HANDOFFS\\|\\__pycache__\\' } |
        ForEach-Object { [void]$scanFiles.Add($_.FullName) }
}
$scanFiles = $scanFiles | Sort-Object -Unique
$scanTexts = @{}
foreach ($f in $scanFiles) {
    $scanTexts[$f] = [System.IO.File]::ReadAllText($f, [System.Text.Encoding]::UTF8)
}
function Rel([string]$p) { $p.Replace($projectRoot, '').TrimStart('\') }
function Get-Context([string]$text, [int]$offset, [int]$len = 40) {
    $s = [Math]::Max(0, $offset - 10)
    $e = [Math]::Min($text.Length, $offset + $len)
    return ($text.Substring($s, $e - $s) -replace "`r?`n", ' ')
}
# E14/E15 共用的"这条引用算不算自带解释"判据（窄判据、宁漏不误）。三种过法：
#   ① 编号附近有解释标记（冒号/等号/破折号/是/即/指/见）；
#   ② 编号后面紧跟一句括号补充（"D-042（小游戏离线经济口径）"）；
#   ③ 编号本身位于一个 ≥6 字的括号补充内部（"（图鉴 + 携带预设，D-022）"）。
# 规则本体 = AGENTS.md「引用自带解释」；机械判据只能拦"裸编号"，判不了语义，别把它当唯一防线。
function Test-RefGlossed([string]$lineText, [System.Text.RegularExpressions.Match]$m, [string]$explainPat) {
    $start = [Math]::Max(0, $m.Index - 4)
    $take = [Math]::Min($lineText.Length - $start, $m.Length + 24)
    if ($lineText.Substring($start, $take) -match $explainPat) { return $true }
    $tailStart = [Math]::Min($lineText.Length, $m.Index + $m.Length)
    $tail = $lineText.Substring($tailStart, [Math]::Min(60, $lineText.Length - $tailStart))
    if ($tail -match '^[\s\*`）)]*[^（(]{0,14}[（(]\s*[^）)]{6,}') { return $true }
    foreach ($bm in [regex]::Matches($lineText, '[（(][^）)]{6,}[）)]')) {
        if ($bm.Index -lt $m.Index -and ($bm.Index + $bm.Length) -gt ($m.Index + $m.Length)) { return $true }
    }
    return $false
}

# ---------- E1 术语 ----------
$glossaryPath = Join-Path $projectRoot 'AI_docs\glossary.json'
if (Test-Path -LiteralPath $glossaryPath -PathType Leaf) {
    $glossary = Get-Content -LiteralPath $glossaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($term in $glossary.forbidden.PSObject.Properties.Name) {
        $rx = [regex]::Escape($term)
        foreach ($f in $scanFiles) {
            if ($f -eq $glossaryPath) { continue }
            $t = $scanTexts[$f]
            foreach ($m in [regex]::Matches($t, $rx)) {
                Add-Err ("[E1 术语] {0} :: 旧写法 `{1}` 应改为：{2}  …{3}" -f (Rel $f), $term, $glossary.forbidden.$term, (Get-Context $t $m.Index))
            }
        }
    }
} else {
    Add-Warn '[E1] glossary.json 不存在，跳过'
}

# ---------- E2 损坏指纹 ----------
$corruptRx = '[\uFFFD\u200B-\u200D]|定定|位位|C\.agents|C\.codex|C\.opencode|CAI_docs|CAI_Script'
foreach ($f in $scanFiles) {
    $t = $scanTexts[$f]
    foreach ($m in [regex]::Matches($t, $corruptRx)) {
        Add-Err ("[E2 损坏] {0} :: `{1}`  …{2}" -f (Rel $f), $m.Value, (Get-Context $t $m.Index))
    }
    # 中段 BOM（首字符已被 ReadAllText 剥离，其余出现即异常）
    $idx = $t.IndexOf([char]0xFEFF)
    while ($idx -ge 0) {
        Add-Err ("[E2 损坏] {0} :: 文本中出现 U+FEFF（中段 BOM）" -f (Rel $f))
        $idx = $t.IndexOf([char]0xFEFF, $idx + 1)
    }
}

# ---------- E3 悬空路径 ----------
$pathSkip = '^(AI_Script/local-env\.json|AI_docs/HANDOFFS|packages/|Build/|TestExcel/|ExcelDiff\.Installer/Release/|Diagrams/)'
foreach ($f in $scanFiles) {
    if ($f -notmatch '\.md$') { continue }
    $t = $scanTexts[$f]
    foreach ($m in [regex]::Matches($t, '`([^`\r\n]{2,200})`')) {
        $tok = $m.Groups[1].Value
        if ($tok -match '[<>{*}…|\s]') { continue }
        if ($tok -notmatch '^(AI_docs/|AI_Script/|\.agents/|\.zcode/|\.qoder/|ExcelDiff\.GUI/|ExcelDiff\.Installer/|ExcelDiff\.ShellExtension/|ExcelDiff/|NetDiff/|FastWpfGrid/|DiffHarness/|lang/|opencode\.json|AGENTS\.md|ProjectPaths\.ps1|GenerateLangJson\.ps1)') { continue }
        if ($tok -match $pathSkip) { continue }
        $clean = ($tok -split '#')[0].TrimEnd('/')
        if (-not $clean) { continue }
        $full = Join-Path $projectRoot ($clean -replace '/', '\')
        if (-not (Test-Path -LiteralPath $full)) {
            Add-Err ("[E3 悬空路径] {0} :: `{1}` 不存在" -f (Rel $f), $tok)
        }
    }
}

# ---------- E4 裸行号 ----------
$nakedRx = '(?<![\w/:])((?:ExcelDiff\.GUI|ExcelDiff\.Installer|ExcelDiff\.ShellExtension|ExcelDiff|NetDiff|FastWpfGrid|DiffHarness|AI_docs|AI_Script|\.agents|lang)/[\w./\-]+\.(?:cs|xaml|ps1|py|json|xml|bat|txt)):(\d+)'
foreach ($f in $scanFiles) {
    if ($f -notmatch '\.md$') { continue }
    $t = $scanTexts[$f]
    foreach ($m in [regex]::Matches($t, $nakedRx)) {
        Add-Err ("[E4 裸行号] {0} :: {1}:{2}（引用代码应写锚点）" -f (Rel $f), $m.Groups[1].Value, $m.Groups[2].Value)
    }
}

# ---------- E5 历史层 ----------
foreach ($f in $scanFiles) {
    if ($f -notmatch '\.md$') { continue }
    $t = $scanTexts[$f]
    foreach ($m in [regex]::Matches($t, '~~[^~\r\n]{1,80}~~')) {
        Add-Err ("[E5 历史层] {0} :: {1}（删除线=旧口径，应直接删除/改写）" -f (Rel $f), $m.Value)
    }
}

# ---------- E6 薄指针（规则本体 = AGENTS.md「加技能 / 加命令的硬性条件（多宿主兼容）」） ----------
# 宿主 → 形态契约（按本仓实际目录，现存宿主 = .zcode 与 .qoder；改前缀必须先确认该宿主真的读它）：
#   命令：.zcode\commands\<n>.md ／ .qoder\skills\<n>\SKILL.md
#   技能：.zcode\skills\<名>\SKILL.md ／ .qoder\skills\<名>\SKILL.md
# 缺一个宿主 = 那个 agent 加载不到这条纪律 ⇒ 拒提。空技能目录（无源对应）同样拒提。
function Get-FmField([string]$text, [string]$field) {
    $m = [regex]::Match($text, "(?m)^$field`:\s*(.+)$")
    if ($m.Success) { return $m.Groups[1].Value.Trim() }
    return ''
}
$cmdDir = Join-Path $projectRoot '.agents\commands'
if (Test-Path -LiteralPath $cmdDir -PathType Container) {
    foreach ($c in Get-ChildItem -LiteralPath $cmdDir -File -Filter *.md) {
        $name = $c.BaseName
        $srcText = [System.IO.File]::ReadAllText($c.FullName, [System.Text.Encoding]::UTF8)
        $srcDesc = Get-FmField $srcText 'description'
        $srcHint = Get-FmField $srcText 'argument-hint'
        foreach ($rel in @(".zcode\commands\$name.md", ".qoder\skills\$name\SKILL.md")) {
            $p = Join-Path $projectRoot $rel
            if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { Add-Err ("[E6 指针] 缺失 {0}（对应 .agents/commands/{1}.md）" -f $rel, $name); continue }
            $pt = [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8)
            if ($pt -notmatch [regex]::Escape(".agents/commands/$name.md")) { Add-Err ("[E6 指针] {0} 未指向 .agents/commands/{1}.md" -f $rel, $name) }
            if ((Get-FmField $pt 'description') -ne $srcDesc) { Add-Err ("[E6 指针] {0} 的 description 与 .agents/commands/{1}.md 不一致" -f $rel, $name) }
            if ($srcHint -and (Get-FmField $pt 'argument-hint') -ne $srcHint) { Add-Err ("[E6 指针] {0} 的 argument-hint 与源不一致" -f $rel) }
        }
    }
}
$skillDir = Join-Path $projectRoot '.agents\skills'
if (Test-Path -LiteralPath $skillDir -PathType Container) {
    foreach ($sk in Get-ChildItem -LiteralPath $skillDir -Directory) {
        $skName = $sk.Name
        $skPath = Join-Path $sk.FullName 'SKILL.md'
        if (-not (Test-Path -LiteralPath $skPath -PathType Leaf)) { Add-Err ("[E6 指针] 源缺失 .agents/skills/{0}/SKILL.md（空目录/半成品技能不注册宿主，先补齐或移出）" -f $skName); continue }
        $skSrc = [System.IO.File]::ReadAllText($skPath, [System.Text.Encoding]::UTF8)
        $skDesc = Get-FmField $skSrc 'description'
        # 多宿主兼容（AGENTS.md「加技能 / 加命令的硬性条件」）：五个宿主目录一个都不能漏
        foreach ($rel in @(".zcode\skills\$skName\SKILL.md", ".qoder\skills\$skName\SKILL.md")) {
            $p = Join-Path $projectRoot $rel
            if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { Add-Err ("[E6 指针] 缺失 {0}（对应 .agents/skills/{1}/SKILL.md）" -f $rel, $skName); continue }
            $pt = [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8)
            if ($pt -notmatch [regex]::Escape(".agents/skills/$skName/SKILL.md")) { Add-Err ("[E6 指针] {0} 未指向 .agents/skills/{1}/SKILL.md" -f $rel, $skName) }
            if ((Get-FmField $pt 'description') -ne $skDesc) { Add-Err ("[E6 指针] {0} 的 description 与 .agents/skills/{1}/SKILL.md 不一致" -f $rel, $skName) }
            if ((Get-FmField $pt 'name') -ne $skName) { Add-Err ("[E6 指针] {0} 的 name 应为 {1}" -f $rel, $skName) }
        }
    }
}

# 存量基线：本规则上线前写下的引用不追诉，只拦新增（正典 = AI_Script/lint-docs-e14-baseline.json）
$e14Base = @{}
$e14BasePath = Join-Path $PSScriptRoot 'lint-docs-e14-baseline.json'
if (Test-Path -LiteralPath $e14BasePath -PathType Leaf) {
    try {
        $e14Json = Get-Content -LiteralPath $e14BasePath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($sec in @('e14','e15','e16','e9bare')) { $e14Base[$sec] = @{}; foreach ($p in $e14Json.baseline.$sec.PSObject.Properties) { $e14Base[$sec][$p.Name] = [int]$p.Value } }
    } catch { Add-Warn '[E14] 基线文件解析失败，按无基线处理' }
}
# ---------- E7 JSON ----------
foreach ($j in @('AI_Script\code-anchors.json', 'AI_Script\protected-paths.json', 'AI_docs\glossary.json')) {
    $p = Join-Path $projectRoot $j
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { Add-Err ("[E7 JSON] 缺失 {0}" -f $j); continue }
    try { Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null }
    catch { Add-Err ("[E7 JSON] 解析失败 {0}：{1}" -f $j, $_.Exception.Message) }
}

# ---------- E8 脚本语法 ----------
# 扫描面 = AI_Script 顶层（模块自带脚本若另有目录，在此追加）
$syntaxDirs = @($scriptDir)
foreach ($s in ($syntaxDirs | Where-Object { Test-Path -LiteralPath $_ } | ForEach-Object { Get-ChildItem -LiteralPath $_ -File -Filter *.ps1 })) {
    $tokens = $null; $errs = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($s.FullName, [ref]$tokens, [ref]$errs)
    if ($errs -and $errs.Count -gt 0) { Add-Err ("[E8 语法] {0} :: {1}" -f $s.Name, $errs[0].Message) }
}

$bareRaw = @{}
# ---------- E9 章节号交叉引用 ----------
# 目的：`XXX.md` §5.1 这类引用必须落在真实存在的章节上（历史事故：引用到已被改名/删除的章节）。
$mdIndex = New-Object System.Collections.ArrayList
foreach ($root in @('AI_docs', '.agents')) {
    Get-ChildItem -LiteralPath (Join-Path $projectRoot $root) -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -eq '.md' } |
        ForEach-Object { [void]$mdIndex.Add($_.FullName) }
}
$headCache = @{}
function Get-Heads([string]$path) {
    if ($headCache.ContainsKey($path)) { return , $headCache[$path] }
    $arr = New-Object System.Collections.ArrayList
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $txt = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
        # 章节标题两种写法都认：数字编号标题（如 `## 5. 某标题`）与带 § 前缀的标题（如 `## §0 节索引`）——
        # 不认 § 写法会把档案里明明有的第 0 节误判成裸号悬空引用。
        foreach ($hm in [regex]::Matches($txt, '(?m)^#{2,4}\s+§?\s*(\d+(?:\.\d+)?)')) { [void]$arr.Add($hm.Groups[1].Value) }
    }
    $headCache[$path] = $arr
    return , $arr
}
$secRx = [regex]'([A-Za-z\u4e00-\u9fff0-9_\-\./]{2,120}\.md)`?\s*§\s*(\d+(?:\.\d+)?)'
$selfRx = [regex]'本文件\s*§\s*(\d+(?:\.\d+)?)'
foreach ($f in $scanFiles) {
    if ($f -notmatch '\.md$') { continue }
    $t = $scanTexts[$f]
    $curSet = Get-Heads $f
    foreach ($m in [regex]::Matches($t, $selfRx)) {
        $sec = $m.Groups[1].Value
        if ($curSet -notcontains $sec) { Add-Err ("[E9 章节号] {0} :: 本文件 §{1} 不存在" -f (Rel $f), $sec) }
    }
    # 裸 §N（同一行内**没有**任何 `.md` 文件名时）：一律解析为**本文件**章节号。
    # 这是"拆分/改名后留下悬空引用"的机械防线。判据刻意窄，宁漏不误：
    #   ① 同一行出现过 `.md` ⇒ 视为"文件名 + §N"引用，交给下面的 secRx，不在此判；
    #   ② 同一行出现过"本文件 / 本节 / 本文" ⇒ 交给 selfRx，不在此判。
    $ln = 0
    foreach ($lineText in ($t -split "`n")) {
        $ln++
        if ($lineText -match '\.md') { continue }
        if ($lineText -match '本文件|本节|本文') { continue }
        foreach ($bm in [regex]::Matches($lineText, '§\s*(\d+(?:\.\d+)?)')) {
            $sec = $bm.Groups[1].Value
            if ($curSet -notcontains $sec) {
                $rk = (Rel $f)
                if (-not $bareRaw.ContainsKey($rk)) { $bareRaw[$rk] = New-Object System.Collections.Generic.List[string] }
                [void]$bareRaw[$rk].Add(('{0}:{1} 裸 §{2}' -f $rk, $ln, $sec))
            }
        }
    }
    foreach ($m in [regex]::Matches($t, $secRx)) {
        $ref = $m.Groups[1].Value
        $sec = $m.Groups[2].Value
        if ($ref -match '^[A-Za-z]:') { continue }
        # 解析为目标文件：先项目根路径，再相对当前文件目录，最后按唯一 basename 匹配
        $cand = New-Object System.Collections.ArrayList
        if ($ref -match '/') {
            $p2 = Join-Path (Split-Path -Parent $f) ($ref -replace '/', '\')
            if (Test-Path -LiteralPath $p2 -PathType Leaf) { [void]$cand.Add($p2) }
            $p3 = Join-Path (Split-Path -Parent $f) (Split-Path -Leaf $ref)
            if ((Test-Path -LiteralPath $p3 -PathType Leaf) -and ($cand -notcontains $p3)) { [void]$cand.Add($p3) }
            $p1 = Join-Path $projectRoot ($ref -replace '/', '\')
            if ((Test-Path -LiteralPath $p1 -PathType Leaf) -and ($cand -notcontains $p1)) { [void]$cand.Add($p1) }
        } else {
            $direct = Join-Path $projectRoot $ref
            if (Test-Path -LiteralPath $direct -PathType Leaf) { [void]$cand.Add($direct) }
            foreach ($hp in $mdIndex) { if ((Split-Path $hp -Leaf) -eq $ref) { [void]$cand.Add($hp) } }
        }
        if ($cand.Count -eq 0) {
            Add-Warn ("[E9 章节号] {0} :: 引用的 `{1}` 解析不到目标文件（跳过校验）" -f (Rel $f), $ref)
            continue
        }
        $ok = $false
        foreach ($c in $cand) { if ((Get-Heads $c) -contains $sec) { $ok = $true; break } }
        if (-not $ok) {
            $shown = if ($cand.Count -eq 1) { Split-Path -Leaf $cand[0] } else { ($cand | ForEach-Object { Split-Path -Leaf $_ }) -join '/' }
            Add-Err ("[E9 章节号] {0} :: `{1}` §{2} 不存在（已解析到 {3}，无该级标题）" -f (Rel $f), $ref, $sec, $shown)
        }
    }
}


# 裸号引用的存量基线（同 E14–E16 机制：只拦超出基线的新增）
$bareBase = if ($e14Base.ContainsKey('e9bare')) { $e14Base['e9bare'] } else { @{} }
foreach ($rk in $bareRaw.Keys) {
    $n = $bareRaw[$rk].Count
    $allow = if ($bareBase.ContainsKey($rk)) { [int]$bareBase[$rk] } else { 0 }
    if ($n -gt $allow) {
        for ($i = $allow; $i -lt $n; $i++) { Add-Err ("[E9 章节号] {0} :: 裸 §号在本文件不存在（若指别的文件，请在同一行写全 `文件名.md §N`；正典 = AI_Script/lint-docs-e14-baseline.json 的 baseline.e9bare）" -f $bareRaw[$rk][$i]) }
    }
}

# ---------- E10 编码与正典一致性 ----------
# E10a：含非 ASCII 的 .ps1 必须带 UTF-8 BOM —— 否则 PS 5.1 按 ANSI 读 → 中文注释乱码 → ParserError（历史事故：lint-docs.ps1 被工具链重写掉 BOM）
# 范围限定为 **git 已跟踪** 脚本：避免他人正在开发、尚未入库的脚本把门禁弄红（未跟踪文件由其作者入库时纳入校验）
$trackedScripts = @()
$e10aGit = Invoke-GitCapture -ProjectRoot $projectRoot -GitArgs @('ls-files', 'AI_Script/*.ps1')
if ($e10aGit.Ok) {
    foreach ($r in $e10aGit.Lines) { if ($r) { $trackedScripts += (Join-Path $projectRoot ($r -replace '/', '\')) } }
}
if ($trackedScripts.Count -eq 0) {
    Add-Warn '[E10a] 取不到 git 已跟踪名单（git 没起来或没返回），退化为磁盘全量扫描：未入库草稿也会被要求带 BOM'
    $trackedScripts = @(Get-ChildItem -LiteralPath $scriptDir -File -Filter *.ps1 | ForEach-Object { $_.FullName })
}
foreach ($sp in $trackedScripts) {
    $s = Get-Item -LiteralPath $sp -ErrorAction SilentlyContinue
    if (-not $s) { continue }
    $bytes = [System.IO.File]::ReadAllBytes($s.FullName)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $nonAscii = $false
    for ($i = 0; $i -lt $bytes.Length; $i++) { if ($bytes[$i] -gt 0x7F) { $nonAscii = $true; break } }
    if ($nonAscii -and -not $hasBom) {
        Add-Err ("[E10 编码] {0} 含非 ASCII 但无 UTF-8 BOM（PS 5.1 下会乱码/ParserError）" -f $s.Name)
    }
    # E10c：以 UTF-8 读回自检——无 BOM 且编码被破坏时首块会出现替换符（PS 5.1 ANSI 读法的模拟）
    $head = [System.IO.File]::ReadAllText($s.FullName, [System.Text.Encoding]::UTF8)
    if ($head.Length -gt 400) { $head = $head.Substring(0, 400) }
    if ($head.IndexOf([char]0xFFFD) -ge 0) {
        Add-Err ("[E10 编码] {0} 以 UTF-8 读回首块出现替换符 U+FFFD（编码已损坏）" -f $s.Name)
    }
}
# E10b：AGENTS.md 禁改区列出的 glob 必须与 protected-paths.json 一致（消灭第二份路径表漂移）
$ppPath = Join-Path $projectRoot 'AI_Script\protected-paths.json'
$agentsPath = Join-Path $projectRoot 'AGENTS.md'
if ((Test-Path -LiteralPath $ppPath -PathType Leaf) -and (Test-Path -LiteralPath $agentsPath -PathType Leaf)) {
    $pp = Get-Content -LiteralPath $ppPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $forbidden = @($pp.forbidden)
    $agentsText = [System.IO.File]::ReadAllText($agentsPath, [System.Text.Encoding]::UTF8)
    $listed = New-Object System.Collections.ArrayList
    foreach ($m in [regex]::Matches($agentsText, '`([^`\r\n]*/\*)`')) { [void]$listed.Add($m.Groups[1].Value) }
    if ($listed.Count -eq 0) {
        Add-Err '[E10 正典] AGENTS.md 未列出任何禁改 glob（应与 protected-paths.json 一致）'
    }
    foreach ($g in $forbidden) {
        if ($listed -notcontains $g) { Add-Err ("[E10 正典] AGENTS.md 缺少禁改 glob `{0}`（正典 = protected-paths.json）" -f $g) }
    }
    foreach ($g in $listed) {
        if ($forbidden -notcontains $g) { Add-Warn ("[E10 正典] AGENTS.md 列出的 `{0}` 不在 protected-paths.json（新增规则请先更新正典）" -f $g) }
    }
}

# （E11 预留：源体系的门禁通道口径检查，本工程无 Unity 双通道，未启用。）

# ---------- E12 历史叙述指纹（零历史纪律；规则本体 = AGENTS.md 文档状态纪律） ----------
$historyMust = @(
    '取代早先', '取代本条', '早先设计', '此前设计', '旧口径', '已作废', '已退役', '已退场', '已删除', '待回填',
    '经实测更正', '用户裁决 20\d\d-\d\d-\d\d', '用户 \d{4}-\d\d-\d\d 多次重申', '（用户裁决 \d{4}',
    # 结构判据：判"日期/演变词与过程叙述同现"，而不是靠定长词表 —— 定长串漏检了全角逗号等写法
    '用户裁决[，,、]\s*\d{4}-\d{2}-\d{2}', '裁决[，,、]?\s*\d{4}-\d{2}-\d{2}',
    '(实测|复验|验收通过|关闭)[^。\n]{0,12}\d{4}-\d{2}-\d{2}', '\d{4}-\d{2}-\d{2}[^。\n]{0,10}(实测|复验|裁决)',
    '(旧版|原先|此前|此前默认)[^。\n]{0,40}(作废|失效|写死|退场|删除)', '我自己引入', '本轮只复验', '同批扩范围', '一句据此作废',
    '\d{4}-\d{2}-\d{2}[^。\n]{0,25}(修订|依 AGENTS|入册|登记|取证)', '(实测|复验|验收通过|关闭|取证|修订)[^。\n]{0,12}\d{4}-\d{2}-\d{2}', '第 \d+ 轮运行时取证', '运行时取证：')
$historyPass = @('零历史', '禁止', '历史唯一', 'git log')
foreach ($f in $scanFiles) {
    $rel = (Rel $f).Replace('\', '/')
    if (($rel -notmatch '^(\.agents/|AI_docs/)') -and ($rel -ne 'AGENTS.md')) { continue }
    if ($rel -match '(CODE_INDEX\.md|glossary\.json)$') { continue }
    $txt = Get-Content -LiteralPath $f -Raw -Encoding UTF8
    foreach ($ln in ($txt -split "`n")) {
        $hit = $null
        foreach ($m in $historyMust) { if ([regex]::IsMatch($ln, $m)) { $hit = $m; break } }
        if ($null -eq $hit) { continue }
        $ok = $false
        foreach ($p in $historyPass) { if ($ln.Contains($p)) { $ok = $true; break } }
        if ($ok) { continue }
        Add-Err ('[E12 历史叙述] {0} :: 命中 "{1}" —— 零历史纪律：记录整条删除或改写成最终态描述，历史查 git log' -f $rel, $hit)
    }
}

# ---------- E19 悬空编号（正文引用的裁决/风险编号必须在定义行存在） ----------
# 规则本体 = AGENTS.md「引用与表达纪律 · 引用自带解释」的配套：引用一个已被删除的编号，
# 读者按编号去台账里根本找不到东西 ⇒ 与"没有解释"等价。定义面 = 裁决册的 `- **D-xxx**` 行、风险册表格首列 `| R-xxx |`。
# 本项不给存量基线：悬空引用一律报错（已删除的编号不得再被引用）。
$defD = @{}; $defR = @{}; $defA = @{}
$decPath = @($scanFiles | Where-Object { (Rel $_).Replace('\', '/') -eq 'AI_docs/DECISION_LOG.md' })[0]
$riskPath = @($scanFiles | Where-Object { (Rel $_).Replace('\', '/') -eq 'AI_docs/RISK_REGISTER.md' })[0]
if ($decPath -and (Test-Path -LiteralPath $decPath)) {
    foreach ($m in [regex]::Matches((Get-Content -LiteralPath $decPath -Raw -Encoding UTF8), '(?m)^\s*-\s+\*\*(D-\d{3})\*\*')) { $defD[$m.Groups[1].Value] = $true }
}
if ($riskPath -and (Test-Path -LiteralPath $riskPath)) {
    foreach ($m in [regex]::Matches((Get-Content -LiteralPath $riskPath -Raw -Encoding UTF8), '(?m)^\s*\|\s*(R-\d{3})\s*\|')) { $defR[$m.Groups[1].Value] = $true }
}
if ($decPath -and (Test-Path -LiteralPath $decPath)) {
    foreach ($m in [regex]::Matches((Get-Content -LiteralPath $decPath -Raw -Encoding UTF8), '(?m)^\s*-\s+\*\*(ADR-\d{3})[\s：]')) { $defA[$m.Groups[1].Value] = $true }
}
foreach ($f in $scanFiles) {
    $rel = (Rel $f).Replace('\', '/')
    if (($rel -notmatch '^AI_docs/') -and ($rel -notmatch '^\.agents/') -and ($rel -ne 'AGENTS.md')) { continue }
    if ($rel -match '(CODE_INDEX\.md|glossary\.json)$') { continue }
    # 台账正面也纳入：定义行的编号由 $defined 判据放行，其余引用一律要真实存在（独立审查反例：此前显式跳过两份台账 ⇒ 裁决册里的悬空引用永远拦不到）
    $txt = Get-Content -LiteralPath $f -Raw -Encoding UTF8
    $seen = @{}
    $ln = 0
    foreach ($lineText in ($txt -split "`n")) {
        $ln++
        foreach ($m in [regex]::Matches($lineText, '(?<![A-Za-z0-9])([DR]-\d{3}|ADR-\d{3})(?![0-9])')) {
            $id = $m.Groups[1].Value
            if ($seen.ContainsKey($id)) { continue }
            $seen[$id] = $true
            $defined = if ($id.StartsWith('D')) { $defD.ContainsKey($id) } elseif ($id.StartsWith('R')) { $defR.ContainsKey($id) } else { $defA.ContainsKey($id) }
            if ($defined) { continue }
            Add-Err ('[E19 悬空编号] {0}:{1} 引用了不存在的编号 {2}（台账里没有定义行；已删除的编号不得再引用）' -f $rel, $ln, $id)
        }
    }
}

# ---------- E14 引用自带解释（规则本体 = AGENTS.md「引用与表达纪律 · 引用自带解释」） ----------
# 判据（窄，宁漏不误）：文档**首次**出现 D-### / R-### 编号（台账裁决 / 未关闭风险）时，
#   该编号**所在行**必须自带一句"它是什么"——解释标记 = 全角/半角冒号、等号、破折号、是/即/指/见 之一；
#   或本文件已有**指针块**（顶部的"不在本文件成文的事实"式声明）覆盖它。
# 为什么只管首次：规则本体就是"首次提到才解释，同一份输出内后续不重复"。
$refBadgePat = '不在本文件成文|唯一正文|口径见|正文 =|正文=|引用约定'
$explainPat = '[：:=—]|是|即|指|见'
# 原始命中（供 -WriteBaseline 导出，计数口径与判错完全同源）
$e14Raw = @{}; $e15Raw = @{}; $e16Raw = @{}
foreach ($f in $scanFiles) {
    $rel = (Rel $f).Replace('\', '/')
    if (($rel -notmatch '^AI_docs/') -and ($rel -notmatch '^\.agents/') -and ($rel -ne 'AGENTS.md')) { continue }
    if ($rel -match '(CODE_INDEX\.md|glossary\.json)$') { continue }
    $txt = Get-Content -LiteralPath $f -Raw -Encoding UTF8
    $seen = @{}
    $fileHits = New-Object System.Collections.Generic.List[string]
    $ln = 0
    foreach ($lineText in ($txt -split "`n")) {
        $ln++
        # 指针块只豁免它自己那一行：整份豁免等于一行"引用约定"把 E14 关掉
        if ([regex]::IsMatch($lineText, $refBadgePat)) { continue }
        foreach ($m in [regex]::Matches($lineText, '(?<![A-Za-z0-9])([DR]-\d{3})(?![0-9])')) {
            $id = $m.Groups[1].Value
            if ($seen.ContainsKey($id)) { continue }
            $seen[$id] = $true
            # 豁免：编号出现在**表格首列**时 = 该行自身的身份（同行内有等级与描述），不算缺解释的引用
            if ($lineText -match ('^\s*\|\s*' + [regex]::Escape($id) + '\s*\|')) { continue }
            # 豁免：编号位于行首（`- **D-001** …`）= 该条自身的定义行，行内正文就是它的解释
            if ($lineText -match ('^\s*(?:[-*+]\s+)?\*{0,2}' + [regex]::Escape($id) + '\*{0,2}(?:\s|$)')) { continue }
            if (Test-RefGlossed $lineText $m $explainPat) { continue }
            $fileHits.Add(('{0}:{1} 首次出现 {2}' -f $rel, $ln, $id))
        }
    }
    if ($fileHits.Count -eq 0) { continue }
    $e14Raw[$rel] = $fileHits
    $allow = if ($e14Base['e14'].ContainsKey($rel)) { $e14Base['e14'][$rel] } else { 0 }
    if ($fileHits.Count -gt $allow) {
        for ($i = $allow; $i -lt $fileHits.Count; $i++) {
            Add-Err ('[E14 引用无解释] {0} —— 首次出现该编号却没写"它是什么"（规则 = AGENTS.md「引用自带解释」，存量基线 = AI_Script/lint-docs-e14-baseline.json）' -f $fileHits[$i])
        }
    } elseif ($fileHits.Count -lt $allow) {
        Add-Warn ('[E14 基线可收紧] {0} :: 实测 {1} 条 < 基线 {2} 条，请下调 AI_Script/lint-docs-e14-baseline.json 的 baseline.e14 段里该条目' -f $rel, $fileHits.Count, $allow)
    }
}

# ---------- E15 引用自带解释（编号族；E14 只认 D-/R-，这里补 ADR-### / ST- / S3- / §N / E<n> / B<nn>） ----------
# 与 E14 同一规则本体（AGENTS.md「引用自带解释」），只换编号族：把 ADR-019、ST-5、§3.1、E9 这类
# "名字看不出是什么"的记号也纳入。判据同样窄：首次出现时所在行要自带解释标记，或本文件已有指针块。
# 存量基线沿用 e14 的每文件条数（两类命中合并计数），只拦新增。
$idFamPat = '(?<![A-Za-z0-9])(ADR-\d{3}|ST-\d{1,2}|S3-\d|§\d+-\d+|§\d+(?:\.\d+)*|E\d{1,2}(?![\d-])|B\d{2})(?![0-9])'
foreach ($f in $scanFiles) {
    $rel = (Rel $f).Replace('\', '/')
    if (($rel -notmatch '^AI_docs/') -and ($rel -notmatch '^\.agents/') -and ($rel -ne 'AGENTS.md')) { continue }
    if ($rel -match '(CODE_INDEX\.md|glossary\.json)$') { continue }
    $txt = Get-Content -LiteralPath $f -Raw -Encoding UTF8
    $seen = @{}
    $famHits = New-Object System.Collections.Generic.List[string]
    $ln = 0
    foreach ($lineText in ($txt -split "`n")) {
        $ln++
        # 同 E14：指针块只豁免它自己那一行
        if ([regex]::IsMatch($lineText, $refBadgePat)) { continue }
        foreach ($m in [regex]::Matches($lineText, $idFamPat)) {
            $id = $m.Groups[1].Value
            if ($seen.ContainsKey($id)) { continue }
            $seen[$id] = $true
            if ($lineText -match ('^\s*\|\s*' + [regex]::Escape($id) + '\s*\|')) { continue }
            # 同 E14：行首编号 = 该条自身的定义行
            if ($lineText -match ('^\s*(?:[-*+]\s+)?\*{0,2}' + [regex]::Escape($id) + '\*{0,2}(?:\s|$)')) { continue }
            if (Test-RefGlossed $lineText $m $explainPat) { continue }
            $famHits.Add(('{0}:{1} 首次出现 {2}' -f $rel, $ln, $id))
        }
    }
    if ($famHits.Count -eq 0) { continue }
    $e15Raw[$rel] = $famHits
    $allow = if ($e14Base['e15'].ContainsKey($rel)) { $e14Base['e15'][$rel] } else { 0 }
    if ($famHits.Count -gt $allow) {
        for ($i = $allow; $i -lt $famHits.Count; $i++) {
            Add-Err ('[E15 引用无解释] {0} —— 编号族记号首次出现却没写"它是什么"（规则 = AGENTS.md「引用自带解释」，存量基线 = AI_Script/lint-docs-e14-baseline.json）' -f $famHits[$i])
        }
    }
}

# ---------- E16 自相矛盾 / 残留状态指纹（规则本体 = AGENTS.md「文档状态纪律」） ----------
# 只机械判六类"同一份文档自己前后打架"或"状态标记留在正文里"的指纹：
#   ① 同一文件出现完全相同的 ## 标题（通常是改文档时留下两版标题）
#   ② 同一张表里出现完全相同的表格行（重复条目）
#   ③ 同一表格行里同时出现"待裁决/待定"与"已裁决/已定"
#   ④ 正文残留流程状态标记（已实施／已落地／已修复／已验证／待运行期验证／里程碑式打勾名）
#   ⑤ "口径见/正文 =/唯一正文"指针行里同时出现"见本文件/本节"（自指指针）
#   ⑥ 同一行同时出现"已删除/已退场"与"读 pose/继续走/保留该分支"（删了却还描述它活着）
# 存量基线同 E14/E15（lint-docs-e14-baseline.json 的 baseline.e16 段），只拦新增。
$e16PatStatus = '已实施|已落地|已修复|已解决|已关闭|已验证|已复核|运行期验收通过|待运行期验证|待人工验收|里程碑'
$e16PatSelfPointer = '(口径见|正文 ?=|唯一正文)'
# 注意：E16 不套用 E14/E15 的"顶部有指针块即整份跳过"——那会让指针块多的文档整份免疫。
$e16Hits = @{}
foreach ($f in $scanFiles) {
    $rel = (Rel $f).Replace('\', '/')
    if (($rel -notmatch '^(\.agents/|AI_docs/)') -and ($rel -ne 'AGENTS.md')) { continue }
    if ($rel -match '(CODE_INDEX\.md|glossary\.json)$') { continue }
    $txt = Get-Content -LiteralPath $f -Raw -Encoding UTF8
    $lines = $txt -split "`n"
    $fileHits = New-Object System.Collections.Generic.List[string]
    # ① 重复标题
    $heads = @{}
    $ln = 0
    foreach ($l in $lines) {
        $ln++
        if ($l -match '^(#{2,4})\s+(.+?)\s*$') {
            $key = $Matches[1] + '|' + $Matches[2]
            if ($heads.ContainsKey($key)) { $fileHits.Add(('{0}:{1} 重复标题「{2}」（另见第 {3} 行）' -f $rel, $ln, $Matches[2], $heads[$key])) }
            else { $heads[$key] = $ln }
        }
    }
    # ② 重复表格行 + ③ 同行 待裁决/已裁决 并存（②只认**同一小节内**的重复：跨小节的同名行是正常结构）
    $rows = @{}
    $curSection = '(文件头)'
    $ln = 0
    foreach ($l in $lines) {
        $ln++
        if ($l -match '^#{1,4}\s+(.+?)\s*$') { $curSection = $Matches[1]; $rows = @{} }
        if ($l -match '^\s*\|.*\|\s*$') {
            $trim = $l.Trim()
            if ($trim -notmatch '^\|[\s\-:|]+\|$') {
                $key = $curSection + '||' + $trim
                if ($rows.ContainsKey($key)) { $fileHits.Add(('{0}:{1} 同一小节「{2}」内重复表格行（另见第 {3} 行）' -f $rel, $ln, $curSection, $rows[$key])) }
                else { $rows[$key] = $ln }
            }
            if ($trim -match '待裁决|待定' -and $trim -match '已裁决|已定') { $fileHits.Add(('{0}:{1} 同一行"待裁决/待定"与"已裁决/已定"并存' -f $rel, $ln)) }
        }
    }
    # ④ 残留流程状态标记 ⑤ 自指指针 ⑥ 删了却还描述它活着
    $ln = 0
    foreach ($l in $lines) {
        $ln++
        if ($rel -notmatch 'EXECUTION_PLAN|PROJECT_STATUS|HANDOFFS/|RISK_REGISTER|MODULE_REGISTER|AGENT_WORK_PROTOCOL|README') {
            if ([regex]::IsMatch($l, $e16PatStatus)) { $fileHits.Add(('{0}:{1} 正文残留流程状态标记（"{2}"）——状态只进台账/队列' -f $rel, $ln, ([regex]::Match($l, $e16PatStatus).Value))) }
        }
        if ([regex]::IsMatch($l, $e16PatSelfPointer) -and ($l -match '见本文件|本节')) { $fileHits.Add(('{0}:{1} 自指指针（"见本文件/本节"）' -f $rel, $ln)) }
        if ($l -match '已删除|已退场' -and $l -match '读 pose|继续走|保留该分支|仍然生效') { $fileHits.Add(('{0}:{1} "已删除/已退场"却仍按活着描述' -f $rel, $ln)) }
    }
    if ($fileHits.Count -gt 0) { $e16Hits[$rel] = $fileHits; $e16Raw[$rel] = $fileHits }
}
$e16Base = if ($e14Base.ContainsKey('e16')) { $e14Base['e16'] } else { @{} }
foreach ($rel in $e16Hits.Keys) {
    $hits = $e16Hits[$rel]
    $allow = if ($e16Base.ContainsKey($rel)) { [int]$e16Base[$rel] } else { 0 }
    if ($hits.Count -gt $allow) {
        for ($i = $allow; $i -lt $hits.Count; $i++) { Add-Err ('[E16 自相矛盾/残留] {0}（存量基线 = AI_Script/lint-docs-e14-baseline.json 的 baseline.e16 段）' -f $hits[$i]) }
    } elseif ($hits.Count -lt $allow) {
        Add-Warn ('[E16 基线可收紧] {0} :: 实测 {1} 条 < 基线 {2} 条，请下调基线 baseline.e16 段里该条目' -f $rel, $hits.Count, $allow)
    }
}

# ---------- E17 技能/命令 frontmatter 编码（BOM 防线） ----------
# 宿主 frontmatter 解析要求文件首行严格为 `---`：UTF-8 BOM 会使首行匹配失败，整个前言错位
# （历史事故：PowerShell 写技能指针带 BOM → Qoder 技能列表把 description 显示成 "---"）。
# 与 E10a 相反：.ps1 含非 ASCII 必须带 BOM，技能/命令 .md 一律禁 BOM。
$e17Files = New-Object System.Collections.ArrayList
foreach ($base in @('.agents', '.qoder', '.zcode')) {
    $sd = Join-Path $projectRoot (Join-Path $base 'skills')
    if (Test-Path -LiteralPath $sd -PathType Container) {
        Get-ChildItem -LiteralPath $sd -Recurse -File -Filter 'SKILL.md' | ForEach-Object { [void]$e17Files.Add($_.FullName) }
    }
}
foreach ($cd in @('.agents\commands', '.zcode\commands')) {
    $full = Join-Path $projectRoot $cd
    if (Test-Path -LiteralPath $full -PathType Container) {
        Get-ChildItem -LiteralPath $full -File -Filter '*.md' | ForEach-Object { [void]$e17Files.Add($_.FullName) }
    }
}
foreach ($mf in ($e17Files | Sort-Object -Unique)) {
    $bytes = [System.IO.File]::ReadAllBytes($mf)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        Add-Err ("[E17 frontmatter] {0} :: 首字节带 UTF-8 BOM（宿主前言解析错位，description 会被读成 `---`；剥 BOM：Get-Content -Raw 后以 UTF8Encoding(false) 重写）" -f (Rel $mf))
    } elseif ($bytes.Length -lt 3) {
        Add-Err ("[E17 frontmatter] {0} :: 文件过短/为空，宿主加载不到 name/description" -f (Rel $mf))
    } elseif ([System.Text.Encoding]::UTF8.GetString($bytes[0..2]) -ne '---') {
        Add-Err ("[E17 frontmatter] {0} :: 首行不是 `---`（无前言或前言破损）" -f (Rel $mf))
    }
}

# ---------- E18 AI 文档 md 禁 UTF-8 BOM（规则本体 = AGENTS.md「文档状态纪律 · 文件编码」） ----------
# 整写文件的通道（工具的 Write、refresh-code-index.ps1 的行号漂移回写）一律按无 BOM 写；带 BOM 的文档每次被
# 整写都掉一次 BOM，git diff 就多出一行"首行被改"的无关变更。口径统一为无 BOM 后该噪声不再出现。
# 与 E10a 相反：AI_Script/*.ps1 含非 ASCII 必须带 BOM（PS 5.1 无 BOM 按 ANSI 读 → 中文乱码/ParserError）。
# 扫描面 = **git 已跟踪**的 AI 文档面 .md 与 .json（与 E10a 同判据：别人正在写、尚未入库的草稿不该把门禁弄红）。
# 取 git 输出必须带 `-c core.quotepath=off`——中文文件名否则被转义成 "\346\200..." 形式，比对不上号就变成静默漏扫。
$e18Tracked = @{}
$e18Git = Invoke-GitCapture -ProjectRoot $projectRoot -GitArgs @('-c', 'core.quotepath=off', 'ls-files', '*.md', '*.json')
if ($e18Git.Ok) {
    foreach ($l in $e18Git.Lines) { if ($l) { $e18Tracked[$l.Replace('/', '\')] = $true } }
}
if ($e18Tracked.Count -eq 0) { Add-Warn '[E18] 取不到 git 已跟踪名单（git 没起来或没返回），本次退化为磁盘全量兜底——"只查已入库文件"的范围失效' }
$e18Files = @($scanFiles | Where-Object { $_ -match '\.(md|json)$' })
$e18Files += @(Get-ChildItem -LiteralPath $scriptDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in @('.md', '.json') } | ForEach-Object { $_.FullName })
foreach ($f in ($e18Files | Sort-Object -Unique)) {
    if ($e18Tracked.Count -gt 0 -and -not $e18Tracked.ContainsKey((Rel $f))) { continue }
    $bytes = [System.IO.File]::ReadAllBytes($f)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        Add-Err ("[E18 编码] {0} :: 首字节带 UTF-8 BOM（AI 文档与数据文件一律无 BOM；整份按目标编码重写即可剥掉，勿按字节截取）" -f (Rel $f))
    }
}

# ---------- E22 脚本语法（.py） ----------
# 为什么加：.py 此前完全无机检（E8 只管 .ps1）。范围 = git 已跟踪的全部 .py（排除 node_modules）；
# python 不可用则降级为 WARN，不伪装成通过。
$pyGit = Invoke-GitCapture -ProjectRoot $projectRoot -GitArgs @('-c', 'core.quotepath=false', 'ls-files', '--cached', '--others', '--exclude-standard')
$pyList = @()
if ($pyGit.Ok) { $pyList = @($pyGit.Lines | Where-Object { $_ -match '\.py$' -and $_ -notmatch '(^|/)node_modules/' }) }
if ($pyList.Count -eq 0) {
    Add-Warn '[E22] 取不到 git 已跟踪的 .py 名单，脚本语法检查本轮跳过（未取证）'
} else {
    $pyExe = Get-Command python -ErrorAction SilentlyContinue
    if (-not $pyExe) {
        Add-Warn '[E22] 找不到 python，.py 语法检查降级为未取证'
    } else {
        foreach ($r in $pyList) {
            $fp = Join-Path $projectRoot ($r -replace '/', '\\')
            if (-not (Test-Path -LiteralPath $fp)) { continue }
            $out = & python -c "import py_compile,sys; py_compile.compile(sys.argv[1], doraise=True)" $fp 2>&1
            if ($LASTEXITCODE -ne 0) { Add-Err ("[E22 语法] {0} :: {1}" -f $r, ($out | Select-Object -First 1)) }
        }
    }
}

# ---------- E20 字节级替换符（真实存储的 EF BB BD 三字节）----------
# 规则本体 = 编码归一口径：入库文本文件不得携带 UTF-8 替换符字节——那是"按 UTF-8 读 + 把坏字节替换掉"式
# 坏转码的残留，原字符已丢失且不可复原。按**字节**扫而不是按解码后的 U+FFFD 扫：GBK 等非 UTF-8 文件按
# UTF-8 解码本来就会出现 U+FFFD，那不是存储的替换符，不能拿去当证据。
# 扫描面 = git 已跟踪的文本扩展名文件；扩展名清单写死在下面并注明用途：
#   .cs/.hlsl/.shader/.cginc/.proto/.py  源码（着色器含中文注释，历史上被坏转码打过）
#   .md/.json/.txt/.xml/.yml/.yaml/.csv  文档与数据
#   .ps1/.asmdef                          脚本与程序集定义
# 取 git 名单同 E18：必须带 `-c core.quotepath=off`，否则中文路径被转义成 "\346..." 比对不上号就整批漏扫。
# 字节扫描用 Latin-1（28591，字节↔字符一一对应）映射成串再 IndexOf——PS 5.1 下逐字节 for 循环扫几千个
# 文件会慢到不可用，IndexOf 走 .NET 内部实现。git 名单取不到时按 E18 同款退化为 WARN + 跳过（宁可漏扫也不
# 拿空名单当"全绿"）。
$e20Tracked = @{}
$e20Git = Invoke-GitCapture -ProjectRoot $projectRoot -GitArgs @('-c', 'core.quotepath=off', 'ls-files')
if ($e20Git.Ok) {
    foreach ($l in $e20Git.Lines) { if ($l) { $e20Tracked[$l.Replace('/', '\')] = $true } }
}
if ($e20Tracked.Count -eq 0) {
    Add-Warn '[E20 替换符] 取不到 git 已跟踪名单（git 没起来或没返回），字节级替换符检查本次跳过'
} else {
    $e20Exts = @('.cs', '.hlsl', '.shader', '.cginc', '.proto', '.py', '.md', '.json', '.txt', '.xml', '.yml', '.yaml', '.csv', '.ps1', '.asmdef')
    $e20Needle = [string][char]0xEF + [string][char]0xBB + [string][char]0xBD
    $e20Latin = [System.Text.Encoding]::GetEncoding(28591)
    foreach ($kv in $e20Tracked.Keys) {
        if ($e20Exts -notcontains [System.IO.Path]::GetExtension($kv)) { continue }
        $e20Path = Join-Path $projectRoot $kv
        if (-not (Test-Path -LiteralPath $e20Path -PathType Leaf)) { continue }   # 已暂存删除/未检出的条目不扫
        $e20Bytes = [System.IO.File]::ReadAllBytes($e20Path)
        if ($e20Latin.GetString($e20Bytes).IndexOf($e20Needle) -ge 0) {
            Add-Err ("[E20 替换符] {0} :: 存在真实存储的 UTF-8 替换符字节（EF BB BD）——内容已损坏不可复原，请从源头重新导出/按原编码重取文本，禁止就地再替换" -f $kv)
        }
    }
}

# ---------- 基线导出（-WriteBaseline）：用本脚本自己的计数生成 E14/E15/E16 存量基线 ----------
if ($WriteBaseline) {
    # fail-closed：扫描面为空时禁止导出。收集扫描面用了 -ErrorAction SilentlyContinue，
    # 并行会话正在写文件时 Get-ChildItem 可能一条都不返回，那会让 -WriteBaseline 把整份基线洗成 0 并照常入库
    # （实测出现过一次 e14=0/e15=0/e16=0 的空导出），下一个运行版本按空基线判就全是误报。
    $scanMdCount = @($scanFiles | Where-Object { $_ -match '\.md$' }).Count
    if ($scanMdCount -lt 10) {
        Write-Host ('[baseline] 拒绝导出：扫描面只取到 {0} 个 .md（疑 enumeration 失败/仓不可读），基线未被改写' -f $scanMdCount) -ForegroundColor Red
        exit 1
    }
    $outBase = [ordered]@{ e14 = [ordered]@{}; e15 = [ordered]@{}; e16 = [ordered]@{}; e9bare = [ordered]@{} }
    foreach ($k in $e14Raw.Keys) { if ($e14Raw[$k].Count -gt 0) { $outBase['e14'][$k] = $e14Raw[$k].Count } }
    foreach ($k in $e15Raw.Keys) { if ($e15Raw[$k].Count -gt 0) { $outBase['e15'][$k] = $e15Raw[$k].Count } }
    foreach ($k in $e16Raw.Keys) { if ($e16Raw[$k].Count -gt 0) { $outBase['e16'][$k] = $e16Raw[$k].Count } }
    foreach ($k in $bareRaw.Keys) { if ($bareRaw[$k].Count -gt 0) { $outBase['e9bare'][$k] = $bareRaw[$k].Count } }
    $payload = [ordered]@{
        _why = 'E14/E15/E16 的存量基线：规则上线前写下的引用与残留状态标记免追诉，只拦超出基线的新增；实测低于基线时提示收紧。修完某文件后删除或下调其条目。生成方式 = AI_Script/lint-docs.ps1 -WriteBaseline（勿手算）。'
        baseline = $outBase
    }
    # 输出必须跨 PowerShell 版本逐字节一致：实测 PS 5.1 与 PS7 的 ConvertTo-Json 在缩进、"键: 值" 冒号
    # 空格、字典序上都不一样，而这个基线文件要入库——排版随运行版本变，每次重导就是一次整份 diff。
    # 因此手写序列化：固定 2 空格缩进、键按 Ordinal 升序、LF 换行、UTF-8 无 BOM。
    function Get-JsonStr([string]$s) {
        return ($s -replace '\\', '\\\\' -replace '"', '\"')
    }
    $sbBase = New-Object System.Text.StringBuilder
    [void]$sbBase.AppendLine('{')
    [void]$sbBase.AppendLine('  "_why": "' + (Get-JsonStr ([string]$payload._why)) + '",')
    [void]$sbBase.AppendLine('  "baseline": {')
    $secNames = @('e14', 'e15', 'e16', 'e9bare')
    for ($si = 0; $si -lt $secNames.Count; $si++) {
        $sec = $secNames[$si]
        $map = $outBase[$sec]
        $keys = New-Object string[] @($map.Keys).Count
        @($map.Keys).CopyTo($keys, 0)
        [Array]::Sort($keys, [System.StringComparer]::Ordinal)
        $pad = '    '
        if ($keys.Count -eq 0) {
            [void]$sbBase.AppendLine($pad + '"' + $sec + '": {}' + $(if ($si -lt $secNames.Count - 1) { ',' } else { '' }))
            continue
        }
        [void]$sbBase.AppendLine($pad + '"' + $sec + '": {')
        for ($ki = 0; $ki -lt $keys.Count; $ki++) {
            $comma = $(if ($ki -lt $keys.Count - 1) { ',' } else { '' })
            [void]$sbBase.AppendLine($pad + '  "' + (Get-JsonStr $keys[$ki]) + '": ' + $map[$keys[$ki]] + $comma)
        }
        [void]$sbBase.AppendLine($pad + '}' + $(if ($si -lt $secNames.Count - 1) { ',' } else { '' }))
    }
    [void]$sbBase.AppendLine('  }')
    [void]$sbBase.AppendLine('}')
    [System.IO.File]::WriteAllText($e14BasePath, ($sbBase.ToString() -replace "`r`n", "`n"), (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ('[baseline] e14={0} e15={1} e16={2} (scanned {3} .md) → {4}' -f $outBase['e14'].Count, $outBase['e15'].Count, $outBase['e16'].Count, $scanMdCount, $e14BasePath)
    exit 0    # 导出模式到此为止：本次运行用的还是内存里的旧基线，不能顺手判错
}
# ---------- 汇总 ----------
Write-Host '=== lint-docs ==='
if ($All) {
    # 修文件/收紧基线时用：列出全部命中（默认只打 40 条，够看结论不够改）
    $errors | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    $warns  | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkYellow }
} elseif (-not $Quiet) {
    $errors | Select-Object -First 40 | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    $warns  | Select-Object -First 20 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkYellow }
} else {
    $errors | Select-Object -First 10 | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
}
if ((-not $All) -and $errors.Count -gt 40) { Write-Host ("  … 其余 {0} 条见重跑输出（加 -All 打全）" -f ($errors.Count - 40)) -ForegroundColor Red }
Write-Host ("RESULT: {0} error(s), {1} warn(s)  (scanned {2} file(s))" -f $errors.Count, $warns.Count, $scanFiles.Count) -ForegroundColor $(if ($errors.Count -gt 0) { 'Red' } elseif ($warns.Count -gt 0) { 'DarkYellow' } else { 'Green' })
exit $(if ($errors.Count -gt 0) { 1 } else { 0 })
