# config.nu — entrypoint
#
# Nushell loads this after env.nu and before the autoload directories. This
# file only wires things together; every setting lives in conf/. The order of
# the `source` lines below is the load order.
#
# Every $env.config key, documented:  config nu --doc | nu-highlight | less -R

# Where this repo lives. `path self` is resolved at parse time, so the repo can
# be cloned anywhere and every path below follows it.
const ROOT = path self | path dirname

# Search path for `use` and `source`: a bare filename resolves against these.
const NU_LIB_DIRS = [
  ($ROOT | path join modules)      # your modules            → use nu-config
  ($ROOT | path join completions)  # completion modules      → use git-completions.nu *
  ($ROOT | path join themes)       # colour themes           → source catppuccin-mocha.nu
]

# Search path for `plugin add <name>`.
const NU_PLUGIN_DIRS = [
  ($ROOT | path join plugins)          # plugins you build or download
  ($nu.current-exe | path dirname)     # plugins shipped next to `nu` (Homebrew, release tarballs)
]

# ── Load order ────────────────────────────────────────────────────────────────
source ($ROOT | path join conf settings.nu)     # the knobs — start here
source ($ROOT | path join conf env.nu)          # PATH, editor, environment variables
source ($ROOT | path join conf shell.nu)        # tables, errors, history, terminal integration
source ($ROOT | path join conf theme.nu)        # colours
source ($ROOT | path join conf prompt.nu)       # prompt (starship when installed)
source ($ROOT | path join conf keybindings.nu)  # keybindings, menus, abbreviations (defaults; add yours here)
source ($ROOT | path join conf completions.nu)  # completion behaviour + completion modules
source ($ROOT | path join conf aliases.nu)      # aliases and small commands
source ($ROOT | path join conf tools.nu)        # hooks and bindings for tools without an init file
source ($ROOT | path join conf agent.nu)        # Claude Code in the shell: agent ask | exec | skill | command
source ($ROOT | path join conf odata.nu)        # OData V2/V4 services as tables: odata <entity> | where ...

# Maintenance commands: nu-config doctor | tools setup | plugins add | fetch completion | ...
use nu-config

# After this file Nushell loads, in order:
#   1. *.nu in $nu.vendor-autoload-dirs — generated tool init files (nu-config tools setup)
#   2. *.nu in autoload/                — your machine-local drop-ins (gitignored)
