#!/bin/sh
# install.sh — get Nushell, get this distro, hand over to install.nu
#
#   curl -fsSL https://raw.githubusercontent.com/AlfoldiMate/nushell-config/main/bootstrap/install.sh | sh
#   sh install.sh --yes                     take every default, ask nothing
#   sh install.sh --dir ~/src/nu-distro     clone somewhere else
#
# This script has exactly two jobs: make sure `nu` exists, and put the distro
# on disk. Everything after that is Nushell — `install.nu` is the installer,
# and it is written in the shell it installs.
#
# It asks before it installs anything, it never writes outside $HOME, and
# re-running it is a `git pull`. Read it first; anyone piping a URL into a
# shell should be able to, which is why it is this short.
#
# Overridable with environment variables as well as flags:
#   NUSHELL_DISTRO_REPO  NUSHELL_DISTRO_DIR  NUSHELL_DISTRO_REF  NUSHELL_VERSION

set -eu

REPO="${NUSHELL_DISTRO_REPO:-https://github.com/AlfoldiMate/nushell-config.git}"
DIR="${NUSHELL_DISTRO_DIR:-$HOME/.local/share/nushell-distro}"
REF="${NUSHELL_DISTRO_REF:-}"
# Only used for the release-tarball path; resolved from GitHub when empty.
NU_VERSION="${NUSHELL_VERSION:-}"
BIN_DIR="${NUSHELL_BIN_DIR:-$HOME/.local/bin}"
YES=0
RUN_INSTALLER=1

while [ $# -gt 0 ]; do
  case "$1" in
    -y|--yes)     YES=1 ;;
    --dir)        DIR="$2"; shift ;;
    --repo)       REPO="$2"; shift ;;
    --ref)        REF="$2"; shift ;;
    --no-install) RUN_INSTALLER=0 ;;
    -h|--help)    sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

# ── Talking to the user ───────────────────────────────────────────────────────
# Piped into `sh`, stdin is this script, so every prompt reads /dev/tty. When
# there is no terminal at all the script refuses to guess: --yes says so.

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  B=$(printf '\033[1m'); C=$(printf '\033[36;1m'); D=$(printf '\033[2m'); R=$(printf '\033[0m')
else
  B=''; C=''; D=''; R=''
fi

step() { printf '%s%s%s\n' "$C" "$1" "$R"; }
info() { printf '  %s\n' "$1"; }
note() { printf '  %s%s%s\n' "$D" "$1" "$R"; }
die()  { printf '%s\n' "error: $1" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# ask "question" "default(y|n)" -> 0 for yes
ask() {
  if [ "$YES" = 1 ]; then return 0; fi
  if [ ! -r /dev/tty ]; then
    die "no terminal to ask '$1' on — re-run with --yes to accept every default"
  fi
  hint='[Y/n]'; [ "$2" = n ] && hint='[y/N]'
  printf '  %s%s%s %s ' "$B" "$1" "$R" "$hint" > /dev/tty
  read -r reply < /dev/tty || reply=''
  case "${reply:-$2}" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

# ── Nushell ───────────────────────────────────────────────────────────────────

target() {
  os=$(uname -s); arch=$(uname -m)
  case "$arch" in arm64|aarch64) arch=aarch64 ;; x86_64|amd64) arch=x86_64 ;; esac
  case "$os" in
    Darwin) echo "${arch}-apple-darwin" ;;
    Linux)  echo "${arch}-unknown-linux-gnu" ;;
    *) die "unsupported platform '$os' — install Nushell yourself, then re-run" ;;
  esac
}

latest_nu() {
  [ -n "$NU_VERSION" ] && { echo "$NU_VERSION"; return; }
  # One unauthenticated API call. A rate-limited or offline machine falls back
  # to the version this distro is verified against rather than failing.
  v=$(curl -fsSL https://api.github.com/repos/nushell/nushell/releases/latest 2>/dev/null \
      | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)
  echo "${v:-0.115.1}"
}

install_nu_tarball() {
  have curl || die "curl is needed to download Nushell"
  have tar  || die "tar is needed to unpack Nushell"
  v=$(latest_nu); t=$(target)
  url="https://github.com/nushell/nushell/releases/download/${v}/nu-${v}-${t}.tar.gz"
  info "downloading $url"
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
  curl -fsSL "$url" -o "$tmp/nu.tar.gz" || die "could not download $url"
  tar xzf "$tmp/nu.tar.gz" -C "$tmp"
  mkdir -p "$BIN_DIR"
  # The tarball holds nu plus the plugins that ship with it, all in one
  # directory. They have to stay together: `nu-config plugins add` registers
  # whatever sits next to the nu binary.
  cp "$tmp"/nu-*/nu "$tmp"/nu-*/nu_plugin_* "$BIN_DIR/"
  info "installed nu $v into $BIN_DIR"
  case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) note "$BIN_DIR is not on your PATH — add it, or the shell you just installed is not on it either" ;;
  esac
  NU="$BIN_DIR/nu"
}

ensure_nu() {
  step "Nushell"
  if have nu; then
    NU=$(command -v nu)
    info "$("$NU" --version) at $NU"
    return
  fi
  info "not installed"
  # Offer the package manager the machine already has first: it is the one
  # that will also upgrade nu later. The tarball is the fallback that always
  # works, and it is what --yes takes.
  if have brew && ask "install it with Homebrew?" y; then
    brew install nushell
    NU=$(command -v nu) || die "brew finished but nu is not on PATH"
  elif ask "download the official release build into $BIN_DIR?" y; then
    install_nu_tarball
  else
    die "Nushell is required — https://www.nushell.sh/book/installation.html"
  fi
}

# ── The distro ────────────────────────────────────────────────────────────────

clone() {
  step "Distro"
  have git || die "git is needed to clone $REPO"
  if [ -d "$DIR/.git" ]; then
    info "already at $DIR — updating"
    git -C "$DIR" pull --ff-only || note "could not fast-forward; your checkout has local changes"
  elif [ -e "$DIR" ]; then
    die "$DIR exists and is not a git checkout — move it, or pass --dir"
  else
    info "cloning $REPO into $DIR"
    mkdir -p "$(dirname "$DIR")"
    git clone --quiet "$REPO" "$DIR"
  fi
  if [ -n "$REF" ]; then
    git -C "$DIR" checkout --quiet "$REF"
    info "checked out $REF"
  fi
  [ -f "$DIR/install.nu" ] || die "$DIR has no install.nu — is $REPO the right repository?"
}

# ── Hand over ─────────────────────────────────────────────────────────────────

main() {
  printf '%sNushell distro%s  %s\n\n' "$C" "$R" "$REPO"
  ensure_nu
  printf '\n'
  clone
  printf '\n'
  if [ "$RUN_INSTALLER" = 0 ]; then
    step "Next"
    info "$NU $DIR/install.nu"
    return
  fi
  # stdin is this script when we were piped into sh, and the installer is
  # interactive, so it is given the terminal instead. `exec` so that Nushell
  # owns the process from here: what you see next is the shell being installed.
  if [ ! -r /dev/tty ]; then
    exec "$NU" "$DIR/install.nu" --defaults
  elif [ "$YES" = 1 ]; then
    exec "$NU" "$DIR/install.nu" --defaults < /dev/tty
  else
    exec "$NU" "$DIR/install.nu" < /dev/tty
  fi
}

main
