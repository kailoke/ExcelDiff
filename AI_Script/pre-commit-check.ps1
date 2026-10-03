<#
.SYNOPSIS
    Git pre-commit 门禁：禁改区拦截 → 锚点健康 → 代码提交时刷新 CODE_INDEX → 台账同笔回写门禁 → 文档 lint。

.DESCRIPTION
    由 .githooks/pre-commit（core.hooksPath）触发；也可手动运行。
       0. （钩子先行步骤，见 .githooks/pre-commit 本体）刷新 AI_docs/PROJECT_STATE.md 并重新暂存。
       1. STAGED  —— 暂存文件列表；为空直接放行。
       2. FORBID  —— 暂存文件命中 protected-paths.json forbidden glob => 阻止提交（exit 1）。
       3. ANCHORS —— 运行 refresh-code-index.ps1（重解析锚点 + 修复 AI_docs 行号漂移）；
                    未解析锚点 > 0 => 阻止提交（不带失效锚点提交）。
       4. RESTAGE —— 若本次提交含代码改动（判据 = lib/common.ps1 的 Get-CodeChangedPaths）：
                    重新暂存被刷新波及的 AI_docs 文件（含 CODE_INDEX.md）。
       5. LEDGER  —— 含代码改动但未暂存 AI_docs/PROJECT_STATUS.md => 阻止提交（exit 1）；
                    并行会话占用台账时用 git add -p 只暂存本会话行，应急 --no-verify（须补跟随笔并注明原因）。
       6. DOCS LINT —— 本批含 AI 文档面文件时跑 lint-docs.ps1（FAIL 即拒提）。

.NOTE
    策略：显式门禁失败（禁改/锚点/lint/台账）= 阻止；工具自身异常 = 放行并大声告警（不因工具 bug 封锁提交；
    只读档例外——异常必须以 UNKNOWN 非零退出，不得被读成通过）。
    临时跳过：git commit --no-verify（应急通道，事后请补跑 verify-scope.ps1）。

.USAGE
    .\AI_Script\pre-commit-check.ps1                          # 钩子用法：检"已暂存"那一批（含 CODE_INDEX 刷新与重暂存）
    .\AI_Script\pre-commit-check.ps1 -Changed                 # 不提交也跑：检"工作区全部未提交改动 + 未跟踪文件"
    .\AI_Script\pre-commit-check.ps1 -Paths a.cs,b.md         # 不提交也跑：只检列出的这批路径
    只读档（-Changed / -Paths）与钩子档的差别：改动集来自磁盘而非暂存面、锚点只重建 CODE_INDEX.md
    （`refresh-code-index.ps1 -IndexOnly`，不改别人的台账）、**绝不执行 git add**。
    存在的理由：会话不得为了"让门禁跑一遍"而去提交——这条通道就是那个借口替代品。
#>

param(
    [string[]]$Paths,
    [switch]$Changed,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
# 中文 Windows 控制台默认 GBK 解码外部程序输出，会把 git 的 UTF-8 中文内容读成乱码导致规则失效；统一按 UTF-8 解码
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
$scriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
# git 输出统一走 Invoke-GitCapture：受限环境（Windows ACL 沙箱）里 PowerShell 捕获子进程 stdout 会失败，
# 而本脚本的暂存面判据一旦取空就会"按空放行"，门禁会静默失效（见该函数注释）。
. (Join-Path $scriptDir 'lib\common.ps1')

# $checkOnly 先置默认值：catch 要靠它判定退出码，若异常发生在赋值之前，不能沿用"钩子档放行"的口径
$checkOnly = $false
try {
    # 注意判据：PowerShell 里 `@($null).Count` 是 1（未传的 [string[]] 参数就是 $null），
    # 用它当条件会让"不带参数的钩子档"误入只读档、把暂存面检查整个架空。必须先滤空再数。
    $pathList = @($Paths | Where-Object { "$_".Trim() -ne '' })
    $checkOnly = ($pathList.Count -gt 0) -or [bool]$Changed
    if ($checkOnly) {
        if ($pathList.Count -gt 0) {
            # 从 Git Bash / cmd 传 `-Paths a,b` 时，逗号不会被 PowerShell 拆成数组（整串是一个参数）——
            # 这里显式按逗号/分号再切一次，否则改动集只剩一项，禁改区与文档 lint 会漏检。
            $staged = @($pathList | ForEach-Object { $_ -split '[,;]' } | ForEach-Object { $_.Replace('\', '/').Trim() } | Where-Object { $_ } | Sort-Object -Unique)
        } else {
            $trackedRes   = Invoke-GitCapture -ProjectRoot $projectRoot -GitArgs @('diff', '--name-only', 'HEAD')
            $untrackedRes = Invoke-GitCapture -ProjectRoot $projectRoot -GitArgs @('ls-files', '--others', '--exclude-standard')
            if (-not $trackedRes.Ok -and -not $untrackedRes.Ok) {
                Write-Host ('[check-only] ERROR: 取不到改动集（git 通道不可用：{0}）——这不是"全部通过"，是本轮无从判断' -f $trackedRes.Error) -ForegroundColor Red
                exit 0
            }
            $tracked   = @($trackedRes.Lines)
            $untracked = @($untrackedRes.Lines)
            $staged = @(($tracked + $untracked) | ForEach-Object { $_.Replace('\', '/') } | Where-Object { $_ } | Sort-Object -Unique)
        }
        Write-Host ("[check-only] 改动集取自磁盘（不读暂存面、绝不 git add）：{0} 个文件" -f @($staged).Count) -ForegroundColor Cyan
        if (@($staged).Count -eq 0) {
            Write-Host '[check-only] 工作区无未提交改动 ⇒ 无可检项（这是"没东西可查"，不是"全过"）' -ForegroundColor Yellow
            exit 0
        }
    } else {
        $gitStaged = Invoke-GitCapture -ProjectRoot $projectRoot -GitArgs @('diff', '--cached', '--name-only')
        if (-not $gitStaged.Ok) {
            # 取不到暂存面 ≠ 没有暂存面：若按"空则放行"处理，本道门禁在受限环境里等于不存在。
            Write-Host ('PRE-COMMIT: WARN (cannot read the staged set: {0}) — 本道门禁本轮未生效' -f $gitStaged.Error) -ForegroundColor Red
            Write-Host '  This is NOT a pass: git 取不到暂存面时无从判断。修好 git 通道后重跑，或改用只读档 -Changed / -Paths。' -ForegroundColor Yellow
            exit 0
        }
        $staged = @($gitStaged.Lines | ForEach-Object { $_.Replace('\', '/') } | Where-Object { $_ })
        if ($staged.Count -eq 0) { exit 0 }
    }

    # ---- 1. FORBIDDEN（阻止）----
    $rules = Get-ProtectedRules -ProjectRoot $projectRoot
    $hits = Get-ProtectedHits -Paths $staged -Rules $rules
    $blocked = @($hits.Forbidden)
    if ($blocked.Count -gt 0) {
        $tag = if ($checkOnly) { 'FILES' } else { 'STAGED' }
        $who = if ($checkOnly) { 'CHECK' } else { 'PRE-COMMIT' }
        foreach ($h in $blocked) { Write-Host ("  [FORBIDDEN-{0}] {1}" -f $tag, $h) -ForegroundColor Red }
        Write-Host ("{0}: REJECTED (forbidden-zone files in this batch)" -f $who) -ForegroundColor Red
        exit 1
    }

    if ($checkOnly) { & (Join-Path $scriptDir 'refresh-code-index.ps1') -IndexOnly > $null 2>&1 }
    else { & (Join-Path $scriptDir 'refresh-code-index.ps1') > $null 2>&1 }
    $indexPath = Join-Path $projectRoot 'AI_docs\CODE_INDEX.md'
    if (Test-Path -LiteralPath $indexPath) {
        $idxText = [System.IO.File]::ReadAllText($indexPath, [System.Text.Encoding]::UTF8)
        $mBad = [regex]::Match($idxText, '未解析：(\d+) 个')
        if ($mBad.Success -and [int]$mBad.Groups[1].Value -gt 0) {
            Write-Host ("PRE-COMMIT: REJECTED ({0} unresolved anchors; fix AI_Script/code-anchors.json or code first)" -f $mBad.Groups[1].Value) -ForegroundColor Red
            exit 1
        }
        if (-not $Quiet) { Write-Host '  [anchors] all resolved' -ForegroundColor Green }
    }

    # ---- 2b. DOCS LINT（阻止）：AI 文档一致性（术语/损坏指纹/悬空路径/裸行号/薄指针/JSON/编码）----
    $lintScopes = @($staged | Where-Object {
            $_ -match '^(AI_docs/|\.agents/|\.zcode/|\.qoder/)' -or
            $_ -eq 'AGENTS.md' -or
            $_ -match '^AI_Script/(code-anchors|protected-paths)\.json$'
        })
    if ($lintScopes.Count -gt 0) {
        & (Join-Path $scriptDir 'lint-docs.ps1') -Quiet
        if ($LASTEXITCODE -ne 0) {
            Write-Host 'PRE-COMMIT: REJECTED (docs lint failed; fix errors above)' -ForegroundColor Red
            exit 1
        }
        if (-not $Quiet) { Write-Host '  [docs-lint] pass' -ForegroundColor Green }
    } elseif ($checkOnly -and -not $Quiet) {
        # 跳过必须出声：否则"没查"会被读成"查过且全绿"
        Write-Host '  [docs-lint] 跳过 —— 本批不含 AI 文档面文件（AGENTS.md / AI_docs / .agents / 门禁数据 json）' -ForegroundColor Cyan
    }

    # ---- 3. RESTAGE（代码提交时同步刷新波及的 AI_docs）----
    # 判据唯一出处 = lib/common.ps1 的 Get-CodeChangedPaths；verify-day 共用同一条。
    $codeChanged = @(Get-CodeChangedPaths -ProjectRoot $projectRoot -Paths $staged -Base 'HEAD')
    if ($checkOnly) {
        if (-not $Quiet) { Write-Host '  [check-only] 跳过重暂存与文档行号回写（只有钩子档会 git add）' -ForegroundColor Cyan }
    } elseif ($codeChanged.Count -gt 0) {
        # git 一律经 Invoke-GitCapture（重定向进文件）：git 的 stderr 落文件、不会变成 PowerShell 终止错误，
        # 故历史上"CRLF 告警在 Stop 下中断整段、把 RESTAGE 与 LEDGER 一起静默跳过"的情形不可能再出现。
        $restage = @($staged | Where-Object { $_ -like 'AI_docs/*' }) + @('AI_docs/CODE_INDEX.md', 'AI_docs/PROJECT_STATE.md')
        foreach ($f in ($restage | Select-Object -Unique)) {
            $dirtyRes = Invoke-GitCapture -ProjectRoot $projectRoot -GitArgs @('diff', '--name-only', '--', $f)
            if (@($dirtyRes.Lines | Where-Object { $_ }).Count -gt 0) {
                $addRes = Invoke-GitCapture -ProjectRoot $projectRoot -GitArgs @('add', '--', $f)
                if (-not $addRes.Ok) { throw ("git add 失败：{0}（{1}）" -f $f, $addRes.Error) }
                Write-Host ("  [re-staged] {0}" -f $f)
            }
        }
    }

    # ---- 4. LEDGER（同笔回写门禁，阻断）----
    # 规则出处：根 AGENTS.md 文档状态纪律（台账与代码同一笔提交）。
    # 会话须"先跑门禁 → 写台账 → 同笔提交"；并行冲突窄口见提示（add -p / --no-verify）。
    $hasStatus = ($staged -contains 'AI_docs/PROJECT_STATUS.md')
    if ($codeChanged.Count -gt 0 -and -not $hasStatus) {
        $who = if ($checkOnly) { 'CHECK' } else { 'PRE-COMMIT' }
        Write-Host ("{0}: REJECTED (code changed but AI_docs/PROJECT_STATUS.md is not in this batch)" -f $who) -ForegroundColor Red
        Write-Host '  Ledger write-back must be in the SAME commit as code (AGENTS 文档状态纪律).' -ForegroundColor Red
        Write-Host '  Fix A (normal): stage your ledger edits with the code.' -ForegroundColor Yellow
        Write-Host '  Fix B (parallel session holds PROJECT_STATUS.md uncommitted): git add -p to stage ONLY your lines,' -ForegroundColor Yellow
        Write-Host '  Fix C (escape hatch): git commit --no-verify — a follow-up docs(ai) commit is then REQUIRED,' -ForegroundColor Yellow
        Write-Host '          and its message must state why the split was necessary.' -ForegroundColor Yellow
        exit 1
    }

    if ($checkOnly) { Write-Host ("[check-only] PASS：{0} 个文件（禁改区 / 锚点 / 文档 lint / 台账同笔 均过；未动暂存面）" -f @($staged).Count) -ForegroundColor Green }
    exit 0
} catch {
    Write-Host ("PRE-COMMIT: tool error (allowed, fix later): {0}" -f $_.Exception.Message) -ForegroundColor Yellow
    # 异常之后的门禁步骤全部未执行——必须把抛点打出来，否则"放行"看起来像"全绿"。
    Write-Host ("  抛出位置: {0} :: 行 {1}" -f $_.InvocationInfo.ScriptName, $_.InvocationInfo.ScriptLineNumber) -ForegroundColor Yellow
    if ($_.InvocationInfo.Line) { Write-Host ("  语句: {0}" -f $_.InvocationInfo.Line.Trim()) -ForegroundColor Yellow }
    Write-Host ("  本次提交被跳过的后续门禁 = 抛点之后的步骤（FORBID/ANCHORS/DOCS-LINT/RESTAGE/LEDGER 中未打印 pass 的那些）") -ForegroundColor Yellow
    # 钩子档：工具故障不封锁提交（原策略）。只读档：exit 0 会被调用方读成"全绿"，必须非零退出，
    # 并明说这一轮是 UNKNOWN 而不是 PASS。
    if ($checkOnly) {
        Write-Host '[check-only] RESULT: UNKNOWN（工具自身异常，后续检查未执行，不得当作通过）' -ForegroundColor Red
        exit 1
    }
    exit 0
}
