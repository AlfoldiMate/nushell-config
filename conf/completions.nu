# completions.nu — completion behaviour, the engine behind Tab, tool specs

# ── Behaviour ─────────────────────────────────────────────────────────────────
# Nushell's defaults are in effect (prefix matching, case-insensitive, quick
# and partial completion, external commands from PATH). To change one, set a
# leaf key here, e.g.:
#   $env.config.completions.algorithm = "fuzzy"   # `gsw` finds `git switch`
# `config nu --doc` documents every completions.* key. The engine below
# honours algorithm and case_sensitive in its own filtering.

# ── The engine ────────────────────────────────────────────────────────────────
# modules/nu-complete: docs/completion.md explains it. In short, three layers:
#   1. Nushell's own completer (built-ins, flags, cell paths, files).
#   2. `@complete` externs with a spec per tool (completions/brew.nu, git.nu):
#      positional completion from the tool's own data, carapace as fallback.
#   3. The Tab menu source `nu-complete smart`, the only place that sees the
#      whole line: columns/operators/values for `ls | where ⌶`, no files after
#      commands that take no argument, no duplicate entries.
# nu-complete itself is loaded by conf/modules.nu, which runs first.
# Published for tooling; the const itself is parse-time and invisible to it.
$env.NU_SMART_TAB = $SMART_TAB

# ── Tool specs ────────────────────────────────────────────────────────────────
# One module per tool in completions/ (on NU_LIB_DIRS). `use` is parse-time,
# so these cannot sit inside `if (which brew ...)`; an extern for a tool that
# is not installed only ever affects completion, never execution.
use brew.nu *     # subcommands, flags, packages with descriptions, installed, taps
use git.nu *      # subcommands, branches by recency, remotes, changed files, stashes
use cargo.nu *    # subcommands, flags from --help, packages/targets/features of the workspace, crate names
# A completion you fetch is YOURS: `nu-config fetch completion docker` saves it
# in your completions/, which comes first on NU_LIB_DIRS, and you wire it in
# from your own settings.nu with `use docker-completions.nu *`.

# ── External argument completer ───────────────────────────────────────────────
# When carapace is installed, its generated init file (nu-config tools setup)
# sets $env.config.completions.external.completer. The specs above hand it
# whatever they have no opinion on; without carapace those slots fall back to
# Nushell's own knowledge of a command and then to file paths.
#   brew install carapace  →  nu-config tools setup

# ── Tab: the smart menu ───────────────────────────────────────────────────────
# A custom menu is the only kind whose `source` closure gets the whole buffer
# (a `source` on the stock completion_menu is ignored by Nushell 0.115), so
# Tab is rebound to this one. Same look as completion_menu in keybindings.nu.
# SMART_TAB is a knob in defaults.nu.
if $SMART_TAB {
  $env.config.menus ++= [{
    name: smart_menu
    input_mode: cursor_prefix          # $buffer is the line up to the cursor
    marker: "| "
    type: {
      layout: columnar
      columns: 1
      col_width: 80
      col_padding: 2
    }
    style: {
      text: green
      selected_text: green_reverse
      description_text: yellow
      match_text: green
      selected_match_text: green_reverse
    }
    # `place` is a name the unified completer inputs bind (#18791): on 0.115.2
    # it arrives as a record, on 0.115.1 as the old position int. Naming it
    # `position` still works there and warns here. `nu-complete smart` takes
    # both. Its `buffer` differs too — see the note on that command.
    source: {|buffer, place| nu-complete smart $buffer $place }
  }]
  # The stock Tab chain, pointed at the smart menu.
  $env.config.keybindings ++= [{
    name: smart_tab
    modifier: none
    keycode: tab
    mode: [emacs vi_normal vi_insert]
    event: {
      until: [
        { send: menu, name: smart_menu }
        { send: menunext }
        { edit: complete }
      ]
    }
  }]
}
