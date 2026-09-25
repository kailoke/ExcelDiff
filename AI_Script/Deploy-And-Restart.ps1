<#
.SYNOPSIS
    Build EDR (main), deploy to Program Files, and restart the resident process.

.DESCRIPTION
    Solidifies the deploy/restart procedure documented in AI_Programmer\AGENTS.md §7.6 / §8.6 / §8.7.
    EDR (EdrRead=true) is the main/primary version and the only variant built, deployed,
    and restarted by this script. The EDN (NPOI) fallback variant is retained in source for
    reference/对照 but is no longer built or deployed in the daily flow.

    IMPORTANT - integrity level:
    The resident GUI must run at the SAME integrity level as the interactive desktop; otherwise a
    difftool client started from the desktop (e.g. Fork) cannot reach the named-pipe IPC and the
    tray icon is unresponsive (UIPI). "Same level" is the invariant, NOT "non-elevated": on a
    machine with UAC off (HKLM\...\Policies\System\EnableLUA = 0) explorer, Fork and this script
    are all High, so running this script from an elevated shell is correct there; with UAC on the
    desktop shell is Medium and the resident must be Medium too.
    This script elevates ONLY the copy worker (Program Files write + killing the old process to
    release file locks), launches the resident from the parent process, and then verifies the
    resident's integrity level against explorer - a mismatch fails with exit code 1, while an
    unreadable token only warns (inconclusive comparison must not block a working deploy).

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

# Integrity level of a process token as an SID string (S-1-16-8192 Medium, S-1-16-12288 High).
# Any failure returns "unknown" - the caller must treat that as inconclusive, never as a mismatch.
function Get-ProcessIntegrity([System.Diagnostics.Process]$proc) {
    try {
        if (-not ('IntegrityLevel' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class IntegrityLevel {
    [DllImport("advapi32.dll", SetLastError=true)] static extern bool OpenProcessToken(IntPtr h, uint a, out IntPtr tok);
    [DllImport("advapi32.dll", SetLastError=true)] static extern bool GetTokenInformation(IntPtr tok, int cls, IntPtr buf, uint len, out uint ret);
    [DllImport("advapi32.dll", CharSet=CharSet.Unicode)] static extern bool ConvertSidToStringSid(IntPtr sid, out IntPtr str);
    [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr h);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    public static string Of(IntPtr procHandle) {
        IntPtr tok;
        if (!OpenProcessToken(procHandle, 0x0008, out tok)) return "unknown";
        try {
            uint ret;
            IntPtr buf = Marshal.AllocHGlobal(64);
            try {
                if (!GetTokenInformation(tok, 25, buf, 64, out ret)) return "unknown";
                IntPtr str;
                IntPtr sid = Marshal.ReadIntPtr(buf);
                string s = ConvertSidToStringSid(sid, out str) ? Marshal.PtrToStringUni(str) : "unknown";
                if (str != IntPtr.Zero) LocalFree(str);
                return s;
            }
            finally { Marshal.FreeHGlobal(buf); }
        }
        finally { CloseHandle(tok); }
    }
}
'@
        }
        return [IntegrityLevel]::Of($proc.Handle)
    }
    catch { return "unknown" }
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

# ---- Main: runs at the interactive desktop's integrity; elevates only the deploy worker ----
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

# Relaunch the resident and confirm it is reachable by the desktop's difftool client.
# The invariant is "same integrity level as the interactive desktop", NOT "non-elevated": with UAC off
# (HKLM...\Policies\System\EnableLUA = 0) explorer, Fork and this script are all High, and a Medium
# requirement would be unsatisfiable. Returns $true when the resident runs at the desktop's level.
function Start-Resident($exe, $wd) {
    Start-Process $exe -ArgumentList "--startup" -WorkingDirectory $wd
    Start-Sleep -Seconds 3
    $proc = Get-Process -Name "ExcelDiffEDR.GUI" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $proc) { return $false }

    $desktop = Get-Process -Name explorer -ErrorAction SilentlyContinue | Select-Object -First 1
    $guiIL = Get-ProcessIntegrity $proc
    if (-not $desktop) {
        Write-Host ("  resident pid=" + $proc.Id + " IL=" + $guiIL + "  (no explorer to compare; cannot verify)")
        return $true
    }
    $shellIL = Get-ProcessIntegrity $desktop
    Write-Host ("  resident pid=" + $proc.Id + " IL=" + $guiIL + "  desktop IL=" + $shellIL)
    if ($guiIL -eq 'unknown' -or $shellIL -eq 'unknown') {
        # A token we are not allowed to open (e.g. querying a higher-IL process) makes the comparison
        # inconclusive, not failed - do not block a working deploy on that.
        Write-Warning '  integrity comparison inconclusive; check manually: $env:WINDIR\System32\whoami.exe /groups'
        return $true
    }
    if ($guiIL -ne $shellIL) {
        # Do not leave a wrong-level resident running: the next run would pick it up via
        # Get-Process -First 1 and report a false pass while the new binary never actually ran.
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        Write-Warning ("resident started at $guiIL but the desktop is $shellIL - a difftool launched from the " +
                       "desktop cannot reach it over the named pipe, so it was stopped. Rerun this script from " +
                       "a shell at the desktop integrity level.")
        return $false
    }
    return $true
}

try {
    if (-not $NoBuild) {
        Write-Host "== Restore EDR packages =="
        dotnet restore ExcelDiff.GUI/ExcelDiff.GUI.csproj --configfile "$NuGetConfigPath" /v:m
        if ($LASTEXITCODE -ne 0) { throw "EDR restore failed (exit $LASTEXITCODE)" }
        dotnet restore ExcelDiff/ExcelDiff.csproj --configfile "$NuGetConfigPath" /v:m
        if ($LASTEXITCODE -ne 0) { throw "ExcelDiff restore failed (exit $LASTEXITCODE)" }

        Write-Host "== Build EDR (main) =="
        dotnet msbuild ExcelDiff.GUI/ExcelDiff.GUI.csproj /p:Configuration=Release /p:EdrRead=true `
            "/p:FrameworkPathOverride=$RefAssemblyPath" `
            /p:IncludePackageReferencesDuringMarkupCompilation=false `
            /p:GenerateResourceMSBuildArchitecture=CurrentArchitecture `
            /p:GenerateResourceMSBuildRuntime=CurrentRuntime /t:Build /v:m /nologo
        if ($LASTEXITCODE -ne 0) { throw "EDR build failed (exit $LASTEXITCODE)" }
    }

    Write-Host "== Deploy EDR -> $Dst =="
    if (-not (Invoke-ElevatedDeploy $Src $Dst (Join-Path $LogDir "deploy_edr.log"))) {
        throw "EDR deploy failed"
    }

    if (-not $NoRestart) {
        Write-Host "== Relaunch resident process (integrity verified against the desktop) =="
        Start-Sleep -Seconds 1
        if (-not (Start-Resident "$Dst\ExcelDiffEDR.GUI.exe" $Dst)) {
            throw ("Copy finished but no usable resident is running (started, or integrity level differs " +
                   "from the desktop). Manual check: `"$Dst\ExcelDiffEDR.GUI.exe`" --startup")
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
