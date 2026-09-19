# Tab in a real terminal: the smart menu driven through tests/pty/harness.py
# (a pseudo-terminal, keys one at a time, the line read back from history),
# under the shipped defaults and again with `completions.partial = true`,
# where nushell main corrupts the line after a partial completion. The
# corruption is asserted per version, so the test documents the upstream bug
# rather than hiding it: 0.115.1 is clean, the 0.115.2 main build of
# 2026-09-19 (19bdc5f) is not, and a later release is expected clean again.
use lib.nu *
use std/assert

const HARNESS = ($ROOT | path join tests pty harness.py)

# Cases as data. `want` is the line as history records it (trailing space
# trimmed: the release appends none after a completed command, main does);
# `corrupt` is what the partial-completion bug makes of it; `screen` is
# what the menu must show for a case that only looks.
const CASES = [
  # The first two run in a shell that has not loaded the lazy terminal module
  # yet: the candidates come from a child nu (smart.nu, "Lazy modules"). The
  # Enter of the second is what loads it.
  { line: "fon", keys: "tab,esc,ctrl-c", screen: ["font dir" "font list" "font use"] }
  { line: "theme use catp", keys: "tab,tab,tab,tab,enter,enter", want: 'theme use "Catppuccin Macchiato"' }
  { line: "bits r", keys: "tab,tab,enter,enter", want: "bits ror", corrupt: "bits ror o" }
  { line: "git cher", keys: "tab,tab,enter,enter", want: "git cherry", corrupt: "git cherryry" }
  { line: "str tr", keys: "tab,enter,enter", want: "str trim" }
  { line: "git checkout ", keys: "tab,enter,enter", want: "git checkout feature" }
  { line: "ls | where ", keys: "tab,esc,ctrl-c", screen: [name type size modified] }
  { line: "echo done", keys: "enter", want: "echo done" }
]

def --env repo []: nothing -> string {
  let d = scratch
  cd $d
  let c = [-c user.name=test -c user.email=test@example.com]
  ^git init -q -b main
  # A file, so `ls | where ` has columns to offer.
  "hello\n" | save ($d | path join README.md)
  ^git add README.md
  ^git ...$c commit -q -m first
  ^git checkout -q -b feature
  ^git ...$c commit -q --allow-empty -m onfeature
  ^git checkout -q main
  $d
}

# One session over every case; returns { history, screens }.
def session [--partial]: nothing -> record {
  if $nu.os-info.name == "windows" { skip-test "no pty on Windows" }
  if (which python3 | is-empty) { skip-test "python3 is not installed" }
  if (which -a git | where type == external | is-empty) { skip-test "git is not installed" }
  let settings = ["const UPDATE_CHECK_EVERY = 0sec"] ++ (if $partial { ['$env.config.completions.partial = true'] } else { [] }) | str join "\n"
  let dir = user-dir --settings $settings
  let cwd = repo
  let args = $CASES | each {|c| ["--case" $"($c.line)|($c.keys)"] } | flatten
  let r = ^python3 $HARNESS --nu $nu.current-exe --config-home $dir.env.XDG_CONFIG_HOME --cwd $cwd ...$args | complete
  assert equal $r.exit_code 0 $r.stderr
  $r.stdout | from json
}

# The recorded lines, one per case that ran one, trailing space trimmed.
def recorded [got: record]: nothing -> list<record> {
  let ran = $CASES | where {|c| $c.keys | str ends-with enter }
  assert equal ($got.history | length) ($ran | length) ($got.history | to nuon)
  $ran | zip $got.history | each {|p| { case: $p.0, line: ($p.1 | str trim --right) } }
}

def "test the menu completes and inserts under the shipped defaults" [] {
  let got = session
  for r in (recorded $got | where {|r| $r.case.want? != null }) {
    assert equal $r.line $r.case.want $r.case.line
  }
  for looks in ($CASES | enumerate | where {|c| $c.item.screen? != null }) {
    let screen = $got.screens | get $looks.index
    for col in $looks.item.screen { assert ($screen | str contains $col) $"($col) not on screen: ($screen)" }
  }
}

def "test partial completion is clean on the release and corrupts the line on main" [] {
  let got = session --partial
  let v = (version).version
  for r in (recorded $got | where {|r| $r.case.want? != null }) {
    let expected = if $v == "0.115.2" and $r.case.corrupt? != null { $r.case.corrupt } else { $r.case.want }
    assert equal $r.line $expected $"($r.case.line) on ($v)"
  }
}
