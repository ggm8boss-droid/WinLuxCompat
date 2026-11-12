@echo off
rem linux-compat for cmd.exe. install.ps1 sets it as the cmd AutoRun (HKCU\Software\Microsoft\Command Processor).
rem Only for interactive cmd windows: `cmd /c ...` (scripts and programs) is left alone.

setlocal EnableDelayedExpansion
set "_lc_cl=!CMDCMDLINE!"
set "_lc_cl=!_lc_cl:"=#!"
set "_lc_skip="
if not "!_lc_cl: /c =!"=="!_lc_cl!" set "_lc_skip=1"
if not "!_lc_cl: /c#=!"=="!_lc_cl!" set "_lc_skip=1"
if not "!_lc_cl: /r =!"=="!_lc_cl!" set "_lc_skip=1"
if not "!_lc_cl: /r#=!"=="!_lc_cl!" set "_lc_skip=1"
if defined LC_FORCE set "_lc_skip="
endlocal & set "_lc_skip=%_lc_skip%"
if defined _lc_skip (set "_lc_skip=" & exit /b 0)
if exist "%~dp0..\state\disabled" exit /b 0

for %%I in ("%~dp0..") do set "LC_HOME=%%~fI"
call "%LC_HOME%\cmd\gnu.cmd"

rem bin at the END of PATH (once), so real programs always win and scripts behave as before.
setlocal EnableDelayedExpansion
set "_lc_has="
if not "!PATH:%LC_HOME%\bin=!"=="!PATH!" set "_lc_has=1"
endlocal & set "_lc_has=%_lc_has%"
if not defined _lc_has set "PATH=%PATH%;%LC_HOME%\bin"
set "_lc_has="

rem cd, mkdir -p, date are cmd built-ins and find, sort, timeout, ping... are Windows programs, so
rem those go through doskey macros (typed commands only; scripts keep the Windows ones).
doskey /macrofile="%LC_HOME%\cmd\macros.doskey"
rem Git Bash style prompt with the git branch (the cd/git/... macros refresh it).
call "%LC_HOME%\cmd\prompt.cmd"
if exist "%USERPROFILE%\.bash_aliases" call "%LC_HOME%\bin\source.cmd" "%USERPROFILE%\.bash_aliases"
exit /b 0
