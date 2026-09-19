# theme.nu — colours. The THEME and BAT_THEME knobs pick them (defaults.nu,
# overridden in your settings.nu).
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

# Which themes there are, trying one in the running session, and writing one of
# your own: themes/README.md.
