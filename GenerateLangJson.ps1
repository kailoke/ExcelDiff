# GenerateLangJson.ps1
# Converts the .resx translation sources into external JSON language files under lang\.
# Usage:  powershell -ExecutionPolicy Bypass -File GenerateLangJson.ps1
$ErrorActionPreference = 'Stop'

$resxDir = Join-Path $PSScriptRoot 'ExcelDiff.GUI\Properties'
$outDir  = Join-Path $PSScriptRoot 'lang'
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

function Read-Resx([string]$path) {
    [xml]$xml = Get-Content -LiteralPath $path -Encoding UTF8
    $map = @{}
    foreach ($node in $xml.root.data) {
        if ($node.name) {
            $map[$node.name] = $node.value
        }
    }
    return $map
}

# Union of all keys so every language file contains the complete set.
# Only Chinese and English are supported (Japanese removed).
$sources = @(
    @{ Culture='en-US'; File='Resources.resx' },
    @{ Culture='zh-CN'; File='Resources.zh-CN.resx' }
)

$neutral = Read-Resx (Join-Path $resxDir 'Resources.resx')
$allKeys = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($s in $sources) {
    $m = Read-Resx (Join-Path $resxDir $s.File)
    foreach ($k in $m.Keys) { [void]$allKeys.Add($k) }
}
foreach ($k in $neutral.Keys) { [void]$allKeys.Add($k) }

foreach ($s in $sources) {
    $m = Read-Resx (Join-Path $resxDir $s.File)
    $ordered = [ordered]@{}
    foreach ($k in ($allKeys | Sort-Object)) {
        if ($m.ContainsKey($k)) { $ordered[$k] = $m[$k] }
        elseif ($neutral.ContainsKey($k)) { $ordered[$k] = $neutral[$k] }
        else { $ordered[$k] = '' }
    }
    $json = $ordered | ConvertTo-Json
    $outPath = Join-Path $outDir ($s.Culture + '.json')
    # ConvertTo-Json escapes non-ASCII as \uXXXX; write UTF-8 for readability anyway.
    [System.IO.File]::WriteAllText($outPath, $json, (New-Object System.Text.UTF8Encoding($true)))
    Write-Host "Wrote $outPath ($($ordered.Count) keys)"
}
