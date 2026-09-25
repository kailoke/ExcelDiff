<#
.SYNOPSIS
    Build the ExcelDiffEDR (EDE main) MSI installer with WiX Toolset v4.

.DESCRIPTION
    Builds the EDE GUI and ShellExtension into an isolated staging directory,
    harvests the staged app files into AppFiles.generated.wxs, and invokes the
    repository-pinned WiX CLI to produce ExcelDiffEDRSetup.msi.

    Shared paths (framework reference assemblies, NuGet config, WiX tool manifest, default install
    folder name, 64-bit csc.exe) resolve through ProjectPaths.ps1 at the repository root.

.PARAMETER SkipBuild
    Skip restore/build and package the existing isolated staging directory.

.PARAMETER Version
    Optional MSI product version. The first three fields must match the staged
    ExcelDiffEDR.GUI.exe file version. Defaults to the staged file version.

.PARAMETER SkipValidation
    Skip ICE validation. Intended only for constrained local environments;
    release artifacts must be built without this switch.

.PARAMETER Wizard
    Build the MSI with the setup wizard UI (WixToolset.UI.wixext dialog set) instead of the
    default no-UI package. The concrete step design is still open; see the EnableWizard block
    in ExcelDiffEDR.Installer.wxs.
#>
param(
    [switch]$SkipBuild,
    [string]$Version,
    [switch]$SkipValidation,
    [switch]$Wizard
)

$ErrorActionPreference = "Stop"

$InstallerDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $InstallerDir
. (Join-Path $RepoRoot 'ProjectPaths.ps1')
$StageDir = Join-Path $InstallerDir "obj\stage"
$GuiSrc = Join-Path $StageDir "app"
$ShellSrc = Join-Path $StageDir "shell"
$ToolSrc = Join-Path $StageDir "tools"
$StaticWxs = Join-Path $InstallerDir "ExcelDiffEDR.Installer.wxs"
$GeneratedWxs = Join-Path $InstallerDir "AppFiles.generated.wxs"
$OutDir = Join-Path $InstallerDir "Release"
$MsiPath = Join-Path $OutDir "ExcelDiffEDRSetup.msi"

# Machine-local / repo-derived values come from ProjectPaths.ps1; the install directory name is
# passed to WiX so the MSI default folder and Deploy-And-Restart.ps1 share one definition.
$FrameworkPathOverride = $RefAssemblyPath
$NuGetConfig = $NuGetConfigPath
$ToolManifest = $WiXToolManifestPath
$InstallDirName = $EdrInstallDirName
$UpgradeCode = "294F9E11-17CF-4F3D-8ECE-EC7F97A6BCDB"

# WiX extensions are version-locked to the wix CLI, so the UI extension follows the pinned tool
# version in .config\dotnet-tools.json instead of taking whatever is newest on NuGet.
$WixVersion = (Get-Content $ToolManifest -Raw | ConvertFrom-Json).tools.wix.version
$UiExtension = "WixToolset.UI.wixext"

function Get-StableGuid([string]$key) {
    $md5 = [System.Security.Cryptography.MD5]::Create()
    try {
        $bytes = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($key))
        return ([System.Guid]::new([byte[]]($bytes[0..15]))).ToString().ToUpperInvariant()
    }
    finally {
        $md5.Dispose()
    }
}

function Get-HarvestId([string]$prefix, [string]$key) {
    $safe = $key -replace '[^A-Za-z0-9_]', '_'
    if ($safe.Length -gt 48) { $safe = $safe.Substring(0, 48) }
    $hash = (Get-StableGuid $key).Replace('-', '').Substring(0, 12)
    return $prefix + $safe + "_" + $hash
}

function New-TreeNode {
    return @{ Dirs = @{}; Files = New-Object System.Collections.Generic.List[object] }
}

function Invoke-Wix([string[]]$Arguments) {
    Push-Location $RepoRoot
    try {
        & dotnet tool run wix @Arguments 2>&1 | Out-Host
        $exitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }
    return $exitCode
}

# Capture wix output as text (used where the exit code is not a reliable signal).
function Get-WixText([string[]]$Arguments) {
    Push-Location $RepoRoot
    try {
        return (& dotnet tool run wix @Arguments 2>&1 | Out-String)
    }
    finally {
        Pop-Location
    }
}

if (-not (Test-Path $ToolManifest)) {
    throw "WiX tool manifest not found: $ToolManifest"
}

Write-Host "== Restore repository-pinned WiX tool =="
dotnet tool restore --tool-manifest $ToolManifest --configfile $NuGetConfig -v minimal
if ($LASTEXITCODE -ne 0) { throw "WiX tool restore failed" }

Write-Host "== Ensure WiX UI extension $UiExtension/$WixVersion =="
# `wix extension add` is not a trustworthy success signal (already-added and fresh-add both print
# nothing, and a duplicate add has been seen to exit non-zero), so gate on the listed state instead.
# Only needed for -Wizard builds, so a default build keeps working offline.
$extMarker = "$UiExtension $WixVersion"
if ($Wizard) {
    if ((Get-WixText @('extension', 'list')) -notlike "*$extMarker*") {
        Invoke-Wix @('extension', 'add', "$UiExtension/$WixVersion") | Out-Null
    }
    if ((Get-WixText @('extension', 'list')) -notlike "*$extMarker*") {
        throw "WiX UI extension $extMarker is not installed (offline? run once with network access)"
    }
    Write-Host "  $extMarker available"
}
else {
    Write-Host "  skipped (-Wizard not set)"
}

if (-not $SkipBuild) {
    if (Test-Path $StageDir) {
        $resolvedInstallerDir = [System.IO.Path]::GetFullPath($InstallerDir).TrimEnd('\')
        $resolvedStageDir = [System.IO.Path]::GetFullPath($StageDir).TrimEnd('\')
        if (-not $resolvedStageDir.StartsWith($resolvedInstallerDir + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to clean staging directory outside installer directory: $resolvedStageDir"
        }
        Remove-Item -LiteralPath $resolvedStageDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $GuiSrc, $ShellSrc, $ToolSrc -Force | Out-Null

    Write-Host "== Restore + build EDE GUI into isolated staging =="
    dotnet restore "$RepoRoot\ExcelDiff.GUI\ExcelDiff.GUI.csproj" --configfile $NuGetConfig /v:m
    if ($LASTEXITCODE -ne 0) { throw "EDE restore failed" }
    dotnet msbuild "$RepoRoot\ExcelDiff.GUI\ExcelDiff.GUI.csproj" /p:Configuration=Release /p:EdrRead=true `
        /p:FrameworkPathOverride="$FrameworkPathOverride" `
        /p:IncludePackageReferencesDuringMarkupCompilation=false `
        /p:GenerateResourceMSBuildArchitecture=CurrentArchitecture `
        /p:GenerateResourceMSBuildRuntime=CurrentRuntime `
        /p:OutputPath="$GuiSrc\" /p:AppendTargetFrameworkToOutputPath=false `
        /t:Rebuild /v:m /nologo
    if ($LASTEXITCODE -ne 0) { throw "EDE build failed" }

    Write-Host "== Restore + build ShellExtension into isolated staging =="
    dotnet restore "$RepoRoot\ExcelDiff.ShellExtension\ExcelDiff.ShellExtension.csproj" --configfile $NuGetConfig /v:m
    if ($LASTEXITCODE -ne 0) { throw "ShellExtension restore failed" }
    dotnet msbuild "$RepoRoot\ExcelDiff.ShellExtension\ExcelDiff.ShellExtension.csproj" /p:Configuration=Release `
        /p:FrameworkPathOverride="$FrameworkPathOverride" `
        /p:OutputPath="$ShellSrc\" /p:AppendTargetFrameworkToOutputPath=false `
        /t:Rebuild /v:m /nologo
    if ($LASTEXITCODE -ne 0) { throw "ShellExtension build failed" }
}

$guiExe = Join-Path $GuiSrc "ExcelDiffEDR.GUI.exe"
if (-not (Test-Path $guiExe)) {
    throw "ExcelDiffEDR.GUI.exe not found in isolated staging: $GuiSrc"
}

$shellDll = Join-Path $ShellSrc "ExcelDiff.ShellExtension.dll"
$shellSharpShell = Join-Path $ShellSrc "SharpShell.dll"
foreach ($requiredShellFile in @($shellDll, $shellSharpShell, (Join-Path $ShellSrc "System.Resources.Extensions.dll"))) {
    if (-not (Test-Path $requiredShellFile)) { throw "Required ShellExtension file not found: $requiredShellFile" }
}

$binaryVersionText = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($guiExe).FileVersion
try {
    $binaryVersion = [System.Version]::Parse($binaryVersionText)
}
catch {
    throw "Invalid ExcelDiffEDR.GUI.exe file version: $binaryVersionText"
}

if ([string]::IsNullOrWhiteSpace($Version)) {
    $requestedVersion = $binaryVersion
}
else {
    try {
        $requestedVersion = [System.Version]::Parse($Version)
    }
    catch {
        throw "Invalid MSI version '$Version'. Use a.b.c or a.b.c.d."
    }
}

if ($requestedVersion.Major -ne $binaryVersion.Major -or
    $requestedVersion.Minor -ne $binaryVersion.Minor -or
    $requestedVersion.Build -ne $binaryVersion.Build) {
    throw "MSI version $requestedVersion must match ExcelDiffEDR.GUI.exe file version $binaryVersion in the first three fields."
}
if ($requestedVersion.Major -gt 255 -or $requestedVersion.Minor -gt 255 -or $requestedVersion.Build -gt 65535) {
    throw "MSI version exceeds Windows Installer limits (major/minor <= 255, build <= 65535)."
}

$MsiVersion = "{0}.{1}.{2}" -f $requestedVersion.Major, $requestedVersion.Minor, $requestedVersion.Build
$ProductCode = Get-StableGuid ("product|" + $UpgradeCode.ToLowerInvariant() + "|" + $MsiVersion)
Write-Host "MSI version: $MsiVersion; ProductCode: $ProductCode"

$csc = $NetFx64CscPath
$srmSrc = Join-Path $InstallerDir "SrmRegistrar\SrmRegistrar.cs"
$srmOut = Join-Path $ToolSrc "srm.exe"
if (-not (Test-Path $csc)) { throw "64-bit .NET Framework compiler not found: $csc" }
if (-not (Test-Path $ToolSrc)) { New-Item -ItemType Directory -Path $ToolSrc -Force | Out-Null }
Write-Host "== Compile srm.exe against staged SharpShell =="
& $csc /nologo /target:exe /out:$srmOut /r:$shellSharpShell $srmSrc
if ($LASTEXITCODE -ne 0) { throw "srm.exe compile failed (exit $LASTEXITCODE)" }

$guiRootLength = $GuiSrc.TrimEnd('\').Length
$files = @(Get-ChildItem $GuiSrc -Recurse -File | Where-Object {
    $_.Extension -notin @('.pdb', '.xml') -and
    $_.Name -notin @('ExcelDiff.GUI.exe', 'ExcelDiff.GUI.exe.config', 'ExcelDiff.GUI.pdb')
} | Sort-Object { $_.FullName.Substring($guiRootLength + 1).ToLowerInvariant() })

$root = New-TreeNode
foreach ($file in $files) {
    $rel = $file.FullName.Substring($guiRootLength + 1).Replace('\', '/')
    $parts = $rel -split '/'
    $node = $root
    for ($i = 0; $i -lt ($parts.Length - 1); $i++) {
        $directoryName = $parts[$i]
        if (-not $node.Dirs.ContainsKey($directoryName)) { $node.Dirs[$directoryName] = New-TreeNode }
        $node = $node.Dirs[$directoryName]
    }
    $node.Files.Add(@{ Rel = $rel; File = $file })
}

$componentRefs = New-Object System.Collections.Generic.List[string]

function Emit-TreeNode([System.Text.StringBuilder]$builder, $node, [string]$pathPrefix, [string]$indent) {
    foreach ($item in ($node.Files | Sort-Object { $_.Rel.ToLowerInvariant() })) {
        $canonicalPath = $item.Rel.ToLowerInvariant()
        $componentId = Get-HarvestId "C_" $canonicalPath
        $fileId = Get-HarvestId "F_" $canonicalPath
        $guid = Get-StableGuid ("component|" + $canonicalPath)
        [void]$builder.AppendLine(("$indent<Component Id=`"{0}`" Guid=`"{1}`">" -f $componentId, $guid))
        [void]$builder.AppendLine(("$indent  <File Id=`"{0}`" Source=`"{1}`" KeyPath=`"yes`" />" -f $fileId, $item.File.FullName))
        [void]$builder.AppendLine("$indent</Component>")
        $componentRefs.Add($componentId)
    }
    foreach ($directoryName in ($node.Dirs.Keys | Sort-Object)) {
        $child = $node.Dirs[$directoryName]
        $childPath = if ($pathPrefix) { "$pathPrefix/$directoryName" } else { $directoryName }
        $directoryId = Get-HarvestId "D_" $childPath.ToLowerInvariant()
        [void]$builder.AppendLine(("$indent<Directory Id=`"{0}`" Name=`"{1}`">" -f $directoryId, $directoryName))
        Emit-TreeNode $builder $child $childPath ($indent + "  ")
        [void]$builder.AppendLine("$indent</Directory>")
    }
}

$builder = New-Object System.Text.StringBuilder
[void]$builder.AppendLine('<?xml version="1.0" encoding="UTF-8"?>')
[void]$builder.AppendLine('<Wix xmlns="http://wixtoolset.org/schemas/v4/wxs">')
[void]$builder.AppendLine('  <Fragment>')
[void]$builder.AppendLine('    <DirectoryRef Id="INSTALLFOLDER">')
Emit-TreeNode $builder $root "" "      "
[void]$builder.AppendLine('    </DirectoryRef>')
[void]$builder.AppendLine('    <ComponentGroup Id="AppComponents">')
foreach ($componentRef in ($componentRefs | Sort-Object)) {
    [void]$builder.AppendLine(("      <ComponentRef Id=`"{0}`" />" -f $componentRef))
}
[void]$builder.AppendLine('    </ComponentGroup>')
[void]$builder.AppendLine('  </Fragment>')
[void]$builder.AppendLine('</Wix>')

[System.IO.File]::WriteAllText($GeneratedWxs, $builder.ToString(), (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Generated $GeneratedWxs ($($files.Count) files)"

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }

$RepoRootFwd = $RepoRoot.Replace('\', '/')
$StageRootFwd = $StageDir.Replace('\', '/')
$EnableWizard = if ($Wizard) { 'yes' } else { 'no' }
$buildArguments = @('build', '-arch', 'x64', '-nologo')
if ($Wizard) { $buildArguments += @('-ext', $UiExtension) }
$buildArguments += @(
    '-d', "RepoRoot=$RepoRootFwd",
    '-d', "StageRoot=$StageRootFwd",
    '-d', "ProductVersion=$MsiVersion",
    '-d', "ProductCode=$ProductCode",
    '-d', "InstallDirName=$InstallDirName",
    '-d', "EnableWizard=$EnableWizard",
    $StaticWxs, $GeneratedWxs, '-o', $MsiPath
)
Write-Host "== wix build (wizard=$EnableWizard) -> $MsiPath =="
$wixExitCode = Invoke-Wix $buildArguments
if ($wixExitCode -ne 0) { throw "wix build failed (exit $wixExitCode)" }

if ($SkipValidation) {
    Write-Warning "ICE validation skipped. Do not publish this artifact without a successful validation run."
}
else {
    Write-Host "== wix msi validate =="
    $wixExitCode = Invoke-Wix @('msi', 'validate', $MsiPath)
    if ($wixExitCode -ne 0) {
        throw "wix msi validate failed (exit $wixExitCode). Release artifacts must pass ICE validation."
    }
}

$signature = Get-AuthenticodeSignature $MsiPath
if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
    Write-Warning "MSI is not Authenticode signed. Sign the release artifact before distribution."
}

Write-Host "DONE: $MsiPath"
