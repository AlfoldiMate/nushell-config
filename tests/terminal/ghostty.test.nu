# modules/terminal/ghostty.nu against the fake ghostty (lib.nu `fake-ghostty`):
# which config file is read, what `ghostty set` writes and undoes, and what
# Ghostty is asked. Nothing here touches a real Ghostty: HOME and
# XDG_CONFIG_HOME are the run's own.
use lib.nu *
use std/assert
use terminal *

def config-of [fake: record]: nothing -> string { open --raw ($fake.config | path join config.ghostty) }
def ours-of [fake: record]: nothing -> string { open --raw ($fake.config | path join nushell-distro.ghostty) }

# ── config-path ───────────────────────────────────────────────────────────────

def "test config-path is the XDG config.ghostty when nothing exists yet" [] {
  let fake = fake-ghostty
  assert equal (ghostty config-path) ($fake.config | path join config.ghostty)
}

def "test config-path prefers config.ghostty over config, and skips an empty file" [] {
  let fake = fake-ghostty
  "theme = Zenburned\n" | save ($fake.config | path join config)
  assert equal (ghostty config-path) ($fake.config | path join config)
  "" | save ($fake.config | path join config.ghostty)
  assert equal (ghostty config-path) ($fake.config | path join config) "an empty config.ghostty must not win"
  "theme = Zenburned\n" | save -f ($fake.config | path join config.ghostty)
  assert equal (ghostty config-path) ($fake.config | path join config.ghostty)
}

def "test config-path reads Application Support before XDG on macOS" [] {
  let fake = fake-ghostty
  if $nu.os-info.name != "macos" { skip-test "Application Support is a macOS path" }
  let as = $nu.home-dir | path join Library "Application Support" com.mitchellh.ghostty
  mkdir $as
  "theme = Zenburned\n" | save ($as | path join config)
  "theme = Zenburned\n" | save ($fake.config | path join config.ghostty)
  assert equal (ghostty config-path) ($as | path join config)
  assert ((ghostty status).also_present == [($fake.config | path join config.ghostty)])
}

# ── set · settings · reset ────────────────────────────────────────────────────

def "test set creates the config with the include when there is none" [] {
  let fake = fake-ghostty
  ghostty set { theme: Zenburned }
  assert ((config-of $fake) | str contains "config-file = ?nushell-distro.ghostty")
  assert equal (ghostty settings) { theme: Zenburned }
  assert ((ours-of $fake) | lines | any {|l| $l == "theme = Zenburned" })
  assert equal (ghostty status | select included live_theme) { included: true, live_theme: Zenburned }
}

def "test set appends the include to an existing config once, after a backup" [] {
  let fake = fake-ghostty
  "font-size = 13\n" | save ($fake.config | path join config.ghostty)
  ghostty set { theme: Zenburned }
  ghostty set { font-size: 14 }
  let cfg = config-of $fake | lines
  assert equal ($cfg | where $it == "config-file = ?nushell-distro.ghostty" | length) 1
  assert equal ($cfg | first) "font-size = 13"
  assert equal (ls $fake.config | get name | path basename | where $it =~ '^config\.ghostty\.backup-' | length) 1
  let backup = ls $fake.config | get name | where {|f| ($f | path basename) =~ '^config\.ghostty\.backup-' } | first
  assert equal (open --raw $backup) "font-size = 13\n"
  # Ours wins over theirs: the fake settles the chain the way Ghostty does.
  assert equal (ghostty live font-size) "14"
}

def "test set rewrites our file whole, sorted, and a null drops a key" [] {
  let fake = fake-ghostty
  ghostty set { theme: Zenburned, command: /bin/nu }
  ghostty set { theme: null, font-size: 12 }
  assert equal (ghostty settings) { command: /bin/nu, font-size: "12" }
  let lines = ours-of $fake | lines | where {|l| ($l | is-not-empty) and not ($l | str starts-with "#") }
  assert equal $lines ["command = /bin/nu" "font-size = 12"]
}

def "test set writes a repeatable key as a reset line and the value" [] {
  let fake = fake-ghostty
  "font-family = Their Font\n" | save ($fake.config | path join config.ghostty)
  ghostty set { font-family: "Hack Nerd Font" }
  let lines = ours-of $fake | lines | where {|l| $l starts-with "font-family" }
  assert equal $lines ["font-family = " "font-family = Hack Nerd Font"]
  assert equal (ghostty settings | get font-family) "Hack Nerd Font"
  assert equal (ghostty live font-family) "Hack Nerd Font" "the reset line must clear theirs"
}

def "test set puts our file back when Ghostty rejects the configuration" [] {
  let fake = fake-ghostty
  ghostty set { theme: Zenburned }
  let before = ours-of $fake
  let err = try { ghostty set { theme: Nope }; null } catch {|e| $e.msg }
  assert equal $err "Ghostty rejected that configuration"
  assert equal (ours-of $fake) $before
  assert equal (ghostty settings) { theme: Zenburned }
}

def "test set removes our file when a first write is rejected" [] {
  let fake = fake-ghostty
  let err = try { ghostty set { theme: Nope }; null } catch {|e| $e.msg }
  assert equal $err "Ghostty rejected that configuration"
  assert not ($fake.config | path join nushell-distro.ghostty | path exists)
  assert equal (ghostty settings) {}
}

def "test set validates through Ghostty with the config it reads" [] {
  let fake = fake-ghostty
  ghostty set { theme: Zenburned }
  let calls = ghostty-calls $fake | where {|c| $c.0 == "+validate-config" }
  assert equal $calls [["+validate-config" $"--config-file=($fake.config | path join config.ghostty)"]]
}

def "test reset removes our file and the two lines, keeps the backup" [] {
  let fake = fake-ghostty
  "font-size = 13\n" | save ($fake.config | path join config.ghostty)
  ghostty set { theme: Zenburned }
  ghostty reset
  assert not ($fake.config | path join nushell-distro.ghostty | path exists)
  assert equal (config-of $fake) "font-size = 13\n"
  assert equal (ls $fake.config | get name | path basename | where $it =~ 'backup' | length) 1
  assert equal (ghostty status | get included) false
}

# ── live · status · shell · reload ────────────────────────────────────────────

def "test live reads the first value of a repeatable key and not its cousins" [] {
  let fake = fake-ghostty
  [
    "font-family-bold = Bold Font"
    "font-family = First Font"
    "font-family = Second Font"
    "theme = Zenburned"
  ] | str join "\n" | save ($fake.root | path join show-config)
  assert equal (ghostty live font-family) "First Font"
  assert equal (ghostty live font-family-bold) "Bold Font"
  assert equal (ghostty live theme) Zenburned
  assert equal (ghostty live command) null
}

def "test shell makes nu the command and --reset drops it" [] {
  let fake = fake-ghostty
  ghostty shell
  assert equal (ghostty settings | get command) (ghostty nu-path)
  assert equal (ghostty status | get shell) (ghostty nu-path)
  ghostty shell --reset
  assert equal (ghostty settings | get -o command) null
}

def "test reload asks Ghostty over AppleScript on macOS and is false elsewhere" [] {
  let fake = fake-ghostty
  if $nu.os-info.name != "macos" {
    assert equal (ghostty reload) false
    assert equal (ghostty-calls $fake | where {|c| $c.0 == "osascript" }) []
    return
  }
  assert equal (ghostty reload) true
  let call = ghostty-calls $fake | where {|c| $c.0 == "osascript" } | first
  assert ($call | str join " " | str contains "performAction('reload_config'") "the reload is the perform action"
  # By pid under a Ghostty shell (the suite run from one), by name elsewhere (CI).
  assert ($call | str join " " | str contains "Application(") $"the app is addressed by pid or name — ($call)"
  touch ($fake.root | path join reload-fails)
  assert equal (ghostty reload) false
}
