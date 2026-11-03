@echo off
rem unset NAME... (also: unset -f NAME removes a doskey alias)
:loop
if "%~1"=="" exit /b 0
if "%~1"=="-v" (shift & goto loop)
if "%~1"=="-f" (doskey %~2= & shift & shift & goto loop)
set "%~1="
shift
goto loop
