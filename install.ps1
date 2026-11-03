# linux-compat for Windows: installer.
#   powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 [-Yes]
# Everything stays in this folder. Outside it, it only writes:
#   - a 4-line block in your PowerShell profile (Documents\WindowsPowerShell\profile.ps1, and
#     Documents\PowerShell\profile.ps1 if PowerShell 7 is installed) that loads linux-compat.ps1
#   - the cmd AutoRun value in HKCU\Software\Microsoft\Command Processor (runs cmd\init.cmd)
# Backups of what was there before go to .\state. uninstall.ps1 undoes both.
param([switch]$Yes)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$state = Join-Path $root 'state'
if (-not (Test-Path $state)) { [void](New-Item -ItemType Directory $state) }
$enc = New-Object Text.UTF8Encoding $true   # BOM: Windows PowerShell 5.1 reads BOM-less files as ANSI

$docs = [Environment]::GetFolderPath('MyDocuments')
$profiles = @(Join-Path $docs 'WindowsPowerShell\profile.ps1')
if (Get-Command pwsh.exe -ErrorAction SilentlyContinue) { $profiles += Join-Path $docs 'PowerShell\profile.ps1' }
$autorunKey = 'HKCU:\Software\Microsoft\Command Processor'
$init = Join-Path $root 'cmd\init.cmd'

"linux-compat installer ($root)"
'This will:'
foreach ($p in $profiles) { "  - add a block that loads linux-compat to $p" }
"  - set cmd's AutoRun to run $init"
if (-not $Yes) { $a = Read-Host 'Continue? [Y/n]'; if ($a -and $a -notmatch '^[yY]') { 'Cancelled.'; exit 1 } }

# 1. cmd shims
& (Join-Path $root 'tools\gen-shims.ps1') | Out-Null

# 2. PowerShell profile(s)
$begin = '# >>> linux-compat >>>'; $end = '# <<< linux-compat <<<'
$block = @(
    $begin
    "`$__lc = '$((Join-Path $root 'linux-compat.ps1').Replace("'", "''"))'"
    'if (Test-Path -LiteralPath $__lc) { . $__lc }; Remove-Variable __lc'
    $end
) -join "`r`n"
$i = 0
foreach ($p in $profiles) {
    $i++
    $dir = Split-Path $p
    if (-not (Test-Path $dir)) { [void](New-Item -ItemType Directory $dir) }
    $old = if (Test-Path $p) { [IO.File]::ReadAllText($p) } else { '' }
    if ($old) { [IO.File]::WriteAllText((Join-Path $state "profile$i.bak.ps1"), $old, $enc) }
    $clean = [regex]::Replace($old, "(?s)\r?\n?$([regex]::Escape($begin)).*?$([regex]::Escape($end))\r?\n?", "`r`n").TrimEnd()
    $new = if ($clean) { "$clean`r`n`r`n$block`r`n" } else { "$block`r`n" }
    [IO.File]::WriteAllText($p, $new, $enc)
    "  profile: $p"
}

# 3. cmd AutoRun (keeps an existing AutoRun command, chained after ours)
if (-not (Test-Path $autorunKey)) { [void](New-Item -Path $autorunKey -Force) }
$cur = (Get-ItemProperty $autorunKey -Name AutoRun -ErrorAction SilentlyContinue).AutoRun
$ours = "`"$init`""
if ("$cur" -notlike "*$init*") {
    if ($cur) { [IO.File]::WriteAllText((Join-Path $state 'autorun.bak'), $cur, $enc) }
    $val = if ($cur) { "$ours & $cur" } else { $ours }
    Set-ItemProperty $autorunKey -Name AutoRun -Value $val
}
"  cmd AutoRun: $((Get-ItemProperty $autorunKey -Name AutoRun).AutoRun)"

# 4. things only you can change
''
$pol = Get-ExecutionPolicy -Scope CurrentUser
$eff = @('MachinePolicy', 'UserPolicy', 'CurrentUser', 'LocalMachine' | ForEach-Object { Get-ExecutionPolicy -Scope $_ } | Where-Object { $_ -ne 'Undefined' })
$effective = if ($eff.Count) { $eff[0] } else { 'Restricted' }
if ($effective -in 'Restricted', 'AllSigned', 'Undefined') {
    'ACTION NEEDED: PowerShell blocks profile scripts on this PC (execution policy: ' + $effective + ').'
    '  Run this once yourself, then open a new window:'
    '      Set-ExecutionPolicy -Scope CurrentUser RemoteSigned'
}
$sudo = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Sudo' -Name Enabled -ErrorAction SilentlyContinue).Enabled
if ($sudo -ne 3) {
    'For sudo in the same window: Settings > System > For developers > Enable sudo, and set it to Inline.'
    '  (Until then sudo opens a separate admin window.)'
}
if (-not (Test-Path "$env:ProgramFiles\Git\usr\bin\ls.exe")) { 'Tip: winget install Git.Git gives the real GNU tools (ls, grep, sed, awk...); without it the built-in PowerShell versions are used.' }
''
'Done. Open a new PowerShell or cmd window. `linuxcompat status` shows what is active.'
