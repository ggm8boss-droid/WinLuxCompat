# linux-compat for Windows: apt / apt-get / apt-cache / dpkg / yum / dnf / pacman / zypper / apk / snap / brew -> winget.

# Linux package name -> winget id. Anything not listed is passed to winget as a search term.
$global:LC_PKGMAP = @{
    'git' = 'Git.Git'; 'nodejs' = 'OpenJS.NodeJS.LTS'; 'node' = 'OpenJS.NodeJS.LTS'; 'npm' = 'OpenJS.NodeJS.LTS'
    'python' = 'Python.Python.3.13'; 'python3' = 'Python.Python.3.13'; 'python3-pip' = 'Python.Python.3.13'; 'python-is-python3' = 'Python.Python.3.13'
    'vim' = 'vim.vim'; 'neovim' = 'Neovim.Neovim'; 'nvim' = 'Neovim.Neovim'; 'nano' = 'GNU.Nano'; 'emacs' = 'GNU.Emacs'
    'curl' = 'cURL.cURL'; 'wget' = 'JernejSimoncic.Wget'; '7zip' = '7zip.7zip'; 'p7zip' = '7zip.7zip'; 'p7zip-full' = '7zip.7zip'; 'zip' = '7zip.7zip'; 'unzip' = '7zip.7zip'
    'code' = 'Microsoft.VisualStudioCode'; 'vscode' = 'Microsoft.VisualStudioCode'; 'visual-studio-code' = 'Microsoft.VisualStudioCode'
    'firefox' = 'Mozilla.Firefox'; 'google-chrome' = 'Google.Chrome'; 'google-chrome-stable' = 'Google.Chrome'; 'chromium' = 'Hibbiki.Chromium'
    'docker' = 'Docker.DockerDesktop'; 'docker.io' = 'Docker.DockerDesktop'; 'docker-ce' = 'Docker.DockerDesktop'; 'docker-compose' = 'Docker.DockerDesktop'
    'golang' = 'GoLang.Go'; 'go' = 'GoLang.Go'; 'golang-go' = 'GoLang.Go'; 'rustup' = 'Rustlang.Rustup'; 'rust' = 'Rustlang.Rustup'; 'cargo' = 'Rustlang.Rustup'
    'jq' = 'jqlang.jq'; 'ripgrep' = 'BurntSushi.ripgrep.MSVC'; 'fd-find' = 'sharkdp.fd'; 'fd' = 'sharkdp.fd'; 'bat' = 'sharkdp.bat'; 'fzf' = 'junegunn.fzf'
    'gh' = 'GitHub.cli'; 'default-jdk' = 'Microsoft.OpenJDK.21'; 'openjdk-21-jdk' = 'Microsoft.OpenJDK.21'; 'openjdk-17-jdk' = 'Microsoft.OpenJDK.17'; 'java' = 'Microsoft.OpenJDK.21'
    'make' = 'ezwinports.make'; 'build-essential' = 'ezwinports.make'; 'cmake' = 'Kitware.CMake'; 'ninja-build' = 'Ninja-build.Ninja'; 'ninja' = 'Ninja-build.Ninja'
    'gcc' = 'BrechtSanders.WinLibs.POSIX.UCRT'; 'g++' = 'BrechtSanders.WinLibs.POSIX.UCRT'; 'clang' = 'LLVM.LLVM'; 'llvm' = 'LLVM.LLVM'
    'vlc' = 'VideoLAN.VLC'; 'ffmpeg' = 'Gyan.FFmpeg'; 'nmap' = 'Insecure.Nmap'; 'putty' = 'PuTTY.PuTTY'; 'wireshark' = 'WiresharkFoundation.Wireshark'
    'htop' = 'Microsoft.Sysinternals.ProcessExplorer'; 'powershell' = 'Microsoft.PowerShell'; 'pwsh' = 'Microsoft.PowerShell'
    'openssh-client' = 'Microsoft.OpenSSH.Beta'; 'openssl' = 'ShiningLight.OpenSSL.Light'; 'libssl-dev' = 'ShiningLight.OpenSSL.Light'
    'gimp' = 'GIMP.GIMP.3'; 'inkscape' = 'Inkscape.Inkscape'; 'obs-studio' = 'OBSProject.OBSStudio'; 'audacity' = 'Audacity.Audacity'
    'tmux' = 'Microsoft.WindowsTerminal'; 'sqlite3' = 'SQLite.SQLite'; 'sqlite' = 'SQLite.SQLite'; 'postgresql' = 'PostgreSQL.PostgreSQL.17'; 'mysql-server' = 'Oracle.MySQL'
    'redis' = 'Redis.Redis'; 'redis-server' = 'Redis.Redis'; 'nginx' = 'nginxinc.nginx'; 'php' = 'PHP.PHP.8.4'; 'ruby' = 'RubyInstallerTeam.Ruby.3.3'
    'kubectl' = 'Kubernetes.kubectl'; 'helm' = 'Helm.Helm'; 'terraform' = 'Hashicorp.Terraform'; 'awscli' = 'Amazon.AWSCLI'; 'azure-cli' = 'Microsoft.AzureCLI'
    'thunderbird' = 'Mozilla.Thunderbird'; 'libreoffice' = 'TheDocumentFoundation.LibreOffice'; 'keepassxc' = 'KeePassXCTeam.KeePassXC'; 'filezilla' = 'TimKosse.FileZilla.Client'
    'tree' = 'GnuWin32.Tree'; 'neofetch' = 'nepnep.neofetch-win'; 'fastfetch' = 'Fastfetch-cli.Fastfetch'
}
# Packages that have no meaning on Windows (headers, -dev libs, ...): skipped with a note.
$global:LC_PKGSKIP = '^(lib.*-dev|.*-dev|.*-devel|linux-headers.*|software-properties-common|apt-transport-https|ca-certificates|gnupg|lsb-release|net-tools|iproute2|procps|coreutils|sudo|man-db|bash-completion)$'

function global:_lc_winget([string[]]$wa) {
    $wg = (Get-Command winget.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
    if (-not $wg -and -not (_lc_dryrun)) { _lc_err 'winget' 'winget is not installed (get "App Installer" from the Microsoft Store)' 127; return }
    if (-not $wg) { $wg = 'winget.exe' }
    _lc_exec $wg $wa
}

# One normalized action: install | remove | update | upgrade | search | show | list | outdated | noop
function global:_lc_pkg([string]$action, [string[]]$pkgs, [bool]$yes, [string]$tool) {
    $agree = if ($yes) { @('--accept-package-agreements', '--accept-source-agreements', '--silent') } else { @() }
    $srcAgree = if ($yes) { @('--accept-source-agreements') } else { @() }
    switch ($action) {
        'install' {
            if (-not $pkgs.Count) { _lc_err $tool 'nothing to install'; return }
            foreach ($p in $pkgs) {
                $p = $p -replace '[:=].*$', ''   # pkg:amd64, pkg=1.2
                if ($p -match $global:LC_PKGSKIP) { "${tool}: skipping '$p' (not needed on Windows)"; continue }
                $id = $global:LC_PKGMAP[$p.ToLower()]
                if ($id) { _lc_winget (@('install', '--id', $id, '--exact') + $agree) } else { _lc_winget (@('install', $p) + $agree) }
            }
        }
        'remove' {
            foreach ($p in $pkgs) { $id = $global:LC_PKGMAP[$p.ToLower()]; if ($id) { _lc_winget (@('uninstall', '--id', $id, '--exact') + $srcAgree) } else { _lc_winget (@('uninstall', $p) + $srcAgree) } }
        }
        'update' { _lc_winget @('source', 'update') }
        'upgrade' {
            if ($pkgs.Count) { foreach ($p in $pkgs) { $id = $global:LC_PKGMAP[$p.ToLower()]; if ($id) { _lc_winget (@('upgrade', '--id', $id, '--exact') + $agree) } else { _lc_winget (@('upgrade', $p) + $agree) } } }
            else { _lc_winget (@('upgrade', '--all') + $agree) }
        }
        'outdated' { _lc_winget (@('upgrade') + $srcAgree) }
        'search' { _lc_winget (@('search', ($pkgs -join ' ')) + $srcAgree) }
        'show' { foreach ($p in $pkgs) { $id = $global:LC_PKGMAP[$p.ToLower()]; if ($id) { _lc_winget (@('show', '--id', $id, '--exact') + $srcAgree) } else { _lc_winget (@('show', $p) + $srcAgree) } } }
        'list' { if ($pkgs.Count) { _lc_winget (@('list', ($pkgs -join ' ')) + $srcAgree) } else { _lc_winget (@('list') + $srcAgree) } }
        'noop' { "${tool}: nothing to do on Windows (winget keeps no orphaned packages or cache)" }
        default { _lc_err $tool "unsupported operation '$action'" }
    }
}

function global:_lc_pkg_split($argv) {
    $a = @($argv | ForEach-Object { "$_" })
    $yes = [bool]($a | Where-Object { $_ -match '^(-y|--yes|--assume-yes|-q|-qq|--noconfirm|--non-interactive|--quiet)$' -or $_ -match '^-[a-z]*y[a-z]*$' })
    $words = @($a | Where-Object { $_ -notmatch '^-' })
    @{ yes = $yes; words = $words; flags = @($a | Where-Object { $_ -match '^-' }) }
}

function global:apt {
    $s = _lc_pkg_split $args; $w = $s.words
    if (-not $w.Count) { 'apt (linux-compat -> winget): install remove purge update upgrade full-upgrade search show list autoremove'; return }
    $verb = $w[0]; $p = @($w | Select-Object -Skip 1)
    $act = switch ($verb) {
        'install' { 'install' } 'reinstall' { 'install' } { $_ -in 'remove', 'purge', 'uninstall' } { 'remove' }
        'update' { 'update' } { $_ -in 'upgrade', 'full-upgrade', 'dist-upgrade' } { 'upgrade' }
        'search' { 'search' } { $_ -in 'show', 'info', 'policy' } { 'show' }
        'list' { if ($s.flags -contains '--upgradable') { 'outdated' } else { 'list' } }
        { $_ -in 'autoremove', 'autoclean', 'clean' } { 'noop' }
        default { $verb }
    }
    _lc_pkg $act $p $s.yes 'apt'
}
function global:apt-get { apt @args }
function global:apt-cache { $s = _lc_pkg_split $args; $w = $s.words; if ($w.Count -and $w[0] -in 'search', 'show', 'policy', 'madison') { _lc_pkg $(if ($w[0] -eq 'search') { 'search' } else { 'show' }) @($w | Select-Object -Skip 1) $false 'apt-cache' } else { _lc_err 'apt-cache' 'supported: search, show, policy' } }
function global:dpkg { $a = @($args | ForEach-Object { "$_" }); if ($a.Count -and $a[0] -in '-l', '--list', '-L') { _lc_pkg 'list' @($a | Select-Object -Skip 1) $false 'dpkg' } elseif ($a.Count -and $a[0] -in '-s', '--status') { _lc_pkg 'show' @($a | Select-Object -Skip 1) $false 'dpkg' } elseif ($a.Count -and $a[0] -in '-i', '--install') { foreach ($f in ($a | Select-Object -Skip 1)) { _lc_act "Start-Process '$f'" { Start-Process -FilePath (_lc_winpath $f) -Wait } } } else { _lc_err 'dpkg' 'supported: -l, -s, -i (runs a Windows installer)' } }

function global:_lc_yum([string]$tool, $argv) {
    $s = _lc_pkg_split $argv; $w = $s.words
    if (-not $w.Count) { _lc_err $tool 'usage: install remove update upgrade search info list check-update'; return }
    $p = @($w | Select-Object -Skip 1)
    $act = switch ($w[0]) {
        'install' { 'install' } 'reinstall' { 'install' } { $_ -in 'remove', 'erase', 'uninstall' } { 'remove' }
        { $_ -in 'update', 'upgrade', 'distro-sync' } { 'upgrade' } 'makecache' { 'update' } 'check-update' { 'outdated' }
        'search' { 'search' } 'info' { 'show' } 'list' { 'list' } { $_ -in 'autoremove', 'clean' } { 'noop' }
        default { $w[0] }
    }
    _lc_pkg $act $p $s.yes $tool
}
function global:yum { _lc_yum 'yum' $args }
function global:dnf { _lc_yum 'dnf' $args }
function global:zypper {
    $short = @{ in = 'install'; rm = 'remove'; up = 'upgrade'; dup = 'upgrade'; ref = 'makecache'; se = 'search'; if = 'info'; lu = 'check-update' }
    _lc_yum 'zypper' @($args | ForEach-Object { $x = "$_"; if ($short.ContainsKey($x)) { $short[$x] } else { $x } })
}
function global:apk { $s = _lc_pkg_split $args; $w = $s.words; if (-not $w.Count) { return }; $act = @{ add = 'install'; del = 'remove'; update = 'update'; upgrade = 'upgrade'; search = 'search'; info = 'show' }[$w[0]]; _lc_pkg $act @($w | Select-Object -Skip 1) $s.yes 'apk' }
function global:snap { $s = _lc_pkg_split $args; $w = $s.words; if (-not $w.Count) { return }; $act = @{ install = 'install'; remove = 'remove'; refresh = 'upgrade'; find = 'search'; info = 'show'; list = 'list' }[$w[0]]; _lc_pkg $act @($w | Select-Object -Skip 1) $s.yes 'snap' }
function global:flatpak { $s = _lc_pkg_split $args; $w = $s.words; if (-not $w.Count) { return }; $act = @{ install = 'install'; uninstall = 'remove'; update = 'upgrade'; search = 'search'; info = 'show'; list = 'list' }[$w[0]]; _lc_pkg $act @($w | Select-Object -Skip 2 | Where-Object { $_ -notmatch '^(flathub)$' }) $s.yes 'flatpak' }

function global:pacman {
    $a = @($args | ForEach-Object { "$_" })
    $op = ($a | Where-Object { $_ -match '^-[A-Za-z]+$' } | Select-Object -First 1); $p = @($a | Where-Object { $_ -notmatch '^-' })
    $yes = [bool]($a -contains '--noconfirm')
    $act = switch -CaseSensitive -Regex ($op) {
        '^-S[a-z]*u' { if ($p.Count) { 'install' } else { 'upgrade' }; break }
        '^-Sy+$' { if ($p.Count) { 'install' } else { 'update' }; break }
        '^-Ss' { 'search'; break } '^-Si' { 'show'; break } '^-Sc' { 'noop'; break } '^-S' { 'install'; break }
        '^-R' { 'remove'; break } '^-Qu' { 'outdated'; break } '^-Qi' { 'show'; break } '^-Q' { 'list'; break }
        default { '' }
    }
    if (-not $act) { _lc_err 'pacman' 'supported: -S -Syu -Sy -Ss -Si -R -Q -Qi -Qu'; return }
    _lc_pkg $act $p $yes 'pacman'
}

function global:brew {
    $s = _lc_pkg_split $args; $w = $s.words
    if (-not $w.Count) { 'brew (linux-compat -> winget): install uninstall upgrade update search info list outdated'; return }
    $act = switch ($w[0]) { 'install' { 'install' } 'reinstall' { 'install' } { $_ -in 'uninstall', 'remove', 'rm' } { 'remove' } 'update' { 'update' } 'upgrade' { 'upgrade' } 'search' { 'search' } { $_ -in 'info', 'home' } { 'show' } { $_ -in 'list', 'ls' } { 'list' } 'outdated' { 'outdated' } { $_ -in 'cleanup', 'autoremove', 'doctor' } { 'noop' } default { $w[0] } }
    _lc_pkg $act @($w | Select-Object -Skip 1) $s.yes 'brew'
}
