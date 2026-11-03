@echo off
rem unalias NAME... (doskey macros)
:loop
if "%~1"=="" exit /b 0
doskey %~1=
shift
goto loop
