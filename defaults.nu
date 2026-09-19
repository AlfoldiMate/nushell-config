# defaults.nu — every knob this distribution ships, with its default value.
#
# READ THIS FILE, DO NOT EDIT IT. It belongs to the distro and `git pull` will
# overwrite it. To change any value below, copy the line into your own
# settings.nu (next to your config.nu) and change it there:
#
#   nu-config edit user            opens your settings.nu
#   nu-config knobs                every knob, its default, and your value
#
# Your settings.nu is sourced immediately after this file, so a `const` there
# shadows the one here and an `$env.` assignment there overwrites this one.
# Anything you do not mention keeps the value below, including knobs added by
# a later `git pull`.
#
# This file holds VALUES ONLY. Behaviour — hooks, menus, keybindings, the
# things that read these values — lives in conf/. Every $env.config key that
# exists:  config nu --doc | nu-highlight | less -R

# ── Colours ───────────────────────────────────────────────────────────────────
# Not a knob. The theme is chosen with `theme use <name>` — one of Ghostty's
# 463 — and rendered for everything at once: tables, `ls`, bat and the prompt
# follow it, in this window and every new one. Until then the shell uses the
# terminal's own sixteen colours by name. themes/README.md.

# ── Editor ────────────────────────────────────────────────────────────────────
# Candidates in order; the first one found on PATH becomes $env.EDITOR,
# $env.VISUAL and the Ctrl+O buffer editor. GUI editors need their blocking flag.
const EDITORS = [
  ["zed" "--wait"]
  ["nvim"]
  ["vim"]
  ["vi"]
]

# ── Line editing ──────────────────────────────────────────────────────────────
# emacs | vi | helix
$env.config.edit_mode = "vi"

# Paint an external command differently once it resolves on PATH, so a typo is
# visible before you press Enter (shape_external vs shape_external_resolved).
# Nushell ships this false: the highlighter looks the word up on PATH as you
# type. It used to be set by each of the four Catppuccin theme files, which is
# the wrong place — a theme runs after your settings.nu and would overwrite you.
$env.config.highlight_resolved_externals = true

# How the cursor looks per mode; it is how you see which vi mode you are in.
$env.config.cursor_shape.emacs = "line"
$env.config.cursor_shape.vi_insert = "line"
$env.config.cursor_shape.vi_normal = "block"

# Reedline abbreviations: `{ gs: "git status" }` expands in place as you type,
# so the full command is visible and editable before Enter — unlike an alias,
# which substitutes silently at parse time. None are shipped: an abbreviation
# is muscle memory and yours, not a distro's.
$env.config.abbreviations = {}

# ── Banner ────────────────────────────────────────────────────────────────────
# true | "short" | false
$env.config.show_banner = false

# ── History ───────────────────────────────────────────────────────────────────
# "sqlite" keeps timestamps, cwd and exit codes and is queryable with `history`;
# "plaintext" is one command per line. These are read once at startup.
$env.config.history.file_format = "sqlite"
$env.config.history.max_size = 1_000_000
$env.config.history.isolation = false            # true: ↑ shows only this session's history
$env.config.history.sync_on_enter = true
$env.config.history.ignore_space_prefixed = true # " secret-cmd" stays out of history

# ── Tables ────────────────────────────────────────────────────────────────────
# Border style; `table --list` shows every option.
$env.config.table.mode = "markdown"
$env.config.table.index_mode = "always"
$env.config.table.header_on_separator = false
$env.config.table.show_empty = true
$env.config.footer_mode = 25              # repeat the header at the bottom past this many rows

# ── Values ────────────────────────────────────────────────────────────────────
$env.config.filesize.unit = "metric"      # kB/MB/GB; "binary" for KiB/MiB/GiB
$env.config.filesize.precision = 1
$env.config.float_precision = 2
$env.config.datetime_format.table = null  # null = humanised ("2 hours ago"); or a strftime string
$env.config.datetime_format.normal = null

# ── Errors ────────────────────────────────────────────────────────────────────
$env.config.error_style = "fancy"                     # "plain" for screen readers
$env.config.display_errors.exit_code = false          # externals already print their own error
$env.config.display_errors.termination_signal = true

# ── Filesystem ────────────────────────────────────────────────────────────────
$env.config.rm.always_trash = false       # true: `rm` moves to the system trash by default
$env.config.auto_cd_implicit = false      # require ./ or an absolute path to auto-cd

# ── Terminal integration ──────────────────────────────────────────────────────
# OSC escape sequences; every modern terminal supports these.
$env.config.shell_integration.osc2 = true      # window / tab title
$env.config.shell_integration.osc7 = true      # report cwd, so new tabs inherit it
$env.config.shell_integration.osc8 = true      # clickable links in `ls`
$env.config.shell_integration.osc133 = true    # prompt marks: jump between prompts
$env.config.shell_integration.osc633 = true    # VS Code's extension of osc133
$env.config.use_ansi_coloring = "auto"
$env.config.bracketed_paste = true
# true lets Tab and Ctrl+I be bound separately, which needs a terminal that
# implements the Kitty keyboard protocol. Ghostty does; `terminal current` is
# how you tell what you are in. Left false because it is a behaviour change and
# a shell started somewhere else would lose the keys.
$env.config.use_kitty_protocol = false

# ── Pager ─────────────────────────────────────────────────────────────────────
# -R keeps colour, -F quits when it fits on one screen, -X leaves output visible.
$env.PAGER = "less"
$env.LESS = "-RFX"

# ── Completion ────────────────────────────────────────────────────────────────
# Tab runs the pipeline-aware engine in modules/nu-complete (columns, operators
# and values for `where`/`get`/`select`..., no file noise after `ps`, one entry
# per command). false: Nushell's stock completion menu.
const SMART_TAB = true

# To offer columns and values, the engine runs the pipeline typed so far in a
# subprocess. "safe": only when every command in it is a read-only built-in
# (ls, ps, open, where, ...; never an external, never rm/save/http).
# "all": your own commands too, with the config loaded (~80 ms instead of ~20).
# "off": never; Tab still filters and deduplicates.
$env.NU_COMPLETE_EVAL = "safe"

# Partial completion: Tab first inserts what every candidate shares (`bits r`
# → `bits ro`), and only then opens the menu. Off, because on Nushell main
# (0.115.2, reedline c9e7035 — the next release, and every build from source)
# a sourced menu is handed the pre-splice line after that insert, so the next
# Tab replaces the wrong span: `bits r` Tab Tab Enter lands as `bits ror o`,
# `theme use Cat` as `"Catppuccin tppuccin`. 0.115.1 is clean; set this true
# there if you miss it. Verified in a pty, 2026-09-19 (docs/completion.md).
$env.config.completions.partial = false

# ── Modules ───────────────────────────────────────────────────────────────────
# Which modules this shell has. Each is a directory under modules/ with a
# mod.nu, a load.nu, a meta.nuon and a README — docs/modules.md is the
# contract, `nu-config module list` shows what is on.
#
# A module carries its OWN defaults, so its knobs are not listed in this file;
# `nu-config knobs` reads them out of each module's meta.nuon. To add one of
# your own, drop it in <your>/modules/ and `use` it from your settings.nu.
const MODULES = [nu-config nu-complete terminal agent odata]

# Of those, the ones NOT parsed at startup. A lazy module is loaded by a
# pre_execution hook on the first line that mentions it — measured at 828 ns
# per Enter to check, against 18 ms (agent) and 97 ms (odata) to load.
#
# The catch, and it is inherent: pre_execution does not fire for `nu -c` or a
# script, so a lazy module is interactive-only and a script has to say
# `use odata *` itself. Move a name out of this list to have it always loaded.
const MODULES_LAZY = [terminal agent odata]

# Extra words that should also trigger a lazy module, beyond its own name.
# `odata`'s `expand` is a pipeline stage that does not repeat the module name;
# most of `terminal` is not called "terminal" — `terminal list` is, but the rest
# of its commands start with `theme`, `ghostty` or `font`, which is also why
# typing `ghostty +list-themes` loads it.
const MODULES_TRIGGERS = { odata: [expand], terminal: [theme ghostty font] }

# ── Updates ───────────────────────────────────────────────────────────────────
# How often an interactive shell checks whether the distro checkout is behind
# its remote. The check is a background `git fetch`, never on the startup
# path: a start reads the LAST result and prints one line when there is
# something to pull — `nu-config upgrade` pulls it. 0sec: never check.
const UPDATE_CHECK_EVERY = 1day
