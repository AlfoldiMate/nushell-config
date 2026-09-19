# The harness tested with itself: the runner's verdicts, and the isolation
# lib.nu promises. Everything else in tests/ relies on both.
use lib.nu *
use std/assert

def "test the runner reports each verdict and exits 1" [] {
  let ran = ^$nu.current-exe ($ROOT | path join tests run.nu) --dir ($ROOT | path join tests fixtures harness) | complete
  assert equal $ran.exit_code 1
  let plain = $ran.stdout | ansi strip
  assert ($plain | str contains "2 passed, 1 failed, 1 skipped") $plain
  assert ($plain | str contains "✗ sample · fails")
  assert ($plain | str contains "skipped: no reason at all")
}

def "test the runner takes a pattern" [] {
  let ran = ^$nu.current-exe ($ROOT | path join tests run.nu) skips --dir ($ROOT | path join tests fixtures harness) | complete
  assert equal $ran.exit_code 0
  assert ($ran.stdout | ansi strip | str contains "0 passed, 0 failed, 1 skipped")
}

def "test the runner refuses a test name a script could not call" [] {
  let ran = ^$nu.current-exe ($ROOT | path join tests run.nu) --dir ($ROOT | path join tests fixtures harness-names) | complete
  assert equal $ran.exit_code 1
  let plain = $ran.stdout | ansi strip
  assert ($plain | str contains "a test name may hold") $plain
  assert ($plain | str contains "test the run's root")
}

def "test scratch directories are fresh and under the run root" [] {
  let a = scratch
  let b = scratch
  assert not equal $a $b
  assert ($a | str starts-with $env.TEST_SCRATCH)
  assert ($a | path basename | str starts-with "test-scratch-directories")
}

def "test a user directory keeps the shell state to itself" [] {
  let dir = user-dir
  let ran = nu-l $dir 'print ({ config: $nu.config-path, data: $nu.data-dir, history: $nu.history-path, plugins: $nu.plugin-path, autoload: $nu.user-autoload-dirs, distro: (which "nu-config doctor" | is-not-empty) } | to nuon)'
  assert equal $ran.exit_code 0 $ran.stderr
  let seen = $ran.stdout | from nuon
  for p in [config data history plugins] {
    assert ($seen | get $p | str starts-with $dir.root) $"($p) is ($seen | get $p)"
  }
  assert ($seen.autoload | all {|d| $d | str starts-with $dir.root })
  assert $seen.distro "the distro did not load"
}

def "test settings.nu of a user directory is what the shell reads" [] {
  let dir = user-dir --settings '$env.NU_TEST_MARK = "from settings.nu"'
  let ran = nu-l $dir 'print $env.NU_TEST_MARK'
  assert equal $ran.exit_code 0 $ran.stderr
  assert equal ($ran.stdout | str trim) "from settings.nu"
}
