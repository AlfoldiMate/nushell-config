# Theme resolution and rendering (modules/terminal/palette.nu, theme.nu):
# the three tiers, a Ghostty theme file as data and back, and `theme use`
# end to end against the fake ghostty, whose shipped themes are the three in
# tests/fixtures/ghostty/themes. Zenburned has no palette (tier two);
# Catppuccin Macchiato has one that extends it (tier three); onedark is an
# NvChad palette with its own sixteen (tier three, handed to Ghostty as a
# file).
use lib.nu *
use std/assert
use terminal *

def "test slug is the palette file name" [] {
  assert equal (theme slug "Catppuccin Macchiato") catppuccin-macchiato
  assert equal (theme slug "0x96f") "0x96f"
  assert equal (theme slug "  TokyoNight Storm! ") tokyonight-storm
}

def "test no theme resolves at tier one with every role an ANSI name" [] {
  let t = theme resolve
  assert equal ($t | select name by tier palette terminal ghostty bat) { name: null, by: ghostty, tier: ansi, palette: null, terminal: null, ghostty: null, bat: ansi }
  assert ($t.roles | values | all {|v| $v !~ '^#' }) "tier one holds no hex"
  assert ($t.source | values | all {|s| $s == ansi })
}

def "test a Ghostty theme with no palette resolves at tier two, shades blended" [] {
  let fake = fake-ghostty
  let t = theme resolve Zenburned
  assert equal ($t | select name by tier ghostty palette) { name: Zenburned, by: ghostty, tier: derived, ghostty: Zenburned, palette: null }
  # The sixteen keep their names; the shaded roles are blended from the hexes.
  assert equal $t.roles.red red
  assert equal $t.source.red ansi
  assert equal $t.source.fg_muted derived
  # fg #f0e4cf pulled halfway to bg #404040.
  assert equal $t.roles.fg_muted "#989288"
  assert equal $t.roles.orange "#cd7869" "red mixed with yellow"
  assert equal $t.dark true
  assert equal ($t.terminal.palette | columns | length) 16
  assert equal $t.terminal.named.background "#404040"
}

def "test a light theme is told from a dark one" [] {
  let fake = fake-ghostty
  assert equal (theme resolve "Catppuccin Latte" | get dark) false
  assert equal (theme resolve "Catppuccin Macchiato" | get dark) true
}

def "test a palette extending a Ghostty theme resolves at tier three" [] {
  let fake = fake-ghostty
  let t = theme resolve "Catppuccin Macchiato"
  assert equal ($t | select name by tier ghostty bat vivid) { name: "Catppuccin Macchiato", by: palette, tier: palette, ghostty: "Catppuccin Macchiato", bat: "Catppuccin Macchiato", vivid: catppuccin-macchiato }
  assert ($t.palette | path basename | $in == "catppuccin-macchiato.nuon")
  assert equal $t.source.fg_muted palette
  let p = open $t.palette
  assert equal $t.roles.fg_muted ($p.colours | get $p.roles.fg_muted) "the colour the palette names for the role"
  assert equal $t.roles.red red "the sixteen stay names"
  assert equal ($t.terminal.palette | get "0") "#494d64" "the sixteen come from the Ghostty file"
}

def "test a palette with its own sixteen needs no Ghostty and is handed to it as a file" [] {
  let t = theme resolve onedark
  assert equal ($t | select by tier ghostty) { by: palette, tier: palette, ghostty: file }
  assert equal ($t.terminal.palette | get "1") "#e06c75"
  assert equal $t.terminal.named.background "#1e222a"
  assert equal $t.source.orange palette
}

def "test --ghostty ignores a palette that does not extend that theme" [] {
  let fake = fake-ghostty
  # zenburn.nuon exists (NvChad's), but names no Ghostty theme, so with
  # --ghostty it is the Ghostty theme alone — which the fake does not ship.
  let err = try { theme resolve Zenburn --ghostty; null } catch {|e| $e.msg }
  assert ($err | str contains "no theme called 'Zenburn'") $err
  let t = theme resolve "Catppuccin Macchiato" --ghostty
  assert equal $t.tier palette "a palette that does extend the theme still applies"
}

def "test an unknown name is an error before anything is written" [] {
  let fake = fake-ghostty
  let err = try { theme resolve "No Such Theme"; null } catch {|e| $e.msg }
  assert ($err | str contains "no theme called 'No Such Theme'") $err
  let used = try { theme use "No Such Theme" --no-icon; null } catch {|e| $e.msg }
  assert ($used | str contains "no theme called") $used
  assert equal (ghostty settings) {} "nothing reached Ghostty"
  assert equal (ghostty-calls $fake | where {|c| $c.0 == "+validate-config" }) []
  assert (((theme current | default {}) | get -o name) != "No Such Theme")
}

def "test roles is a table of role, value and the tier that decided it" [] {
  let fake = fake-ghostty
  let rows = theme roles Zenburned
  assert equal ($rows | columns) [role value from swatch]
  assert equal ($rows | where role == red | get 0 | select value from) { value: red, from: ansi }
  assert equal ($rows | where role == border | get 0.from) derived
}

# ── Ghostty theme files ───────────────────────────────────────────────────────

def "test ghostty themes lists what Ghostty ships and what the user added" [] {
  let fake = fake-ghostty
  mkdir ($fake.config | path join themes)
  open --raw ($fake.themes | path join Zenburned) | save ($fake.config | path join themes Mine)
  let rows = ghostty themes
  assert equal ($rows | get theme) ["Catppuccin Latte" "Catppuccin Macchiato" Zenburned Mine]
  assert equal ($rows | where theme == Mine | get 0.source) user
  assert equal ($rows | where theme == Zenburned | get 0.path) ($fake.themes | path join Zenburned)
}

def "test theme palette reads a Ghostty file as the sixteen and the named colours" [] {
  let fake = fake-ghostty
  let p = theme palette Zenburned
  assert equal $p.theme Zenburned
  assert equal ($p.palette | columns | length) 16
  assert equal ($p.palette | get "15") "#c0ab86"
  assert equal $p.named { background: "#404040", foreground: "#f0e4cf", cursor-color: "#f3eadb", selection-background: "#746956", selection-foreground: "#f0e4cf" }
}

def "test ghostty-file writes the lines Ghostty reads, line for line" [] {
  let fake = fake-ghostty
  let file = $fake.themes | path join Zenburned
  let back = theme read $file Zenburned | theme ghostty-file $in
  # Everything in the fixture but `cursor-text`, which is not a colour OSC sets.
  let expected = open --raw $file | lines | where $it !~ '^cursor-text' | append "" | str join "\n"
  assert equal $back $expected
  let t = theme resolve onedark
  let lines = theme ghostty-file $t.terminal | lines
  assert equal ($lines | first) "palette = 0=#1e222a"
  assert ("background = #1e222a" in $lines)
  assert ("selection-background = #373b43" in $lines)
}

# ── theme use ─────────────────────────────────────────────────────────────────

def "test theme use renders the files, writes Ghostty and reports the theme" [] {
  let fake = fake-ghostty
  theme use onedark --no-icon
  let dir = theme state-dir
  assert (($dir | path join theme.nuon) | path exists)
  assert (($dir | path join ghostty onedark) | path exists) "a palette with its own sixteen is written as a Ghostty theme file"
  assert equal (theme current | select name by tier) { name: onedark, by: palette, tier: palette }
  assert equal (ghostty settings | get theme) ($dir | path join ghostty onedark)
  assert equal (ghostty live theme) ($dir | path join ghostty onedark)
  assert equal (theme status | select name ghostty_theme icon) { name: onedark, ghostty_theme: ($dir | path join ghostty onedark), icon: null }
  if (which starship | is-not-empty) {
    let toml = open --raw ($dir | path join starship.toml) | from toml
    assert equal $toml.palette distro
    assert equal $toml.palettes.distro.red red
    assert equal $toml.palettes.distro.orange ((theme current).roles.orange)
  }
}

def "test theme use with a Ghostty theme writes its name and reloads" [] {
  let fake = fake-ghostty
  theme use "Catppuccin Macchiato" --no-icon
  assert equal (ghostty settings | get theme) "Catppuccin Macchiato"
  assert equal (theme current | select name tier bat) { name: "Catppuccin Macchiato", tier: palette, bat: "Catppuccin Macchiato" }
  let calls = ghostty-calls $fake | each {|c| $c.0 }
  assert ("+validate-config" in $calls) ($calls | to nuon)
  if $nu.os-info.name == "macos" { assert ("osascript" in $calls) "every open window is reloaded on macOS" }
}

def "test theme sync re-renders the current theme and --none forgets it" [] {
  let fake = fake-ghostty
  theme use Zenburned --no-icon
  let s = theme sync --quiet
  assert equal ($s | select name tier) { name: Zenburned, tier: derived }
  let none = theme sync --none --quiet
  assert equal ($none | select name tier) { name: null, tier: ansi }
  assert equal (theme current | get name) null
}

# ── the icon ──────────────────────────────────────────────────────────────────

# The corner of the tile is transparent and its centre is the theme's
# background, exactly — the check that found the white square qlmanage left.
# Read with Python's zlib: every Mac has python3, and a PNG reader is thirty
# lines.
const PNG_PIXELS = '
import sys, zlib, struct
data = open(sys.argv[1], "rb").read()
pos, chunks, w = 8, [], 0
while pos < len(data):
    n, kind = struct.unpack(">I4s", data[pos:pos+8]); body = data[pos+8:pos+8+n]; pos += 12 + n
    if kind == b"IHDR": w, h, depth, ctype = struct.unpack(">IIBB", body[:10])
    if kind == b"IDAT": chunks.append(body)
raw = zlib.decompress(b"".join(chunks))
bpp = 4 if ctype == 6 else 3
stride = w * bpp
rows, prev = [], bytearray(stride)
for y in range(h // 2 + 1):  # the centre row is the last one needed
    f = raw[y*(stride+1)]; line = bytearray(raw[y*(stride+1)+1:(y+1)*(stride+1)])
    for i in range(stride):
        a = line[i-bpp] if i >= bpp else 0; b = prev[i]; c = prev[i-bpp] if i >= bpp else 0
        if f == 1: line[i] = (line[i] + a) & 255
        elif f == 2: line[i] = (line[i] + b) & 255
        elif f == 3: line[i] = (line[i] + (a + b) // 2) & 255
        elif f == 4:
            p = a + b - c; pa, pb, pc = abs(p-a), abs(p-b), abs(p-c)
            line[i] = (line[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
    rows.append(line); prev = line
def px(x, y): return list(rows[y][x*bpp:x*bpp+bpp])
print(w, px(2, 2), px(w//2, h//2))
'

def "test the icon is a PNG with a transparent corner and the background at its centre" [] {
  let fake = fake-ghostty
  if $nu.os-info.name != "macos" { skip-test "the rasterizer is AppKit, macOS only" }
  theme use onedark
  let icon = ghostty settings | get macos-custom-icon
  assert ($icon | path exists) $icon
  assert equal (ghostty settings | get macos-icon) custom
  let out = ^python3 -c $PNG_PIXELS $icon | complete
  assert equal $out.exit_code 0 $out.stderr
  # 1024 px, corner rgba 0 0 0 0, centre onedark's bg #1e222a = 30 34 42 opaque.
  assert equal ($out.stdout | str trim) "1024 [0, 0, 0, 0] [30, 34, 42, 255]"
}
