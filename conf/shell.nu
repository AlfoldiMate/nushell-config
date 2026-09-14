# shell.nu — display, errors, filesystem and terminal behaviour
#
# Assign leaf keys ($env.config.table.index_mode = ...) rather than whole
# records ($env.config.table = {...}): a whole-record assignment silently
# resets every sibling key to its default.

# ── Tables ────────────────────────────────────────────────────────────────────
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

# ── Line editor ───────────────────────────────────────────────────────────────
$env.config.cursor_shape = {
  emacs: line
  vi_insert: line
  vi_normal: block
}
$env.config.history.ignore_space_prefixed = true      # " secret-cmd" stays out of history

# ── Terminal integration ──────────────────────────────────────────────────────
# OSC escape sequences; every modern terminal supports these.
$env.config.shell_integration.osc2 = true      # window / tab title
$env.config.shell_integration.osc7 = true      # report cwd, so new tabs inherit it
$env.config.shell_integration.osc8 = true      # clickable links in `ls`
$env.config.shell_integration.osc133 = true    # prompt marks: jump between prompts
$env.config.shell_integration.osc633 = true    # VS Code's extension of osc133
$env.config.use_ansi_coloring = "auto"
$env.config.bracketed_paste = true
$env.config.use_kitty_protocol = false         # true lets Tab and Ctrl+I be bound separately
