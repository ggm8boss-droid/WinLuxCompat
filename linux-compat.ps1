# linux-compat for Windows: lets Linux/bash commands work in PowerShell (and cmd, see cmd\init.cmd).
# Dot-sourced from the PowerShell profile by install.ps1. See README.md.
param([switch]$NonInteractive)

$global:LC_VERSION = '1.0.0'
$global:LC_HOME = $PSScriptRoot
. (Join-Path $PSScriptRoot 'lib\common.ps1')
if (-not (Test-Path -LiteralPath $global:LC_STATE)) { [void](New-Item -ItemType Directory -Path $global:LC_STATE) }

function global:linuxcompat {
    $a = @($args | ForEach-Object { "$_" })
    $st = { param($n, [bool]$on) $f = Join-Path $global:LC_STATE $n; if ($on) { [void](New-Item -ItemType File -Path $f -Force) } else { Remove-Item -LiteralPath $f -ErrorAction SilentlyContinue } }
    switch ($(if ($a.Count) { $a[0] } else { '' })) {
        'debug' {
            switch ($a[1]) {
                'on' { & $st 'debug' $true; 'linux-compat: debug on (translations are shown dimmed, in PowerShell and cmd)' }
                'off' { & $st 'debug' $false; 'linux-compat: debug off' }
                default { if (_lc_debug_on) { 'on' } else { 'off' } }
            }
        }
        'gnu' {
            switch ($a[1]) {
                'on' { & $st 'nognu' $false; $global:LC_GNU = _lc_find_gnu; "linux-compat: GNU tools on ($global:LC_GNU)" }
                'off' { & $st 'nognu' $true; $global:LC_GNU = $null; 'linux-compat: GNU tools off, native PowerShell versions only' }
                default { if ($global:LC_GNU) { "on ($global:LC_GNU)" } else { 'off' } }
            }
        }
        'prompt' {
            switch ($a[1]) {
                'on' { & $st 'noprompt' $false; 'linux-compat: Git Bash style prompt on (new PowerShell and cmd windows)' }
                'off' { & $st 'noprompt' $true; 'linux-compat: prompt off, new windows keep the normal PowerShell/cmd prompt' }
                default { if (_lc_state 'noprompt') { 'off' } else { 'on' } }
            }
        }
        'off' { & $st 'disabled' $true; 'linux-compat: disabled for new PowerShell and cmd windows (`linuxcompat on` to re-enable)' }
        'on' { & $st 'disabled' $false; 'linux-compat: enabled for new windows' }
        'status' {
            "linux-compat $global:LC_VERSION ($global:LC_HOME)"
            "  enabled:     $(if (_lc_state 'disabled') { 'no' } else { 'yes' })"
            "  debug:       $(if (_lc_debug_on) { 'on' } else { 'off' })"
            "  GNU tools:   $(if ($global:LC_GNU) { $global:LC_GNU } else { 'none found (native PowerShell versions in use; winget install Git.Git for the real ones)' })"
            $m = _lc_sudo_mode
            "  sudo:        $(@('Windows sudo off -> opens an admin window (Settings > System > For developers > Enable sudo, Inline)', 'Windows sudo, new window', 'Windows sudo, input disabled', 'Windows sudo, inline (same window)')[[Math]::Min(3, $m)])"
            "  winget:      $(if (Get-Command winget.exe -ErrorAction SilentlyContinue) { 'yes' } else { 'not found' })"
            $pol = Get-ExecutionPolicy
            "  exec policy: $pol$(if ($pol -in 'Restricted', 'AllSigned') { '  <- profile scripts are blocked; run: Set-ExecutionPolicy -Scope CurrentUser RemoteSigned' })"
            $ar = (Get-ItemProperty 'HKCU:\Software\Microsoft\Command Processor' -Name AutoRun -ErrorAction SilentlyContinue).AutoRun
            "  cmd:         $(if ("$ar" -like "*$global:LC_HOME*") { 'hooked (AutoRun)' } else { 'not hooked (run install.ps1)' })"
        }
        'test' { & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File (Join-Path $global:LC_HOME 'tests\run-tests.ps1') @($a | Select-Object -Skip 1) }
        'install' { & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File (Join-Path $global:LC_HOME 'install.ps1') }
        'uninstall' { & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File (Join-Path $global:LC_HOME 'uninstall.ps1') }
        default { 'usage: linuxcompat status | debug on|off | gnu on|off | prompt on|off | on | off | test | install | uninstall' }
    }
}

if ((_lc_state 'disabled') -and -not $NonInteractive) { return }

foreach ($f in 'gnu', 'native', 'system', 'pkg', 'bashcompat', 'sudo') { . (Join-Path $PSScriptRoot "lib\$f.ps1") }

# PowerShell's own aliases that would shadow the Linux commands defined above.
foreach ($n in 'curl', 'wget', 'kill', 'ps', 'echo', 'pwd', 'cd', 'man', 'sleep', 'sort', 'tee', 'diff', 'cat', 'ls', 'cp', 'mv', 'rm', 'rmdir', 'mkdir') {
    if (Test-Path "alias:$n") { Remove-Item "alias:$n" -Force -ErrorAction SilentlyContinue }
}

if (-not $NonInteractive) {
    if (-not (_lc_state 'noprompt')) { . (Join-Path $PSScriptRoot 'lib\prompt.ps1') }
    _lc_install_readline
    $ba = Join-Path $HOME '.bash_aliases'
    if (Test-Path -LiteralPath $ba) { source $ba }
}
