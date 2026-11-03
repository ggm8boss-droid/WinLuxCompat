# linux-compat for Windows: sudo = run as administrator.
# Uses Windows' built-in sudo (same window when it's set to Inline), else a UAC-elevated new window.
# The elevated side loads linux-compat too (lib\run.ps1), so `sudo apt install x` / `sudo rm -rf x` work.

# 0 = off, 1 = new window, 2 = input disabled, 3 = inline
function global:_lc_sudo_mode {
    $v = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Sudo' -Name Enabled -ErrorAction SilentlyContinue).Enabled
    if ($null -eq $v) { 0 } else { [int]$v }
}

function global:_lc_b64([string]$s) { [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($s)) }

# Elevate a command line. $shell = ps (run it in PowerShell) or cmd (run it in cmd.exe).
function global:_lc_elevate([string]$line, [string]$shell = 'ps', [switch]$interactive) {
    $run = Join-Path $global:LC_HOME 'lib\run.ps1'
    $cwd = (Get-Location -PSProvider FileSystem).ProviderPath
    $ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $pa = @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $run, '--lc-line', $shell, (_lc_b64 $cwd), (_lc_b64 $line))
    if ($interactive) {
        if ($shell -eq 'cmd') {
            # admin cmd with linux-compat loaded (cmd\admin.cmd cds to LC_SUDO_CWD, kept by sudo -E)
            $ps = $env:ComSpec
            $env:LC_SUDO_CWD = $cwd
            $pa = @('/d', '/k', (Join-Path $global:LC_HOME 'cmd\admin.cmd'))
        } else { $pa = @('-NoLogo', '-NoExit', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $run, '--lc-shell', $shell, (_lc_b64 $cwd)) }
    }
    $mode = _lc_sudo_mode
    _lc_dbg "sudo ($(@('off: new admin window', 'Windows sudo, new window', 'Windows sudo, no input', 'Windows sudo, inline')[[Math]::Min(3, $mode)])) $line"
    if (_lc_dryrun) { "[dry] sudo[$mode] $shell $line"; return }
    if (_lc_is_admin) {
        if ($interactive) { "linux-compat: already running as administrator"; return }
        & $ps @pa; return
    }
    if ($mode -ge 1) {
        $sudo = "$env:SystemRoot\System32\sudo.exe"
        & $sudo -E $ps @pa
        return
    }
    [Console]::Error.WriteLine('sudo: Windows sudo is off, opening an admin window (for same-window sudo: Settings > System > For developers > Enable sudo, set to Inline)')
    $quoted = if ($ps -eq $env:ComSpec) { "/d /s /k `"`"$($pa[2])`" `"$cwd`"`"" } else { ($pa | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }) -join ' ' }
    if (-not $interactive) { $quoted = $quoted -replace '^-NoLogo', '-NoLogo -NoExit' }
    try { Start-Process -FilePath $ps -ArgumentList $quoted -Verb RunAs -WorkingDirectory $cwd } catch { _lc_err 'sudo' 'cancelled' }
}

# cmd's sudo.cmd: the raw command line comes in LC_SUDO_LINE.
function global:_lc_cmd_sudo {
    $line = "$env:LC_SUDO_LINE".Trim()
    while ($line -match '^(-E|--preserve-env|-k|-H|--)\s+(.*)$') { $line = $Matches[2] }
    if ($line -match '^(-i|-s|--login|--shell|su|cmd)$') { _lc_elevate '' 'cmd' -interactive; return }
    if ($line -match '^(powershell|pwsh)$') { _lc_elevate '' 'ps' -interactive; return }
    _lc_elevate $line 'cmd'
}

function global:sudo {
    $a = @($args)
    # Windows sudo's own commands and flags go straight through.
    if ($a.Count -and "$($a[0])" -in 'config', '--new-window', '-N', '--inline', '--disable-input', '--chdir', '-D', '--help', '-h', '--version', '-V') {
        & "$env:SystemRoot\System32\sudo.exe" @a; return
    }
    while ($a.Count -and "$($a[0])" -match '^-') {
        switch -CaseSensitive -Regex ("$($a[0])") {
            '^-(i|s|-login|-shell)$' { _lc_elevate '' 'ps' -interactive; return }
            '^-(k|K|v)$' { if ($a.Count -eq 1) { return } }
            '^-(u|g|C|p|r|t|U|h)$' { if ("$($a[0])" -eq '-u' -and "$($a[1])" -ne 'root') { _lc_err 'sudo' 'only root (administrator) is supported'; return }; $a = @($a | Select-Object -Skip 1) }
            '^--$' { $a = @($a | Select-Object -Skip 1); break }
        }
        $a = @($a | Select-Object -Skip 1)
    }
    if (-not $a.Count) { 'usage: sudo command [args...]   (sudo -i / sudo su for an admin shell)'; return }
    if ("$($a[0])" -eq 'su' -or ("$($a[0])" -in 'bash', 'powershell', 'pwsh', 'cmd' -and $a.Count -eq 1)) { _lc_elevate '' $(if ("$($a[0])" -eq 'cmd') { 'cmd' } else { 'ps' }) -interactive; return }
    $line = (@($a) | ForEach-Object { $x = $_; if ($x -is [System.IO.FileSystemInfo]) { $x = $x.FullName }; _lc_q "$x" }) -join ' '
    _lc_elevate $line 'ps'
}
