<#
.SYNOPSIS
    Mermaid 图渲染封装：调用本仓固定版本 @mermaid-js/mermaid-cli，把 .mmd（或 .md）渲染为 SVG/PNG/PDF。

.DESCRIPTION
    第三方工具 = 官方 @mermaid-js/mermaid-cli（固定 11.17.0），装在本脚本同级的 tools/mermaid/；
    package.json / package-lock.json 入库，node_modules 不入库。渲染引擎是 headless Chromium
    （puppeteer 下载到 %USERPROFILE%\.cache\puppeteer，同样不入仓）。
    本脚本只读输入、只写输出（默认与输入同目录同名 .svg），不改任何源文件。
    唯一事实源 = .agents/skills/diagram-mermaid/SKILL.md（用法/纪律/产物落点），本封装只负责调用。

    新机 / 新克隆先跑一次 -Install：npm install + 显式补跑 puppeteer 浏览器下载。
    （npm 11 的 allow-scripts 默认拦 puppeteer 的 postinstall，故不能只靠 npm install。）

.USAGE
    .\AI_Script\mermaid-render.ps1 -Install                 # 一次性：装依赖 + 下载 Chromium
    .\AI_Script\mermaid-render.ps1 <in.mmd>                 # 渲染为同目录同名 .svg
    .\AI_Script\mermaid-render.ps1 <in.mmd> -Output <out>   # 指定输出（扩展名决定格式：.svg/.png/.pdf）
    .\AI_Script\mermaid-render.ps1 <in.mmd> -Format png     # 未给 -Output 时按格式定扩展名
    .\AI_Script\mermaid-render.ps1 <in.mmd> -Theme dark -BackgroundColor transparent
    .\AI_Script\mermaid-render.ps1 <in.mmd> -Check          # 只校验语法：渲到临时文件后删除，不留产物

.EXITCODE
    0 = 成功；1 = 渲染/安装失败；2 = 参数或输入文件问题；3 = 工具未安装（提示先 -Install）。
#>

param(
    [Parameter(Position = 0)][string]$InputFile = '',
    [string]$Output = '',
    [ValidateSet('svg', 'png', 'pdf')][string]$Format = 'svg',
    [ValidateSet('default', 'neutral', 'dark', 'forest', 'base')][string]$Theme = 'default',
    [string]$BackgroundColor = '',
    [string]$PuppeteerConfigFile = '',
    [switch]$Install,
    [switch]$Check,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
. (Join-Path $PSScriptRoot 'lib\common.ps1')

$toolDir = Join-Path $PSScriptRoot 'tools\mermaid'
$pkgJson = Join-Path $toolDir 'package.json'
function Get-MmdcPath {
    if ($IsWindows -or $env:OS -eq 'Windows_NT' -or $PSVersionTable.PSVersion.Major -lt 6) {
        $c = Join-Path $toolDir 'node_modules\.bin\mmdc.cmd'
        if (Test-Path -LiteralPath $c) { return $c }
    }
    $p = Join-Path $toolDir 'node_modules\.bin\mmdc'
    if (Test-Path -LiteralPath $p) { return $p }
    return ''
}

function Invoke-Install {
    if (-not (Test-Path -LiteralPath $pkgJson)) { throw "tool manifest missing: $pkgJson" }
    Write-Host 'Installing pinned @mermaid-js/mermaid-cli ...'
    Push-Location $toolDir
    try {
        $instRes = Invoke-NativeCapture -FilePath 'npm' -Arguments @('install', '--no-audit', '--no-fund')
        foreach ($l in @($instRes.Lines)) { if ($l) { Write-Host $l } }
        if ($instRes.Error) { Write-Host $instRes.Error }
        if ($instRes.Failed) { throw 'npm install failed' }
        $pptrInstall = Join-Path $toolDir 'node_modules\puppeteer\install.mjs'
        if (Test-Path -LiteralPath $pptrInstall) {
            Write-Host 'Downloading Chromium (puppeteer postinstall is blocked by npm allow-scripts) ...'
            $pptrRes = Invoke-NativeCapture -FilePath 'node' -Arguments @($pptrInstall)
            foreach ($l in @($pptrRes.Lines)) { if ($l) { Write-Host $l } }
            if ($pptrRes.Error) { Write-Host $pptrRes.Error }
            if ($pptrRes.Failed) { throw 'puppeteer browser download failed' }
        }
    } finally { Pop-Location }
}

if ($Install) {
    Invoke-Install
    if (-not $InputFile) {
        Write-Host 'Install done. Usage: .\AI_Script\mermaid-render.ps1 <in.mmd> [-Output <out>]'
        exit 0
    }
}

$mmdc = Get-MmdcPath
if (-not $mmdc) {
    Write-Host "mermaid-cli not installed under $toolDir. Run: .\AI_Script\mermaid-render.ps1 -Install" -ForegroundColor Red
    exit 3
}

if (-not $InputFile) {
    Write-Host 'No input. Usage: .\AI_Script\mermaid-render.ps1 <in.mmd> [-Output <out>] [-Format svg|png|pdf]' -ForegroundColor Red
    exit 2
}
if (-not (Test-Path -LiteralPath $InputFile -PathType Leaf)) {
    Write-Host "Input not found: $InputFile" -ForegroundColor Red
    exit 2
}

$inItem = Get-Item -LiteralPath $InputFile
$target = $Output
$tempTarget = ''
if ($Check) {
    $tempTarget = Join-Path ([System.IO.Path]::GetTempPath()) ("mmcheck-" + [System.Guid]::NewGuid().ToString('N') + '.' + $Format)
    $target = $tempTarget
} elseif (-not $target) {
    $target = [System.IO.Path]::ChangeExtension($inItem.FullName, $Format)
}
$target = [System.IO.Path]::GetFullPath($target)
$targetDir = Split-Path -Parent $target
if ($targetDir -and -not (Test-Path -LiteralPath $targetDir)) { New-Item -ItemType Directory -Force -Path $targetDir | Out-Null }

$mmArgs = @('-i', $inItem.FullName, '-o', $target, '-t', $Theme)
if ($BackgroundColor) { $mmArgs += @('-b', $BackgroundColor) }
if ($PuppeteerConfigFile) { $mmArgs += @('-p', $PuppeteerConfigFile) }

try {
    & $mmdc @mmArgs
    $code = $LASTEXITCODE
} catch {
    if ($tempTarget -and (Test-Path -LiteralPath $tempTarget)) { Remove-Item -LiteralPath $tempTarget -Force -ErrorAction SilentlyContinue }
    Write-Host "Render failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

if ($Check) {
    Remove-Item -LiteralPath $tempTarget -Force -ErrorAction SilentlyContinue
    if ($code -ne 0) { Write-Host "SYNTAX FAIL: $($inItem.Name)" -ForegroundColor Red; exit 1 }
    if (-not $Quiet) { Write-Host "SYNTAX OK: $($inItem.Name)" -ForegroundColor Green }
    exit 0
}

if ($code -ne 0) { Write-Host "Render failed (mmdc exit $code)" -ForegroundColor Red; exit 1 }
if (-not (Test-Path -LiteralPath $target)) { Write-Host "Render reported success but output missing: $target" -ForegroundColor Red; exit 1 }
if (-not $Quiet) { Write-Host ("Rendered: {0} ({1:N0} bytes)" -f $target, (Get-Item -LiteralPath $target).Length) -ForegroundColor Green }
exit 0
