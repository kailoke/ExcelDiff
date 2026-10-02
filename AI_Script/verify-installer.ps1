<#
.SYNOPSIS
    Release gate for the ExcelDiffEDR setup wizard (INVARIANTS E10).

.DESCRIPTION
    Static checks always run:
      - the published setup exe exists and carries the payload + both string tables
      - the payload's own main exe FileVersion equals the setup exe FileVersion (E8)
      - the payload holds no symbols, no helper tool and no leftover reader library (E7)
      - zh-CN and en-US string tables have identical key sets, with the same {0} placeholders
        per key (a drifting arity throws at runtime)
      - the published exe is newer than every installer source (a green run on a stale binary
        proves nothing)
      - no hardcoded brand or CJK text in XAML - that rule is owned by INVARIANT D1 and is scanned
        by AI_Script\verify.ps1 across the whole solution, so it is deliberately not duplicated here

    Pass -Install to run the real cases against a throwaway folder:
      A  install with every component -> assert files/registry/COM/shortcuts/auto-start -> uninstall
      B  install into a PRE-EXISTING non-empty folder that then fails -> the unrelated file survives
      C  uninstall with no /dir and no registry record -> must fail, must not touch the default folder
      D  run setup from inside the installed folder (the ARP shape) -> must succeed via the temp copy
      E  reinstall over an existing install -> same folder, no .old-* leftovers
      F  auto-start OFF while the Run value belongs to another folder -> that value is left alone
      G  /clearsettings governs the user settings folder (default keeps it, switch removes it)
      H  malformed command lines -> exit code 4, nothing installed, empty /dir= refused
      I  well-formed command lines are still accepted (switch validation has no false positives)
      J  install folder without install-manifest.txt -> uninstall refuses, files and HKLM record
         survive, and succeeds again once the manifest is put back (positive control)
      K  bad target shapes (/dir=Q:\, /dir=Q:, /dir=Tools relative) are argument errors: exit 4,
         nothing installed, and no folder created from a working-directory resolution
      L  the in-folder Uninstall.exe uninstalls on its name alone (no /uninstall), which also proves
         the %TEMP% relay carries the role as an explicit switch
      M  the ARP QuietUninstallString itself performs the uninstall - the only coverage of the
         recorded-folder branch of ResolveUninstallDir, because that string carries no /dir

    Every assertion is taken BEFORE the finally-block repairs anything, so a product bug cannot be
    hidden by the gate's own cleanup. -Install writes HKLM keys, registers a COM server and touches
    the HKCU Run value: it refuses to start when a foreign CLSID registration or an existing install
    would be damaged. Requires an elevated shell.

    ASCII only: a .ps1 with non-ASCII literals needs a BOM or PowerShell 5.1 decodes it as GBK.

.PARAMETER Install
    Run the live cases.

.PARAMETER SetupExe
    Path to the setup exe. Defaults to the newest ExcelDiff.Installer\Release\ExcelDiffSetup-*.exe.
#>
[CmdletBinding()]
param(
    [switch]$Install,
    [string]$SetupExe
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'ProjectPaths.ps1')

$ReleaseDir = Join-Path $root 'ExcelDiff.Installer\Release'
$StringsDir = Join-Path $root 'ExcelDiff.Installer\Strings'
$ProductRegPath = 'HKLM:\SOFTWARE\ExcelDiffEDR'
$ArpRegPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\ExcelDiffEDR'
$ClsidPath = 'HKLM:\SOFTWARE\Classes\CLSID\{C7471DED-BC6E-4A86-8B71-2B9FE239FE07}'
$RunKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$RunValue = 'ExcelDiffEDR.GUI'
$StartMenuDir = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\ExcelDiffEDR'

$script:failed = 0
$script:passed = 0
$script:skipped = 0

function Check([string]$name, [bool]$ok, [string]$detail) {
    if ($ok) { $script:passed++ } else { $script:failed++ }
    '{0}  {1}{2}' -f ($(if ($ok) { 'PASS' } else { 'FAIL' })), $name, $(if ($detail) { '  [' + $detail + ']' } else { '' })
}

function Skip([string]$name, [string]$why) {
    $script:skipped++
    'SKIP  {0}  [{1}]' -f $name, $why
}

function CheckKey([string]$name, $actual, $expected) {
    Check $name ($actual -eq $expected) ('got=' + $actual)
}

# Artifact names come from the source, never from a literal in this gate: a rename must not be able
# to green-light itself. Same pattern Build-Setup.ps1 uses for InstallDirName.
$ProductInfoSource = [System.IO.File]::ReadAllText((Join-Path $root 'ExcelDiff.Installer\Core\ProductInfo.cs'))
$UninstallerMatch = [regex]::Match($ProductInfoSource, 'UninstallerName\s*=\s*"([^"]+)"')
Check 'ProductInfo declares UninstallerName' ($UninstallerMatch.Success) ''
$UninstallerName = if ($UninstallerMatch.Success) { $UninstallerMatch.Groups[1].Value } else { 'Uninstall.exe' }
$MainExeName = [regex]::Match($ProductInfoSource, 'MainExeName\s*=\s*"([^"]+)"').Groups[1].Value
# The role is decided by this filename, so a value that is not a bare .exe - or that collides with
# the app's own exe - would make double-clicking the program mean two different things.
Check 'uninstaller name is a bare .exe and not the app exe' `
    ($UninstallerName -notmatch '[\\/]' -and $UninstallerName -like '*.exe' -and $UninstallerName -ne $MainExeName) `
    ('name=' + $UninstallerName + ' app=' + $MainExeName)
$ZhText = [System.IO.File]::ReadAllText((Join-Path $StringsDir 'zh-CN.txt'))
$EnText = [System.IO.File]::ReadAllText((Join-Path $StringsDir 'en-US.txt'))
$StringTables = $ZhText + $EnText
Check 'user-facing strings do not promise a setup-named file' (-not ($StringTables -match 'ExcelDiffSetup\.exe')) `
    'the install folder holds Uninstall.exe; err.noUninstallTarget and finish.noshell must match that'
# finish.noshell is how the user learns where the uninstall entry lives, so it must name the artifact
# the engine actually writes; a rename that leaves it behind is the drift this gate exists to catch
# (E13). The refusal strings are deliberately not listed here: err.noUninstallTarget now warns that
# the in-folder artifact cannot help in that state, which is the opposite of pointing at it.
foreach ($key in @('finish.noshell')) {
    $hits = @(foreach ($text in @($ZhText, $EnText)) {
        $value = [regex]::Match($text, ('(?m)^' + [regex]::Escape($key) + '=(.*)$')).Groups[1].Value
        if ($value.Contains($UninstallerName)) { $text }
    }).Count
    Check "$key names the in-folder artifact in both languages" ($hits -eq 2) ('hits=' + $hits + '/2')
}

function KeySet([string]$path) {
    # Explicit UTF-8: PS 5.1 would otherwise decode these BOM-less files as GBK and a
    # double-byte trail byte can swallow the following ASCII character, merging lines.
    @(Get-Content -LiteralPath $path -Encoding UTF8 | Where-Object { $_ -match '^[^#=]+=' } |
        ForEach-Object { ($_ -split '=', 2)[0].Trim() }) | Sort-Object
}

function Hash-Dir([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return 'absent' }
    $lines = @(Get-ChildItem -LiteralPath $path -Recurse -File |
        Sort-Object FullName |
        ForEach-Object { $_.Name + '=' + (Get-FileHash $_.FullName -Algorithm SHA1).Hash })
    return (Get-FileHash -InputStream ([IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes(($lines -join ';')))) -Algorithm SHA1).Hash
}

# ---------------------------------------------------------------- static checks

if (-not $SetupExe) {
    $candidate = Get-ChildItem -LiteralPath $ReleaseDir -Filter 'ExcelDiffSetup-*.exe' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $candidate) {
        Check 'setup exe published' $false "run ExcelDiff.Installer\Build-Setup.ps1 first ($ReleaseDir)"
        Write-Host ''; Write-Host 'RESULT: FAILURES'
        exit 1
    }
    $SetupExe = $candidate.FullName
}
Check 'setup exe published' (Test-Path -LiteralPath $SetupExe) $SetupExe

$assembly = [System.Reflection.Assembly]::LoadFile([System.IO.Path]::GetFullPath($SetupExe))
$resources = @($assembly.GetManifestResourceNames())
foreach ($required in @('ExcelDiff.Setup.Payload.zip', 'ExcelDiff.Setup.Strings.zh-CN.txt', 'ExcelDiff.Setup.Strings.en-US.txt')) {
    Check "embedded resource $required" ($resources -contains $required)
}

Add-Type -AssemblyName System.IO.Compression.FileSystem | Out-Null
Add-Type -AssemblyName System.IO.Compression | Out-Null

$probe = Join-Path $env:TEMP ('setup-gate-' + [Guid]::NewGuid().ToString('N') + '.zip')
$stream = $assembly.GetManifestResourceStream('ExcelDiff.Setup.Payload.zip')
$fs = [System.IO.File]::Create($probe)
$stream.CopyTo($fs, 1MB)
$fs.Dispose(); $stream.Dispose()

$archive = [System.IO.Compression.ZipFile]::OpenRead($probe)
try {
    $entries = @($archive.Entries | ForEach-Object { $_.FullName.Replace('\', '/') })
    $leaves = $entries | ForEach-Object { $_.Split('/')[-1] }

    Check 'payload has main exe' ($leaves -contains 'ExcelDiffEDR.GUI.exe')
    Check 'payload has both lang json' (($leaves -contains 'zh-CN.json') -and ($leaves -contains 'en-US.json'))
    Check 'payload has shell extension + SharpShell' (($leaves -contains 'ExcelDiff.ShellExtension.dll') -and ($leaves -contains 'SharpShell.dll'))
    Check 'payload free of pdb (E7)' (@($leaves | Where-Object { $_ -like '*.pdb' }).Count -eq 0)
    # The NPOI family came in as a transitive dependency of the retired EDN reader. Stale bin
    # directories survive rebuilds, so assert against the shipped bytes that none of them is
    # still being delivered.
    Check 'payload free of retired reader libraries (E7)' `
        (@($leaves | Where-Object { $_ -match '^(NPOI|ICSharpCode\.SharpZipLib|BouncyCastle)' }).Count -eq 0) `
        ('left=' + (($leaves | Where-Object { $_ -match '^(NPOI|ICSharpCode|BouncyCastle)' }) -join ','))
    Check 'payload free of srm.exe (E7)' ($leaves -notcontains 'srm.exe')

    # E8 against the shipped bytes, not against a possibly stale obj\stage.
    $mainEntry = $archive.Entries | Where-Object { $_.Name -eq 'ExcelDiffEDR.GUI.exe' } | Select-Object -First 1
    $stagedMain = Join-Path $env:TEMP ('gate-main-' + [Guid]::NewGuid().ToString('N') + '.exe')
    $extract = [System.IO.Compression.ZipFileExtensions]::ExtractToFile($mainEntry, $stagedMain, $true)
    $entry = $mainEntry
}
finally {
    $archive.Dispose()
}

$payloadVersion = $null
if (Test-Path $stagedMain) {
    $payloadVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($stagedMain).FileVersion
    Remove-Item -LiteralPath $stagedMain -Force -ErrorAction SilentlyContinue
}
Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue

$setupVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($SetupExe).FileVersion
Check 'setup version matches payload main exe (E8)' ($payloadVersion -eq $setupVersion) ("setup=$setupVersion payload=$payloadVersion")

$zhKeys = KeySet (Join-Path $StringsDir 'zh-CN.txt')
$enKeys = KeySet (Join-Path $StringsDir 'en-US.txt')
$missingZh = @($enKeys | Where-Object { $zhKeys -notcontains $_ })
$missingEn = @($zhKeys | Where-Object { $enKeys -notcontains $_ })
Check 'string tables in sync' ($missingZh.Count -eq 0 -and $missingEn.Count -eq 0) `
    ('only-en=' + ($missingZh -join ',') + ' only-zh=' + ($missingEn -join ','))

# Key sets matching is not enough: a {0} that drifts between the two languages throws at runtime.
function Placeholders([string]$path) {
    $map = @{}
    foreach ($line in (Get-Content -LiteralPath $path -Encoding UTF8)) {
        if ($line -notmatch '^([^#=]+)=(.*)$') { continue }
        $map[$Matches[1].Trim()] = @([regex]::Matches($Matches[2], '\{\d+\}') | ForEach-Object { $_.Value } | Sort-Object)
    }
    return $map
}
$zhPh = Placeholders (Join-Path $StringsDir 'zh-CN.txt')
$enPh = Placeholders (Join-Path $StringsDir 'en-US.txt')
$drift = @($zhPh.Keys | Where-Object { -not $enPh.ContainsKey($_) -or (($zhPh[$_] -join ',') -ne ($enPh[$_] -join ',')) })
Check 'placeholder sets match per key across languages' ($drift.Count -eq 0) ('drift=' + ($drift -join ','))

# A green run against a stale binary proves nothing about the sources on disk.
# -Include is ignored with -LiteralPath (measured: it returned pdb/exe/obj files), so filter by hand.
$newestSource = (Get-ChildItem -LiteralPath (Join-Path $root 'ExcelDiff.Installer') -Recurse -File |
    Where-Object { $_.Extension -in '.cs', '.xaml', '.txt', '.csproj', '.manifest' -and $_.FullName -notmatch '\\bin\\|\\obj\\|\\Release\\' } |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1)
Check 'setup exe is newer than installer sources' ((Get-Item -LiteralPath $SetupExe).LastWriteTime -gt $newestSource.LastWriteTime) `
    ($newestSource.FullName.Substring($root.Length + 1) + ' ' + $newestSource.LastWriteTime + ' vs exe ' + (Get-Item -LiteralPath $SetupExe).LastWriteTime)

if (-not $Install) {
    Write-Host ''
    Write-Host '--- static checks only (pass -Install for the live cases) ---'
    Write-Host ''
    '{0} checks, {1} failed, {2} skipped' -f ($script:passed + $script:failed), $script:failed, $script:skipped
    if ($script:failed -eq 0) { 'RESULT: ALL PASS'; exit 0 }
    'RESULT: FAILURES'; exit 1
}

# ---------------------------------------------------------------- live cases

function RunSetup([string[]]$argList) {
    # Pinned working directory: case K asserts a relative /dir does not create <root>\Tools, which
    # is only a meaningful claim while the caller's working directory is the repository root.
    return RunExe $SetupExe $argList $root
}

# RunSetup with an explicit image: the in-folder Uninstall.exe and the command string stored in the
# registry both have to be exercised as the user would run them, not as $SetupExe.
# $workingDirectory is load-bearing, not cosmetic: Explorer double-clicks with the working directory
# set to the folder holding the exe, and a live process's own current directory cannot be deleted.
# Launching from anywhere else hides that failure mode (measured: every file gone, folder left).
function RunExe([string]$exe, [string[]]$argList, [string]$workingDirectory) {
    $quoted = @($argList | ForEach-Object { if ($_.Contains(' ')) { '"' + $_ + '"' } else { $_ } })
    if ($workingDirectory) {
        $p = Start-Process -FilePath $exe -ArgumentList $quoted -WorkingDirectory $workingDirectory -PassThru
    } else {
        $p = Start-Process -FilePath $exe -ArgumentList $quoted -PassThru
    }
    # A wizard or modal left on screen would otherwise block the gate forever; a timeout turns that
    # into a failure that names the command line that produced it.
    if (-not $p.WaitForExit(180000)) {
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        Check ('setup hung: ' + ($argList -join ' ')) $false 'no exit within 180s - a dialog is blocking it'
        return -99
    }
    return $p.ExitCode
}

# Executes an ARP uninstall string exactly as Control Panel / Settings would.
function RunCommandString([string]$command) {
    $exe = $command
    $rest = @()
    if ($command.StartsWith('"')) {
        $end = $command.IndexOf('"', 1)
        $exe = $command.Substring(1, $end - 1)
        $rest = @($command.Substring($end + 1).Trim() -split '\s+' | Where-Object { $_ })
    }
    else {
        $parts = @($command -split '\s+' | Where-Object { $_ })
        $exe = $parts[0]
        $rest = @($parts | Select-Object -Skip 1)
    }
    # Control Panel / Settings launch the stored string with the exe's own folder as the working
    # directory, so reproduce that - it is the shape that can lock the folder against deletion.
    return RunExe $exe $rest (Split-Path -Parent $exe)
}

# A handed-over uninstall finishes in its own time, so its outcome is polled, not assumed. Without
# this the assertion would race the child and a slow disk could turn a working uninstall red.
function WaitForGone([string]$path, [int]$seconds) {
    $until = (Get-Date).AddSeconds($seconds)
    while ((Get-Date) -lt $until) {
        if (-not (Test-Path -LiteralPath $path)) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return -not (Test-Path -LiteralPath $path)
}

function WaitForGoneKey([string]$path, [int]$seconds) {
    $until = (Get-Date).AddSeconds($seconds)
    while ((Get-Date) -lt $until) {
        if (-not (Test-Path $path)) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return -not (Test-Path $path)
}

# Case N needs to know a specific process ended, not merely that no name matches (another instance
# could start in the window).
function WaitForProcessGone([int]$processId, [int]$seconds) {
    $until = (Get-Date).AddSeconds($seconds)
    while ((Get-Date) -lt $until) {
        if (-not (Get-Process -Id $processId -ErrorAction SilentlyContinue)) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return -not (Get-Process -Id $processId -ErrorAction SilentlyContinue)
}

function ClsidCodeBase {
    if (-not (Test-Path $ClsidPath)) { return $null }
    $inproc = Join-Path $ClsidPath 'InprocServer32'
    if (Test-Path $inproc) {
        $cb = (Get-Item -LiteralPath $inproc).GetValue('CodeBase')
        if ($cb) { return $cb }
    }
    return (Get-Item -LiteralPath $ClsidPath).GetValue('CodeBase')
}

function Normalize-Uri([string]$value) {
    if (-not $value) { return '' }
    return [System.Uri]::UnescapeDataString([string]$value).Replace('file:///', '').Replace('/', '\')
}

# Refuse to run where the gate would damage a live developer setup.
$foreignCodeBase = Normalize-Uri (ClsidCodeBase)
if ($foreignCodeBase) {
    Check 'gate can run (no foreign COM registration)' $false "CLSID already points at $foreignCodeBase - unregister it first, the gate would remove it"
    Write-Host ''; Write-Host 'RESULT: REFUSED'; exit 2
}
if (Test-Path $ProductRegPath) {
    $recorded = (Get-Item -LiteralPath $ProductRegPath).GetValue('InstallFolder')
    Check 'gate can run (no existing install)' $false "HKLM already records an install at $recorded - uninstall it first"
    Write-Host ''; Write-Host 'RESULT: REFUSED'; exit 2
}

$work = Join-Path $env:TEMP ('ExcelDiffSetupGate-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $work -Force | Out-Null

$runBefore = (Get-Item -LiteralPath $RunKey).GetValue($RunValue)
$liveAppData = Join-Path $env:APPDATA 'ExcelDiffEDR.GUI'
$configBackupPath = Join-Path $work 'appdata-backup'
$appDataBefore = Hash-Dir $liveAppData
if ($appDataBefore -ne 'absent') {
    Copy-Item -LiteralPath $liveAppData -Destination $configBackupPath -Recurse -Force
}
$desktopLnk = Join-Path ([Environment]::GetFolderPath('CommonDesktopDirectory')) 'ExcelDiffEDR.lnk'

try {
    # ---- A: full install, then clean uninstall
    '== A: install with every component, then uninstall =='
    $dirA = Join-Path $work 'A\ExcelDiffEDRTool'
    $code = RunSetup @('/silent', ('/dir=' + $dirA), '/culture=zh-CN', '/components:shell,desktop,autostart')
    Check 'A install exit 0' ($code -eq 0) ('exit=' + $code)
    Check 'A main exe installed' (Test-Path (Join-Path $dirA 'ExcelDiffEDR.GUI.exe'))
    Check 'A uninstaller artifact copied' (Test-Path (Join-Path $dirA $UninstallerName)) ('name=' + $UninstallerName)
    Check 'A no setup-named copy left in the folder' (-not (Test-Path (Join-Path $dirA 'ExcelDiffSetup.exe')))
    Check 'A manifest written' (Test-Path (Join-Path $dirA 'install-manifest.txt'))
    $prod = Get-Item -LiteralPath $ProductRegPath -ErrorAction SilentlyContinue
    Check 'A HKLM product key present' ($null -ne $prod)
    if ($prod) {
        CheckKey 'A InstallFolder recorded' $prod.GetValue('InstallFolder') ((Resolve-Path $dirA).Path + '\')
        CheckKey 'A SetupCulture recorded' $prod.GetValue('SetupCulture') 'zh-CN'
        CheckKey 'A ShellExtRegistered' $prod.GetValue('ShellExtRegistered') '1'
        CheckKey 'A SetupStartOnBoot' $prod.GetValue('SetupStartOnBoot') '1'
    }
    $arp = Get-Item -LiteralPath $ArpRegPath -ErrorAction SilentlyContinue
    Check 'A ARP entry present' ($null -ne $arp)
    if ($arp) {
        CheckKey 'A ARP DisplayName' $arp.GetValue('DisplayName') 'ExcelDiffEDR'
        # Control Panel gets the wizard (it must confirm, and only its checkbox can clear settings);
        # the silent form stays available for scripts. Same target, different switches.
        $unstr = [string]$arp.GetValue('UninstallString')
        $qstr = [string]$arp.GetValue('QuietUninstallString')
        Check 'A ARP UninstallString targets the artifact' ($unstr.Contains('"' + (Join-Path $dirA $UninstallerName) + '"') -and $unstr -match '/uninstall') ('string=' + $unstr)
        Check 'A ARP UninstallString is interactive' (-not ($unstr -match '/silent')) ('string=' + $unstr)
        Check 'A ARP QuietUninstallString is silent' ($qstr -match '/uninstall' -and $qstr -match '/silent') ('string=' + $qstr)
        Check 'A ARP blocks modify/repair' ($arp.GetValue('NoModify') -eq 1 -and $arp.GetValue('NoRepair') -eq 1)
        Check 'A ARP EstimatedSize > 0' ($arp.GetValue('EstimatedSize') -gt 0) ('KB=' + $arp.GetValue('EstimatedSize'))
    }
    $codeBase = Normalize-Uri (ClsidCodeBase)
    Check 'A COM registered for THIS folder' ($codeBase.StartsWith($dirA)) ('codebase=' + $codeBase)
    Check 'A start-menu shortcut present' (Test-Path (Join-Path $StartMenuDir 'ExcelDiffEDR.lnk'))
    Check 'A desktop shortcut present' (Test-Path $desktopLnk)
    $runAfterInstall = (Get-Item -LiteralPath $RunKey).GetValue($RunValue)
    Check 'A auto-start Run value points here' ($runAfterInstall -like ('"' + $dirA + '\ExcelDiffEDR.GUI.exe" --startup')) ('value=' + $runAfterInstall)

    $code = RunSetup @('/uninstall', '/silent', ('/dir=' + $dirA))
    Check 'A uninstall exit 0' ($code -eq 0) ('exit=' + $code)
    Check 'A install folder removed' (-not (Test-Path $dirA))
    Check 'A start-menu folder removed' (-not (Test-Path $StartMenuDir))
    Check 'A HKLM product key removed' (-not (Test-Path $ProductRegPath))
    Check 'A ARP entry removed' (-not (Test-Path $ArpRegPath))
    Check 'A COM unregistered' (-not (ClsidCodeBase))
    Check 'A auto-start Run value removed' (-not (Get-Item -LiteralPath $RunKey).GetValue($RunValue))
    Remove-Item -LiteralPath $desktopLnk -Force -ErrorAction SilentlyContinue

    # ---- B: pre-existing non-empty folder + forced failure must not eat unrelated files
    '== B: failure inside a pre-existing folder must spare the other files =='
    $dirB = Join-Path $work 'B\keepme'
    New-Item -ItemType Directory -Path $dirB -Force | Out-Null
    $decoy = Join-Path $dirB 'do-not-delete.txt'
    Set-Content -LiteralPath $decoy -Value 'pre-existing user file'
    # Lock a payload target so extraction fails after the folder already existed.
    $blocked = Join-Path $dirB 'ExcelDiff.dll'
    $handle = [System.IO.File]::Open($blocked, [System.IO.FileMode]::CreateNew,
        [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    try {
        $code = RunSetup @('/silent', ('/dir=' + $dirB), '/components:none')
        # Exact code, not "-ne 0": a 180s timeout also returns non-zero (-99) and would otherwise be
        # scored as "the install failed as expected".
        Check 'B install fails with 1' ($code -eq 1) ('exit=' + $code)
    }
    finally {
        $handle.Dispose()
        Remove-Item -LiteralPath $blocked -Force -ErrorAction SilentlyContinue
    }
    Check 'B unrelated file survived' (Test-Path $decoy)
    Check 'B folder survived (was not ours to create)' (Test-Path $dirB)
    Check 'B no registry left behind' (-not (Test-Path $ProductRegPath))
    Check 'B no ARP left behind' (-not (Test-Path $ArpRegPath))

    # ---- C: uninstall with no /dir and no record must fail, not guess
    '== C: uninstall without a target must refuse =='
    $defaultDir = Join-Path $env:ProgramFiles $EdrInstallDirName
    $code = RunSetup @('/uninstall', '/silent')
    Check 'C uninstall without target fails with 1' ($code -eq 1) ('exit=' + $code)
    Check 'C default folder untouched' (-not (Test-Path $defaultDir))

    # A wrong path must not be allowed to clear the record of the real install. This reproduces a
    # build where an unmatched /dir deleted nothing yet still wiped HKLM and returned 0.
    $dirC = Join-Path $work 'C\ExcelDiffEDRTool'
    $null = RunSetup @('/silent', ('/dir=' + $dirC), '/components:none')
    $wrong = Join-Path $work 'C\Typo'
    $code = RunSetup @('/uninstall', '/silent', ('/dir=' + $wrong))
    Check 'C wrong-path uninstall fails with 1' ($code -eq 1) ('exit=' + $code)
    $prod = Get-Item -LiteralPath $ProductRegPath -ErrorAction SilentlyContinue
    Check 'C real install record survives' ($null -ne $prod -and $prod.GetValue('InstallFolder') -eq ((Resolve-Path $dirC).Path + '\'))
    Check 'C real install files survive' (Test-Path (Join-Path $dirC 'ExcelDiffEDR.GUI.exe'))
    $null = RunSetup @('/uninstall', '/silent', ('/dir=' + $dirC))
    Check 'C correct uninstall then succeeds' (-not (Test-Path $dirC))

    # ---- D: run the artifact from inside the installed folder (the ARP shape)
    '== D: artifact launched from inside the install folder =='
    $dirD = Join-Path $work 'D\ExcelDiffEDRTool'
    $code = RunSetup @('/silent', ('/dir=' + $dirD), '/components:none')
    Check 'D baseline install exit 0' ($code -eq 0) ('exit=' + $code)
    $inner = Join-Path $dirD $UninstallerName
    Check 'D in-folder artifact exists' (Test-Path $inner)
    $beforeWrite = (Get-Item -LiteralPath (Join-Path $dirD 'ExcelDiffEDR.GUI.exe')).LastWriteTimeUtc
    $relayBefore = @(Get-ChildItem -LiteralPath $env:TEMP -Filter '*.relay.log' -File -ErrorAction SilentlyContinue).Name
    # /install is what keeps a reinstall possible now that the folder artifact uninstalls by default.
    $code = RunExe $inner @('/install', '/silent', ('/dir=' + $dirD), '/components:none') $dirD
    Check 'D explicit /install reinstall succeeds' ($code -eq 0) ('exit=' + $code)
    Check 'D main exe still there' (Test-Path (Join-Path $dirD 'ExcelDiffEDR.GUI.exe'))
    # Without this the case would also pass when the relaunch silently did nothing.
    Check 'D payload actually rewritten' ((Get-Item -LiteralPath (Join-Path $dirD 'ExcelDiffEDR.GUI.exe')).LastWriteTimeUtc -gt $beforeWrite)
    # Only the %TEMP% relay ever creates a *.relay.log, so a new one is proof the child ran from
    # outside the folder instead of installing over the image it was launched from.
    $relayNew = @(Get-ChildItem -LiteralPath $env:TEMP -Filter '*.relay.log' -File -ErrorAction SilentlyContinue).Name |
        Where-Object { $relayBefore -notcontains $_ }
    Check 'D went through the %TEMP% relay' (@($relayNew).Count -gt 0) ('new=' + ($relayNew -join ','))
    # The old image is still loaded by the process we launched from inside the folder, so its parked
    # backup cannot be deleted yet; it must be swept by the next uninstall instead. Exactly one: zero
    # would mean the folder was never moved aside, i.e. the relay did nothing.
    $stale = @(Get-ChildItem -LiteralPath (Split-Path -Parent $dirD) -Directory -Filter '*.old-*' -ErrorAction SilentlyContinue)
    Check 'D one parked backup' ($stale.Count -eq 1) ('found=' + ($stale.Name -join ','))
    $null = RunSetup @('/uninstall', '/silent', ('/dir=' + $dirD))
    Check 'D uninstall swept the backup' (@(Get-ChildItem -LiteralPath (Split-Path -Parent $dirD) -Directory -Filter '*.old-*' -ErrorAction SilentlyContinue).Count -eq 0)
    Check 'D folder gone' (-not (Test-Path $dirD))

    # ---- E: reinstall over an existing install reuses the folder
    '== E: reinstall reuses the folder =='
    $dirE = Join-Path $work 'E\ExcelDiffEDRTool'
    $code = RunSetup @('/silent', ('/dir=' + $dirE), '/culture=en-US', '/components:shell')
    Check 'E first install exit 0' ($code -eq 0) ('exit=' + $code)
    $eBefore = (Get-Item -LiteralPath (Join-Path $dirE 'ExcelDiffEDR.GUI.exe')).LastWriteTimeUtc
    $code = RunSetup @('/silent', ('/dir=' + $dirE), '/culture=en-US', '/components:shell')
    # Discarding this exit code made the whole case pass on a failed reinstall: rollback puts the old
    # folder and the old HKLM record back, so "still installed" and "folder still remembered" were
    # both true without the second install ever completing. The timestamp pin proves it ran.
    Check 'E reinstall exit 0' ($code -eq 0) ('exit=' + $code)
    Check 'E reinstalled into the same folder' (Test-Path (Join-Path $dirE 'ExcelDiffEDR.GUI.exe'))
    Check 'E reinstall actually rewrote the files' `
        ((Get-Item -LiteralPath (Join-Path $dirE 'ExcelDiffEDR.GUI.exe')).LastWriteTimeUtc -gt $eBefore) `
        ('before=' + $eBefore)
    $prod = Get-Item -LiteralPath $ProductRegPath -ErrorAction SilentlyContinue
    CheckKey 'E folder still remembered' $prod.GetValue('InstallFolder') ((Resolve-Path $dirE).Path + '\')
    CheckKey 'E culture seed is en-US' $prod.GetValue('SetupCulture') 'en-US'
    Check 'E no .old-* leftovers' (@(Get-ChildItem -LiteralPath (Split-Path -Parent $dirE) -Directory -Filter '*.old-*' -ErrorAction SilentlyContinue).Count -eq 0)
    $null = RunSetup @('/uninstall', '/silent', ('/dir=' + $dirE))

    # ---- F: auto-start off must not steal another folder's Run value
    '== F: auto-start off leaves a foreign Run value alone =='
    $foreign = '"' + (Join-Path $work 'F\other\ExcelDiffEDR.GUI.exe') + '" --startup'
    Set-ItemProperty -LiteralPath $RunKey -Name $RunValue -Value $foreign
    $dirF = Join-Path $work 'F\ExcelDiffEDRTool'
    $code = RunSetup @('/silent', ('/dir=' + $dirF), '/components:none')
    Check 'F install exit 0' ($code -eq 0) ('exit=' + $code)
    CheckKey 'F foreign Run value preserved' (Get-Item -LiteralPath $RunKey).GetValue($RunValue) $foreign
    $null = RunSetup @('/uninstall', '/silent', ('/dir=' + $dirF))
    CheckKey 'F uninstall left the foreign Run value alone' (Get-Item -LiteralPath $RunKey).GetValue($RunValue) $foreign

    # ---- G: the shared user settings folder is cleared only on explicit request
    '== G: /clearsettings governs the user settings folder =='
    $dirG = Join-Path $work 'G\ExcelDiffEDRTool'
    New-Item -ItemType Directory -Path $liveAppData -Force | Out-Null
    $marker = Join-Path $liveAppData 'gate-marker.txt'
    Set-Content -LiteralPath $marker -Value 'gate marker'
    $code = RunSetup @('/silent', ('/dir=' + $dirG), '/components:none')
    Check 'G first install exit 0' ($code -eq 0) ('exit=' + $code)
    $code = RunSetup @('/uninstall', '/silent', ('/dir=' + $dirG))
    Check 'G default uninstall exit 0' ($code -eq 0) ('exit=' + $code)
    Check 'G default uninstall keeps user settings' (Test-Path $marker)
    $code = RunSetup @('/silent', ('/dir=' + $dirG), '/components:none')
    Check 'G second install exit 0' ($code -eq 0) ('exit=' + $code)
    $code = RunSetup @('/uninstall', '/silent', '/clearsettings', ('/dir=' + $dirG))
    Check 'G /clearsettings uninstall exit 0' ($code -eq 0) ('exit=' + $code)
    Check 'G /clearsettings removes user settings' (-not (Test-Path $marker))

    # Repair at the point of damage, not only at the end. /clearsettings really does delete the live
    # settings folder, and a later case that starts the product would recreate it with factory
    # defaults - the end-of-run restore could then no longer tell "the user's own settings" from
    # "defaults written by the gate", and one run did lose them that way.
    if ((Test-Path $configBackupPath) -and ((Hash-Dir $liveAppData) -ne $appDataBefore)) {
        Remove-Item -LiteralPath $liveAppData -Recurse -Force -ErrorAction SilentlyContinue
        Copy-Item -LiteralPath $configBackupPath -Destination $liveAppData -Recurse -Force
    }
    Check 'G puts the live settings back after /clearsettings' ((Hash-Dir $liveAppData) -eq $appDataBefore) `
        ('before=' + $appDataBefore + ' now=' + (Hash-Dir $liveAppData))

    # ---- H: malformed switches must refuse, not fall through to the UI
    '== H: bad command lines are refused =='
    $code = RunSetup @('/silent=1', '/culture=de-DE', ('/dir=' + (Join-Path $work 'H\ExcelDiffEDRTool')))
    CheckKey 'H bad switches exit 4' $code 4
    Check 'H installed nothing' (-not (Test-Path (Join-Path $work 'H\ExcelDiffEDRTool')))
    Check 'H left no registry record' (-not (Test-Path $ProductRegPath))
    $code = RunSetup @('/dir=')
    CheckKey 'H empty /dir is refused too' $code 4

    # ---- I: an interactive /uninstall /clearsettings must not drop the request on the floor
    '== I: switch validation stays out of the way of valid command lines =='
    $dirI = Join-Path $work 'I\ExcelDiffEDRTool'
    $code = RunSetup @('/silent', ('/dir=' + $dirI), '/culture=en-US', '/components=all')
    Check 'I well-formed command line accepted' ($code -eq 0) ('exit=' + $code)
    $code = RunSetup @('/uninstall', '/silent', ('/dir=' + $dirI))
    Check 'I uninstall exit 0' ($code -eq 0) ('exit=' + $code)

    # ---- J: no manifest means nothing to replay, so the uninstall must refuse
    '== J: uninstall refuses when the install manifest is gone =='
    $dirJ = Join-Path $work 'J\ExcelDiffEDRTool'
    $code = RunSetup @('/silent', ('/dir=' + $dirJ), '/components:none')
    Check 'J install exit 0' ($code -eq 0) ('exit=' + $code)
    $manifest = Join-Path $dirJ 'install-manifest.txt'
    $manifestBackup = Join-Path $work 'J-manifest-backup.txt'
    Copy-Item -LiteralPath $manifest -Destination $manifestBackup -Force
    Remove-Item -LiteralPath $manifest -Force
    $code = RunSetup @('/uninstall', '/silent', ('/dir=' + $dirJ))
    CheckKey 'J uninstall without manifest fails' $code 1
    Check 'J files survived the refusal' (Test-Path (Join-Path $dirJ 'ExcelDiffEDR.GUI.exe'))
    Check 'J HKLM record survived the refusal' (Test-Path $ProductRegPath)
    # Positive control: put the manifest back and the very same uninstall completes. Without this,
    # the failure above could also mean "nothing was ever installed here".
    Copy-Item -LiteralPath $manifestBackup -Destination $manifest -Force
    $code = RunSetup @('/uninstall', '/silent', ('/dir=' + $dirJ))
    CheckKey 'J uninstall succeeds once the manifest is back' $code 0
    Check 'J folder gone after the restored uninstall' (-not (Test-Path $dirJ))

    # ---- K: bad target shapes are argument errors, refused before anything runs
    '== K: drive-root and relative install targets are refused =='
    # Q: does not exist on this machine, so a regression cannot turn into files written somewhere
    # real. The relative forms must fail as argument errors (4), not resolve against the process's
    # working directory and install there - hence the folder check under $root as well.
    $code = RunSetup @('/silent', '/dir=Q:\')
    CheckKey 'K drive root refused with exit 4' $code 4
    Check 'K left no registry record' (-not (Test-Path $ProductRegPath))
    $code = RunSetup @('/silent', '/dir=Q:')
    CheckKey 'K bare drive letter refused too' $code 4
    $code = RunSetup @('/silent', '/dir=Tools')
    CheckKey 'K relative target refused' $code 4
    Check 'K relative target created no folder' (-not (Test-Path (Join-Path $root 'Tools')))
    # A UNC share root is the other shape Path.GetFullPath leaves without a trailing separator, so
    # only the "root == full" half of ValidateTargetDir rejects it. It gets its own case because that
    # half looks redundant beside the first one and is easy to delete as "dead code". server\share
    # does not exist here, so the pair below cannot write anywhere real: the accepted form fails later
    # when the folder cannot be created (exit 1, before any registry write), not as a bad argument.
    $code = RunSetup @('/silent', '/dir=\\server\share')
    CheckKey 'K UNC share root refused with exit 4' $code 4
    $code = RunSetup @('/silent', '/dir=\\server\share\ExcelDiffEDRTool')
    Check 'K UNC path under a share is not refused as a bad shape' ($code -ne 4) ('exit=' + $code) 0
    $code = RunSetup @('/silent', '/uninstall', '/dir=Tools')
    CheckKey 'K relative target refused on uninstall too' $code 4

    # ---- L: the in-folder artifact uninstalls on its name alone (double-click shape)
    '== L: in-folder Uninstall.exe uninstalls without /uninstall =='
    $dirL = Join-Path $work 'L\ExcelDiffEDRTool'
    $code = RunSetup @('/silent', ('/dir=' + $dirL), '/components:none')
    Check 'L install exit 0' ($code -eq 0) ('exit=' + $code)
    # Everything below polls for absence, which is trivially true when it was never there: pin the
    # effects of the install first so the polls measure a uninstall and not a no-op.
    Check 'L folder, ARP and product key present before the uninstall' `
        ((Test-Path $dirL) -and (Test-Path $ArpRegPath) -and (Test-Path $ProductRegPath)) `
        ('dir=' + (Test-Path $dirL) + ' arp=' + (Test-Path $ArpRegPath) + ' hklm=' + (Test-Path $ProductRegPath))
    # No /uninstall anywhere: the role comes from the file name, and it has to survive the %TEMP%
    # relay (which renames the image to ExcelDiffSetup-<guid>.exe). Without the synthesis the child
    # resolves to the install role and the folder would still be there when we stop waiting.
    # Uninstall from inside the folder is a handover, so the exit code only says "delegated":
    # assert the effects, exactly like the user reads them off Control Panel.
    # Working directory = the install folder, exactly like an Explorer double-click.
    $code = RunExe (Join-Path $dirL $UninstallerName) @('/silent') $dirL
    CheckKey 'L handover exits delegated (100)' $code 100
    Check 'L folder removed' (WaitForGone $dirL 90) $(if (Test-Path $dirL) { 'still there after 90s' } else { '' })
    Check 'L ARP entry removed' (WaitForGoneKey $ArpRegPath 30) $(if (Test-Path $ArpRegPath) { 'still registered after 30s' } else { '' })
    Check 'L product key removed' (WaitForGoneKey $ProductRegPath 30) $(if (Test-Path $ProductRegPath) { 'still registered after 30s' } else { '' })

    # ---- M: run the command string the registry actually holds
    '== M: ARP QuietUninstallString performs the uninstall =='
    $dirM = Join-Path $work 'M\ExcelDiffEDRTool'
    $code = RunSetup @('/silent', ('/dir=' + $dirM), '/components:none')
    Check 'M install exit 0' ($code -eq 0) ('exit=' + $code)
    $arp = Get-Item -LiteralPath $ArpRegPath -ErrorAction SilentlyContinue
    $qstr = if ($arp) { [string]$arp.GetValue('QuietUninstallString') } else { '' }
    Check 'M ARP quiet string is present' ($qstr.Length -gt 0) ('string=' + $qstr)
    # This is the only coverage of ResolveUninstallDir() reading the recorded folder: the ARP string
    # carries no /dir, exactly like the Control Panel click.
    Check 'M ARP quiet string carries no /dir' (-not ($qstr -match '/dir')) ('string=' + $qstr)
    Check 'M folder, key and start menu present before the uninstall' `
        ((Test-Path $dirM) -and (Test-Path $ProductRegPath) -and (Test-Path $StartMenuDir)) `
        ('dir=' + (Test-Path $dirM) + ' hklm=' + (Test-Path $ProductRegPath) + ' start=' + (Test-Path $StartMenuDir))
    $code = RunCommandString $qstr
    CheckKey 'M uninstall via ARP string hands over (100)' $code 100
    Check 'M folder gone' (WaitForGone $dirM 90) $(if (Test-Path $dirM) { 'still there after 90s' } else { '' })
    Check 'M ARP entry removed' (WaitForGoneKey $ArpRegPath 30) $(if (Test-Path $ArpRegPath) { 'still registered after 30s' } else { '' })
    Check 'M product key removed' (WaitForGoneKey $ProductRegPath 30) $(if (Test-Path $ProductRegPath) { 'still registered after 30s' } else { '' })
    Check 'M start-menu folder removed' (WaitForGone $StartMenuDir 30) $(if (Test-Path $StartMenuDir) { 'still there after 30s' } else { '' })

    # ---- N: uninstall while the product is running from that very folder
    '== N: the uninstaller ends the running product before it deletes =='
    $dirN = Join-Path $work 'N\ExcelDiffEDRTool'
    # G repairs the folder its own /clearsettings deleted, so the product started here is running
    # against the user's real settings, not a factory-first-run state. If that ever stops being true
    # this precondition says so instead of quietly testing a different shape.
    Check 'N settings folder is present before the launch' (Test-Path $liveAppData) 'absent'
    # zh-CN + no autostart keeps the recorded seed identical to the live settings' own signature, so
    # this case cannot re-seed the user's language or auto-start choice.
    $code = RunSetup @('/silent', ('/dir=' + $dirN), '/culture=zh-CN', '/components:none')
    Check 'N install exit 0' ($code -eq 0) ('exit=' + $code)
    # The product is single-instance and the mutex name comes from the exe name, so a copy started
    # while another resident is alive forwards its arguments and exits - the case would silently test
    # "nothing was running". Any resident outside this folder has to go first, and that is a machine
    # side effect worth naming: redeploy the dev build after the gate.
    $strays = @(Get-Process -Name 'ExcelDiffEDR.GUI' -ErrorAction SilentlyContinue)
    if ($strays.Count -gt 0) {
        Write-Host ('  note: ending ' + $strays.Count + ' running ExcelDiffEDR so N can start its own (redeploy afterwards)')
        $strays | ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
        Start-Sleep -Seconds 2
    }
    Check 'N no ExcelDiffEDR running before the launch' `
        (@(Get-Process -Name 'ExcelDiffEDR.GUI' -ErrorAction SilentlyContinue).Count -eq 0) 'a resident survived'
    $app = Start-Process -FilePath (Join-Path $dirN 'ExcelDiffEDR.GUI.exe') -WorkingDirectory $dirN -PassThru
    $running = $false
    $untilN = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $untilN) {
        $probe = Get-Process -Name 'ExcelDiffEDR.GUI' -ErrorAction SilentlyContinue
        $running = @($probe | Where-Object { $_.Path -and $_.Path.StartsWith($dirN, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
        if ($running) { break }
        Start-Sleep -Milliseconds 500
    }
    Check 'N product is running from the target folder' $running ('pid=' + $app.Id)
    $code = RunSetup @('/uninstall', '/silent', ('/dir=' + $dirN))
    CheckKey 'N uninstall exit 0 with the product running' $code 0
    Check 'N the running process ended' (WaitForProcessGone $app.Id 30) ('pid=' + $app.Id + ' still alive')
    # The folder can only go if the image was released first: deleting or moving a running exe fails,
    # so "folder gone" is the proof of the ordering, not a separate lucky outcome.
    Check 'N folder removed' (WaitForGone $dirN 90) $(if (Test-Path $dirN) { 'still there after 90s' } else { '' })
    Check 'N product key removed' (WaitForGoneKey $ProductRegPath 30) $(if (Test-Path $ProductRegPath) { 'still registered after 30s' } else { '' })

    # ---- O: a folder that is not the recorded install must be refused, and the real install spared
    '== O: ownership is decided before anything is deleted =='
    $dirO1 = Join-Path $work 'O\real\ExcelDiffEDRTool'
    $dirO2 = Join-Path $work 'O\copy\ExcelDiffEDRTool'
    $code = RunSetup @('/silent', ('/dir=' + $dirO1), '/components:none')
    Check 'O install exit 0' ($code -eq 0) ('exit=' + $code)
    # A copied install folder: its manifest holds the original absolute paths, which is exactly the
    # shape that used to eat the *other* install's files and still report success.
    Copy-Item -LiteralPath $dirO1 -Destination $dirO2 -Recurse -Force
    Check 'O copy made' (Test-Path (Join-Path $dirO2 'install-manifest.txt')) $dirO2
    $code = RunSetup @('/uninstall', '/silent', ('/dir=' + $dirO2))
    CheckKey 'O uninstalling a copy is refused' $code 1
    Check 'O the copy survived the refusal' (Test-Path (Join-Path $dirO2 'ExcelDiffEDR.GUI.exe')) 'gone'
    Check 'O the recorded install survived the refusal' (Test-Path (Join-Path $dirO1 'ExcelDiffEDR.GUI.exe')) 'gone'
    $recordedO = (Get-Item -LiteralPath $ProductRegPath).GetValue('InstallFolder')
    Check 'O the record still points at the real install' ($recordedO -eq ($dirO1 + '\')) ('got=' + $recordedO)
    # Now make the record agree with the copy while its manifest still lists the real install: that is
    # the only way to reach the manifest half of the ownership test, so it is forced here.
    Set-ItemProperty -LiteralPath $ProductRegPath -Name 'InstallFolder' -Value $dirO2
    $code = RunSetup @('/uninstall', '/silent', ('/dir=' + $dirO2))
    CheckKey 'O manifest pointing outside the target is refused' $code 1
    Check 'O the copy survived the manifest refusal' (Test-Path (Join-Path $dirO2 'ExcelDiffEDR.GUI.exe')) 'gone'
    Check 'O the recorded install survived the manifest refusal' (Test-Path (Join-Path $dirO1 'ExcelDiffEDR.GUI.exe')) 'gone'
    # Positive control: with the record back on the real folder, the same command line uninstalls it.
    Set-ItemProperty -LiteralPath $ProductRegPath -Name 'InstallFolder' -Value $dirO1
    $code = RunSetup @('/uninstall', '/silent', ('/dir=' + $dirO1))
    CheckKey 'O uninstalling the real install succeeds' $code 0
    Check 'O real folder gone' (WaitForGone $dirO1.TrimEnd('\') 60) $(if (Test-Path $dirO1) { 'still there' } else { '' })
    Remove-Item -LiteralPath (Split-Path -Parent $dirO2) -Recurse -Force -ErrorAction SilentlyContinue
}
finally {
    # Repairs happen after every assertion above, so they cannot mask a product bug.
    $leftover = @(Get-ChildItem -LiteralPath $env:ProgramData -Filter 'ExcelDiff*.lnk' -Recurse -ErrorAction SilentlyContinue)
    Check 'no stray shortcuts' ($leftover.Count -eq 0) ($leftover.FullName -join ', ')
    Remove-Item -LiteralPath $desktopLnk -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path ([Environment]::GetFolderPath('CommonDesktopDirectory')) 'ExcelDiff.lnk') -Force -ErrorAction SilentlyContinue
    if ($runBefore) { Set-ItemProperty -LiteralPath $RunKey -Name $RunValue -Value $runBefore }
    elseif ((Get-Item -LiteralPath $RunKey).GetValue($RunValue)) { (Get-Item -LiteralPath $RunKey).DeleteValue($RunValue) }
    if ($marker) { Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue }
    # Restore whenever the live state differs from what the gate found, not only when the folder went
    # missing: a case that legitimately lets the product create its settings (first run after G's
    # /clearsettings) would otherwise fail this check for a reason that is not a defect.
    if ((Test-Path $configBackupPath) -and ((Hash-Dir $liveAppData) -ne $appDataBefore)) {
        Write-Host '  note: gate restores the live settings folder from its snapshot'
        Remove-Item -LiteralPath $liveAppData -Recurse -Force -ErrorAction SilentlyContinue
        Copy-Item -LiteralPath $configBackupPath -Destination $liveAppData -Recurse -Force
    }
    elseif (-not (Test-Path $configBackupPath) -and (Test-Path $liveAppData) -and $appDataBefore -eq 'absent') {
        Remove-Item -LiteralPath $liveAppData -Recurse -Force -ErrorAction SilentlyContinue
    }
    Check 'live settings restored after the gate' ((Hash-Dir $liveAppData) -eq $appDataBefore) `
        ('before=' + $appDataBefore + ' now=' + (Hash-Dir $liveAppData))

    # A failed case can leave HKLM pointing into $work; the next run would then refuse at
    # pre-flight and be unable to recover, because the manifest dies with $work.
    if (Test-Path $ProductRegPath) {
        $stuck = (Get-Item -LiteralPath $ProductRegPath).GetValue('InstallFolder')
        if ($stuck) {
            $code = RunSetup @('/uninstall', '/silent', ('/dir=' + $stuck.TrimEnd('\')))
            Check 'gate uninstalled its own leftovers' ($code -eq 0) ('exit=' + $code + ' dir=' + $stuck)
        }
    }
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

''
'===== summary ====='
'{0} checks, {1} failed, {2} skipped' -f ($script:passed + $script:failed), $script:failed, $script:skipped
if ($script:failed -eq 0) { 'RESULT: ALL PASS'; exit 0 }
'RESULT: FAILURES'; exit 1
