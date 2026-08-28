<#
.SYNOPSIS
    Build EDE (main), deploy to Program Files, and restart the resident process.

.DESCRIPTION
    Solidifies the deploy/restart procedure documented in AI_Programmer\AGENTS.md §7.6 / §8.6 / §8.7.
    EDE (EdrRead=true) is the main/primary version and the only variant built, deployed,
    and restarted by this script. The ED (NPOI) fallback variant is retained in source for
    reference/对照 but is no longer built or deployed in the daily flow.

    IMPORTANT - integrity level:
    The GUI must run at the NORMAL user's integrity level, not elevated. An elevated GUI
    cannot serve a non-elevated difftool client (e.g. Fork) over the named-pipe IPC, and its
    tray icon is unresponsive to the non-elevated explorer (UIPI). Therefore this script
    elevates ONLY the deploy step (which writes to Program Files and kills the old process
    to release file locks) and relaunches the GUI from the NON-elevated parent process.
    Run this script NON-elevated; it self-elevates just the copy worker. If you run it as
    Administrator, the relaunch will attempt to drop to medium IL via explorer.exe, but
    running non-elevated is the supported path.

    Elevation uses Start-Process -Verb RunAs WITHOUT -Wait (ADR-011); the parent polls the
    worker log for DONE. Space-containing paths are quoted in the -ArgumentList array (§8.7).

.PARAMETER NoBuild
    Skip the msbuild step and deploy whatever is currently in bin\Release.

.PARAMETER NoRestart
    Deploy only; do not relaunch the resident process.
#>
param(
    [switch]$NoBuild,
    [switch]$NoRestart,
    [string]$Src    = "D:\ExcelDiff\ExcelDiff.GUI\bin\Release",
    [string]$Dst    = "D:\Program Files\ExcelDiffEDRTool",
    [string]$LogDir = "D:\ExcelDiff",
    # internal: elevated deploy worker (kill + copy)
    [string]$Stage  = "",
    [string]$Log    = ""
)

$ErrorActionPreference = "Stop"

function Test-IsAdmin {
    $wp = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    return $wp.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ---- Elevated deploy worker: kill old process (release locks) + copy ----
if ($Stage -eq "deploy") {
    try {
        # Kill first so the exe/dll locks are released (can kill elevated processes too).
        Get-Process -Name "ExcelDiffEDR.GUI" -ErrorAction SilentlyContinue |
            Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1

        # Avoid the lang\lang nesting pitfall (AI_Programmer\ARCHITECTURE.md §8): delete dest lang first.
        if (Test-Path "$Dst\lang") { Remove-Item "$Dst\lang" -Recurse -Force }

        $attempt = 0; $ok = $false
        while ($attempt -lt 3 -and -not $ok) {
            $attempt++
            try {
                Get-ChildItem -Path $Src | Copy-Item -Destination $Dst -Recurse -Force
                $ok = $true
            }
            catch {
                Write-Host "  copy attempt $attempt failed: $_"
                Start-Sleep -Seconds 1
            }
        }
        if (-not $ok) { throw "Copy to $Dst failed after 3 attempts (file locked?)" }

        # Verify the key exe actually landed (§8.7: confirm the target exe is updated).
        $srcExe = Get-ChildItem -Path $Src -Filter "ExcelDiffEDR.GUI.exe" | Select-Object -First 1
        if (-not $srcExe) { throw "No ExcelDiffEDR.GUI.exe found in $Src" }
        $dstExe = Join-Path $Dst $srcExe.Name
        if (-not (Test-Path $dstExe)) { throw "Deploy verification failed: $dstExe missing" }
        Write-Host "Deployed $($srcExe.Name) -> $dst ($(Get-Item $dstExe | Select-Object -ExpandProperty LastWriteTime))"

        "DONE" | Out-File -FilePath $Log -Encoding ascii
    }
    catch {
        "FAIL: $_" | Out-File -FilePath $Log -Encoding ascii
    }
    return
}

# ---- Main: runs NON-elevated; elevates only the deploy worker ----
Set-Location (Split-Path -Parent $PSScriptRoot)   # repo root (script lives in AI_Script\)

function Invoke-ElevatedDeploy($src, $dst, $log) {
    Remove-Item $log -ErrorAction SilentlyContinue
    $argList = @(
        "-ExecutionPolicy Bypass",
        "-File",
        "`"$PSCommandPath`"",
        "-Stage", "deploy",
        "-Src", "`"$src`"",
        "-Dst", "`"$dst`"",
        "-Log", "`"$log`""
    )
    Start-Process powershell -Verb RunAs -ArgumentList $argList

    $elapsed = 0
    while ($elapsed -lt 240) {
        if (Test-Path $log) {
            $c = Get-Content $log -Raw
            if ($c -like "*DONE*") { return $true }
            if ($c -like "*FAIL*") { return $false }
        }
        Start-Sleep -Seconds 2
        $elapsed += 2
    }
    return $false
}

# Relaunch the GUI at the NORMAL user integrity level (never elevated - see header).
function Start-Resident($exe, $wd) {
    if (Test-IsAdmin) {
        # Drop to medium IL so the GUI matches the interactive (non-elevated) user / difftool.
        Start-Process "explorer.exe" -ArgumentList "`"$exe`" --startup"
    }
    else {
        Start-Process $exe -ArgumentList "--startup" -WorkingDirectory $wd
    }
}

try {
    if (-not $NoBuild) {
        Write-Host "== Restore EDE packages =="
        dotnet restore ExcelDiff.GUI/ExcelDiff.GUI.csproj --configfile "D:\ExcelDiff\.nuget\NuGet.Config" /v:m
        if ($LASTEXITCODE -ne 0) { throw "EDE restore failed (exit $LASTEXITCODE)" }
        dotnet restore ExcelDiff/ExcelDiff.csproj --configfile "D:\ExcelDiff\.nuget\NuGet.Config" /v:m
        if ($LASTEXITCODE -ne 0) { throw "ExcelDiff restore failed (exit $LASTEXITCODE)" }

        Write-Host "== Build EDE (main) =="
        dotnet msbuild ExcelDiff.GUI/ExcelDiff.GUI.csproj /p:Configuration=Release /p:EdrRead=true `
            /p:FrameworkPathOverride="D:\ExcelDiff\packages\refs\.NETFramework\v4.7.2" `
            /p:IncludePackageReferencesDuringMarkupCompilation=false `
            /p:GenerateResourceMSBuildArchitecture=CurrentArchitecture `
            /p:GenerateResourceMSBuildRuntime=CurrentRuntime /t:Build /v:m /nologo
        if ($LASTEXITCODE -ne 0) { throw "EDE build failed (exit $LASTEXITCODE)" }
    }

    Write-Host "== Deploy EDE -> $Dst =="
    if (-not (Invoke-ElevatedDeploy $Src $Dst (Join-Path $LogDir "deploy_edr.log"))) {
        throw "EDE deploy failed"
    }

    if (-not $NoRestart) {
        Write-Host "== Relaunch resident process (non-elevated) =="
        Start-Sleep -Seconds 1
        Start-Resident "$Dst\ExcelDiffEDR.GUI.exe" $Dst
        Start-Sleep -Seconds 3
        Get-Process -Name "ExcelDiffEDR.GUI" -ErrorAction SilentlyContinue |
            Select-Object Name, Id, Path | Format-Table -AutoSize | Out-String | Write-Host
    }
    else {
        Write-Host "== -NoRestart: left stopped =="
    }

    "DONE" | Out-File -FilePath (Join-Path $LogDir "deploy_all.log") -Encoding ascii
}
catch {
    "FAIL: $_" | Out-File -FilePath (Join-Path $LogDir "deploy_all.log") -Encoding ascii
    Write-Error $_
    exit 1
}
