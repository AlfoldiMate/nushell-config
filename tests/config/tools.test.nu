# `nu-config tools setup | status | remove`: the init files generated for
# installed tools land in the vendor autoload dir of the user directory
# under test, parse, and are removed again for a tool that is gone. Which
# tools exist is the machine's business: the generators run only for what
# is on PATH, and a runner with none of them still checks that nothing is
# written.
use lib.nu *
use std/assert

def "test setup writes a parsing file per installed tool and nothing else" [] {
  let dir = user-dir
  let ran = nu-l $dir 'nu-config tools setup; nu-config tools status | to nuon'
  assert equal $ran.exit_code 0 $ran.stderr
  let status = $ran.stdout | lines | last | from nuon
  let vendor = $dir.data | path join vendor autoload
  let files = if ($vendor | path exists) { ls $vendor | get name | path basename | sort } else { [] }
  assert equal $files ($status | where installed | get tool | each {|t| $"($t).nu" } | sort)
  assert ($status | all {|t| $t.state in [ok "not installed"] }) ($status | to nuon)
  for f in $files {
    let check = nu-l $dir $"nu-check ($vendor | path join $f | to nuon)"
    assert equal ($check.stdout | str trim) "true" $"($f) does not parse"
  }
}

def "test the generated files are what a shell loads after config.nu" [] {
  let dir = user-dir
  let ran = nu-l $dir 'print (nu-config tools dir) ($nu.vendor-autoload-dirs | last)'
  assert equal $ran.exit_code 0 $ran.stderr
  let lines = $ran.stdout | lines
  assert equal ($lines | first) ($lines | last) "tools dir is the last vendor autoload dir"
  assert ($lines | first | str starts-with $dir.data) "under the user directory's data dir"
}

def "test a second setup changes nothing and remove takes one file out" [] {
  let dir = user-dir
  nu-l $dir 'nu-config tools setup' | ignore
  let again = nu-l $dir 'nu-config tools setup'
  assert equal $again.exit_code 0 $again.stderr
  let out = $again.stdout | ansi strip
  assert not ($out | str contains "created") $out
  assert not ($out | str contains "file(s) changed") $out
  let installed = nu-l $dir 'nu-config tools status | where installed | get tool | to nuon' | get stdout | from nuon
  if ($installed | is-empty) { skip-test "no tool with an init file is installed here" }
  let tool = $installed | first
  let removed = nu-l $dir $"nu-config tools remove ($tool); nu-config tools status | where tool == ($tool) | get 0.state"
  assert ($removed.stdout | str contains "missing: run `nu-config tools setup`") $removed.stdout
  assert not ($dir.data | path join vendor autoload $"($tool).nu" | path exists)
}

def "test the carapace file rewraps the completer for both input shapes" [] {
  let dir = user-dir
  if (which -a carapace | where type == external | is-empty) { skip-test "carapace is not installed" }
  nu-l $dir 'nu-config tools setup --quiet' | ignore
  let f = $dir.data | path join vendor autoload carapace.nu
  let text = open --raw $f
  assert ($text | str contains "nu-complete spans $token (try { $place }) (try { $buffer })") "the unified-inputs wrapper"
  assert ($text | str contains "CARAPACE_BRIDGES") "the bridges"
}
