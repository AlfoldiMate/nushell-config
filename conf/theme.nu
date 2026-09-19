# theme.nu — colours: the theme `theme use` rendered, or the ANSI tier.
#
# There is no THEME knob. A theme is chosen with `theme use <name>` (the
# terminal module), which paints the window, writes Ghostty's config, and
# renders the shell's own colours into <your dir>/.state/theme/ — the roles
# for themes/nushell.nu, a starship.toml, vivid's LS_COLORS. This file loads
# that. Rendered rather than resolved here because a resolve spawns Ghostty to
# find the theme file and a render runs vivid — 40 ms — while a start is one
# `open` of a 1 kB NUON, 0.36 ms (median of 21), plus 0.09 ms for LS_COLORS.
#
# Before the first `theme use` there is no state, and tier one applies:
# themes/palettes/ansi.nuon, every role an ANSI name, so the shell follows
# whatever sixteen colours the terminal paints. Which is also what a machine
# without Ghostty gets. modules/terminal/palette.nu explains the tiers.

const THEME_STATE = ($nu.data-dir | path join .state theme)
const THEME_FILE = ($THEME_STATE | path join theme.nuon)

let palette = (
  if ($THEME_FILE | path exists) { open $THEME_FILE } else {
    open ($DISTRO_ROOT | path join themes palettes ansi.nuon) | merge { ls_colors: false }
  }
)

# themes/nushell.nu reads `$c`. A bare name, so a copy in your themes/ wins.
let c = $palette.roles
source nushell.nu

# bat, and through it `help` and git diffs paged by delta: a theme bat ships,
# `ansi` unless the palette named one.
$env.BAT_THEME = $palette.bat

# `ls` file colours: vivid's output for the theme, baked at render time.
# Without vivid nothing was rendered and Nushell's built-in colours apply.
if $palette.ls_colors { $env.LS_COLORS = (open --raw ($THEME_STATE | path join ls_colors)) }

# The prompt's colours are the same roles: conf/prompt.nu points starship at
# the rendered starship.toml. Which themes there are, the roles, and writing a
# palette of your own: docs/concepts/theming.md.
