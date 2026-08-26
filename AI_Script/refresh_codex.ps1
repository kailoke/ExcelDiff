# refresh_codex.ps1 - Recalibrate line numbers in AI_Programmer\CODEX.md.
#
# Semi-automatic: each "File.cs:NNN" annotation in CODEX.md is matched, in document
# order, to a curated target (source file + symbol regex) below. The line number is
# refreshed from the live source. If any annotation fails to resolve, or the order
# diverges from the target list, nothing is written and the script exits non-zero.
#
# Usage:  powershell -ExecutionPolicy Bypass -File AI_Script\refresh_codex.ps1
#
# NOTE: keep this file pure ASCII (PowerShell 5.1 reads .ps1 without BOM as ANSI).

$ErrorActionPreference = 'Stop'

$root  = Split-Path -Parent $PSScriptRoot   # repo root (script lives in AI_Script\)
$codex = Join-Path $root 'AI_Programmer\CODEX.md'

# Curated targets, in the exact order their annotations appear in CODEX.md.
$Targets = @(
  @{ Key = 'App.xaml.cs';                         File = 'ExcelDiff.GUI\App.xaml.cs';                          Pattern = 'public static void Main' },
  @{ Key = 'App.xaml.cs';                         File = 'ExcelDiff.GUI\App.xaml.cs';                          Pattern = 'override void OnStartup' },
  @{ Key = 'DiffCommand.cs';                      File = 'ExcelDiff.GUI\Commands\DiffCommand.cs';              Pattern = 'public void Execute\(' },
  @{ Key = 'DiffView.xaml.cs';                    File = 'ExcelDiff.GUI\Views\DiffView.xaml.cs';               Pattern = 'Tuple<ExcelWorkbook, ExcelWorkbook> ReadWorkbooks' },
  @{ Key = 'DiffView.xaml.cs';                    File = 'ExcelDiff.GUI\Views\DiffView.xaml.cs';               Pattern = 'ExcelSheetDiff ExecuteDiff\(ExcelSheet' },
  @{ Key = 'DiffView.xaml.cs';                    File = 'ExcelDiff.GUI\Views\DiffView.xaml.cs';               Pattern = 'private void ExecuteDiff\(bool' },
  @{ Key = 'SingleInstance.cs';                   File = 'ExcelDiff.GUI\SingleInstance.cs';                    Pattern = 'public static bool SendToRunningInstance' },
  @{ Key = 'SingleInstance.cs';                   File = 'ExcelDiff.GUI\SingleInstance.cs';                    Pattern = 'private static void ServerLoop' },
  @{ Key = 'App.xaml.cs';                         File = 'ExcelDiff.GUI\App.xaml.cs';                          Pattern = 'private void OnRemoteCommand' },
  @{ Key = 'App.xaml.cs';                         File = 'ExcelDiff.GUI\App.xaml.cs';                          Pattern = 'private void RouteCommand' },
  @{ Key = 'DiffView.xaml.cs';                    File = 'ExcelDiff.GUI\Views\DiffView.xaml.cs';               Pattern = 'public void ApplyDiff' },
  @{ Key = 'App.xaml.cs';                         File = 'ExcelDiff.GUI\App.xaml.cs';                          Pattern = 'class App\b' },
  @{ Key = 'SingleInstance.cs';                   File = 'ExcelDiff.GUI\SingleInstance.cs';                    Pattern = 'class SingleInstance' },
  @{ Key = 'TrayIconManager.cs';                  File = 'ExcelDiff.GUI\TrayIconManager.cs';                   Pattern = 'class TrayIconManager' },
  @{ Key = 'StartupHelper.cs';                    File = 'ExcelDiff.GUI\StartupHelper.cs';                     Pattern = 'class StartupHelper' },
  @{ Key = 'Timing.cs';                           File = 'ExcelDiff.GUI\Timing.cs';                            Pattern = 'class Timing' },
  @{ Key = 'Commands/DiffCommand.cs';             File = 'ExcelDiff.GUI\Commands\DiffCommand.cs';              Pattern = 'class DiffCommand' },
  @{ Key = 'Commands/CommandFactory.cs';          File = 'ExcelDiff.GUI\Commands\CommandFactory.cs';           Pattern = 'class CommandFactory' },
  @{ Key = 'Commands/CommandLineOption.cs';       File = 'ExcelDiff.GUI\Commands\CommandLineOption.cs';        Pattern = 'class CommandLineOption' },
  @{ Key = 'Views/MainWindow.xaml.cs';            File = 'ExcelDiff.GUI\Views\MainWindow.xaml.cs';             Pattern = 'class MainWindow' },
  @{ Key = 'Views/DiffView.xaml.cs';              File = 'ExcelDiff.GUI\Views\DiffView.xaml.cs';               Pattern = 'class DiffView\b' },
  @{ Key = 'Views/NoDiffWindow.xaml.cs';          File = 'ExcelDiff.GUI\Views\NoDiffWindow.xaml.cs';           Pattern = 'class NoDiffWindow' },
  @{ Key = 'Localization/LocalizationManager.cs'; File = 'ExcelDiff.GUI\Localization\LocalizationManager.cs'; Pattern = 'class LocalizationManager' },
  @{ Key = 'ExcelWorkbook.cs';                    File = 'ExcelDiff\ExcelWorkbook.cs';                          Pattern = 'class ExcelWorkbook' },
  @{ Key = 'ExcelSheetDiff.cs';                   File = 'ExcelDiff\ExcelSheetDiff.cs';                         Pattern = 'class ExcelSheetDiff' }
)

$content = [System.IO.File]::ReadAllText($codex)
$regex   = [regex]'([A-Za-z0-9_./\\-]+\.cs):(\d+)'
$matches = $regex.Matches($content)

if ($matches.Count -ne $Targets.Count) {
    Write-Host ("[FAIL] annotation count mismatch: CODEX.md has {0}, target list has {1}" -f $matches.Count, $Targets.Count)
    exit 1
}

$updates = @()
for ($i = 0; $i -lt $matches.Count; $i++) {
    $m   = $matches[$i]
    $key = $m.Groups[1].Value
    $old = [int]$m.Groups[2].Value
    $t   = $Targets[$i]

    if ($key -ne $t.Key) {
        Write-Host ("[FAIL] order mismatch at #{0}: expected '{1}', got '{2}'" -f ($i + 1), $t.Key, $key)
        exit 1
    }
    $hit = Select-String -Path (Join-Path $root $t.File) -Pattern $t.Pattern -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $hit) {
        Write-Host ("[FAIL] symbol not found: {0} ({1})" -f $t.File, $t.Pattern)
        exit 1
    }
    $updates += [PSCustomObject]@{ Key = $key; Old = $old; New = $hit.LineNumber; File = $t.File }
}

# Rebuild the document with refreshed line numbers (order preserved).
$sb   = New-Object System.Text.StringBuilder
$last = 0
for ($i = 0; $i -lt $matches.Count; $i++) {
    $m = $matches[$i]
    [void]$sb.Append($content.Substring($last, $m.Index - $last))
    [void]$sb.Append(($updates[$i].Key + ':' + $updates[$i].New))
    $last = $m.Index + $m.Length
}
[void]$sb.Append($content.Substring($last))

# UTF-8 without BOM (INVARIANTS D3 convention).
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($codex, $sb.ToString(), $utf8)

$changed = @($updates | Where-Object { $_.Old -ne $_.New })
Write-Host ("Refreshed {0} annotations ({1} changed) in {2}" -f $updates.Count, $changed.Count, $codex)
$changed | ForEach-Object { Write-Host ("  {0}:{1} -> {2}  ({3})" -f $_.Key, $_.Old, $_.New, $_.File) }
