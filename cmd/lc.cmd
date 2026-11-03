@rem linux-compat: run a command from the PowerShell layer (lib\run.ps1). Usage: lc.cmd NAME [ARGS...]
@"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\lib\run.ps1" %*
