# theme.nu — colours. Pick the theme in settings.nu (THEME).
#
# Files in themes/ are "source style": each assigns $env.config.color_config
# (Catppuccin also sets the `explore` colours). "dark" and "light" use the
# neutral themes from the standard library instead of a file.

const THEME_FILE = if $THEME in ["dark" "light"] { null } else { $"($THEME).nu" }
source $THEME_FILE     # `source null` is a no-op; a bare name resolves through NU_LIB_DIRS

if $THEME == "dark" {
  use std/config dark-theme
  $env.config.color_config = (dark-theme)
} else if $THEME == "light" {
  use std/config light-theme
  $env.config.color_config = (light-theme)
}

# bat follows the Catppuccin flavour.
if ($THEME | str starts-with "catppuccin-") {
  $env.BAT_THEME = $"Catppuccin ($THEME | str replace 'catppuccin-' '' | str capitalize)"
}

# `ls` file colours (LS_COLORS) come from vivid, baked into a generated file by
# `nu-config tools setup`; without vivid Nushell's built-in default applies.

# Try another theme in the running session without editing anything:
#   source catppuccin-latte.nu
#   use std/config light-theme; $env.config.color_config = (light-theme)
# More: https://github.com/nushell/nu_scripts/tree/main/themes  →  nu-config fetch theme <name>
