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
    Administrator the copy still works, but the script refuses to launch the resident process
    (it cannot drop back to normal integrity) and tells you to start it from a non-elevated
    shell - the final restart step then fails with exit code 1.

    Elevation uses Start-Process -Verb RunAs WITHOUT -Wait (ADR-011); the parent polls the
    worker log for DONE. Space-containing paths are quoted in the -ArgumentList array (§8.7).

.PARAMETER NoBuild
    Skip the msbuild step and deploy whatever is currently in bin\Release.

.PARAMETER NoRestart
    Deploy only; do not relaunch the resident process.

.PARAMETER Src
    Build output to deploy. Default: ExcelDiff.GUI\bin\Release under the repo root (ProjectPaths.ps1).

.PARAMETER Dst
    Install directory. Default: $EdrDeployPath from ProjectPaths.ps1 (Program Files base + install
    directory name, overridable with EXCELDIFF_PROGRAM_FILES / EXCELDIFF_DEPLOY_DIR).

.PARAMETER LogDir
    Where deploy_edr.log / deploy_all.log are written. Default: repo root.
#>
param(
    [switch]$NoBuild,
    [switch]$NoRestart,
    [string]$Src    = "",
    [string]$Dst    = "",
    [string]$LogDir = "",
    # internal: elevated deploy worker (kill + copy)
    [string]$Stage  = "",
    [string]$Log    = ""
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot '..\ProjectPaths.ps1')
if (-not $Src)    { $Src = $GuiReleasePath }
if (-not $Dst)    { $Dst = $EdrDeployPath }
if (-not $LogDir) { $LogDir = $WorkflowLogDir }

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
# Returns $true when the resident process is confirmed running.
function Start-Resident($exe, $wd) {
    if (Test-IsAdmin) {
        # Deliberately NOT launching here. Launching from an elevated parent yields a high-IL GUI,
        # which a non-elevated difftool (Fork) cannot reach over the named pipe (UIPI); the old
        # `explorer.exe "<exe>" --startup` downgrade trick was measured to start nothing (2026-09-25).
        Write-Host "  [!] This shell is ELEVATED - cannot start the resident at normal integrity from here." -ForegroundColor Yellow
        Write-Host "  [!] Run this in a normal (non-admin) PowerShell instead:" -ForegroundColor Yellow
        Write-Host "          `"$exe`" --startup" -ForegroundColor Yellow
        return $false
    }

    Start-Process $exe -ArgumentList "--startup" -WorkingDirectory $wd
    Start-Sleep -Seconds 3
    $proc = Get-Process -Name "ExcelDiffEDR.GUI" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $proc) { return $false }
    Write-Host ("  resident running: pid=" + $proc.Id)
    return $true
}

try {
    if (-not $NoBuild) {
        Write-Host "== Restore EDE packages =="
        dotnet restore ExcelDiff.GUI/ExcelDiff.GUI.csproj --configfile "$NuGetConfigPath" /v:m
        if ($LASTEXITCODE -ne 0) { throw "EDE restore failed (exit $LASTEXITCODE)" }
        dotnet restore ExcelDiff/ExcelDiff.csproj --configfile "$NuGetConfigPath" /v:m
        if ($LASTEXITCODE -ne 0) { throw "ExcelDiff restore failed (exit $LASTEXITCODE)" }

        Write-Host "== Build EDE (main) =="
        dotnet msbuild ExcelDiff.GUI/ExcelDiff.GUI.csproj /p:Configuration=Release /p:EdrRead=true `
            "/p:FrameworkPathOverride=$RefAssemblyPath" `
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
        if (-not (Start-Resident "$Dst\ExcelDiffEDR.GUI.exe" $Dst)) {
            throw ("Copy finished but no resident is running. If this shell is elevated, start it " +
                   "from a non-elevated one: `"$Dst\ExcelDiffEDR.GUI.exe`" --startup")
        }
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
