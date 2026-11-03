@echo off
rem cd with bash habits: `cd` = home, `cd -` = previous dir, ~ and /c/... paths. Changes drive too.
set "_lc_t=%*"
if defined _lc_t set "_lc_t=%_lc_t:"=%"
if "%_lc_t%"=="/?" (cd /? & goto done)
if /i "%_lc_t:~0,3%"=="/d " set "_lc_t=%_lc_t:~3%"
if not defined _lc_t set "_lc_t=%USERPROFILE%"
if "%_lc_t%"=="~" set "_lc_t=%USERPROFILE%"
if "%_lc_t:~0,2%"=="~/" set "_lc_t=%USERPROFILE%\%_lc_t:~2%"
if "%_lc_t:~0,2%"=="~\" set "_lc_t=%USERPROFILE%\%_lc_t:~2%"
if "%_lc_t%"=="-" goto back
if not "%_lc_t:~0,1%"=="/" goto go
if "%_lc_t:~2,1%"=="/" set "_lc_t=%_lc_t:~1,1%:\%_lc_t:~3%" & goto go
if "%_lc_t:~2%"=="" set "_lc_t=%_lc_t:~1,1%:\"
goto go
:back
if not defined OLDPWD (echo cd: OLDPWD not set 1>&2 & goto done)
set "_lc_t=%OLDPWD%"
echo %OLDPWD%
:go
set "_lc_o=%CD%"
cd /d "%_lc_t:/=\%" && set "OLDPWD=%_lc_o%"
:done
set "_lc_t=" & set "_lc_o="
