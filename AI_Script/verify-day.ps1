<#
.SYNOPSIS
    日终批量门禁：对时间窗内的提交逐笔做静态审计（禁改区 / 台账同笔），再对 HEAD 跑一次重量门禁（范围+锚点+lint+编译单测）。

.DESCRIPTION
    分层依据（触发时机唯一出处 = AI_Script/README.md）：
      - 每笔提交：pre-commit-check.ps1（禁改区 / 锚点 / 文档 lint / 台账同笔），秒级，钩子已自动跑，无需本脚本。
      - 每轮改码：verify-scope.ps1（SCOPE+ANCHORS+LINT，秒级）。
      - 重量段：verify-scope -Compile（verify.ps1 全量：构建 + 31 用例 + lang 同步，分钟级）。
    本脚本把「逐提交」的重活降级为**纯 git 读**的静态审计（不需要 checkout、不需要构建），
    重量门禁只对 HEAD 跑一次——同一 HEAD 重复编译没有增量信息，而逐提交编译需为每个提交建临时
    worktree 并串行构建，代价远大于收益。

.USAGE
    .\AI_Script\verify-day.ps1                    # 今天 00:00 起的提交 + HEAD 编译门禁
    .\AI_Script\verify-day.ps1 -Since <yyyy-MM-dd>  # 指定起点（git 可解析的日期/时间）
    .\AI_Script\verify-day.ps1 -SkipCompile       # 只做静态审计（秒级/十秒级）

.EXITCODE
    0 = 无 FAIL；1 = 存在 FAIL（静态审计或 HEAD 重量门禁结论为失败）；2 = 环境错误（git 不可用）

.NOTE
    控制台输出用英文（跨控制台代码页稳定）；注释用中文。历史提交的禁改区命中一律记 FAIL。
#>

param(
    [string]$Since = '',
    [switch]$SkipCompile
)

$ErrorActionPreference = 'Stop'
$scriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir 'lib\common.ps1')
$projectRoot = Get-ProjectRoot -ScriptDir $scriptDir

if (-not $Since) { $Since = (Get-Date).ToString('yyyy-MM-dd') }

$fail = 0
$envProblems = 0
$warn = 0
Write-Host '=== verify-day (batch gate) ==='
Write-Host ("  Project : {0}" -f $projectRoot)
Write-Host ("  Since   : {0}" -f $Since)

# ---------- 1. 时间窗内提交 ----------
$logFmt = '%H' + [char]9 + '%ad' + [char]9 + '%s'
$logRes = Invoke-GitCapture -ProjectRoot $projectRoot -GitArgs @('log', "--since=$Since 00:00", '--date=iso', "--pretty=format:$logFmt")
if (-not $logRes.Ok) {
    Write-Host ('  ERROR: git log 取不到（{0}）' -f $logRes.Error) -ForegroundColor Red
    exit 2
}
$rawLog = $logRes.Lines

$commits = @()
foreach ($line in @($rawLog)) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $parts = "$line" -split [char]9
    if ($parts.Count -lt 3) { continue }
    $commits += [pscustomobject]@{ Hash = $parts[0]; When = $parts[1]; Subject = ($parts[2..($parts.Count - 1)] -join ' ') }
}

Write-Host ''
Write-Host ("[1/2] per-commit static audit ({0} commit(s))" -f $commits.Count)

if ($commits.Count -eq 0) {
    Write-Host '  (no commits in window)'
}

$rules = Get-ProtectedRules -ProjectRoot $projectRoot
$ledgerPath = 'AI_docs/PROJECT_STATUS.md'

foreach ($c in $commits) {
    $showRes = Invoke-GitCapture -ProjectRoot $projectRoot -GitArgs @('show', '--name-status', '--format=', '--no-renames', $c.Hash)
    if (-not $showRes.Ok) {
        Write-Host ("  WARN: git show 取不到 {0}（{1}）——该提交本轮未审计" -f $c.Hash, $showRes.Error) -ForegroundColor Red
        $envProblems++
        continue
    }
    $nameStatus = $showRes.Lines
    $paths = @()
    foreach ($l in @($nameStatus)) {
        if ([string]::IsNullOrWhiteSpace($l)) { continue }
        $cols = "$l" -split [char]9
        if ($cols.Count -lt 2) { continue }
        $paths += ($cols[$cols.Count - 1]).Replace('\', '/')
    }

    $hits = Get-ProtectedHits -Paths $paths -Rules $rules
    $hardHits = @($hits.Forbidden)
    $cautionCount = @($hits.Caution).Count

    # 判据唯一出处 = lib/common.ps1 的 Get-CodeChangedPaths（与 pre-commit 同一条）
    $codeTouched = (@(Get-CodeChangedPaths -ProjectRoot $projectRoot -Paths $paths -Base "$($c.Hash)^")).Count -gt 0
    $ledgerInCommit = @($paths | Where-Object { $_ -eq $ledgerPath }).Count -gt 0

    $verdict = 'PASS'
    $notes = @()
    if ($hardHits.Count -gt 0) { $verdict = 'FAIL'; $fail++; $notes += ("forbidden: " + ($hardHits -join ', ')) }
    if ($ledgerInCommit -eq $false -and $codeTouched) { $verdict = 'FAIL'; $fail++; $notes += 'code changed without PROJECT_STATUS.md in same commit' }
    if ($cautionCount -gt 0) { if ($verdict -eq 'PASS') { $verdict = 'WARN' }; $warn++; $notes += ("caution: " + $cautionCount + " file(s)") }

    $color = if ($verdict -eq 'FAIL') { 'Red' } elseif ($verdict -eq 'WARN') { 'Yellow' } else { 'Green' }
    Write-Host ("  [{0}] {1}  {2}  {3}" -f $verdict, $c.Hash.Substring(0, 8), $c.When, $c.Subject) -ForegroundColor $color
    foreach ($n in $notes) { Write-Host ("         - {0}" -f $n) -ForegroundColor DarkYellow }
}

# ---------- 2. HEAD 重量门禁 ----------
Write-Host ''
Write-Host '[2/2] HEAD heavy gates'

if ($SkipCompile) {
    Write-Host '  COMPILE: skipped (-SkipCompile)'
} else {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    & (Join-Path $scriptDir 'verify-scope.ps1') -Compile
    $scopeExit = $LASTEXITCODE
    $sw.Stop()
    Write-Host ("  verify-scope -Compile: exit={0}  elapsed={1:n1}s" -f $scopeExit, $sw.Elapsed.TotalSeconds)
    if ($scopeExit -eq 2) {
        Write-Host '  -> ENV: environment problem (git unavailable), not a code verdict' -ForegroundColor Yellow
        $envProblems++
    } elseif ($scopeExit -ne 0) {
        $fail++
    }
}

Write-Host ''
Write-Host ("=== Result: FAIL={0}  ENV={1}  WARN={2}  commit(s)={3} ===" -f $fail, $envProblems, $warn, $commits.Count)
if ($fail -gt 0) { exit 1 }
if ($envProblems -gt 0) { exit 2 }
exit 0
