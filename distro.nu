# distro.nu — the distribution entrypoint.
#
# Your own config.nu sources this file. Nothing here is meant to be edited:
# this is the distro, it is a git checkout, and `git pull` owns it.
#
#   defaults.nu          every knob, with the value this distro ships
#   <your>/settings.nu   your overrides — sourced right after, so it wins
#   conf/                behaviour: hooks, menus, keybindings, wiring
#   <your>/autoload/     your drop-ins — Nushell loads them last of all
#
# Layering works because a `const` in a later `source` shadows an earlier one
# and a later `$env.` assignment overwrites an earlier one. So you override by
# mentioning a knob, and a knob you never mention keeps its shipped value —
# including one added by a later `git pull`. docs/layout.md has the full story.

# Where the distro lives. `path self` resolves at parse time, so the checkout
# can sit anywhere and every path below follows it.
const DISTRO_ROOT = path self | path dirname

# Where your configuration lives: the directory holding the config.nu Nushell
# actually loaded. Nushell derives history, the plugin registry and the
# autoload dirs from this same directory, so all of your state is there too.
const USER_ROOT = $nu.config-path | path dirname

# Search path for `use` and `source`: a bare filename resolves against these,
# YOURS FIRST — so dropping a copy of a shipped completion or theme into your
# own directory and editing it is all it takes to override one.
const NU_LIB_DIRS = [
  ($USER_ROOT | path join modules)        # your modules
  ($USER_ROOT | path join completions)    # completions you fetched or wrote
  ($USER_ROOT | path join themes)         # your themes
  ($DISTRO_ROOT | path join modules)      # shipped modules       → use nu-config
  ($DISTRO_ROOT | path join completions)  # shipped completions   → use git.nu *
  ($DISTRO_ROOT | path join themes)       # shipped themes        → source catppuccin-mocha.nu
]

# Search path for `plugin add <name>`.
const NU_PLUGIN_DIRS = [
  ($USER_ROOT | path join plugins)        # plugins you build or download
  ($nu.current-exe | path dirname)        # plugins shipped next to `nu` (Homebrew, release tarballs)
]

# Nushell resolves `use`/`source` through the const above; publishing the same
# list as an environment variable lets tooling (`nu-config doctor`) read it too.
$env.NU_LIB_DIRS = $NU_LIB_DIRS

# ── Values: the distro's, then yours ──────────────────────────────────────────
source ($DISTRO_ROOT | path join defaults.nu)

# `path exists` and `if` are const-evaluable, and `source null` is a no-op, so
# this is an optional parse-time include. Without it a missing settings.nu
# would be a parse error, which means no shell at all.
const USER_SETTINGS_PATH = ($USER_ROOT | path join settings.nu)
const USER_SETTINGS = (if ($USER_SETTINGS_PATH | path exists) { $USER_SETTINGS_PATH } else { null })
source $USER_SETTINGS

# ── Behaviour: reads the values settled above ─────────────────────────────────
source ($DISTRO_ROOT | path join conf env.nu)          # PATH, editor, environment variables
source ($DISTRO_ROOT | path join conf theme.nu)        # applies THEME
source ($DISTRO_ROOT | path join conf prompt.nu)       # prompt (starship when installed)
source ($DISTRO_ROOT | path join conf keybindings.nu)  # keybindings, menus, abbreviations
source ($DISTRO_ROOT | path join conf modules.nu)      # the enabled modules, eagerly or on first mention
source ($DISTRO_ROOT | path join conf completions.nu)  # the Tab menu and the tool specs
source ($DISTRO_ROOT | path join conf aliases.nu)      # aliases and small commands
source ($DISTRO_ROOT | path join conf tools.nu)        # hooks for tools without an init file
source ($DISTRO_ROOT | path join conf update.nu)       # "the distro is behind its remote", once a day

# After this file Nushell loads, in order:
#   1. *.nu in $nu.vendor-autoload-dirs — generated tool init files (nu-config tools setup)
#   2. *.nu in <your>/autoload/         — your drop-ins, the last word
