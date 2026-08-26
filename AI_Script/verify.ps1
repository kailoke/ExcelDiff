# verify.ps1 - One-command development gate.
# Builds the EDE (EDR) main variant, runs the NetDiff unit tests, checks
# lang\*.json <-> .resx sync, and prints the WIP snapshot.
# The ED (NPOI) fallback variant is retained in source but is not part of the gate.
#
# Usage:  powershell -ExecutionPolicy Bypass -File AI_Script\verify.ps1 [-SkipBuild]
# Exit code 0 = all checks passed.
#
# NOTE: keep this file pure ASCII (PowerShell 5.1 reads .ps1 without BOM as ANSI).

param(
    [switch]$SkipBuild
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot   # repo root (script lives in AI_Script\)
$refs = Join-Path $root 'packages\refs'
$fail = $false

function FailStep($msg) { $script:fail = $true; Write-Host ('[FAIL] ' + $msg) -ForegroundColor Red }
function OkStep($msg)   { Write-Host ('[ OK ] ' + $msg) -ForegroundColor Green }

$dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
if (-not $dotnet) { Write-Host '[FAIL] dotnet SDK not found' -ForegroundColor Red; exit 1 }

# --- 1. NetDiff unit tests (offline runner) ---
$runnerProj = Join-Path $root 'NetDiff\NetDiff.TestRunner\NetDiff.TestRunner.csproj'
$runnerExe  = Join-Path $root 'NetDiff\NetDiff.TestRunner\bin\Release\NetDiff.TestRunner.exe'
if ($SkipBuild) {
    if (Test-Path $runnerExe) { OkStep 'TestRunner already built, skipping build' }
} else {
    & dotnet msbuild $runnerProj /p:Configuration=Release "/p:TargetFrameworkRootPath=$refs" /t:Build /v:m /nologo
    if ($LASTEXITCODE -ne 0) { FailStep 'NetDiff.TestRunner build failed'; exit 1 }
}
if (-not (Test-Path $runnerExe)) { FailStep 'NetDiff.TestRunner.exe missing'; exit 1 }
& $runnerExe | ForEach-Object { Write-Host '        ' $_ }
if ($LASTEXITCODE -ne 0) { FailStep 'NetDiff unit tests failed' } else { OkStep 'NetDiff unit tests passed' }

# --- 2. Build EDE (main version, EDR read) ---
if (-not $SkipBuild) {
    $guiProj = Join-Path $root 'ExcelDiff.GUI\ExcelDiff.GUI.csproj'
    $common = @(
        '/p:Configuration=Release',
        '/p:EdrRead=true',
        "/p:TargetFrameworkRootPath=$refs",
        '/p:IncludePackageReferencesDuringMarkupCompilation=false',
        '/p:GenerateResourceMSBuildArchitecture=CurrentArchitecture',
        '/p:GenerateResourceMSBuildRuntime=CurrentRuntime',
        '/t:Build', '/v:m', '/nologo'
    )

    Write-Host '--- Build EDE (EDR, main) ---'
    & dotnet msbuild $guiProj @common
    if ($LASTEXITCODE -ne 0) { FailStep 'EDE build failed' } else { OkStep 'EDE built (ExcelDiffEDR.GUI.exe)' }
} else {
    OkStep 'Builds skipped (-SkipBuild)'
}

# --- 5. lang\*.json <-> .resx sync ---
$resxDir = Join-Path $root 'ExcelDiff.GUI\Properties'
foreach ($pair in @(@('en-US', 'Resources.resx'), @('zh-CN', 'Resources.zh-CN.resx'))) {
    $culture = $pair[0]
    $resxFile = Join-Path $resxDir $pair[1]
    $jsonFile = Join-Path $root ("lang\" + $culture + ".json")
    if (-not (Test-Path $resxFile) -or -not (Test-Path $jsonFile)) {
        FailStep "$culture lang/resx file missing"
        continue
    }
    [xml]$doc = [System.IO.File]::ReadAllText($resxFile)
    $map = @{}
    foreach ($n in $doc.root.data) { if ($n.name) { $map[$n.name] = $n.value } }
    $json = [System.IO.File]::ReadAllText($jsonFile) | ConvertFrom-Json
    $diffs = @()
    foreach ($k in $map.Keys) {
        $v = $json.PSObject.Properties[$k]
        if (-not $v) { $diffs += "missing key: $k" }
        elseif ($v.Value -ne $map[$k]) { $diffs += "value differs: $k" }
    }
    if ($diffs.Count -eq 0) { OkStep "$culture lang\json in sync with resx" }
    else { FailStep "$culture lang\json out of sync: " + ($diffs -join '; ') }
}

# --- 6. AGENTS 8.3 pitfall scan: no Start-Process -Wait on ExcelDiff ---
# Waiting on the forwarder with -Wait hangs when no resident instance exists
# (the forwarder becomes resident and never exits). Enforce the fire-and-forget
# rule in every checked-in script.
$psFiles = Get-ChildItem -Path $root -Filter '*.ps1' -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object {
        $_.FullName -ne $PSCommandPath -and
        $_.FullName -notmatch '\\bin\\|\\obj\\|\\Build\\|\\backup_installed_|\\packages\\|\\\.git\\'
    }
$pitfall = @()
foreach ($psf in $psFiles) {
    $lines = [System.IO.File]::ReadAllLines($psf.FullName)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].TrimStart().StartsWith('#')) { continue }
        if ($lines[$i] -match 'Start-Process' -and $lines[$i] -match '-Wait' -and $lines[$i] -match 'ExcelDiff') {
            $pitfall += ($psf.FullName + ':' + ($i + 1))
        }
    }
}
if ($pitfall.Count -eq 0) { OkStep 'No Start-Process -Wait on ExcelDiff (AGENTS 8.3 pitfall)' }
else { FailStep ('Start-Process -Wait on ExcelDiff found: ' + ($pitfall -join '; ')) }

# --- 7. WIP snapshot ---
Write-Host ''
Write-Host '--- WIP snapshot (git status) ---'
git -C $root status --short | ForEach-Object { Write-Host '        ' $_ }
Write-Host ''

if ($fail) { Write-Host 'verify FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'verify PASSED' -ForegroundColor Green
exit 0
