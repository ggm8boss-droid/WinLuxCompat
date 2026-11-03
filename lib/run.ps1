# linux-compat for Windows: run one command with the layer loaded, outside an interactive PowerShell.
# Used by the cmd shims (bin\*.cmd) and by sudo on the elevated side. No param() block on purpose:
# Linux flags like -la or -s must reach the command, not PowerShell's parameter binder.
#   run.ps1 <name> <args...>                              cmd shim: run linux-compat command <name>
#   run.ps1 --lc-line ps|cmd <cwd b64> <line b64>         sudo: run a whole command line
#   run.ps1 --lc-shell ps|cmd <cwd b64>                   sudo -i: admin shell
$ErrorActionPreference = 'Continue'
$lcHome = Split-Path -Parent $PSScriptRoot
function _dec([string]$s) { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($s)) }

if ($args.Count -ge 3 -and $args[0] -in '--lc-line', '--lc-shell') {
    $mode = $args[0]; $shell = $args[1]
    Set-Location -LiteralPath (_dec $args[2])
    $Host.UI.RawUI.WindowTitle = "Administrator: linux-compat"
    if ($shell -eq 'cmd') {
        $init = Join-Path $lcHome 'cmd\init.cmd'
        if ($mode -eq '--lc-shell') { & "$env:ComSpec" /d /k "`"$init`""; exit $LASTEXITCODE }
        $env:PATH = (Join-Path $lcHome 'bin') + ';' + $env:PATH
        & "$env:ComSpec" /d /c (_dec $args[3])
        exit $LASTEXITCODE
    }
    . (Join-Path $lcHome 'linux-compat.ps1') -NonInteractive:($mode -eq '--lc-line')
    if ($mode -eq '--lc-shell') { return }   # powershell -NoExit keeps this shell open
    $global:LASTEXITCODE = 0
    Invoke-Expression (_lc_rewrite (_dec $args[3]))
    $rc = $global:LASTEXITCODE; if (-not $? -and -not $rc) { $rc = 1 }
    exit $rc
}

if (-not $args.Count) { exit 0 }
. (Join-Path $lcHome 'linux-compat.ps1') -NonInteractive
$global:LASTEXITCODE = 0
$name = $args[0]
# cmd doesn't expand ~ or wildcards; bash would.
$argv = @(foreach ($x in @($args | Select-Object -Skip 1)) { if ("$x" -match '[*?]' -and "$x" -notmatch '^-') { _lc_glob @("$x") } else { "$x" } })
# Only text filters read stdin; `free` or `apt` must not block on a pipe that never closes.
$reads = $global:LC_GNU_CMDS.Contains($name) -or $name -in 'xclip', 'xsel', 'wl-copy', 'xargs'
if ($reads -and [Console]::IsInputRedirected) { [Console]::In.ReadToEnd().TrimEnd("`r", "`n") -split "`r?`n" | & $name @argv }
else { & $name @argv }
$rc = $global:LASTEXITCODE; if (-not $? -and -not $rc) { $rc = 1 }
exit $rc
