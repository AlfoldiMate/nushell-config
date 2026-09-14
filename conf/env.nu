# env.nu — PATH, editor, environment variables

use std/util "path add"

# ── PATH ──────────────────────────────────────────────────────────────────────
# `path add` prepends, so the last line ends up first. A record picks the entry
# for the running OS and is a no-op elsewhere.
path add { macos: "/opt/homebrew/sbin" }
path add { macos: "/opt/homebrew/bin", linux: "/home/linuxbrew/.linuxbrew/bin" }
path add ($nu.home-dir | path join ".cargo" "bin")
path add ($nu.home-dir | path join ".local" "bin")

# Drop duplicates only. Not filtering on `path exists`: some tools prepend a
# directory they create lazily, and filtering would strip it every startup.
if "PATH" in $env { $env.PATH = ($env.PATH | uniq) }

# ── Editor ────────────────────────────────────────────────────────────────────
# First candidate from settings.nu that exists on PATH.
let editor = ($EDITORS | where {|e| which $e.0 | is-not-empty } | get -o 0)
if $editor != null {
  $env.EDITOR = ($editor | str join " ")
  $env.VISUAL = $env.EDITOR
  $env.config.buffer_editor = $editor
}

# ── Pager ─────────────────────────────────────────────────────────────────────
# -R keeps colour, -F quits when it fits on one screen, -X leaves output visible.
$env.PAGER = "less"
$env.LESS = "-RFX"

# ── Converting environment variables ──────────────────────────────────────────
# PATH is already a list. To present another colon-separated variable as a
# list too, add it here:
#
# $env.ENV_CONVERSIONS = $env.ENV_CONVERSIONS | merge {
#   XDG_DATA_DIRS: {
#     from_string: {|s| $s | split row (char esep) | path expand --no-symlink }
#     to_string:   {|v| $v | path expand --no-symlink | str join (char esep) }
#   }
# }
