#!/usr/bin/env nu
# tests/run.nu — the test runner.
#
#   nu tests/run.nu                every test
#   nu tests/run.nu completion     only files or tests whose name contains it
#   nu tests/run.nu --timing       ... and the ten slowest at the end
#
# A test file is tests/**/*.test.nu (fixtures/ excluded); a test is a
# `def "test <name>"` in it. Each FILE runs in a fresh `nu -n` with
# NU_LIB_DIRS pointing at this checkout — tests/ for lib.nu, then modules/,
# completions/ and themes/ — so a test sees the shipped modules the way a
# shell does and nothing the user's config sets. The tests are listed with
# `scope commands` after the file is sourced, so a test is whatever parses as
# one, and each runs inside a `try`: `std assert` makes the failure,
# `skip-test` (lib.nu) makes a skip, reaching the end is the pass. One line per test, a
# summary, exit 1 when anything failed.
#
# Budget: the whole suite under 30 s, so it is run before every commit.

const ROOT = path self | path dirname | path dirname
const TESTS = $ROOT | path join tests
const LIB_DIRS = [
  ($ROOT | path join tests)
  ($ROOT | path join modules)
  ($ROOT | path join completions)
  ($ROOT | path join themes)
]

def main [
  pattern?: string    # run only the tests whose file or name contains this
  --timing            # print the ten slowest tests
  --verbose (-v)      # print every file's output, not only a failing one's
  --dir: string       # the directory to search instead of tests/ (the harness's own test)
] {
  let tests = $dir | default $TESTS | path expand
  # Forward slashes: a backslash is an escape in a glob, so `path join` on
  # Windows would make a pattern that fails to parse.
  let files = glob (($tests | str replace -a '\\' '/') + "/**/*.test.nu") --exclude ["**/fixtures/**"] | sort
  let scratch = mktemp -d --tmpdir-path $nu.temp-dir "nu-tests.XXXXXX"
  # Every child shell gets XDG directories under the scratch, so $nu.data-dir,
  # $nu.cache-dir and the config dir are the run's own and a test that writes
  # a cache (completions/brew.nu) or a plugin registry cannot reach the real
  # ones. Nushell warns on stderr when that config directory is empty, and
  # `nu -n` reads nothing there, so a placeholder keeps the output clean.
  mkdir ($scratch | path join xdg config nushell) ($scratch | path join xdg data) ($scratch | path join xdg cache)
  "# nu -n reads no config; this keeps Nushell from warning that the directory is empty\n" | save ($scratch | path join xdg config nushell config.nu)
  let child_env = {
    TEST_SCRATCH: $scratch
    XDG_CONFIG_HOME: ($scratch | path join xdg config)
    XDG_DATA_HOME: ($scratch | path join xdg data)
    XDG_CACHE_HOME: ($scratch | path join xdg cache)
  }
  let started = date now

  let results = $files
    | each {|file| run-file $file $tests $pattern $child_env $verbose }
    | flatten
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

# Run one file: list its tests, run those matching the pattern, print a line
# for each. Returns the results as records {file, name, status, duration, ...}.
def run-file [file: string, tests: string, pattern: any, child_env: record, verbose: bool]: nothing -> list {
  let label = $file | path relative-to $tests | str replace -r '\.test\.nu$' ''
  let prelude = $"const NU_LIB_DIRS = ($LIB_DIRS | to nuon)\nsource ($file | to nuon)\n"

  # The list is the file's own word, not a regex over its text.
  let listed = with-env $child_env { ^$nu.current-exe -n -c $"($prelude)scope commands | where name starts-with 'test ' | get name | to nuon" | complete }
  if $listed.exit_code != 0 {
    print $"(ansi red)✗ ($label)(ansi reset)  the file did not load"
    print ($listed.stderr | indent)
    return [{ file: $label, name: "", status: fail, duration: 0sec }]
  }
  let names = $listed.stdout | from nuon
    | where {|n| $pattern == null or ($label =~ $pattern) or ($n =~ $pattern) }
  if ($names | is-empty) { return [] }
  # The name becomes a command call in the script below, so a quote in it
  # would open a string there — and pair with the next one, silently eating
  # the tests in between.
  let odd = $names | where {|n| $n !~ '^test [A-Za-z0-9 ._+/=:,-]+$' }
  if ($odd | is-not-empty) {
    print $"(ansi red)✗ ($label)(ansi reset)  a test name may hold letters, digits, spaces and ._+/=:,- only"
    print ($odd | str join "\n" | indent)
    return [{ file: $label, name: "", status: fail, duration: 0sec }]
  }

  # One `try` per test, generated: a command cannot be called by a name held
  # in a variable, so the script names each one. The verdict goes to a file,
  # leaving stdout to the tests.
  let out = $child_env.TEST_SCRATCH | path join $"($label | str replace -a '/' '_').nuon"
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

  let ran = with-env $child_env { ^$nu.current-exe -n -c $script | complete }
  if $ran.exit_code != 0 or not ($out | path exists) {
    print $"(ansi red)✗ ($label)(ansi reset)  the run did not finish"
    print ($ran.stdout + $ran.stderr | indent)
    return [{ file: $label, name: "", status: fail, duration: 0sec }]
  }

  let results = open $out | insert file $label
  let lost = $names | where {|n| $n not-in ($results | get name) }
  if ($lost | is-not-empty) {
    print $"(ansi red)✗ ($label)(ansi reset)  listed but never reported"
    print ($lost | str join "\n" | indent)
    return ($results | append ($lost | each {|n| { file: $label, name: $n, status: fail, duration: 0sec } }))
  }
  for r in $results {
    let short = $r.name | str substring 5..
    match $r.status {
      "pass" => { print $"  (ansi green)✓(ansi reset) ($label) · ($short)  (ansi dark_gray)($r.duration | format-duration)(ansi reset)" }
      "skip" => { print $"  (ansi yellow)-(ansi reset) ($label) · ($short)  (ansi dark_gray)skipped: ($r.reason)(ansi reset)" }
      "fail" => {
        print $"  (ansi red)✗ ($label) · ($short)(ansi reset)"
        print ($r.error | indent)
      }
    }
  }
  let output = $ran.stdout + $ran.stderr
  if ($output | str trim | is-not-empty) and ($verbose or ($results | any {|r| $r.status == fail })) {
    print $"(ansi dark_gray)── ($label) output ──(ansi reset)"
    print ($output | indent)
  }
  $results
}

def indent []: string -> string {
  $in | str trim --right | lines | each {|l| $"      ($l)" } | str join "\n"
}

def format-duration []: duration -> string {
  let d = $in
  if $d < 1sec { $"($d | into int | $in / 1_000_000 | math round --precision 1) ms" } else { $"($d | into int | $in / 1_000_000_000 | math round --precision 1) s" }
}
