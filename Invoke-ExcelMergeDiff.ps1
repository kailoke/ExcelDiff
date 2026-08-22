# Invoke-ExcelMergeDiff.ps1 - Safe wrapper for starting a GUI diff.
#
# AGENTS.md 8.3 / INVARIANTS C4: NEVER `Start-Process ... -Wait` on the ExcelMerge
# forwarder. When no resident instance is running, the forwarder becomes resident
# itself and never exits, so -Wait hangs forever.
#
# This wrapper starts the diff fire-and-forget (no -Wait) and polls for the diff
# main window instead of waiting for process exit. Use it from smoke/regression
# scripts whenever you need to launch and (optionally) wait for a diff session.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File Invoke-ExcelMergeDiff.ps1 `
#       -Executable D:\Program Files\ExcelMerge\ExcelMerge.GUI.exe `
#       -SrcPath <src> -DstPath <dst> [-WaitClose] [-TimeoutSeconds 90]
#
# -WaitClose: additionally poll until the diff window closes (session end).
# Without it the script returns as soon as the diff window is shown.
# Exit code 0 = window appeared (and closed, if -WaitClose), 1 = timeout.

param(
    [Parameter(Mandatory)][string]$Executable,
    [Parameter(Mandatory)][string]$SrcPath,
    [Parameter(Mandatory)][string]$DstPath,
    [switch]$WaitClose,
    [int]$TimeoutSeconds = 90
)
$ErrorActionPreference = 'Stop'

function Wait-DiffWindow {
    param([switch]$UntilClosed, [int]$TimeoutSeconds)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $win = Get-Process -Name 'ExcelMerge*' -ErrorAction SilentlyContinue |
            Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
        $has = [bool]$win
        if (-not $UntilClosed -and $has) { return $true }
        if ($UntilClosed -and -not $has) { return $true }
        Start-Sleep -Milliseconds 300
    }
    return $false
}

# Fire-and-forget: never pass -Wait here.
Start-Process -FilePath $Executable -ArgumentList @('diff', '-s', $SrcPath, '-d', $DstPath)

if (-not (Wait-DiffWindow -TimeoutSeconds $TimeoutSeconds)) {
    Write-Host 'ExcelMerge diff window did not appear in time' -ForegroundColor Red
    exit 1
}

if ($WaitClose) {
    if (-not (Wait-DiffWindow -UntilClosed -TimeoutSeconds $TimeoutSeconds)) {
        Write-Host 'ExcelMerge diff window did not close in time' -ForegroundColor Red
        exit 1
    }
}

exit 0
