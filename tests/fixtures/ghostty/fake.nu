# A ghostty that answers from files, for the terminal tests. lib.nu's
# `fake-ghostty` puts a wrapper for it first on PATH, and GHOSTTY_FAKE names
# the root it works from:
#
#   share/ghostty/themes/   the themes it "ships" — `+list-themes` lists them
#                           as (resources), the config dir's themes/ as (user)
#   faces                   one family per line that `+show-face` finds, on top
#                           of any family whose files are in the user's font
#                           dir (`HackNerdFont-*.ttf` is “Hack Nerd Font”);
#                           anything else resolves to “JetBrains Mono”, the way
#                           Ghostty falls back to its built-in font
#   settles-at              a unix timestamp in nanoseconds: until then a family
#                           is found through `faces` only, not its files — macOS
#                           registers a font some time after it lands
#   show-config             when present, printed verbatim by `+show-config`;
#                           otherwise the config chain is read for real
#   reload-fails            when present, the fake osascript answers false
#   log                     every call, one NUON list of arguments per line
#
# The config chain is Ghostty's rule as the module relies on it: the first
# non-empty of config.ghostty and config in the XDG dir (on macOS, Application
# Support first), `config-file = ?name` includes resolved next to the file
# that holds them, a later value winning except for the repeatable font keys,
# where every value is kept and an empty one clears the list.

const REPEATABLE = [font-family font-family-bold font-family-italic font-family-bold-italic]

def --wrapped main [...args: string] {
  let root = $env.GHOSTTY_FAKE
  # Nushell hands a script its arguments re-quoted, and `--wrapped` keeps a
  # `--key="a value"` token verbatim, quotes included: `--font-family="Hack
  # Nerd Font"` here was `--font-family=Hack Nerd Font` on the command line.
  let args = $args | each {|a| $a | str replace -r '^(--[\w-]+=)"(.*)"$' '$1$2' }
  ($args | to nuon) + "\n" | save -a ($root | path join log)
  match ($args | get -o 0 | default "") {
    "+show-config" => { show-config $root }
    "+show-face" => { show-face $root $args }
    "+validate-config" => { validate $root $args }
    "+list-themes" => { list-themes $root }
    "osascript" => { osascript $root }
    $other => { print -e $"fake ghostty: no answer for ($other)"; exit 2 }
  }
}

def config-dir []: nothing -> path {
  $env.XDG_CONFIG_HOME? | default ($nu.home-dir | path join .config) | path join ghostty
}

def candidates []: nothing -> list<path> {
  let dirs = if $nu.os-info.name == "macos" {
    [($nu.home-dir | path join Library "Application Support" com.mitchellh.ghostty) (config-dir)]
  } else { [(config-dir)] }
  $dirs | each {|d| [($d | path join config.ghostty) ($d | path join config)] } | flatten
}

def user-config []: nothing -> any {
  candidates | where {|p| ($p | path exists) and ((ls -l $p | get 0.size) > 0b) } | get -o 0
}

# `key = value` lines of a file and everything it includes, in order.
def chain [file: path]: nothing -> list<record> {
  if not ($file | path exists) { return [] }
  open --raw $file | lines | each {|l| $l | str trim }
  | where {|l| ($l | is-not-empty) and not ($l | str starts-with "#") }
  | parse -r '^(?<key>[a-z0-9-]+)\s*=\s*(?<value>.*)$'
  | each {|kv|
      if $kv.key == "config-file" {
        let inc = $kv.value | str trim | str trim -l -c "?"
        let path = if ($inc | str starts-with "/") { $inc } else { $file | path dirname | path join $inc }
        chain $path
      } else { [$kv] }
    }
  | flatten
}

# The chain folded into what Ghostty would report: last wins, the repeatable
# keys as lists.
def settle [entries: list<record>]: nothing -> record {
  $entries | reduce -f {} {|kv, acc|
    let v = $kv.value | str trim
    if $kv.key in $REPEATABLE {
      let cur = $acc | get -o $kv.key | default []
      $acc | upsert $kv.key (if ($v | is-empty) { [] } else { $cur | append $v })
    } else { $acc | upsert $kv.key $v }
  }
}

def show-config [root: path] {
  let fixed = $root | path join show-config
  if ($fixed | path exists) { print (open --raw $fixed | str trim -r); return }
  let cfg = user-config
  let s = if $cfg == null { {} } else { settle (chain $cfg) }
  # Repeatable keys first, the way Ghostty prints them.
  for k in $REPEATABLE { for v in ($s | get -o $k | default []) { print $"($k) = ($v)" } }
  for kv in ($s | transpose key value | where key not-in $REPEATABLE) { print $"($kv.key) = ($kv.value)" }
}

def show-face [root: path, args: list<string>] {
  let family = $args | where {|a| $a starts-with "--font-family=" } | get -o 0 | default "" | str replace "--font-family=" ""
  let faces = $root | path join faces
  let known = if ($faces | path exists) { open --raw $faces | lines } else { [] }
  let settles = $root | path join settles-at
  let font_dir = font-dir
  let settled = (not ($settles | path exists)) or ((date now | into int) >= (open --raw $settles | str trim | into int))
  # Forward slashes: a backslash is an escape in a glob pattern (and '\\' in
  # single quotes is two of them).
  let on_disk = ($settled and (glob (($font_dir | str replace -a '\' '/') + $"/($family | str replace -a ' ' '')-*.ttf") | is-not-empty))
  let face = if ($family in $known) or $on_disk { $family } else { "JetBrains Mono" }
  print $"U+41 « A » found in face “($face)”."
}

# Where `font install` puts files on this platform (font.nu's `font dir`).
def font-dir []: nothing -> path {
  match $nu.os-info.name {
    "macos" => ($nu.home-dir | path join Library Fonts)
    "windows" => ($env.LOCALAPPDATA | path join Microsoft Windows Fonts)
    _ => ($nu.home-dir | path join .local share fonts)
  }
}

def theme-dirs [root: path]: nothing -> record {
  { resources: ($root | path join share ghostty themes), user: (config-dir | path join themes) }
}

def list-themes [root: path] {
  let dirs = theme-dirs $root
  for d in [resources user] {
    let dir = $dirs | get $d
    if ($dir | path exists) { for f in (ls $dir | get name | sort) { print $"($f | path basename) \(($d)\)" } }
  }
}

# A theme must be a shipped or user theme file, or an absolute path that
# exists — the two ways `theme use` hands one to Ghostty.
def validate [root: path, args: list<string>] {
  let file = $args | where {|a| $a starts-with "--config-file=" } | get -o 0 | default "" | str replace "--config-file=" ""
  let s = settle (chain $file)
  let theme = $s | get -o theme
  if $theme == null { exit 0 }
  let dirs = theme-dirs $root
  let ok = ($theme | path exists) or ([user resources] | any {|d| $dirs | get $d | path join $theme | path exists })
  if $ok { exit 0 }
  for d in [user resources] { print $"theme \"($theme)\" not found, tried path \"($dirs | get $d | path join $theme)\"" }
  exit 1
}

# `ghostty reload` runs `osascript -l JavaScript -e 'Application(…).performAction…'`
# and reads "true" from it; the wrapper sends every `-e` script here.
def osascript [root: path] {
  print (if ($root | path join reload-fails | path exists) { "false" } else { "true" })
}
