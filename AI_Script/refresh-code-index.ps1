<#
.SYNOPSIS
    刷新代码锚点索引，并自动修复 AI_docs 里因代码改动产生的行号漂移。

.DESCRIPTION
    1. 读取 AI_Script/code-anchors.json（锚点注册表）。
    2. 对每个锚点，在其对应文件中用正则定位第一处匹配，得到当前行号。
    3. 重写 AI_docs/CODE_INDEX.md（机器生成，勿手改）。
    4. 扫描 AI_docs/**/*.md，修复形如以下的行内引用行号：
           Client/.../NetworkManager.cs#L428 <!-- anchor:NetworkManager.SendNenwordMessage -->
       每次代码改动后运行本脚本，即可把 #Lnnn 刷新为真实行号，避免行漂移。

.USAGE
    .\AI_Script\refresh-code-index.ps1              # 全量：重建索引 + 修复 AI_docs 行号漂移
    .\AI_Script\refresh-code-index.ps1 -IndexOnly   # 只重建 CODE_INDEX.md，不动 AI_docs 下任何文档
                                                    #   （给"不提交也要跑门禁"的只读检查用：不碰别的会话正在写的台账）
#>

param([switch]$IndexOnly)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$anchorsPath = Join-Path $scriptDir 'code-anchors.json'
$aiDocsDir = Join-Path $projectRoot 'AI_docs'
$indexPath = Join-Path $aiDocsDir 'CODE_INDEX.md'

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

if (-not (Test-Path -LiteralPath $anchorsPath -PathType Leaf)) {
    throw "Anchor registry not found: $anchorsPath"
}

$registry = Get-Content -LiteralPath $anchorsPath -Raw -Encoding UTF8 | ConvertFrom-Json

$anchorMap = @{}
$resolved = 0
$missing = @()
$fileCache = @{}   # 文件路径 -> 行数组：多个锚点同文件时只读一次

foreach ($a in $registry.anchors) {
    $fullPath = Join-Path $projectRoot ($a.file -replace '/', '\')
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        $missing += "file-not-found: $($a.id) -> $($a.file)"
        continue
    }

    if (-not $fileCache.ContainsKey($fullPath)) {
        $fileCache[$fullPath] = [System.IO.File]::ReadAllText($fullPath, [System.Text.Encoding]::UTF8) -split "`r?`n"
    }
    $lines = $fileCache[$fullPath]
    $lineNo = -1
    $matchedText = ''
    $matchCount = 0
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match $a.pattern) {
            $matchCount++
            if ($lineNo -lt 0) {
                $lineNo = $i + 1
                $matchedText = $lines[$i].Trim()
            }
        }
    }
    if ($matchCount -gt 1) {
        Write-Warning "Anchor $($a.id) pattern matched $matchCount times in $($a.file); using first match (line $lineNo). Tighten the pattern."
    }

    if ($lineNo -lt 0) {
        $missing += "pattern-not-matched: $($a.id) (pattern=$($a.pattern))"
        continue
    }

    $anchorMap[$a.id] = [pscustomobject]@{
        Id    = $a.id
        File  = $a.file
        Line  = $lineNo
        Note  = $a.note
        Match = $matchedText
    }
    $resolved++
}

# ---- 生成 CODE_INDEX.md ----
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('# CODE_INDEX（代码锚点索引）')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('> 本文件由 `AI_Script/refresh-code-index.ps1` 自动生成，请勿手改。每次修改代码后运行该脚本刷新行号。')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('生成时间：' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
[void]$sb.AppendLine('')
[void]$sb.AppendLine('解析成功：' + $resolved + ' 个锚点')
if ($missing.Count -gt 0) {
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('未解析：' + $missing.Count + ' 个')
}
[void]$sb.AppendLine('')
[void]$sb.AppendLine('| 锚点 ID | 文件 | 行号 | 说明 |')
[void]$sb.AppendLine('|---|---|---:|---|')
foreach ($id in ($anchorMap.Keys | Sort-Object)) {
    $v = $anchorMap[$id]
    [void]$sb.AppendLine(('| {0} | {1} | {2} | {3} |' -f $v.Id, $v.File, $v.Line, $v.Note))
}
[void]$sb.AppendLine('')
if ($missing.Count -gt 0) {
    [void]$sb.AppendLine('## 未解析锚点')
    [void]$sb.AppendLine('')
    foreach ($m in $missing) {
        [void]$sb.AppendLine('- ' + $m)
    }
}

# 内容实质未变时跳过写入（忽略生成时间戳行）：否则 pre-commit 每次跑刷新都会因时戳差异把 CODE_INDEX 弄脏，工作区永远无法收敛
$newContent = $sb.ToString()
$stripTimestamp = { param($t) ($t -split "`n" | Where-Object { $_ -notmatch '^生成时间：' }) -join "`n" }
$oldRaw = if (Test-Path -LiteralPath $indexPath) { [System.IO.File]::ReadAllText($indexPath, $utf8NoBom) } else { $null }
if ($null -eq $oldRaw -or (& $stripTimestamp $oldRaw) -ne (& $stripTimestamp $newContent)) {
    [System.IO.File]::WriteAllText($indexPath, $newContent, $utf8NoBom)
}

# ---- 修复 AI_docs 行号漂移 ----
$driftFixed = 0
$filesTouched = 0
$anchorComment = '<!--\s*anchor:([A-Za-z0-9_.\-]+)\s*-->'

if (-not $IndexOnly) {
Get-ChildItem -LiteralPath $aiDocsDir -Recurse -Filter *.md -File | ForEach-Object {
    $docPath = $_.FullName
    $docText = [System.IO.File]::ReadAllText($docPath, [System.Text.Encoding]::UTF8)
    $docLines = $docText -split "`r?`n"
    $changed = $false

    for ($i = 0; $i -lt $docLines.Count; $i++) {
        $line = $docLines[$i]
        if ($line -match $anchorComment) {
            $anchorId = $Matches[1]
            if ($anchorMap.ContainsKey($anchorId)) {
                $currentLine = $anchorMap[$anchorId].Line
                $newLine = [regex]::Replace($line, '#L\d+', "#L$currentLine")
                if ($newLine -ne $line) {
                    $docLines[$i] = $newLine
                    $changed = $true
                    $driftFixed++
                }
            }
            else {
                Write-Warning "Unknown anchor id in $($_.Name): $anchorId"
            }
        }
    }

    if ($changed) {
        # 按该文件原有的换行写回：AI_docs 的工作副本多为 LF，固定按 CRLF 整写会让 git status 出现
        # "有 M 但 diff 为空"的幽灵脏项（core.autocrlf 归一后换行差异不进 diff），共享工作区里每个会话的
        # 清洁度判断都会被带偏。
        $eol = if ($docText.Contains("`r`n")) { "`r`n" } else { "`n" }
        $joined = [string]::Join($eol, $docLines)
        [System.IO.File]::WriteAllText($docPath, $joined, $utf8NoBom)
        $filesTouched++
    }
}
}

Write-Host ("Resolved {0} anchors, {1} unresolved." -f $resolved, $missing.Count)
Write-Host ("Fixed {0} line drift reference(s) across {1} file(s)." -f $driftFixed, $filesTouched)
Write-Host ("Index written to: {0}" -f $indexPath)
