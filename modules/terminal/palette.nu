# palette — one palette, resolved in tiers, rendered for every tool
#
#   theme sync             re-resolve the current theme and re-render every file
#   theme roles [name]     the resolved roles, as a table, with where each came from
#   theme status           what is rendered, from which theme, at which tier
#
# A theme is a palette RECORD, and every tool's colours are rendered from it.
# Nobody writes a Nushell theme, a starship palette or a vivid theme by hand:
# themes/nushell.nu, themes/starship.toml and themes/vivid.yml are written
# against a small role vocabulary — fg_muted, border, accent, orange, … — and
# this file decides what each role IS for the theme in use. Three tiers, each
# only filling in what the one before could not say:
#
#   1  ansi     themes/palettes/ansi.nuon: every role an ANSI NAME. The sixteen
#               are the terminal's own, so `red` is whatever the terminal paints
#               red — and the sixteen stay names in every tier, which is what
#               keeps the shell right when the palette changes under it (SSH,
#               tmux, a hand-edited Ghostty config). What ANSI cannot say —
#               a muted grey, a border, an orange — is approximated.
#   2  derived  the Ghostty theme file gives the sixteen, background and
#               foreground as hex, so the shaded roles are BLENDED from them:
#               fg_muted is fg pulled halfway to bg, border is bg pushed a
#               quarter of the way to fg, orange is red mixed with yellow. Hex,
#               but only for roles ANSI has no word for. Every one of Ghostty's
#               463 themes gets this.
#   3  palette  themes/palettes/<slug>.nuon names the shaded roles exactly —
#               Catppuccin's overlay1, surface1, peach — and can name a bat and
#               a vivid theme that already match.
#
# `theme use` resolves and renders; the result is three files under
# <your dir>/.state/theme/, which conf/theme.nu and conf/prompt.nu read at
# startup. Rendered, not resolved at every start: theme.nuon is 1 kB and opens
# in 0.36 ms (median of 21), a resolve is 40 ms because `theme palette` spawns
# Ghostty to find the theme file, and a render on top runs vivid:
#
#   theme.nuon      the roles, plus the theme name, tier and the bat theme
#   starship.toml   themes/starship.toml with [palettes.distro] filled in
#   ls_colors       vivid's output for the theme, a raw string
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

# Ghostty's palette index for each of the sixteen roles, and the two named
# colours; what tier two blends from.
const SIXTEEN = {
  black: 0, red: 1, green: 2, yellow: 3, blue: 4, magenta: 5, cyan: 6, white: 7
  bright_black: 8, bright_red: 9, bright_green: 10, bright_yellow: 11
  bright_blue: 12, bright_magenta: 13, bright_cyan: 14, bright_white: 15
}

# ── Where the rendered files live ─────────────────────────────────────────────

export def "theme state-dir" []: nothing -> path {
  $nu.data-dir | path join .state theme
}

def user-palettes []: nothing -> path {
  $nu.config-path | path dirname | path join themes palettes
}

# "Catppuccin Macchiato" → catppuccin-macchiato: the file name a palette has.
export def "theme slug" [name: string]: nothing -> string {
  $name | str lowercase | str replace -ra '[^a-z0-9]+' '-' | str trim -c '-'
}

# The palette file for a theme name, the user's directory first, or null.
def palette-file [name: string]: nothing -> any {
  let f = $"(theme slug $name).nuon"
  [(user-palettes | path join $f) ($SHIPPED_PALETTES | path join $f)]
  | where {|p| $p | path exists }
  | get -o 0
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

# ── Resolving ─────────────────────────────────────────────────────────────────

# Tier one, as shipped: the file, not a copy of it, so there is one list of roles.
def ansi-palette []: nothing -> record {
  open ($SHIPPED_PALETTES | path join ansi.nuon)
}

# The resolved theme for a name: the roles and everything the render needs.
# `null` is "no theme chosen", which is tier one and nothing else.
#
#   name      the Ghostty theme, or null
#   tier      ansi | derived | palette
#   palette   the palette file used, or null
#   bat       a theme bat ships
#   vivid     a theme vivid ships, or null to render themes/vivid.yml
#   roles     role → Nushell colour (an ANSI name or a hex)
#   source    role → which tier decided it, for `theme roles`
export def "theme resolve" [name?: string]: nothing -> record {
  let base = (ansi-palette)
  mut roles = $base.roles
  mut source = ($roles | items {|k, v| { $k: "ansi" } } | as-record)
  mut r: record = { name: $name, tier: "ansi", palette: null, bat: $base.bat, vivid: null }
  if $name == null { return ($r | merge { roles: $roles, source: $source }) }

  # Tier two: Ghostty's theme file, when Ghostty has one by that name. Without
  # Ghostty (a Linux box, SSH) the name is kept and the roles stay ANSI.
  let ghostty = (try { theme palette $name } catch { null })
  if $ghostty != null and ($ghostty.palette | columns | length) == 16 {
    let hexes = (
      $SIXTEEN | items {|role, i| { $role: ($ghostty.palette | get ($i | into string)) } } | as-record
      | merge { bg: ($ghostty.named | get -o background | default ($ghostty.palette | get "0")) }
      | merge { fg: ($ghostty.named | get -o foreground | default ($ghostty.palette | get "7")) }
    )
    for d in ($DERIVED | transpose role rule) {
      $roles = ($roles | upsert $d.role (mix ($hexes | get $d.rule.mix.0) ($hexes | get $d.rule.mix.1) $d.rule.mix.2))
      $source = ($source | upsert $d.role "derived")
    }
    $r.tier = "derived"
  }

  # Tier three: a palette file. A role may name one of the palette's colours
  # or carry a colour of its own.
  let pf = (palette-file $name)
  if $pf != null {
    let p = (open $pf)
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
    })
  }
  $r | merge { roles: $roles, source: $source }
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

# A template: the user's copy in their themes/ when there is one, else the shipped one.
def template-for [file: string]: nothing -> path {
  let user = ($nu.config-path | path dirname | path join themes $file)
  if ($user | path exists) { $user } else { $DISTRO_ROOT | path join themes $file }
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

# Resolve a theme and write every rendered file. The name defaults to the one
# rendered last time, so `theme sync` after a `git pull` picks up a changed
# template; `--none` renders the ANSI tier and forgets the name.
export def --env "theme sync" [
  name?: string
  --none   # no theme: tier one, and the state says so
  --quiet (-q)
]: nothing -> record {
  let name = if $none { null } else { $name | default (current-name) }
  # A name has to be a theme Ghostty knows or a palette file; without Ghostty
  # (`theme names` errors) any name is taken, and resolves at tier one.
  if $name != null {
    let known = (try { theme names } catch { null })
    if $known != null and $name not-in $known and (palette-file $name) == null {
      error make { msg: $"Ghostty has no theme called '($name)' and there is no palette file for it", label: { text: "not a theme", span: (metadata $name).span } }
    }
  }
  let t = (theme resolve $name)
  let dir = (theme state-dir)
  mkdir $dir

  let ls_colors = (render-ls-colors $t)
  let state = (
    $t | reject source
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

# Keep a theme: Ghostty's config for every window from now on, OSC for this
# one, and the shell's own colours — tables, `ls`, bat, the prompt — rendered
# from it, for this session and every one after.
export def --env "theme use" [name: string@"theme names"]: nothing -> nothing {
  theme palette $name | ignore       # a wrong name fails here, before anything is written
  ghostty set { theme: $name }
  if (is-terminal --stdout) { theme preview $name }
  theme sync $name --quiet
  let s = (theme current)
  print $"theme is ($name) — this window now, new windows from Ghostty's config; shell colours at tier ($s.tier)"
}

# The picker. `input list --fuzzy` does the searching over all 463 at once, with
# each theme's own sixteen colours beside its name.
#
# Why it does not repaint as you arrow through the list: `input list` cannot call
# back on cursor movement, and the alternative — driving `input listen` and
# drawing a scrolling fuzzy list by hand — is a TUI written in Nushell to save
# one keystroke. So nothing is painted while you choose, which also means a
# cancelled list leaves the terminal exactly as it was. The theme is applied once
# you pick it, and the keep/discard question is one you answer looking at it.
# `export def theme`, not `main`: main here would be a command called `palette`.
export def --env theme []: nothing -> nothing {
  if not ((is-terminal --stdin) and (is-terminal --stdout)) {
    error make { msg: "`theme` is the interactive picker and needs a terminal on both ends; `theme use <name>` is not" }
  }
  let before = (ghostty settings | get -o theme)
  let rows = (theme list --swatches | select theme colours)

  mut picking = true
  while $picking {
    let pick = ($rows | input list --fuzzy --display {|r| $"($r.theme) ($r.colours)" } "theme")
    if $pick == null {
      print "unchanged"
      return
    }
    theme preview $pick.theme
    match ([$"keep ($pick.theme)" "pick another" "leave it as it was"] | input list $"($pick.theme) — this is it")  {
      $a if ($a | default "" | str starts-with "keep") => {
        theme use $pick.theme
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

# ── Looking ───────────────────────────────────────────────────────────────────

# What was rendered last, or null before the first `theme use`.
export def "theme current" []: nothing -> any {
  let f = (theme state-dir | path join theme.nuon)
  if ($f | path exists) { open $f } else { null }
}

def current-name []: nothing -> any {
  theme current | default {} | get -o name
}

# Every role, its value and the tier that decided it — for a named theme, or
# the current one. In colour, so the row shows the colour it is talking about.
export def "theme roles" [name?: string]: nothing -> table {
  let t = (theme resolve ($name | default (current-name)))
  $t.roles | items {|k, v| { role: $k, value: $v, from: ($t.source | get $k), swatch: (swatch-of $v) } }
}

def swatch-of [v: string]: nothing -> string {
  let code = if (is-hex $v) {
    let rgb = (hex-rgb $v)
    $"38;2;($rgb.0);($rgb.1);($rgb.2)m"
  } else { "" }
  if (is-hex $v) { $"(ansi -e $code)██████(ansi reset)" } else { $"(ansi $v)██████(ansi reset)" }
}

# What is on disk, and whether it still matches what Ghostty says.
export def "theme status" []: nothing -> record {
  let cur = (theme current)
  let dir = (theme state-dir)
  {
    rendered: ($cur != null)
    name: ($cur | get -o name)
    tier: ($cur | get -o tier)
    palette: ($cur | get -o palette)
    bat: ($cur | get -o bat)
    ghostty_theme: (ghostty settings | get -o theme)
    in_sync: (($cur | get -o name) == (ghostty settings | get -o theme))
    rendered_at: ($cur | get -o rendered)
    files: (if ($dir | path exists) { ls $dir | get name | each {|f| $f | path basename } } else { [] })
    starship_template: (template-for starship.toml)
    nushell_theme: $NUSHELL_THEME
  }
}
