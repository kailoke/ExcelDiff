# run_diff_compare.ps1 - Headless EM (NPOI) vs EME (EDR) comparison on one file.
# Compares a same-named file: git HEAD version vs working-tree version, per AGENTS.md 7.7.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File DiffHarness\run_diff_compare.ps1
#     -RelPath Config/Data/Level.xlsx [-Repo D:\P\BackPack\baggame] [-NoBuild] [-SrcHeader N] [-DstHeader N]
#
# Exit code 0 = EM and EME outputs match (excluding the READER line).

param(
    [string]$RelPath = 'Config/Data/Level.xlsx',
    [string]$Repo = 'D:\P\BackPack\baggame',
    [switch]$NoBuild,
    [int]$SrcHeader = -1,
    [int]$DstHeader = -1
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$refs = Join-Path $root 'packages\refs'
$harnessProj = Join-Path $PSScriptRoot 'DiffHarness.csproj'
$emExe = Join-Path $PSScriptRoot 'bin\Release\DiffHarness.exe'
$emeExe = Join-Path $PSScriptRoot 'bin\Release-EDR\DiffHarnessEDR.exe'

$tmpDir = Join-Path $env:TEMP 'opencode\diffcompare'
New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
$head = Join-Path $tmpDir ('head_' + [System.IO.Path]::GetFileName($RelPath))
$emOut = Join-Path $tmpDir 'em.txt'
$emeOut = Join-Path $tmpDir 'eme.txt'

if (-not $NoBuild) {
    Write-Host 'Building EME harness (EDR)...'
    & dotnet msbuild $harnessProj /p:Configuration=Release /p:EdrRead=true "/p:TargetFrameworkRootPath=$refs" /t:Build /v:q /nologo
    if ($LASTEXITCODE -ne 0) { throw 'EME harness build failed' }
    Write-Host 'Building EM harness (NPOI)...'
    & dotnet msbuild $harnessProj /p:Configuration=Release "/p:TargetFrameworkRootPath=$refs" /t:Build /v:q /nologo
    if ($LASTEXITCODE -ne 0) { throw 'EM harness build failed' }
}

Write-Host "Extracting HEAD of $RelPath ..."
cmd /c "git -C `"$Repo`" show HEAD:$RelPath > `"$head`""
if (-not (Test-Path $head)) { throw 'HEAD extraction failed' }
$work = Join-Path $Repo ($RelPath -replace '/', '\')

Write-Host 'Running EME harness ...'
& $emeExe --src $head --dst $work --out $emeOut --src-header $SrcHeader --dst-header $DstHeader
if ($LASTEXITCODE -ne 0) { throw 'EME harness run failed' }
Write-Host 'Running EM harness ...'
& $emExe --src $head --dst $work --out $emOut --src-header $SrcHeader --dst-header $DstHeader
if ($LASTEXITCODE -ne 0) { throw 'EM harness run failed' }

$emLines = [System.IO.File]::ReadAllLines($emOut, [System.Text.Encoding]::UTF8) | Where-Object { $_ -notlike 'READER=*' }
$emeLines = [System.IO.File]::ReadAllLines($emeOut, [System.Text.Encoding]::UTF8) | Where-Object { $_ -notlike 'READER=*' }
$c = Compare-Object $emLines $emeLines
if ($c) {
    Write-Host ('DIFF between EM and EME (' + $c.Count + ' lines):') -ForegroundColor Yellow
    $c | Select-Object -First 30 | ForEach-Object { Write-Host ('  ' + $_.SideIndicator + ' ' + $_.InputObject) }
    exit 1
}

Write-Host 'MATCH: EM (NPOI) and EME (EDR) outputs identical' -ForegroundColor Green
Write-Host ''
Write-Host '--- First modified cells (EM) ---'
$emLines | Where-Object { $_ -like 'SHEET*' -or $_ -like 'CELL*' } | Select-Object -First 20 | ForEach-Object { Write-Host '  ' $_ }
exit 0
