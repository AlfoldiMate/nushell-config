# import.nu — NvChad's base46 themes as palette files, one .nuon each
#
#   nu themes/palettes/nvchad/import.nu            # fetch, convert, write next to this file
#   nu themes/palettes/nvchad/import.nu --from DIR # from a checkout of NvChad/base46
#
# Run by hand when base46 moves; nothing here runs at shell start or from
# `theme use`, which is why a network fetch is acceptable in this one script.
# The output is committed, so a user gets the palettes with the checkout.
#
# What is taken: `M.base_30`, NvChad's thirty UI colours, which already carry
# the roles this distro renders from (a background, three greys, a border, the
# hues, an orange and a teal) — the reason these themes are worth importing at
# all. `M.base_16` is not used: the sixteen a terminal needs are the base_30
# hues plus base_30's own greys, and base_16 in a third of the files is written
# in terms of base_30 anyway. Values may be written as `key = "#hex"` or as a
# `local name = "#hex"` referenced by name (slatewave); both are resolved.
#
# Naming: the palette's `name` is base46's own id (`onedark`, `tokyonight`,
# `gruvbox_light`) so anyone who knows NvChad knows the name; the file is its
# slug (`gruvbox-light.nuon`), which is how `theme use` finds a palette.
# `catppuccin-latte` collides with the hand-made palette one directory up,
# which extends Ghostty's own Catppuccin Latte with all 26 colours and is
# what `theme use catppuccin-latte` resolves to; the import here is skipped.

const HERE = (path self | path dirname)
const REPO = "NvChad/base46"
const BRANCH = "v3.0"   # base46's default branch, 2026-09-19

# base_30 → this distro's roles. The right-hand side is a base_30 key, with
# a fallback for the one file that lacks a key (catppuccin-latte has no
# vibrant_green).
const ROLES = {
  fg: white
  fg_dim: light_grey
  fg_muted: grey_fg
  bg: black
  bg_alt: statusline_bg
  bg_surface: one_bg2
  border: grey
  orange: orange
  purple: purple
  pink: pink
  teal: teal
  accent: blue
  accent_alt: dark_purple
  ok: green
  warn: yellow
  err: red
  info: cyan
  hint: grey_fg2
  on_accent: black
}

# base_30 → the sixteen Ghostty paints, plus the named colours. `black` is
# NvChad's editor background and `white` its text — in a light theme they are
# light and dark respectively, which is what base16 terminals do too.
const TERMINAL = {
  black: black
  red: red
  green: green
  yellow: yellow
  blue: blue
  magenta: purple
  cyan: cyan
  white: white
  bright_black: light_grey
  bright_red: baby_pink
  bright_green: vibrant_green
  bright_yellow: sun
  bright_blue: nord_blue
  bright_magenta: dark_purple
  bright_cyan: teal
  bright_white: white
  background: black
  foreground: white
  cursor: white
  selection_background: one_bg3
  selection_foreground: white
}

const FALLBACK = { vibrant_green: green, statusline_bg: darker_black, sun: yellow, nord_blue: blue, dark_purple: purple, baby_pink: pink, light_grey: grey_fg2 }

def main [--from: path] {
  let files = if $from != null {
    ls ($from | path join lua base46 themes) | get name
  } else {
    let branch = $BRANCH
    let names = (http get $"https://api.github.com/repos/($REPO)/contents/lua/base46/themes" | get name)
    print $"fetching ($names | length) themes from ($REPO)@($branch)"
    let dir = (mktemp -d)
    $names | par-each {|n| http get --raw $"https://raw.githubusercontent.com/($REPO)/($branch)/lua/base46/themes/($n)" | save -f ($dir | path join $n) }
    ls $dir | get name
  }

  let written = ($files | sort | each {|f| convert $f } | compact)
  print $"($written | length) palettes written to ($HERE)"
}

def convert [file: path]: nothing -> any {
  let id = ($file | path basename | str replace -r '\.lua$' '')
  let slug = ($id | str lowercase | str replace -ra '[^a-z0-9]+' '-' | str trim -c '-')
  if (($HERE | path dirname | path join $"($slug).nuon") | path exists) {
    print $"  skip ($id): a hand-made palette of that name exists one directory up"
    return null
  }
  let text = (open --raw $file)
  let locals = ($text | parse -r '(?m)^local (?<k>\w+)\s*=\s*"(?<v>#[0-9a-fA-F]{6})"' | reduce -f {} {|it, acc| $acc | upsert $it.k $it.v })
  let block = ($text | parse -r '(?s)M\.base_30 = \{(?<b>.*?)\n\}' | get -o 0.b)
  if $block == null { print $"  skip ($id): no base_30"; return null }
  let base30 = (
    $block
    | parse -r '(?m)^\s*(?<k>\w+)\s*=\s*(?<v>"#[0-9a-fA-F]{6}"|\w+)'
    | reduce -f {} {|it, acc|
        let v = if ($it.v | str starts-with '"') { $it.v | str trim -c '"' } else { $locals | get -o $it.v }
        if $v == null { $acc } else { $acc | upsert $it.k ($v | str lowercase) }
      }
  )
  let get = {|key| $base30 | get -o $key | default ($base30 | get -o ($FALLBACK | get -o $key | default "")) }
  let missing = ($TERMINAL | values | append ($ROLES | values) | uniq | where {|k| (do $get $k) == null })
  if ($missing | is-not-empty) { print $"  skip ($id): missing ($missing | str join ', ')"; return null }

  let dark = (($text | parse -r 'M\.type = "(?<t>\w+)"' | get -o 0.t | default "dark") == "dark")
  let terminal = ($TERMINAL | items {|k, v| { $k: (do $get $v) } } | reduce -f {} {|it, acc| $acc | merge $it })
  let roles = ($ROLES | items {|k, v| { $k: (if ($base30 | get -o $v) != null { $v } else { $FALLBACK | get $v }) } } | reduce -f {} {|it, acc| $acc | merge $it })

  let header = $"# ($slug).nuon — NvChad's `($id)` \(base46\), imported by import.nu. Do not edit:
# re-run the import instead. base_30 is `colours`; the roles name its keys.
"
  let body = ({
    name: $id
    source: $"https://github.com/($REPO)/blob/($BRANCH)/lua/base46/themes/($id).lua"
    dark: $dark
    terminal: $terminal
    colours: $base30
    roles: $roles
  } | to nuon --indent 2)
  ($header + $body + "\n") | save -f ($HERE | path join $"($slug).nuon")
  $id
}
