# install.ps1 — get Nushell, get this distro, hand over to install.nu
#
#   irm https://raw.githubusercontent.com/AlfoldiMate/nushell-config/main/bootstrap/install.ps1 | iex
#   .\install.ps1 -Yes                      take every default, ask nothing
#   .\install.ps1 -Dir C:\src\nu-distro     clone somewhere else
#
# The Windows half of bootstrap/install.sh, and it has the same two jobs: make
# sure `nu` exists, and put the distro on disk. Everything after that is
# Nushell — install.nu is the installer, written in the shell it installs.
#
# Piped into `iex` there are no parameters, so every one of them also reads an
# environment variable: NUSHELL_DISTRO_REPO, NUSHELL_DISTRO_DIR,
# NUSHELL_DISTRO_REF, NUSHELL_VERSION, NUSHELL_BIN_DIR.

[CmdletBinding()]
param(
  [string] $Repo    = $env:NUSHELL_DISTRO_REPO,
  [string] $Dir     = $env:NUSHELL_DISTRO_DIR,
  [string] $Ref     = $env:NUSHELL_DISTRO_REF,
  [string] $Version = $env:NUSHELL_VERSION,
  [string] $BinDir  = $env:NUSHELL_BIN_DIR,
  [switch] $Yes,
  [switch] $NoInstall
)

$ErrorActionPreference = 'Stop'

if (-not $Repo)   { $Repo   = 'https://github.com/AlfoldiMate/nushell-config.git' }
if (-not $Dir)    { $Dir    = Join-Path $env:LOCALAPPDATA 'nushell-distro' }
if (-not $BinDir) { $BinDir = Join-Path $env:LOCALAPPDATA 'Programs\nu' }

function Step($m) { Write-Host $m -ForegroundColor Cyan }
function Info($m) { Write-Host "  $m" }
function Note($m) { Write-Host "  $m" -ForegroundColor DarkGray }
function Die($m)  { Write-Error $m; exit 1 }
function Have($c) { [bool](Get-Command $c -ErrorAction SilentlyContinue) }

function Ask($question, $defaultYes = $true) {
  if ($Yes) { return $true }
  $hint = if ($defaultYes) { '[Y/n]' } else { '[y/N]' }
  $reply = Read-Host "  $question $hint"
  if (-not $reply) { return $defaultYes }
  return $reply -match '^(y|yes)$'
}

# ── Nushell ───────────────────────────────────────────────────────────────────

function Latest-Nu {
  if ($Version) { return $Version }
  # A rate-limited or offline machine falls back to the version this distro
  # is verified against rather than failing.
  try {
    (Invoke-RestMethod 'https://api.github.com/repos/nushell/nushell/releases/latest').tag_name
  } catch { '0.115.1' }
}

function Install-NuZip {
  $v = Latest-Nu
  $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'aarch64' } else { 'x86_64' }
  $url = "https://github.com/nushell/nushell/releases/download/$v/nu-$v-$arch-pc-windows-msvc.zip"
  Info "downloading $url"
  $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid())
  New-Item -ItemType Directory -Path $tmp | Out-Null
  try {
    Invoke-WebRequest $url -OutFile "$tmp\nu.zip"
    Expand-Archive "$tmp\nu.zip" -DestinationPath $tmp -Force
    New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
    # nu and the plugins that ship with it have to land in ONE directory:
    # `nu-config plugins add` registers whatever sits next to the nu binary.
    Get-ChildItem $tmp -Recurse -Filter 'nu*.exe' | Copy-Item -Destination $BinDir -Force
    Info "installed nu $v into $BinDir"
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($userPath -notlike "*$BinDir*") {
      [Environment]::SetEnvironmentVariable('Path', "$userPath;$BinDir", 'User')
      Note "added $BinDir to your PATH — new terminals will see it"
    }
    $env:Path = "$env:Path;$BinDir"
  } finally { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
  return (Join-Path $BinDir 'nu.exe')
}

function Ensure-Nu {
  Step 'Nushell'
  if (Have 'nu') {
    $nu = (Get-Command nu).Source
    Info "$(& $nu --version) at $nu"
    return $nu
  }
  Info 'not installed'
  # winget first: it is what will also upgrade nu later. The release zip is
  # the fallback that always works, and it is what -Yes takes.
  if ((Have 'winget') -and (Ask 'install it with winget?')) {
    winget install --id Nushell.Nushell --source winget --accept-package-agreements --accept-source-agreements
    # winget puts it on the machine PATH, which this process does not have yet.
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
    if (Have 'nu') { return (Get-Command nu).Source }
    Note 'winget finished but nu is not on PATH yet — falling back to the release build'
  }
  if (Ask "download the official release build into $BinDir?") { return Install-NuZip }
  Die 'Nushell is required — https://www.nushell.sh/book/installation.html'
}

# ── The distro ────────────────────────────────────────────────────────────────

function Get-Distro {
  Step 'Distro'
  if (-not (Have 'git')) { Die "git is needed to clone $Repo" }
  if (Test-Path (Join-Path $Dir '.git')) {
    Info "already at $Dir — updating"
    git -C $Dir pull --ff-only
    if ($LASTEXITCODE -ne 0) { Note 'could not fast-forward; your checkout has local changes' }
  } elseif (Test-Path $Dir) {
    Die "$Dir exists and is not a git checkout — move it, or pass -Dir"
  } else {
    Info "cloning $Repo into $Dir"
    New-Item -ItemType Directory -Path (Split-Path $Dir -Parent) -Force | Out-Null
    git clone --quiet $Repo $Dir
    if ($LASTEXITCODE -ne 0) { Die "clone failed" }
  }
  if ($Ref) { git -C $Dir checkout --quiet $Ref; Info "checked out $Ref" }
  if (-not (Test-Path (Join-Path $Dir 'install.nu'))) {
    Die "$Dir has no install.nu — is $Repo the right repository?"
  }
}

# ── Hand over ─────────────────────────────────────────────────────────────────

Write-Host "Nushell distro  $Repo" -ForegroundColor Cyan
Write-Host ''
$nu = Ensure-Nu
Write-Host ''
Get-Distro
Write-Host ''

$installer = Join-Path $Dir 'install.nu'
if ($NoInstall) {
  Step 'Next'
  Info "$nu $installer"
} elseif ($Yes) {
  & $nu $installer --defaults
} else {
  & $nu $installer
}
