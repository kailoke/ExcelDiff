<#
.SYNOPSIS
    AI_Script 公共函数库（dot-source 使用，不直接执行）。

.DESCRIPTION
    统一此前在多个脚本里重复实现的逻辑：
      - Get-ProjectRoot            从脚本目录推工程根
      - Get-ProtectedRules         读取 protected-paths.json
      - Get-ProtectedHits          路径列表 × 规则 → forbidden/caution 命中
      - Invoke-NativeCapture       取任意原生命令输出（重定向交给 cmd；受限环境里 PowerShell 捕获子进程 stdout 会失败）
      - Invoke-GitCapture          上一条的特化：加 `-C` 取 git 输出
      - Get-CodeChangedPaths       "算不算代码改动"的唯一出处（LEDGER 与逐提交审计共用）

.USAGE
    $lib = Join-Path $scriptDir 'lib\common.ps1'
    . $lib
#>

function Get-ProjectRoot {
    param([Parameter(Mandatory = $true)][string]$ScriptDir)
    return (Split-Path -Parent $ScriptDir)
}

function Get-ProtectedRules {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)
    $cfgPath = Join-Path $ProjectRoot 'AI_Script\protected-paths.json'
    return (Get-Content -LiteralPath $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Get-ProtectedHits {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Paths,
        [Parameter(Mandatory = $true)]$Rules
    )
    $forbidden = @()
    $caution = @()
    # forbiddenExcept：禁改区里"同目录手写扩展类"之类的例外（glob 与 forbidden 同语法）。规则正典 = protected-paths.json。
    $except = @()
    if (@($Rules.PSObject.Properties.Name) -contains 'forbiddenExcept') { $except = @($Rules.forbiddenExcept) }
    foreach ($p in $Paths) {
        $exempt = $false
        foreach ($ge in $except) { if ($p -like $ge) { $exempt = $true; break } }
        if (-not $exempt) {
            foreach ($g in $Rules.forbidden) { if ($p -like $g) { $forbidden += $p; break } }
        }
        foreach ($g in $Rules.caution) { if ($p -like $g) { $caution += $p; break } }
    }
    return @{ Forbidden = $forbidden; Caution = $caution }
}

<#
取「受限环境里能拿到的」原生命令输出。这是**通用**入口，不只给 git：本仓门禁还会调 python / powershell，
它们在沙箱里同样会因为"PowerShell 捕获子进程 stdout"而拿不到输出——实测 check-ai-deps.ps1 因此把已安装的
包误报成 [FAIL]。按工具一个个修是治不完的，收进这一个函数。

三条路只有一条两版本通用：
1. `$x = & 程序 ...` —— 不行。这会让 PowerShell 去捕获子进程 stdout，在 Windows ACL 沙箱（给子进程按访问
   控制列表限权的隔离层）里这条路径起不来：实测 git/node/cmd 一律报"拒绝访问"，且调用方自身退出码仍为 0。
2. `Start-Process -RedirectStandardOutput` —— PowerShell 7 下可行，**Windows PowerShell 5.1 下不行**：5.1 走
   .NET Framework 的管道，受限令牌下直接抛 Win32Exception: Access is denied（实测）。本仓要求门禁双版本都绿。
3. **本函数采用**：把重定向交给 cmd（`> 文件 2> 文件`），不经 PowerShell 管道，两个版本行为一致。代价是 cmd 会
   自行解析命令串，故两道防护：
   - **程序名**含路径分隔符/空格/引号时写成 `""路径"`（开头双引号加倍）：cmd 的 `/c` 有"首尾引号剥离"规则，
     直接写 `"D:\Program Files\..."` 会被吃掉那对引号并按空格断开（实测）；加倍后正常。
   - **参数**含 `%`/引号/通配/空格等时经环境变量注入并放进双引号里引用：cmd 只展开一遍、不回扫注入内容
     （实测 `--pretty=format:%H<TAB>%ad<TAB>%s` 三个字段完整穿过）。含双引号或换行的参数直接拒绝——cmd 没法
     把它们安全带过命令串，静默拼错（产物文件不生成、stderr 还空着）比显式报错更糟。

判成败三个信号：① 产物文件没生成 = 命令没跑成；② stderr 命中 fatal 类字样；③ 退出码非 0（由 cmd 的 `||` 落一个
失败标记文件得到，放在结果的 `Failed` 上）。**不能拿"stderr 非空"当失败**：不少工具把 warning 写进 stderr 而退出码为
0（实测，曾被这条误判成失败），git 的 `[attr] ... not allowed` 告警同理。
用 `||` 而不是读 `%ERRORLEVEL%`：后者在 cmd 里是解析期展开（拿到的是上一条命令的码）；用延迟展开
（`/v:on` + `!ERRORLEVEL!`）又会把参数里的 `!` 吃掉。
#>
function Invoke-NativeCapture {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [AllowEmptyCollection()][AllowEmptyString()][string[]]$Arguments = @()
    )
    $tmpOut = Join-Path ([System.IO.Path]::GetTempPath()) ("cap-" + [guid]::NewGuid().ToString('N') + ".out")
    $tmpErr = $tmpOut + ".err"
    $tmpFail = $tmpOut + ".fail"
    $lines = @()
    $err = ''
    $ok = $false
    $failed = $true
    $envNames = @()
    try {
        $unsupported = @($Arguments | Where-Object { $_ -match '["\r\n]' })
        if ($unsupported.Count -gt 0) {
            return [pscustomobject]@{ Ok = $false; Failed = $true; Lines = @(); Error = ('unsupported character (double quote / CR / LF) in argument: ' + $unsupported[0]) }
        }

        $parts = @()
        $i = 0
        foreach ($a in $Arguments) {
            if ($a -match '[%^!&|<>()*?\s]') {
                $nm = 'DSH_ARG' + $i
                Set-Item -Path ('env:' + $nm) -Value $a
                $envNames += $nm
                $parts += ('"%' + $nm + '%"')
            } else {
                $parts += $a
            }
            $i++
        }
        $prog = if ($FilePath -match '[\\/\s"]') { '""' + $FilePath + '"' } else { $FilePath }
        $cmdline = $prog + ' ' + ($parts -join ' ') + ' > "' + $tmpOut + '" 2> "' + $tmpErr + '" || echo 1 > "' + $tmpFail + '"'

        for ($attempt = 1; $attempt -le 2; $attempt++) {
            # 每轮先清标记文件：否则上一轮留下的"失败标记"会把本轮成功误判成失败
            if (Test-Path -LiteralPath $tmpFail) { Remove-Item -LiteralPath $tmpFail -Force -ErrorAction SilentlyContinue }
            Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', $cmdline) -NoNewWindow -Wait
            if (Test-Path -LiteralPath $tmpOut) { break }
        }
        if (Test-Path -LiteralPath $tmpOut) { $lines = @([System.IO.File]::ReadAllLines($tmpOut)); $ok = $true }
        if (Test-Path -LiteralPath $tmpErr) { $err = (@([System.IO.File]::ReadAllLines($tmpErr)) -join ' ').Trim() }
        if (-not (Test-Path -LiteralPath $tmpOut)) { $ok = $false }
        elseif ($err -match '(?i)fatal:|error:|not recognized|not a git command|not a git repository|ambiguous argument|unknown revision|did not match any') { $ok = $false }
        $failed = Test-Path -LiteralPath $tmpFail
    } catch {
        $ok = $false
        $failed = $true
        $err = "$_"
    } finally {
        foreach ($nm in $envNames) { Remove-Item -Path ('env:' + $nm) -Force -ErrorAction SilentlyContinue }
        foreach ($f in @($tmpOut, $tmpErr, $tmpFail)) {
            if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
        }
    }
    return [pscustomobject]@{ Ok = $ok; Failed = $failed; Lines = $lines; Error = $err }
}

<#
取 git 输出 = 上面的通用入口加 `-C`。git 用 PATH 上的名字而不写全路径：本机 git 在带空格的安装目录下，
带空格的全路径要额外绕引号，PATH 解析交给 cmd 即可；存在性先由 Get-Command 把关。
#>
function Invoke-GitCapture {
    param(
        # 省略 = 不加 `-C`（给不依赖仓库的命令用）
        [string]$ProjectRoot = '',
        # AllowEmptyString：不加它时，数组里出现空串元素会让 PowerShell 在**参数绑定阶段**就抛异常，
        # helper 变成会炸的函数而不是返回受控结果。
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][AllowEmptyString()][string[]]$GitArgs
    )
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{ Ok = $false; Failed = $true; Lines = @(); Error = 'git not found on PATH' }
    }
    $argv = @()
    if ($ProjectRoot) { $argv += @('-C', $ProjectRoot) }
    $argv += $GitArgs
    return (Invoke-NativeCapture -FilePath 'git' -Arguments $argv)
}

# "算不算代码改动"的唯一出处：pre-commit 的 LEDGER/RESTAGE 与 verify-day 的逐提交审计必须同判据，
# 否则同一笔提交会出现"提交时放行、日终判 FAIL"的自相矛盾。
# 判据（本工程）：七个产品/工具工程目录下的 .cs/.xaml/.csproj，加 lang\*.json（部署载荷），
# 加锚点注册表本身（改锚点 = 改了文档↔代码的映射，必须带台账）。
function Get-CodeChangedPaths {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Paths,
        # 保留参数位（与逐提交审计的调用形状兼容）；当前判据不依赖基线版本
        [string]$Base = 'HEAD'
    )
    $code = @()
    foreach ($p in $Paths) {
        if ($p -eq 'AI_Script/code-anchors.json') { $code += $p; continue }
        if ($p -like 'lang/*' -and $p -like '*.json') { $code += $p; continue }
        if ($p -notlike '*.cs' -and $p -notlike '*.xaml' -and $p -notlike '*.csproj') { continue }
        if ($p -notmatch '^(ExcelDiff/|ExcelDiff\.GUI/|ExcelDiff\.Installer/|ExcelDiff\.ShellExtension/|NetDiff/|FastWpfGrid/|DiffHarness/)') { continue }
        $code += $p
    }
    return $code
}
