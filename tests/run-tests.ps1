# linux-compat for Windows: self-test. `linuxcompat test` or
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1 [-Quick]
# Anything with side effects (winget, services, shutdown, kill, sudo) runs with LC_DRYRUN=1 and is
# checked by the command it would run. Scratch files go to tests\tmp.
param([switch]$Quick)
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$tmp = Join-Path $PSScriptRoot 'tmp'
if (-not (Test-Path $tmp)) { [void](New-Item -ItemType Directory $tmp) }
$env:TMP = $tmp; $env:TEMP = $tmp
. (Join-Path $root 'linux-compat.ps1') -NonInteractive
Set-Location $root

$script:pass = 0; $script:fail = 0
function t([string]$name, [scriptblock]$code, $expect) {
    try { $got = (& $code 2>&1 | Out-String).TrimEnd() } catch { $got = "EXCEPTION: $_" }
    $ok = if ($expect -is [scriptblock]) { [bool](& $expect $got) } else { $got -ceq "$expect" }
    if ($ok) { $script:pass++ } else { $script:fail++; Write-Host "FAIL $name`n  expected: $expect`n  got:      $got" -ForegroundColor Red }
}
function section([string]$s) { Write-Host "-- $s" -ForegroundColor Cyan }

Set-Content -LiteralPath "$tmp\f.txt" -Value 'banana', 'apple', 'cherry', 'apple'

foreach ($mode in 'gnu', 'native') {
    if ($mode -eq 'native') { $env:LC_NOGNU = '1' } else { Remove-Item env:LC_NOGNU -ErrorAction SilentlyContinue }
    $global:LC_GNU = _lc_find_gnu
    if ($mode -eq 'gnu' -and -not $global:LC_GNU) { Write-Host '-- GNU tools not found, skipping GNU mode' -ForegroundColor Yellow; continue }
    section "file/text commands ($mode)"
    t "$mode sort -u" { sort -u "$tmp\f.txt" } "apple`r`nbanana`r`ncherry"
    t "$mode sort -r pipe" { 'b', 'a', 'c' | sort -r } "c`r`nb`r`na"
    t "$mode uniq -c" { sort "$tmp\f.txt" | uniq -c | ForEach-Object { $_.Trim() } } "2 apple`r`n1 banana`r`n1 cherry"
    t "$mode grep -c" { grep -c apple "$tmp\f.txt" } '2'
    t "$mode grep -v -n" { grep -vn apple "$tmp\f.txt" } "1:banana`r`n3:cherry"
    t "$mode grep -i -E" { 'Foo', 'bar', 'BAZ' | grep -iE '^(foo|baz)$' } "Foo`r`nBAZ"
    t "$mode grep exit 1" { grep -q zzz "$tmp\f.txt"; $LASTEXITCODE } '1'
    t "$mode head -n 2" { head -n 2 "$tmp\f.txt" } "banana`r`napple"
    t "$mode head -2" { head -2 "$tmp\f.txt" } "banana`r`napple"
    t "$mode tail -n 1" { tail -n 1 "$tmp\f.txt" } 'apple'
    t "$mode tail -n +3" { tail -n +3 "$tmp\f.txt" } "cherry`r`napple"
    t "$mode wc -l" { (wc -l "$tmp\f.txt") -replace '\s+.*$', '' -replace '^\s+', '' } '4'
    t "$mode wc -w pipe" { ('a b', 'c' | wc -w).Trim() } '3'
    t "$mode cut -d -f" { 'a:b:c' | cut -d ':' -f '2,3' } 'b:c'
    t "$mode tr a-z A-Z" { 'hello' | tr a-z A-Z } 'HELLO'
    t "$mode sed s///g" { 'aaa' | sed 's/a/b/g' } 'bbb'
    t "$mode sed -n /re/p" { sed -n '/zzz/p' "$tmp\f.txt"; 'x' } 'x'
    t "$mode sed -i" { Set-Content "$tmp\s.txt" 'one two'; sed -i 's/one/1/' "$tmp\s.txt"; Get-Content "$tmp\s.txt" } '1 two'
    t "$mode seq" { (seq 3) -join ',' } '1,2,3'
    t "$mode seq -s" { seq -s ',' 1 2 5 } '1,3,5'
    t "$mode tac" { (tac "$tmp\f.txt") -join ',' } 'apple,cherry,apple,banana'
    t "$mode touch/rm -f" { touch "$tmp\new.txt"; $a = Test-Path "$tmp\new.txt"; rm -f "$tmp\new.txt"; "$a $(Test-Path "$tmp\new.txt")" } 'True False'
    t "$mode mkdir -p/rm -rf" { mkdir -p "$tmp\d1\d2\d3"; $a = Test-Path "$tmp\d1\d2\d3"; rm -rf "$tmp\d1"; "$a $(Test-Path "$tmp\d1")" } 'True False'
    t "$mode cp -r/mv" { mkdir -p "$tmp\src\x"; touch "$tmp\src\x\f"; cp -r "$tmp\src" "$tmp\dst"; mv "$tmp\dst" "$tmp\dst2"; $a = Test-Path "$tmp\dst2\x\f"; rm -rf "$tmp\src" "$tmp\dst2"; $a } 'True'
    t "$mode ls -a hidden" { mkdir -p "$tmp\lsd"; touch "$tmp\lsd\.h" "$tmp\lsd\v"; $a = (ls "$tmp\lsd") -join ','; $b = (ls -A "$tmp\lsd") -join ','; rm -rf "$tmp\lsd"; "$a|$b" } 'v|.h,v'
    t "$mode find -name" { mkdir -p "$tmp\fd\sub"; touch "$tmp\fd\sub\a.log" "$tmp\fd\b.txt"; $r = (find "$tmp\fd" -name '*.log' -type f) -replace '\\', '/'; rm -rf "$tmp\fd"; $r -replace '^.*/fd/', 'fd/' } 'fd/sub/a.log'
    t "$mode sha256sum" { 'abc' | Set-Content -NoNewline "$tmp\h.txt"; (sha256sum "$tmp\h.txt") -replace '\s.*$', '' } 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
    t "$mode base64" { 'hi' | base64 } 'aGkK'
    t "$mode base64 -d" { 'aGkK' | base64 -d } 'hi'
    t "$mode date +%Y" { date +%Y } "$((Get-Date).Year)"
    t "$mode date -d" { date -d '2024-02-29' +%F } '2024-02-29'
    t "$mode date -d yesterday" { date -d yesterday +%F } ((Get-Date).AddDays(-1).ToString('yyyy-MM-dd'))
    t "$mode test -f" { test -f "$tmp\f.txt"; $LASTEXITCODE } '0'
    t "$mode test -d fails" { test -d "$tmp\f.txt"; $LASTEXITCODE } '1'
    t "$mode xargs" { 'a b c' | xargs -n 1 echo } "a`r`nb`r`nc"
    t "$mode printf" { printf '%s=%d\n' x 5 } 'x=5'
    t "$mode diff" { Set-Content "$tmp\d1.txt" 'a', 'b'; Set-Content "$tmp\d2.txt" 'a', 'c'; diff "$tmp\d1.txt" "$tmp\d2.txt" | grep -c '^[<>]' } '2'
    t "$mode tilde" { touch "$tmp\t~x"; (ls ~ | Measure-Object).Count -gt 0 } 'True'
}
Remove-Item env:LC_NOGNU -ErrorAction SilentlyContinue
$global:LC_GNU = _lc_find_gnu

section 'PowerShell stays PowerShell'
t 'objects to sort' { (@([pscustomobject]@{ n = 2 }, [pscustomobject]@{ n = 1 }) | sort n | ForEach-Object n) -join ',' } '1,2'
t 'ls -Recurse = cmdlet' { (ls -Recurse -File "$root\cmd" | Select-Object -First 1).GetType().Name } 'FileInfo'
t 'gci | rm (objects)' { mkdir -p "$tmp\ob"; touch "$tmp\ob\a"; Get-ChildItem "$tmp\ob" | rm; (Get-ChildItem "$tmp\ob" | Measure-Object).Count } '0'
t 'ps | piped = objects' { (ps | Select-Object -First 1).GetType().Name } 'Process'
t 'cat -Raw = cmdlet' { (cat -Raw "$tmp\f.txt").GetType().Name } 'String'
t 'sleep -Milliseconds' { sleep -Milliseconds 1; 'ok' } 'ok'
t 'echo objects' { (echo 1, 2).Count } '2'

section 'bash builtins'
t 'echo -e' { echo -e 'a\tb' } "a`tb"
t 'echo -n pipe' { echo -n hi | ForEach-Object { "[$_]" } } '[hi]'
t 'echo joins' { echo a b c } 'a b c'
t 'export' { export LCT_A=1; $env:LCT_A } '1'
t 'export PATH append' { $o = $env:PATH; export "PATH=$env:PATH`:/c/lctest:~/bin"; $r = ($env:PATH -split ';')[-2, -1] -join '|'; $env:PATH = $o; $r } "C:\lctest|$HOME\bin"
t 'unset' { $env:LCT_B = 1; unset LCT_B; [string]$env:LCT_B } ''
t 'env VAR=x cmd' { env LCT_C=5 printenv LCT_C } '5'
t 'printenv' { $env:LCT_D = 'q'; printenv LCT_D } 'q'
t 'alias' { alias lct='echo aliased'; lct x } 'aliased x'
t 'which' { (which notepad) -like '*notepad.exe' } 'True'
t 'which missing' { which nope_lc_x 2>$null; $LASTEXITCODE } '1'
t 'basename' { basename 'C:\a\b\file.txt' .txt } 'file'
t 'basename /' { basename '/usr/local/bin/' } 'bin'
t 'dirname' { dirname 'C:\a\b\file.txt' } 'C:\a\b'
t 'realpath' { Push-Location $tmp; $r = realpath ..\tmp; Pop-Location; $r } $tmp
t 'cd - / OLDPWD' { Push-Location; cd $tmp; cd $root; $r = cd -; cd $root; Pop-Location; $r } $tmp
t 'cd /c/ path' { Push-Location; cd /c/Windows; $r = (Get-Location).Path; Pop-Location; $r } 'C:\Windows'
t 'pwd string' { Push-Location $tmp; $r = pwd; Pop-Location; $r.GetType().Name + ' ' + $r } "String $tmp"
t 'mktemp' { $f = mktemp; $r = (Test-Path $f) -and $f.StartsWith($tmp); Remove-Item $f; $r } 'True'
t 'mktemp -d' { $f = mktemp -d; $r = Test-Path $f -PathType Container; Remove-Item $f; $r } 'True'
if ((Get-Volume -DriveLetter $tmp[0] -ErrorAction SilentlyContinue).FileSystem -eq 'NTFS') { t 'ln hard' { Set-Content "$tmp\lt.txt" 'x'; Remove-Item "$tmp\lt2.txt" -ErrorAction SilentlyContinue; ln "$tmp\lt.txt" "$tmp\lt2.txt"; Get-Content "$tmp\lt2.txt" } 'x' }
t 'source rc file' { Set-Content "$tmp\rc" "alias lcrc='echo rc'", 'export LCRC=7', '# comment', 'echo should-not-run'; source "$tmp\rc"; "$(lcrc) $env:LCRC" } 'rc 7'

section 'line rewrite'
t 'rw &&' { Invoke-Expression (_lc_rewrite 'echo a && echo b') } "a`r`nb"
t 'rw && stops' { Invoke-Expression (_lc_rewrite 'grep -q zzz $tmp\f.txt && echo NO') } ''
t 'rw ||' { Invoke-Expression (_lc_rewrite 'grep -q zzz $tmp\f.txt || echo fallback') } 'fallback'
t 'rw && ||' { Invoke-Expression (_lc_rewrite 'false && echo x || echo y') } 'y'
t 'rw VAR=x cmd' { Invoke-Expression (_lc_rewrite 'LCT_E=hi printenv LCT_E'); "|$env:LCT_E" } "hi`r`n|"
t 'rw VAR=x' { Invoke-Expression (_lc_rewrite 'LCT_F="a b"'); $LCT_F } 'a b'
t 'rw $ENV' { _lc_rewrite 'echo $PATH' } 'echo ${env:PATH}'
t 'rw $ENV in quotes' { _lc_rewrite 'echo "$USERPROFILE/x"' } 'echo "${env:USERPROFILE}/x"'
t 'rw keeps PS vars' { _lc_rewrite 'echo $HOME $PSHOME' } 'echo $HOME $PSHOME'
t 'rw keeps lowercase' { _lc_rewrite 'foreach ($path in 1) { $path }' } 'foreach ($path in 1) { $path }'
t 'rw keeps single quotes' { _lc_rewrite "echo '`$PATH && x'" } "echo '`$PATH && x'"
t 'rw /dev/null' { _lc_rewrite 'ls x 2>/dev/null' } 'ls x 2>$null'
t 'rw &>/dev/null' { _lc_rewrite 'ls &>/dev/null' } 'ls *>$null'
t 'rw < file' { Invoke-Expression (_lc_rewrite "wc -l < '$tmp\f.txt'") | ForEach-Object { $_.Trim() } } '4'
t 'rw quotes -f2,3' { _lc_rewrite 'cut -d: -f2,3 x | sort -t, -k2' } "cut '-d:' '-f2,3' x | sort '-t,' -k2"
t 'rw find -exec' { _lc_rewrite 'find . -name x -exec rm {} \;' } "find . -name x -exec rm '{}' ';'"
t 'rw quoted cut runs' { Invoke-Expression (_lc_rewrite "echo a:b:c | cut -d: -f2,3") } 'b:c'
t 'rw source ps1' { _lc_rewrite 'source x.ps1' } '. x.ps1'
t 'rw bash for' { Invoke-Expression (_lc_rewrite 'for i in 1 2; do echo n$i; done') } { param($g) if ($global:LC_GNU) { $g -eq "n1`nn2" -or $g -eq "n1`r`nn2" } else { $g -match 'no bash' } }
t 'rw bash if' { Invoke-Expression (_lc_rewrite 'if [ -d / ]; then echo dir; fi') } { param($g) -not $global:LC_GNU -or $g -eq 'dir' }
t 'rw leaves PS alone' { _lc_rewrite 'Get-Process | Where-Object { $_.CPU -gt 1 } | Select -First 1' } 'Get-Process | Where-Object { $_.CPU -gt 1 } | Select -First 1'
t 'rw leaves hashtable' { _lc_rewrite '$h = @{a=1;b=2}; $h.a' } '$h = @{a=1;b=2}; $h.a'
t 'rw background' { _lc_rewrite 'sleep 1 &' } { param($g) $g -like "_lc_bg '*'" }

section 'system tools'
t 'uname -s' { uname -s } 'Windows_NT'
t 'uname -m' { uname -m } { param($g) $g -in 'x86_64', 'aarch64', 'i686' }
t 'nproc' { nproc } "$([Environment]::ProcessorCount)"
t 'free -h' { (free -h)[1] } { param($g) $g -match '^Mem:\s+[\d.]+Gi' }
t 'df -h' { (df -h)[0] } { param($g) $g -match '^Filesystem\s+Size\s+Used\s+Avail\s+Use%\s+Mounted on' }
t 'ps aux header' { (ps aux)[0] } { param($g) $g -match '^USER\s+PID %CPU %MEM' }
t 'ps -ef has self' { ps -ef | grep -c powershell } { param($g) [int]$g -ge 1 }
t 'pgrep' { pgrep -x powershell | Select-Object -First 1 } { param($g) $g -match '^\d+$' }
t 'pidof' { (pidof powershell) -match '^\d' } 'True'
t 'uptime -p' { uptime -p } { param($g) $g -like 'up *minute*' }
t 'hostname' { hostname } $env:COMPUTERNAME
t 'hostname -I' { hostname -I } { param($g) $g -match '\d+\.\d+\.\d+\.\d+' }
t 'id -un' { id -un } $env:USERNAME
t 'ip a' { (ip a)[0] } { param($g) $g -match '^1: lo:' }
t 'ip route' { ip route | Select-Object -First 1 } { param($g) $g -match 'dev ' }
t 'ss -tln' { (ss -tln)[0] } { param($g) $g -match '^Netid State' }
t 'netstat -tulpn -> ss' { (netstat -tulpn)[0] } { param($g) $g -match '^Netid' }
t 'lscpu' { (lscpu)[0] } { param($g) $g -match '^Architecture:' }
t 'lsb_release -is' { lsb_release -is } 'Microsoft'
t 'systemctl is-active' { systemctl is-active Winmgmt } 'active'
t 'systemctl status' { (systemctl status Winmgmt)[0] } { param($g) $g -match 'Winmgmt\.service' }
t 'service --status-all' { service --status-all | Select-Object -First 1 } { param($g) $g -match '^ \[ [+-] \]' }
t 'timedatectl' { (timedatectl)[0] } { param($g) $g -match 'Local time:' }
if (-not $Quick) {
    t 'journalctl -n 2' { @(journalctl -n 2).Count } { param($g) [int]$g -ge 1 }
    t 'lsblk' { (lsblk)[0] } { param($g) $g -match '^NAME' }
    t 'top -b -n 1' { (top -b -n 1 -d 0.2)[0] } { param($g) $g -match '^top - ' }
}

section 'dry-run: package managers, services, power, kill, sudo'
$env:LC_DRYRUN = '1'
t 'apt install -y' { apt install -y git } '[dry] winget.exe install --id Git.Git --exact --accept-package-agreements --accept-source-agreements --silent'
t 'apt install unknown' { apt install foo } '[dry] winget.exe install foo'
t 'apt-get remove' { apt-get remove vim } '[dry] winget.exe uninstall --id vim.vim --exact'
t 'apt update' { apt update } '[dry] winget.exe source update'
t 'apt upgrade' { apt upgrade } '[dry] winget.exe upgrade --all'
t 'apt -dev skipped' { apt install libssl-dev } { param($g) $g -match 'skipping' }
t 'apt search' { apt search ripgrep } '[dry] winget.exe search ripgrep'
t 'apt list --upgradable' { apt list --upgradable } '[dry] winget.exe upgrade'
t 'yum install -y' { yum install -y nodejs } '[dry] winget.exe install --id OpenJS.NodeJS.LTS --exact --accept-package-agreements --accept-source-agreements --silent'
t 'dnf update (all)' { dnf update } '[dry] winget.exe upgrade --all'
t 'pacman -Syu' { pacman -Syu } '[dry] winget.exe upgrade --all'
t 'pacman -S' { pacman -S jq } '[dry] winget.exe install --id jqlang.jq --exact'
t 'pacman -Ss' { pacman -Ss fzf } '[dry] winget.exe search fzf'
t 'brew install' { brew install fd } '[dry] winget.exe install --id sharkdp.fd --exact'
t 'zypper in' { zypper in git } '[dry] winget.exe install --id Git.Git --exact'
t 'systemctl restart' { systemctl restart spooler.service } '[dry] Restart-Service spooler'
t 'systemctl enable --now' { (systemctl enable --now spooler) -join '|' } '[dry] Set-Service spooler -StartupType Automatic|[dry] Start-Service spooler'
t 'service x stop' { service spooler stop } '[dry] Stop-Service spooler'
t 'shutdown -h now' { shutdown -h now } '[dry] shutdown.exe /s /t 0'
t 'shutdown -r +5' { shutdown -r +5 } '[dry] shutdown.exe /r /t 300'
t 'shutdown -c' { shutdown -c } '[dry] shutdown.exe /a'
t 'shutdown /s /t 0 (Windows)' { shutdown /s /t 0 } '[dry] shutdown.exe /s /t 0'
t 'reboot' { reboot } '[dry] shutdown.exe /r /t 0'
t 'kill -9' { kill -9 $PID } { param($g) $g -match "^\[dry\] Stop-Process $PID .*-Force$" }
t 'killall' { killall -q nope_lc_proc; $LASTEXITCODE } '1'
t 'wget' { wget https://example.com/a.zip } '[dry] curl.exe -L --fail -O --remote-header-name --progress-bar https://example.com/a.zip'
t 'wget -qO-' { wget -qO- https://example.com } '[dry] curl.exe -L --fail -s -S https://example.com'
t 'wget -O file' { wget -O out.bin https://example.com/x } '[dry] curl.exe -L --fail -o out.bin --progress-bar https://example.com/x'
t 'sudo cmd' { sudo apt install git } { param($g) $g -match "^\[dry\] sudo\[\d\] ps apt install git$" }
t 'sudo quoting' { sudo rm -rf 'C:\a b' } { param($g) $g -match "^\[dry\] sudo\[\d\] ps rm -rf 'C:\\a b'$" }
Remove-Item env:LC_DRYRUN

section 'cmd.exe'
$cmdTest = Join-Path $tmp 'cmdtest.cmd'
@"
@echo off
set LC_FORCE=1
call "$root\cmd\init.cmd"
cd /d "$root"
echo ##gnu %LC_GNU%
call ls README.md
dir /b tests\run-tests.ps1 | grep -c run
call "%LC_HOME%\cmd\shadow\sort.cmd" -r "$tmp\f.txt" | head -n 1
type "$tmp\f.txt" | gsort -u | gfind /c /v ""
call "%LC_HOME%\cmd\shadow\find.cmd" /c "apple" "$tmp\f.txt"
call uname -s
call export LCX=1 LCY=`$USERNAME
echo ##export %LCX% %LCY%
call export PATH=`$PATH:/c/lcx
echo %PATH% | findstr /c:";C:\lcx" >nul && echo ##path ok
call "%LC_HOME%\cmd\cd.cmd" /c/Windows
echo ##cd %CD%
call "%LC_HOME%\cmd\cd.cmd" -
call grep -q zzz README.md
echo ##rc %errorlevel%
call test -f README.md && echo ##test ok
call "%LC_HOME%\cmd\mkdir.cmd" -p "$tmp\c1\c2" && echo ##mkdir ok
"%LC_HOME%\cmd\date.cmd" +%%Y
"@ | Set-Content -LiteralPath $cmdTest -Encoding ASCII
$cmdOut = (cmd /d /c "`"$cmdTest`" < NUL" 2>&1 | Out-String) -split "`r?`n"
$has = { param($pat) [bool]($cmdOut | Where-Object { $_ -match $pat }) }
t 'cmd init + GNU' { & $has '^##gnu \S' } 'True'
t 'cmd ls' { & $has '^README\.md$' } 'True'
t 'cmd pipe into grep' { & $has '^1$' } 'True'
t 'cmd sort -r (GNU)' { & $has '^cherry$' } 'True'
t 'cmd gsort | gfind (Windows /c)' { & $has '^3$' } 'True'
t 'cmd find /c (Windows)' { & $has 'F\.TXT: 2$' } 'True'
t 'cmd uname (PowerShell side)' { & $has '^Windows_NT$' } 'True'
t 'cmd export $VAR' { & $has "^##export 1 $env:USERNAME$" } 'True'
t 'cmd export PATH a:b' { & $has '^##path ok$' } 'True'
t 'cmd cd /c/...' { & $has '^##cd C:\\Windows$' } 'True'
t 'cmd cd -' { & $has ([regex]::Escape($root) + '$') } 'True'
t 'cmd exit code' { & $has '^##rc 1$' } 'True'
t 'cmd test' { & $has '^##test ok$' } 'True'
t 'cmd mkdir -p' { & $has '^##mkdir ok$' } 'True'
t 'cmd date +%Y' { & $has "^$((Get-Date).Year)$" } 'True'
t 'cmd /c skips AutoRun' { (cmd /d /c "`"$root\cmd\init.cmd`" & if defined LC_HOME (echo loaded) else (echo skipped)" 2>&1 | Out-String).Trim() } 'skipped'
Remove-Item -Recurse -Force "$tmp\c1" -ErrorAction SilentlyContinue

''
$color = if ($script:fail) { 'Red' } else { 'Green' }
Write-Host "$($script:pass) passed, $($script:fail) failed" -ForegroundColor $color
exit [int]($script:fail -gt 0)
