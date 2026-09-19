#!/usr/bin/env nu
# tests/run.nu — the test runner.
#
#   nu tests/run.nu                every test
#   nu tests/run.nu completion     only files or tests whose name contains it
#   nu tests/run.nu --timing       ... and the ten slowest at the end
#   nu tests/run.nu --serial       one file at a time, in order
#
# A test file is tests/**/*.test.nu (fixtures/ excluded); a test is a
# `def "test <name>"` in it. Each FILE runs in a fresh `nu -n` with
# NU_LIB_DIRS pointing at this checkout — modules/, completions/, themes/,
# then tests/ for lib.nu — so a test sees the shipped modules the way a
# shell does and nothing the user's config sets. The tests are listed with
# `scope commands` after the file is sourced, so a test is whatever parses as
# one, and each runs inside a `try`: `std assert` makes the failure,
# `skip-test` (lib.nu) makes a skip, reaching the end is the pass. One line
# per test, a summary, exit 1 when anything failed.
#
# Files run concurrently (`par-each`), each in a sandbox of its own — HOME
# and the XDG directories under the run's scratch — so two files cannot see
# each other's state, and a file's lines print together once it is done.
# 135 tests: 20 s serial, 7 s concurrent on an M-series Mac (2026-09-19).
# Budget: the whole suite under 30 s, so it is run before every commit.

const ROOT = path self | path dirname | path dirname
const TESTS = $ROOT | path join tests
# tests/ last: a directory of tests named after a module (tests/terminal/)
# would otherwise shadow the module for `use terminal *`.
const LIB_DIRS = [
  ($ROOT | path join modules)
  ($ROOT | path join completions)
  ($ROOT | path join themes)
  ($ROOT | path join tests)
]

def main [
  pattern?: string    # run only the tests whose file or name contains this
  --timing            # print the ten slowest tests
  --verbose (-v)      # print every file's output, not only a failing one's
  --serial            # one file at a time, in order
  --dir: string       # the directory to search instead of tests/ (the harness's own test)
] {
  # Forward slashes throughout: a backslash is an escape in a glob, so the
  # pattern `path join` makes on Windows fails to parse, and `glob` answers
  # with forward slashes, which `path relative-to` then has to match.
  let tests = $dir | default $TESTS | path expand | str replace -a '\' '/'
  let files = glob ($tests + "/**/*.test.nu") --exclude ["**/fixtures/**"] | sort
  let scratch = mktemp -d --tmpdir-path $nu.temp-dir "nu-tests.XXXXXX"
  let started = date now

  let results = if $serial {
    $files | each {|file| run-file $file $tests $pattern $scratch $verbose }
  } else {
    $files | par-each {|file| run-file $file $tests $pattern $scratch $verbose }
  } | flatten | sort-by file name
  let elapsed = (date now) - $started
  rm -rf $scratch

  let count = {|s| $results | where status == $s | length }
  let passed = do $count pass
  let failed = do $count fail
  let skipped = do $count skip
  let colour = if $failed > 0 { ansi red } else { ansi green }
  print $"\n($colour)($passed) passed, ($failed) failed, ($skipped) skipped(ansi reset)  ·  ($elapsed | format-duration)"

  if $timing {
    print ""
    $results
      | where status != skip
      | sort-by duration --reverse
      | first 10
      | select duration file name
      | update name {|r| $r.name | str substring 5.. }
      | update duration {|r| $r.duration | format-duration }
      | print
  }

  if $failed > 0 { exit 1 }
}

# The environment a file's shells run in: a sandbox of its own under the
# run's scratch. XDG directories, so $nu.data-dir, $nu.cache-dir and the
# config dir are the file's and a test that writes a cache (completions/
# brew.nu), a plugin registry or a theme's state cannot reach the real ones
# or another file's; Nushell warns on stderr when the config directory is
# empty and `nu -n` reads nothing there, so a placeholder keeps the output
# clean. HOME too, off Windows (where $nu.home-dir does not follow it): on
# macOS the terminal module reads ~/Library/Application Support and writes
# ~/Library/Fonts, and a test must never find the user's own. rustup's cargo
# is a proxy that finds the toolchain through the home directory, so the real
# one stays reachable and a cargo test is not skipped.
def sandbox [scratch: string, label: string]: nothing -> record {
  let box = $scratch | path join ($label | str replace -ra '[/\\]' '_')
  mkdir ($box | path join xdg config nushell) ($box | path join xdg data) ($box | path join xdg cache) ($box | path join home)
  "# nu -n reads no config; this keeps Nushell from warning that the directory is empty\n" | save ($box | path join xdg config nushell config.nu)
  {
    TEST_SCRATCH: $box
    XDG_CONFIG_HOME: ($box | path join xdg config)
    XDG_DATA_HOME: ($box | path join xdg data)
    XDG_CACHE_HOME: ($box | path join xdg cache)
  }
  | merge (if $nu.os-info.name == "windows" { {} } else { { HOME: ($box | path join home) } })
  | merge ({ CARGO_HOME: ($nu.home-dir | path join .cargo), RUSTUP_HOME: ($nu.home-dir | path join .rustup) }
      | transpose k v | where {|r| ($env | get -o $r.k) == null and ($r.v | path exists) }
      | reduce -f {} {|r, acc| $acc | insert $r.k $r.v })
}

# Run one file: list its tests, run those matching the pattern, print its
# lines together. Returns the results as records {file, name, status, duration, ...}.
def run-file [file: string, tests: string, pattern: any, scratch: string, verbose: bool]: nothing -> list {
  let label = $file | path relative-to $tests | str replace -r '\.test\.nu$' ''
  let box = sandbox $scratch $label
  let prelude = $"const NU_LIB_DIRS = ($LIB_DIRS | to nuon)\nsource ($file | to nuon)\n"
  let failed = {|why, detail| print ([$"(ansi red)✗ ($label)(ansi reset)  ($why)" ($detail | indent)] | str join "\n"); [{ file: $label, name: "", status: fail, duration: 0sec }] }

  # The list is the file's own word, not a regex over its text.
  let listed = with-env $box { ^$nu.current-exe -n -c $"($prelude)scope commands | where name starts-with 'test ' | get name | to nuon" | complete }
  if $listed.exit_code != 0 { return (do $failed "the file did not load" $listed.stderr) }
  let names = $listed.stdout | from nuon
    | where {|n| $pattern == null or ($label =~ $pattern) or ($n =~ $pattern) }
  if ($names | is-empty) { return [] }
  # The name becomes a command call in the script below, so a quote in it
  # would open a string there — and pair with the next one, silently eating
  # the tests in between.
  let odd = $names | where {|n| $n !~ '^test [A-Za-z0-9 ._+/=:,-]+$' }
  if ($odd | is-not-empty) { return (do $failed "a test name may hold letters, digits, spaces and ._+/=:,- only" ($odd | str join "\n")) }

  # One `try` per test, generated: a command cannot be called by a name held
  # in a variable, so the script names each one. The verdict goes to a file,
  # leaving stdout to the tests.
  let out = $box.TEST_SCRATCH | path join verdicts.nuon
  let steps = $names | each {|name|
    let n = $name | to nuon
    [
      $"$env.TEST_NAME = ($n)"
      "let t0 = date now"
      $"let r = try { ($name) | ignore; { status: pass } } catch {|e| __verdict $e }"
      $"$results = \($results | append \($r | merge { name: ($n), duration: \(\(date now\) - $t0\) }\)\)"
    ] | str join "\n"
  } | str join "\n"
  let script = [
    $prelude
    'def __verdict [e: record]: nothing -> record {'
    '  if ($e.msg | str starts-with "skip: ") { { status: skip, reason: ($e.msg | str substring 6..) } } else { { status: fail, error: $e.rendered } }'
    '}'
    "mut results = []"
    $steps
    $"$results | to nuon | save -f ($out | to nuon)"
  ] | str join "\n"

  let ran = with-env $box { ^$nu.current-exe -n -c $script | complete }
  if $ran.exit_code != 0 or not ($out | path exists) { return (do $failed "the run did not finish" ($ran.stdout + $ran.stderr)) }

  let reported = open $out | insert file $label
  let lost = $names | where {|n| $n not-in ($reported | get name) }
  let results = $reported | append ($lost | each {|n| { file: $label, name: $n, status: fail, duration: 0sec } })
  let lines = (
    (if ($lost | is-empty) { [] } else { [$"(ansi red)✗ ($label)(ansi reset)  listed but never reported" ($lost | str join "\n" | indent)] })
    ++ ($reported | each {|r|
      let short = $r.name | str substring 5..
      match $r.status {
        "pass" => [$"  (ansi green)✓(ansi reset) ($label) · ($short)  (ansi dark_gray)($r.duration | format-duration)(ansi reset)"]
        "skip" => [$"  (ansi yellow)-(ansi reset) ($label) · ($short)  (ansi dark_gray)skipped: ($r.reason)(ansi reset)"]
        "fail" => [$"  (ansi red)✗ ($label) · ($short)(ansi reset)" ($r.error | indent)]
      }
    } | flatten)
  )
  let output = $ran.stdout + $ran.stderr
  let tail = if ($output | str trim | is-not-empty) and ($verbose or ($results | any {|r| $r.status == fail })) {
    [$"(ansi dark_gray)── ($label) output ──(ansi reset)" ($output | indent)]
  } else { [] }
  print ($lines ++ $tail | str join "\n")
  $results
}

def indent []: string -> string {
  $in | str trim --right | lines | each {|l| $"      ($l)" } | str join "\n"
}

def format-duration []: duration -> string {
  let d = $in
  if $d < 1sec { $"($d | into int | $in / 1_000_000 | math round --precision 1) ms" } else { $"($d | into int | $in / 1_000_000_000 | math round --precision 1) s" }
}
