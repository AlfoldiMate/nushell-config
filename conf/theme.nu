# theme.nu — colours. Pick the theme in settings.nu (THEME, BAT_THEME).
#
# A theme is a file in themes/ in "source style": it assigns
# $env.config.color_config, and nothing else — a theme must not set behaviour,
# because this file runs after your settings.nu and would overwrite you.
# The default, themes/terminal.nu, is all ANSI names, so the terminal's own
# palette is the theme. Catppuccin brings hex and also sets `explore`.
# "dark" and "light" are the standard library's themes, with no file.

const THEME_FILE = if $THEME in ["dark" "light"] { null } else { $"($THEME).nu" }
source $THEME_FILE     # `source null` is a no-op; a bare name resolves through NU_LIB_DIRS

if $THEME == "dark" {
  use std/config dark-theme
  $env.config.color_config = (dark-theme)
} else if $THEME == "light" {
  use std/config light-theme
  $env.config.color_config = (light-theme)
}

# bat: the BAT_THEME knob wins, otherwise follow THEME. bat ships an `ansi`
# theme that is terminal-relative exactly like themes/terminal.nu, and a
# Catppuccin flavour for each of ours.
$env.BAT_THEME = $BAT_THEME | default (
  if ($THEME | str starts-with "catppuccin-") {
    $"Catppuccin ($THEME | str replace 'catppuccin-' '' | str capitalize)"
  } else {
    "ansi"
  }
)

# `ls` file colours (LS_COLORS) come from vivid, baked into a generated file by
# `nu-config tools setup`; without vivid Nushell's built-in default applies.

# With THEME = "terminal" the theme to change is Ghostty's: `theme` (the
# `terminal` module) repaints this window as you pick, and keeps the one you say
# yes to.
#
# Try another Nushell theme in the running session without editing anything:
#   source terminal.nu
#   source catppuccin-latte.nu
#   use std/config light-theme; $env.config.color_config = (light-theme)
#
# To add a theme of your own, drop a file that assigns $env.config.color_config
# into <your dir>/themes/ and name it in THEME; themes/terminal.nu is the
# smallest example to copy. Nothing is fetched at runtime — the distro used to
# have `nu-config fetch theme`, and a theme downloaded onto a live machine is
# exactly the kind of state this layout keeps out of the config directory.
