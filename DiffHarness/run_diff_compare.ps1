# run_diff_compare.ps1 - Headless ED (NPOI) vs EDE (EDR) comparison on one file.
# Compares a same-named file: git HEAD version vs working-tree version, per AI_Programmer\AGENTS.md 7.7.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File DiffHarness\run_diff_compare.ps1
#     -RelPath Config/Data/Level.xlsx [-Repo D:\P\BackPack\baggame] [-NoBuild] [-SrcHeader N] [-DstHeader N]
#
# Exit code 0 = ED and EDE outputs match (excluding the READER line).

param(
    [string]$RelPath = 'Config/Data/Level.xlsx',
    [string]$Repo = 'D:\P\BackPack\baggame',
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

Write-Host "Extracting HEAD of $RelPath ..."
cmd /c "git -C `"$Repo`" show HEAD:$RelPath > `"$head`""
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
