# The Tab menu source (modules/nu-complete/smart.nu), called the way the menu
# calls it: `nu-complete smart <line> <cursor>`. No terminal needed. The
# pipeline probe runs `nu -n -c` in a subprocess with the test's $env.PWD;
# `commandline complete` itself lists files from the process's working
# directory, which a `cd` in a test does not move, so the `cd` fallback runs
# in a child shell started in the empty directory.
use lib.nu *
use std/assert
use nu-complete *

def smart [line: string]: nothing -> list<record> {
  nu-complete smart $line ($line | str length)
}

def kinds [line: string]: nothing -> list<string> {
  smart $line | get kind? | compact | uniq | sort
}

def "test a condition slot offers the columns of the pipeline" [] {
  let got = smart "ls | where "
  assert ([name type size modified] | all {|c| $c in ($got | get value) }) ($got | get value | to nuon)
  assert ($got | where value == size | get 0.description | str starts-with "filesize") "the type is in the description"
}

def "test a column is followed by the operators for its type" [] {
  assert equal (smart "ls | where size " | get value | sort) ["!=" "<" "<=" "==" ">" ">=" in not-in]
  let s = smart "ls | where name " | get value
  assert ("starts-with" in $s and "=~" in $s and "<" not-in $s) ($s | to nuon)
}

def "test an operator is followed by the distinct values of the column" [] {
  assert equal (smart "ls | where type == " | get value | sort) [dir file]
  assert equal (smart "ls | where type == d" | get value) [dir]
}

def "test after and or or the columns come back" [] {
  assert ("name" in (smart "ls | where type == dir and " | get value))
}

def "test a cell-path slot offers columns, nested paths and closure fields" [] {
  let d = scratch
  { package: { name: alpha, version: "1.0" }, deps: [] } | save ($d | path join data.json)
  cd $d
  assert equal (smart "ls | get na" | get value) [name]
  assert equal (smart "ls | select name " | get value) [type size modified]
  assert equal (smart "ls | each {|r| $r.si" | get value) [size]
  assert equal (smart "open data.json | get package." | get value | sort) [name version]
}

def "test a command with no positional stops offering files" [] {
  assert equal (kinds "ps ") []
  assert ("file" in (kinds "ls "))
}

def "test a number slot stops offering files, before a pipe too" [] {
  assert equal (kinds "first ") []
  assert equal (kinds "sleep ") []
  assert equal (kinds "ls | first ") []
}

def "test a flag slot and a flag value keep the Nushell answer" [] {
  assert equal (smart "cd --" | get value) [--help --physical]
}

def "test the probe never runs a command that writes" [] {
  let d = scratch
  let line = $"[1] | save ($d)/marker | where "
  let got = smart $line
  assert ("marker" not-in (ls $d | get name | path basename)) "save ran"
  assert ($got | all {|r| $r.kind? != null }) "no invented columns"
}

# What Nushell itself offers after `where ` differs between releases (files
# on 0.115.2, nothing on 0.115.1), so these assert that no column was
# invented — every item is Nushell's own, with a kind — not what was.
def "test an external at the head is never run" [] {
  let got = smart "^ls | where "
  assert ($got | all {|r| $r.kind? != null }) ($got | to nuon)
}

def "test NU_COMPLETE_EVAL off leaves the line alone" [] {
  $env.NU_COMPLETE_EVAL = "off"
  let got = smart "ls | where "
  assert ($got | all {|r| $r.kind? != null }) ($got | to nuon)
}

def "test no candidate is listed twice" [] {
  let got = smart "ls | where "
  assert equal ($got | get value | length) ($got | get value | uniq | length)
  let base = smart "l"
  assert equal ($base | get value | length) ($base | get value | uniq | length)
}

def "test cd in a folder with nothing to enter offers parents and places" [] {
  let d = scratch
  cd $d
  let code = $"const NU_LIB_DIRS = [($ROOT | path join modules | to nuon)]; use nu-complete *; nu-complete smart 'cd ' 3 | select value description | to nuon"
  let out = ^$nu.current-exe -n -c $code | complete
  assert equal $out.exit_code 0 $out.stderr
  let got = $out.stdout | from nuon
  assert equal ($got | first 3 | get value) [".." "~" "-"]
  assert equal ($got | first 3 | get description) [parent home "previous directory"]
}
