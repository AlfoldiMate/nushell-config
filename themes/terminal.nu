# terminal.nu — the default theme: sixteen colours, all of them the terminal's.
#
# Every value below is an ANSI colour NAME or `default`, never a hex code, so
# the terminal decides what each one looks like. Pick a theme in Ghostty and
# Nushell follows it — no generated file, nothing to keep in sync, and it works
# for all 463 themes Ghostty ships as well as any you add later. `VIVID_THEME`
# and `BAT_THEME` are both "ansi" by default so `ls` and `bat` follow too.
#
# `default` means "whatever the terminal's foreground is". Plain data — strings,
# ints, records, lists — is left unpainted on purpose: that is what makes one
# theme readable on a light background and a dark one, and it keeps colour for
# the things that carry meaning.
#
# Derived from `std/config dark-theme`, plus Nushell's own defaults for the six
# keys it does not set (closure, glob, semver, semver-range, selection,
# selection_cursor). After a Nushell upgrade, re-diff it against upstream:
#
#   nu -n -c 'use std/config *
#     source themes/terminal.nu
#     let ours = $env.config.color_config
#     dark-theme | transpose key std
#       | insert ours {|r| $ours | get -o $r.key }
#       | where std != $it.ours'
#
# For more than 16 colours there are the Catppuccin themes: they carry a full
# 26-colour palette in hex and ignore the terminal. THEME = "catppuccin-mocha".

$env.config.color_config = {
  # ── Table chrome ────────────────────────────────────────────────────────────
  header: green_bold
  row_index: green_bold
  separator: default
  empty: blue                        # the `empty list` / `empty record` note
  hints: dark_gray                   # the history hint ahead of the cursor
  search_result: { bg: red fg: white }
  selection: { attr: r }             # reverse video: the terminal's own inverse
  selection_cursor: { attr: n }
  leading_trailing_space_bg: { attr: n }   # attr: n = do not mark it at all

  # ── Values, by type ─────────────────────────────────────────────────────────
  # `default` here is deliberate, see the note at the top.
  bool: light_cyan
  int: default
  float: default
  string: default
  filesize: cyan
  duration: default
  datetime: purple
  range: default
  nothing: default
  binary: default
  record: default
  list: default
  block: default
  closure: green_bold
  cell-path: default
  glob: cyan_bold
  semver: cyan_bold
  semver-range: cyan_bold

  # ── The `into binary` viewer ────────────────────────────────────────────────
  binary_null_char: grey42
  binary_printable: cyan_bold
  binary_whitespace: green_bold
  binary_ascii_other: purple_bold
  binary_non_ascii: yellow_bold

  # ── Syntax highlighting, as you type ────────────────────────────────────────
  shape_garbage: { fg: white bg: red attr: b }
  shape_matching_brackets: { attr: u }

  shape_internalcall: cyan_bold      # a Nushell command
  shape_external: cyan               # an external command
  shape_external_resolved: light_yellow_bold   # ...that was found on PATH
  shape_externalarg: green_bold
  shape_keyword: cyan_bold
  shape_operator: yellow
  shape_pipe: purple_bold
  shape_redirection: purple_bold
  shape_flag: blue_bold
  shape_signature: green_bold
  shape_variable: purple
  shape_vardecl: purple
  shape_block: blue_bold
  shape_closure: green_bold
  shape_match_pattern: green
  shape_custom: green

  shape_bool: light_cyan
  shape_int: purple_bold
  shape_float: purple_bold
  shape_binary: purple_bold
  shape_datetime: cyan_bold
  shape_range: yellow_bold
  shape_nothing: light_cyan
  shape_literal: blue
  shape_string: green
  shape_raw_string: light_purple
  shape_string_interpolation: cyan_bold
  shape_directory: cyan
  shape_filepath: cyan
  shape_globpattern: cyan_bold
  shape_glob_interpolation: cyan_bold
  shape_list: cyan_bold
  shape_record: cyan_bold
  shape_table: blue_bold
}
