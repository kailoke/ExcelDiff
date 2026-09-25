<#
.SYNOPSIS
    Build the ExcelDiffEDR setup wizard exe with the application payload embedded.

.DESCRIPTION
    Replaces the retired WiX/MSI chain. Flow:
      1. assert the installer's folder-name constant matches ProjectPaths.ps1
      2. restore + rebuild EDR GUI and ShellExtension into isolated staging (INVARIANTS E7)
      3. merge the shell files into the app payload, drop pdb/xml and the EDN trio
      4. assert the installer version equals the main exe FileVersion (INVARIANTS E8)
      5. zip the payload and embed it as a manifest resource by building the csproj
      6. verify the produced exe really carries the payload resource
      7. publish to Release\ExcelDiffSetup-<version>.exe

    ASCII only on purpose: a .ps1 with non-ASCII literals must be saved with a BOM or
    PowerShell 5.1 decodes it as GBK (AGENTS 8.1).

.PARAMETER SkipBuild
    Reuse the existing staging tree instead of rebuilding it.

.PARAMETER OutputDir
    Where the setup exe is published. Defaults to ExcelDiff.Installer\Release.
#>
[CmdletBinding()]
param(
    [switch]$SkipBuild,
    [string]$OutputDir
)

$ErrorActionPreference = 'Stop'

$InstallerDir = $PSScriptRoot
$RepoRoot = Split-Path -Parent $InstallerDir
. (Join-Path $RepoRoot 'ProjectPaths.ps1')

if (-not $OutputDir) { $OutputDir = Join-Path $InstallerDir 'Release' }

$StageDir   = Join-Path $InstallerDir 'obj\stage'
$AppStage   = Join-Path $StageDir 'app'
$ShellStage = Join-Path $StageDir 'shell'
$PayloadZip = Join-Path $InstallerDir 'obj\payload.zip'
$SetupProj  = Join-Path $InstallerDir 'ExcelDiff.Installer.csproj'
$ProductCs  = Join-Path $InstallerDir 'Core\ProductInfo.cs'
$AssemblyCs = Join-Path $InstallerDir 'Properties\AssemblyInfo.cs'
$GuiProj    = Join-Path $RepoRoot 'ExcelDiff.GUI\ExcelDiff.GUI.csproj'
$ShellProj  = Join-Path $RepoRoot 'ExcelDiff.ShellExtension\ExcelDiff.ShellExtension.csproj'

# ---------------------------------------------------------------- E11: one folder name, two places

Write-Host "== Check install folder name against ProjectPaths.ps1 =="
$productSource = Get-Content -LiteralPath $ProductCs -Raw
$nameMatch = [regex]::Match($productSource, 'InstallDirName\s*=\s*"([^"]+)"')
if (-not $nameMatch.Success) { throw "could not read InstallDirName from $ProductCs" }
$installerDirName = $nameMatch.Groups[1].Value
if ($installerDirName -ne $EdrInstallDirName) {
    throw "ProductInfo.InstallDirName ('$installerDirName') != ProjectPaths.ps1 `$EdrInstallDirName ('$EdrInstallDirName')"
}
Write-Host "  $installerDirName"

# ---------------------------------------------------------------- HKLM contract, installer <-> app

Write-Host "== Check the HKLM seed contract =="
$appSettings = Get-Content -LiteralPath (Join-Path $RepoRoot 'ExcelDiff.GUI\Settings\ApplicationSetting.cs') -Raw
$registryStore = Get-Content -LiteralPath (Join-Path $InstallerDir 'Core\RegistryStore.cs') -Raw
$keyMatch = [regex]::Match((Get-Content -LiteralPath $ProductCs -Raw), 'ProductRegKey\s*=\s*@"([^"]+)"')
if (-not $keyMatch.Success) { throw "could not read ProductRegKey from $ProductCs" }
$productRegKey = $keyMatch.Groups[1].Value
# The app reads the EDR key under #if EDR_READ; both literals must match or the seed silently no-ops.
if ($appSettings -notmatch ('@"' + [regex]::Escape($productRegKey) + '"')) {
    throw "ApplicationSetting.cs does not read HKLM\$productRegKey - installer and app disagree about the seed key"
}
foreach ($valueName in @('SetupCulture', 'SetupStartOnBoot')) {
    if ($registryStore -notmatch $valueName) { throw "RegistryStore.cs no longer writes $valueName" }
    if ($appSettings -notmatch ('"' + $valueName + '"')) { throw "ApplicationSetting.cs no longer reads $valueName" }
}
Write-Host "  HKLM\$productRegKey + SetupCulture/SetupStartOnBoot match on both sides"

# ---------------------------------------------------------------- staging

function Remove-StagingSafely([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return }
    $root = [System.IO.Path]::GetFullPath($InstallerDir).TrimEnd('\')
    $full = [System.IO.Path]::GetFullPath($path).TrimEnd('\')
    if (-not $full.StartsWith($root + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to clean a directory outside the installer folder: $full"
    }
    Remove-Item -LiteralPath $full -Recurse -Force
}

if (-not $SkipBuild) {
    Write-Host "== Restore + build EDR GUI into isolated staging =="
    Remove-StagingSafely $StageDir
    New-Item -ItemType Directory -Path $AppStage, $ShellStage -Force | Out-Null

    dotnet restore "$GuiProj" --configfile $NuGetConfigPath /v:m
    if ($LASTEXITCODE -ne 0) { throw 'EDR restore failed' }
    dotnet msbuild "$GuiProj" /p:Configuration=Release /p:EdrRead=true `
        /p:FrameworkPathOverride="$RefAssemblyPath" `
        /p:IncludePackageReferencesDuringMarkupCompilation=false `
        /p:GenerateResourceMSBuildArchitecture=CurrentArchitecture `
        /p:GenerateResourceMSBuildRuntime=CurrentRuntime `
        /p:OutputPath="$AppStage\" /p:AppendTargetFrameworkToOutputPath=false `
        /t:Rebuild /v:m /nologo
    if ($LASTEXITCODE -ne 0) { throw 'EDR build failed' }

    Write-Host "== Restore + build ShellExtension into isolated staging =="
    dotnet restore "$ShellProj" --configfile $NuGetConfigPath /v:m
    if ($LASTEXITCODE -ne 0) { throw 'ShellExtension restore failed' }
    dotnet msbuild "$ShellProj" /p:Configuration=Release `
        /p:FrameworkPathOverride="$RefAssemblyPath" `
        /p:OutputPath="$ShellStage\" /p:AppendTargetFrameworkToOutputPath=false `
        /t:Rebuild /v:m /nologo
    if ($LASTEXITCODE -ne 0) { throw 'ShellExtension build failed' }
}
else {
    Write-Host "== -SkipBuild: reusing $StageDir =="
}

# ---------------------------------------------------------------- payload

Write-Host "== Assemble payload =="
$guiExe = Join-Path $AppStage 'ExcelDiffEDR.GUI.exe'
if (-not (Test-Path -LiteralPath $guiExe)) { throw "main exe missing from staging: $guiExe" }

foreach ($shellFile in @('ExcelDiff.ShellExtension.dll', 'SharpShell.dll', 'System.Resources.Extensions.dll')) {
    $source = Join-Path $ShellStage $shellFile
    if (-not (Test-Path -LiteralPath $source)) { throw "shell payload file missing: $source" }
    Copy-Item -LiteralPath $source -Destination (Join-Path $AppStage $shellFile) -Force
}

# Symbols, docs and the EDN build must never ship inside the EDR package.
Get-ChildItem -LiteralPath $AppStage -Recurse -File | Where-Object {
    $_.Extension -in '.pdb', '.xml' -or $_.Name -in 'ExcelDiff.GUI.exe', 'ExcelDiff.GUI.exe.config'
} | Remove-Item -Force

$payloadFiles = Get-ChildItem -LiteralPath $AppStage -Recurse -File
Write-Host ("  {0} files, {1:N1} MB" -f $payloadFiles.Count, (($payloadFiles | Measure-Object Length -Sum).Sum / 1MB))

# ---------------------------------------------------------------- E8: version identity

$binaryVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($guiExe).FileVersion
$assemblySource = Get-Content -LiteralPath $AssemblyCs -Raw
$versionMatch = [regex]::Match($assemblySource, 'AssemblyFileVersion\("([^"]+)"\)')
if (-not $versionMatch.Success) { throw "could not read AssemblyFileVersion from $AssemblyCs" }
$setupVersion = $versionMatch.Groups[1].Value
if ($setupVersion -ne $binaryVersion) {
    throw "setup version ($setupVersion) must equal ExcelDiffEDR.GUI.exe FileVersion ($binaryVersion)"
}
Write-Host "  version $setupVersion (matches main exe)"

# ---------------------------------------------------------------- zip + build

Write-Host "== Zip payload =="
New-Item -ItemType Directory -Path (Split-Path -Parent $PayloadZip) -Force | Out-Null
Remove-Item -LiteralPath $PayloadZip -Force -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.IO.Compression | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem | Out-Null
[System.IO.Compression.ZipFile]::CreateFromDirectory($AppStage, $PayloadZip,
    [System.IO.Compression.CompressionLevel]::Optimal, $false)
Write-Host ("  {0:N1} MB -> {1}" -f ((Get-Item -LiteralPath $PayloadZip).Length / 1MB), $PayloadZip)

Write-Host "== Build setup exe =="
dotnet restore "$SetupProj" --configfile $NuGetConfigPath /v:m
if ($LASTEXITCODE -ne 0) { throw 'setup restore failed' }
dotnet msbuild "$SetupProj" /p:Configuration=Release /p:FrameworkPathOverride="$RefAssemblyPath" `
    /t:Rebuild /v:m /nologo
if ($LASTEXITCODE -ne 0) { throw 'setup build failed' }

$builtExe = Join-Path $InstallerDir 'bin\Release\ExcelDiffSetup.exe'
if (-not (Test-Path -LiteralPath $builtExe)) { throw "setup exe not produced: $builtExe" }

Write-Host "== Verify embedded payload resource =="
$assembly = [System.Reflection.Assembly]::LoadFile([System.IO.Path]::GetFullPath($builtExe))
$resources = $assembly.GetManifestResourceNames()
foreach ($required in @('ExcelDiff.Setup.Payload.zip', 'ExcelDiff.Setup.Strings.zh-CN.txt', 'ExcelDiff.Setup.Strings.en-US.txt')) {
    if ($resources -notcontains $required) { throw "embedded resource missing: $required" }
}
Write-Host ("  resources: {0}" -f ($resources -join ', '))

$exeVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($builtExe).FileVersion
if ($exeVersion -ne $binaryVersion) { throw "setup exe FileVersion ($exeVersion) != $binaryVersion" }

Write-Host "== Publish =="
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$published = Join-Path $OutputDir ("ExcelDiffSetup-{0}.exe" -f $setupVersion)
Copy-Item -LiteralPath $builtExe -Destination $published -Force
$size = (Get-Item -LiteralPath $published).Length
Write-Host ("  {0}  ({1:N1} MB)" -f $published, ($size / 1MB))
Write-Host '  NOTE: not Authenticode signed. Sign the release artifact before distribution (E10).'
Write-Host 'DONE'
