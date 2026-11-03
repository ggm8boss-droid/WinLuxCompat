# linux-compat for Windows: GNU text/file commands.
# Each name becomes a PowerShell function that runs the GNU tool (Git for Windows etc.) when there is
# one, else a native PowerShell version (lib\native.ps1, functions named _lc_n_<cmd>).
# PowerShell-style use (objects piped in, -Recurse/-Force style params) still goes to the cmdlet.

# Commands routed to GNU first. Value = exe name + fixed leading args, when it differs.
$global:LC_GNU_CMDS = [ordered]@{
    ls = ''; cat = ''; grep = ''; egrep = 'grep -E'; fgrep = 'grep -F'; sed = ''; awk = ''; gawk = ''
    head = ''; tail = ''; wc = ''; sort = ''; uniq = ''; cut = ''; tr = ''; tee = ''; touch = ''
    rm = ''; cp = ''; mv = ''; mkdir = ''; rmdir = ''; chmod = ''; find = ''; xargs = ''; diff = ''
    cmp = ''; sdiff = ''; file = ''; du = ''; stat = ''; date = ''; seq = ''; sleep = ''; yes = ''
    nl = ''; paste = ''; split = ''; od = ''; xxd = ''; base64 = ''; md5sum = ''; sha1sum = ''
    sha256sum = ''; sha512sum = ''; tac = ''; less = ''; nano = ''; vim = ''; vi = 'vim'; gzip = ''
    gunzip = 'gzip -d'; zcat = 'gzip -dc'; unzip = ''; column = ''; fold = ''; comm = ''; join = ''
    fmt = ''; dos2unix = ''; unix2dos = ''; patch = ''; printf = ''; test = ''; expr = ''
    true = ''; false = ''; truncate = ''; shuf = ''; numfmt = ''; factor = ''; tsort = ''; csplit = ''
    b2sum = ''; cksum = ''; sum = ''; shred = ''; iconv = ''; bzip2 = ''; bunzip2 = ''
}

# PowerShell cmdlet each name normally means (built-in alias), for PowerShell-style passthrough.
$global:LC_CMDLET = @{
    ls = 'Get-ChildItem'; cat = 'Get-Content'; rm = 'Remove-Item'; cp = 'Copy-Item'; mv = 'Move-Item'
    sort = 'Sort-Object'; tee = 'Tee-Object'; diff = 'Compare-Object'; sleep = 'Start-Sleep'
    rmdir = 'Remove-Item'; mkdir = 'New-Item'; date = 'Get-Date'; echo = 'Write-Output'
    ps = 'Get-Process'; kill = 'Stop-Process'; pwd = 'Get-Location'; cd = 'Set-Location'; man = 'Get-Help'
}

$global:LC_PARAMCACHE = @{}
# True when the args look like PowerShell parameters of $cmdlet (-Recurse, -Force, -Filter x...).
function global:_lc_psstyle([string]$cmdlet, $argv) {
    if (-not $global:LC_PARAMCACHE.ContainsKey($cmdlet)) {
        $c = Get-Command $cmdlet -CommandType Cmdlet -ErrorAction SilentlyContinue
        $global:LC_PARAMCACHE[$cmdlet] = if ($c) { @($c.Parameters.Keys) } else { @() }
    }
    $names = $global:LC_PARAMCACHE[$cmdlet]
    foreach ($a in @($argv)) {
        if ($a -isnot [string]) { continue }
        if ($a -match '^-([A-Za-z][A-Za-z]{2,}):?$') {
            $p = $Matches[1]
            if ($names | Where-Object { $_.StartsWith($p, 'OrdinalIgnoreCase') }) { return $true }
        }
    }
    $false
}

function global:_lc_has_objects($items) {
    foreach ($x in $items) { if ($null -ne $x -and $x -isnot [string]) { return $true } }
    $false
}

# Windows command-line quoting of one argument (CommandLineToArgvW rules).
function global:_lc_winarg([string]$a) {
    if ($a -ne '' -and $a -notmatch '[\s"]') { return $a }
    '"' + ($a -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}

# Pipe text into a program the Linux way: LF line ends (PowerShell would send CRLF, so `grep 'x$'`,
# base64, md5sum... would see a \r). Output comes back line by line into the pipeline.
function global:_lc_pipe_lf([string]$exe, [string[]]$argv, $items) {
    $text = (@($items | Out-String -Stream) -join "`n") + "`n"
    $bytes = (New-Object Text.UTF8Encoding $false).GetBytes($text)
    $psi = New-Object Diagnostics.ProcessStartInfo $exe
    $psi.Arguments = (@($argv) | ForEach-Object { _lc_winarg $_ }) -join ' '
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true
    $psi.StandardOutputEncoding = New-Object Text.UTF8Encoding $false
    $p = [Diagnostics.Process]::Start($psi)
    $ms = New-Object IO.MemoryStream (, $bytes)
    $copy = $ms.CopyToAsync($p.StandardInput.BaseStream)
    $closed = $false
    while ($true) {
        $read = $p.StandardOutput.ReadLineAsync()
        while (-not $read.Wait(20)) { if (-not $closed -and $copy.IsCompleted) { $p.StandardInput.Close(); $closed = $true } }
        if ($null -eq $read.Result) { break }
        $read.Result
    }
    if (-not $closed) { try { $p.StandardInput.Close() } catch {} }
    $p.WaitForExit()
    $global:LASTEXITCODE = $p.ExitCode
}

# Run a GNU exe with Git's usr\bin first on PATH (so xargs/find -exec/timeout find the other tools).
function global:_lc_run_gnu([string]$exe, [string[]]$argv, $inputItems, [bool]$hasInput) {
    _lc_dbg ("GNU $(Split-Path -Leaf $exe) " + (_lc_qall $argv))
    $old = $env:PATH
    $env:PATH = "$global:LC_GNU;$old"
    # GNU tools speak UTF-8. Switch only for this call, so Windows tools keep the console code page.
    # (Console.InputEncoding is what PowerShell 5.1 really uses when piping into a program; a UTF-8
    # one with a BOM would put the BOM in front of the first line.)
    $utf8 = New-Object Text.UTF8Encoding $false
    $oe = $global:OutputEncoding; $co = $ci = $null
    try { $co = [Console]::OutputEncoding; $ci = [Console]::InputEncoding; [Console]::OutputEncoding = $utf8; [Console]::InputEncoding = $utf8 } catch {}
    $global:OutputEncoding = $utf8
    try {
        # Pagers/editors need the console, so they get PowerShell's own pipe.
        if ($hasInput -and (Split-Path -Leaf $exe) -match '^(less|more|vim|vi|nano|view)\.exe$') { $inputItems | Out-String -Stream | & $exe @argv }
        elseif ($hasInput) { _lc_pipe_lf $exe $argv $inputItems }
        else { & $exe @argv }
    } finally {
        $env:PATH = $old; $global:OutputEncoding = $oe
        try { if ($co) { [Console]::OutputEncoding = $co }; if ($ci) { [Console]::InputEncoding = $ci } } catch {}
    }
}

function global:_lc_run_cmdlet([string]$cmdlet, [object[]]$argv, $inputItems, [bool]$hasInput) {
    _lc_dbg "$cmdlet $($argv -join ' ')  (PowerShell style)"
    $argv = @($argv)
    if ($cmdlet -eq 'New-Item') { $argv = @('-ItemType', 'Directory') + $argv }
    if ($hasInput) { $inputItems | & $cmdlet @argv } else { & $cmdlet @argv }
}

# Per-command fixes applied before running the GNU tool.
function global:_lc_gnu_args([string]$name, [string[]]$a) {
    switch ($name) {
        { $_ -in 'ls', 'grep', 'egrep', 'fgrep', 'diff' } {
            if (-not ($a -match '^--colou?r')) { $a = @('--color=auto') + $a }
        }
        # Windows' hidden system files, which GNU ls would show (it only hides dotfiles).
        'ls' {
            if (-not ($a -match '^--(hide|ignore|all|almost-all)|^-[a-zA-Z]*[aA]')) {
                $a = @('--hide=NTUSER*', '--hide=ntuser*', '--hide=desktop.ini', '--hide=$RECYCLE.BIN',
                    '--hide=System Volume Information', '--hide=DumpStack.log*', '--hide=pagefile.sys',
                    '--hide=swapfile.sys', '--hide=hiberfil.sys') + $a
            }
        }
    }
    , $a
}

# Windows-syntax passthrough for names that are also Windows programs (find "x", sort /r, timeout /t 5).
function global:_lc_windows_syntax([string]$name, $argv, [bool]$hasInput) {
    $a = @($argv | ForEach-Object { "$_" })
    $slash = [bool]($a | Where-Object { $_ -match '^/[A-Za-z?]{1,3}(:.*)?$' })
    switch ($name) {
        'find' { return $slash -or ($hasInput -and $a.Count -ge 1 -and $a[0] -notmatch '^-') }
        'sort' { return $slash }
    }
    $false
}

# Main dispatcher behind every GNU-command function.
function global:_lc_call([string]$name, [object[]]$argv, $inputItems, $inv) {
    $global:LASTEXITCODE = 0
    $argv = @($argv)
    $hasInput = $inv.ExpectingInput
    $cmdlet = $global:LC_CMDLET[$name]
    if ($cmdlet -and (($hasInput -and (_lc_has_objects $inputItems)) -or (_lc_psstyle $cmdlet $argv))) {
        _lc_run_cmdlet $cmdlet $argv $inputItems $hasInput
        return
    }
    if (_lc_windows_syntax $name $argv $hasInput) {
        $w = _lc_win_bin $name
        _lc_dbg "Windows $name.exe $($argv -join ' ')"
        if ($hasInput) { $inputItems | & $w @argv } else { & $w @argv }
        return
    }
    $a = _lc_args $argv
    $spec = $global:LC_GNU_CMDS[$name]
    $exeName = $name; $pre = @()
    if ($spec) { $parts = $spec -split ' '; $exeName = $parts[0]; $pre = @($parts | Select-Object -Skip 1) }
    $exe = _lc_gnu_bin $exeName
    if ($exe) {
        # C:\x\y -> C:/x/y: GNU tools print (and sha256sum escapes) backslashes otherwise.
        $a = @($a | ForEach-Object { if ($_ -match '^[A-Za-z]:\\' -or ($_ -match '\\' -and $_ -notmatch '[*?]' -and (Test-Path -LiteralPath $_))) { $_ -replace '\\', '/' } else { $_ } })
        $a = _lc_gnu_args $name (@($pre) + @($a))
        _lc_run_gnu $exe $a $inputItems $hasInput
        return
    }
    $native = Get-Command "_lc_n_$name" -CommandType Function -ErrorAction SilentlyContinue
    if ($native) {
        _lc_dbg "native $name $(_lc_qall $a)"
        if ($hasInput) { $inputItems | Out-String -Stream | & $native @a } else { & $native @a }
        return
    }
    _lc_err $name 'needs the GNU tools (install Git for Windows: winget install Git.Git), no built-in fallback for this one' 127
}

# Define the functions. Global aliases with the same names (ls, cat, rm, ...) are removed first.
function global:_lc_define([string]$name, [string]$body) {
    if (Test-Path "alias:$name") { Remove-Item "alias:$name" -Force -ErrorAction SilentlyContinue }
    Set-Item -Path "function:global:$name" -Value ([scriptblock]::Create($body))
}

foreach ($n in $global:LC_GNU_CMDS.Keys) {
    _lc_define $n "_lc_call '$n' `$args @(`$input) `$MyInvocation"
}
