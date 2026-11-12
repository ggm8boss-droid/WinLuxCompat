@echo off
rem Git Bash style prompt for cmd:   user@HOST MINGW64 /e/some/path (branch)   then "$ " on the next line.
rem cmd has no per-prompt hook, so init.cmd runs this once and the cd/pushd/popd/git/drive-letter
rem macros (macros.doskey) run it again after each of those commands. Reads .git itself (no git.exe).
rem `linuxcompat prompt off` (state\noprompt) leaves cmd's own prompt alone.
if exist "%~dp0..\state\noprompt" exit /b 0
setlocal EnableDelayedExpansion

rem --- path: home -> ~, E:\a\b -> /e/a/b ---
set "_t=!CD!\"
set "_t=!_t:%USERPROFILE%\=|!"
if "!_t:~0,1!"=="|" (
    set "_p=~/!_t:~1!"
) else (
    set "_p=!CD!"
    set "_dl=!_p:~0,1!"
    for %%L in (a b c d e f g h i j k l m n o p q r s t u v w x y z) do if /i "!_dl!"=="%%L" set "_dl=%%L"
    set "_p=/!_dl!/!_p:~3!"
)
set "_p=!_p:\=/!"
if "!_p:~-1!"=="/" if not "!_p!"=="/" set "_p=!_p:~0,-1!"

rem --- find the repo: walk up looking for .git (a folder, or a file "gitdir: ..." for worktrees/submodules) ---
set "_g=" & set "_b=" & set "_s=" & set "_hb="
set "_d=!CD!"
:up
if exist "!_d!\.git\HEAD" (set "_g=!_d!\.git" & goto head)
if exist "!_d!\.git" goto gitfile
for %%P in ("!_d!\..") do set "_n=%%~fP"
if /i "!_n!"=="!_d!" goto show
set "_d=!_n!"
goto up

:gitfile
set "_l="
set /p "_l=" < "!_d!\.git"
if not "!_l:~0,8!"=="gitdir: " goto show
set "_g=!_l:~8!"
set "_g=!_g:/=\!"
if not "!_g:~1,1!"==":" set "_g=!_d!\!_g!"

:head
if not exist "!_g!\HEAD" (set "_g=" & goto show)
set "_h="
set /p "_h=" < "!_g!\HEAD"
rem in-progress operations, same names as Git Bash (git-prompt.sh)
if exist "!_g!\rebase-merge\" (set "_s=|REBASE" & set /p "_hb=" < "!_g!\rebase-merge\head-name" & goto branch)
if exist "!_g!\rebase-apply\" (set "_s=|REBASE" & if exist "!_g!\rebase-apply\head-name" set /p "_hb=" < "!_g!\rebase-apply\head-name")
if exist "!_g!\rebase-apply\" goto branch
if exist "!_g!\MERGE_HEAD" (set "_s=|MERGING" & goto branch)
if exist "!_g!\CHERRY_PICK_HEAD" (set "_s=|CHERRY-PICKING" & goto branch)
if exist "!_g!\REVERT_HEAD" (set "_s=|REVERTING" & goto branch)
if exist "!_g!\BISECT_LOG" set "_s=|BISECTING"

:branch
if "!_hb:~0,5!"=="refs/" set "_h=ref: !_hb!"
if "!_h:~0,16!"=="ref: refs/heads/" (set "_b=!_h:~16!" & goto show)
if "!_h:~0,5!"=="ref: " (set "_b=!_h:~5!" & goto show)
rem detached HEAD: short commit id, like Git Bash's ((1a2b3c4...))
set "_b=(!_h:~0,7!...)"

:show
set "_p=!_p:$=$$!"
set "_x="
if defined _g set "_x=$E[36m (!_b:$=$$!!_s!)"
endlocal & set "PROMPT=$_$E[32m%USERNAME%@%COMPUTERNAME% $E[35mMINGW64 $E[33m%_p%%_x%$E[0m$_$$ "
exit /b 0
