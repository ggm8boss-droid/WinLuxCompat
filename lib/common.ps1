# linux-compat for Windows: shared helpers (state, debug, GNU tool lookup, getopt).

$global:LC_STATE = Join-Path $global:LC_HOME 'state'

function global:_lc_state([string]$name) { Test-Path -LiteralPath (Join-Path $global:LC_STATE $name) }

function global:_lc_debug_on { $env:LC_DEBUG -eq '1' -or (_lc_state 'debug') }

# Dimmed "[linux-compat] -> ..." line on the console only (never in the pipeline).
function global:_lc_dbg([string]$msg) {
    $e = [char]27
    if (_lc_debug_on) { [Console]::Error.WriteLine("$e[90m[linux-compat] -> $msg$e[0m") }
}

# Where GNU tools live: $env:LC_GNU, Git for Windows, MSYS2, Cygwin, Scoop. $null = native only.
function global:_lc_find_gnu {
    if ($env:LC_NOGNU -eq '1' -or (_lc_state 'nognu')) { return $null }
    $cands = @($env:LC_GNU,
        "$env:ProgramFiles\Git\usr\bin",
        "${env:ProgramFiles(x86)}\Git\usr\bin",
        "$env:LOCALAPPDATA\Programs\Git\usr\bin",
        "$env:USERPROFILE\scoop\apps\git\current\usr\bin",
        'C:\msys64\usr\bin', 'C:\cygwin64\bin')
    foreach ($d in $cands) {
        if ($d -and (Test-Path -LiteralPath (Join-Path $d 'ls.exe'))) { return $d }
    }
    $git = Get-Command git.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($git) {
        $d = Join-Path (Split-Path (Split-Path $git.Source)) 'usr\bin'
        if (Test-Path -LiteralPath (Join-Path $d 'ls.exe')) { return $d }
    }
    $null
}
$global:LC_GNU = _lc_find_gnu

function global:_lc_gnu_bin([string]$name) {
    if (-not $global:LC_GNU) { return $null }
    $p = Join-Path $global:LC_GNU "$name.exe"
    if (Test-Path -LiteralPath $p) { $p } else { $null }
}

# Real Windows program, skipping our own functions/aliases.
function global:_lc_win_bin([string]$name) {
    $p = Join-Path "$env:SystemRoot\System32" "$name.exe"
    if (Test-Path -LiteralPath $p) { return $p }
    (Get-Command "$name.exe" -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
}

function global:_lc_dryrun { $env:LC_DRYRUN -eq '1' }

# Quote one argument the way you'd type it, for debug/dry-run output and command lines.
function global:_lc_q([string]$s) {
    if ($s -eq '') { return "''" }
    if ($s -match '^[\w\-./\\:=@%+,~*?]+$') { return $s }
    "'" + $s.Replace("'", "''") + "'"
}
function global:_lc_qall($list) { (@($list) | ForEach-Object { _lc_q "$_" }) -join ' ' }

# Run an external program, or print it when LC_DRYRUN=1 (tests use that for anything with side effects).
function global:_lc_exec([string]$exe, [object[]]$argv) {
    $argv = @($argv)
    _lc_dbg ("$(Split-Path -Leaf $exe) " + (_lc_qall $argv))
    if (_lc_dryrun) { "[dry] $(Split-Path -Leaf $exe) $(_lc_qall $argv)"; $global:LASTEXITCODE = 0; return }
    & $exe @argv
}
# Same for a PowerShell action described by $text.
function global:_lc_act([string]$text, [scriptblock]$action) {
    _lc_dbg $text
    if (_lc_dryrun) { "[dry] $text"; return }
    & $action
}

function global:_lc_err([string]$cmd, [string]$msg, [int]$code = 1) {
    [Console]::Error.WriteLine("${cmd}: $msg")
    $global:LASTEXITCODE = $code
}

# ~ and ~/x -> home; FileInfo -> full path; arrays flattened. Used on args for native exes.
function global:_lc_args($list) {
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($a in @($list)) {
        if ($null -eq $a) { continue }
        if ($a -is [System.IO.FileSystemInfo]) { $out.Add($a.FullName); continue }
        if ($a -is [array]) { foreach ($x in (_lc_args $a)) { $out.Add($x) }; continue }
        $s = "$a"
        if ($s -eq '~') { $s = $HOME }
        elseif ($s -match '^~[\\/]') { $s = $HOME + $s.Substring(1) }
        elseif ($s -match '^--?[\w-]+=~[\\/]') { $s = $s -replace '=~(?=[\\/])', "=$HOME" }
        $out.Add($s)
    }
    , $out.ToArray()
}

# /c/Users/x -> C:\Users\x, ~ -> home. For paths given Linux-style to native code.
function global:_lc_winpath([string]$p) {
    if ($p -eq '~') { return $HOME }
    if ($p -match '^~[\\/]') { return $HOME + ($p.Substring(1) -replace '/', '\') }
    if ($p -match '^/([a-zA-Z])(/.*)?$') {
        $rest = if ($Matches[2]) { $Matches[2] -replace '/', '\' } else { '\' }
        return $Matches[1].ToUpper() + ':' + $rest
    }
    if ($p -eq '/dev/null') { return 'NUL' }
    $p
}

# Minimal GNU getopt. $spec: short letters, ':' after one that takes a value ("n:hv").
# $long: names, '=' suffix when it takes a value ("lines=","help"). $longMap maps long -> short.
# Returns @{ o = @{name=value|$true|count}; rest = string[] }. -5 style numbers land in o['#'].
function global:_lc_getopt($argv, [string]$spec = '', [string[]]$long = @(), [hashtable]$longMap = @{}, [switch]$numeric, [switch]$stopAtFirst) {
    # Case-sensitive: -a and -A are different flags.
    $o = New-Object System.Collections.Hashtable ([StringComparer]::Ordinal)
    $rest = New-Object System.Collections.Generic.List[string]
    $argv = _lc_args $argv
    $i = 0
    while ($i -lt $argv.Count) {
        $a = $argv[$i]
        if ($a -eq '--') { $i++; while ($i -lt $argv.Count) { $rest.Add($argv[$i]); $i++ }; break }
        if ($a.StartsWith('--') -and $a.Length -gt 2) {
            $name = $a.Substring(2); $val = $null
            if ($name.Contains('=')) { $val = $name.Substring($name.IndexOf('=') + 1); $name = $name.Substring(0, $name.IndexOf('=')) }
            $def = $long | Where-Object { $_.TrimEnd('=') -eq $name } | Select-Object -First 1
            if (-not $def) { $def = $long | Where-Object { $_.StartsWith($name) } | Select-Object -First 1 }
            if (-not $def) { $o["?$name"] = $true; $i++; continue }
            $key = $def.TrimEnd('='); if ($longMap.ContainsKey($key)) { $key = $longMap[$key] }
            if ($def.EndsWith('=')) {
                if ($null -eq $val) { $i++; $val = if ($i -lt $argv.Count) { $argv[$i] } else { '' } }
                $o[$key] = $val
            } else { $o[$key] = if ($o[$key] -is [int]) { $o[$key] + 1 } else { 1 } }
            $i++; continue
        }
        if ($a.Length -gt 1 -and $a[0] -eq '-' -and $numeric -and $a.Substring(1) -match '^\d+$') { $o['#'] = [int]$a.Substring(1); $i++; continue }
        if ($a.Length -gt 1 -and $a[0] -eq '-') {
            $j = 1
            while ($j -lt $a.Length) {
                $c = [string]$a[$j]; $k = $spec.IndexOf($c)
                if ($k -lt 0) { $o["?$c"] = $true; $j++; continue }
                if ($k + 1 -lt $spec.Length -and $spec[$k + 1] -eq ':') {
                    $val = $a.Substring($j + 1)
                    if ($val -eq '') { $i++; $val = if ($i -lt $argv.Count) { $argv[$i] } else { '' } }
                    $o[$c] = $val; break
                }
                $o[$c] = if ($o[$c] -is [int]) { $o[$c] + 1 } else { 1 }
                $j++
            }
            $i++; continue
        }
        $rest.Add($a); $i++
        if ($stopAtFirst) { while ($i -lt $argv.Count) { $rest.Add($argv[$i]); $i++ }; break }
    }
    @{ o = $o; rest = $rest.ToArray() }
}

# Expand wildcards in path args the way bash would (unmatched patterns stay literal).
function global:_lc_glob([string[]]$paths) {
    foreach ($p in $paths) {
        $p = _lc_winpath $p
        if ($p -match '[*?\[]') {
            $m = @(Resolve-Path -Path $p -ErrorAction SilentlyContinue | ForEach-Object { $_.ProviderPath })
            if ($m.Count) { $m; continue }
        }
        $p
    }
}

# Human-readable size like GNU -h (1K, 2.5M, 3.1G).
function global:_lc_human([double]$n, [int]$base = 1024) {
    $u = 'B', 'K', 'M', 'G', 'T', 'P'; $i = 0
    while ($n -ge $base -and $i -lt $u.Count - 1) { $n /= $base; $i++ }
    if ($i -eq 0) { return '{0:0}' -f $n + $(if ($base -eq 1024) { '' } else { 'B' }) }
    $f = if ($n -lt 10) { '{0:0.0}' } else { '{0:0}' }
    ($f -f $n) + $u[$i] + $(if ($base -eq 1000) { 'B' } else { '' })
}

function global:_lc_is_admin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function global:_lc_need_admin([string]$cmd) {
    if (-not (_lc_is_admin) -and -not (_lc_dryrun)) { _lc_err $cmd 'needs admin rights, run it with sudo'; return $true }
    $false
}
