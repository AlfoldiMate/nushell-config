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
  let stem = $env.TEST_NAME? | default "test" | str replace -a " " "-"
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

# Stop this test with a reason instead of a verdict; run.nu counts it apart
# from the failures. For a test that only makes sense with a tool installed
# or on one platform, which says so rather than passing vacuously.
export def skip [reason: string] {
  error make -u { msg: $"skip: ($reason)" }
}
