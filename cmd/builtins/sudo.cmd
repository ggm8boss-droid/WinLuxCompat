@echo off
rem sudo COMMAND: run it in an elevated cmd (Windows sudo inline when enabled, else a UAC admin window).
rem sudo -i / sudo su / sudo cmd: admin cmd shell. Windows sudo's own options (config, -N, ...) pass through.
if "%~1"=="" (echo usage: sudo command [args...]   ^(sudo -i for an admin shell^) & exit /b 1)
for %%o in (config --new-window -N --inline --disable-input --chdir -D --help -h --version -V) do if /i "%~1"=="%%o" ("%SystemRoot%\System32\sudo.exe" %* & exit /b)
setlocal
set "LC_SUDO_LINE=%*"
set "LC_SUDO_SHELL=cmd"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\lib\run.ps1" _lc_cmd_sudo
