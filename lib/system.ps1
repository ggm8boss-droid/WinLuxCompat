# linux-compat for Windows: Linux system tools on top of Windows (always native PowerShell).

function global:_lc_procs {
    $cpu = [Environment]::ProcessorCount
    $byId = @{}; foreach ($p in (Get-Process)) { $byId[$p.Id] = $p }
    $now = Get-Date
    foreach ($w in (Get-CimInstance Win32_Process -Property ProcessId, ParentProcessId, Name, CommandLine, CreationDate, WorkingSetSize, VirtualSize, KernelModeTime, UserModeTime, SessionId)) {
        $secs = ([double]$w.KernelModeTime + [double]$w.UserModeTime) / 1e7
        $start = $w.CreationDate
        $el = if ($start) { ($now - $start).TotalSeconds } else { 0 }
        [pscustomobject]@{
            PID = [int]$w.ProcessId; PPID = [int]$w.ParentProcessId
            USER = if ($w.SessionId -eq 0) { 'SYSTEM' } else { $env:USERNAME }
            CPU = if ($el -gt 0) { [Math]::Round(100 * $secs / $el / $cpu, 1) } else { 0 }
            MEM = [Math]::Round(100 * [double]$w.WorkingSetSize / (_lc_totalmem), 1)
            RSS = [long]($w.WorkingSetSize / 1KB); VSZ = [long]([double]$w.VirtualSize / 1KB)
            TTY = if ($w.SessionId -eq 0) { '?' } else { "con$($w.SessionId)" }
            START = if ($start) { if ($start.Date -eq $now.Date) { $start.ToString('HH:mm') } else { $start.ToString('MMMdd') } } else { '?' }
            TIME = [TimeSpan]::FromSeconds([int]$secs).ToString('hh\:mm\:ss').TrimStart('0').TrimStart(':').PadLeft(4, '0')
            COMM = ($w.Name -replace '\.exe$', '')
            ARGS = if ($w.CommandLine) { $w.CommandLine } else { $w.Name }
            ELAPSED = $el
        }
    }
}
$global:LC_TOTALMEM = 0
function global:_lc_totalmem {
    if ($global:LC_TOTALMEM -le 1) { $global:LC_TOTALMEM = [double](Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory }
    $global:LC_TOTALMEM
}

function global:ps {
    # Plain `ps` piped into PowerShell (ps | where ...) keeps giving Process objects.
    if (-not $args.Count -and $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength) { return Get-Process }
    if (_lc_psstyle 'Get-Process' $args) { return Get-Process @args }
    [void](_lc_totalmem)
    $a = @($args | ForEach-Object { "$_" })
    $bsd = $a.Count -and $a[0] -match '^[a-zA-Z]+$'   # ps aux
    $g = _lc_getopt $(if ($bsd) { @($a | ForEach-Object { if ($_ -match '^[a-zA-Z]+$') { "-$_" } else { $_ } }) } else { $a }) 'efAauxlwp:C:u:o:' @('sort=', 'pid=', 'forest') @{ pid = 'p' }
    $o = $g.o
    $list = @(_lc_procs)
    if ($o.p) { $ids = @("$($o.p)" -split ',' | ForEach-Object { [int]$_ }); $list = @($list | Where-Object { $ids -contains $_.PID }) }
    if ($o.C) { $names = "$($o.C)" -split ','; $list = @($list | Where-Object { $names -contains $_.COMM }) }
    if ($o.u -and -not $bsd) { $list = @($list | Where-Object { $_.USER -eq $o.u }) }
    if ($o.sort) {
        $keyName = $o.sort.TrimStart('-+'); $desc = $o.sort.StartsWith('-')
        $k = @{ pid = 'PID'; ppid = 'PPID'; '%cpu' = 'CPU'; pcpu = 'CPU'; '%mem' = 'MEM'; pmem = 'MEM'; rss = 'RSS'; vsz = 'VSZ'; comm = 'COMM'; cmd = 'ARGS'; etime = 'ELAPSED'; start_time = 'ELAPSED'; time = 'TIME' }[$keyName]
        if ($k) { $list = @($list | Sort-Object $k -Descending:$desc) }
    } else { $list = @($list | Sort-Object PID) }
    if (-not ($o.e -or $o.A -or $o.a -or $o.x -or $o.p -or $o.C -or $o.u)) {
        # bare ps: this console's processes, like Linux
        $mine = @{}; $id = $PID; while ($id -and -not $mine.ContainsKey($id)) { $mine[$id] = 1; $id = ($list | Where-Object PID -eq $id).PPID }
        $kids = { param($p) $list | Where-Object { $_.PPID -eq $p } }
        $list = @($list | Where-Object { $mine.ContainsKey($_.PID) -or $mine.ContainsKey($_.PPID) })
    }
    if ($o.o) {
        $cols = @("$($o.o)" -split ',' | ForEach-Object { $_.Trim() })
        $map = @{ pid = 'PID'; ppid = 'PPID'; user = 'USER'; uid = 'USER'; '%cpu' = 'CPU'; pcpu = 'CPU'; '%mem' = 'MEM'; pmem = 'MEM'; rss = 'RSS'; vsz = 'VSZ'; tty = 'TTY'; comm = 'COMM'; cmd = 'ARGS'; args = 'ARGS'; command = 'ARGS'; time = 'TIME'; start = 'START'; stime = 'START'; etime = 'ELAPSED' }
        ($cols | ForEach-Object { $h = $_.Split('=')[-1]; if (-not $h) { $h = '' }; $h.ToUpper().PadLeft(8) }) -join ' '
        foreach ($p in $list) { ($cols | ForEach-Object { $f = $map[$_.Split('=')[0].ToLower()]; "$(if ($f) { $p.$f })".PadLeft(8) }) -join ' ' }
        return
    }
    if ($bsd -and ($o.u)) {
        'USER         PID %CPU %MEM      VSZ     RSS TTY      STAT START   TIME COMMAND'
        foreach ($p in $list) { '{0,-10} {1,5} {2,4} {3,4} {4,8} {5,7} {6,-8} {7,-4} {8,5} {9,6} {10}' -f $p.USER, $p.PID, $p.CPU, $p.MEM, $p.VSZ, $p.RSS, $p.TTY, 'S', $p.START, $p.TIME, $p.ARGS }
    } elseif ($o.f -or $o.l) {
        'UID          PID    PPID  C STIME TTY          TIME CMD'
        foreach ($p in $list) { '{0,-10} {1,6} {2,7} {3,2} {4,5} {5,-8} {6,8} {7}' -f $p.USER, $p.PID, $p.PPID, [int]$p.CPU, $p.START, $p.TTY, $p.TIME, $p.ARGS }
    } else {
        '    PID TTY          TIME CMD'
        foreach ($p in $list) { '{0,7} {1,-8} {2,8} {3}' -f $p.PID, $p.TTY, $p.TIME, $p.COMM }
    }
}

$global:LC_SIGNALS = @('HUP', 'INT', 'QUIT', 'ILL', 'TRAP', 'ABRT', 'BUS', 'FPE', 'KILL', 'USR1', 'SEGV', 'USR2', 'PIPE', 'ALRM', 'TERM')
# Graceful = ask the window to close (like SIGTERM), force (KILL/9) = terminate.
function global:_lc_signal_force($sig) { "$sig" -match '^(9|KILL|SIGKILL)$' }
function global:_lc_stop([System.Diagnostics.Process]$p, [bool]$force, [string]$cmd) {
    _lc_act "Stop-Process $($p.Id) ($($p.ProcessName))$(if ($force) { ' -Force' })" {
        if (-not $force -and $p.MainWindowHandle -ne 0) { if ($p.CloseMainWindow()) { if ($p.WaitForExit(3000)) { return } } }
        try { Stop-Process -Id $p.Id -Force -ErrorAction Stop } catch { _lc_err $cmd "($($p.Id)) - $($_.Exception.Message.Split([Environment]::NewLine)[0])" }
    }
}

function global:kill {
    if ($MyInvocation.ExpectingInput -or (_lc_psstyle 'Stop-Process' $args) -or ($args | Where-Object { $_ -is [System.Diagnostics.Process] })) { $input | Stop-Process @args; return }
    $a = @($args | ForEach-Object { "$_" }); $sig = 'TERM'
    if ($a.Count -and $a[0] -eq '-l') { ($global:LC_SIGNALS | ForEach-Object -Begin { $i = 0 } -Process { $i++; '{0,2}) SIG{1}' -f $i, $_ }) ; return }
    if ($a.Count -and $a[0] -eq '-s') { $sig = $a[1]; $a = @($a | Select-Object -Skip 2) }
    elseif ($a.Count -and $a[0] -match '^-(\w+)$') { $sig = $Matches[1] -replace '^SIG', ''; $a = @($a | Select-Object -Skip 1) }
    if (-not $a.Count) { _lc_err 'kill' 'usage: kill [-s sigspec | -signum] pid ...'; return }
    foreach ($id in $a) {
        if ($id -match '^%(\d+)$') { Stop-Job -Id ([int]$Matches[1]); continue }
        $p = Get-Process -Id ([int]$id) -ErrorAction SilentlyContinue
        if (-not $p) { _lc_err 'kill' "($id) - No such process"; continue }
        _lc_stop $p (_lc_signal_force $sig) 'kill'
    }
}

# pgrep/pkill/killall/pidof share the matching.
function global:_lc_match_procs([string]$pat, [bool]$full, [bool]$exact, [bool]$icase) {
    $opt = if ($icase) { 'IgnoreCase' } else { 'None' }
    $re = if ($exact) { "^(?:$pat)$" } else { $pat }
    if ($full) { Get-CimInstance Win32_Process | Where-Object { $_.ProcessId -ne $PID -and [regex]::IsMatch("$($_.CommandLine)", $re, $opt) } | ForEach-Object { [pscustomobject]@{ Id = [int]$_.ProcessId; Name = $_.Name -replace '\.exe$', ''; Cmd = $_.CommandLine } } }
    else { Get-Process | Where-Object { [regex]::IsMatch($_.ProcessName, $re, $opt) } | ForEach-Object { [pscustomobject]@{ Id = $_.Id; Name = $_.ProcessName; Cmd = $_.Path } } }
}
function global:pgrep {
    $g = _lc_getopt $args 'flaxinou:d:' @('full', 'list-name', 'list-full', 'exact', 'ignore-case', 'newest', 'oldest', 'delimiter=') @{ full = 'f'; 'list-name' = 'l'; 'list-full' = 'a'; exact = 'x'; 'ignore-case' = 'i'; newest = 'n'; oldest = 'o'; delimiter = 'd' }
    $o = $g.o; $m = @(_lc_match_procs $g.rest[0] ([bool]$o.f) ([bool]$o.x) ([bool]$o.i) | Sort-Object Id)
    if ($o.n -or $o.o) { $m = @($m | Sort-Object { (Get-Process -Id $_.Id -ErrorAction SilentlyContinue).StartTime } | Select-Object -Last:$([bool]$o.n) -First:$([bool]$o.o) 1) }
    $out = foreach ($p in $m) { if ($o.a) { "$($p.Id) $($p.Cmd)" } elseif ($o.l) { "$($p.Id) $($p.Name)" } else { "$($p.Id)" } }
    if ($o.d) { $out -join $o.d } else { $out }
    $global:LASTEXITCODE = if ($m.Count) { 0 } else { 1 }
}
function global:pkill {
    $a = @($args | ForEach-Object { "$_" }); $sig = 'TERM'
    if ($a.Count -and $a[0] -match '^-(\d+|[A-Z]+)$') { $sig = $Matches[1]; $a = @($a | Select-Object -Skip 1) }
    $g = _lc_getopt $a 'fxi' @('full', 'exact', 'ignore-case', 'signal=') @{ full = 'f'; exact = 'x'; 'ignore-case' = 'i' }
    if ($g.o.signal) { $sig = $g.o.signal }
    $m = @(_lc_match_procs $g.rest[0] ([bool]$g.o.f) ([bool]$g.o.x) ([bool]$g.o.i))
    foreach ($p in $m) { $pp = Get-Process -Id $p.Id -ErrorAction SilentlyContinue; if ($pp) { _lc_stop $pp (_lc_signal_force $sig) 'pkill' } }
    $global:LASTEXITCODE = if ($m.Count) { 0 } else { 1 }
}
function global:killall {
    $a = @($args | ForEach-Object { "$_" }); $sig = 'TERM'
    if ($a.Count -and $a[0] -match '^-(\d+|[A-Z]+)$' -and $a[0] -notmatch '^-[iqvI]+$') { $sig = $Matches[1]; $a = @($a | Select-Object -Skip 1) }
    $g = _lc_getopt $a 'qvIs:' @('quiet', 'verbose', 'ignore-case', 'signal=') @{ quiet = 'q'; verbose = 'v'; 'ignore-case' = 'I'; signal = 's' }
    if ($g.o.s) { $sig = $g.o.s }
    $any = $false
    foreach ($n in $g.rest) {
        $ps = @(Get-Process -Name ($n -replace '\.exe$', '') -ErrorAction SilentlyContinue)
        if (-not $ps.Count) { if (-not $g.o.q) { _lc_err 'killall' "${n}: no process found" }; continue }
        $any = $true
        foreach ($p in $ps) { _lc_stop $p (_lc_signal_force $sig) 'killall'; if ($g.o.v) { "Killed $n($($p.Id)) with signal $sig" } }
    }
    $global:LASTEXITCODE = if ($any) { 0 } else { 1 }
}
function global:pidof {
    $g = _lc_getopt $args 'sx' @()
    $ids = foreach ($n in $g.rest) { Get-Process -Name ($n -replace '\.exe$', '') -ErrorAction SilentlyContinue | Sort-Object Id -Descending | ForEach-Object Id }
    $ids = @($ids); if ($g.o.s) { $ids = @($ids | Select-Object -First 1) }
    if ($ids.Count) { $ids -join ' '; $global:LASTEXITCODE = 0 } else { $global:LASTEXITCODE = 1 }
}

function global:free {
    $g = _lc_getopt $args 'hbkmgtwl' @('human', 'bytes', 'kilo', 'mega', 'giga', 'si', 'total', 'wide') @{ human = 'h'; bytes = 'b'; kilo = 'k'; mega = 'm'; giga = 'g'; total = 't'; wide = 'w' }
    $o = $g.o
    if (-not ('LcPerf' -as [type])) {
        Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class LcPerf {
    [StructLayout(LayoutKind.Sequential)] public struct PI {
        public uint cb; public UIntPtr CommitTotal, CommitLimit, CommitPeak, PhysicalTotal, PhysicalAvailable, SystemCache,
        KernelTotal, KernelPaged, KernelNonpaged, PageSize; public uint HandleCount, ProcessCount, ThreadCount; }
    [DllImport("psapi.dll")] static extern bool GetPerformanceInfo(out PI pi, uint cb);
    public static PI Get() { PI p; GetPerformanceInfo(out p, (uint)Marshal.SizeOf(typeof(PI))); return p; }
}
'@
    }
    $pi = [LcPerf]::Get(); $pg = [double]$pi.PageSize.ToUInt64()
    $total = [double]$pi.PhysicalTotal.ToUInt64() * $pg; $avail = [double]$pi.PhysicalAvailable.ToUInt64() * $pg
    # Windows "available" already includes the standby cache; Linux shows that cache separately.
    $cache = [Math]::Min($avail, [double]$pi.SystemCache.ToUInt64() * $pg)
    $free = $avail - $cache
    $used = $total - $avail
    $pf = @(Get-CimInstance Win32_PageFileUsage -ErrorAction SilentlyContinue)
    $st = [double](($pf | Measure-Object AllocatedBaseSize -Sum).Sum) * 1MB; $su = [double](($pf | Measure-Object CurrentUsage -Sum).Sum) * 1MB
    $fmt = {
        param($b)
        if ($o.h) { (_lc_human $b) -replace '([KMGTP])$', '$1i' -replace '^(\d+)$', '$1B' }
        elseif ($o.b) { [long]$b } elseif ($o.m) { [long]($b / 1MB) } elseif ($o.g) { [long]($b / 1GB) } else { [long]($b / 1KB) }
    }
    $w = 11
    ('{0,-6}' -f '') + (('total', 'used', 'free', 'shared', 'buff/cache', 'available') | ForEach-Object { $_.PadLeft($w) }) -join ''
    ('{0,-6}' -f 'Mem:') + ((& $fmt $total), (& $fmt $used), (& $fmt $free), (& $fmt 0), (& $fmt $cache), (& $fmt $avail) | ForEach-Object { "$_".PadLeft($w) }) -join ''
    ('{0,-6}' -f 'Swap:') + ((& $fmt $st), (& $fmt $su), (& $fmt ($st - $su)) | ForEach-Object { "$_".PadLeft($w) }) -join ''
    if ($o.t) { ('{0,-6}' -f 'Total:') + ((& $fmt ($total + $st)), (& $fmt ($used + $su)), (& $fmt ($free + $st - $su)) | ForEach-Object { "$_".PadLeft($w) }) -join '' }
}

function global:df {
    $g = _lc_getopt $args 'hHTkmaPlx:t:' @('human-readable', 'si', 'print-type', 'all', 'local', 'type=', 'exclude-type=', 'output=') @{ 'human-readable' = 'h'; si = 'H'; 'print-type' = 'T'; all = 'a'; local = 'l'; type = 't'; 'exclude-type' = 'x' }
    $o = $g.o
    $vols = @(Get-CimInstance Win32_LogicalDisk | Where-Object { $_.Size })
    if ($g.rest.Count) {
        $letters = @($g.rest | ForEach-Object { $p = _lc_winpath $_; ((Resolve-Path -LiteralPath $p -ErrorAction SilentlyContinue).ProviderPath + '  ').Substring(0, 2).ToUpper() })
        $vols = @($vols | Where-Object { $letters -contains $_.DeviceID })
    }
    if ($o.t) { $vols = @($vols | Where-Object { $_.FileSystem -eq $o.t }) }
    if ($o.x) { $vols = @($vols | Where-Object { $_.FileSystem -ne $o.x }) }
    if ($o.l) { $vols = @($vols | Where-Object { $_.DriveType -ne 4 }) }
    $fmt = { param($b) if ($o.h) { _lc_human $b } elseif ($o.H) { _lc_human $b 1000 } elseif ($o.m) { [long]($b / 1MB) } else { [long]($b / 1KB) } }
    $hdr = if ($o.h -or $o.H) { 'Size' } elseif ($o.m) { '1M-blocks' } else { '1K-blocks' }
    $rows = New-Object System.Collections.Generic.List[object]
    $h = @('Filesystem'); if ($o.T) { $h += 'Type' }; $h += $hdr, 'Used', 'Avail', 'Use%', 'Mounted on'
    $rows.Add($h)
    foreach ($v in $vols) {
        $size = [double]$v.Size; $fr = [double]$v.FreeSpace; $used = $size - $fr
        $name = if ($v.ProviderName) { $v.ProviderName } elseif ($v.VolumeName) { $v.VolumeName } else { $v.DeviceID }
        $r = @($name); if ($o.T) { $r += "$($v.FileSystem)" }
        $r += (& $fmt $size), (& $fmt $used), (& $fmt $fr), ('{0}%' -f [Math]::Ceiling(100 * $used / [Math]::Max([double]1, $size))), "$($v.DeviceID)\"
        $rows.Add($r)
    }
    $n = $rows[0].Count; $w = @(0) * $n
    foreach ($r in $rows) { for ($i = 0; $i -lt $n; $i++) { $w[$i] = [Math]::Max($w[$i], "$($r[$i])".Length) } }
    foreach ($r in $rows) { (@(for ($i = 0; $i -lt $n; $i++) { if ($i -eq 0 -or $i -eq $n - 1 -or ($o.T -and $i -eq 1)) { "$($r[$i])".PadRight($w[$i]) } else { "$($r[$i])".PadLeft($w[$i]) } }) -join ' ').TrimEnd() }
}

function global:uname {
    $g = _lc_getopt $args 'asnrvmpio' @('all', 'kernel-name', 'nodename', 'kernel-release', 'kernel-version', 'machine', 'processor', 'hardware-platform', 'operating-system') @{ all = 'a'; 'kernel-name' = 's'; nodename = 'n'; 'kernel-release' = 'r'; 'kernel-version' = 'v'; machine = 'm'; processor = 'p'; 'hardware-platform' = 'i'; 'operating-system' = 'o' }
    $o = $g.o
    $ver = [Environment]::OSVersion.Version
    $ubr = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue)
    $arch = switch ($env:PROCESSOR_ARCHITECTURE) { 'AMD64' { 'x86_64' } 'ARM64' { 'aarch64' } 'x86' { 'i686' } default { $env:PROCESSOR_ARCHITECTURE } }
    $f = [ordered]@{
        s = 'Windows_NT'; n = $env:COMPUTERNAME; r = "$($ver.Major).$($ver.Minor).$($ver.Build).$($ubr.UBR)"
        v = "$(if ($ver.Build -ge 22000) { $ubr.ProductName -replace 'Windows 10', 'Windows 11' } else { $ubr.ProductName }) $($ubr.DisplayVersion)"; m = $arch; p = $arch; i = $arch; o = 'Windows'
    }
    if ($o.a) { ($f.s, $f.n, $f.r, $f.v, $f.m, $f.o) -join ' '; return }
    $sel = @($f.Keys | Where-Object { $o[$_] })
    if (-not $sel.Count) { $sel = @('s') }
    ($sel | ForEach-Object { $f[$_] }) -join ' '
}

function global:uptime {
    $g = _lc_getopt $args 'ps' @('pretty', 'since') @{ pretty = 'p'; since = 's' }
    $boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    $up = (Get-Date) - $boot
    if ($g.o.s) { $boot.ToString('yyyy-MM-dd HH:mm:ss'); return }
    $parts = @(); if ($up.Days -ge 7) { $parts += "$([int][Math]::Floor($up.Days / 7)) week$(if ([Math]::Floor($up.Days / 7) -ne 1) { 's' })" }
    if ($up.Days % 7) { $parts += "$($up.Days % 7) day$(if ($up.Days % 7 -ne 1) { 's' })" }
    if ($up.Hours) { $parts += "$($up.Hours) hour$(if ($up.Hours -ne 1) { 's' })" }
    $parts += "$($up.Minutes) minute$(if ($up.Minutes -ne 1) { 's' })"
    if ($g.o.p) { 'up ' + ($parts -join ', '); return }
    $load = (Get-CimInstance Win32_Processor | Measure-Object LoadPercentage -Average).Average / 100 * [Environment]::ProcessorCount
    $users = @(Get-CimInstance Win32_LoggedOnUser -ErrorAction SilentlyContinue | ForEach-Object { $_.Antecedent.Name } | Sort-Object -Unique).Count
    $u = if ($up.Days) { "$($up.Days) days, {0}:{1:00}" -f $up.Hours, $up.Minutes } else { '{0}:{1:00}' -f $up.Hours, $up.Minutes }
    ' {0} up {1},  {2} user{3},  load average: {4:0.00}, {4:0.00}, {4:0.00}' -f (Get-Date).ToString('HH:mm:ss'), $u, [Math]::Max(1, $users), $(if ($users -ne 1) { 's' }), $load
}

function global:nproc { [Environment]::ProcessorCount }

function global:hostname {
    $a = @($args | ForEach-Object { "$_" })
    if (-not $a.Count -or ($a | Where-Object { $_ -match '^/' })) { & (_lc_win_bin 'hostname') @a; return }
    $g = _lc_getopt $a 'IifsdA' @('all-ip-addresses', 'ip-address', 'fqdn', 'long', 'short', 'domain') @{ 'all-ip-addresses' = 'I'; 'ip-address' = 'i'; fqdn = 'f'; long = 'f'; short = 's'; domain = 'd' }
    $o = $g.o
    if ($o.I -or $o.i) { (Get-NetIPAddress -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notmatch '^(127\.|::1$|fe80:|169\.254\.)' -and $_.AddressState -eq 'Preferred' } | Sort-Object AddressFamily, InterfaceIndex | ForEach-Object IPAddress) -join ' '; return }
    $cs = Get-CimInstance Win32_ComputerSystem
    if ($o.f -or $o.A) { if ($cs.PartOfDomain) { "$($env:COMPUTERNAME).$($cs.Domain)".ToLower() } else { $env:COMPUTERNAME } ; return }
    if ($o.d) { if ($cs.PartOfDomain) { $cs.Domain }; return }
    if ($g.rest.Count) { _lc_err 'hostname' 'use: sudo hostnamectl set-hostname NAME'; return }
    $env:COMPUTERNAME
}

function global:id {
    $g = _lc_getopt $args 'ugnG' @('user', 'group', 'name', 'groups') @{ user = 'u'; group = 'g'; name = 'n'; groups = 'G' }
    $me = [Security.Principal.WindowsIdentity]::GetCurrent()
    $sid = $me.User.Value; $rid = $sid.Split('-')[-1]
    $grp = @($me.Groups | ForEach-Object { try { $_.Translate([Security.Principal.NTAccount]).Value } catch { $null } } | Where-Object { $_ })
    if ($g.o.G) { if ($g.o.n) { ($grp | ForEach-Object { $_.Split('\')[-1] }) -join ' ' } else { ($me.Groups | ForEach-Object { $_.Value.Split('-')[-1] }) -join ' ' }; return }
    if ($g.o.u) { if ($g.o.n) { $env:USERNAME } else { $rid }; return }
    if ($g.o.g) { if ($g.o.n) { 'Users' } else { '545' }; return }
    "uid=$rid($env:USERNAME) gid=545(Users) groups=" + (($me.Groups | Select-Object -First 12 | ForEach-Object { $n = try { $_.Translate([Security.Principal.NTAccount]).Value.Split('\')[-1] } catch { '?' }; "$($_.Value.Split('-')[-1])($n)" }) -join ',')
}
function global:groups { id -Gn }

# top/htop: refreshing table sorted by CPU over the refresh interval. q or Ctrl+C quits.
function global:top {
    $g = _lc_getopt $args 'bn:d:o:p:u:' @('batch', 'iterations=', 'delay=') @{ batch = 'b'; iterations = 'n'; delay = 'd' }
    $o = $g.o; $delay = if ($o.d) { [double]$o.d } else { 3 }; $iters = if ($o.n) { [int]$o.n } else { [int]::MaxValue }
    $cpu = [Environment]::ProcessorCount; $prev = @{}
    Get-Process | ForEach-Object { $prev[$_.Id] = $_.TotalProcessorTime.TotalSeconds }
    $t0 = Get-Date; $first = $true
    for ($k = 0; $k -lt $iters; $k++) {
        if (-not $first -or $o.b) { Start-Sleep -Milliseconds ([int]($delay * 1000)) } else { Start-Sleep -Milliseconds 500 }
        $first = $false
        $dt = ((Get-Date) - $t0).TotalSeconds; $t0 = Get-Date
        $os = Get-CimInstance Win32_OperatingSystem
        $rows = foreach ($p in (Get-Process)) {
            $s = $p.TotalProcessorTime.TotalSeconds; $d = $s - $(if ($prev.ContainsKey($p.Id)) { $prev[$p.Id] } else { $s }); $prev[$p.Id] = $s
            [pscustomobject]@{ PID = $p.Id; Name = "$($p.ProcessName)"; CPU = [Math]::Round(100 * $d / $dt / $cpu, 1); MEM = [Math]::Round($p.WorkingSet64 / 1MB, 1); THR = $p.Threads.Count; TIME = $(if ($p.TotalProcessorTime) { $p.TotalProcessorTime } else { [TimeSpan]::Zero }) }
        }
        if ($o.p) { $ids = "$($o.p)" -split ','; $rows = $rows | Where-Object { $ids -contains "$($_.PID)" } }
        $sortBy = if ($o.o -match 'mem') { 'MEM' } else { 'CPU' }
        $rows = @($rows | Sort-Object $sortBy -Descending)
        $tot = [double]$os.TotalVisibleMemorySize / 1KB; $fr = [double]$os.FreePhysicalMemory / 1KB
        $lines = @(
            "top - $((Get-Date).ToString('HH:mm:ss')) $(uptime -p),  $(@($rows).Count) processes"
            "%Cpu(s): {0,5:0.0} us     MiB Mem: {1,9:0.0} total, {2,9:0.0} free, {3,9:0.0} used" -f (($rows | Measure-Object CPU -Sum).Sum), $tot, $fr, ($tot - $fr)
            ''
            '    PID NAME                      %CPU   MEM(MiB)  THR      TIME+'
        )
        $h = if ($o.b) { 30 } else { [Math]::Max(5, [Console]::WindowHeight - 6) }
        $lines += $rows | Select-Object -First $h | ForEach-Object { '{0,7} {1,-24} {2,6:0.0} {3,10:0.0} {4,4} {5,10}' -f $_.PID, ($_.Name.Substring(0, [Math]::Min(24, $_.Name.Length))), $_.CPU, $_.MEM, $_.THR, $_.TIME.ToString('h\:mm\:ss') }
        if ($o.b) { $lines; '' } else { Clear-Host; $lines | ForEach-Object { Write-Host $_ } }
        if (-not $o.b) {
            $end = (Get-Date).AddSeconds($delay)
            while ((Get-Date) -lt $end) { if ([Console]::KeyAvailable) { $key = [Console]::ReadKey($true); if ($key.KeyChar -eq 'q') { return } }; Start-Sleep -Milliseconds 100 }
            $t0 = $t0.AddSeconds(0)
        }
    }
}
function global:htop { top @args }

# ip addr / link / route, ifconfig, ss, netstat -tulpn, lsof -i
# Adapter names can carry invisible direction marks (RTL Windows locales); drop them.
function global:_lc_clean([string]$s) { $s -replace '[‎‏‪-‮⁦-⁩]', '' }
function global:_lc_adapters {
    Get-NetAdapter -ErrorAction SilentlyContinue | ForEach-Object { [pscustomobject]@{ Name = (_lc_clean $_.Name); ifIndex = $_.ifIndex; Status = "$($_.Status)"; MacAddress = $_.MacAddress; MtuSize = $_.MtuSize } }
}
function global:ip {
    $a = @($args | ForEach-Object { "$_" })
    $fam = $null; $brief = $false
    while ($a.Count -and $a[0].StartsWith('-')) {
        switch -Regex ($a[0]) { '^-4$' { $fam = 'IPv4' } '^-6$' { $fam = 'IPv6' } '^-(br|brief)$' { $brief = $true } '^-c(olor)?' { } }
        $a = @($a | Select-Object -Skip 1)
    }
    $obj = if ($a.Count) { $a[0] } else { 'help' }; $rest = @($a | Select-Object -Skip 1)
    if ($rest.Count -and $rest[0] -in 'show', 'list', 'ls') { $rest = @($rest | Select-Object -Skip 1) }
    $dev = $null; if ($rest.Count -ge 2 -and $rest[0] -eq 'dev') { $dev = $rest[1] } elseif ($rest.Count -eq 1) { $dev = $rest[0] }
    $ads = @(_lc_adapters)
    $ifs = @(Get-NetIPInterface -ErrorAction SilentlyContinue)
    $loop = [pscustomobject]@{ Name = 'lo'; ifIndex = 1; Status = 'Up'; MacAddress = '00-00-00-00-00-00'; MtuSize = 65536 }
    switch -Regex ($obj) {
        '^(a|addr|address)$' {
            $ips = @(Get-NetIPAddress -ErrorAction SilentlyContinue); if ($fam) { $ips = @($ips | Where-Object AddressFamily -eq $fam) }
            $n = 0
            foreach ($ad in (@($loop) + @($ads | Sort-Object ifIndex))) {
                $n++
                if ($dev -and $ad.Name -ne $dev) { continue }
                $mine = @($ips | Where-Object { $_.InterfaceIndex -eq $ad.ifIndex -or ($ad.Name -eq 'lo' -and $_.IPAddress -match '^(127\.|::1$)') })
                $state = if ($ad.Status -eq 'Up') { 'UP' } else { 'DOWN' }
                if ($brief) { '{0,-16} {1,-14} {2}' -f $ad.Name, $state, (($mine | ForEach-Object { "$($_.IPAddress)/$($_.PrefixLength)" }) -join ' '); continue }
                $mtu = ($ifs | Where-Object { $_.InterfaceIndex -eq $ad.ifIndex } | Select-Object -First 1).NlMtu; if (-not $mtu) { $mtu = $ad.MtuSize }
                "${n}: $($ad.Name): <$(if ($ad.Name -eq 'lo') { 'LOOPBACK,' })$(if ($state -eq 'UP') { 'UP,LOWER_UP' } else { 'NO-CARRIER' })> mtu $mtu state $state"
                "    link/$(if ($ad.Name -eq 'lo') { 'loopback' } else { 'ether' }) $(($ad.MacAddress -replace '-', ':').ToLower())"
                foreach ($i in $mine) { "    $(if ($i.AddressFamily -eq 'IPv4') { 'inet' } else { 'inet6' }) $($i.IPAddress)/$($i.PrefixLength) scope $(if ($i.IPAddress -match '^(127\.|::1)') { 'host' } elseif ($i.IPAddress -match '^fe80') { 'link' } else { 'global' }) $($ad.Name)" }
            }
        }
        '^(l|link)$' {
            $n = 0
            foreach ($ad in (@($loop) + @($ads | Sort-Object ifIndex))) {
                $n++; if ($dev -and $ad.Name -ne $dev) { continue }
                $state = if ($ad.Status -eq 'Up') { 'UP' } else { 'DOWN' }
                if ($brief) { '{0,-16} {1,-14} {2}' -f $ad.Name, $state, ($ad.MacAddress -replace '-', ':').ToLower(); continue }
                "${n}: $($ad.Name): <$(if ($state -eq 'UP') { 'UP,LOWER_UP' } else { 'NO-CARRIER' })> mtu $($ad.MtuSize) state $state"
                "    link/ether $(($ad.MacAddress -replace '-', ':').ToLower())"
            }
        }
        '^(r|route|ro)$' {
            $af = if ($fam -eq 'IPv6') { 'IPv6' } else { 'IPv4' }
            Get-NetRoute -AddressFamily $af -ErrorAction SilentlyContinue | Where-Object { $_.DestinationPrefix -notmatch '^(224\.|255\.|ff00)' -and $_.InterfaceAlias -notmatch 'Loopback' } | Sort-Object RouteMetric | ForEach-Object {
                $dst = if ($_.DestinationPrefix -in '0.0.0.0/0', '::/0') { 'default' } else { $_.DestinationPrefix }
                $via = if ($_.NextHop -notin '0.0.0.0', '::') { " via $($_.NextHop)" } else { '' }
                "$dst$via dev $(_lc_clean $_.InterfaceAlias) metric $($_.RouteMetric)"
            }
        }
        '^(n|neigh|neighbour|neighbor)$' { Get-NetNeighbor -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object State -ne 'Unreachable' | ForEach-Object { "$($_.IPAddress) dev $(_lc_clean $_.InterfaceAlias) lladdr $(($_.LinkLayerAddress -replace '-', ':').ToLower()) $($_.State.ToString().ToUpper())" } }
        default { 'Usage: ip [ -4 | -6 | -br ] { addr | link | route | neigh } [ show [ dev NAME ] ]' }
    }
}

function global:ifconfig {
    $ads = @(_lc_adapters | Sort-Object ifIndex)
    $ips = @(Get-NetIPAddress -ErrorAction SilentlyContinue)
    $sel = if ($args.Count) { "$($args[0])" } else { $null }
    foreach ($ad in $ads) {
        if ($sel -and $ad.Name -ne $sel) { continue }
        if (-not $sel -and $ad.Status -ne 'Up' -and $args -notcontains '-a') { continue }
        $st = Get-NetAdapterStatistics -ErrorAction SilentlyContinue | Where-Object { (_lc_clean $_.Name) -eq $ad.Name } | Select-Object -First 1
        "$($ad.Name): flags=<$(if ($ad.Status -eq 'Up') { 'UP,BROADCAST,RUNNING,MULTICAST' } else { 'BROADCAST,MULTICAST' })>  mtu $($ad.MtuSize)"
        foreach ($i in ($ips | Where-Object InterfaceIndex -eq $ad.ifIndex)) {
            if ($i.AddressFamily -eq 'IPv4') {
                $m = [uint32]0; if ($i.PrefixLength) { $m = [uint32]([math]::Pow(2, 32) - [math]::Pow(2, 32 - $i.PrefixLength)) }
                $b = [BitConverter]::GetBytes($m); [array]::Reverse($b); $mask = $b -join '.'
                "        inet $($i.IPAddress)  netmask $mask"
            } else { "        inet6 $($i.IPAddress)  prefixlen $($i.PrefixLength)" }
        }
        "        ether $(($ad.MacAddress -replace '-', ':').ToLower())"
        if ($st) { "        RX bytes $($st.ReceivedBytes)  TX bytes $($st.SentBytes)" }
        ''
    }
}

function global:ss {
    $a = @($args | ForEach-Object { "$_" })
    $flags = (($a | Where-Object { $_ -match '^-[a-zA-Z]+$' }) -join '').Replace('-', '')
    $filter = @($a | Where-Object { $_ -notmatch '^-' })
    $tcp = $flags -match 't'; $udp = $flags -match 'u'; if (-not $tcp -and -not $udp) { $tcp = $true; $udp = $flags -match 'a' }
    $listen = $flags -match 'l'; $all = $flags -match 'a'; $procs = $flags -match 'p'
    $names = @{}; if ($procs) { Get-Process | ForEach-Object { $names[$_.Id] = $_.ProcessName } }
    $rows = @()
    if ($tcp) {
        foreach ($c in (Get-NetTCPConnection -ErrorAction SilentlyContinue)) {
            $isL = $c.State -eq 'Listen'
            if (($listen -and -not $isL) -or (-not $listen -and -not $all -and ($isL -or $c.State -ne 'Established'))) { continue }
            $rows += [pscustomobject]@{ Proto = 'tcp'; State = $(if ($isL) { 'LISTEN' } else { $c.State.ToString().ToUpper() }); Local = "$($c.LocalAddress):$($c.LocalPort)"; Peer = "$($c.RemoteAddress):$(if ($isL) { '*' } else { $c.RemotePort })"; PID = $c.OwningProcess }
        }
    }
    if ($udp -and ($listen -or $all)) {
        foreach ($c in (Get-NetUDPEndpoint -ErrorAction SilentlyContinue)) { $rows += [pscustomobject]@{ Proto = 'udp'; State = 'UNCONN'; Local = "$($c.LocalAddress):$($c.LocalPort)"; Peer = '*:*'; PID = $c.OwningProcess } }
    }
    foreach ($f in $filter) {
        if ($f -match '^:?(\d+)$') { $port = $Matches[1]; $rows = @($rows | Where-Object { $_.Local -match ":$port$" -or $_.Peer -match ":$port$" }) }
        elseif ($f -match '^(sport|dport)$') { }
    }
    'Netid State      Local Address:Port                     Peer Address:Port                    ' + $(if ($procs) { 'Process' })
    foreach ($r in ($rows | Sort-Object Proto, { [int]($_.Local -replace '^.*:', '') })) {
        '{0,-5} {1,-10} {2,-38} {3,-36} {4}' -f $r.Proto, $r.State, $r.Local, $r.Peer, $(if ($procs) { "users:((`"$($names[[int]$r.PID])`",pid=$($r.PID)))" })
    }
}

# Windows netstat for Windows flags (-ano), ss for Linux ones (-tulpn, -plant).
function global:netstat {
    $a = @($args | ForEach-Object { "$_" })
    $f = (($a | Where-Object { $_ -match '^-[a-zA-Z]+$' }) -join '')
    if ($f -match '[tul]' -and $f -notmatch '[bo]') { ss @a; return }
    & (_lc_win_bin 'netstat') @a
}

function global:lsof {
    $a = @($args | ForEach-Object { "$_" })
    $i = [array]::IndexOf($a, '-i')
    if ($i -ge 0) {
        $spec = if ($i + 1 -lt $a.Count) { $a[$i + 1] } else { '' }
        $port = if ($spec -match ':(\d+)$') { $Matches[1] } else { $null }
        $names = @{}; Get-Process | ForEach-Object { $names[$_.Id] = $_.ProcessName }
        'COMMAND          PID USER      TYPE NODE NAME'
        foreach ($c in (Get-NetTCPConnection -ErrorAction SilentlyContinue)) {
            if ($port -and "$($c.LocalPort)" -ne $port -and "$($c.RemotePort)" -ne $port) { continue }
            $n = if ($c.State -eq 'Listen') { "$($c.LocalAddress):$($c.LocalPort) (LISTEN)" } else { "$($c.LocalAddress):$($c.LocalPort)->$($c.RemoteAddress):$($c.RemotePort) ($($c.State.ToString().ToUpper()))" }
            '{0,-12} {1,7} {2,-9} IPv{3}  TCP  {4}' -f $names[[int]$c.OwningProcess], $c.OwningProcess, $env:USERNAME, $(if ("$($c.LocalAddress)".Contains(':')) { 6 } else { 4 }), $n
        }
        return
    }
    _lc_err 'lsof' 'only "lsof -i [:port]" is supported on Windows (try: openfiles /query, or Sysinternals handle.exe)'
}

function global:lsblk {
    $g = _lc_getopt $args 'fadb' @('fs', 'all', 'nodeps', 'bytes') @{ fs = 'f'; all = 'a'; nodeps = 'd'; bytes = 'b' }
    $fmt = { param($b) if ($g.o.b) { [long]$b } else { _lc_human $b } }
    if ($g.o.f) { 'NAME        FSTYPE   LABEL                 UUID                                   MOUNTPOINT' } else { 'NAME        MAJ:MIN RM   SIZE RO TYPE MOUNTPOINT' }
    foreach ($d in (Get-Disk -ErrorAction SilentlyContinue | Sort-Object Number)) {
        $dn = "disk$($d.Number)"
        if ($g.o.f) { '{0,-11}' -f $dn } else { '{0,-11} {1,7} {2,2} {3,6} {4,2} {5,-4} ' -f $dn, "$($d.Number):0", $(if ($d.BusType -eq 'USB') { 1 } else { 0 }), (& $fmt $d.Size), $(if ($d.IsReadOnly) { 1 } else { 0 }), 'disk' }
        if ($g.o.d) { continue }
        $parts = @(Get-Partition -DiskNumber $d.Number -ErrorAction SilentlyContinue | Sort-Object PartitionNumber)
        for ($k = 0; $k -lt $parts.Count; $k++) {
            $p = $parts[$k]; $tree = if ($k -eq $parts.Count - 1) { '`-' } else { '|-' }
            $v = $p | Get-Volume -ErrorAction SilentlyContinue
            $mp = if ($p.DriveLetter -and $p.DriveLetter -ne [char]0) { "$($p.DriveLetter):\" } else { '' }
            if ($g.o.f) { '{0,-11} {1,-8} {2,-21} {3,-38} {4}' -f "$tree$($p.PartitionNumber)", $v.FileSystem, $v.FileSystemLabel, $v.UniqueId -replace '^\\\\\?\\Volume', '' -replace '\\$', '', $mp }
            else { '{0,-11} {1,7} {2,2} {3,6} {4,2} {5,-4} {6}' -f "$tree$($p.PartitionNumber)", "$($d.Number):$($p.PartitionNumber)", 0, (& $fmt $p.Size), 0, 'part', $mp }
        }
    }
}

function global:lscpu {
    $c = @(Get-CimInstance Win32_Processor)
    $cs = Get-CimInstance Win32_ComputerSystem
    $arch = uname -m
    "{0,-24}{1}" -f 'Architecture:', $arch
    "{0,-24}{1}" -f 'CPU op-mode(s):', $(if ($arch -eq 'x86_64') { '32-bit, 64-bit' } else { '64-bit' })
    "{0,-24}{1}" -f 'CPU(s):', [Environment]::ProcessorCount
    "{0,-24}{1}" -f 'Vendor ID:', $c[0].Manufacturer
    "{0,-24}{1}" -f 'Model name:', $c[0].Name.Trim()
    "{0,-24}{1}" -f 'Thread(s) per core:', [int]($c[0].NumberOfLogicalProcessors / [Math]::Max(1, $c[0].NumberOfCores))
    "{0,-24}{1}" -f 'Core(s) per socket:', $c[0].NumberOfCores
    "{0,-24}{1}" -f 'Socket(s):', $cs.NumberOfProcessors
    "{0,-24}{1}" -f 'CPU max MHz:', $c[0].MaxClockSpeed
    "{0,-24}{1}" -f 'L2 cache:', "$($c[0].L2CacheSize) KiB"
    "{0,-24}{1}" -f 'L3 cache:', "$($c[0].L3CacheSize) KiB"
    "{0,-24}{1}" -f 'Virtualization:', $(if ($c[0].VirtualizationFirmwareEnabled) { 'enabled' } else { 'disabled / in use by Hyper-V' })
}

function global:lsusb { Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -match '^USB\\VID_([0-9A-F]{4})&PID_([0-9A-F]{4})' } | ForEach-Object { $null = $_.InstanceId -match 'VID_([0-9A-F]{4})&PID_([0-9A-F]{4})'; 'ID {0}:{1} {2}' -f $Matches[1].ToLower(), $Matches[2].ToLower(), $_.FriendlyName } | Sort-Object -Unique }
function global:lspci { Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -match '^PCI\\' } | Sort-Object Class, FriendlyName | ForEach-Object { '{0}: {1}' -f $_.Class, $_.FriendlyName } }

# journalctl over the Windows event logs. -u svc, -n N, -f, -p err, -k, -b, --since/--until, -r.
function global:journalctl {
    $g = _lc_getopt $args 'u:n:fp:kbre' @('unit=', 'lines=', 'follow', 'priority=', 'dmesg', 'boot', 'reverse', 'since=', 'until=', 'pager-end', 'no-pager', 'system', 'user', 'utc') @{ unit = 'u'; lines = 'n'; follow = 'f'; priority = 'p'; dmesg = 'k'; boot = 'b'; reverse = 'r'; 'pager-end' = 'e' }
    $o = $g.o
    $f = @{ LogName = @('System', 'Application') }
    if ($o.k) { $f.LogName = 'System'; $f.ProviderName = @('Microsoft-Windows-Kernel-General', 'Microsoft-Windows-Kernel-Power', 'Microsoft-Windows-Kernel-Boot', 'Microsoft-Windows-Kernel-PnP', 'disk', 'Ntfs', 'volmgr') }
    if ($o.u) {
        $svc = $o.u -replace '\.service$', ''
        $s = Get-Service -Name $svc -ErrorAction SilentlyContinue; if (-not $s) { $s = Get-Service -DisplayName $svc -ErrorAction SilentlyContinue }
        $f.LogName = 'System'; $f.ProviderName = 'Service Control Manager'
        $unit = if ($s) { $s.DisplayName } else { $svc }
    }
    if ($o.p) { $lv = @{ emerg = 1; alert = 1; crit = 1; err = 2; '3' = 2; warning = 3; '4' = 3; notice = 4; info = 4; '6' = 4; debug = 5; '7' = 5; '0' = 1; '1' = 1; '2' = 1; '5' = 4 }[$o.p.Split('.')[-1]]; if ($lv) { $f.Level = 1..$lv } }
    if ($o.b) { $f.StartTime = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime }
    if ($o.since) { $d = _lc_parse_date ($o.since -replace '^(\d+) (\w+) ago$', '$1 $2 ago'); if ($d) { $f.StartTime = $d } }
    if ($o.until) { $d = _lc_parse_date $o.until; if ($d) { $f.EndTime = $d } }
    $n = if ($o.n) { [int]$o.n } elseif ($o.f -or $o.e) { 10 } else { 200 }
    $fmtEv = { param($e) '{0} {1} {2}[{3}]: {4}' -f $e.TimeCreated.ToString('MMM dd HH:mm:ss'), $env:COMPUTERNAME, $e.ProviderName, $e.ProcessId, (("$($e.Message)" -split "`r?`n")[0]) }
    $get = {
        param($max)
        $ev = @(Get-WinEvent -FilterHashtable $f -MaxEvents $(if ($o.u) { $max * 20 } else { $max }) -ErrorAction SilentlyContinue)
        if ($o.u) { $ev = @($ev | Where-Object { "$($_.Message)" -like "*$unit*" } | Select-Object -First $max) }
        $ev
    }
    $ev = @(& $get $n)
    if (-not $o.r) { [array]::Reverse($ev) }
    if (-not $ev.Count) { '-- No entries --' }
    foreach ($e in $ev) { & $fmtEv $e }
    if ($o.f) {
        $last = if ($ev.Count) { ($ev | Measure-Object -Property RecordId -Maximum).Maximum } else { 0 }
        while ($true) {
            Start-Sleep -Seconds 2
            $new = @(& $get 50 | Where-Object { $_.RecordId -gt $last }); [array]::Reverse($new)
            foreach ($e in $new) { & $fmtEv $e; if ($e.RecordId -gt $last) { $last = $e.RecordId } }
        }
    }
}
function global:dmesg { journalctl -k @args }

# systemctl / service over Windows services.
function global:_lc_svc([string]$name, [string]$cmd) {
    $n = $name -replace '\.(service|socket|timer)$', ''
    $s = Get-Service -Name $n -ErrorAction SilentlyContinue
    if (-not $s) { $s = Get-Service -DisplayName $n -ErrorAction SilentlyContinue }
    if (-not $s) { $s = @(Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*$n*" -or $_.DisplayName -like "*$n*" }); if ($s.Count -eq 1) { $s = $s[0] } else { $s = $null } }
    if (-not $s) { _lc_err $cmd "Unit $name could not be found." 4 }
    $s
}
function global:systemctl {
    $a = @($args | ForEach-Object { "$_" } | Where-Object { $_ -notin '--now', '--no-pager', '-l', '--full', '--user', '--system', '--quiet', '-q', '--no-block' })
    $now = $args -contains '--now'; $quiet = ($args -contains '--quiet') -or ($args -contains '-q')
    $verb = if ($a.Count) { $a[0] } else { 'list-units' }
    $units = @($a | Select-Object -Skip 1 | Where-Object { -not $_.StartsWith('-') })
    $opts = @($a | Select-Object -Skip 1 | Where-Object { $_.StartsWith('-') })
    switch ($verb) {
        { $_ -in 'start', 'stop', 'restart', 'reload', 'try-restart', 'reload-or-restart' } {
            if (_lc_need_admin 'systemctl') { return }
            foreach ($u in $units) {
                $s = _lc_svc $u 'systemctl'; if (-not $s) { continue }
                $act = switch -Regex ($verb) { '^start$' { 'Start-Service' } '^stop$' { 'Stop-Service' } default { 'Restart-Service' } }
                _lc_act "$act $($s.Name)" { & $act -Name $s.Name -Force -ErrorAction Stop }
            }
        }
        { $_ -in 'enable', 'disable', 'mask', 'unmask' } {
            if (_lc_need_admin 'systemctl') { return }
            foreach ($u in $units) {
                $s = _lc_svc $u 'systemctl'; if (-not $s) { continue }
                $type = switch ($verb) { 'enable' { 'Automatic' } 'unmask' { 'Manual' } default { 'Disabled' } }
                _lc_act "Set-Service $($s.Name) -StartupType $type" { Set-Service -Name $s.Name -StartupType $type -ErrorAction Stop }
                if ($now) { if ($verb -eq 'enable') { _lc_act "Start-Service $($s.Name)" { Start-Service -Name $s.Name } } else { _lc_act "Stop-Service $($s.Name)" { Stop-Service -Name $s.Name -Force } } }
                if (-not $quiet -and -not (_lc_dryrun)) { if ($verb -eq 'enable') { "Created symlink (Windows: $($s.Name) start type set to Automatic)." } else { "Removed (Windows: $($s.Name) start type set to $type)." } }
            }
        }
        'status' {
            if (-not $units.Count) { "State: running`n  Services: $(@(Get-Service | Where-Object Status -eq 'Running').Count) running"; return }
            $rc = 0
            foreach ($u in $units) {
                $s = _lc_svc $u 'systemctl'; if (-not $s) { continue }
                $w = Get-CimInstance Win32_Service -Filter "Name='$($s.Name)'" -ErrorAction SilentlyContinue
                $run = $s.Status -eq 'Running'; if (-not $run) { $rc = 3 }
                $dot = if ($run) { "$([char]27)[32m*$([char]27)[0m" } else { '*' }
                "$dot $($s.Name).service - $($s.DisplayName)"
                "     Loaded: loaded ($($w.PathName); $(@{ Auto = 'enabled'; Manual = 'manual'; Disabled = 'disabled' }["$($w.StartMode)"]))"
                "     Active: $(if ($run) { 'active (running)' } else { 'inactive (' + $s.Status.ToString().ToLower() + ')' })"
                if ($w.ProcessId) { "   Main PID: $($w.ProcessId)" }
                if ($w.Description) { "       Docs: $($w.Description)" }
                ''
            }
            $global:LASTEXITCODE = $rc
        }
        'is-active' { foreach ($u in $units) { $s = _lc_svc $u 'systemctl'; $r = if ($s -and $s.Status -eq 'Running') { 'active' } else { 'inactive' }; if (-not $quiet) { $r }; $global:LASTEXITCODE = [int]($r -ne 'active') * 3 } }
        'is-enabled' { foreach ($u in $units) { $s = _lc_svc $u 'systemctl'; $r = if ($s -and $s.StartType -eq 'Automatic') { 'enabled' } elseif ($s -and $s.StartType -eq 'Disabled') { 'disabled' } else { 'static' }; if (-not $quiet) { $r }; $global:LASTEXITCODE = [int]($r -ne 'enabled') } }
        'is-failed' { foreach ($u in $units) { $s = _lc_svc $u 'systemctl'; if ($s -and $s.Status -eq 'Stopped' -and $s.StartType -eq 'Automatic') { 'failed' } else { 'active' } } }
        { $_ -in 'list-units', 'list-unit-files' } {
            $state = ($opts | Where-Object { $_ -like '--state=*' }) -replace '--state=', ''
            $svcs = @(Get-Service -ErrorAction SilentlyContinue | Sort-Object Name)
            if ($state -eq 'running') { $svcs = @($svcs | Where-Object Status -eq 'Running') }
            elseif ($state -in 'failed') { $svcs = @($svcs | Where-Object { $_.Status -eq 'Stopped' -and $_.StartType -eq 'Automatic' }) }
            elseif ($state -in 'inactive', 'exited', 'dead') { $svcs = @($svcs | Where-Object Status -ne 'Running') }
            elseif ($verb -eq 'list-units' -and -not ($opts -contains '--all' -or $opts -contains '-a')) { $svcs = @($svcs | Where-Object Status -eq 'Running') }
            if ($units.Count) { $svcs = @($svcs | Where-Object { $n = $_.Name; $units | Where-Object { $n -like ($_ -replace '\.service$', '') } }) }
            if ($verb -eq 'list-unit-files') {
                '{0,-50} {1}' -f 'UNIT FILE', 'STATE'
                foreach ($s in $svcs) { '{0,-50} {1}' -f "$($s.Name).service", @{ Automatic = 'enabled'; Manual = 'static'; Disabled = 'disabled'; AutomaticDelayedStart = 'enabled' }["$($s.StartType)"] }
            } else {
                '  {0,-48} {1,-7} {2,-7} {3,-8} {4}' -f 'UNIT', 'LOAD', 'ACTIVE', 'SUB', 'DESCRIPTION'
                foreach ($s in $svcs) { '  {0,-48} {1,-7} {2,-7} {3,-8} {4}' -f "$($s.Name).service", 'loaded', $(if ($s.Status -eq 'Running') { 'active' } else { 'inactive' }), $s.Status.ToString().ToLower(), $s.DisplayName }
                ''; "$($svcs.Count) loaded units listed."
            }
        }
        'daemon-reload' { }
        'reset-failed' { }
        { $_ -in 'poweroff', 'halt' } { poweroff }
        'reboot' { reboot }
        'suspend' { _lc_act 'suspend' { Add-Type -AssemblyName System.Windows.Forms; [void][System.Windows.Forms.Application]::SetSuspendState('Suspend', $false, $false) } }
        'hibernate' { _lc_exec (_lc_win_bin 'shutdown') @('/h') }
        default { _lc_err 'systemctl' "unknown command '$verb' (supported: start stop restart status enable disable is-active is-enabled list-units list-unit-files mask unmask poweroff reboot suspend)" }
    }
}
function global:service {
    $a = @($args | ForEach-Object { "$_" })
    if ($a -contains '--status-all') { Get-Service | Sort-Object Name | ForEach-Object { ' [ {0} ]  {1}' -f $(if ($_.Status -eq 'Running') { '+' } else { '-' }), $_.Name }; return }
    if ($a.Count -lt 2) { 'Usage: service <name> {start|stop|restart|status}'; return }
    systemctl $a[1] $a[0]
}

function global:hostnamectl {
    $a = @($args | ForEach-Object { "$_" })
    if ($a.Count -ge 2 -and $a[0] -eq 'set-hostname') {
        if (_lc_need_admin 'hostnamectl') { return }
        _lc_act "Rename-Computer -NewName $($a[1])" { Rename-Computer -NewName $a[1] -Force; 'Takes effect after a reboot.' }
        return
    }
    $os = Get-CimInstance Win32_OperatingSystem; $cs = Get-CimInstance Win32_ComputerSystem; $bios = Get-CimInstance Win32_BIOS
    $mid = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Cryptography' -ErrorAction SilentlyContinue).MachineGuid
    ' Static hostname: {0}' -f $env:COMPUTERNAME
    '       Icon name: computer-{0}' -f $(if ($cs.PCSystemType -eq 2) { 'laptop' } else { 'desktop' })
    '      Machine ID: {0}' -f ("$mid" -replace '-', '')
    'Operating System: {0}' -f $os.Caption
    '          Kernel: Windows NT {0}' -f $os.Version
    '    Architecture: {0}' -f (uname -m)
    ' Hardware Vendor: {0}' -f $cs.Manufacturer
    '  Hardware Model: {0}' -f $cs.Model
    'Firmware Version: {0}' -f $bios.SMBIOSBIOSVersion
}

function global:timedatectl {
    $a = @($args | ForEach-Object { "$_" })
    switch ($(if ($a.Count) { $a[0] } else { 'status' })) {
        'set-timezone' {
            $tz = $a[1]
            $id = (Get-TimeZone -ListAvailable | Where-Object { $_.Id -eq $tz -or $_.DisplayName -like "*$tz*" -or $_.StandardName -eq $tz } | Select-Object -First 1).Id
            if (-not $id) {
                # IANA name (Europe/Berlin) -> Windows id via .NET when it can, else a short table.
                $iana = @{ 'UTC' = 'UTC'; 'Etc/UTC' = 'UTC'; 'Europe/London' = 'GMT Standard Time'; 'Europe/Berlin' = 'W. Europe Standard Time'; 'Europe/Paris' = 'Romance Standard Time'; 'Europe/Madrid' = 'Romance Standard Time'; 'Europe/Rome' = 'W. Europe Standard Time'; 'Europe/Amsterdam' = 'W. Europe Standard Time'; 'Europe/Moscow' = 'Russian Standard Time'; 'Asia/Jerusalem' = 'Israel Standard Time'; 'Asia/Tokyo' = 'Tokyo Standard Time'; 'Asia/Shanghai' = 'China Standard Time'; 'Asia/Kolkata' = 'India Standard Time'; 'America/New_York' = 'Eastern Standard Time'; 'America/Chicago' = 'Central Standard Time'; 'America/Denver' = 'Mountain Standard Time'; 'America/Los_Angeles' = 'Pacific Standard Time'; 'America/Sao_Paulo' = 'E. South America Standard Time'; 'Australia/Sydney' = 'AUS Eastern Standard Time' }
                $id = $iana[$tz]
            }
            if (-not $id) { _lc_err 'timedatectl' "Invalid or unknown time zone '$tz' (see: timedatectl list-timezones)"; return }
            _lc_act "Set-TimeZone -Id '$id'" { Set-TimeZone -Id $id }
        }
        'list-timezones' { Get-TimeZone -ListAvailable | ForEach-Object Id }
        'set-ntp' { _lc_exec (_lc_win_bin 'w32tm') @('/resync') }
        default {
            $now = Get-Date; $tz = Get-TimeZone
            '               Local time: {0}' -f $now.ToString('ddd yyyy-MM-dd HH:mm:ss')
            '           Universal time: {0} UTC' -f $now.ToUniversalTime().ToString('ddd yyyy-MM-dd HH:mm:ss')
            '                Time zone: {0} ({1})' -f $tz.Id, $now.ToString('zzz')
            'System clock synchronized: {0}' -f $(if ((Get-Service W32Time -ErrorAction SilentlyContinue).Status -eq 'Running') { 'yes' } else { 'no' })
        }
    }
}

function global:lsb_release {
    $g = _lc_getopt $args 'aidrcs' @('all', 'id', 'description', 'release', 'codename', 'short') @{ all = 'a'; id = 'i'; description = 'd'; release = 'r'; codename = 'c'; short = 's' }
    $o = $g.o; $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $name = (Get-CimInstance Win32_OperatingSystem).Caption -replace '^Microsoft ', ''
    $f = [ordered]@{ i = @('Distributor ID', 'Microsoft'); d = @('Description', $name); r = @('Release', "$($cv.DisplayVersion)"); c = @('Codename', "build$($cv.CurrentBuild)") }
    $sel = if ($o.a -or -not ($o.i -or $o.d -or $o.r -or $o.c)) { if ($o.a) { 'i', 'd', 'r', 'c' } else { , 'd' } } else { @('i', 'd', 'r', 'c' | Where-Object { $o[$_] }) }
    foreach ($k in $sel) { if ($o.s) { $f[$k][1] } else { "$($f[$k][0]):`t$($f[$k][1])" } }
}

function global:xdg-open {
    foreach ($t in $args) {
        $p = _lc_winpath "$t"
        _lc_act "Start-Process '$p'" { if (Test-Path -LiteralPath $p -PathType Container) { explorer.exe $p } else { Start-Process -FilePath $p } }
    }
}
function global:open { xdg-open @args }
function global:gio { if ($args.Count -and $args[0] -eq 'open') { xdg-open @($args | Select-Object -Skip 1) } else { _lc_err 'gio' 'only "gio open" is supported' } }

# xclip / xsel: -o (or no input) pastes, otherwise copies.
function global:_lc_clip($argv, $inp, [bool]$hasInput) {
    $a = @($argv | ForEach-Object { "$_" })
    $out = ($a -match '^-(o|out|-output|b?o)$') -or ($a -contains '--output') -or (-not $hasInput -and -not ($a | Where-Object { $_ -notmatch '^-' }))
    $files = @($a | Where-Object { $_ -notmatch '^-' -and $_ -notin 'clipboard', 'primary', 'secondary' })
    if ($out) { Get-Clipboard; return }
    $text = if ($files.Count) { (Get-Content -LiteralPath (_lc_winpath $files[0]) -Raw) } else { (@($inp) -join "`r`n") }
    Set-Clipboard -Value $text
}
function global:xclip { _lc_clip $args $input $MyInvocation.ExpectingInput }
function global:xsel { _lc_clip $args $input $MyInvocation.ExpectingInput }
function global:wl-copy { Set-Clipboard -Value (@($input) + @($args) -join "`r`n") }
function global:wl-paste { Get-Clipboard }

# wget on top of the real curl.exe that ships with Windows.
function global:wget {
    $g = _lc_getopt $args 'O:qcP:o:t:T:U:Nnv' @('output-document=', 'quiet', 'continue', 'directory-prefix=', 'output-file=', 'tries=', 'timeout=', 'user-agent=', 'no-check-certificate', 'header=', 'no-verbose', 'show-progress', 'progress=', 'timestamping') @{ 'output-document' = 'O'; quiet = 'q'; continue = 'c'; 'directory-prefix' = 'P'; 'output-file' = 'o'; tries = 't'; timeout = 'T'; 'user-agent' = 'U'; timestamping = 'N' }
    $o = $g.o; $c = @('-L', '--fail')
    if ($o.q -or $o.nv -or $o['no-verbose']) { $c += '-s', '-S' }
    if ($o.c) { $c += '-C', '-' }
    if ($o.t) { $c += '--retry', $o.t }
    if ($o.T) { $c += '--max-time', $o.T }
    if ($o.U) { $c += '-A', $o.U }
    if ($o['no-check-certificate']) { $c += '-k' }
    if ($o.header) { $c += '-H', $o.header }
    if ($o.P) { $c += '--create-dirs', '--output-dir', (_lc_winpath $o.P) }
    foreach ($u in $g.rest) {
        $cc = @($c)
        if ($o.O -eq '-') { } elseif ($o.O) { $cc += '-o', (_lc_winpath $o.O) } else { $cc += '-O', '--remote-header-name' }
        if (-not ($o.q) -and $o.O -ne '-') { $cc += '--progress-bar' }
        _lc_exec (_lc_win_bin 'curl') (@($cc) + $u)
    }
}

# watch [-n secs] [-d] command...
function global:watch {
    $g = _lc_getopt $args 'n:dtbeg' @('interval=', 'differences', 'no-title', 'beep', 'errexit', 'chgexit') @{ interval = 'n'; differences = 'd'; 'no-title' = 't'; beep = 'b'; errexit = 'e'; chgexit = 'g' } -stopAtFirst
    $n = if ($g.o.n) { [double]$g.o.n } else { 2 }
    $line = ($g.rest | ForEach-Object { if ($_ -match '\s') { "'$_'" } else { $_ } }) -join ' '
    $prev = $null
    while ($true) {
        $out = (Invoke-Expression $line 2>&1 | Out-String).TrimEnd()
        Clear-Host
        if (-not $g.o.t) { Write-Host ("Every {0:0.0}s: {1}" -f $n, $line).PadRight([Math]::Max(0, [Console]::WindowWidth - 25)) -NoNewline; Write-Host "$env:COMPUTERNAME: $((Get-Date).ToString('ddd MMM d HH:mm:ss yyyy'))"; Write-Host '' }
        Write-Host $out
        if ($g.o.g -and $null -ne $prev -and $out -ne $prev) { return }
        $prev = $out
        Start-Sleep -Milliseconds ([int]($n * 1000))
    }
}

# timeout DURATION command... (Windows' own `timeout /t 5` and `timeout 5` still work).
function global:timeout {
    $a = @($args | ForEach-Object { "$_" })
    if (($a | Where-Object { $_ -match '^/' }) -or ($a.Count -eq 1 -and $a[0] -match '^-?\d+$')) { & (_lc_win_bin 'timeout') @a; return }
    $g = _lc_getopt $a 's:k:' @('signal=', 'kill-after=', 'preserve-status', 'foreground', 'verbose') @{ signal = 's'; 'kill-after' = 'k' } -stopAtFirst
    $rest = @($g.rest)
    if ($rest.Count -lt 2) { _lc_err 'timeout' 'usage: timeout DURATION COMMAND [ARG]...' 125; return }
    $secs = if ($rest[0] -match '^([\d.]+)([smhd]?)$') { [double]$Matches[1] * @{ '' = 1; s = 1; m = 60; h = 3600; d = 86400 }[$Matches[2]] } else { _lc_err 'timeout' "invalid time interval '$($rest[0])'" 125; return }
    $cmd = $rest[1]; $cargs = @($rest | Select-Object -Skip 2)
    $app = Get-Command $cmd -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($app -and $app.CommandType -eq 'Application') {
        $exe = $app.Source
        $psi = New-Object Diagnostics.ProcessStartInfo $exe
        $psi.Arguments = ($cargs | ForEach-Object { if ($_ -match '[\s"]' -or $_ -eq '') { '"' + ($_ -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"' } else { $_ } }) -join ' '
        $psi.UseShellExecute = $false
        $p = [Diagnostics.Process]::Start($psi)
        if ($p.WaitForExit([int]($secs * 1000))) { $global:LASTEXITCODE = $p.ExitCode; return }
        & "$env:SystemRoot\System32\taskkill.exe" /PID $p.Id /T /F *> $null
        $global:LASTEXITCODE = 124; return
    }
    # PowerShell command: run it as a job so it can be stopped.
    $line = (@($cmd) + $cargs | ForEach-Object { _lc_q $_ }) -join ' '
    $j = Start-Job -ScriptBlock { param($h, $l) . (Join-Path $h 'linux-compat.ps1') -NonInteractive; Invoke-Expression $l } -ArgumentList $global:LC_HOME, $line
    if (Wait-Job $j -Timeout ([int][Math]::Ceiling($secs))) { Receive-Job $j; Remove-Job $j; $global:LASTEXITCODE = 0 }
    else { Stop-Job $j; Receive-Job $j; Remove-Job $j -Force; $global:LASTEXITCODE = 124 }
}

# shutdown/poweroff/reboot/halt. Windows-style args (/s /r /t, -s -t) go straight to shutdown.exe.
function global:shutdown {
    $a = @($args | ForEach-Object { "$_" })
    $linux = ($a | Where-Object { $_ -match '^(now|\+\d+|\d{1,2}:\d{2})$' -or $_ -in '-h', '-P', '-H', '--poweroff', '--halt', '--reboot', '-c', '-k' }) -or (-not $a.Count)
    if (-not $linux) { _lc_exec (_lc_win_bin 'shutdown') $a; return }
    if ($a -contains '-c') { _lc_exec (_lc_win_bin 'shutdown') @('/a'); return }
    $mode = if ($a -contains '-r' -or $a -contains '--reboot') { '/r' } else { '/s' }
    $t = 60
    foreach ($x in $a) {
        if ($x -eq 'now') { $t = 0 }
        elseif ($x -match '^\+(\d+)$') { $t = [int]$Matches[1] * 60 }
        elseif ($x -match '^(\d{1,2}):(\d{2})$') { $when = (Get-Date).Date.AddHours([int]$Matches[1]).AddMinutes([int]$Matches[2]); if ($when -lt (Get-Date)) { $when = $when.AddDays(1) }; $t = [int]($when - (Get-Date)).TotalSeconds }
    }
    $msg = @($a | Where-Object { $_ -notmatch '^(-|now$|\+\d+$|\d{1,2}:\d{2}$)' }) -join ' '
    $wa = @($mode, '/t', "$t"); if ($msg) { $wa += '/c', $msg }
    if ($a -contains '-k') { "Shutdown scheduled (dry: -k only warns)"; return }
    _lc_exec (_lc_win_bin 'shutdown') $wa
}
function global:poweroff { shutdown -h now }
function global:halt { shutdown -h now }
function global:reboot { shutdown -r now }

# Linux ping flags (-c, -W, -i, -s, -t) -> Windows ping. Plain `ping host` is untouched.
function global:ping {
    $a = @($args | ForEach-Object { "$_" }); $w = @(); $linux = $false
    for ($i = 0; $i -lt $a.Count; $i++) {
        switch -CaseSensitive -Regex ($a[$i]) {
            '^-c(\d*)$' { $linux = $true; $v = if ($Matches[1]) { $Matches[1] } else { $a[++$i] }; $w += '-n', $v }
            '^-W(\d*)$' { $linux = $true; $v = if ($Matches[1]) { $Matches[1] } else { $a[++$i] }; $w += '-w', ([int]([double]$v * 1000)) }
            '^-s(\d*)$' { $linux = $true; $v = if ($Matches[1]) { $Matches[1] } else { $a[++$i] }; $w += '-l', $v }
            '^-i$' { $linux = $true; $i++ }
            '^-q$' { $linux = $true }
            '^-t$' { if ($i + 1 -lt $a.Count -and $a[$i + 1] -match '^\d+$') { $linux = $true; $w += '-i', $a[++$i] } else { $w += '-t' } }
            default { $w += $a[$i] }
        }
    }
    if ($linux) { _lc_dbg "ping $($w -join ' ')" }
    & (_lc_win_bin 'ping') @w
}
function global:traceroute {
    $a = @($args | ForEach-Object { "$_" }); $w = @()
    for ($i = 0; $i -lt $a.Count; $i++) { switch -CaseSensitive ($a[$i]) { '-n' { $w += '-d' } '-m' { $w += '-h', $a[++$i] } '-w' { $w += '-w', ([int]$a[++$i] * 1000) } '-4' { $w += '-4' } '-6' { $w += '-6' } default { $w += $a[$i] } } }
    & (_lc_win_bin 'tracert') @w
}
function global:dig {
    $a = @($args | ForEach-Object { "$_" }); $short = $a -contains '+short'
    $server = ($a | Where-Object { $_.StartsWith('@') } | Select-Object -First 1); $rest = @($a | Where-Object { -not $_.StartsWith('@') -and -not $_.StartsWith('+') })
    $name = $rest[0]; $type = if ($rest.Count -gt 1) { $rest[1].ToUpper() } else { 'A' }
    if ($a -contains '-x') { $name = $rest[1]; $type = 'PTR' }
    $p = @{ Name = $name; Type = $type; ErrorAction = 'Stop' }; if ($server) { $p.Server = $server.Substring(1) }
    try { $r = Resolve-DnsName @p } catch { _lc_err 'dig' $_.Exception.Message; return }
    foreach ($x in ($r | Where-Object { $_.Section -eq 'Answer' -or -not $_.Section })) {
        $val = switch ($x.QueryType) { 'A' { $x.IPAddress } 'AAAA' { $x.IPAddress } 'CNAME' { $x.NameHost } 'MX' { "$($x.Preference) $($x.NameExchange)" } 'NS' { $x.NameHost } 'TXT' { '"' + ($x.Strings -join '') + '"' } 'PTR' { $x.NameHost } default { "$x" } }
        if ($short) { $val } else { "{0,-30} {1,-6} IN {2,-6} {3}" -f "$($x.Name).", $x.TTL, $x.QueryType, $val }
    }
}
