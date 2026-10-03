<#
.SYNOPSIS
    新机/新克隆依赖自检：git / PowerShell / dotnet SDK / Python / hooksPath / AI 会话资产 / 构建参考程序集。
.DESCRIPTION
    默认只读检查并输出 PASS/WARN/FAIL；-Install 时自动补可自动补的项（hooksPath）。
    机器相关路径（Program Files 基目录、外部测试数据仓）走根目录 ProjectPaths.ps1，本脚本只验证它能解析。
.USAGE
    .\AI_Script\check-ai-deps.ps1
    .\AI_Script\check-ai-deps.ps1 -Install
.EXITCODE
    0 = 无 FAIL；1 = 存在 FAIL（缺硬依赖）。
#>
param([switch]$Install)

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $scriptDir
# git 输出统一走 Invoke-GitCapture（受限环境里 PowerShell 捕获子进程 stdout 会失败，会把 PASS 误报成 FAIL）
. (Join-Path $scriptDir 'lib\common.ps1')
$script:fail = 0
$script:warn = 0

function Ok([string]$m)   { Write-Host "  [PASS] $m" -ForegroundColor Green }
function Warn([string]$m) { Write-Host "  [WARN] $m" -ForegroundColor DarkYellow; $script:warn++ }
function Bad([string]$m)  { Write-Host "  [FAIL] $m" -ForegroundColor Red; $script:fail++ }

Write-Host '=== check-ai-deps ==='

# 1. git
if (Get-Command git -ErrorAction SilentlyContinue) {
    $gitVer = Invoke-GitCapture -ProjectRoot $root -GitArgs @('--version')
    if ($gitVer.Ok -and @($gitVer.Lines).Count -gt 0) { Ok ("git " + ($gitVer.Lines[0] -replace '^git version ', '')) }
    else { Bad ("git 取不到版本（{0}）" -f $gitVer.Error) }
} else { Bad 'git not found in PATH' }

# 2. PowerShell
Ok ("PowerShell " + $PSVersionTable.PSVersion.ToString())

# 3. dotnet SDK（构建工具链唯一入口：dotnet msbuild）
$dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
if ($dotnet) {
    $dnVer = Invoke-NativeCapture -FilePath 'dotnet' -Arguments @('--version')
    if ($dnVer.Ok -and @($dnVer.Lines).Count -gt 0) { Ok ("dotnet SDK " + @($dnVer.Lines | Where-Object { $_ })[0]) }
    else { Warn ("dotnet present but --version not readable ({0})" -f $dnVer.Error) }
} else { Bad 'dotnet not found in PATH - product build gate cannot run' }

# 4. 提交前/后钩子启用（每克隆一次）
$hpRes = Invoke-GitCapture -ProjectRoot $root -GitArgs @('config', 'core.hooksPath')
$hp = if (@($hpRes.Lines).Count -gt 0) { $hpRes.Lines[0].Trim() } else { '' }
if ($hp -eq '.githooks') {
    Ok 'core.hooksPath = .githooks'
} elseif ($Install) {
    $setRes = Invoke-GitCapture -ProjectRoot $root -GitArgs @('config', 'core.hooksPath', '.githooks')
    if ($setRes.Ok) { Ok 'core.hooksPath set to .githooks' } else { Bad ("设 core.hooksPath 失败：{0}" -f $setRes.Error) }
} else {
    Warn 'core.hooksPath not enabled (run with -Install, or: git config core.hooksPath .githooks)'
}

# 5. Python（bom 技能脚本与 lint-docs E22 的 .py 语法检查依赖）
$py = Get-Command python -ErrorAction SilentlyContinue
if ($py) {
    # python 代码串一律用单引号写：双引号会被 Invoke-NativeCapture 显式拒绝（cmd 带不过去）
    $verRes = Invoke-NativeCapture -FilePath 'python' -Arguments @('-c', 'import sys;print(sys.version.split()[0])')
    if ($verRes.Ok -and -not $verRes.Failed) { Ok ("python " + ((@($verRes.Lines | Where-Object { $_ }) -join ' '))) } else { Warn ("python present but not runnable ({0})" -f $verRes.Error) }
} else {
    Warn 'python not found in PATH - .py syntax check (lint-docs E22) and bom helper degrade to warnings'
}

# 6. 机器路径正典可解析（ProjectPaths.ps1：路径单一事实源）
$pp = Join-Path $root 'ProjectPaths.ps1'
if (Test-Path -LiteralPath $pp) {
    $ppRes = Invoke-NativeCapture -FilePath 'powershell' -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $pp, '-Print')
    if ($ppRes.Ok -and @($ppRes.Lines | Where-Object { $_ -match 'RepoRootPath' }).Count -gt 0) {
        $refsMissing = @($ppRes.Lines | Where-Object { $_ -match '\[MISSING\]' }).Count
        if ($refsMissing -gt 0) { Warn ("ProjectPaths.ps1 resolves but {0} path(s) MISSING (see -Print output)" -f $refsMissing) }
        else { Ok 'ProjectPaths.ps1 resolves (path single source of truth)' }
    } else { Warn 'ProjectPaths.ps1 -Print did not produce expected output' }
} else { Bad 'ProjectPaths.ps1 missing (path single source of truth)' }

# 7. .NET Framework 参考程序集（构建必需）
if (Test-Path -LiteralPath (Join-Path $root 'packages\refs\.NETFramework\v4.7.2\mscorlib.dll')) { Ok 'packages/refs/.NETFramework/v4.7.2 present (FrameworkPathOverride target)' }
else { Bad 'packages/refs/.NETFramework/v4.7.2 missing - dotnet msbuild cannot target net472' }

# 8. AI 会话资产
foreach ($p in @('AGENTS.md', 'AI_docs\ARCHITECTURE.md', 'AI_docs\PROJECT_STATUS.md', 'AI_docs\EXECUTION_PLAN.md',
        'AI_docs\DECISION_LOG.md', 'AI_docs\INVARIANTS.md', 'AI_Script\code-anchors.json', 'AI_Script\protected-paths.json',
        '.agents\skills\exceldiff-workflow\SKILL.md', '.agents\commands\gate.md')) {
    if (Test-Path -LiteralPath (Join-Path $root $p)) { Ok "asset $p" } else { Bad "missing $p" }
}

Write-Host ''
Write-Host ("RESULT: {0} fail, {1} warn" -f $script:fail, $script:warn) -ForegroundColor ($(if ($script:fail -gt 0) { 'Red' } elseif ($script:warn -gt 0) { 'DarkYellow' } else { 'Green' }))
exit $(if ($script:fail -gt 0) { 1 } else { 0 })
