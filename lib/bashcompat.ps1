# linux-compat for Windows: bash builtins and habits in PowerShell, plus the Enter-key rewrite of
# bash-only syntax (&&, ||, VAR=x cmd, $PATH, 2>/dev/null, < file, !!, cmd &, for/if/while -> bash).

# bash-style variables most scripts and habits expect.
if (-not $env:USER) { $env:USER = $env:USERNAME }
if (-not (Test-Path variable:global:HOSTNAME)) { $global:HOSTNAME = $env:COMPUTERNAME }
if (-not $env:SHELL) { $env:SHELL = 'powershell' }

function global:echo {
    if (_lc_has_objects $args) { $args; return }
    $a = @($args | ForEach-Object { "$_" }); $nl = $true; $esc = $false
    while ($a.Count -and $a[0] -cmatch '^-[neE]+$') { if ($a[0] -cmatch 'n') { $nl = $false }; if ($a[0] -cmatch 'e') { $esc = $true }; if ($a[0] -cmatch 'E') { $esc = $false }; $a = @($a | Select-Object -Skip 1) }
    $s = $a -join ' '
    if ($esc) {
        $s = [regex]::Replace($s, '\\(\\|n|t|r|a|b|e|v|f|0[0-7]{0,3}|x[0-9a-fA-F]{1,2}|c)', {
                param($m) $k = $m.Groups[1].Value
                switch -CaseSensitive -Regex ($k) {
                    '^\\$' { '\' } '^n$' { "`n" } '^t$' { "`t" } '^r$' { "`r" } '^a$' { [string][char]7 } '^b$' { [string][char]8 }
                    '^e$' { [string][char]27 } '^v$' { [string][char]11 } '^f$' { [string][char]12 } '^c$' { [string][char]0 }
                    '^0' { [string][char][Convert]::ToInt32(('0' + $k.Substring(1)), 8) } '^x' { [string][char][Convert]::ToInt32($k.Substring(1), 16) }
                }
            })
        if ($s.Contains([string][char]0)) { $s = $s.Substring(0, $s.IndexOf([char]0)); $nl = $false }
    }
    if ($nl) { $s }
    elseif ($MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength) { $s }
    else { [Console]::Out.Write($s) }
}

function global:pwd {
    $p = (Get-Location).ProviderPath
    if ($args -contains '-P') { try { $t = (Get-Item -LiteralPath $p -Force).Target; if ($t) { $p = @($t)[0] } } catch {} }
    $p
}

function global:cd {
    if ($args.Count -and (_lc_psstyle 'Set-Location' $args)) { Set-Location @args; return }
    $a = @($args | ForEach-Object { "$_" } | Where-Object { $_ -notin '-L', '-P', '-e', '--' })
    $target = if (-not $a.Count) { $HOME } elseif ($a[0] -eq '-') { if (-not $env:OLDPWD) { _lc_err 'cd' 'OLDPWD not set'; return }; $env:OLDPWD } else { _lc_winpath ($a -join ' ') }
    if ($target -match '^\.\.\.+$') { $target = (@('..') * ($target.Length - 1)) -join '\' }
    $old = (Get-Location).Path
    if ($target -ne '' -and -not (Test-Path -LiteralPath $target)) {
        if (Test-Path -Path $target) { $target = (Resolve-Path -Path $target | Select-Object -First 1).Path }
        else { _lc_err 'cd' "${target}: No such file or directory"; return }
    }
    Set-Location -LiteralPath $target
    $env:OLDPWD = $old; $global:OLDPWD = $old
    if ($a.Count -and $a[0] -eq '-') { (Get-Location).Path }
}

function global:_lc_pathlist([string]$name, [string]$v) {
    # bash PATH=$PATH:/c/bin:~/bin -> Windows ;-list. Only for *PATH* variables.
    if ($name -notmatch 'PATH$') { return $v }
    $parts = foreach ($p in ($v -split ';')) { if ($p -match '^[a-zA-Z]:\\' -or $p -notmatch ':') { if ($p -match ':(?![\\/])' -and $p -notmatch '^[a-zA-Z]:') { $p -split ':' } else { $p -split '(?<=[^:]):(?=[/~.]|[a-zA-Z]:)' } } else { $p -split '(?<!^[a-zA-Z]):' } }
    (@($parts | Where-Object { $_ -ne '' } | ForEach-Object { _lc_winpath $_ })) -join ';'
}

function global:export {
    $a = @($args | ForEach-Object { "$_" })
    if (-not $a.Count -or $a -contains '-p') { Get-ChildItem env: | Sort-Object Name | ForEach-Object { "declare -x $($_.Name)=`"$($_.Value)`"" }; return }
    $remove = $false
    foreach ($x in $a) {
        if ($x -eq '-n') { $remove = $true; continue }
        if ($x -match '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') {
            $n = $Matches[1]; $v = _lc_pathlist $n $Matches[2]
            Set-Item -Path "env:$n" -Value $v
        } elseif ($x -match '^[A-Za-z_][A-Za-z0-9_]*$') {
            if ($remove) { Remove-Item "env:$x" -ErrorAction SilentlyContinue; continue }
            $pv = Get-Variable -Name $x -Scope Global -ErrorAction SilentlyContinue
            if ($pv -and $null -ne $pv.Value) { Set-Item -Path "env:$x" -Value "$($pv.Value)" }
        } else { _lc_err 'export' "``$x': not a valid identifier" }
    }
}
# cmd's export.cmd: print `set "NAME=value"` lines with $VARS, ~ and a:b PATH lists translated.
function global:_lc_cmd_export {
    foreach ($x in @($args | ForEach-Object { "$_" })) {
        if ($x -notmatch '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') { continue }
        $n = $Matches[1]
        $v = [regex]::Replace($Matches[2], '\$(?:\{(\w+)\}|(\w+))', { param($m) $k = if ($m.Groups[1].Success) { $m.Groups[1].Value } else { $m.Groups[2].Value }; [Environment]::GetEnvironmentVariable($k) })
        $v = _lc_pathlist $n $v
        if ($n -notmatch 'PATH$') { $v = _lc_winpath $v }
        "set `"$n=$v`""
    }
}

function global:unset {
    $a = @($args | ForEach-Object { "$_" }); $fn = $false
    foreach ($x in $a) {
        if ($x -eq '-f') { $fn = $true; continue } elseif ($x -eq '-v') { continue }
        if ($fn) { Remove-Item "function:$x" -ErrorAction SilentlyContinue; continue }
        Remove-Item "env:$x" -ErrorAction SilentlyContinue
        Remove-Variable -Name $x -Scope Global -ErrorAction SilentlyContinue
    }
}

function global:env {
    $a = @($args | ForEach-Object { "$_" }); $set = [ordered]@{}; $unset = @(); $i = 0; $clear = $false
    while ($i -lt $a.Count) {
        if ($a[$i] -in '-i', '--ignore-environment', '-') { $clear = $true; $i++ }
        elseif ($a[$i] -in '-u', '--unset') { $unset += $a[$i + 1]; $i += 2 }
        elseif ($a[$i] -match '^([^=\s-][^=\s]*)=(.*)$') { $set[$Matches[1]] = $Matches[2]; $i++ }
        else { break }
    }
    $cmd = @($a | Select-Object -Skip $i)
    if (-not $cmd.Count) {
        $vars = if ($clear) { @{} } else { $h = [ordered]@{}; Get-ChildItem env: | ForEach-Object { $h[$_.Name] = $_.Value }; $h }
        foreach ($k in $set.Keys) { $vars[$k] = $set[$k] }
        foreach ($k in @($vars.Keys)) { if ($unset -notcontains $k) { "$k=$($vars[$k])" } }
        return
    }
    $saved = @{}
    foreach ($k in @($set.Keys) + $unset) { $saved[$k] = [Environment]::GetEnvironmentVariable($k) }
    try {
        foreach ($k in $set.Keys) { Set-Item "env:$k" $set[$k] }
        foreach ($k in $unset) { Remove-Item "env:$k" -ErrorAction SilentlyContinue }
        & $cmd[0] @($cmd | Select-Object -Skip 1)
    } finally { foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) } }
}
function global:printenv { if ($args.Count) { foreach ($n in $args) { $v = [Environment]::GetEnvironmentVariable("$n"); if ($null -ne $v) { $v } else { $global:LASTEXITCODE = 1 } } } else { Get-ChildItem env: | ForEach-Object { "$($_.Name)=$($_.Value)" } } }

$global:LC_ALIASES = [ordered]@{}
function global:alias {
    $a = @($args | ForEach-Object { "$_" } | Where-Object { $_ -ne '-p' })
    if (-not $a.Count) { foreach ($k in $global:LC_ALIASES.Keys) { "alias $k='$($global:LC_ALIASES[$k])'" }; return }
    foreach ($x in $a) {
        if ($x -match '^([^=\s]+)=(.*)$') {
            $n = $Matches[1]; $v = $Matches[2].Trim()
            if ($v -match "^'(.*)'$" -or $v -match '^"(.*)"$') { $v = $Matches[1] }
            $global:LC_ALIASES[$n] = $v
            $body = (_lc_rewrite $v) + ' @args'
            if (Test-Path "alias:$n") { Remove-Item "alias:$n" -Force -ErrorAction SilentlyContinue }
            Set-Item -Path "function:global:$n" -Value ([scriptblock]::Create($body))
        } elseif ($global:LC_ALIASES.Contains($x)) { "alias $x='$($global:LC_ALIASES[$x])'" }
        else { _lc_err 'alias' "${x}: not found" }
    }
}
function global:unalias {
    foreach ($x in @($args | ForEach-Object { "$_" })) {
        if ($x -eq '-a') { foreach ($k in @($global:LC_ALIASES.Keys)) { Remove-Item "function:$k" -ErrorAction SilentlyContinue }; $global:LC_ALIASES.Clear(); continue }
        if ($global:LC_ALIASES.Contains($x)) { $global:LC_ALIASES.Remove($x); Remove-Item "function:$x" -ErrorAction SilentlyContinue }
        elseif (Test-Path "alias:$x") { Remove-Item "alias:$x" -Force }
        else { _lc_err 'unalias' "${x}: not found" }
    }
}
function global:ll { ls -alF @args }
function global:la { ls -A @args }
function global:l { ls -CF @args }

# source FILE: .ps1 is dot-sourced (the Enter rewrite turns `source x.ps1` into `. x.ps1` so it lands in
# the global scope); a bash rc file has its alias/export/VAR= lines applied, the rest is skipped.
function global:source {
    if (-not $args.Count) { _lc_err 'source' 'filename argument required' 2; return }
    $f = _lc_winpath "$($args[0])"
    if (-not (Test-Path -LiteralPath $f)) { _lc_err 'source' "${f}: No such file or directory"; return }
    if ($f -match '\.ps1$') { . $f; return }
    foreach ($l in (Get-Content -LiteralPath $f)) {
        $t = $l.Trim()
        if ($t -match '^alias\s+(.+)$') { Invoke-Expression ("alias " + $Matches[1]) }
        elseif ($t -match '^export\s+(.+)$') { Invoke-Expression (_lc_rewrite ("export " + $Matches[1])) }
        elseif ($t -match '^([A-Za-z_]\w*)=(.*)$' -and $t -notmatch '\s') { Invoke-Expression (_lc_rewrite $t) }
        elseif ($t -match '^unalias\s') { Invoke-Expression $t }
    }
}

function global:which {
    $g = _lc_getopt $args 'as' @('all', 'skip-alias', 'skip-functions')
    $rc = 0
    foreach ($n in $g.rest) {
        $found = @()
        $gnuName = if ($global:LC_GNU_CMDS.Contains($n)) { ("$($global:LC_GNU_CMDS[$n])" -split ' ')[0] } else { '' }
        if ($global:LC_GNU_CMDS.Contains($n)) { $p = _lc_gnu_bin $(if ($gnuName) { $gnuName } else { $n }); if ($p) { $found += $p } }
        $found += @(Get-Command $n -CommandType Application -All -ErrorAction SilentlyContinue | ForEach-Object Source)
        if (-not $found.Count) {
            $c = Get-Command $n -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($c) { $found += "${n}: $($c.CommandType.ToString().ToLower())$(if ($c.CommandType -eq 'Alias') { " for $($c.Definition)" })" }
        }
        if (-not $found.Count) { if (-not $g.o.s) { [Console]::Error.WriteLine("which: no $n in ($env:PATH)") }; $rc = 1; continue }
        if (-not $g.o.s) { if ($g.o.a) { $found | Select-Object -Unique } else { $found[0] } }
    }
    $global:LASTEXITCODE = $rc
}

function global:basename {
    $g = _lc_getopt $args 'as:z' @('multiple', 'suffix=', 'zero') @{ multiple = 'a'; suffix = 's'; zero = 'z' }
    $names = @($g.rest); $suf = $g.o.s
    if (-not $g.o.a -and -not $suf -and $names.Count -eq 2) { $suf = $names[1]; $names = @($names[0]) }
    foreach ($p in $names) {
        $t = $p.TrimEnd('/', '\'); if (-not $t) { '/'; continue }
        $b = ($t -split '[\\/]')[-1]
        if ($suf -and $b.EndsWith($suf) -and $b -ne $suf) { $b = $b.Substring(0, $b.Length - $suf.Length) }
        $b
    }
}
function global:dirname {
    foreach ($p in @($args | ForEach-Object { "$_" })) {
        $t = $p.TrimEnd('/', '\')
        $i = [Math]::Max($t.LastIndexOf('/'), $t.LastIndexOf('\'))
        if ($i -lt 0) { '.' } elseif ($i -eq 0) { $t[0] } elseif ($t -match '^[a-zA-Z]:[\\/]?[^\\/]*$') { $t.Substring(0, 3) } else { $t.Substring(0, $i).TrimEnd('/', '\') }
    }
}
function global:realpath {
    $g = _lc_getopt $args 'esmqz' @('canonicalize-existing', 'strip', 'canonicalize-missing', 'quiet', 'relative-to=') @{ 'canonicalize-existing' = 'e'; strip = 's'; 'canonicalize-missing' = 'm'; quiet = 'q' }
    foreach ($p in $g.rest) {
        $w = _lc_winpath $p
        $full = [IO.Path]::GetFullPath([IO.Path]::Combine((Get-Location -PSProvider FileSystem).ProviderPath, $w))
        if (-not $g.o.s) { try { $it = Get-Item -LiteralPath $full -Force -ErrorAction Stop; if ($it.LinkType -and $it.Target) { $full = [IO.Path]::GetFullPath([IO.Path]::Combine((Split-Path $full), @($it.Target)[0])) } } catch {} }
        if ($g.o.e -and -not (Test-Path -LiteralPath $full)) { if (-not $g.o.q) { _lc_err 'realpath' "${p}: No such file or directory" }; continue }
        if ($g.o['relative-to']) { $base = [IO.Path]::GetFullPath((_lc_winpath $g.o['relative-to'])).TrimEnd('\') + '\'; ([Uri]::new($base)).MakeRelativeUri([Uri]::new($full)).ToString().Replace('/', '\') -replace '%20', ' '; continue }
        $full.TrimEnd('\') -replace '^([A-Za-z]:)$', '$1\'
    }
}
function global:readlink {
    $g = _lc_getopt $args 'femnqsvz' @('canonicalize', 'canonicalize-existing', 'canonicalize-missing', 'no-newline') @{ canonicalize = 'f'; 'canonicalize-existing' = 'e'; 'canonicalize-missing' = 'm'; 'no-newline' = 'n' }
    if ($g.o.f -or $g.o.e -or $g.o.m) { realpath @(if ($g.o.e) { '-e' }) @($g.rest); return }
    $rc = 1
    foreach ($p in $g.rest) { $it = Get-Item -LiteralPath (_lc_winpath $p) -Force -ErrorAction SilentlyContinue; if ($it -and $it.LinkType) { @($it.Target)[0]; $rc = 0 } }
    $global:LASTEXITCODE = $rc
}

function global:mktemp {
    $g = _lc_getopt $args 'dqup:t' @('directory', 'quiet', 'dry-run', 'tmpdir=', 'suffix=') @{ directory = 'd'; quiet = 'q'; 'dry-run' = 'u'; tmpdir = 'p' }
    $tpl = if ($g.rest.Count) { $g.rest[0] } else { 'tmp.XXXXXXXXXX' }
    $dir = if ($g.o.p) { _lc_winpath $g.o.p } elseif ($g.o.t -or -not ($tpl -match '[\\/]')) { if ($env:TMPDIR) { _lc_winpath $env:TMPDIR } else { [IO.Path]::GetTempPath() } } else { '' }
    $chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    $rnd = [regex]::Replace($tpl, 'X{3,}$|X{3,}(?=\.)', { param($m) -join (1..$m.Length | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] }) })
    if ($g.o.suffix) { $rnd += $g.o.suffix }
    $path = if ($dir) { Join-Path $dir $rnd } else { _lc_winpath $rnd }
    if (-not $g.o.u) { [void](New-Item -ItemType $(if ($g.o.d) { 'Directory' } else { 'File' }) -Path $path) }
    $path
}

# ln [-s] [-f] TARGET LINK. Symlinks need Developer Mode or admin; directories fall back to a junction.
function global:ln {
    $g = _lc_getopt $args 'sfnvrT' @('symbolic', 'force', 'no-dereference', 'verbose', 'relative') @{ symbolic = 's'; force = 'f'; 'no-dereference' = 'n'; verbose = 'v'; relative = 'r' }
    $o = $g.o; $r = @($g.rest)
    if (-not $r.Count) { _lc_err 'ln' 'missing file operand'; return }
    $target = _lc_winpath $r[0]
    $link = if ($r.Count -gt 1) { _lc_winpath $r[1] } else { Split-Path -Leaf $target }
    if ((Test-Path -LiteralPath $link -PathType Container) -and -not (Get-Item -LiteralPath $link -Force).LinkType) { $link = Join-Path $link (Split-Path -Leaf $target) }
    if (Test-Path -LiteralPath $link) {
        if (-not $o.f) { _lc_err 'ln' "failed to create link '$link': File exists"; return }
        $li = Get-Item -LiteralPath $link -Force
        if ($li.LinkType) { $li.Delete() } else { Remove-Item -LiteralPath $link -Force }
    }
    $abs = if ([IO.Path]::IsPathRooted($target)) { $target } else { Join-Path (Split-Path -Parent ([IO.Path]::GetFullPath((Join-Path (Get-Location).ProviderPath $link)))) $target }
    $isDir = Test-Path -LiteralPath $abs -PathType Container
    if (-not $o.s) {
        if ($isDir) { _lc_err 'ln' "'$target': hard link not allowed for directory"; return }
        _lc_act "New-Item -ItemType HardLink $link -> $target" { [void](New-Item -ItemType HardLink -Path $link -Target $abs -ErrorAction Stop) }
    } else {
        $ok = $false
        try { _lc_act "New-Item -ItemType SymbolicLink $link -> $target" { [void](New-Item -ItemType SymbolicLink -Path $link -Target $target -ErrorAction Stop) }; $ok = $true } catch {}
        if (-not $ok) {
            if ($isDir) { _lc_act "New-Item -ItemType Junction $link -> $abs" { [void](New-Item -ItemType Junction -Path $link -Target $abs -ErrorAction Stop) }; [Console]::Error.WriteLine('ln: no symlink privilege, made a junction instead (turn on Developer Mode, or use sudo, for real symlinks)') }
            else { _lc_err 'ln' 'creating a file symlink needs Developer Mode (Settings > System > For developers) or sudo' }
        }
    }
    if ($o.v) { "'$link' -> '$target'" }
}

function global:man {
    if (-not $args.Count) { 'What manual page do you want?'; return }
    $n = "$($args[-1])"
    if ($global:LC_GNU_CMDS.Contains($n) -and ($e = _lc_gnu_bin (("$($global:LC_GNU_CMDS[$n])" -split ' ')[0], $n | Where-Object { $_ } | Select-Object -First 1))) {
        $txt = & $e --help 2>&1 | Out-String
        $less = _lc_gnu_bin 'less'
        if ($less -and -not [Console]::IsOutputRedirected) { $txt | & $less -R } else { $txt }
        return
    }
    $c = Get-Command $n -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c -and $c.CommandType -in 'Cmdlet', 'Function' -and -not $c.Name.StartsWith('_lc') -and $c.ScriptBlock.File -notlike "$global:LC_HOME*") { Get-Help $n -Full | Out-Host -Paging; return }
    if ($c -and $c.CommandType -eq 'Function') { "$n (linux-compat): Linux command emulated on Windows. Supported flags are listed in $global:LC_HOME\README.md."; return }
    if ($c -and $c.CommandType -eq 'Application') { & $c.Source /? 2>&1 | Out-Host -Paging; return }
    _lc_err 'man' "No manual entry for $n" 16
}

# read [-p prompt] [-s] [-r] [-a] [-n N] [VAR...]  -> sets $VAR (default $REPLY) in the global scope.
function global:read {
    $g = _lc_getopt $args 'p:srat:n:d:' @()
    $o = $g.o
    if ($o.p) { [Console]::Out.Write($o.p) }
    $line = if ($o.s) { $ss = Read-Host -AsSecureString; [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($ss)) }
            elseif ($o.n) { -join (1..[int]$o.n | ForEach-Object { [Console]::ReadKey($false).KeyChar }); '' | Out-Null }
            else { [Console]::ReadLine() }
    if ($o.n) { [Console]::Out.WriteLine() }
    $names = @($g.rest); if (-not $names.Count) { $names = @('REPLY') }
    if ($o.a) { Set-Variable -Name $names[0] -Scope Global -Value @("$line".Trim() -split '\s+'); return }
    $parts = @("$line".Trim() -split '\s+', $names.Count)
    for ($i = 0; $i -lt $names.Count; $i++) { Set-Variable -Name $names[$i] -Scope Global -Value $(if ($i -lt $parts.Count) { $parts[$i] } else { '' }) }
}

# Background jobs: `cmd &` (rewritten to _lc_bg), jobs, fg, bg.
function global:_lc_bg([string]$b64) {
    $line = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64))
    $j = Start-Job -ScriptBlock { param($h, $d, $l) Set-Location -LiteralPath $d; . (Join-Path $h 'linux-compat.ps1') -NonInteractive; Invoke-Expression $l } -ArgumentList $global:LC_HOME, (Get-Location).ProviderPath, $line
    "[$($j.Id)] $line"
}
function global:jobs { Get-Job | ForEach-Object { '[{0}]  {1,-10} {2}' -f $_.Id, $(if ($_.State -eq 'Running') { 'Running' } else { 'Done' }), $_.Command.Trim() } }
function global:fg { $id = if ($args.Count) { [int]("$($args[0])".TrimStart('%')) } else { (Get-Job | Select-Object -Last 1).Id }; if ($id) { Receive-Job -Id $id -Wait -AutoRemoveJob } }
function global:bg { }

# bash for/while/if/case lines are handed to Git's bash as a whole.
function global:_lc_bashline([string]$b64) {
    $line = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64))
    $bash = _lc_gnu_bin 'bash'
    if (-not $bash) { _lc_err 'linux-compat' 'that line is bash syntax and no bash was found (install Git for Windows)'; return }
    $f = Join-Path $global:LC_STATE 'bash-line.sh'
    [IO.File]::WriteAllText($f, $line + "`n", (New-Object Text.UTF8Encoding $false))
    $old = $env:PATH; $env:PATH = "$global:LC_GNU;$old"
    try { & $bash $f } finally { $env:PATH = $old }
}

# ---------- line rewriting ----------

# Split $line at top-level (outside quotes/brackets) && || ; and a trailing &. Returns @{segs; ops}.
function global:_lc_split_line([string]$line) {
    $segs = New-Object System.Collections.Generic.List[string]; $ops = New-Object System.Collections.Generic.List[string]
    $sb = New-Object System.Text.StringBuilder; $q = [char]0; $depth = 0; $i = 0
    while ($i -lt $line.Length) {
        $c = $line[$i]
        if ($q) {
            if ($c -eq '`' -and $q -eq '"' -and $i + 1 -lt $line.Length) { [void]$sb.Append($c).Append($line[$i + 1]); $i += 2; continue }
            if ($c -eq $q) { $q = [char]0 }
            [void]$sb.Append($c); $i++; continue
        }
        if ($c -eq "'" -or $c -eq '"') { $q = $c; [void]$sb.Append($c); $i++; continue }
        if (($c -eq '`' -or ($c -eq '\' -and $line[$i + 1] -eq ';')) -and $i + 1 -lt $line.Length) { [void]$sb.Append($c).Append($line[$i + 1]); $i += 2; continue }
        if ($c -in '(', '{', '[') { $depth++ } elseif ($c -in ')', '}', ']') { $depth-- }
        if ($depth -eq 0) {
            $two = if ($i + 1 -lt $line.Length) { $line.Substring($i, 2) } else { '' }
            if ($two -eq '&&' -or $two -eq '||') { $segs.Add($sb.ToString()); $ops.Add($two); [void]$sb.Clear(); $i += 2; continue }
            if ($c -eq ';') { $segs.Add($sb.ToString()); $ops.Add(';'); [void]$sb.Clear(); $i++; continue }
            if ($c -eq '&' -and $two -ne '&>' -and ($i -eq 0 -or $line[$i - 1] -notin '>', '2', '*', '1') -and $line.Substring($i + 1).Trim() -eq '') { $segs.Add($sb.ToString()); $ops.Add('&'); [void]$sb.Clear(); $i++; continue }
        }
        [void]$sb.Append($c); $i++
    }
    $segs.Add($sb.ToString())
    @{ segs = $segs.ToArray(); ops = $ops.ToArray() }
}

function global:_lc_parse_errors([string]$line) {
    $t = $null; $e = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($line, [ref]$t, [ref]$e)
    @($e)
}

# Apply $fn to the parts of $line outside single quotes.
function global:_lc_outside_sq([string]$line, [scriptblock]$fn) {
    $parts = [regex]::Split($line, "('(?:[^']|'')*')")
    -join ($parts | ForEach-Object { if ($_.StartsWith("'") -and $_.EndsWith("'") -and $_.Length -ge 2) { $_ } else { & $fn $_ } })
}

# Is $w one of linux-compat's commands (so its args are meant bash-style)?
function global:_lc_is_ours([string]$w) {
    if ($global:LC_GNU_CMDS.Contains($w)) { return $true }
    $c = Get-Command $w -CommandType Function -ErrorAction SilentlyContinue
    $c -and $c.ScriptBlock.File -and $c.ScriptBlock.File.StartsWith($global:LC_HOME)
}

# For our commands, quote bare words PowerShell would mangle: -f2,3 (array), -d: (colon param),
# {} and \; (find -exec), @x. Works per pipeline element.
function global:_lc_quote_args([string]$seg) {
    $out = New-Object System.Text.StringBuilder
    $elems = New-Object System.Collections.Generic.List[string]; $cur = New-Object System.Text.StringBuilder; $q = [char]0; $d = 0
    foreach ($c in $seg.ToCharArray()) {
        if ($q) { if ($c -eq $q) { $q = [char]0 }; [void]$cur.Append($c); continue }
        if ($c -eq "'" -or $c -eq '"') { $q = $c } elseif ($c -eq '(') { $d++ } elseif ($c -eq ')') { $d-- }
        if ($c -eq '|' -and $d -eq 0) { $elems.Add($cur.ToString()); [void]$cur.Clear(); continue }
        [void]$cur.Append($c)
    }
    $elems.Add($cur.ToString())
    $res = foreach ($e in $elems) {
        $toks = [regex]::Matches($e, "(\s+)|('(?:[^']|'')*'|`"(?:[^`"``]|``.)*`"|\$\([^)]*\)|[^\s'`"]+)+")
        $first = ($toks | Where-Object { $_.Value.Trim() } | Select-Object -First 1).Value
        if (-not $first -or -not (_lc_is_ours $first.Trim())) { $e; continue }
        $seen = $false
        -join ($toks | ForEach-Object {
                $t = $_.Value
                if (-not $t.Trim() -or -not $seen) { if ($t.Trim()) { $seen = $true }; return $t }
                if ($t -match '^[''"$(]' -or $t.Contains('$(')) { return $t }
                if ($t -eq '\;') { return "';'" }
                if ($t -match '[,{}@]' -or $t -match '^-[\w-]*:$' -or $t -match '^-\w+:\S') { return "'" + $t.Replace("'", "''") + "'" }
                $t
            })
    }
    $res -join '|'
}

# Rewrites inside one command segment (no && || ; left in it).
function global:_lc_rewrite_seg([string]$s, [string]$full) {
    if ($s.Trim() -eq '') { return $s }
    $lead = [regex]::Match($s, '^\s*').Value; $body = $s.Substring($lead.Length)

    # source file.ps1 / . file.sh
    if ($body -match '^(?:source|\.)\s+(\S+)\s*$') {
        $f = $Matches[1]
        if ($f -match '\.ps1[''"]?$') { if ($body.StartsWith('source')) { return "$lead. $f" } }
        elseif ($body.StartsWith('.')) { return "${lead}source $f" }
    }

    # VAR=value [VAR2=value2] [command...]
    $assign = '^((?:[A-Za-z_][A-Za-z0-9_]*=(?:''[^'']*''|"(?:[^"`]|`.)*"|[^\s''"]*)\s*)+)(.*)$'
    if ($body -match $assign -and $body -notmatch '^\S+==') {
        $vars = [regex]::Matches($Matches[1], '([A-Za-z_][A-Za-z0-9_]*)=(''[^'']*''|"(?:[^"`]|`.)*"|[^\s''"]*)')
        $cmd = $Matches[2].Trim()
        $val = { param($v) if ($v.StartsWith("'") -or $v.StartsWith('"')) { $v } else { '"' + $v + '"' } }
        if (-not $cmd) {
            return $lead + (($vars | ForEach-Object { "`$$($_.Groups[1].Value) = $(& $val $_.Groups[2].Value)" }) -join '; ')
        }
        $save = ($vars | ForEach-Object { $n = $_.Groups[1].Value; "'$n' = `$env:$n" }) -join '; '
        $set = ($vars | ForEach-Object { $n = $_.Groups[1].Value; "`$env:$n = $(& $val $_.Groups[2].Value)" }) -join '; '
        $restore = ($vars | ForEach-Object { $n = $_.Groups[1].Value; "`$env:$n = `$__lc_env['$n']" }) -join '; '
        $inner = _lc_rewrite_seg $cmd $full
        return "$lead`$__lc_env = @{ $save }; $set; try { $inner } finally { $restore }"
    }

    # cmd < file  ->  Get-Content file | cmd
    if ($body -match '^(.*?)\s<\s*("[^"]+"|''[^'']+''|.+?)\s*$' -and $body -notmatch '<<' -and (_lc_parse_errors $body).Count) {
        return "${lead}Get-Content -LiteralPath $(_lc_q (_lc_winpath $Matches[2].Trim('''"'))) | $(_lc_quote_args $Matches[1])"
    }
    $lead + (_lc_quote_args $body)
}

# Whole-line rewrite. Returns the line to run (unchanged if nothing applies).
function global:_lc_rewrite([string]$line) {
    if ($line.Trim() -eq '' -or $line.TrimStart().StartsWith('#')) { return $line }
    $orig = $line

    # !! and !$ (history), outside single quotes
    if ($line -match '!!|!\$') {
        $prev = $null
        try { $h = [Microsoft.PowerShell.PSConsoleReadLine]::GetHistoryItems(); if ($h.Count) { $prev = $h[$h.Count - 1].CommandLine } } catch {}
        if (-not $prev) { $prev = (Get-History -Count 1).CommandLine }
        if ($prev) {
            $lastArg = (_lc_split_line $prev).segs[-1].Trim() -split '\s+' | Select-Object -Last 1
            $line = _lc_outside_sq $line { param($p) $p.Replace('!!', $prev).Replace('!$', $lastArg) }
        }
    }

    # /dev/null redirections, &> file
    $line = _lc_outside_sq $line {
        param($p)
        $p = [regex]::Replace($p, '&>>\s*/dev/null|&>\s*/dev/null', '*>$$null')
        $p = [regex]::Replace($p, '(\d?)>>?\s*/dev/null', '$1>$$null')
        $p = [regex]::Replace($p, '(?<![\w*])&>(?!>)', '*>')
        $p = [regex]::Replace($p, '(?<![\w*])&>>', '*>>')
        $p
    }

    # $UPPERCASE env vars that aren't PowerShell variables -> ${env:NAME}
    $line = _lc_outside_sq $line {
        param($p)
        [regex]::Replace($p, '\$(?:\{([A-Z_][A-Z0-9_]*)\}|([A-Z_][A-Z0-9_]*)\b)(?!:)', {
                param($m)
                $n = if ($m.Groups[1].Success) { $m.Groups[1].Value } else { $m.Groups[2].Value }
                if ($n -cne $n.ToUpper() -or $n -eq '_') { return $m.Value }
                if (Get-Variable -Name $n -Scope Global -ErrorAction SilentlyContinue) { return $m.Value }
                if ($line -match "\`$$n\s*=|\(\s*\`$$n\s+in\b") { return $m.Value }
                if ($null -eq [Environment]::GetEnvironmentVariable($n)) { return $m.Value }
                '${env:' + $n + '}'
            })
    }

    $sp = _lc_split_line $line
    $segs = @($sp.segs | ForEach-Object { _lc_rewrite_seg $_ $line })
    $ops = @($sp.ops)
    $needChain = ($ops -contains '&&') -or ($ops -contains '||')
    $bg = $ops.Count -and $ops[-1] -eq '&'

    if ($needChain -or $bg -or (($segs -join '') -ne ($sp.segs -join ''))) {
        $out = ''; $ok = '$__lc_ok'
        for ($i = 0; $i -lt $segs.Count; $i++) {
            $seg = $segs[$i].Trim(); if ($seg -eq '' -and $i -eq $segs.Count - 1) { continue }
            $op = if ($i -gt 0) { $ops[$i - 1] } else { ';' }
            if ($op -eq '&') { continue }
            if ($i -eq $segs.Count - 2 -and $bg -and $ops[$i] -eq '&') {
                $seg = "_lc_bg '" + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($seg)) + "'"
            }
            $run = if ($needChain) { "`$global:LASTEXITCODE = 0; $seg; $ok = (`$? -and `$global:LASTEXITCODE -eq 0)" } else { $seg }
            if ($i -eq 0 -or $op -eq ';') { $out += $(if ($out) { '; ' } else { '' }) + $run }
            elseif ($op -eq '&&') { $out += "; if ($ok) { $run }" }
            elseif ($op -eq '||') { $out += "; if (-not $ok) { $run }" }
        }
        if ($bg -and $segs.Count -eq 2 -and -not $needChain) { $out = "_lc_bg '" + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($segs[0].Trim())) + "'" }
        $line = $out
    }

    # Still not PowerShell, and looks like bash -> run the original line in bash.
    if ((_lc_parse_errors $line).Count -and $orig -match '\b(do|done|then|fi|esac|elif)\b|\[\[|\$\(\(|`[^`]+`|<<<|^\s*function\s+\w+\s*\(\)|^\s*\w+\s*\(\)\s*\{|\$\{#|\$\{\w+[,^]{1,2}\}|\$\{!') {
        return "_lc_bashline '" + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($orig)) + "'"
    }
    if ($line -ne $orig -and (_lc_parse_errors $line).Count -and -not (_lc_parse_errors $orig).Count) { return $orig }
    $line
}

# Enter key: rewrite, keep what was typed in history, show the translation when debug is on.
function global:_lc_install_readline {
    if (-not (Get-Module PSReadLine)) { return }
    $global:__lc_skiphist = $null
    Set-PSReadLineOption -AddToHistoryHandler {
        param($l)
        if ($null -ne $global:__lc_skiphist -and $l -eq $global:__lc_skiphist) { $global:__lc_skiphist = $null; return $false }
        $true
    }
    Set-PSReadLineKeyHandler -Key Enter -BriefDescription 'linux-compat AcceptLine' -ScriptBlock {
        $line = $null; $cur = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cur)
        $new = $line
        if (-not (_lc_state 'disabled')) { try { $new = _lc_rewrite $line } catch { $new = $line } }
        if ($new -ne $line) {
            # Incomplete input (open quote/brace) is left alone so multi-line editing still works.
            $err = _lc_parse_errors $line
            if ($err | Where-Object { $_.IncompleteInput }) { [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine(); return }
            # History keeps what was typed; the screen shows what runs.
            [Microsoft.PowerShell.PSConsoleReadLine]::AddToHistory($line)
            $global:__lc_skiphist = $new
            [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $line.Length, $new)
        }
        [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
    }
}
