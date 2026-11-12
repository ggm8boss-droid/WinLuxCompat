# Git Bash style prompt:   user@HOST MINGW64 /e/some/path (branch)   then "$ " on the next line.
# Reads .git itself (no git.exe call), so it costs almost nothing per prompt. cmd twin: cmd\prompt.cmd.
# `linuxcompat prompt off` (state\noprompt) keeps PowerShell's own prompt in new windows.

# " (branch)" / " (branch|MERGING)" / " ((1a2b3c4...))" for the repo containing $dir, '' outside one.
function global:_lc_git_head([string]$dir) {
    $d = $dir
    $g = $null
    while ($d) {
        $dot = Join-Path $d '.git'
        if (Test-Path -LiteralPath (Join-Path $dot 'HEAD') -PathType Leaf) { $g = $dot; break }
        if (Test-Path -LiteralPath $dot -PathType Leaf) {
            # worktree / submodule: ".git" is a file "gitdir: <path>"
            $l = Get-Content -LiteralPath $dot -TotalCount 1 -ErrorAction SilentlyContinue
            if ($l -match '^gitdir:\s*(.+)$') {
                $p = $Matches[1].Trim() -replace '/', '\'
                if (-not [IO.Path]::IsPathRooted($p)) { $p = Join-Path $d $p }
                $g = $p
            }
            break
        }
        $d = [IO.Path]::GetDirectoryName($d)   # null at the drive root (Split-Path -LiteralPath -Parent fails in PS 5.1)
    }
    if (-not $g) { return '' }
    $headFile = Join-Path $g 'HEAD'
    if (-not (Test-Path -LiteralPath $headFile -PathType Leaf)) { return '' }
    $h = "$(Get-Content -LiteralPath $headFile -TotalCount 1 -ErrorAction SilentlyContinue)".Trim()

    # in-progress operations, same names as Git Bash (git-prompt.sh)
    $s = ''
    foreach ($r in 'rebase-merge', 'rebase-apply') {
        if (Test-Path -LiteralPath (Join-Path $g $r) -PathType Container) {
            $s = '|REBASE'
            $hn = Join-Path $g "$r\head-name"
            if (Test-Path -LiteralPath $hn) {
                $n = "$(Get-Content -LiteralPath $hn -TotalCount 1)".Trim()
                if ($n -like 'refs/*') { $h = "ref: $n" }
            }
            break
        }
    }
    if (-not $s) {
        foreach ($p in @(@('MERGE_HEAD', '|MERGING'), @('CHERRY_PICK_HEAD', '|CHERRY-PICKING'), @('REVERT_HEAD', '|REVERTING'), @('BISECT_LOG', '|BISECTING'))) {
            if (Test-Path -LiteralPath (Join-Path $g $p[0])) { $s = $p[1]; break }
        }
    }

    if ($h -like 'ref: refs/heads/*') { $b = $h.Substring(16) }
    elseif ($h -like 'ref: *') { $b = $h.Substring(5) }
    elseif ($h.Length -ge 7) { $b = "($($h.Substring(0, 7))...)" }   # detached HEAD
    else { return '' }
    " ($b$s)"
}

# C:\Users\me\x -> ~/x, E:\a\b -> /e/a/b (other providers, e.g. HKCU:\, are shown as they are)
function global:_lc_prompt_path {
    if ($PWD.Provider.Name -ne 'FileSystem') { return $PWD.Path }
    $p = $PWD.ProviderPath
    $h = $HOME.TrimEnd('\')
    if ($p -eq $h) { return '~' }
    if ($p.StartsWith("$h\", [StringComparison]::OrdinalIgnoreCase)) { return '~/' + ($p.Substring($h.Length + 1) -replace '\\', '/') }
    if ($p -match '^([A-Za-z]):\\?(.*)$') {
        $r = '/' + $Matches[1].ToLower()
        if ($Matches[2]) { $r += '/' + ($Matches[2] -replace '\\', '/').TrimEnd('/') }
        return $r
    }
    $p -replace '\\', '/'
}

function global:prompt {
    $code = $global:LASTEXITCODE
    $e = [char]27
    $br = ''
    if ($PWD.Provider.Name -eq 'FileSystem') { try { $br = _lc_git_head $PWD.ProviderPath } catch { $br = '' } }
    Write-Host ("`n$e[32m$env:USERNAME@$env:COMPUTERNAME $e[35mMINGW64 $e[33m$(_lc_prompt_path)$e[36m$br$e[0m")
    $global:LASTEXITCODE = $code
    '$ '
}
