# ghostty — one appended line in the user's config, and one file the distro owns
#
# With THEME = "terminal" the terminal's 16 ANSI colours ARE the Nushell theme,
# so choosing a theme means setting Ghostty's. And a Nushell distro that
# configures the terminal has one more thing to say to it: start Nushell
# (`ghostty shell`). Both are done without ever rewriting the user's own config:
#
#   <ghostty dir>/nushell-distro.ghostty    ours, rewritten freely
#   config-file = ?nushell-distro.ghostty   one line appended to theirs, once
#
# Removing that one line undoes everything, `git diff` of a dotfiles repo shows
# exactly what changed, and the user's config is backed up before the append.
#
# Verified against Ghostty 1.3.1 with XDG_CONFIG_HOME pointed at a scratch
# directory, so nothing real was touched:
#
#   * An included file wins over the file that includes it no matter WHERE the
#     `config-file` line sits — "configuration files do not take effect until
#     after the entire configuration is loaded". Appending is therefore enough:
#     we never have to find the user's own `theme =` line, let alone edit it.
#   * The `?` prefix makes a missing include a silent no-op, so deleting our
#     file is a complete uninstall even with the line still in place.
#   * A relative path resolves next to the file holding the directive.
#   * `config.ghostty` wins over `config` in the same directory, and only one of
#     the two is loaded.
#
# Ghostty has no `+reload` CLI action — `reload_config` is a keybind action —
# but on macOS its AppleScript dictionary can perform any action, so `ghostty
# reload` below reaches every open window. Elsewhere a write reaches new
# windows only, and the running one is repainted over OSC instead; see theme.nu.

# Our file, and the line that pulls it in. Relative, so it resolves next to
# whichever config Ghostty reads.
const OURS = "nushell-distro.ghostty"
const INCLUDE = "config-file = ?nushell-distro.ghostty"
const MARK = "# Added by the Nushell distro; `ghostty reset` removes it again."
# Keys Ghostty treats as a LIST: every assignment appends, and the first entry
# wins where one is used. Our file is applied after the user's, so for these a
# plain `key = value` would sit behind whatever they set and lose — verified
# with `+show-config` on 1.3.1: their `font-family` first, ours second, theirs
# used. An empty `key =` clears the list, so each of these is written as a
# reset line followed by the value.
const REPEATABLE = [font-family font-family-bold font-family-italic font-family-bold-italic]

# The Ghostty binary, wherever it is; null when there is none.
#
# On macOS it lives inside the app bundle and is only on PATH inside a Ghostty
# window, because Ghostty's shell integration prepends GHOSTTY_BIN_DIR. A shell
# started from Terminal.app, from SSH or by a script therefore sees no `ghostty`
# at all — and `which ghostty` alone would report "not installed" for a terminal
# that is plainly installed, which is exactly the case the installer meets.
export def ghostty-bin []: nothing -> any {
  let onpath = (which ghostty | get -o 0.path)
  if $onpath != null { return $onpath }
  [$env.GHOSTTY_BIN_DIR?
   "/Applications/Ghostty.app/Contents/MacOS"
   ($nu.home-dir | path join Applications "Ghostty.app" Contents MacOS)]
  | compact | where {|d| $d | is-not-empty }
  | each {|d| $d | path join ghostty }
  | where {|p| $p | path exists }
  | get -o 0
}

# The XDG config dir, which every platform has and dotfiles repos manage.
def xdg-dir []: nothing -> path {
  $env.XDG_CONFIG_HOME? | default ($nu.home-dir | path join ".config") | path join ghostty
}

# Every path Ghostty would look at, highest priority first. On macOS it reads
# Application Support as well as XDG; elsewhere only XDG. Within a directory
# `config.ghostty` beats the legacy `config`, and only one of the two is loaded.
def candidates []: nothing -> list<path> {
  let dirs = match $nu.os-info.name {
    "macos" => [($nu.home-dir | path join Library "Application Support" com.mitchellh.ghostty) (xdg-dir)]
    # No official build; the Win32 ports that exist read %LOCALAPPDATA%\ghostty
    # (shiweis/ghostty-windows README, 2026-09-02) before XDG. Unverified here.
    "windows" => [($env.LOCALAPPDATA? | default ($nu.home-dir | path join AppData Local) | path join ghostty) (xdg-dir)]
    _ => [(xdg-dir)]
  }
  $dirs | each {|d| [($d | path join config.ghostty) ($d | path join config)] } | flatten
}

# The config Ghostty is reading: the first candidate that exists and is not
# empty, which is Ghostty's own rule. When there is none we write the XDG one
# even on macOS, where `ghostty +edit-config` would have picked Application
# Support: a file under ~/.config is the one a dotfiles repo can keep, and
# Ghostty reads it as long as Application Support holds nothing. If that ever
# stops being true, `ghostty status` says so — it asks Ghostty for the theme it
# actually ended up with.
export def "ghostty config-path" []: nothing -> path {
  let found = (candidates | where {|p| ($p | path exists) and (($p | path type) == file) and ((ls -l $p | get 0.size) > 0b) })
  if ($found | is-empty) { xdg-dir | path join config.ghostty } else { $found | first }
}

def ours-path []: nothing -> path {
  ghostty config-path | path dirname | path join $OURS
}

# The settings the distro currently owns. Our file is ours alone, so parsing it
# as `key = value` lines is safe — there is nothing else in it.
export def "ghostty settings" []: nothing -> record {
  let f = (ours-path)
  if not ($f | path exists) { return {} }
  open $f
  | lines
  | each {|l| $l | str trim }
  | where {|l| ($l | is-not-empty) and not ($l | str starts-with "#") }
  | parse -r '^(?<key>[a-z0-9-]+)\s*=\s*(?<value>.*)$'
  # A bare `key =` is the reset line before a repeatable key, not a setting.
  | where {|it| ($it.value | str trim) | is-not-empty }
  | reduce -f {} {|it, acc| $acc | upsert $it.key ($it.value | str trim) }
}

# Write settings into our file and make sure the user's config includes it.
# A null value drops the key. Nothing else in their config is read or changed.
export def "ghostty set" [
  settings: record   # e.g. { theme: "TokyoNight Storm" } — null removes a key
]: nothing -> nothing {
  let merged = (ghostty settings | merge $settings | transpose key value | where value != null)
  let body = ([
    "# Written by the Nushell distro (`ghostty set`), which owns this file and"
    "# rewrites it whole, so put your own settings in your Ghostty config, not"
    "# here — it is included from there, and an included file is applied last, so"
    "# only the keys below are taken out of your hands. `ghostty reset` undoes"
    "# the whole arrangement."
    ""
  ] ++ ($merged | sort-by key | each {|s|
    if $s.key in $REPEATABLE { [$"($s.key) = " $"($s.key) = ($s.value)"] } else { [$"($s.key) = ($s.value)"] }
  } | flatten) ++ [""])
  let f = (ours-path)
  let before = (if ($f | path exists) { open --raw $f } else { null })
  mkdir ($f | path dirname)
  $body | str join (char nl) | save -f $f
  link

  # Ghostty is the judge of its own configuration, and it will tell us: an
  # unknown key or a theme it cannot find fails `+validate-config`. Put the file
  # back the way it was rather than leaving a broken include behind.
  let check = (validate)
  if not $check.ok {
    if $before == null { rm $f } else { $before | save -f $f }
    error make { msg: "Ghostty rejected that configuration", label: { text: $check.err, span: (metadata $settings).span } }
  }
}

# Remove everything the distro put in Ghostty's configuration: our file, and
# the one line that includes it. The backup of their config is left in place.
export def "ghostty reset" []: nothing -> nothing {
  let cfg = (ghostty config-path)
  let f = (ours-path)
  if ($f | path exists) { rm $f; print $"removed ($f)" }
  if ($cfg | path exists) and (includes? $cfg) {
    # Both lines we added, and any blank tail they leave behind.
    open $cfg
    | lines
    | where {|l| ($l | str trim) not-in [$INCLUDE $MARK] }
    | reverse | skip until {|l| ($l | str trim) | is-not-empty } | reverse
    | append ""
    | str join (char nl)
    | save -f $cfg
    print $"removed the include line from ($cfg)"
  }
  print "restart Ghostty, or open a new window, to see its own configuration again"
}

# Where things stand, and whether Ghostty agrees with us about which file it
# reads — `ghostty +show-config` is the only authority on that.
export def "ghostty status" []: nothing -> record {
  let cfg = (ghostty config-path)
  {
    installed: ((ghostty-bin) != null)
    config: $cfg
    config_exists: ($cfg | path exists)
    also_present: (candidates | where {|p| $p != $cfg and ($p | path exists) })
    ours: (ours-path)
    included: (if ($cfg | path exists) { includes? $cfg } else { false })
    settings: (ghostty settings)
    live_theme: (ghostty live "theme")
    # What a new window starts. Ghostty's own default when nothing sets it:
    # SHELL, then the passwd entry — zsh on a stock Mac.
    shell: (ghostty live "command")
  }
}

# ── the shell ─────────────────────────────────────────────────────────────────
#
# Ghostty starts SHELL, or failing that the passwd shell, and neither is Nushell
# on any machine this distro has just been installed on. Changing the login
# shell (`chsh`) is the wrong fix: macOS insists on /etc/shells, a Homebrew `nu`
# moves at every upgrade, and scripts that assume a POSIX $SHELL break. So the
# terminal is told instead — `command = <nu>` in our included file, which wins
# over a `command =` in their own config like every other key we own.
#
# Verified on macOS with Ghostty 1.3.1: a bare absolute path, no arguments, is
# still launched through `login -flp <user> /bin/sh -c "exec -l <nu>"`, and
# Nushell reads the dash in argv[0] the way every shell does, so the window
# gets a LOGIN nu ($nu.is-login == true) with login's environment. No `-l` in
# the value, then — it would only push Ghostty into `/bin/sh -c` argument
# parsing for nothing.

# The nu Ghostty should run. The one on PATH, not `$nu.current-exe`: PATH holds
# the path the user installed — /opt/homebrew/bin/nu, ~/.cargo/bin/nu — while
# the running binary can be the versioned Cellar file behind that symlink,
# which stops existing at the next `brew upgrade`.
export def "ghostty nu-path" []: nothing -> path {
  which nu | where type == external | get -o 0.path | default $nu.current-exe
}

# Make Nushell what a new Ghostty window starts, or hand that back to Ghostty.
#
# On macOS the same write makes the right Option key Alt, unless their config
# already says something about it. Ghostty's default (`macos-option-as-alt`
# unset) lets Option compose the layout's characters, so Alt+E (the agent),
# Alt+Enter (a newline) and Alt+arrows (words) type an accent or a symbol
# instead — Ghostty 1.3.1 default, verified 2026-09-19. `right` keeps the left
# key for the layout (on a Hungarian ISO layout `@ [ ] { }` are Option+letter;
# on US it is the accents) and gives the shell the other one.
export def "ghostty shell" [
  --reset  # drop our `command` (and the Option key), so Ghostty falls back to SHELL / passwd again
]: nothing -> nothing {
  if $reset {
    ghostty set { command: null, macos-option-as-alt: null }
  } else {
    let alt = (if $nu.os-info.name == "macos" and (ghostty live "macos-option-as-alt" | default "" | is-empty) { { macos-option-as-alt: "right" } } else { {} })
    ghostty set ({ command: (ghostty nu-path) } | merge $alt)
  }
  let now = (ghostty live "command")
  print (if $now == null {
    "Ghostty is not installed; the setting is written for when it is"
  } else {
    $"new Ghostty windows start ($now)"
  })
}

# Reload Ghostty's configuration in every open window, from the CLI. There is
# no `+reload` action, but the AppleScript dictionary (`sdef Ghostty.app`) has
# `perform action`, which takes any keybind action string — `reload_config`
# included — so on macOS this is what makes a written theme or icon reach the
# windows already open. True when Ghostty did it; false when it is not running
# or this is not macOS (Linux has no equivalent yet), and the caller falls
# back to the OSC repaint. Verified with Ghostty 1.3.1, 2026-09-19.
#
# The app is addressed by pid, not by name. A child of a Ghostty shell that
# checks in with LaunchServices — `screencapture -v`, ffmpeg's screen capture,
# an osascript sitting in a `tell` block — is listed *as* Ghostty (same bundle
# id, the shell's responsible process) for as long as it runs, and `tell
# application "Ghostty"` then resolves to it: every window lookup fails with
# -1728 and the reload silently reports false. JXA's `Application(pid)` cannot
# be hijacked. The pid is the shell's own ancestor, 15 ms of `ps` hops; the
# name is the fallback for a shell Ghostty did not start (ssh, a test).
# Seen on macOS 27.2 with Ghostty 1.3.1, 2026-09-19.
export def "ghostty reload" []: nothing -> bool {
  if $nu.os-info.name != "macos" { return false }
  let app = (match (ghostty-pid) { null => 'Application("Ghostty")', $p => $"Application\(($p))" })
  let r = (^osascript -l JavaScript -e $"($app).performAction\('reload_config', {on: ($app).windows[0].terminals[0]})" | complete)
  $r.exit_code == 0 and ($r.stdout | str trim) == "true"
}

# The Ghostty this shell runs in: the nearest ancestor that is Ghostty itself,
# or null when no ancestor is (then the shell was not started by Ghostty).
def ghostty-pid []: nothing -> any {
  mut pid = $nu.pid
  for _ in 0..16 {
    let row = (^ps -o ppid=,comm= -p $pid | str trim | split row -r '\s+' -n 2)
    if ($row | length) < 2 { return null }
    if ($row.1 | path basename) == "ghostty" { return $pid }
    $pid = ($row.0 | into int)
    if $pid <= 1 { return null }
  }
  null
}

# ── internals ─────────────────────────────────────────────────────────────────

def includes? [cfg: path]: nothing -> bool {
  open $cfg | lines | any {|l| ($l | str trim) == $INCLUDE }
}

# Append the include line, once, after backing their config up. Creating the
# config when there is none is part of the job: a user who has never written one
# still gets the theme.
def link []: nothing -> nothing {
  let cfg = (ghostty config-path)
  if not ($cfg | path exists) {
    mkdir ($cfg | path dirname)
    [
      "# Ghostty configuration."
      $"# The line below pulls in ($OURS), which `nu-config` writes."
      ""
      $INCLUDE
      ""
    ] | str join (char nl) | save -f $cfg
    print $"created ($cfg)"
    return
  }
  if (includes? $cfg) { return }
  let backup = $"($cfg).backup-(date now | format date '%Y%m%d-%H%M%S')"
  cp $cfg $backup
  let text = (open $cfg)
  let sep = if ($text | str ends-with (char nl)) { "" } else { (char nl) }
  $"($text)($sep)(char nl)($MARK)(char nl)($INCLUDE)(char nl)" | save -f $cfg
  print $"($cfg | path basename) now includes ($OURS) — backup at ($backup | path basename)"
}

# `ghostty +validate-config` on the whole chain, our file included. Silent when
# Ghostty is not installed: a theme can be chosen before the terminal is there.
def validate []: nothing -> record<ok: bool, err: string> {
  let g = (ghostty-bin)
  if $g == null { return { ok: true, err: "" } }
  let r = (^$g +validate-config --config-file=(ghostty config-path) | complete)
  # Ghostty repeats each complaint once per surface it would apply to.
  { ok: ($r.exit_code == 0), err: ([$r.stdout $r.stderr] | str join | str trim | lines | uniq | str join (char nl)) }
}

# What Ghostty itself reports for one key, which is how we know we wrote to the
# file it actually reads. Null when Ghostty is not installed or the key is
# unset — `+show-config` prints only keys that resolved to a value. For a
# repeatable key (`font-family`) this is the first value, which is the one
# Ghostty uses. 18 ms.
export def "ghostty live" [key: string]: nothing -> any {
  let g = (ghostty-bin)
  if $g == null { return null }
  ^$g +show-config
  | lines
  # Concatenated, not interpolated: in a `$'…'` string `\(` does not escape
  # the paren the regex group needs.
  | parse -r ('^' + $key + '\s*=\s*(?<v>.+)$')
  | get -o 0.v
}
