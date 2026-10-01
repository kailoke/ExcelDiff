# verify.ps1 - One-command development gate.
# Builds the product (ExcelDiffEDR.GUI, ExcelDataReader reader), runs the NetDiff unit
# tests, checks lang\*.json <-> .resx sync, and prints the WIP snapshot.
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
. (Join-Path $root 'ProjectPaths.ps1')
$refs = $RefAssemblyPath
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
    & dotnet msbuild $runnerProj /p:Configuration=Release "/p:FrameworkPathOverride=$refs" /t:Build /v:m /nologo
    if ($LASTEXITCODE -ne 0) { FailStep 'NetDiff.TestRunner build failed'; exit 1 }
}
if (-not (Test-Path $runnerExe)) { FailStep 'NetDiff.TestRunner.exe missing'; exit 1 }
& $runnerExe | ForEach-Object { Write-Host '        ' $_ }
if ($LASTEXITCODE -ne 0) { FailStep 'NetDiff unit tests failed' } else { OkStep 'NetDiff unit tests passed' }

# --- 2. Restore + Build EDR (main version, ExcelDataReader read) ---
if (-not $SkipBuild) {
    $guiProj = Join-Path $root 'ExcelDiff.GUI\ExcelDiff.GUI.csproj'
    $libProj = Join-Path $root 'ExcelDiff\ExcelDiff.csproj'
    $shellProj = Join-Path $root 'ExcelDiff.ShellExtension\ExcelDiff.ShellExtension.csproj'
    $nugetConfig = $NuGetConfigPath
    $common = @(
        '/p:Configuration=Release',
        "/p:FrameworkPathOverride=$refs",
        '/p:IncludePackageReferencesDuringMarkupCompilation=false',
        '/p:GenerateResourceMSBuildArchitecture=CurrentArchitecture',
        '/p:GenerateResourceMSBuildRuntime=CurrentRuntime',
        '/t:Build', '/v:m', '/nologo'
    )

    Write-Host '--- Restore packages (GUI + ExcelDiff + ShellExtension) ---'
    & dotnet restore $guiProj --configfile $nugetConfig /v:m
    if ($LASTEXITCODE -ne 0) { FailStep 'Package restore failed (GUI)'; exit 1 }
    & dotnet restore $libProj --configfile $nugetConfig /v:m
    if ($LASTEXITCODE -ne 0) { FailStep 'Package restore failed (ExcelDiff)'; exit 1 }
    & dotnet restore $shellProj --configfile $nugetConfig /v:m
    if ($LASTEXITCODE -ne 0) { FailStep 'Package restore failed (ShellExtension)'; exit 1 }

    Write-Host '--- Build EDR (ExcelDataReader, main) ---'
    & dotnet msbuild $guiProj @common
    if ($LASTEXITCODE -ne 0) { FailStep 'EDR build failed' } else { OkStep 'EDR built (ExcelDiffEDR.GUI.exe)' }

    # The setup wizard project must keep compiling even without obj\payload.zip,
    # otherwise a broken installer stays invisible to this gate.
    Write-Host '--- Build setup wizard project ---'
    $installerProj = Join-Path $root 'ExcelDiff.Installer\ExcelDiff.Installer.csproj'
    & dotnet restore $installerProj --configfile $nugetConfig /v:m
    if ($LASTEXITCODE -ne 0) { FailStep 'Package restore failed (Installer)' }
    else {
        & dotnet msbuild $installerProj /p:Configuration=Release "/p:FrameworkPathOverride=$refs" /t:Build /v:m /nologo
        if ($LASTEXITCODE -ne 0) { FailStep 'setup wizard build failed' } else { OkStep 'setup wizard built (ExcelDiffSetup.exe)' }
    }
} else {
    OkStep 'Builds skipped (-SkipBuild)'
}

# --- 5. lang\*.json <-> .resx sync (both ways) and resx-to-resx key parity ---
$resxDir = Join-Path $root 'ExcelDiff.GUI\Properties'
$resxMaps = @{}
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
    $resxMaps[$culture] = $map
    $json = [System.IO.File]::ReadAllText($jsonFile) | ConvertFrom-Json
    $diffs = @()
    foreach ($k in $map.Keys) {
        $v = $json.PSObject.Properties[$k]
        if (-not $v) { $diffs += "missing key: $k" }
        elseif ($v.Value -ne $map[$k]) { $diffs += "value differs: $k" }
    }
    # The other direction matters: LocalizationManager prefers the json, so a key deleted from the
    # resx keeps serving a stale translation forever unless this is caught.
    foreach ($p in $json.PSObject.Properties) {
        if (-not $map.ContainsKey($p.Name)) { $diffs += "stale json key: $($p.Name)" }
    }
    if ($diffs.Count -eq 0) { OkStep "$culture lang\json in sync with resx" }
    else { FailStep "$culture lang\json out of sync: " + ($diffs -join '; ') }
}

# GenerateLangJson.ps1 takes the union of both resx and falls back to the neutral value, so a key
# added to only one file silently ships English text into zh-CN with the check above still green.
if ($resxMaps.ContainsKey('en-US') -and $resxMaps.ContainsKey('zh-CN')) {
    $enKeys = @($resxMaps['en-US'].Keys)
    $zhKeys = @($resxMaps['zh-CN'].Keys)
    $onlyEn = @($enKeys | Where-Object { $zhKeys -notcontains $_ })
    $onlyZh = @($zhKeys | Where-Object { $enKeys -notcontains $_ })
    if ($onlyEn.Count -eq 0 -and $onlyZh.Count -eq 0) { OkStep 'both .resx files carry the same key set' }
    else {
        FailStep ('resx key sets diverge: only-en=' + ($onlyEn -join ',') +
                  ' only-zh=' + ($onlyZh -join ','))
    }
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

# --- 6b. INVARIANT D1 scan: no hardcoded UI text in XAML ---
# Visible text must come from the string tables (GUI: Resources.* -> lang\*.json; installer:
# Strings\*.txt, filled by key in WizardWindow.ApplyTexts), because a literal baked into XAML
# cannot be translated. Two literal kinds are caught, in the six UI attributes and in element
# text that shares a line with its tags:
#   - CJK / kana / full-width: NoDiffWindow shipped a hardcoded button label, so it read Chinese
#     in ENGLISH mode (fixed to {x:Static Resources.Word_OK} in 4b71c9a);
#   - the brand literal (ExcelDiff*): the name's owning layer is ProductInfo + the tables, so a
#     copy in XAML silently survives a rename. No violation exists today - this alternative is
#     prevention, not a regression test for a measured bug.
# Known blind spots (do not claim more than this): Style/Setter Value="...", attached or
# qualified properties such as TextBlock.ToolTip=", a value spanning lines, and element text
# spread over several lines. Language-neutral symbols are deliberately outside the class below
# (DiffView.xaml labels shortcut buttons with arrow glyphs). A wrong *translation* in the tables
# is a value mismatch, not a literal, and no scan here detects it.
$d1Class = '[\u3000-\u303f\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uff01-\uff5e\uff61-\uff9f]'
$d1UiAttrs = 'Text|Content|Header|ToolTip|Description|Title'
$d1 = @()
$xamlFiles = Get-ChildItem -Path $root -Filter '*.xaml' -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\bin\\|\\obj\\|\\Build\\|\\backup_installed_|\\packages\\|\\\.git\\' }
foreach ($xf in $xamlFiles) {
    $lines = [System.IO.File]::ReadAllLines($xf.FullName)
    $inComment = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($inComment) {
            if ($line.Contains('-->')) { $inComment = $false }
            continue
        }
        if ($line.Contains('<!--') -and -not $line.Contains('-->')) { $inComment = $true; continue }
        if ($line.TrimStart().StartsWith('<!--')) { continue }

        $body = [regex]::Replace($line, '<!--.*?-->', '')
        $hit = $false
        foreach ($q in @('"', "'")) {
            $pattern = '(^|[\s<])(' + $d1UiAttrs + ')=' + $q + '[^' + $q + ']*' + $q
            foreach ($m in [regex]::Matches($body, $pattern)) {
                $value = $m.Value.Substring($m.Value.IndexOf($q) + 1).TrimEnd($q)
                if ($value.StartsWith('{')) { continue }      # bound to a resource, not a literal
                if ($value -match $d1Class -or $value -match 'ExcelDiff') { $hit = $true }
            }
        }
        if (-not $hit) {
            foreach ($text in [regex]::Matches($body, '>([^<>]+)<')) {
                $value = $text.Groups[1].Value
                if ($value -match $d1Class -or $value -match 'ExcelDiff') { $hit = $true; break }
            }
        }
        if ($hit) { $d1 += ($xf.FullName + ':' + ($i + 1)) }
    }
}
if ($d1.Count -eq 0) { OkStep 'No hardcoded UI text (CJK or brand literal) in XAML (INVARIANT D1)' }
else { FailStep ('Hardcoded UI text in XAML: ' + ($d1 -join '; ')) }

# --- 7. WIP snapshot ---
Write-Host ''
Write-Host '--- WIP snapshot (git status) ---'
git -C $root status --short | ForEach-Object { Write-Host '        ' $_ }
Write-Host ''

if ($fail) { Write-Host 'verify FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'verify PASSED' -ForegroundColor Green
exit 0
