# settings.nu — yours. Override anything the distro ships.
#
# Sourced straight after the distro's defaults.nu, so a `const` here shadows
# the one there and an `$env.` assignment here replaces it. Mention only what
# you want to change; everything else keeps its shipped value, including knobs
# added by a later `git pull`.
#
#   nu-config knobs              every knob, and whether you have overridden it
#   nu-config knobs --overridden just yours
#   nu-config edit               open the distro and read defaults.nu
#
# For anything that is not a knob — a hook, a keybinding, a machine-local
# secret — drop a .nu file in autoload/ instead. Those load last and win.

# ── Colours ───────────────────────────────────────────────────────────────────
# Not a knob: `theme use <name>` picks one of Ghostty's themes and renders it
# for tables, ls, bat and the prompt at once (themes/README.md).

# ── Editing ───────────────────────────────────────────────────────────────────
# $env.config.edit_mode = "vi"              # emacs | vi | helix
# const EDITORS = [["nvim"] ["vim"] ["vi"]] # first one found becomes $EDITOR

# ── Display ───────────────────────────────────────────────────────────────────
# $env.config.show_banner = false
# $env.config.table.mode = "markdown"       # `table --list` shows every option
# $env.config.table.index_mode = "always"

# ── Completion ────────────────────────────────────────────────────────────────
# const SMART_TAB = true                    # false: Nushell's stock Tab menu
# $env.NU_COMPLETE_EVAL = "safe"            # safe | all | off

# ── Your own completion modules ───────────────────────────────────────────────
# Anything in your completions/ resolves before the shipped one of the same name.
# use docker-completions.nu *
