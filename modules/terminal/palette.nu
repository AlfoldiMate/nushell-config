# palette — one palette, resolved in tiers, rendered for every tool
#
#   theme                  the picker: the shipped palettes (--ghostty: Ghostty's own 463)
#   theme list             the palettes, with swatches (--ghostty: Ghostty's list)
#   theme use <name>       terminal, icon, shell colours — now, and persistently
#   theme preview <name>   paint this session only
#   theme sync             re-resolve the current theme and re-render every file
#   theme roles [name]     the resolved roles, as a table, with where each came from
#   theme status           what is rendered, from which theme, at which tier
#   theme icon [--off]     the Ghostty app icon for the current theme, or none
#
# A theme is a palette RECORD, and every tool's colours are rendered from it.
# Nobody writes a Nushell theme, a starship palette, a vivid theme or an app
# icon per theme: themes/nushell.nu, starship.toml, vivid.yml and icon.svg are
# written against a small role vocabulary — fg_muted, border, accent, orange,
# … — and this file decides what each role IS for the theme in use. Three
# tiers, each only filling in what the one before could not say:
#
#   1  ansi     themes/palettes/ansi.nuon: every role an ANSI NAME. The sixteen
#               are the terminal's own, so `red` is whatever the terminal paints
#               red — and the sixteen stay names in every tier, which is what
#               keeps the shell right when the palette changes under it (SSH,
#               tmux, a hand-edited Ghostty config). What ANSI cannot say —
#               a muted grey, a border, an orange — is approximated.
#   2  derived  the sixteen, background and foreground as hex — from the
#               palette's own `terminal` block or from Ghostty's theme file —
#               so the shaded roles are BLENDED: fg_muted is fg pulled halfway
#               to bg, border is bg pushed a quarter of the way to fg, orange
#               is red mixed with yellow. Hex, but only for roles ANSI has no
#               word for. Every one of Ghostty's 463 gets this.
#   3  palette  a palette file names the shaded roles exactly — Catppuccin's
#               overlay1, NvChad's grey_fg and one_bg2 — and can name a bat and
#               a vivid theme that already match.
#
# Two kinds of palette file, told apart by their keys:
#
#   terminal:   the palette IS a terminal theme: its own sixteen, background,
#               foreground, cursor and selection. Ghostty is handed it as a
#               file (`theme = <absolute path>` is accepted) written under the
#               state dir. NvChad's 96 (themes/palettes/nvchad/) are these.
#   ghostty:    the palette EXTENDS a theme Ghostty ships: that file supplies
#               the sixteen. The four Catppuccins are these.
#
# `theme use` resolves and renders; the result is under <your dir>/.state/
# theme/, which conf/theme.nu and conf/prompt.nu read at startup. Rendered,
# not resolved at every start: theme.nuon is 1 kB and opens in 0.36 ms (median
# of 21), a resolve is 40 ms because `theme palette` spawns Ghostty to find a
# theme file, and a render on top runs vivid and rasterizes the icon:
#
#   theme.nuon        the roles, plus the theme name, tier and the bat theme
#   starship.toml     themes/starship.toml with [palettes.distro] filled in
#   ls_colors         vivid's output for the theme, a raw string
#   ghostty/<slug>    the Ghostty theme file, for a palette with a `terminal` block
#   icons/<slug>.png  the app icon (macOS)
#
# Nothing here reads state at parse time: the module is lazy and the paths
# are `$nu.data-dir`, which is the user's directory.

use ghostty.nu *
use theme.nu *

const DISTRO_ROOT = (path self | path dirname | path dirname | path dirname)
const SHIPPED_PALETTES = ($DISTRO_ROOT | path join themes palettes)

# The theme file this module applies to a running session. The user's copy
# wins, as it does at startup through NU_LIB_DIRS — decided at parse time
# because `source` needs a constant, so a copy dropped in after the module
# loaded is seen by the next shell, not this one.
const USER_THEME_FILE = ($nu.config-path | path dirname | path join themes nushell.nu)
const NUSHELL_THEME = (if ($USER_THEME_FILE | path exists) { $USER_THEME_FILE } else { $DISTRO_ROOT | path join themes nushell.nu })

# Roles that are blended in tier two. Everything else keeps its tier-one name:
# the sixteen by design, and the semantic roles because they point AT a hue
# (accent = blue) rather than being one.
#   mix a b t   →  a pulled t of the way towards b
const DERIVED = {
  fg_dim:     { mix: [fg bg 0.25] }
  fg_muted:   { mix: [fg bg 0.5] }
  hint:       { mix: [fg bg 0.5] }
  bg_alt:     { mix: [bg fg 0.04] }
  bg_surface: { mix: [bg fg 0.12] }
  border:     { mix: [bg fg 0.25] }
  orange:     { mix: [red yellow 0.5] }
  purple:     { mix: [blue magenta 0.5] }
  pink:       { mix: [magenta red 0.4] }
  teal:       { mix: [cyan green 0.4] }
  accent_alt: { mix: [blue magenta 0.5] }
  on_accent:  { mix: [bg fg 0.0] }
}

# Ghostty's palette index for each of the sixteen roles; what tier two blends
# from, and how a palette's `terminal` block becomes a Ghostty theme file.
const SIXTEEN = {
  black: 0, red: 1, green: 2, yellow: 3, blue: 4, magenta: 5, cyan: 6, white: 7
  bright_black: 8, bright_red: 9, bright_green: 10, bright_yellow: 11
  bright_blue: 12, bright_magenta: 13, bright_cyan: 14, bright_white: 15
}

# A palette's `terminal` keys → the named colours a Ghostty theme file has.
const NAMED = {
  background: background, foreground: foreground, cursor: cursor-color
  selection_background: selection-background, selection_foreground: selection-foreground
}

# The icon's six placeholders, and the role each one is. Where a role is an
# ANSI name rather than a hex (tiers one and two), the terminal's own hex for
# that colour is used instead.
const ICON_ROLES = { bg: bg, fg: fg, err: red, accent: blue, ok: green, warn: yellow }

# ── Where things live ─────────────────────────────────────────────────────────

export def "theme state-dir" []: nothing -> path {
  $nu.data-dir | path join .state theme
}

# "Catppuccin Macchiato" → catppuccin-macchiato: the file name a palette has.
export def "theme slug" [name: string]: nothing -> string {
  $name | str lowercase | str replace -ra '[^a-z0-9]+' '-' | str trim -c '-'
}

# Where palettes are looked for, first match wins: yours, the hand-made
# shipped ones, then the NvChad import.
def palette-dirs []: nothing -> list<path> {
  [
    ($nu.config-path | path dirname | path join themes palettes)
    $SHIPPED_PALETTES
    ($SHIPPED_PALETTES | path join nvchad)
  ]
}

# The palette file for a name, or null. The contract is that a file's stem is
# the slug of its `name`, so this is a path check, not a hundred `open`s.
def palette-file [name: string]: nothing -> any {
  let f = $"(theme slug $name).nuon"
  palette-dirs | each {|d| $d | path join $f } | where {|p| ($p | path exists) and ($f != "ansi.nuon") } | get -o 0
}

# A template: the user's copy in their themes/ when there is one, else the shipped one.
def template-for [file: string]: nothing -> path {
  let user = ($nu.config-path | path dirname | path join themes $file)
  if ($user | path exists) { $user } else { $DISTRO_ROOT | path join themes $file }
}

# ── Colour arithmetic ─────────────────────────────────────────────────────────

def hex-rgb [hex: string]: nothing -> list<int> {
  let n = ($"0x($hex | str substring 1..)" | into int)
  [($n // 65536) (($n // 256) mod 256) ($n mod 256)]
}

def rgb-hex [rgb: list<int>]: nothing -> string {
  "#" + ($rgb | each {|v| $v | format number | get lowerhex | str substring 2.. | fill -a r -c '0' -w 2 } | str join)
}

# `a` pulled `t` of the way to `b`, per channel in sRGB. Linear-light would be
# more correct and, for these small steps between a background and its
# foreground, indistinguishable.
def mix [a: string, b: string, t: float]: nothing -> string {
  rgb-hex (hex-rgb $a | zip (hex-rgb $b) | each {|p| (($p.0 * (1 - $t)) + ($p.1 * $t)) | math round | into int })
}

def is-hex [v: any]: nothing -> bool {
  ($v | describe) == "string" and ($v =~ '^#[0-9a-fA-F]{6}$')
}

# `items` gives a list of one-key records; this folds them into one record.
def as-record []: list<record> -> record {
  reduce -f {} {|it, acc| $acc | merge $it }
}

# ── The palettes ──────────────────────────────────────────────────────────────

# Every palette file there is: yours, the shipped ones, NvChad's. A hundred
# `open`s, 30 ms; only `theme list` and `theme names` pay it.
export def "theme palettes" []: nothing -> table<name: string, dark: bool, kind: string, ghostty: any, file: path> {
  palette-dirs
  | each {|d|
      let kind = (if $d == $SHIPPED_PALETTES { "shipped" } else if ($d | path basename) == "nvchad" { "nvchad" } else { "yours" })
      if not ($d | path exists) { return [] }
      ls $d | where name =~ '\.nuon$' and name !~ 'ansi\.nuon$' | each {|f|
        let p = (open $f.name)
        { name: ($p | get -o name | default ($f.name | path basename | str replace ".nuon" "")), dark: ($p | get -o dark | default true), kind: $kind, ghostty: ($p | get -o ghostty), file: $f.name }
      }
    }
  | flatten
  | uniq-by name
}

# What every `<name>` argument completes from: the palettes, then Ghostty's.
export def "theme names" []: nothing -> list<string> {
  (theme palettes | get name) ++ (try { ghostty names } catch { [] }) | uniq
}

# The themes to choose from: the palettes, or Ghostty's own with --ghostty.
export def "theme list" [
  --ghostty    # Ghostty's 463 instead of the palettes
  --swatches   # add the sixteen as a column
]: nothing -> table {
  if $ghostty { return (ghostty themes --swatches=$swatches) }
  let rows = (theme palettes | rename theme)
  if not $swatches { return $rows }
  # A palette with a `terminal` block carries its sixteen; one that extends a
  # Ghostty theme is read from Ghostty's file, found through one listing.
  let files = (try { ghostty themes } catch { [] })
  $rows | insert colours {|r|
    let p = (open $r.file)
    let hexes = if ($p | get -o terminal) != null {
      $SIXTEEN | items {|k, i| $p.terminal | get $k }
    } else {
      let f = ($files | where theme == ($p | get -o ghostty | default "") | get -o 0.path)
      if $f == null { [] } else { theme read $f $p.ghostty | get palette | transpose i hex | sort-by {|x| $x.i | into int } | get hex }
    }
    theme swatch $hexes
  }
}

# ── Resolving ─────────────────────────────────────────────────────────────────

# Tier one, as shipped: the file, not a copy of it, so there is one list of roles.
def ansi-palette []: nothing -> record {
  open ($SHIPPED_PALETTES | path join ansi.nuon)
}

# A palette's `terminal` block in the shape `theme palette` returns for a
# Ghostty file: `palette` 0-15 and `named`.
def terminal-record [name: string, t: record]: nothing -> record {
  {
    theme: $name
    palette: ($SIXTEEN | items {|k, i| { ($i | into string): ($t | get $k) } } | as-record)
    named: ($NAMED | items {|k, g| let v = ($t | get -o $k); if $v == null { {} } else { { $g: $v } } } | as-record)
  }
}

# The resolved theme for a name: the roles and everything the render needs.
# `null` is "no theme chosen", which is tier one and nothing else.
#
#   name      the theme's name
#   by        palette | ghostty — how the name was matched
#   tier      ansi | derived | palette
#   palette   the palette file used, or null
#   terminal  the sixteen and named colours as `theme palette` returns them, or null
#   ghostty   what Ghostty's `theme =` gets: a theme name, or "file" for a palette's own block
#   bat       a theme bat ships
#   vivid     a theme vivid ships, or null to render themes/vivid.yml
#   dark      whether the background is dark
#   roles     role → Nushell colour (an ANSI name or a hex)
#   source    role → which tier decided it, for `theme roles`
export def "theme resolve" [
  name?: string
  --ghostty   # the name is one of Ghostty's; a palette applies only if it says it extends that theme
]: nothing -> record {
  let base = (ansi-palette)
  mut roles = $base.roles
  mut source = ($roles | items {|k, v| { $k: "ansi" } } | as-record)
  mut r: record = { name: $name, by: "ghostty", tier: "ansi", palette: null, terminal: null, ghostty: $name, bat: $base.bat, vivid: null, dark: true }
  if $name == null { return ($r | merge { roles: $roles, source: $source }) }

  # Which palette, if any.
  let pf = (palette-file $name)
  let p = (if $pf == null { null } else { open $pf })
  let p = (if $ghostty and $p != null and ($p | get -o ghostty) != $name { null } else { $p })

  # The sixteen as hex: the palette's own, or Ghostty's file for the theme
  # the palette extends (or the name itself). Without Ghostty (a Linux box,
  # SSH) a Ghostty name resolves at tier one.
  let ghostty_name = (if $p != null { $p | get -o ghostty | default $name } else { $name })
  let term = (
    if $p != null and ($p | get -o terminal) != null { terminal-record $name $p.terminal }
    else { try { theme palette $ghostty_name } catch { null } }
  )
  if $p == null and $term == null {
    error make { msg: $"no theme called '($name)': not a palette \(`theme list`\) and not one of Ghostty's \(`theme list --ghostty`\)", label: { text: "unknown theme", span: (metadata $name).span } }
  }
  $r = ($r | merge {
    name: (if $p != null { $p | get -o name | default $name } else { $name })
    by: (if $p != null { "palette" } else { "ghostty" })
    terminal: $term
    ghostty: (if $p != null and ($p | get -o terminal) != null { "file" } else { $ghostty_name })
  })

  # Tier two: blend the shaded roles from the hexes.
  if $term != null and ($term.palette | columns | length) == 16 {
    let hexes = (term-hexes $term)
    for d in ($DERIVED | transpose role rule) {
      $roles = ($roles | upsert $d.role (mix ($hexes | get $d.rule.mix.0) ($hexes | get $d.rule.mix.1) $d.rule.mix.2))
      $source = ($source | upsert $d.role "derived")
    }
    $r.tier = "derived"
    $r.dark = (is-dark $hexes.bg)
  }

  # Tier three: the palette's roles. A role may name one of the palette's
  # colours or carry a colour of its own.
  if $p != null {
    let colours = ($p | get -o colours | default {})
    for role in ($p | get -o roles | default {} | transpose k v) {
      let v = ($colours | get -o $role.v | default $role.v)
      $roles = ($roles | upsert $role.k $v)
      $source = ($source | upsert $role.k "palette")
    }
    $r = ($r | merge {
      tier: "palette"
      palette: $pf
      bat: ($p | get -o bat | default $base.bat)
      vivid: ($p | get -o vivid)
      dark: ($p | get -o dark | default $r.dark)
    })
  }
  $r | merge { roles: $roles, source: $source }
}

# The sixteen, bg and fg as hex out of a `theme palette` record.
def term-hexes [term: record]: nothing -> record {
  $SIXTEEN | items {|role, i| { $role: ($term.palette | get ($i | into string)) } } | as-record
  | merge { bg: ($term.named | get -o background | default ($term.palette | get "0")) }
  | merge { fg: ($term.named | get -o foreground | default ($term.palette | get "7")) }
}

# Perceived luminance below the midpoint. Rec. 601 weights, good enough to
# tell a light background from a dark one.
def is-dark [hex: string]: nothing -> bool {
  let c = (hex-rgb $hex)
  (($c.0 * 299) + ($c.1 * 587) + ($c.2 * 114)) / 1000 < 128
}

# ── Rendering ─────────────────────────────────────────────────────────────────

# Nushell's colour names → starship's. `default` has no starship spelling and
# is dropped from the block; a template must not use fg or bg for that reason.
def to-starship [v: string]: nothing -> any {
  if (is-hex $v) { return $v }
  match $v {
    "default" => null
    "purple" => "purple"
    "dark_gray" => "bright-black"
    "light_gray" => "bright-white"
    "light_purple" => "bright-purple"
    _ if ($v | str starts-with "light_") => ($v | str replace "light_" "bright-")
    _ => $v
  }
}

# Nushell's colour names → vivid's `ansi:` spellings; hex loses its `#`.
def to-vivid [v: string]: nothing -> any {
  if (is-hex $v) { return ($v | str substring 1..) }
  match $v {
    "default" => null
    "purple" => "ansi:magenta"
    "light_purple" => "ansi:bright_magenta"
    "dark_gray" => "ansi:bright_black"
    "light_gray" => "ansi:bright_white"
    _ if ($v | str starts-with "light_") => ("ansi:bright_" + ($v | str replace "light_" ""))
    _ => $"ansi:($v)"
  }
}

# The [palettes.distro] block, as a record starship's TOML can hold.
export def "theme starship-palette" [roles: record]: nothing -> record {
  $roles | items {|k, v| let s = (to-starship $v); if $s == null { {} } else { { $k: $s } } } | as-record
}

# The template with the palette filled in. Through `from toml`/`to toml`
# rather than text: the block is replaced whole and the file stays valid
# whatever the template's author did with whitespace. Comments do not survive
# the round trip, which is fine for a rendered file — the template keeps them.
def render-starship [roles: record]: nothing -> string {
  let t = (open --raw (template-for starship.toml) | from toml)
  $t
  | upsert palette "distro"
  | upsert palettes { distro: (theme starship-palette $roles) }
  | to toml
}

# LS_COLORS: vivid's own theme when the palette names one, otherwise
# themes/vivid.yml with its `colors:` block rendered from the roles. Null
# without vivid, and Nushell's built-in colours apply.
def render-ls-colors [t: record]: nothing -> any {
  if (which vivid | is-empty) { return null }
  if $t.vivid != null { return (^vivid generate $t.vivid | str trim) }
  let colours = (
    $t.roles | items {|k, v| let c = (to-vivid $v); if $c == null { [] } else { [$"  ($k): ($c | to json)"] } } | flatten
  )
  let template = (open --raw (template-for vivid.yml))
  # The `colors:` block runs to the next key at column 0.
  let yml = ($template | str replace -r '(?ms)^colors:.*?\n(?=\S)' ("colors:\n" + ($colours | str join "\n") + "\n\n"))
  let f = (theme state-dir | path join vivid.yml)
  $yml | save -f $f
  ^vivid generate $f | str trim
}

# The app icon: themes/icon.svg with its six roles filled in, rasterized by
# macOS's own `qlmanage` (QuickLook renders SVG through WebKit — the one
# SVG rasterizer a stock Mac has; `sips` cannot read SVG). Ghostty takes the
# PNG as `macos-custom-icon`. The file is named by the theme, not `icon.png`,
# so the path in Ghostty's config changes with the theme and a reload sees a
# change. Null off macOS, without a terminal record, or when qlmanage fails.
def render-icon [t: record]: nothing -> any {
  if $nu.os-info.name != "macos" or $t.terminal == null or (which qlmanage | is-empty) { return null }
  let hexes = (term-hexes $t.terminal)
  let svg = (
    $ICON_ROLES | transpose ph role | reduce -f (open --raw (template-for icon.svg)) {|it, acc|
      let v = ($t.roles | get $it.ph)
      $acc | str replace -a $"{{($it.ph)}}" (if (is-hex $v) { $v } else { $hexes | get $it.role })
    }
  )
  let dir = (theme state-dir | path join icons)
  mkdir $dir
  let stem = (theme slug $t.name)
  let svg_file = ($dir | path join $"($stem).svg")
  $svg | save -f $svg_file
  # qlmanage names its output <input>.png in the directory given.
  let r = (^qlmanage -t -s 1024 -o $dir $svg_file | complete)
  let out = ($dir | path join $"($stem).svg.png")
  if $r.exit_code != 0 or not ($out | path exists) { return null }
  let png = ($dir | path join $"($stem).png")
  mv -f $out $png
  rm -f $svg_file
  $png
}

# Ghostty's `theme =` value for a resolved theme, writing the theme file when
# the palette carries its own sixteen.
def ghostty-theme-value [t: record]: nothing -> string {
  if $t.ghostty != "file" { return $t.ghostty }
  let dir = (theme state-dir | path join ghostty)
  mkdir $dir
  let f = ($dir | path join (theme slug $t.name))
  theme ghostty-file $t.terminal | save -f $f
  $f
}

# Resolve a theme and write every rendered file. The name defaults to the one
# rendered last time, so `theme sync` after a `git pull` picks up a changed
# template; `--none` renders the ANSI tier and forgets the name.
export def --env "theme sync" [
  name?: string
  --ghostty   # the name is one of Ghostty's (kept from the last `theme use` when omitted)
  --none      # no theme: tier one, and the state says so
  --quiet (-q)
]: nothing -> record {
  let cur = (theme current | default {})
  let name = if $none { null } else { $name | default ($cur | get -o name) }
  let by_ghostty = (if $name == null { false } else if $ghostty { true } else if ($cur | get -o name) == $name { ($cur | get -o by) == "ghostty" } else { false })
  let t = (theme resolve $name --ghostty=$by_ghostty)
  render $t --quiet=$quiet
}

def --env render [t: record, --quiet]: nothing -> record {
  let dir = (theme state-dir)
  mkdir $dir
  let ls_colors = (render-ls-colors $t)
  let state = (
    $t | reject source terminal
    | merge { rendered: (date now), ls_colors: ($ls_colors != null) }
  )
  $state | to nuon --indent 2 | save -f ($dir | path join theme.nuon)
  if (which starship | is-not-empty) { render-starship $t.roles | save -f ($dir | path join starship.toml) }
  if $ls_colors != null { $ls_colors | save -f ($dir | path join ls_colors) }

  theme apply $state
  if not $quiet {
    let what = (match $t.tier {
      "ansi" => "the terminal's sixteen colours"
      "derived" => "sixteen by name, shades blended from the theme"
      "palette" => $"the palette in ($t.palette | path basename)"
    })
    print $"rendered ($t.name | default 'no theme') — ($what) → ($dir)"
  }
  $state
}

# Make a resolved theme this session's: the same three things conf/theme.nu
# and conf/prompt.nu do at startup, from the same files.
export def --env "theme apply" [state: record]: nothing -> nothing {
  let c = $state.roles
  source $NUSHELL_THEME
  $env.BAT_THEME = $state.bat
  let dir = (theme state-dir)
  if ($state | get -o ls_colors | default false) { $env.LS_COLORS = (open --raw ($dir | path join ls_colors)) }
  if (($dir | path join starship.toml) | path exists) { $env.STARSHIP_CONFIG = ($dir | path join starship.toml) }
}

# ── Choosing one ──────────────────────────────────────────────────────────────

# Paint this session with a theme and change nothing on disk.
export def "theme preview" [
  name: string@"theme names"
  --ghostty   # one of Ghostty's, not a palette
]: nothing -> nothing {
  let t = (theme resolve $name --ghostty=$ghostty)
  if $t.terminal == null { error make { msg: $"($name) has no colours to paint here: Ghostty is not installed and the palette has no terminal block" } }
  theme paint $t.terminal
}

# Keep a theme: Ghostty's config for every window from now on, the app icon
# to match, this window painted (and every open one reloaded, on macOS), and
# the shell's own colours — tables, `ls`, bat, the prompt — rendered from it,
# for this session and every one after.
export def --env "theme use" [
  name: string@"theme names"
  --ghostty   # one of Ghostty's 463, not a palette (`theme list --ghostty`)
  --no-icon   # leave the app icon alone
]: nothing -> nothing {
  let t = (theme resolve $name --ghostty=$ghostty)   # a wrong name fails here, before anything is written
  let icon = (if $no_icon { null } else { render-icon $t })
  ghostty set (
    { theme: (ghostty-theme-value $t) }
    | merge (if $icon == null { {} } else { { macos-icon: "custom", macos-custom-icon: $icon } })
  )
  if $t.terminal != null and (is-terminal --stdout) { theme paint $t.terminal }
  let reloaded = (ghostty reload)
  render $t --quiet
  let windows = (if $reloaded { "every open window and new ones" } else { "this window now, new windows from Ghostty's config" })
  let icon_note = (if $icon == null { "" } else { ", icon rendered" })
  print $"theme is ($t.name) — ($windows)($icon_note); shell colours at tier ($t.tier)"
}

# The picker. `input list --fuzzy` does the searching over all of them at once,
# with each theme's own sixteen colours beside its name.
#
# Why it does not repaint as you arrow through the list: `input list` cannot call
# back on cursor movement, and the alternative — driving `input listen` and
# drawing a scrolling fuzzy list by hand — is a TUI written in Nushell to save
# one keystroke. So nothing is painted while you choose, which also means a
# cancelled list leaves the terminal exactly as it was. The theme is applied once
# you pick it, and the keep/discard question is one you answer looking at it.
# `export def theme`, not `main`: main here would be a command called `palette`.
export def --env theme [
  --ghostty   # choose among Ghostty's 463 instead of the palettes
]: nothing -> nothing {
  if not ((is-terminal --stdin) and (is-terminal --stdout)) {
    error make { msg: "`theme` is the interactive picker and needs a terminal on both ends; `theme use <name>` is not" }
  }
  let before = (ghostty settings | get -o theme)
  let rows = (theme list --swatches --ghostty=$ghostty | select theme colours)

  mut picking = true
  while $picking {
    let pick = ($rows | input list --fuzzy --display {|r| $"($r.theme) ($r.colours)" } "theme")
    if $pick == null {
      print "unchanged"
      return
    }
    theme preview $pick.theme --ghostty=$ghostty
    match ([$"keep ($pick.theme)" "pick another" "leave it as it was"] | input list $"($pick.theme) — this is it")  {
      $a if ($a | default "" | str starts-with "keep") => {
        theme use $pick.theme --ghostty=$ghostty
        $picking = false
      }
      "pick another" => { theme reset }
      _ => {
        # Esc here means the same as saying no: undo the paint.
        theme reset
        print (if $before == null { "unchanged — Ghostty's own theme is back" } else { $"unchanged — back to ($before)" })
        $picking = false
      }
    }
  }
}

# The app icon for the current theme, rendered again (after editing
# themes/icon.svg, say), or removed with --off so Ghostty's config decides.
export def "theme icon" [--off]: nothing -> nothing {
  if $off {
    ghostty set { macos-icon: null, macos-custom-icon: null }
    ghostty reload | ignore
    print "icon keys removed from the distro's Ghostty file"
    return
  }
  let cur = (theme current)
  if $cur == null or $cur.name == null { error make { msg: "no theme rendered yet — `theme use <name>`" } }
  let t = (theme resolve $cur.name --ghostty=($cur.by == "ghostty"))
  let icon = (render-icon $t)
  if $icon == null { error make { msg: "no icon: this needs macOS with qlmanage, and a theme with colours" } }
  ghostty set { macos-icon: "custom", macos-custom-icon: $icon }
  let reloaded = (ghostty reload)
  print $"icon ($icon)(if $reloaded { ' — Ghostty reloaded' } else { ' — takes effect when Ghostty reloads its config' })"
}

# ── Looking ───────────────────────────────────────────────────────────────────

# What was rendered last, or null before the first `theme use`.
export def "theme current" []: nothing -> any {
  let f = (theme state-dir | path join theme.nuon)
  if ($f | path exists) { open $f } else { null }
}

# Every role, its value and the tier that decided it — for a named theme, or
# the current one. In colour, so the row shows the colour it is talking about.
export def "theme roles" [name?: string@"theme names", --ghostty]: nothing -> table {
  let cur = (theme current | default {})
  let t = (theme resolve ($name | default ($cur | get -o name)) --ghostty=($ghostty or ($name == null and ($cur | get -o by) == "ghostty")))
  $t.roles | items {|k, v| { role: $k, value: $v, from: ($t.source | get $k), swatch: (swatch-of $v) } }
}

def swatch-of [v: string]: nothing -> string {
  if (is-hex $v) {
    let rgb = (hex-rgb $v)
    $"(ansi -e $'38;2;($rgb.0);($rgb.1);($rgb.2)m')██████(ansi reset)"
  } else {
    $"(ansi $v)██████(ansi reset)"
  }
}

# What is on disk, and whether it still matches what Ghostty says.
export def "theme status" []: nothing -> record {
  let cur = (theme current)
  let dir = (theme state-dir)
  let settings = (ghostty settings)
  {
    rendered: ($cur != null)
    name: ($cur | get -o name)
    by: ($cur | get -o by)
    tier: ($cur | get -o tier)
    dark: ($cur | get -o dark)
    palette: ($cur | get -o palette)
    bat: ($cur | get -o bat)
    ghostty_theme: ($settings | get -o theme)
    icon: ($settings | get -o "macos-custom-icon")
    rendered_at: ($cur | get -o rendered)
    files: (if ($dir | path exists) { ls $dir | get name | each {|f| $f | path basename } } else { [] })
    starship_template: (template-for starship.toml)
    nushell_theme: $NUSHELL_THEME
  }
}
