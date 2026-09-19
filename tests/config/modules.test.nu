# `nu-config module list | info | check | lint | enable | disable` against a
# user directory holding a module of its own that keeps the contract and one
# that breaks it every way lint knows (docs/concepts/modules.md).
use lib.nu *
use std/assert

# A user directory with modules/good (the contract) and modules/broken.
def modules-dir [--settings: string]: nothing -> record {
  let dir = if $settings == null { user-dir } else { user-dir --settings $settings }
  let good = $dir.config | path join modules good
  let broken = $dir.config | path join modules broken
  mkdir $good $broken
  'export def "good hello" [] { "hi" }
export def --env "good activate" [] { $env.GOOD_ON = ($env.GOOD_ON? | default true) }
' | save ($good | path join mod.nu)
  "use good *\ngood activate\n" | save ($good | path join load.nu)
  '{ description: "a module that keeps the contract", docs: "README.md", cost: 1ms, lazy: false, knobs: { GOOD_ON: { default: "true", about: "on or off" } } }' | save ($good | path join meta.nuon)
  "# good\n" | save ($good | path join README.md)
  "export def [ oops\n" | save ($broken | path join mod.nu)
  "use broken *\n" | save ($broken | path join load.nu)
  '{ description: "", cost: 0ns, requires: [{ bin: "nope" }] }' | save ($broken | path join meta.nuon)
  $dir
}

def "test module list shows yours beside the shipped ones" [] {
  let dir = modules-dir
  let ran = nu-l $dir 'nu-config module list | select module from enabled lazy | to nuon'
  assert equal $ran.exit_code 0 $ran.stderr
  let rows = $ran.stdout | from nuon
  assert equal ($rows | where from == yours | get module | sort) [broken good]
  assert equal ($rows | where module == nu-config | get 0 | select enabled lazy) { enabled: true, lazy: false }
  assert equal ($rows | where module == odata | get 0 | select enabled lazy) { enabled: true, lazy: true }
  assert equal ($rows | where module == good | get 0.enabled) false "not in MODULES, so not enabled"
}

def "test module info reads meta.nuon and finds the README beside a module of yours" [] {
  let dir = modules-dir
  let ran = nu-l $dir 'nu-config module info good | to nuon'
  assert equal $ran.exit_code 0 $ran.stderr
  let info = $ran.stdout | from nuon
  assert equal ($info | select module from description lazy cost) { module: good, from: yours, description: "a module that keeps the contract", lazy: false, cost: 1ms }
  assert equal $info.docs ($dir.config | path join modules good README.md)
  assert equal ($info.knobs | columns) [GOOD_ON]
  let shipped = nu-l $dir 'nu-config module info terminal | get docs'
  assert equal ($shipped.stdout | str trim) ($ROOT | path join docs reference modules terminal.md)
}

def "test module info of a missing module is an error" [] {
  let dir = modules-dir
  let ran = nu-l $dir 'nu-config module info nothing'
  assert equal $ran.exit_code 1
  assert ($ran.stderr | str contains "no module named 'nothing'") $ran.stderr
}

def "test module lint names every break of the contract and nothing else" [] {
  let dir = modules-dir
  let ran = nu-l $dir 'nu-config module lint | to nuon'
  assert equal $ran.exit_code 0 $ran.stderr
  let problems = $ran.stdout | from nuon
  assert equal ($problems | where module != broken) [] "the shipped modules and `good` are clean"
  assert equal ($problems | where module == broken | get problem) [
    "meta.nuon has no description"
    "meta.nuon has no measured cost"
    "meta.nuon has no docs"
    "load.nu does not parse — the module would fail on first use"
    "requires nope has no why"
  ]
}

def "test module check reports a dependency that is missing" [] {
  let dir = modules-dir
  let ran = nu-l $dir 'nu-config module check broken'
  assert equal $ran.exit_code 0 $ran.stderr
  assert ($ran.stdout | ansi strip | str contains "!! nope") $ran.stdout
}

def "test the knobs of a module of yours are listed with it as owner" [] {
  let dir = modules-dir
  let ran = nu-l $dir 'nu-config knobs | where owner == good | select knob about | to nuon'
  assert equal ($ran.stdout | from nuon) [{ knob: GOOD_ON, about: "on or off" }]
}

def "test a module of yours is wired by a use in settings.nu" [] {
  let dir = modules-dir --settings "use good *\ngood activate"
  let ran = nu-l $dir 'print (good hello) $env.GOOD_ON'
  assert equal $ran.exit_code 0 $ran.stderr
  assert equal ($ran.stdout | lines) [hi "true"]
}

# ── enable · disable ──────────────────────────────────────────────────────────

def "test module disable and enable edit one line of settings.nu each" [] {
  let dir = user-dir
  let off = nu-l $dir 'nu-config module disable odata'
  assert equal $off.exit_code 0 $off.stderr
  let settings = open --raw ($dir.config | path join settings.nu) | lines | where {|l| $l =~ '^const MODULES' }
  assert equal $settings ["const MODULES = [nu-config nu-complete terminal agent]"]
  let after = nu-l $dir 'nu-config module list | where module == odata | get 0.enabled'
  assert equal ($after.stdout | str trim) "false"

  let on = nu-l $dir 'nu-config module enable odata --eager'
  assert equal $on.exit_code 0 $on.stderr
  assert ($on.stdout | ansi strip | str contains "no dependencies") $on.stdout
  let lines = open --raw ($dir.config | path join settings.nu) | lines | where {|l| $l =~ '^const MODULES' }
  assert equal $lines ["const MODULES = [nu-config nu-complete terminal agent odata]" "const MODULES_LAZY = [terminal agent]"]
  let back = nu-l $dir 'nu-config module list | where module == odata | get 0 | select enabled lazy loaded | to nuon'
  assert equal ($back.stdout | from nuon) { enabled: true, lazy: false, loaded: true }
  let overridden = nu-l $dir 'nu-config knobs --overridden | get knob | to nuon'
  assert equal ($overridden.stdout | from nuon) [MODULES MODULES_LAZY]
}

def "test nu-config cannot be disabled" [] {
  let dir = user-dir
  let ran = nu-l $dir 'nu-config module disable nu-config'
  assert equal $ran.exit_code 1
  assert ($ran.stderr | str contains "no way back") $ran.stderr
  assert not ($dir.config | path join settings.nu | path exists) "nothing was written"
}
