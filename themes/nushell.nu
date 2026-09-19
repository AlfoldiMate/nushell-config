# nushell.nu — THE Nushell theme. There is one, and it is written in roles.
#
# `$c` is defined by whoever sources this file: conf/theme.nu at startup and
# `theme use` in a running session. It is the resolved role record — `$c.accent`,
# `$c.border`, `$c.orange` — and each value is a Nushell colour, either an ANSI
# name (`blue`, `dark_gray`) or a hex. Which it is depends on the tier the
# palette resolved at (docs/concepts/theming.md): with only the terminal's sixteen the
# shaded roles are ANSI names and this file looks like the old terminal.nu;
# with the theme's hexes known they are blended shades; with a palette file
# they are exact. This file does not know or care which — that is the point.
#
# The sixteen (`$c.red`, `$c.cyan`, …) are ANSI names in every tier, so the
# terminal's own red is red here whatever theme it paints. Plain data —
# strings, ints, records, lists — is left unpainted (`default`) on purpose:
# it is what keeps one theme readable on a light background and a dark one,
# and keeps colour for the things that carry meaning.
#
# A hue used as text is its `text_` form (`$c.text_cyan`, `$c.text_bright_yellow`):
# the hue itself where it reads on the background, which on a dark theme is
# nearly always, and pulled towards fg where it does not — a light theme's
# bright yellow is 1.5–2:1 against its background, and it is what every
# external command you type is painted in. `$c.cyan` stays for a surface, or
# for a place where the terminal's exact colour is the point.
#
# A copy in <your dir>/themes/nushell.nu wins over this one (NU_LIB_DIRS lists
# yours first). The key list is `std/config dark-theme` plus Nushell's own
# defaults for the keys it does not set; after a Nushell upgrade re-diff it:
#
#   nu -n -c 'use std/config *; let c = (open themes/palettes/ansi.nuon).roles
#     source themes/nushell.nu; let ours = $env.config.color_config
#     dark-theme | transpose key std | insert ours {|r| $ours | get -o $r.key }
#       | where std != $it.ours'

$env.config.color_config = {
  # ── Table chrome ────────────────────────────────────────────────────────────
  header: { fg: $c.text_accent attr: b }
  row_index: $c.fg_muted
  separator: $c.border
  empty: $c.info                       # the `empty list` / `empty record` note
  hints: $c.hint                       # the history hint ahead of the cursor
  search_result: { bg: $c.warn fg: $c.on_accent }
  selection: { attr: r }               # reverse video: the terminal's own inverse
  selection_cursor: { attr: n }
  leading_trailing_space_bg: { attr: n }   # attr: n = do not mark it at all

  # ── Values, by type ─────────────────────────────────────────────────────────
  # `default` here is deliberate, see the note at the top.
  bool: $c.text_bright_cyan
  int: default
  float: default
  string: default
  range: default
  nothing: default
  binary: default
  record: default
  list: default
  block: default
  closure: { fg: $c.text_green attr: b }
  cell-path: default
  glob: { fg: $c.text_cyan attr: b }
  semver: { fg: $c.text_cyan attr: b }
  semver-range: { fg: $c.text_cyan attr: b }

  # Sizes and ages are graded: small and recent in the cool hues, large and old
  # in the warm ones. The hues past the sixteen (teal, orange, purple) are what
  # tier two and three add; in tier one they fall back to cyan, yellow, purple.
  # (`else` at the start of a line is a new command to the parser, hence the
  # line breaks after the braces.)
  filesize: {||
    if $in < 1kb { $c.text_teal } else if $in < 100kb { $c.text_green } else if $in < 10mb { $c.text_yellow } else if (
      $in < 100mb) { $c.text_orange } else if $in < 1gb { $c.text_red } else { $c.text_purple }
  }
  duration: {||
    if $in < 1sec { $c.text_teal } else if $in < 1min { $c.text_green } else if $in < 1hr { $c.text_yellow } else if (
      $in < 1day) { $c.text_orange } else if $in < 1wk { $c.text_red } else { $c.text_purple }
  }
  datetime: {|| (date now) - $in |
    if $in < 1hr { $c.text_teal } else if $in < 1day { $c.text_green } else if $in < 1wk { $c.text_yellow } else if (
      $in < 4wk) { $c.text_orange } else if $in < 52wk { $c.text_red } else { $c.text_purple }
  }

  # ── The `into binary` viewer ────────────────────────────────────────────────
  binary_null_char: $c.fg_muted
  binary_printable: { fg: $c.text_cyan attr: b }
  binary_whitespace: { fg: $c.text_green attr: b }
  binary_ascii_other: { fg: $c.text_purple attr: b }
  binary_non_ascii: { fg: $c.text_yellow attr: b }

  # ── Syntax highlighting, as you type ────────────────────────────────────────
  shape_garbage: { fg: $c.bright_white bg: $c.err attr: b }
  shape_matching_brackets: { attr: u }

  shape_internalcall: { fg: $c.text_cyan attr: b }          # a Nushell command
  shape_external: $c.text_cyan                              # an external command
  shape_external_resolved: { fg: $c.text_bright_yellow attr: b }   # ...that was found on PATH
  shape_externalarg: { fg: $c.text_green attr: b }
  shape_keyword: { fg: $c.text_purple attr: b }
  shape_operator: $c.text_yellow
  shape_pipe: { fg: $c.text_purple attr: b }
  shape_redirection: { fg: $c.text_purple attr: b }
  shape_flag: { fg: $c.text_blue attr: b }
  shape_signature: { fg: $c.text_green attr: b }
  shape_variable: $c.text_pink
  shape_vardecl: $c.text_pink
  shape_block: { fg: $c.text_blue attr: b }
  shape_closure: { fg: $c.text_green attr: b }
  shape_match_pattern: $c.text_green
  shape_custom: $c.text_green

  shape_bool: $c.text_bright_cyan
  shape_int: { fg: $c.text_orange attr: b }
  shape_float: { fg: $c.text_orange attr: b }
  shape_binary: { fg: $c.text_orange attr: b }
  shape_datetime: { fg: $c.text_cyan attr: b }
  shape_range: { fg: $c.text_yellow attr: b }
  shape_nothing: $c.text_bright_cyan
  shape_literal: $c.text_blue
  shape_string: $c.text_green
  shape_raw_string: $c.text_bright_magenta
  shape_string_interpolation: { fg: $c.text_cyan attr: b }
  shape_directory: $c.text_cyan
  shape_filepath: $c.text_cyan
  shape_globpattern: { fg: $c.text_cyan attr: b }
  shape_glob_interpolation: { fg: $c.text_cyan attr: b }
  shape_list: { fg: $c.text_cyan attr: b }
  shape_record: { fg: $c.text_cyan attr: b }
  shape_table: { fg: $c.text_blue attr: b }
}

# `explore`, the same way. Leaf keys, so a user's autoload can still change one.
$env.config.explore.status_bar_background = { fg: $c.fg bg: $c.bg_alt }
$env.config.explore.command_bar_text = { fg: $c.fg }
$env.config.explore.highlight = { fg: $c.on_accent bg: $c.warn }
$env.config.explore.status.error = $c.err
$env.config.explore.status.warn = $c.warn
$env.config.explore.status.info = $c.info
$env.config.explore.selected_cell = { fg: $c.on_accent bg: $c.accent }
