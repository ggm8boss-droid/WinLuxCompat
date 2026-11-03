@rem linux-compat: start of an elevated cmd from `sudo -i` / `sudo su`. %1 or LC_SUDO_CWD = starting folder.
@if not "%~1"=="" (cd /d "%~1") else if defined LC_SUDO_CWD cd /d "%LC_SUDO_CWD%"
@set "LC_SUDO_CWD="
@title Administrator: linux-compat
@call "%~dp0init.cmd"
