<#
.SYNOPSIS
    对"给用户/策划的回复正文"跑一遍引用自带解释自查（规则本体 = 根 AGENTS.md「引用与表达纪律 · 引用自带解释」）。

.DESCRIPTION
    为什么需要它：`lint-docs.ps1` 的 E14/E15 **只扫文件**（AGENTS.md、AI_docs/**、.agents/**），
    对话回复没有文件可扫 ⇒ 回复侧本来没有任何机械门禁。本脚本补的就是这一侧：
    把草稿正文交给它，它按与 E14/E15 同源的判据找出"裸编号"（首次出现却没写"它是什么"的编号）。

    覆盖的编号族：D-###（裁决）/ R-###（风险）/ Q-###（问题登记）/ C-<n>（缺陷项）/ ST-<n>（状态/条目号）/
    S3-<n> 与 P<n>-<X> 与 N<n>.<n>（切片）/ E<n>（取证或门禁检查项）/ B<nn>（阻塞或采样批次）/
    全大写任务名（如 CHEST-D1）/ §N（章节号）。

    判据（窄，宁漏不误）：编号所在行满足任一即算"自带解释"——
      ① 编号附近有解释标记（冒号 / 等号 / 破折号 / 是 / 即 / 指）；**回复侧不收"见"**——
         文档里"见 D-042"是合法的指针写法，回复里"见 D-042"仍是没解释的裸编号；
      ② 编号后紧跟一句括号补充（"D-042（小游戏离线经济口径）"）；
      ③ 编号位于一个 ≥6 字的括号补充内部（"（图鉴 + 携带预设，D-022）"）；
      ④ 编号在表格首列、或位于行首（该行就是这一条自身的定义）。
    它判不了语义，只拦"光秃秃一个编号"。**它不是唯一防线**：最终判据仍是"一个没参与过本项目讨论的人，
    只读这段能不能明白说的是哪件事"。

.USAGE
    # 自查一份草稿（推荐：把草稿先写到临时文件）
    .\AI_Script\lint-reply.ps1 -Path Client\Temp\reply-draft.md
    # 直接给一段文本
    .\AI_Script\lint-reply.ps1 -Text '见 D-042 与 R-036'
    # 管道
    Get-Content draft.md -Raw | .\AI_Script\lint-reply.ps1

.EXITCODE
    0 = 没有裸编号；1 = 有命中（逐条补齐后再跑）；2 = 用法/读文件失败。
#>
param(
    [string]$Path,
    [string]$Text,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$explainPat = '[：:=—]|是|即|指'
$idPat = '(?<![A-Za-z0-9])(D-\d{3}|R-\d{3}|Q-\d{3}|C-\d+|ST-\d+|S3-\d+|N\d+\.\d+|P\d+-[A-Z0-9]+|[A-Z]{2,}-[A-Z0-9]+|E\d{1,2}|B-?\d{1,2}|§\d+-\d+|§\d+(?:\.\d+)*)(?![0-9])'

# 与 lint-docs.ps1 的 Test-RefGlossed 同源：判据改动必须两处一起改（否则文件侧与回复侧口径漂移）
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

$body = $null
if ($PSBoundParameters.ContainsKey('Text')) { $body = $Text }
elseif ($Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Write-Host ("[lint-reply] 读不到草稿文件：{0}" -f $Path) -ForegroundColor Red
        exit 2
    }
    $body = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path).Path, [System.Text.Encoding]::UTF8)
} else {
    $piped = @($input)
    if ($piped.Count -gt 0) { $body = ($piped -join "`n") }
}
if ([string]::IsNullOrWhiteSpace($body)) {
    Write-Host '[lint-reply] 用法：-Path <草稿文件> 或 -Text <文本>（或管道输入）。见脚本头 .USAGE' -ForegroundColor Red
    exit 2
}

$hits = New-Object System.Collections.ArrayList
$seen = @{}
$ln = 0
foreach ($lineText in ($body -split "`r?`n")) {
    $ln++
    foreach ($m in [regex]::Matches($lineText, $idPat)) {
        $id = $m.Groups[1].Value
        if ($seen.ContainsKey($id)) { continue }
        $seen[$id] = $true
        if ($lineText -match ('^\s*\|\s*' + [regex]::Escape($id) + '\s*\|')) { continue }
        if ($lineText -match ('^\s*(?:[-*+]\s+)?\*{0,2}' + [regex]::Escape($id) + '\*{0,2}(?:\s|$)')) { continue }
        if (Test-RefGlossed $lineText $m $explainPat) { continue }
        [void]$hits.Add(('第 {0} 行 首次出现 {1}' -f $ln, $id))
    }
}

if (-not $Quiet) { Write-Host '=== lint-reply（回复侧引用自查） ===' }
foreach ($h in $hits) { Write-Host ("  [裸编号] {0}" -f $h) -ForegroundColor Red }
if ($hits.Count -eq 0) {
    if (-not $Quiet) { Write-Host 'RESULT: 0 个裸编号（判据窄，语义仍要自己过一遍）' -ForegroundColor Green }
    exit 0
}
Write-Host ("RESULT: {0} 个裸编号 —— 每个编号首次出现处补一句「它是什么」（括号里一句人话），或删掉编号改直说" -f $hits.Count) -ForegroundColor Red
exit 1
