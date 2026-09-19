# tests/lib.nu — what a test needs and the checkout does not provide.
#
# `use lib.nu *` at the top of a test file: run.nu puts tests/ on NU_LIB_DIRS
# next to the checkout's modules/, completions/ and themes/, so a test imports
# a shipped module the way a shell does (`use nu-complete`, `use git.nu *`).

# The checkout under test.
export const ROOT = path self | path dirname | path dirname

# A fresh directory for this test. run.nu names the run's scratch root in
# TEST_SCRATCH and deletes it at the end, so nothing a test writes outlives
# the run or lands anywhere else; TEST_NAME is in the name so a leftover from
# a crashed run says which test it was.
export def scratch []: nothing -> string {
  let root = $env.TEST_SCRATCH? | default $nu.temp-dir
  # Letters, digits, `._-` only: a comma or a bracket from a test name would
  # break a `glob` over the directory.
  let stem = $env.TEST_NAME? | default "test" | str replace -ra '[^A-Za-z0-9._-]+' '-' 
  mktemp -d --tmpdir-path $root $"($stem).XXXXXX"
}

# A user directory of the test's own: a config.nu that sources this checkout's
# distro.nu, under an XDG_CONFIG_HOME and XDG_DATA_HOME of its own, so the
# shell it starts has its own settings.nu, autoload/, history, plugin registry
# and .state and never touches the user's. `nu -l --config <file>` would not
# do: Nushell derives $nu.data-dir and the autoload dirs from its config
# directory, not from the file --config names, so those would stay the user's.
export def user-dir [
  --settings: string  # the body of settings.nu, when the test needs overrides
]: nothing -> record {
  let root = scratch
  let config = $root | path join config nushell
  let data = $root | path join data nushell
  mkdir $config $data
  $"const DISTRO = ($ROOT | to nuon)\nsource \($DISTRO | path join distro.nu\)\n"
    | save ($config | path join config.nu)
  if $settings != null { $settings | save ($config | path join settings.nu) }
  {
    root: $root
    config: $config
    data: $data
    env: {
      XDG_CONFIG_HOME: ($root | path join config)
      XDG_DATA_HOME: ($root | path join data)
    }
  }
}

# Run a login shell against a directory from `user-dir` and return what
# `complete` returns: stdout, stderr and the exit code, separately. `-l`
# because `nu -c` loads no config at all and would prove nothing.
export def nu-l [dir: record, code: string]: nothing -> record {
  with-env $dir.env { ^$nu.current-exe -l -c $code | complete }
}

# A ghostty that answers from files (tests/fixtures/ghostty/fake.nu), first
# on PATH for the rest of the test, with a Ghostty config directory of its own
# (XDG_CONFIG_HOME) so `ghostty set` writes there. The fake osascript beside
# it answers `ghostty reload` (JXA given with `-e`) and hands the icon
# rasterizer (`-l JavaScript <file>`) to the real one. Returns where things
# are; `log` holds every call.
export def --env fake-ghostty []: nothing -> record {
  if $nu.os-info.name == "windows" { skip-test "no Ghostty on Windows" }
  let root = scratch
  let bin = $root | path join bin
  let fixtures = $ROOT | path join tests fixtures ghostty
  mkdir $bin ($root | path join share ghostty) ($root | path join config ghostty) ($root | path join config nushell)
  # The fake is a nu script: without this Nushell warns that the directory is empty.
  "# placeholder\n" | save ($root | path join config nushell config.nu)
  cp -r ($fixtures | path join themes) ($root | path join share ghostty)
  let fake = $fixtures | path join fake.nu
  $"#!/bin/sh
exec ($nu.current-exe | to nuon) ($fake | to nuon) "$@"
" | save ($bin | path join ghostty)
  $"#!/bin/sh
if [ "$1" = -l ] && [ "$3" != -e ]; then exec /usr/bin/osascript "$@"; fi
exec ($nu.current-exe | to nuon) ($fake | to nuon) osascript "$@"
" | save ($bin | path join osascript)
  ^chmod +x ($bin | path join ghostty) ($bin | path join osascript)
  $env.PATH = ($env.PATH | prepend $bin)
  $env.GHOSTTY_FAKE = $root
  $env.XDG_CONFIG_HOME = ($root | path join config)
  # On macOS the module also reads ~/Library/Application Support, and the
  # fake finds a font by its files in ~/Library/Fonts (~/.local/share/fonts
  # elsewhere) — both under the run's fake home, which the file's tests
  # share: a test that wrote there must not leak into the next.
  if ($nu.home-dir | str starts-with ($env.TEST_SCRATCH? | default "/nowhere")) {
    for d in [
      ($nu.home-dir | path join Library "Application Support" com.mitchellh.ghostty)
      ($nu.home-dir | path join Library Fonts)
      ($nu.home-dir | path join .local share fonts)
    ] { if ($d | path exists) { rm -rf $d } }
  }
  {
    root: $root
    bin: $bin
    log: ($root | path join log)
    config: ($root | path join config ghostty)
    themes: ($root | path join share ghostty themes)
  }
}

# The calls the fake ghostty has answered so far, as argument lists.
export def ghostty-calls [fake: record]: nothing -> list<list<string>> {
  if ($fake.log | path exists) { open --raw $fake.log | lines | each {|l| $l | from nuon } } else { [] }
}

# Stop this test with a reason instead of a verdict; run.nu counts it apart
# from the failures. For a test that only makes sense with a tool installed
# or on one platform, which says so rather than passing vacuously. Not
# `skip`: a module `use`d after this file resolves names against the scope
# it is parsed in, and the engine's `skip $n` became this command.
export def skip-test [reason: string] {
  error make -u { msg: $"skip: ($reason)" }
}
