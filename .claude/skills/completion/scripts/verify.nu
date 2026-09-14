#!/usr/bin/env nu
# verify.nu — does Tab answer the way the spec promised, and how fast
#
#   nu verify.nu <tool>                      auto cases: root, every subcommand, its flags
#   nu verify.nu <tool> --cases cases.nuon   your cases
#   nu verify.nu <tool> --oracle carapace    also list what carapace offers that we do not
#
# A case is { line: "gh pr ", has: [checkout list], not: [], no_files: true, min: 3, max_ms: 50 }:
# every field but `line` is optional. Lines are completed the way Tab does
# it, through `commandline complete --detailed` in a login shell (`nu -l`,
# the config loaded), all cases in one process so a 90 ms startup is paid
# once. Exit code 1 when any case fails. Timing is per line, first call
# (cold caches) unless --warm, which runs every line twice and reports the
# second.

def run-cases [cases: list<record>, warm: bool]: nothing -> list<record> {
  let code = $"
    let cases = ($cases | to nuon)
    $cases | each {|c|
      let first = \(timeit { $c.line | commandline complete --detailed | ignore })
      let second = \(timeit { $c.line | commandline complete --detailed | ignore })
      let items = \($c.line | commandline complete --detailed | select -o value kind description | default "" description)
      { line: $c.line, ms: \(\(if ($warm) { $second } else { $first }) | into int | $in / 1_000_000), items: $items }
    } | to json -r
  "
  let r = (^$nu.current-exe -l -c $code | complete)
  if $r.exit_code != 0 {
    if ($env.VERIFY_DEBUG? | default "") == "1" { print -e $code }
    error make { msg: $"completion run failed: ($r.stderr | lines | first 25 | str join (char nl))" }
  }
  $r.stdout | from json
}

def judge [c: record, r: record]: nothing -> record {
  let values = ($r.items | get value)
  let kinds = ($r.items | get kind | uniq)
  mut problems = []
  for h in ($c.has? | default []) { if $h not-in $values { $problems ++= [$"missing ($h)"] } }
  for n in ($c.not? | default []) { if $n in $values { $problems ++= [$"unwanted ($n)"] } }
  if ($c.no_files? | default false) and ("file" in $kinds or "directory" in $kinds) { $problems ++= ["files offered"] }
  if ($c.min? != null) and ($values | length) < $c.min { $problems ++= [$"only ($values | length) candidates, wanted ($c.min)"] }
  if ($c.max_ms? != null) and $r.ms > $c.max_ms { $problems ++= [$"($r.ms | math round) ms > ($c.max_ms)"] }
  { line: $c.line, n: ($values | length), kinds: ($kinds | str join ","), ms: ($r.ms | math round --precision 1), ok: ($problems | is-empty), problems: ($problems | str join "; "), sample: ($values | first 6 | str join " ") }
}

# Cases from what the root offers: every subcommand, then its flags.
def auto-cases [tool: string]: nothing -> list<record> {
  let root = (run-cases [{ line: $"($tool) " }] false | get 0.items)
  let subs = ($root | where kind not-in [file directory] | get value | where $it !~ '^-' | first 60)
  let per_sub = ($subs | each {|s| [{ line: $"($tool) ($s) -", min: 1, no_files: true } { line: $"($tool) ($s) " }] } | flatten)
  [{ line: $"($tool) ", min: 1, no_files: true }] ++ $per_sub
}

def oracle-diff [tool: string, cases: list<record>, results: list<record>]: nothing -> list<record> {
  if (which carapace | is-empty) { return [] }
  $cases | each {|c|
    let spans = ($c.line | split row " ")
    let ours = ($results | where line == $c.line | get -o 0.items | default [] | get value)
    let theirs = (do -i { ^carapace $tool nushell ...$spans | from json | get value } | default [])
    let missing = ($theirs | where $it not-in $ours | where $it !~ '^-.*ERR$')
    { line: $c.line, ours: ($ours | length), carapace: ($theirs | length), carapace_only: ($missing | first 12 | str join " "), n_carapace_only: ($missing | length) }
  }
}

export def main [
  tool: string
  --cases: path          # a nuon/json list of cases; default: auto
  --oracle: string       # "carapace": report candidates carapace has that we lack
  --warm                 # report the second call's time
  --json
]: nothing -> nothing {
  let cases = (if $cases != null { open $cases } else { auto-cases $tool })
  let results = (run-cases $cases $warm)
  let table = ($cases | each {|c| judge $c ($results | where line == $c.line | first) })
  if $json { print ($table | to json) } else {
    for r in $table {
      let mark = (if $r.ok { $"(ansi green)ok  (ansi reset)" } else { $"(ansi red)FAIL(ansi reset)" })
      print $"($mark) ($r.ms | fill --alignment right --width 7) ms  ($r.n | fill --alignment right --width 5)  ($r.kinds | fill --width 16)  ($r.line | fill --width 32)  (if $r.ok { $r.sample | str substring 0..60 } else { $r.problems })"
    }
  }
  if $oracle == "carapace" {
    let d = (oracle-diff $tool $cases $results)
    print $"(ansi cyan_bold)carapace has, we do not(ansi reset)"
    for r in ($d | where n_carapace_only > 0) { print $"  ($r.line | fill --width 32) ours ($r.ours | fill --width 5) carapace ($r.carapace | fill --width 5) only there: ($r.n_carapace_only)  ($r.carapace_only | str substring 0..70)" }
  }
  let failed = ($table | where not ok | length)
  print $"(if $failed == 0 { ansi green } else { ansi red })($table | length) cases, ($failed) failed, ($table | get ms | math max) ms worst(ansi reset)"
  if $failed > 0 { exit 1 }
}
