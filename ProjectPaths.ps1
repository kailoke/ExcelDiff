<#
.SYNOPSIS
    Single source of truth for the machine-local and repo-derived paths the workflow scripts use.

.DESCRIPTION
    Dot-source from a workflow script:
        . (Join-Path $PSScriptRoot '..\ProjectPaths.ps1')
    Self-check from a shell:
        powershell -ExecutionPolicy Bypass -File ProjectPaths.ps1 -Print

    Overridable values resolve: caller parameter > environment variable > the value set here.
    Machine-local things (Program Files base, external test-data repo) are the only values that
    change between machines; everything else derives from the repository root, so the repo can move.

.PARAMETER Print
    Print every resolved path and exit.
#>
param([switch]$Print)

$RepoRootPath = $PSScriptRoot

# ---- machine-local ----
if ($env:EXCELDIFF_PROGRAM_FILES) { $ProgramFilesBasePath = $env:EXCELDIFF_PROGRAM_FILES }
else { $ProgramFilesBasePath = 'D:\Program Files' }

$EdrInstallDirName = 'ExcelDiffEDRTool'
if ($env:EXCELDIFF_DEPLOY_DIR) { $EdrDeployPath = $env:EXCELDIFF_DEPLOY_DIR }
else { $EdrDeployPath = Join-Path $ProgramFilesBasePath $EdrInstallDirName }

# External git repo holding the xlsx config tables for ED/EDE regression (AGENTS 7.7).
# May point at the repo root OR a data subfolder — run_diff_compare.ps1 walks up to the git root
# and prefixes -RelPath accordingly. Override with EXCELDIFF_TESTDATA_REPO.
if ($env:EXCELDIFF_TESTDATA_REPO) { $TestDataRepoPath = $env:EXCELDIFF_TESTDATA_REPO }
else { $TestDataRepoPath = 'F:\ProjectLibs\2_POP时空沙海\Data_POP' }

# ---- repo-derived ----
$RefAssemblyPath     = Join-Path $RepoRootPath 'packages\refs\.NETFramework\v4.7.2'
$NuGetConfigPath     = Join-Path $RepoRootPath '.nuget\NuGet.Config'
$WiXToolManifestPath = Join-Path $RepoRootPath '.config\dotnet-tools.json'
$GuiReleasePath      = Join-Path $RepoRootPath 'ExcelDiff.GUI\bin\Release'
$WorkflowLogDir      = $RepoRootPath
$NetFx64CscPath      = Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'

if ($Print) {
    foreach ($entry in @(
        @{ Name = 'RepoRootPath';          Value = $RepoRootPath;          Source = 'this file location' },
        @{ Name = 'ProgramFilesBasePath';  Value = $ProgramFilesBasePath;  Source = 'EXCELDIFF_PROGRAM_FILES or ProjectPaths.ps1' },
        @{ Name = 'EdrInstallDirName';     Value = $EdrInstallDirName;     Source = 'ProjectPaths.ps1 (also passed to WiX)'; Raw = $true },
        @{ Name = 'EdrDeployPath';         Value = $EdrDeployPath;         Source = 'Deploy-And-Restart -Dst / EXCELDIFF_DEPLOY_DIR' },
        @{ Name = 'TestDataRepoPath';      Value = $TestDataRepoPath;      Source = 'ProjectPaths.ps1 / EXCELDIFF_TESTDATA_REPO' },
        @{ Name = 'RefAssemblyPath';       Value = $RefAssemblyPath;       Source = 'repo-derived' },
        @{ Name = 'NuGetConfigPath';       Value = $NuGetConfigPath;       Source = 'repo-derived' },
        @{ Name = 'WiXToolManifestPath';   Value = $WiXToolManifestPath;   Source = 'repo-derived' },
        @{ Name = 'GuiReleasePath';        Value = $GuiReleasePath;        Source = 'repo-derived' },
        @{ Name = 'WorkflowLogDir';        Value = $WorkflowLogDir;        Source = 'repo-derived' },
        @{ Name = 'NetFx64CscPath';        Value = $NetFx64CscPath;        Source = '$env:SystemRoot' }
    )) {
        $exists = if ($entry.Raw) { 'name' }
        elseif ($entry.Value) { if (Test-Path $entry.Value) { 'OK' } else { 'MISSING' } }
        else { 'unset' }
        Write-Host ('{0,-20} {1,-7} [{2}] {3}' -f $entry.Name, $exists, $entry.Source, $entry.Value)
    }
    exit 0
}
