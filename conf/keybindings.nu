# keybindings.nu — Reedline menus, keybindings and abbreviations
#
# Nushell's defaults are in effect: the columnar completion menu on Tab,
# history menu on Ctrl+R (atuin takes that key over when installed), help
# menu on F1. Nothing is overridden here on purpose.
#
# Both lists merge into Nushell's defaults BY NAME: an entry with the same
# name as a default replaces it, anything else is added. To add or change a
# binding, append to the list — never assign the whole thing:
#   $env.config.keybindings ++= [{ name: ..., modifier: ..., keycode: ..., mode: [...], event: {...} }]
#   $env.config.menus ++= [{ name: ..., ... }]
# Remove a default binding by rebinding its key to `{ send: none }`.
#
# Discovery:
#   keybindings list          every modifier, keycode, event and edit
#   keybindings default       the defaults, as records you can copy
#   keybindings listen        press a key, see what Reedline calls it
#   $env.config.menus         the default menus, as records you can copy

# ── Menus ─────────────────────────────────────────────────────────────────────
# The default Tab menu is a 4-column grid, which is hard to scan for paths.
# Same name as the default → replaces it: one candidate per line, full width,
# so `ls <Tab>` and directory completions read as a list. With SMART_TAB
# (settings.nu) Tab opens smart_menu from conf/completions.nu instead, which
# copies this look; this one stays for `keybindings` that name it.
$env.config.menus ++= [{
  name: completion_menu
  only_buffer_difference: false
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
    # Reedline underlines the matched part of each candidate unless told
    # otherwise; same colour as the rest turns that off.
    match_text: green
    selected_match_text: green_reverse
  }
}]

# ── Abbreviations ─────────────────────────────────────────────────────────────
# Expand in place as you type, so the full command is visible and editable
# before Enter — unlike aliases, which substitute silently at parse time.
# $env.config.abbreviations = {
#   gs: "git status"
#   gd: "git diff"
# }
