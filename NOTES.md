# linux-compat for Windows: notes

Windows port of `..\LinuxCompat` (macOS zsh). Linux/bash commands in Windows PowerShell 5.1 and cmd.

## Decisions (asked the user, 2026-11-03)
- Hook-in: tiny stubs. Code stays on E:; only a 4-line block in the PS profile (Documents, on C:)
  and HKCU cmd AutoRun. No user-PATH registry entry (init.cmd adds bin per cmd session instead).
- Engine: hybrid. GNU tools from Git for Windows / MSYS2 / Cygwin / Scoop when found, else native
  PowerShell fallbacks (`_lc_n_<cmd>` in lib\native.ps1).
- sudo: Windows' built-in sudo (inline = same window); if off, UAC new admin window that stays open.
  The user still has to enable sudo (Settings > For developers) and set CurrentUser RemoteSigned
  themselves: both are security settings, never changed by us.
- Scope: all four (file/text, package managers -> winget, system tools, bash syntax).
- This PC: PS 5.1 only, Git at C:\Program Files\Git, Windows in Hebrew locale (adapter names carry
  U+200E marks; console code page is not UTF-8). E: is not NTFS (no hard links there).

## Layout
- `linux-compat.ps1` loader (`-NonInteractive` for run.ps1/jobs: no PSReadLine hook), `linuxcompat` cmd.
- `lib\common.ps1` getopt (ORDINAL hashtable: -a vs -A), debug, GNU lookup, `_lc_exec` (LC_DRYRUN=1).
- `lib\gnu.ps1` one function per GNU command -> `_lc_call`: objects/PS-style params -> cmdlet,
  Windows syntax (find "x", sort /r) -> Windows exe, else GNU exe, else native.
- `lib\bashcompat.ps1` builtins + `_lc_rewrite` (Enter key via PSReadLine; history keeps the typed line).
- `lib\run.ps1` entry for cmd shims and the elevated side of sudo. No param() block on purpose.
- `cmd\init.cmd` AutoRun (skips `cmd /c`), `cmd\macros.doskey`, `cmd\shadow\` (find/sort/timeout),
  `cmd\builtins\` (copied to bin). `bin\` is GENERATED: `tools\gen-shims.ps1` (install runs it).

## Gotchas
- `function f { ... }` + `$args`, never [CmdletBinding] (would eat -e/-v as common params).
- `_lc_args` returns `, $array`: assign it, don't wrap in @() (made a nested array once).
- PS 5.1 pipes into programs using Console.InputEncoding: a UTF-8 one with BOM prefixed the first
  line with a BOM. Encodings are switched only for the duration of a GNU call.
- PS->program pipes send CRLF; `_lc_pipe_lf` feeds GNU tools LF (Process + async copy). Pagers
  (less/vim/nano) keep PowerShell's pipe so they get the console.
- switch -Regex runs every matching branch: add `break` (pacman -Syu matched twice).
- Hashtable literals are case-insensitive: strftime %a/%A etc. is a `switch -CaseSensitive`.
- .ps1 files must be ASCII (or BOM): PS 5.1 reads BOM-less files as ANSI.
- cmd: a .cmd found on PATH under a Windows name (sort.cmd) breaks .bat files that call `sort`
  without `call` (control never returns). So bin is appended to PATH and those names are macros.
- cmd: `call x.cmd +%Y` expands % twice; date macro/wrapper don't use call.
- run.ps1 reads stdin only for text filters: an open-but-idle stdin pipe hung `free` forever.

## Testing
- `tests\run-tests.ps1` (`linuxcompat test`): GNU and native modes, PS passthrough, builtins,
  rewrite, system tools, dry-run of winget/services/shutdown/kill/sudo, and a cmd.exe batch.
  Run with stdin from NUL. 2026-11-03: 199/199 pass.
- NOT covered automatically: the Enter-key hook itself (needs a real console; it loads without
  errors in an interactive tab), real sudo elevation (Windows sudo was off), real winget/service changes.
