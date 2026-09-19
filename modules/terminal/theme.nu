# theme — Ghostty's themes: listing them, reading them, painting one onto the
# running terminal
#
#   theme list            every theme Ghostty can find (--swatches: in colour)
#   theme palette <name>  one theme file as data: the sixteen and the named colours
#   theme preview <name>  paint this session only
#   theme reset           back to what Ghostty's config says
#
# Choosing one — `theme`, `theme use` — and what the choice means for the shell
# is palette.nu, which builds on the two things here: a theme file as data, and
# a theme painted onto the window you are in.
#
# Why the terminal is the preview and not a pane: the sixteen ANSI colours are
# the base of every Nushell theme this distro renders, and a Ghostty theme file
# is exactly the palette plus background, foreground, cursor and selection.
# Every one of those can be set at runtime over OSC, so applying a theme file to
# the running session is a dozen escape sequences and no reload — what you see
# is the theme, prompt, tables and scrollback included.

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
  if (ghostty-bin) == null { error make { msg: "ghostty is not installed — `terminal install ghostty`" } }
  # theme-dirs shells out, so it is resolved once: called per row the 463 themes
  # took 719 ms, hoisted they take 31 ms (333 ms with --swatches).
  let dirs = (theme-dirs)
  let themes = (
    ^(ghostty-bin) +list-themes --plain
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
  let root = (ghostty-bin | path expand | path dirname | path dirname)
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
export def "theme palette" [name: string@"theme names"]: nothing -> record {
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

# The names alone — what every `<name>` argument completes from.
export def "theme names" []: nothing -> list<string> {
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

# Paint this session with a theme and change nothing on disk. The test is
# `is-terminal --stdout`, not `$nu.is-interactive`: these bytes are instructions
# to a terminal and in a pipeline they would be data, so what matters is where
# stdout goes. It is also why install.nu can preview — a script is never
# "interactive", but its stdout is the terminal you are looking at.
export def "theme preview" [name: string@"theme names"]: nothing -> nothing {
  if not (is-terminal --stdout) { error make { msg: "theme preview paints a terminal; stdout is not one" } }
  print -n (paint (theme palette $name))
}

# Hand the palette back to Ghostty's configuration — the way out of a preview
# you did not keep, and of a session someone left half-painted.
export def "theme reset" []: nothing -> nothing {
  if not (is-terminal --stdout) { return }
  print -n ([104 110 111 112 117 119] | each {|c| osc ($c | into string) } | str join)
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
