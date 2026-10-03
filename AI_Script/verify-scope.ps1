<#
.SYNOPSIS
    主会话交叉验收门禁：改动范围校验 → 锚点健康检查 →（可选）产品构建+单测门禁。

.DESCRIPTION
    四段验收，一条命令：
      1. SCOPE   —— git status 的改动文件比对 AI_Script/protected-paths.json：
                    forbidden 命中 => FAIL；caution 命中 => WARN（需主会话确认授权）。
      1b. TASK SCOPE —— 仅 -TaskBrief 时执行：改动文件必须落在派发单的机读 SCOPE 行（允许 glob）
                    与固定台账面（AI_docs/**、AI_Script/code-anchors.json）之内，越界 => FAIL。
      2. ANCHORS —— 调用 refresh-code-index.ps1（顺带刷新 CODE_INDEX.md 与文档行号），
                    从 CODE_INDEX.md 解析未解析锚点数（>0 即 FAIL）。
      2b. LINT   —— lint-docs.ps1：AI 文档术语/损坏指纹/悬空路径/裸行号/薄指针/JSON（FAIL 即验收失败）。
      3. COMPILE —— 仅 -Compile 时执行权威验收门禁（AI_Script/verify.ps1 全量：构建 EDR + NetDiff 31 用例
                    + lang↔resx 同步 + 坑扫描；权威且无第二实现）。

.USAGE
    .\AI_Script\verify-scope.ps1              # SCOPE + ANCHORS + LINT
    .\AI_Script\verify-scope.ps1 -Compile     # 追加编译+单测门禁（较慢，分钟级）
    .\AI_Script\verify-scope.ps1 -ReadOnly    # 不写工作区（跳过 refresh 写盘，只读现有 CODE_INDEX），供 session-brief 用
    .\AI_Script\verify-scope.ps1 -TaskBrief AI_docs/HANDOFFS/<日期>-<任务号>-brief.md
                                              # 追加 TASK SCOPE：校验改动是否落在该派发单的允许范围内

.EXITCODE
    0 = 全部通过；1 = 验收失败（禁改命中/越界/锚点失效/文档 lint/编译失败）；2 = 环境错误（git/配置不可用）。

.NOTE
    控制台输出用英文（跨控制台代码页稳定）；注释用中文。锚点计数从 CODE_INDEX.md 文件解析，
    而不是解析 refresh-code-index.ps1 的控制台流（Write-Host 不进输出流，跨版本行为不一致）。
    受限环境（Windows ACL 沙箱）里 `$x = & git ...` 拿不到子进程输出，
    故 git 一律走公共库的 Invoke-GitCapture（Start-Process 重定向进临时文件，本脚本只读文件）。
#>

param(
    [switch]$Compile,
    [switch]$ReadOnly,
    [string]$TaskBrief,
    [switch]$WriteScopeBaseline
)

$ErrorActionPreference = 'Stop'
$scriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir 'lib\common.ps1')
$projectRoot = Get-ProjectRoot -ScriptDir $scriptDir
$pathsCfg    = Join-Path $scriptDir 'protected-paths.json'
$refresh     = Join-Path $scriptDir 'refresh-code-index.ps1'
$indexPath   = Join-Path $projectRoot 'AI_docs\CODE_INDEX.md'

$exitCode = 0
Write-Host '=== verify-scope acceptance gate ==='

# ---------- 1. SCOPE ----------
Write-Host ''
Write-Host '[1/3] SCOPE check'
try {
    $cfg = Get-ProtectedRules -ProjectRoot $projectRoot
} catch {
    Write-Host "  SCOPE: ERROR (cannot read rules: $pathsCfg)"
    exit 2
}

# git 可能向 stderr 写 "[attr] ... not allowed" 告警（属无害告警，Invoke-GitCapture 不据此判失败）。
$git = Invoke-GitCapture -ProjectRoot $projectRoot -GitArgs @('status', '--porcelain')
if (-not $git.Ok) {
    Write-Host "  SCOPE: ERROR (git unavailable: $($git.Error))"
    exit 2
}

$rawStatus = $git.Lines
$changed = @()
foreach ($line in @($rawStatus)) {
    $s = "$line"
    if ([string]::IsNullOrWhiteSpace($s)) { continue }
    # porcelain 行结构固定为 XY<space>path；过滤 stderr 混入的告警行
    if ($s.Length -lt 4 -or $s[2] -ne ' ') { continue }
    $p = $s.Substring(3)
    if ($p -match ' -> ') { $p = ($p -split ' -> ', 2)[1] }
    $p = $p.Trim('"').Replace('\', '/')
    $changed += [pscustomobject]@{ Status = $s.Substring(0, 2).Trim(); Path = $p }
}

if ($changed.Count -eq 0) {
    Write-Host '  Worktree clean, no changed files.'
}

$hits = Get-ProtectedHits -Paths @($changed | ForEach-Object { $_.Path }) -Rules $cfg
$forbiddenHit = @($changed | Where-Object { $hits.Forbidden -contains $_.Path })
$cautionHit   = @($changed | Where-Object { $hits.Caution   -contains $_.Path })

foreach ($f in $forbiddenHit) { Write-Host ("  [FORBIDDEN] {0}  {1}" -f $f.Status, $f.Path) -ForegroundColor Red }
foreach ($f in $cautionHit)   { Write-Host ("  [CAUTION]   {0}  {1}" -f $f.Status, $f.Path) -ForegroundColor Yellow }

if ($forbiddenHit.Count -gt 0) {
    Write-Host '  SCOPE: FAIL (forbidden-zone changes present, reject)'
    $exitCode = 1
} else {
    Write-Host ("  SCOPE: PASS ({0} changed file(s), {1} caution item(s) need confirmation)" -f $changed.Count, $cautionHit.Count)
}

# ---------- 1b. TASK SCOPE（仅 -TaskBrief） ----------
# 派发单的 D 节里带一行机读的 `SCOPE: <glob>[;<glob>...]`；改动文件必须落在
# 这些 glob ∪ 固定台账面之内。允许范围因此可机器拦，不再只靠主会话人工看 diff。
if (-not [string]::IsNullOrWhiteSpace($TaskBrief)) {
    Write-Host ''
    Write-Host '[1b/3] TASK SCOPE check'

    $briefPath = $TaskBrief
    if (-not [System.IO.Path]::IsPathRooted($briefPath)) { $briefPath = Join-Path $projectRoot $briefPath }
    if (-not (Test-Path -LiteralPath $briefPath -PathType Leaf)) {
        Write-Host "  TASK SCOPE: ERROR (brief not found: $briefPath)"
        exit 2
    }

    $briefText = [System.IO.File]::ReadAllText($briefPath, [System.Text.Encoding]::UTF8)
    # 允许行首有列表符号/缩进，也允许整行被反引号包住（派发单里常写成 `SCOPE: ...`）
    $m = [regex]::Match($briefText, '(?m)^[ \t]*(?:[-*][ \t]+)?`?[ \t]*SCOPE:[ \t]*(.+?)[ \t]*$')
    if (-not $m.Success) {
        Write-Host '  TASK SCOPE: ERROR (brief has no machine-readable "SCOPE:" line)'
        exit 2
    }

    $taskGlobs = @()
    $scopeText = $m.Groups[1].Value.Trim().Trim('`').Trim()
    foreach ($g in @($scopeText -split '[;,]')) {
        $t = $g.Trim().Trim('`').Trim().Replace('\', '/')
        if ($t -ne '') { $taskGlobs += $t }
    }
    # 固定台账面：任何单都要回写台账/注册表，不占任务范围
    $ledgerGlobs = @('AI_docs/**', 'AI_Script/code-anchors.json')
    $allGlobs = @($taskGlobs + $ledgerGlobs)

    # 基线：派发时用 -WriteScopeBaseline 把"当时已有的改动文件"记进 <brief>.scope-baseline（派发单目录已 gitignore）。
    # 收货时只校验"基线之后新增的改动"——否则多会话工作区里别人的改动会天天把本检查顶红（闸门疲劳）。
    $baselinePath = $briefPath + '.scope-baseline'
    $baseline = @()
    if (Test-Path -LiteralPath $baselinePath) {
        $baseline = @([System.IO.File]::ReadAllLines($baselinePath) | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
    }

    if ($WriteScopeBaseline) {
        # 派发时用：把当前改动清单写成基线，随后不做越界判定
        $paths = @($changed | ForEach-Object { $_.Path })
        [System.IO.File]::WriteAllLines($baselinePath, $paths, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host ("  baseline written: {0} ({1} path(s))" -f $baselinePath, $paths.Count)
        Write-Host '  TASK SCOPE: BASELINE WRITTEN (dispatch-time mode, no verdict)'
    } else {
        $candidates = @($changed | Where-Object { $baseline -notcontains $_.Path })
        $outOfScope = @()
        foreach ($f in $candidates) {
            $inScope = $false
            foreach ($g in $allGlobs) {
                # PowerShell 通配符语义：`*` 跨目录分隔符（`**` 与 `*` 等价），大小写不敏感
                if ($f.Path -like $g) { $inScope = $true; break }
            }
            if (-not $inScope) { $outOfScope += $f }
        }

        Write-Host ("  brief: {0}" -f $briefPath)
        Write-Host ("  scope: {0}" -f ($taskGlobs -join ' | '))
        if ($baseline.Count -gt 0) {
            Write-Host ("  baseline: {0} pre-existing path(s) ignored; checking {1} new change(s)" -f $baseline.Count, $candidates.Count)
        } else {
            Write-Host '  baseline: none (comparing the whole worktree; other sessions'' changes will show up)'
        }
        foreach ($f in $outOfScope) { Write-Host ("  [OUT-OF-SCOPE] {0}  {1}" -f $f.Status, $f.Path) -ForegroundColor Red }
        if ($outOfScope.Count -gt 0) {
            Write-Host '  TASK SCOPE: FAIL (changed files outside the brief scope; reject, or widen the brief and re-dispatch)'
            if ($exitCode -eq 0) { $exitCode = 1 }
        } else {
            Write-Host ("  TASK SCOPE: PASS ({0} new change(s) all within scope)" -f $candidates.Count)
        }
    }
}

# ---------- 2. ANCHORS ----------
Write-Host ''
Write-Host '[2/3] ANCHORS health'
if ($ReadOnly) {
    Write-Host '  [ReadOnly] skip refresh; reading existing CODE_INDEX.md as-is.'
} else {
    & $refresh 6>&1 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match 'unresolved|Unknown anchor' } | ForEach-Object { Write-Host "  $_" }
}

if (-not (Test-Path -LiteralPath $indexPath -PathType Leaf)) {
    Write-Host '  ANCHORS: ERROR (CODE_INDEX.md not found after refresh)'
    if ($exitCode -eq 0) { $exitCode = 2 }
} else {
    $idxText = [System.IO.File]::ReadAllText($indexPath, [System.Text.Encoding]::UTF8)
    $mOk  = [regex]::Match($idxText, '解析成功：(\d+) 个锚点')
    $mBad = [regex]::Match($idxText, '未解析：(\d+) 个')
    if (-not $mOk.Success) {
        Write-Host '  ANCHORS: ERROR (CODE_INDEX.md format unexpected)'
        if ($exitCode -eq 0) { $exitCode = 2 }
    } elseif ($mBad.Success -and [int]$mBad.Groups[1].Value -gt 0) {
        Write-Host ("  ANCHORS: FAIL ({0} unresolved, fix registry/code first)" -f $mBad.Groups[1].Value)
        if ($exitCode -eq 0) { $exitCode = 1 }
    } else {
        Write-Host ("  ANCHORS: PASS ({0} anchors resolved)" -f $mOk.Groups[1].Value)
    }
}

# ---------- 2b. DOCS LINT ----------
Write-Host ''
Write-Host '[2b/3] DOCS LINT'
& (Join-Path $scriptDir 'lint-docs.ps1') -Quiet
if ($LASTEXITCODE -ne 0) {
    Write-Host '  LINT: FAIL (AI docs inconsistency; fix errors above)'
    if ($exitCode -eq 0) { $exitCode = 1 }
} else {
    Write-Host '  LINT: PASS'
}

# ---------- 3. COMPILE ----------
Write-Host ''
Write-Host '[3/3] COMPILE gate'
if (-not $Compile) {
    Write-Host '  COMPILE: SKIPPED (add -Compile to run)'
} else {
    # 权威验收门禁 = verify.ps1（构建 EDR + NetDiff 31 用例 + lang↔resx 同步 + 坑扫描；唯一实现，无双通道漂移）。
    & (Join-Path $scriptDir 'verify.ps1')
    $gateExit = $LASTEXITCODE
    if ($gateExit -eq 0) {
        Write-Host '  COMPILE: PASS'
    } elseif ($gateExit -eq 2) {
        Write-Host '  COMPILE: ERROR (environment problem, see verify output above)'
        if ($exitCode -eq 0) { $exitCode = 2 }
    } else {
        Write-Host '  COMPILE: FAIL (see verify output above)'
        if ($exitCode -eq 0) { $exitCode = 1 }
    }
}

# ---------- Summary ----------
Write-Host ''
Write-Host '=== Result ==='
if ($exitCode -eq 0) { Write-Host 'VERIFY: PASS' -ForegroundColor Green }
elseif ($exitCode -eq 1) { Write-Host 'VERIFY: FAIL (acceptance failed)' -ForegroundColor Red }
else { Write-Host 'VERIFY: ERROR (environment problem, see above)' -ForegroundColor Red }
exit $exitCode
