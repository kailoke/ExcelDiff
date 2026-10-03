<#
.SYNOPSIS
    会话开工简报：git 摘要 + 范围/锚点健康 + 活跃任务指针。降低会话冷启动的读档成本。

.DESCRIPTION
    输出一屏：
      1. 最近提交与工作区摘要（git）
      2. 范围/锚点健康（复用 verify-scope.ps1 的 SCOPE+ANCHORS 两段）
      3. 当前切片队列（EXECUTION_PLAN.md §8）
      4. 回复纪律提醒

.USAGE
    .\AI_Script\session-brief.ps1

.NOTE
    只读优先；锚点刷新由 verify-scope 内部的 refresh-code-index 完成。
#>

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
$scriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
# git 输出统一走 Invoke-GitCapture（受限环境里 PowerShell 捕获子进程 stdout 会失败）
. (Join-Path $scriptDir 'lib\common.ps1')

Write-Host '=== session-brief ==='
Write-Host ''
Write-Host '[1/4] Recent commits'
$recentRes = Invoke-GitCapture -ProjectRoot $projectRoot -GitArgs @('log', '--oneline', '-5')
if ($recentRes.Ok) { foreach ($l in @($recentRes.Lines)) { if ($l) { Write-Host "  $l" } } }
else { Write-Host ("  (git log 取不到：{0})" -f $recentRes.Error) -ForegroundColor Yellow }

Write-Host ''
Write-Host '[2/4] Gate (scope + anchors + lint, read-only)'
Write-Host '  编译+单测门禁 = AI_Script/verify.ps1（改码轮次跑 /gate-compile，即 verify-scope -Compile）'
& (Join-Path $scriptDir 'verify-scope.ps1') -ReadOnly

Write-Host ''
Write-Host '[3/4] Active tasks (AI_docs/EXECUTION_PLAN.md sec 8)'
$plan = Join-Path $projectRoot 'AI_docs\EXECUTION_PLAN.md'
if (Test-Path -LiteralPath $plan) {
$lines = Get-Content -LiteralPath $plan -Encoding UTF8
$start = 0
for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^## .*当前切片队列') { $start = $i + 1; break } }
if ($start) {
    $end = [math]::Min($start + 14, $lines.Count - 1)
    $lines[$start..$end] | ForEach-Object { Write-Host "  $_" }
} else {
    Write-Host '  (queue section not found)'
}
} else {
    Write-Host '  (missing)'
}

Write-Host ''
Write-Host '[4/4] Reply discipline (rules only, no host hooks)'
Write-Host '  给用户/业主的正文发出前：.\AI_Script\lint-reply.ps1 -Path <草稿>  （编号首次出现必须自带一句解释）'
Write-Host '  步骤 = AI_docs/AGENT_WORK_PROTOCOL.md「回复前自查」；规则本体 = AGENTS.md「引用自带解释」'
