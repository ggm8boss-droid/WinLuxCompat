# linux-compat for Windows: uninstaller. Removes the profile block(s) and the cmd AutoRun entry.
#   powershell -NoProfile -ExecutionPolicy Bypass -File uninstall.ps1
# The folder itself is left alone; delete it yourself if you want it gone.
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$enc = New-Object Text.UTF8Encoding $true
$docs = [Environment]::GetFolderPath('MyDocuments')
$begin = '# >>> linux-compat >>>'; $end = '# <<< linux-compat <<<'
foreach ($p in (Join-Path $docs 'WindowsPowerShell\profile.ps1'), (Join-Path $docs 'PowerShell\profile.ps1')) {
    if (-not (Test-Path $p)) { continue }
    $old = [IO.File]::ReadAllText($p)
    if (-not $old.Contains($begin)) { continue }
    $new = [regex]::Replace($old, "(?s)\r?\n?$([regex]::Escape($begin)).*?$([regex]::Escape($end))\r?\n?", "`r`n").Trim()
    if ($new) { [IO.File]::WriteAllText($p, "$new`r`n", $enc) } else { Remove-Item -LiteralPath $p }
    "removed linux-compat from $p"
}
$key = 'HKCU:\Software\Microsoft\Command Processor'
$cur = (Get-ItemProperty $key -Name AutoRun -ErrorAction SilentlyContinue).AutoRun
$init = Join-Path $root 'cmd\init.cmd'
if ("$cur" -like "*$init*") {
    $rest = ("$cur" -replace [regex]::Escape("`"$init`""), '').Trim().TrimStart('&').Trim()
    if ($rest) { Set-ItemProperty $key -Name AutoRun -Value $rest } else { Remove-ItemProperty $key -Name AutoRun }
    'removed linux-compat from cmd AutoRun'
}
'Done. Open a new window.'
