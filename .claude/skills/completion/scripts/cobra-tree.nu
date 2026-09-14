#!/usr/bin/env nu
# cobra-tree.nu — the command tree of a cobra CLI through its `__complete` hook
#
#   nu cobra-tree.nu <tool> [--depth 4] [--max 200] [--no-values] [--json]
#
# Every cobra program (gh, kubectl, docker, helm, hugo …) answers
# `<tool> __complete <args…> ""` with `value<TAB>description` lines and a
# final `:N` directive (4 = no file completion, 0 = default, 1 = error).
# That is what its shipped zsh/fish files call at runtime, so it is the
# only complete source for cobra tools: subcommands including hidden ones,
# flags (`__complete sub --`), the values of an enum flag
# (`__complete sub --state ""`), and whether a positional is dynamic
# (`__complete sub ""` on a leaf returns live candidates, or nothing with
# `:0` when it wants files or has nothing to say).
#
# Which entries of a listing are subcommands rather than positional values
# is decided with the help text (a Commands section), parsed by help-tree.nu.
# Flag types (string, int, path) come from help too: `__complete` has none.

use help-tree.nu [help-of parse-help]

def active-help-var [tool: string]: nothing -> string {
  ($tool | str uppercase | str replace --regex --all '[^A-Z0-9]' '_') + "_ACTIVE_HELP"
}

# One __complete probe: { items: [{value, description}], directive: int, ok: bool }
export def probe [tool: string, args: list<string>]: nothing -> record {
  let r = (with-env { (active-help-var $tool): "0", NO_COLOR: "1", TERM: dumb } { ^$tool __complete ...$args | complete })
  let lines = ($r.stdout | lines)
  let dir_line = ($lines | where $it =~ '^:\d+$' | last | default "")
  if ($dir_line | is-empty) { return { items: [], directive: (-1), ok: false } }
  let items = ($lines | where $it !~ '^:\d+$' and ($it | str trim | is-not-empty) | each {|l|
    let p = ($l | split row "\t")
    let d = ($p | skip 1 | str join "\t")
    if ($d | is-empty) { { value: ($p | first) } } else { { value: ($p | first), description: $d } }
  })
  { items: $items, directive: ($dir_line | str trim --left --char ':' | into int), ok: true }
}

def walk [tool: string, path: list<string>, depth: int, max: int, values: bool, quiet: bool]: nothing -> record {
  let label = ([$tool] ++ $path | str join " ")
  let h = (parse-help (help-of $tool $path).text)
  let listing = (probe $tool ($path ++ [""]))
  let known = ($h.commands | get name)
  let is_parent = ($known | is-not-empty)
  let flags_raw = (probe $tool ($path ++ ["--"]))
  # help gives the type; __complete gives hidden flags and the full set
  let flags = ($flags_raw.items | each {|f|
    let hf = ($h.flags | where name == $f.value | get -o 0)
    let base = { name: $f.value, description: ($f.description? | default ($hf.description? | default "")) }
    let base = if $hf != null and ($hf.short? != null) { $base | insert short $hf.short } else { $base }
    let base = if $hf != null and ($hf.arg? != null) { $base | insert arg $hf.arg } else { $base }
    if $hf != null and ($hf.values? != null) { $base | insert values $hf.values } else { $base }
  })
  # enum values of flags that take one (bounded: one probe per valued flag)
  let flags = if $values {
    $flags | each {|f|
      if ($f.arg? == null) or ($f.values? != null) { $f } else {
        let v = (probe $tool ($path ++ [$f.name ""]))
        if $v.ok and $v.directive == 4 and ($v.items | is-not-empty) and ($v.items | length) < 40 { $f | insert values ($v.items | get value) } else { $f }
      }
    }
  } else { $flags }
  if not $quiet { print -e $"  ($label): ($listing.items | length) listed, ($flags | length) flags, directive ($listing.directive)(if $is_parent { '' } else { ' (leaf)' })" }
  mut subs = {}
  if $is_parent {
    mut count = 0
    for it in $listing.items {
      if $it.value in [help completion] { continue }
      if $count >= $max { break }
      let child = if $depth > 0 { walk $tool ($path ++ [$it.value]) ($depth - 1) $max $values $quiet } else { { description: "", flags: [], subcommands: {} } }
      let child = if ($child.description | is-empty) { $child | update description ($it.description? | default "") } else { $child }
      let child = if $it.value not-in $known { $child | insert hidden true } else { $child }
      $subs = ($subs | upsert $it.value $child)
      $count += 1
    }
  }
  let node = {
    description: $h.description
    usage: $h.usage
    args: $h.args
    flags: $flags
    subcommands: $subs
  }
  if $is_parent { $node } else {
    # a leaf: what did __complete offer for the first positional?
    $node | insert positional { directive: $listing.directive, sample: ($listing.items | first 20), count: ($listing.items | length) }
  }
}

export def main [
  tool: string
  --at: string = ""   # start at this subcommand path, e.g. "pr list"
  --depth: int = 4
  --max: int = 200
  --no-values       # do not probe enum values of valued flags (one __complete per flag)
  --json
  --quiet (-q)
]: nothing -> string {
  if (which $tool | is-empty) { error make { msg: $"($tool) is not on PATH" } }
  let root = (probe $tool [""])
  if not $root.ok { error make { msg: $"($tool) does not answer `__complete`: not a cobra program", help: "use help-tree.nu or fish-spec.nu" } }
  let start = ($at | split row " " | where $it != "")
  let t = (walk $tool $start $depth $max (not $no_values) $quiet)
  if $json { $t | to json } else { $t | to nuon --indent 2 }
}
