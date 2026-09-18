# theme — choose one of Ghostty's themes, and see it before you keep it
#
#   theme                 pick one: fuzzy list of all 463, then keep it
#   theme list            every theme Ghostty can find (--swatches: in colour)
#   theme preview <name>  paint this session only
#   theme reset           back to what Ghostty's config says
#   theme use <name>      paint, and keep it (ghostty.nu persists it)
#
# Why the terminal is the preview and not a pane: with THEME = "terminal" the
# sixteen ANSI colours ARE the Nushell theme, and a Ghostty theme file is exactly
# the palette plus background, foreground, cursor and selection. Every one of
# those can be set at runtime over OSC, so applying a theme file to the running
# session is a dozen escape sequences and no reload — what you see is the theme,
# prompt, tables and scrollback included.
#
# Ghostty cannot reload its config from the CLI (`reload_config` is a keybind
# action only), so `use` does both: OSC for this window, config for the next.

use ghostty.nu *

# ── Where the themes are ──────────────────────────────────────────────────────

# `(?m)` so one pass over the whole file replaces splitting it into lines: over
# 463 files that is 49 ms instead of 109 ms.
const PALETTE_RE = '(?m)^\s*palette\s*=\s*(?<i>\d+)\s*=\s*(?<hex>#[0-9a-fA-F]{6})\s*$'
const NAMED_RE = '(?m)^\s*(?<k>background|foreground|cursor-color|selection-background|selection-foreground)\s*=\s*(?<v>#[0-9a-fA-F]{6})\s*$'

# `+list-themes` is the authority on what exists: theme names carry spaces and
# punctuation ('TokyoNight Storm', '0x96f'), so the list comes from Ghostty and
# never from a glob. Ghostty searches two directories and labels each name with
# the one it came from, which is how a theme of your own shadows a shipped one.
export def "theme list" [
  --swatches   # add the theme's own sixteen colours as a column (+300 ms)
]: nothing -> table {
  if (which ghostty | is-empty) { error make { msg: "ghostty is not on PATH" } }
  # theme-dirs shells out, so it is resolved once: called per row the 463 themes
  # took 719 ms, hoisted they take 31 ms (333 ms with --swatches).
  let dirs = (theme-dirs)
  let themes = (
    ^ghostty +list-themes --plain
    | lines
    | parse -r '^(?<theme>.+) \((?<source>[a-z]+)\)$'
    | insert path {|r| $dirs | get -o $r.source | default "" | path join $r.theme }
  )
  if not $swatches { return $themes }
  $themes | insert colours {|t| swatch (theme-hexes $t.path) }
}

# Ghostty's two theme directories, keyed by the label `+list-themes` prints.
# The shipped one lives inside the install, so it is derived from the binary:
# Ghostty.app on macOS, a Unix prefix elsewhere.
def theme-dirs []: nothing -> record {
  let root = (which ghostty | get 0.path | path expand | path dirname | path dirname)
  let resources = (
    [
      ($root | path join Resources ghostty themes)   # Ghostty.app/Contents/
      ($root | path join share ghostty themes)       # /usr/local, /usr, ...
    ]
    | where {|d| $d | path exists } | append "" | first
  )
  { user: (ghostty config-path | path dirname | path join themes), resources: $resources }
}

# One theme file: `palette = N=#hex` for 0-15 plus a few named colours, which are
# the same things OSC can set. Anything else Ghostty allows in a theme is ignored
# rather than rejected — a theme is data, and a new key is Ghostty's business.
export def "theme palette" [name: string@theme-names]: nothing -> record {
  let f = (theme list | where theme == $name | get -o 0.path)
  if $f == null { error make { msg: $"Ghostty has no theme called '($name)'" } }
  read-theme $f $name
}

# Reads a theme FILE. Everything that works over all 463 goes through here with
# a path from a single `theme list`, never through `theme palette`, which spawns
# Ghostty to resolve the name — 463 spawns is eight seconds.
def read-theme [file: path, name: string]: nothing -> record {
  let text = (open $file)
  {
    theme: $name
    palette: ($text | parse -r $PALETTE_RE | reduce -f {} {|it, acc| $acc | upsert $it.i $it.hex })
    named: ($text | parse -r $NAMED_RE | reduce -f {} {|it, acc| $acc | upsert $it.k $it.v })
  }
}

# Just the sixteen colours, in order, for a swatch. Sorted by index rather than
# trusted to file order, because a hand-written theme need not be tidy.
def theme-hexes [file: path]: nothing -> list<string> {
  open $file | parse -r $PALETTE_RE | sort-by {|r| $r.i | into int } | get hex
}

def theme-names []: nothing -> list<string> {
  theme list | get theme
}

# ── Painting the running terminal ─────────────────────────────────────────────
#
# OSC 4;N;#hex   palette entry N          OSC 104   reset every palette entry
# OSC 10;#hex    foreground               OSC 110   reset foreground
# OSC 11;#hex    background               OSC 111   reset background
# OSC 12;#hex    cursor                   OSC 112   reset cursor
# OSC 17;#hex    selection background     OSC 117   reset selection background
# OSC 19;#hex    selection foreground     OSC 119   reset selection foreground
#
# "Reset" means back to whatever Ghostty's own configuration says, which is why
# `theme reset` needs no memory of what was there before.

# `char esc` does not exist in 0.115 — `char --list` has no name for ESC at all,
# and `char -u 1b` reads "1b" as a filesize. A \u escape is the way to write it.
const ESC = "\u{1b}"
const BEL = "\u{7}"

def osc [body: string]: nothing -> string { $"($ESC)]($body)($BEL)" }

# Every sequence for one theme as a single string: one write, nothing to tear.
def paint [t: record]: nothing -> string {
  let pal = ($t.palette | transpose i hex | each {|p| osc $"4;($p.i);($p.hex)" })
  let named = (
    [[key osc]; [foreground 10] [background 11] [cursor-color 12]
                [selection-background 17] [selection-foreground 19]]
    | each {|n| let v = ($t.named | get -o $n.key); if $v == null { "" } else { osc $"($n.osc);($v)" } }
  )
  $pal ++ $named | str join
}

# Paint this session with a theme and change nothing on disk. Interactive only:
# these bytes are instructions to a terminal, and in a pipeline they would be
# data. That is not a safety rail, it is what they mean.
export def "theme preview" [name: string@theme-names]: nothing -> nothing {
  if not $nu.is-interactive { error make { msg: "theme preview paints a terminal; there is none here" } }
  print -n (paint (theme palette $name))
}

# Hand the palette back to Ghostty's configuration — the way out of a preview
# you did not keep, and of a session someone left half-painted.
export def "theme reset" []: nothing -> nothing {
  if not $nu.is-interactive { return }
  print -n ([104 110 111 112 117 119] | each {|c| osc ($c | into string) } | str join)
}

# ── Choosing one ──────────────────────────────────────────────────────────────

# Keep a theme: Ghostty's config for every window from now on, OSC for this one.
export def "theme use" [name: string@theme-names]: nothing -> nothing {
  let t = (theme palette $name)      # a wrong name fails here, before anything is written
  ghostty set { theme: $name }
  if $nu.is-interactive { print -n (paint $t) }
  print $"theme is ($name) — this window now, new windows from Ghostty's config"
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
export def main []: nothing -> nothing {
  if not $nu.is-interactive { error make { msg: "`theme` is the interactive picker; `theme use <name>` is not" } }
  let before = (ghostty settings | get -o theme)
  let rows = (theme list --swatches | select theme colours)

  mut picking = true
  while $picking {
    let pick = ($rows | input list --fuzzy --display {|r| $"($r.theme) ($r.colours)" } "theme")
    if $pick == null {
      print "unchanged"
      return
    }
    print -n (paint (theme palette $pick.theme))
    match ([$"keep ($pick.theme)" "pick another" "leave it as it was"] | input list $"($pick.theme) — this is it")  {
      $a if ($a | default "" | str starts-with "keep") => {
        ghostty set { theme: $pick.theme }
        print $"kept ($pick.theme) — new windows will read it from Ghostty's config"
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

# Sixteen blocks in the theme's own colours, as truecolor, so a swatch shows what
# the theme IS rather than what the current palette happens to be. Bit shifts
# rather than splitting the hex into pairs: 95 ms over all 463 instead of 380 ms.
def swatch [hexes: list<string>]: nothing -> string {
  $hexes
  | each {|hex|
      let n = ($"0x($hex | str substring 1..)" | into int)
      $"(ansi -e $'38;2;($n // 65536);($n // 256 mod 256);($n mod 256)m')█"
    }
  | append (ansi reset)
  | str join
}
