# linux-compat for Windows

Type Linux/bash commands in **PowerShell** and **cmd** and they work: `ls -la`, `rm -rf`,
`grep -rn`, `sed -i`, `cat f | sort | uniq -c`, `apt install git`, `sudo systemctl restart spooler`,
`free -h`, `ip a`, `ps aux`, `export PATH=$PATH:~/bin`, `cmd1 && cmd2`, `for f in *.txt; do ...; done`...
It's the Windows version of the macOS `LinuxCompat` layer. Nothing is printed unless you turn debug on.

## Install

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "E:\claude projects\WinLinuxCompat\install.ps1"
```

All the code stays in this folder. The installer only adds:
- a 4-line block to your PowerShell profile (`Documents\WindowsPowerShell\profile.ps1`, plus
  `Documents\PowerShell\profile.ps1` if PowerShell 7 is installed) that loads `linux-compat.ps1`;
- cmd's AutoRun value (`HKCU\Software\Microsoft\Command Processor`) pointing to `cmd\init.cmd`.

Backups of what was there go to `state\`. `uninstall.ps1` removes both.

Two things only you can switch on, the installer tells you if they're needed:
1. **Execution policy.** Windows blocks profile scripts by default. Once:
   `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`
2. **Windows sudo**, for `sudo` in the same window: Settings > System > For developers >
   Enable sudo, and set it to **Inline**. Until then `sudo` opens a separate admin window.

Recommended: Git for Windows (`winget install Git.Git`). Its real GNU tools (`ls`, `grep`, `sed`, `awk`,
`find`, `xargs`...) are used when present, so flags behave exactly like Linux. Without them,
built-in PowerShell versions cover the common flags.

## Commands

| | |
|---|---|
| `linuxcompat status` | what's active: GNU tools, sudo mode, execution policy, cmd hook |
| `linuxcompat debug on` / `off` | show each translation, dimmed: `[linux-compat] -> GNU grep -rn x .` |
| `linuxcompat gnu off` / `on` | use only the PowerShell versions / use GNU tools again |
| `linuxcompat prompt off` / `on` | Git Bash style prompt with the git branch (both shells, new windows). In cmd it refreshes after `cd`, `pushd`, `popd`, `git` and drive changes like `e:` |
| `linuxcompat test` | self-test (send the output if something's wrong) |
| `linuxcompat off` / `on` | disable / re-enable for new windows |
| `linuxcompat uninstall` | remove the profile block and the cmd hook |

## What works

**File and text commands** (GNU tool if found, else PowerShell): `ls` `cat` `grep` `egrep` `sed`
`awk` `head` `tail` `wc` `sort` `uniq` `cut` `tr` `tee` `touch` `rm` `cp` `mv` `mkdir` `rmdir`
`chmod` `find` `xargs` `diff` `du` `stat` `date` (`-d yesterday`, `+%F`) `seq` `sleep` `tac`
`base64` `md5sum` `sha256sum` `less` `nano` `vim` `gzip` `zcat` `unzip` `test` `printf`... plus
`ln -s` (symlink, or a junction without the privilege), `realpath`, `readlink -f`, `basename`,
`dirname`, `mktemp`, `which`, `env`, `printenv`, `man`, `ll`/`la`/`l`.

**System tools:** `ps aux`/`-ef`/`-o`, `kill -9`, `killall`, `pkill`, `pgrep`, `pidof`, `top`/`htop`,
`free -h`, `df -h`, `uname -a`, `uptime -p`, `nproc`, `id`, `hostname -I`, `ip a`/`ip route`/`ip -br a`,
`ifconfig`, `ss -tulpn`, `netstat -tulpn` (Windows `netstat -ano` still works), `lsof -i :80`,
`lsblk`, `lscpu`, `lsusb`, `lspci`, `journalctl -u svc -n 50 -f`, `dmesg`, `systemctl`
(start/stop/restart/status/enable/disable/is-active/list-units), `service x start`, `hostnamectl`,
`timedatectl set-timezone Europe/Berlin`, `lsb_release -a`, `xdg-open`/`open`, `xclip`/`xsel`
(clipboard), `wget` (on Windows' curl.exe), `watch -n 2`, `timeout 5 cmd`, `ping -c 4`,
`traceroute`, `dig`, `shutdown -h now`/`-r +5`/`-c`, `poweroff`, `reboot`.

**Package managers → winget:** `apt` `apt-get` `apt-cache` `dpkg -l` `yum` `dnf` `zypper` `pacman`
`apk` `snap` `flatpak` `brew`. Common names are mapped (`nodejs` → `OpenJS.NodeJS.LTS`, `python3`,
`build-essential`, `docker.io`, `ripgrep`...); `-dev` libraries are skipped; `-y` accepts the
winget agreements and installs silently.

**sudo** = run as administrator. `sudo apt install x`, `sudo rm -rf x`, `sudo systemctl stop x`
work because the elevated side loads linux-compat too. `sudo -i` / `sudo su` = admin shell.

**bash syntax in PowerShell** (rewritten when you press Enter; history keeps what you typed):
`a && b || c`, `VAR=x cmd`, `X=1`, `export`/`unset`, `$PATH`/`$USERPROFILE` env vars,
`2>/dev/null`, `&>/dev/null`, `cmd < file`, `!!`, `sudo !!`, `cmd &` (job; `jobs`, `fg`),
`source ~/.bashrc` (aliases and exports), `alias ll='ls -l'`, `read -p`, `cd -`, `cd` (home),
`cd /c/Users`, `echo -e`/`-n`, and `-f2,3` / `-d:` / `{} \;` args. Lines PowerShell can't parse at all
(`for ... do ... done`, `if [ ]; then fi`, `while`, `case`) run in Git's bash. `~/.bash_aliases`
is loaded at start.

**PowerShell still works:** objects piped in (`Get-Process | sort CPU`, `gci | rm`), PowerShell
parameters (`ls -Recurse`, `rm -Force`, `cat -Raw`, `sort -Unique`) and `ps | where ...` go to the
normal cmdlets. `gci`/`dir` still give objects.

## cmd

Same commands, as `.cmd` files in `bin\` (added to the END of PATH, so real programs always win and
scripts behave as before). GNU commands run the GNU exe directly (fast); system tools start
PowerShell (about half a second). Bash habits: `export X=1`, `export PATH=$PATH:/c/tools`,
`unset`, `alias ll='ls -la'` (doskey), `unalias`, `source file`, `history`, `pwd`, `clear`,
`cd ~`, `cd -`, `cd /c/x`, `mkdir -p`, `date +%F`, `sudo`. `&&` and `||` are native in cmd.

Names that are also cmd built-ins or Windows programs (`cd`, `mkdir`, `date`, `find`, `sort`,
`timeout`, `ping`, `netstat`, `hostname`, `shutdown`, `sudo`) are doskey macros, so only what you
type changes; Windows syntax (`find "x" file`, `sort /r`, `timeout /t 5`, `date /t`, `rmdir /s`)
still goes to Windows. After a pipe use `gsort`, `gfind`, `gtimeout` for the GNU ones.

## Limits

- cmd can't rewrite lines, so in cmd there is no `VAR=x cmd`, `$VAR`, `/dev/null`, `!!` or bash loops.
- In PowerShell, the `&&`/`$PATH`/`VAR=x` rewrite happens at the prompt (Enter key), not in .ps1
  scripts. Scripts can call the commands, but use PowerShell syntax.
- Windows has no Unix permissions: `chmod` only maps `w` to the read-only flag (GNU chmod is a no-op).
- `ps` USER is approximate (SYSTEM for session 0, you otherwise) unless run with sudo.
- `systemctl` manages Windows services; Linux unit names that don't exist on Windows just fail.
