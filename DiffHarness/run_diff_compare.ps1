# run_diff_compare.ps1 - Headless ED (NPOI) vs EDE (EDR) comparison on one file.
# Compares a same-named file: git HEAD version vs working-tree version, per AI_Programmer\AGENTS.md 7.7.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File DiffHarness\run_diff_compare.ps1
#     -RelPath Artifact.xlsx [-Repo <xlsx data dir or its git root>] [-NoBuild] [-SrcHeader N] [-DstHeader N]
#
# -Repo comes from ProjectPaths.ps1 ($TestDataRepoPath, override with EXCELDIFF_TESTDATA_REPO or -Repo).
# It may be the git root or a data subfolder inside it; -RelPath is relative to that folder.
#
# Exit code 0 = ED and EDE outputs match (excluding the READER line).

param(
    [string]$RelPath = 'Artifact.xlsx',
    [string]$Repo = '',
    [switch]$NoBuild,
    [int]$SrcHeader = -1,
    [int]$DstHeader = -1,
    [switch]$SkipFirstBlankRows,
    [switch]$SkipFirstBlankColumns,
    [switch]$TrimLastBlankRows,
    [switch]$TrimLastBlankColumns
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'ProjectPaths.ps1')

if (-not $Repo) { $Repo = $TestDataRepoPath }
if (-not $Repo) { throw 'No test-data repo: pass -Repo <path> or set EXCELDIFF_TESTDATA_REPO (see ProjectPaths.ps1).' }
if (-not (Test-Path $Repo)) { throw "Test-data path not found: $Repo" }

# -Repo may be a subfolder of the git repo. Walk up looking for .git and accumulate the folder
# names: parsing `git rev-parse` output would break on non-ASCII paths under PS 5.1 (GBK console).
$dir = (Resolve-Path $Repo).Path.TrimEnd('\')
$relPrefix = ''
while (-not (Test-Path (Join-Path $dir '.git'))) {
    $leaf = Split-Path -Leaf $dir
    $parent = Split-Path -Parent $dir
    if (-not $parent -or $parent -eq $dir) { throw "Not inside a git repository: $Repo" }
    $relPrefix = if ($relPrefix) { $leaf + '/' + $relPrefix } else { $leaf }
    $dir = $parent
}
$RelInRepo = if ($relPrefix) { $relPrefix + '/' + $RelPath } else { $RelPath }
Write-Host ("git root=$dir  file=$RelInRepo")

$refs = Join-Path $root 'packages\refs'
$harnessProj = Join-Path $PSScriptRoot 'DiffHarness.csproj'
$edExe = Join-Path $PSScriptRoot 'bin\Release\DiffHarness.exe'
$edeExe = Join-Path $PSScriptRoot 'bin\Release-EDR\DiffHarnessEDR.exe'

$trimArgs = @()
if ($SkipFirstBlankRows)    { $trimArgs += '--skip-first-blank-rows' }
if ($SkipFirstBlankColumns) { $trimArgs += '--skip-first-blank-columns' }
if ($TrimLastBlankRows)     { $trimArgs += '--trim-last-blank-rows' }
if ($TrimLastBlankColumns)  { $trimArgs += '--trim-last-blank-columns' }

$tmpDir = Join-Path $env:TEMP 'opencode\diffcompare'
New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
$head = Join-Path $tmpDir ('head_' + [System.IO.Path]::GetFileName($RelPath))
$edOut = Join-Path $tmpDir 'ed.txt'
$edeOut = Join-Path $tmpDir 'ede.txt'

if (-not $NoBuild) {
    Write-Host 'Building EDE harness (EDR)...'
    & dotnet msbuild $harnessProj /p:Configuration=Release /p:EdrRead=true "/p:TargetFrameworkRootPath=$refs" /t:Build /v:q /nologo
    if ($LASTEXITCODE -ne 0) { throw 'EDE harness build failed' }
    Write-Host 'Building ED harness (NPOI)...'
    & dotnet msbuild $harnessProj /p:Configuration=Release "/p:TargetFrameworkRootPath=$refs" /t:Build /v:q /nologo
    if ($LASTEXITCODE -ne 0) { throw 'ED harness build failed' }
}

Write-Host "Extracting HEAD of $RelInRepo ..."
cmd /c "git -C `"$Repo`" show HEAD:$RelInRepo > `"$head`""
if (-not (Test-Path $head)) { throw 'HEAD extraction failed' }
$work = Join-Path $Repo ($RelPath -replace '/', '\')

Write-Host 'Running EDE harness ...'
& $edeExe @('--src', $head, '--dst', $work, '--out', $edeOut, '--src-header', "$SrcHeader", '--dst-header', "$DstHeader") @trimArgs
if ($LASTEXITCODE -ne 0) { throw 'EDE harness run failed' }
Write-Host 'Running ED harness ...'
& $edExe @('--src', $head, '--dst', $work, '--out', $edOut, '--src-header', "$SrcHeader", '--dst-header', "$DstHeader") @trimArgs
if ($LASTEXITCODE -ne 0) { throw 'ED harness run failed' }

$edLines = [System.IO.File]::ReadAllLines($edOut, [System.Text.Encoding]::UTF8) | Where-Object { $_ -notlike 'READER=*' }
$edeLines = [System.IO.File]::ReadAllLines($edeOut, [System.Text.Encoding]::UTF8) | Where-Object { $_ -notlike 'READER=*' }
$c = Compare-Object $edLines $edeLines
if ($c) {
    Write-Host ('DIFF between ED and EDE (' + $c.Count + ' lines):') -ForegroundColor Yellow
    $c | Select-Object -First 30 | ForEach-Object { Write-Host ('  ' + $_.SideIndicator + ' ' + $_.InputObject) }
    exit 1
}

Write-Host 'MATCH: ED (NPOI) and EDE (EDR) outputs identical' -ForegroundColor Green
Write-Host ''
Write-Host '--- First modified cells (ED) ---'
$edLines | Where-Object { $_ -like 'SHEET*' -or $_ -like 'CELL*' } | Select-Object -First 20 | ForEach-Object { Write-Host '  ' $_ }
exit 0
