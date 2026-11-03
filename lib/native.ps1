# linux-compat for Windows: native fallbacks for the GNU commands, used when no GNU tools are found
# (or LC_NOGNU=1). They cover the common flags, not everything. Args arrive as strings; piped text
# arrives as $input lines.

function global:_lc_lines([string[]]$files, $inp, [string]$cmd) {
    if (-not $files -or $files.Count -eq 0 -or ($files.Count -eq 1 -and $files[0] -eq '-')) { return @($inp) }
    foreach ($f in (_lc_glob $files)) {
        if ($f -eq '-') { $inp; continue }
        if (Test-Path -LiteralPath $f -PathType Leaf) { Get-Content -LiteralPath $f }
        else { _lc_err $cmd "${f}: No such file or directory" }
    }
}

function global:_lc_n_cat {
    $g = _lc_getopt $args 'nbsAvET' @('number', 'squeeze-blank') @{ number = 'n'; 'squeeze-blank' = 's' }
    $n = 0; $prevBlank = $false
    foreach ($l in (_lc_lines $g.rest $input 'cat')) {
        if ($g.o.s -and $l -eq '' -and $prevBlank) { continue }
        $prevBlank = ($l -eq '')
        if ($g.o.n -or ($g.o.b -and $l -ne '')) { $n++; '{0,6}  {1}' -f $n, $l } else { $l }
    }
}

function global:_lc_n_ls {
    $g = _lc_getopt $args 'laAhR1tSrdF' @('all', 'almost-all', 'human-readable', 'recursive', 'reverse', 'directory', 'color=') @{ all = 'a'; 'almost-all' = 'A'; 'human-readable' = 'h'; recursive = 'R'; reverse = 'r'; directory = 'd' }
    $o = $g.o
    $paths = @($g.rest); if (-not $paths.Count) { $paths = @('.') }
    $paths = @(_lc_glob $paths)
    $show = {
        param($items)
        $items = @($items | Where-Object { $o.a -or $o.A -or (-not $_.Name.StartsWith('.') -and -not ($_.Attributes -band [IO.FileAttributes]::Hidden)) })
        if ($o.t) { $items = @($items | Sort-Object LastWriteTime -Descending) }
        elseif ($o.S) { $items = @($items | Sort-Object { if ($_.PSIsContainer) { 0 } else { $_.Length } } -Descending) }
        else { $items = @($items | Sort-Object Name) }
        if ($o.r) { [array]::Reverse($items) }
        if ($o.l) {
            foreach ($i in $items) {
                $mode = if ($i.PSIsContainer) { 'd' } else { '-' }
                $mode += if ($i.Attributes -band [IO.FileAttributes]::ReadOnly) { 'r-xr-xr-x' } else { 'rwxr-xr-x' }
                $size = if ($i.PSIsContainer) { 0 } else { $i.Length }
                $sz = if ($o.h) { _lc_human $size } else { "$size" }
                $when = if ($i.LastWriteTime -lt (Get-Date).AddMonths(-6)) { $i.LastWriteTime.ToString('MMM dd  yyyy') } else { $i.LastWriteTime.ToString('MMM dd HH:mm') }
                $nm = $i.Name; if ($o.F -and $i.PSIsContainer) { $nm += '/' }
                '{0} 1 {1,-8} {2,8} {3} {4}' -f $mode, $env:USERNAME, $sz, $when, $nm
            }
        } else {
            $names = @($items | ForEach-Object { $_.Name + $(if ($o.F -and $_.PSIsContainer) { '/' }) })
            if ($o.'1' -or [Console]::IsOutputRedirected -or $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength) { $names }
            elseif ($names.Count) {
                $w = ($names | Measure-Object -Property Length -Maximum).Maximum + 2
                $cols = [Math]::Max(1, [int][Math]::Floor(([Console]::WindowWidth - 1) / $w))
                $rows = [Math]::Ceiling($names.Count / $cols)
                for ($r = 0; $r -lt $rows; $r++) {
                    $line = ''
                    for ($c = 0; $c -lt $cols; $c++) { $k = $c * $rows + $r; if ($k -lt $names.Count) { $line += $names[$k].PadRight($w) } }
                    $line.TrimEnd()
                }
            }
        }
    }
    $multi = $paths.Count -gt 1 -or $o.R
    foreach ($p in $paths) {
        $it = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
        if (-not $it) { _lc_err 'ls' "cannot access '$p': No such file or directory" 2; continue }
        if (-not $it.PSIsContainer -or $o.d) { & $show @($it); continue }
        $dirs = if ($o.R) { @($it) + @(Get-ChildItem -LiteralPath $p -Recurse -Directory -Force -ErrorAction SilentlyContinue) } else { @($it) }
        foreach ($d in $dirs) {
            if ($multi) { "$($d.FullName):" }
            & $show (Get-ChildItem -LiteralPath $d.FullName -Force -ErrorAction SilentlyContinue)
            if ($multi) { '' }
        }
    }
}

function global:_lc_n_grep {
    $g = _lc_getopt $args 'ivnclLrREFwxoqshHe:A:B:C:m:P' @('ignore-case', 'invert-match', 'line-number', 'count', 'files-with-matches', 'recursive', 'extended-regexp', 'fixed-strings', 'word-regexp', 'line-regexp', 'only-matching', 'quiet', 'silent', 'no-filename', 'with-filename', 'regexp=', 'include=', 'exclude=', 'color=', 'colour=', 'max-count=') @{ 'ignore-case' = 'i'; 'invert-match' = 'v'; 'line-number' = 'n'; count = 'c'; 'files-with-matches' = 'l'; recursive = 'r'; 'extended-regexp' = 'E'; 'fixed-strings' = 'F'; 'word-regexp' = 'w'; 'line-regexp' = 'x'; 'only-matching' = 'o'; quiet = 'q'; silent = 'q'; 'no-filename' = 'h'; 'with-filename' = 'H'; regexp = 'e'; 'max-count' = 'm' }
    $o = $g.o; $rest = @($g.rest)
    if ($o.e) { $pat = $o.e } elseif ($rest.Count) { $pat = $rest[0]; $rest = @($rest | Select-Object -Skip 1) } else { _lc_err 'grep' 'no pattern' 2; return }
    if ($o.F) { $pat = [regex]::Escape($pat) }
    elseif (-not $o.E -and -not $o.P) { $pat = $pat -replace '\\([|(){}+?])', '$1' }  # BRE \| \( -> ERE
    if ($o.w) { $pat = "\b(?:$pat)\b" }
    if ($o.x) { $pat = "^(?:$pat)$" }
    $opt = if ($o.i) { 'IgnoreCase' } else { 'None' }
    $re = [regex]::new($pat, $opt)
    $files = @()
    if ($o.r -or $o.R) {
        if (-not $rest.Count) { $rest = @('.') }
        foreach ($p in (_lc_glob $rest)) {
            if (Test-Path -LiteralPath $p -PathType Container) {
                $files += Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { (-not $o.include -or $_.Name -like $o.include) -and (-not $o.exclude -or $_.Name -notlike $o.exclude) } | ForEach-Object { $_.FullName }
            } else { $files += $p }
        }
    } else { $files = @(_lc_glob $rest) }
    $showName = ($files.Count -gt 1 -or $o.r -or $o.R -or $o.H) -and -not $o.h
    $found = $false
    $srcs = if ($files.Count) { $files } else { @('-') }
    foreach ($f in $srcs) {
        $lines = if ($f -eq '-') { @($input) } elseif (Test-Path -LiteralPath $f -PathType Leaf) { Get-Content -LiteralPath $f -ErrorAction SilentlyContinue } else { if (-not $o.s) { _lc_err 'grep' "${f}: No such file or directory" 2 }; continue }
        $label = if ($f -eq '-') { '(standard input)' } else { $f }
        $cnt = 0; $ln = 0
        foreach ($l in $lines) {
            $ln++
            $m = $re.IsMatch("$l")
            if ($m -eq [bool]$o.v) { continue }
            $cnt++; $found = $true
            if ($o.q) { $global:LASTEXITCODE = 0; return }
            if ($o.l -or $o.c) { if ($o.m -and $cnt -ge [int]$o.m) { break }; continue }
            $pre = ''
            if ($showName) { $pre += "${label}:" }
            if ($o.n) { $pre += "${ln}:" }
            if ($o.o -and -not $o.v) { foreach ($mm in $re.Matches("$l")) { "$pre$($mm.Value)" } } else { "$pre$l" }
            if ($o.m -and $cnt -ge [int]$o.m) { break }
        }
        if ($o.l -and $cnt) { $label }
        if ($o.c) { if ($showName) { "${label}:$cnt" } else { "$cnt" } }
    }
    $global:LASTEXITCODE = if ($found) { 0 } else { 1 }
}
function global:_lc_n_egrep { $input | _lc_n_grep -E @args }
function global:_lc_n_fgrep { $input | _lc_n_grep -F @args }

function global:_lc_n_head {
    $g = _lc_getopt $args 'n:c:qv' @('lines=', 'bytes=') @{ lines = 'n'; bytes = 'c' } -numeric
    $n = if ($null -ne $g.o['#']) { $g.o['#'] } elseif ($g.o.n) { [int]$g.o.n } else { 10 }
    $files = @($g.rest)
    $srcs = if ($files.Count) { _lc_glob $files } else { @('-') }
    foreach ($f in $srcs) {
        if (@($srcs).Count -gt 1) { "==> $f <==" }
        $lines = @(if ($f -eq '-') { $input } else { Get-Content -LiteralPath $f -TotalCount $(if ($n -ge 0) { $n } else { [int]::MaxValue }) })
        if ($n -lt 0) { $lines | Select-Object -First ([Math]::Max(0, $lines.Count + $n)) } else { $lines | Select-Object -First $n }
    }
}

function global:_lc_n_tail {
    $g = _lc_getopt $args 'n:fFq' @('lines=', 'follow') @{ lines = 'n'; follow = 'f' } -numeric
    $spec = if ($null -ne $g.o['#']) { "$($g.o['#'])" } elseif ($g.o.n) { "$($g.o.n)" } else { '10' }
    $fromStart = $spec.StartsWith('+'); $n = [int]$spec.TrimStart('+')
    $files = @($g.rest)
    if ($g.o.f -or $g.o.F) {
        if (-not $files.Count) { _lc_err 'tail' '-f needs a file'; return }
        Get-Content -LiteralPath (_lc_winpath $files[0]) -Tail $n -Wait
        return
    }
    $srcs = if ($files.Count) { _lc_glob $files } else { @('-') }
    foreach ($f in $srcs) {
        if (@($srcs).Count -gt 1) { "==> $f <==" }
        $lines = @(if ($f -eq '-') { $input } else { Get-Content -LiteralPath $f })
        if ($fromStart) { $lines | Select-Object -Skip ([Math]::Max(0, $n - 1)) } else { $lines | Select-Object -Last $n }
    }
}

function global:_lc_n_wc {
    $g = _lc_getopt $args 'lwcmL' @('lines', 'words', 'bytes', 'chars') @{ lines = 'l'; words = 'w'; bytes = 'c'; chars = 'm' }
    $o = $g.o; $all = -not ($o.l -or $o.w -or $o.c -or $o.m)
    $fmt = {
        param($l, $w, $c, $name)
        $p = @(); if ($all -or $o.l) { $p += '{0,7}' -f $l }; if ($all -or $o.w) { $p += '{0,7}' -f $w }; if ($all -or $o.c -or $o.m) { $p += '{0,7}' -f $c }
        (($p -join ' ') + $(if ($name) { " $name" })).TrimStart()
    }
    $files = @($g.rest)
    if (-not $files.Count) {
        $t = (@($input) -join "`n") + "`n"; if ($t -eq "`n") { $t = '' }
        & $fmt ([regex]::Matches($t, "`n").Count) ([regex]::Matches($t, '\S+').Count) ([Text.Encoding]::UTF8.GetByteCount($t)) ''
        return
    }
    $tl = 0; $tw = 0; $tc = 0
    foreach ($f in (_lc_glob $files)) {
        if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { _lc_err 'wc' "${f}: No such file or directory"; continue }
        $b = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $f).ProviderPath); $t = [Text.Encoding]::UTF8.GetString($b)
        $l = ([regex]::Matches($t, "`n")).Count; $w = ([regex]::Matches($t, '\S+')).Count; $c = if ($o.m) { $t.Length } else { $b.Length }
        $tl += $l; $tw += $w; $tc += $c
        & $fmt $l $w $c $f
    }
    if (@(_lc_glob $files).Count -gt 1) { & $fmt $tl $tw $tc 'total' }
}

function global:_lc_n_sort {
    $g = _lc_getopt $args 'rnufk:t:hV' @('reverse', 'numeric-sort', 'unique', 'ignore-case', 'key=', 'field-separator=', 'human-numeric-sort', 'version-sort') @{ reverse = 'r'; 'numeric-sort' = 'n'; unique = 'u'; 'ignore-case' = 'f'; key = 'k'; 'field-separator' = 't'; 'human-numeric-sort' = 'h'; 'version-sort' = 'V' }
    $o = $g.o
    $lines = @(_lc_lines $g.rest $input 'sort')
    $key = { param($l) $l }
    if ($o.k) {
        $fld = [int](($o.k -split '[,.]')[0]) - 1; $sep = $o.t
        $key = { param($l) $parts = if ($sep) { $l -split [regex]::Escape($sep) } else { "$l".Trim() -split '\s+' }; if ($fld -lt $parts.Count) { $parts[$fld] } else { '' } }.GetNewClosure()
    }
    $val = if ($o.n -or $o.h) { { $s = & $key $_; $d = 0.0; if ([double]::TryParse(($s -replace '[KMGTP]$', ''), [ref]$d)) { $m = @{ K = 1e3; M = 1e6; G = 1e9; T = 1e12; P = 1e15 }[[string]($s[-1])]; if ($o.h -and $m) { $d * $m } else { $d } } else { 0 } }.GetNewClosure() }
    elseif ($o.V) { { [regex]::Replace((& $key $_), '\d+', { $args[0].Value.PadLeft(20, '0') }) }.GetNewClosure() }
    else { { & $key $_ }.GetNewClosure() }
    $sorted = @($lines | Sort-Object -Property $val -Descending:([bool]$o.r) -CaseSensitive:(-not $o.f))
    if ($o.u) { $seen = @{}; $sorted | Where-Object { $k = "$(& $key $_)"; if (-not $o.f) { $k = "$k|" + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($k)) }; if (-not $seen.ContainsKey($k)) { $seen[$k] = 1; $true } } } else { $sorted }
}

function global:_lc_n_uniq {
    $g = _lc_getopt $args 'cdui' @('count', 'repeated', 'unique', 'ignore-case') @{ count = 'c'; repeated = 'd'; unique = 'u'; 'ignore-case' = 'i' }
    $o = $g.o; $prev = $null; $n = 0
    $emit = { if ($null -ne $prev) { if ((-not $o.d -or $n -gt 1) -and (-not $o.u -or $n -eq 1)) { if ($o.c) { '{0,7} {1}' -f $n, $prev } else { $prev } } } }
    foreach ($l in (_lc_lines @($g.rest | Select-Object -First 1) $input 'uniq')) {
        $same = $null -ne $prev -and $(if ($o.i) { $l -eq $prev } else { $l -ceq $prev })
        if ($same) { $n++ } else { & $emit; $prev = $l; $n = 1 }
    }
    & $emit
}

function global:_lc_n_cut {
    $g = _lc_getopt $args 'd:f:c:s' @('delimiter=', 'fields=', 'characters=', 'only-delimited') @{ delimiter = 'd'; fields = 'f'; characters = 'c'; 'only-delimited' = 's' }
    $o = $g.o
    $sel = { param($spec, $max) foreach ($r in ($spec -split ',')) { if ($r -match '^(\d*)-(\d*)$') { $a = if ($Matches[1]) { [int]$Matches[1] } else { 1 }; $b = if ($Matches[2]) { [int]$Matches[2] } else { $max }; for ($i = $a; $i -le [Math]::Min($b, $max); $i++) { $i } } else { [int]$r } } }
    $d = if ($null -ne $o.d) { $o.d } else { "`t" }
    foreach ($l in (_lc_lines $g.rest $input 'cut')) {
        if ($o.c) { $ch = $l.ToCharArray(); (@(& $sel $o.c $ch.Count) | Where-Object { $_ -le $ch.Count } | ForEach-Object { $ch[$_ - 1] }) -join '' }
        elseif ($o.f) {
            if (-not $l.Contains($d)) { if (-not $o.s) { $l }; continue }
            $p = $l.Split([string[]]@($d), 'None')
            (@(& $sel $o.f $p.Count) | Where-Object { $_ -le $p.Count } | ForEach-Object { $p[$_ - 1] }) -join $d
        }
    }
}

function global:_lc_trset([string]$s) {
    $s = $s -replace '\[:upper:\]', 'A-Z' -replace '\[:lower:\]', 'a-z' -replace '\[:digit:\]', '0-9' -replace '\[:space:\]', " `t`r`n" -replace '\[:alpha:\]', 'A-Za-z' -replace '\[:alnum:\]', 'A-Za-z0-9'
    $s = $s.Replace('\n', "`n").Replace('\t', "`t").Replace('\r', "`r").Replace('\\', '\')
    $out = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $s.Length; $i++) {
        if ($i + 2 -lt $s.Length -and $s[$i + 1] -eq '-') { for ($c = [int]$s[$i]; $c -le [int]$s[$i + 2]; $c++) { [void]$out.Append([char]$c) }; $i += 2 }
        else { [void]$out.Append($s[$i]) }
    }
    $out.ToString()
}
function global:_lc_n_tr {
    $g = _lc_getopt $args 'dsc' @('delete', 'squeeze-repeats') @{ delete = 'd'; 'squeeze-repeats' = 's' }
    $s1 = _lc_trset $g.rest[0]; $s2 = if ($g.rest.Count -gt 1) { _lc_trset $g.rest[1] } else { '' }
    $text = (@($input) -join "`n")
    $sb = New-Object System.Text.StringBuilder; $last = [char]0
    foreach ($ch in $text.ToCharArray()) {
        $k = $s1.IndexOf($ch)
        if ($g.o.d) { if ($k -ge 0) { continue }; [void]$sb.Append($ch); continue }
        if ($k -ge 0 -and $s2) { $ch = $s2[[Math]::Min($k, $s2.Length - 1)] }
        if ($g.o.s -and $ch -eq $last -and ($s2.IndexOf($ch) -ge 0 -or (-not $s2 -and $k -ge 0))) { continue }
        [void]$sb.Append($ch); $last = $ch
    }
    $sb.ToString() -split "`n"
}

function global:_lc_n_tee {
    $g = _lc_getopt $args 'a' @('append') @{ append = 'a' }
    $lines = @($input)
    foreach ($f in $g.rest) { $p = _lc_winpath $f; if ($g.o.a) { $lines | Add-Content -LiteralPath $p } else { $lines | Set-Content -LiteralPath $p } }
    $lines
}

function global:_lc_n_touch {
    $g = _lc_getopt $args 'cd:t:' @('no-create', 'date=') @{ 'no-create' = 'c'; date = 'd' }
    $when = if ($g.o.d) { [datetime]::Parse($g.o.d) } else { Get-Date }
    foreach ($f in $g.rest) {
        $p = _lc_winpath $f
        if (Test-Path -LiteralPath $p) { (Get-Item -LiteralPath $p -Force).LastWriteTime = $when }
        elseif (-not $g.o.c) { [void](New-Item -ItemType File -Path $p); (Get-Item -LiteralPath $p).LastWriteTime = $when }
    }
}

function global:_lc_n_rm {
    $g = _lc_getopt $args 'rRfivd' @('recursive', 'force', 'verbose', 'dir') @{ recursive = 'r'; force = 'f'; verbose = 'v'; dir = 'd' }
    $o = $g.o
    foreach ($p in (_lc_glob $g.rest)) {
        $it = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
        if (-not $it) { if (-not $o.f) { _lc_err 'rm' "cannot remove '$p': No such file or directory" }; continue }
        if ($it.PSIsContainer -and -not ($o.r -or $o.R) -and -not ($o.d -and -not (Get-ChildItem -LiteralPath $p -Force))) { _lc_err 'rm' "cannot remove '$p': Is a directory"; continue }
        Remove-Item -LiteralPath $p -Recurse:([bool]($o.r -or $o.R)) -Force -Confirm:([bool]$o.i) -ErrorAction Continue
        if ($o.v) { "removed '$p'" }
    }
}

function global:_lc_n_cp {
    $g = _lc_getopt $args 'rRafvnpt:T' @('recursive', 'archive', 'force', 'verbose', 'no-clobber', 'target-directory=') @{ recursive = 'r'; archive = 'a'; force = 'f'; verbose = 'v'; 'no-clobber' = 'n'; 'target-directory' = 't' }
    $o = $g.o; $items = @($g.rest)
    if ($o.t) { $dest = _lc_winpath $o.t } else { $dest = _lc_winpath $items[-1]; $items = @($items | Select-Object -SkipLast 1) }
    foreach ($s in (_lc_glob $items)) {
        $it = Get-Item -LiteralPath $s -Force -ErrorAction SilentlyContinue
        if (-not $it) { _lc_err 'cp' "cannot stat '$s': No such file or directory"; continue }
        if ($it.PSIsContainer -and -not ($o.r -or $o.R -or $o.a)) { _lc_err 'cp' "-r not specified; omitting directory '$s'"; continue }
        $target = if (Test-Path -LiteralPath $dest -PathType Container) { Join-Path $dest $it.Name } else { $dest }
        if ($o.n -and (Test-Path -LiteralPath $target)) { continue }
        Copy-Item -LiteralPath $s -Destination $target -Recurse:$it.PSIsContainer -Force
        if ($o.v) { "'$s' -> '$target'" }
    }
}

function global:_lc_n_mv {
    $g = _lc_getopt $args 'fvnit:' @('force', 'verbose', 'no-clobber', 'target-directory=') @{ force = 'f'; verbose = 'v'; 'no-clobber' = 'n'; 'target-directory' = 't' }
    $o = $g.o; $items = @($g.rest)
    if ($o.t) { $dest = _lc_winpath $o.t } else { $dest = _lc_winpath $items[-1]; $items = @($items | Select-Object -SkipLast 1) }
    foreach ($s in (_lc_glob $items)) {
        if (-not (Test-Path -LiteralPath $s)) { _lc_err 'mv' "cannot stat '$s': No such file or directory"; continue }
        $target = if (Test-Path -LiteralPath $dest -PathType Container) { Join-Path $dest (Split-Path -Leaf $s) } else { $dest }
        if ($o.n -and (Test-Path -LiteralPath $target)) { continue }
        if ((Test-Path -LiteralPath $target -PathType Leaf)) { Remove-Item -LiteralPath $target -Force }
        Move-Item -LiteralPath $s -Destination $target -Force
        if ($o.v) { "renamed '$s' -> '$target'" }
    }
}

function global:_lc_n_mkdir {
    $g = _lc_getopt $args 'pvm:' @('parents', 'verbose', 'mode=') @{ parents = 'p'; verbose = 'v'; mode = 'm' }
    foreach ($d in $g.rest) {
        $p = _lc_winpath $d
        if (Test-Path -LiteralPath $p) { if (-not $g.o.p) { _lc_err 'mkdir' "cannot create directory '$d': File exists" }; continue }
        $parent = Split-Path -Parent $p
        if (-not $g.o.p -and $parent -and -not (Test-Path -LiteralPath $parent)) { _lc_err 'mkdir' "cannot create directory '$d': No such file or directory"; continue }
        [void](New-Item -ItemType Directory -Path $p -Force)
        if ($g.o.v) { "mkdir: created directory '$d'" }
    }
}

function global:_lc_n_rmdir {
    $g = _lc_getopt $args 'pv' @('parents', 'verbose', 'ignore-fail-on-non-empty') @{ parents = 'p'; verbose = 'v' }
    foreach ($d in $g.rest) {
        $p = _lc_winpath $d
        if (Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue) { _lc_err 'rmdir' "failed to remove '$d': Directory not empty"; continue }
        Remove-Item -LiteralPath $p
    }
}

# NTFS has no Unix modes: w/-w maps to the read-only attribute, the rest is accepted and ignored.
function global:_lc_n_chmod {
    $g = _lc_getopt $args 'Rvfc' @('recursive', 'verbose') @{ recursive = 'R'; verbose = 'v' }
    $mode = $g.rest[0]
    $ro = $null
    if ($mode -match '^[0-7]{3,4}$') { $ro = -not ([int][string]$mode[-3] -band 2) }
    elseif ($mode -match '-[rwx]*w') { $ro = $true } elseif ($mode -match '\+[rwx]*w') { $ro = $false }
    foreach ($f in (_lc_glob @($g.rest | Select-Object -Skip 1))) {
        if ($null -eq $ro) { continue }
        $items = @(Get-Item -LiteralPath $f -Force); if ($g.o.R) { $items += Get-ChildItem -LiteralPath $f -Recurse -File -Force }
        foreach ($i in $items) { if (-not $i.PSIsContainer) { $i.IsReadOnly = $ro } }
    }
}

function global:_lc_n_find {
    $argv = @($args); $roots = @()
    while ($argv.Count -and $argv[0] -notmatch '^[-!(]') { $roots += $argv[0]; $argv = @($argv | Select-Object -Skip 1) }
    if (-not $roots.Count) { $roots = @('.') }
    $tests = @(); $max = [int]::MaxValue; $min = 0; $delete = $false; $exec = $null
    for ($i = 0; $i -lt $argv.Count; $i++) {
        switch ($argv[$i]) {
            '-name' { $v = $argv[++$i]; $tests += { param($x) $x.Name -clike $v }.GetNewClosure() }
            '-iname' { $v = $argv[++$i]; $tests += { param($x) $x.Name -like $v }.GetNewClosure() }
            '-path' { $v = $argv[++$i]; $tests += { param($x) $x.FullName -like $v }.GetNewClosure() }
            '-type' { $v = $argv[++$i]; $tests += { param($x) if ($v -eq 'd') { $x.PSIsContainer } else { -not $x.PSIsContainer } }.GetNewClosure() }
            '-maxdepth' { $max = [int]$argv[++$i] }
            '-mindepth' { $min = [int]$argv[++$i] }
            '-mtime' { $v = $argv[++$i]; $n = [int]$v.TrimStart('+-'); $sign = $v[0]; $tests += { param($x) $age = ((Get-Date) - $x.LastWriteTime).TotalDays; if ($sign -eq '+') { $age -gt $n + 1 } elseif ($sign -eq '-') { $age -lt $n } else { [int][Math]::Floor($age) -eq $n } }.GetNewClosure() }
            '-size' { $v = $argv[++$i]; if ($v -match '^([+-]?)(\d+)([ckMG]?)$') { $sign = $Matches[1]; $sz = [long]$Matches[2] * @{ '' = 512; c = 1; k = 1KB; M = 1MB; G = 1GB }[$Matches[3]]; $tests += { param($x) if ($x.PSIsContainer) { return $false }; if ($sign -eq '+') { $x.Length -gt $sz } elseif ($sign -eq '-') { $x.Length -lt $sz } else { $x.Length -eq $sz } }.GetNewClosure() } }
            '-empty' { $tests += { param($x) if ($x.PSIsContainer) { -not (Get-ChildItem -LiteralPath $x.FullName -Force) } else { $x.Length -eq 0 } } }
            '-delete' { $delete = $true }
            '-exec' { $exec = @(); $i++; while ($i -lt $argv.Count -and $argv[$i] -ne ';' -and $argv[$i] -ne '+') { $exec += $argv[$i]; $i++ } }
            '-print' { }
            default { _lc_err 'find' "unknown predicate '$($argv[$i])' (no GNU find installed)"; return }
        }
    }
    foreach ($r in $roots) {
        $rp = _lc_winpath $r
        if (-not (Test-Path -LiteralPath $rp)) { _lc_err 'find' "'$r': No such file or directory"; continue }
        $base = (Resolve-Path -LiteralPath $rp).ProviderPath.TrimEnd('\')
        $all = @(Get-Item -LiteralPath $rp -Force) + @(Get-ChildItem -LiteralPath $rp -Recurse -Force -ErrorAction SilentlyContinue)
        foreach ($x in $all) {
            $rel = $x.FullName.Substring([Math]::Min($base.Length, $x.FullName.Length)).TrimStart('\')
            $depth = if ($rel) { ($rel -split '\\').Count } else { 0 }
            if ($depth -gt $max -or $depth -lt $min) { continue }
            $ok = $true; foreach ($t in $tests) { if (-not (& $t $x)) { $ok = $false; break } }
            if (-not $ok) { continue }
            $shown = if ($rel) { (Join-Path $r $rel) -replace '\\', '/' } else { $r }
            if ($delete) { Remove-Item -LiteralPath $x.FullName -Recurse -Force -ErrorAction SilentlyContinue }
            elseif ($exec) { $cmd = @($exec | ForEach-Object { if ($_ -eq '{}') { $x.FullName } else { $_ } }); & $cmd[0] @($cmd | Select-Object -Skip 1) }
            else { $shown }
        }
    }
}

# sed: s///[gip], /re/d, /re/p, Nd, -n, -i, -E. Enough for one-liners.
function global:_lc_n_sed {
    $g = _lc_getopt $args 'nirEe:' @('quiet', 'in-place', 'regexp-extended', 'expression=') @{ quiet = 'n'; 'in-place' = 'i'; 'regexp-extended' = 'E'; expression = 'e' }
    $o = $g.o; $rest = @($g.rest)
    $script = if ($o.e) { $o.e } else { $s = $rest[0]; $rest = @($rest | Select-Object -Skip 1); $s }
    $ere = $o.E -or $o.r
    $fixre = { param($p) if ($ere) { $p } else { $p -replace '\\([|(){}+?])', '$1' } }
    $cmds = foreach ($c in ($script -split ';')) {
        $c = $c.Trim()
        if ($c -match '^(?<addr>\d+|\$|/[^/]*/)?s(?<d>.)(?<re>(?:\\.|(?!\k<d>).)*)\k<d>(?<rep>(?:\\.|(?!\k<d>).)*)\k<d>(?<fl>[gipI0-9]*)$') {
            $rep = $Matches.rep -replace '\$', '$$$$' -replace '\\(\d)', '$${$1}' -replace '(?<!\\)&', '$$0' -replace '\\&', '&' -replace '\\n', "`n" -replace '\\/', '/'
            @{ op = 's'; addr = $Matches.addr; re = [regex]::new((& $fixre $Matches.re), $(if ($Matches.fl -match '[iI]') { 'IgnoreCase' } else { 'None' })); rep = $rep; g = $Matches.fl -match 'g'; p = $Matches.fl -match 'p' }
        } elseif ($c -match '^(\d+|\$|/(.*)/)?([dp])$') {
            @{ op = $Matches[3]; addr = $Matches[1] }
        } elseif ($c) { _lc_err 'sed' "unsupported command '$c' (no GNU sed installed)"; return }
    }
    $match = {
        param($cmd, $line, $n, $last)
        $a = $cmd.addr
        if (-not $a) { return $true }
        if ($a -eq '$') { return $last }
        if ($a -match '^\d+$') { return $n -eq [int]$a }
        [regex]::IsMatch($line, (& $fixre $a.Trim('/')))
    }
    $run = {
        param($lines)
        $lines = @($lines); $n = 0
        foreach ($line in $lines) {
            $n++; $del = $false; $extra = @()
            foreach ($c in @($cmds)) {
                if (-not (& $match $c $line $n ($n -eq $lines.Count))) { continue }
                switch ($c.op) {
                    's' { $new = if ($c.g) { $c.re.Replace($line, $c.rep) } else { $c.re.Replace($line, $c.rep, 1) }; if ($c.p -and $new -ne $line) { $extra += $new }; $line = $new }
                    'd' { $del = $true }
                    'p' { $extra += $line }
                }
                if ($del) { break }
            }
            if (-not $del) { $extra; if (-not $o.n) { $line } }
        }
    }
    if ($o.i) { foreach ($f in (_lc_glob $rest)) { $out = @(& $run (Get-Content -LiteralPath $f)); Set-Content -LiteralPath $f -Value $out }; return }
    & $run (_lc_lines $rest $input 'sed')
}

function global:_lc_n_seq {
    $g = _lc_getopt $args 's:wf:' @('separator=', 'equal-width') @{ separator = 's'; 'equal-width' = 'w' }
    $n = @($g.rest | ForEach-Object { [double]$_ })
    $first, $inc, $last = switch ($n.Count) { 1 { 1, 1, $n[0] } 2 { $n[0], 1, $n[1] } default { $n[0], $n[1], $n[2] } }
    $vals = @(); if ($inc -gt 0) { for ($x = $first; $x -le $last; $x += $inc) { $vals += $x } } elseif ($inc -lt 0) { for ($x = $first; $x -ge $last; $x += $inc) { $vals += $x } }
    $w = if ($g.o.w) { ("$([long]$last)").Length } else { 0 }
    $s = @($vals | ForEach-Object { "$_".PadLeft($w, '0') })
    if ($g.o.s) { $s -join $g.o.s } else { $s }
}

function global:_lc_n_tac { $l = @(_lc_lines $args $input 'tac'); [array]::Reverse($l); $l }

function global:_lc_n_du {
    $g = _lc_getopt $args 'shcad:' @('summarize', 'human-readable', 'total', 'all', 'max-depth=') @{ summarize = 's'; 'human-readable' = 'h'; total = 'c'; all = 'a'; 'max-depth' = 'd' }
    $o = $g.o; $paths = @($g.rest); if (-not $paths.Count) { $paths = @('.') }
    $depth = if ($o.s) { 0 } elseif ($null -ne $o.d) { [int]$o.d } else { [int]::MaxValue }
    $fmt = { param($b) if ($o.h) { _lc_human $b } else { [Math]::Ceiling($b / 1024) } }
    $total = 0
    foreach ($p in (_lc_glob $paths)) {
        $base = (Resolve-Path -LiteralPath $p).ProviderPath
        $files = @(Get-ChildItem -LiteralPath $base -Recurse -File -Force -ErrorAction SilentlyContinue)
        $sum = ($files | Measure-Object Length -Sum).Sum; if (-not $sum) { $sum = 0 }; $total += $sum
        if ($depth -gt 0) {
            $dirs = Get-ChildItem -LiteralPath $base -Recurse -Directory -Force -ErrorAction SilentlyContinue | Where-Object { ($_.FullName.Substring($base.Length).Trim('\') -split '\\').Count -le $depth } | Sort-Object FullName -Descending
            foreach ($d in $dirs) { $s = ($files | Where-Object { $_.FullName.StartsWith($d.FullName + '\') } | Measure-Object Length -Sum).Sum; "$(& $fmt ([double]$s))`t$((Join-Path $p $d.FullName.Substring($base.Length).Trim('\')) -replace '\\','/')" }
        }
        "$(& $fmt ([double]$sum))`t$p"
    }
    if ($o.c) { "$(& $fmt ([double]$total))`ttotal" }
}

function global:_lc_hashsum([string]$algo, $argv, $inp) {
    $g = _lc_getopt $argv 'cb' @('check')  @{ check = 'c' }
    if ($g.o.c) {
        $bad = 0
        foreach ($l in (_lc_lines $g.rest $inp "${algo}sum")) {
            if ($l -notmatch '^([0-9a-fA-F]+)\s+\*?(.+)$') { continue }
            $ok = (Get-FileHash -Algorithm $algo -LiteralPath $Matches[2]).Hash -eq $Matches[1].ToUpper()
            "$($Matches[2]): $(if ($ok) { 'OK' } else { $bad++; 'FAILED' })"
        }
        $global:LASTEXITCODE = [int]($bad -gt 0); return
    }
    if (-not $g.rest.Count) {
        $bytes = [Text.Encoding]::UTF8.GetBytes(((@($inp) -join "`n") + "`n"))
        $h = [Security.Cryptography.HashAlgorithm]::Create($algo).ComputeHash($bytes)
        (($h | ForEach-Object { $_.ToString('x2') }) -join '') + '  -'; return
    }
    foreach ($f in (_lc_glob $g.rest)) { "$((Get-FileHash -Algorithm $algo -LiteralPath $f).Hash.ToLower())  $f" }
}
function global:_lc_n_md5sum { _lc_hashsum MD5 $args $input }
function global:_lc_n_sha1sum { _lc_hashsum SHA1 $args $input }
function global:_lc_n_sha256sum { _lc_hashsum SHA256 $args $input }
function global:_lc_n_sha512sum { _lc_hashsum SHA512 $args $input }

function global:_lc_n_base64 {
    $g = _lc_getopt $args 'dw:i' @('decode', 'wrap=') @{ decode = 'd'; wrap = 'w' }
    $text = if ($g.rest.Count) { [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath (_lc_winpath $g.rest[0])).ProviderPath) } else { $null }
    if ($g.o.d) {
        $s = if ($text) { [Text.Encoding]::ASCII.GetString($text) } else { @($input) -join '' }
        [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($s -replace '\s', '')))
    } else {
        if (-not $text) { $text = [Text.Encoding]::UTF8.GetBytes((@($input) -join "`n") + "`n") }
        $b = [Convert]::ToBase64String($text); $w = if ($null -ne $g.o.w) { [int]$g.o.w } else { 76 }
        if ($w -le 0) { $b } else { for ($i = 0; $i -lt $b.Length; $i += $w) { $b.Substring($i, [Math]::Min($w, $b.Length - $i)) } }
    }
}

function global:_lc_n_sleep {
    $t = 0.0
    foreach ($a in $args) { if ("$a" -match '^([\d.]+)([smhd]?)$') { $t += [double]$Matches[1] * @{ '' = 1; s = 1; m = 60; h = 3600; d = 86400 }[$Matches[2]] } else { _lc_err 'sleep' "invalid time interval '$a'"; return } }
    Start-Sleep -Milliseconds ([int]($t * 1000))
}

function global:_lc_n_diff {
    $g = _lc_getopt $args 'uqiwrN' @('unified', 'brief', 'ignore-case') @{ unified = 'u'; brief = 'q'; 'ignore-case' = 'i' }
    $a, $b = $g.rest | ForEach-Object { _lc_winpath $_ }
    $l1 = @(Get-Content -LiteralPath $a); $l2 = @(Get-Content -LiteralPath $b)
    $d = @(Compare-Object $l1 $l2 -CaseSensitive:(-not $g.o.i) -SyncWindow ([Math]::Max($l1.Count, $l2.Count)))
    if (-not $d.Count) { $global:LASTEXITCODE = 0; return }
    if ($g.o.q) { "Files $a and $b differ" } else { foreach ($x in $d) { if ($x.SideIndicator -eq '<=') { "< $($x.InputObject)" } else { "> $($x.InputObject)" } } }
    $global:LASTEXITCODE = 1
}

function global:_lc_n_less { if ($args.Count) { Get-Content -LiteralPath (_lc_winpath $args[-1]) | Out-Host -Paging } else { $input | Out-Host -Paging } }

function global:_lc_n_yes { $s = if ($args.Count) { $args -join ' ' } else { 'y' }; while ($true) { $s } }
function global:_lc_n_true { $global:LASTEXITCODE = 0 }
function global:_lc_n_false { $global:LASTEXITCODE = 1 }

function global:_lc_n_xargs {
    $g = _lc_getopt $args 'n:I:0rd:t' @('max-args=', 'replace=', 'null', 'no-run-if-empty', 'delimiter=', 'verbose') @{ 'max-args' = 'n'; replace = 'I'; null = '0'; 'no-run-if-empty' = 'r'; delimiter = 'd'; verbose = 't' } -stopAtFirst
    $cmd = @($g.rest); if (-not $cmd.Count) { $cmd = @('echo') }
    $text = @($input) -join "`n"
    $items = if ($g.o['0']) { $text -split "`0" } elseif ($g.o.d) { $text -split [regex]::Escape($g.o.d) } elseif ($g.o.I) { $text -split "`n" } else { $text -split '\s+' }
    $items = @($items | Where-Object { $_ -ne '' })
    if (-not $items.Count -and $g.o.r) { return }
    $run = { param($c) if ($g.o.t) { [Console]::Error.WriteLine(($c -join ' ')) }; & $c[0] @($c | Select-Object -Skip 1) }
    if ($g.o.I) { foreach ($it in $items) { & $run @($cmd | ForEach-Object { $_.Replace($g.o.I, $it) }) }; return }
    $n = if ($g.o.n) { [int]$g.o.n } else { $items.Count }
    for ($i = 0; $i -lt [Math]::Max(1, $items.Count); $i += $n) { & $run (@($cmd) + @($items | Select-Object -Skip $i -First $n)) }
}

# test / [ for the common file and string checks.
function global:_lc_n_test {
    $a = @($args | ForEach-Object { "$_" }); if ($a.Count -and $a[-1] -eq ']') { $a = @($a | Select-Object -SkipLast 1) }
    $neg = $false; if ($a.Count -and $a[0] -eq '!') { $neg = $true; $a = @($a | Select-Object -Skip 1) }
    $r = switch ($a.Count) {
        0 { $false }
        1 { $a[0] -ne '' }
        2 {
            $p = _lc_winpath $a[1]
            switch -CaseSensitive ($a[0]) {
                '-f' { Test-Path -LiteralPath $p -PathType Leaf } '-d' { Test-Path -LiteralPath $p -PathType Container }
                '-e' { Test-Path -LiteralPath $p } '-s' { (Test-Path -LiteralPath $p -PathType Leaf) -and (Get-Item -LiteralPath $p).Length -gt 0 }
                '-r' { Test-Path -LiteralPath $p } '-w' { (Test-Path -LiteralPath $p) -and -not (Get-Item -LiteralPath $p -Force).IsReadOnly }
                '-x' { (Test-Path -LiteralPath $p) -and $p -match '\.(exe|cmd|bat|com|ps1)$' }
                '-L' { (Test-Path -LiteralPath $p) -and [bool]((Get-Item -LiteralPath $p -Force).LinkType) }
                '-z' { $a[1] -eq '' } '-n' { $a[1] -ne '' }
                default { $false }
            }
        }
        default {
            $x = $a[0]; $y = $a[2]
            switch -CaseSensitive ($a[1]) {
                '=' { $x -ceq $y } '==' { $x -ceq $y } '!=' { $x -cne $y }
                '-eq' { [long]$x -eq [long]$y } '-ne' { [long]$x -ne [long]$y } '-lt' { [long]$x -lt [long]$y }
                '-le' { [long]$x -le [long]$y } '-gt' { [long]$x -gt [long]$y } '-ge' { [long]$x -ge [long]$y }
                default { $false }
            }
        }
    }
    $global:LASTEXITCODE = if ([bool]$r -xor $neg) { 0 } else { 1 }
}

function global:_lc_n_date {
    $g = _lc_getopt $args 'ud:IRr:' @('utc', 'date=', 'iso-8601', 'rfc-2822', 'reference=') @{ utc = 'u'; date = 'd'; 'iso-8601' = 'I'; 'rfc-2822' = 'R'; reference = 'r' }
    $o = $g.o; $d = Get-Date
    if ($o.r) { $d = (Get-Item -LiteralPath (_lc_winpath $o.r)).LastWriteTime }
    if ($o.d) { $d = _lc_parse_date $o.d }
    if ($null -eq $d) { _lc_err 'date' "invalid date '$($o.d)'"; return }
    if ($o.u) { $d = $d.ToUniversalTime() }
    $fmt = ($g.rest | Where-Object { $_.StartsWith('+') } | Select-Object -First 1)
    if ($fmt) { _lc_strftime $d $fmt.Substring(1) }
    elseif ($o.I) { $d.ToString('yyyy-MM-dd') }
    elseif ($o.R) { $d.ToString('ddd, dd MMM yyyy HH:mm:ss ') + $d.ToString('zzz').Replace(':', '') }
    else { $d.ToString('ddd MMM ') + $d.Day.ToString().PadLeft(2) + $d.ToString(' HH:mm:ss ') + $(if ($o.u) { 'UTC' } else { [TimeZoneInfo]::Local.StandardName -replace '[^A-Z]', '' }) + $d.ToString(' yyyy') }
}

# GNU date -d strings: now, today, yesterday, tomorrow, "N units ago", "+N units", "next monday", @epoch, ISO.
function global:_lc_parse_date([string]$s) {
    $s = $s.Trim(); $now = Get-Date
    if ($s -match '^@(\d+)$') { return ([DateTimeOffset]::FromUnixTimeSeconds([long]$Matches[1])).LocalDateTime }
    switch -Regex ($s) {
        '^now$' { return $now }
        '^today$' { return $now }
        '^yesterday$' { return $now.AddDays(-1) }
        '^tomorrow$' { return $now.AddDays(1) }
    }
    if ($s -match '^(?:(next|last)\s+)(mon|tue|wed|thu|fri|sat|sun)\w*$') {
        $target = [array]::IndexOf(@('sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'), $Matches[2])
        $diff = ($target - [int]$now.DayOfWeek + 7) % 7
        if ($Matches[1] -eq 'next') { if ($diff -eq 0) { $diff = 7 }; return $now.Date.AddDays($diff) }
        $back = ([int]$now.DayOfWeek - $target + 7) % 7; if ($back -eq 0) { $back = 7 }; return $now.Date.AddDays(-$back)
    }
    $d = $now; $rest = $s; $any = $false
    while ($rest -match '^\s*([+-]?\d+)\s*(sec|second|min|minute|hour|day|week|month|year|fortnight)s?\b(\s+ago)?(.*)$') {
        $n = [int]$Matches[1]; if ($Matches[3]) { $n = -$n }; $rest = $Matches[4]; $any = $true
        $d = switch -Regex ($Matches[2]) { '^sec' { $d.AddSeconds($n) } '^min' { $d.AddMinutes($n) } 'hour' { $d.AddHours($n) } 'day' { $d.AddDays($n) } 'fortnight' { $d.AddDays(14 * $n) } 'week' { $d.AddDays(7 * $n) } 'month' { $d.AddMonths($n) } 'year' { $d.AddYears($n) } }
    }
    if ($any -and $rest.Trim() -eq '') { return $d }
    $p = [datetime]::MinValue
    if ([datetime]::TryParse($s, [ref]$p)) { return $p }
    $null
}

function global:_lc_strftime([datetime]$d, [string]$f) {
    $inv = [Globalization.CultureInfo]::InvariantCulture
    [regex]::Replace($f, '%([a-zA-Z%])', {
            param($m)
            switch -CaseSensitive ($m.Groups[1].Value) {
                'Y' { $d.ToString('yyyy') } 'y' { $d.ToString('yy') } 'm' { $d.ToString('MM') } 'd' { $d.ToString('dd') } 'e' { "$($d.Day)".PadLeft(2) }
                'H' { $d.ToString('HH') } 'I' { $d.ToString('hh') } 'M' { $d.ToString('mm') } 'S' { $d.ToString('ss') } 'p' { $d.ToString('tt', $inv) }
                'a' { $d.ToString('ddd', $inv) } 'A' { $d.ToString('dddd', $inv) } 'b' { $d.ToString('MMM', $inv) } 'h' { $d.ToString('MMM', $inv) } 'B' { $d.ToString('MMMM', $inv) }
                'j' { "$($d.DayOfYear)".PadLeft(3, '0') } 'u' { $w = [int]$d.DayOfWeek; if ($w -eq 0) { '7' } else { "$w" } } 'w' { "$([int]$d.DayOfWeek)" }
                's' { "$([DateTimeOffset]::new($d).ToUnixTimeSeconds())" } 'N' { ($d.Ticks % 10000000 * 100).ToString('000000000') }
                'z' { $d.ToString('zzz').Replace(':', '') } 'Z' { [TimeZoneInfo]::Local.StandardName -creplace '[^A-Z]', '' }
                'F' { $d.ToString('yyyy-MM-dd') } 'T' { $d.ToString('HH:mm:ss') } 'D' { $d.ToString('MM/dd/yy') } 'R' { $d.ToString('HH:mm') }
                'c' { $d.ToString('ddd MMM d HH:mm:ss yyyy', $inv) } 'x' { $d.ToString('MM/dd/yy') } 'X' { $d.ToString('HH:mm:ss') }
                'n' { "`n" } 't' { "`t" } '%' { '%' }
                'V' { "$($inv.Calendar.GetWeekOfYear($d, 'FirstFourDayWeek', 'Monday'))".PadLeft(2, '0') }
                default { $m.Value }
            }
        })
}

function global:_lc_n_printf {
    if (-not $args.Count) { return }
    $fmt = "$($args[0])".Replace('\n', "`n").Replace('\t', "`t").Replace('\\', '\')
    $vals = @($args | Select-Object -Skip 1); $i = [ref]0
    $out = [regex]::Replace($fmt, '%(-?\d*)(?:\.(\d+))?([sdfxXo%])', {
            param($m)
            if ($m.Groups[3].Value -eq '%') { return '%' }
            $v = if ($i.Value -lt $vals.Count) { $vals[$i.Value] } else { '' }; $i.Value++
            $w = $m.Groups[1].Value; $p = $m.Groups[2].Value
            $s = switch ($m.Groups[3].Value) {
                's' { "$v" } 'd' { "$([long]$v)" } 'f' { ([double]$v).ToString('F' + $(if ($p) { $p } else { '6' })) }
                'x' { ([long]$v).ToString('x') } 'X' { ([long]$v).ToString('X') } 'o' { [Convert]::ToString([long]$v, 8) }
            }
            if ($w) { if ($w.StartsWith('-')) { $s.PadRight([int]$w.Substring(1)) } else { $s.PadLeft([int]$w, $(if ($w.StartsWith('0')) { '0' } else { ' ' })) } } else { $s }
        })
    # Whole lines go to the pipeline; a trailing partial line is written straight to the console.
    $lines = $out -split "`n"
    $lines | Select-Object -SkipLast 1
    if ($lines[-1] -ne '') { [Console]::Out.Write($lines[-1]) }
}
