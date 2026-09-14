#!/usr/bin/env nu
# fish-spec.nu — a draft spec from a fish completion file
#
#   nu fish-spec.nu <tool>            finds <tool>.fish in the usual places
#   nu fish-spec.nu --file x.fish <tool>
#   <tool> --generate complete-fish | nu fish-spec.nu --stdin <tool>
#
# fish completions are a flat list of `complete` calls, one per (context,
# flag) — the easiest shipped format to read mechanically. Each line says
# where it applies (-n condition: __fish_seen_subcommand_from / using_subcommand
# / needs_command), the flag (-s -l -o), its description (-d), whether it takes
# a value (-r, -x) and the candidates (-a: a literal `a\t'desc'` list, a
# `(command)` = a dynamic source, or `$var`). Lines without a flag define
# subcommands (at a needs_command / not-seen condition) or positional values.
#
# The draft has the shape modules/nu-complete/engine.nu reads, minus sources:
#   { flags: [{name, short, description, arg: bool, files: bool, values: [..], dynamic: "(cmd)"}],
#     values: [..] / dynamic: [..]   candidates a positional got from -a lines,
#     subcommands: {name: {…}} }
# Dynamic sources are reported verbatim for you to translate into a Nushell
# closure — that is the step that needs a person.
#
# cobra tools (gh, kubectl, docker) ship a fish file that only calls
# `<tool> __complete`: nothing to parse — use cobra-tree.nu.

# ── Tokenising one fish command line ──────────────────────────────────────────

# Split on unquoted whitespace, honouring '…', "…" and backslashes; quotes
# are removed. Returns the words.
def fish-words [line: string]: nothing -> list<string> {
  mut words = []
  mut cur = ""
  mut quote = ""
  mut have = false
  mut esc = false
  for c in ($line | split chars) {
    if $esc {
      $cur += (if $quote == "" and $c == "t" { "\t" } else if $quote == "" and $c == "n" { "\n" } else if $quote == '"' and $c not-in ['"' "$" "\\"] { "\\" + $c } else { $c })
      $esc = false
      $have = true
    } else if $c == "\\" and $quote != "'" {
      $esc = true
    } else if $quote != "" {
      if $c == $quote { $quote = "" } else { $cur += $c }
    } else if $c in ["'" '"'] {
      $quote = $c
      $have = true
    } else if $c in [" " "\t"] {
      if $have { $words ++= [$cur]; $cur = ""; $have = false }
    } else if $c == "#" and not $have {
      break
    } else {
      $cur += $c
      $have = true
    }
  }
  if $have { $words ++= [$cur] }
  $words
}

# `complete` options → a record. Long and short spellings both count.
def parse-complete [words: list<string>]: nothing -> any {
  mut r = { cmd: "", cond: [], short: [], long: [], old: [], desc: "", args: [], req: false, nofiles: false, files: false, wraps: [] }
  mut i = 1
  let n = ($words | length)
  while $i < $n {
    let w = ($words | get $i)
    let next = (if ($i + 1) < $n { $words | get ($i + 1) } else { "" })
    match $w {
      "-c" | "--command" => { $r.cmd = $next; $i += 2 }
      "-n" | "--condition" => { $r.cond ++= [$next]; $i += 2 }
      "-s" | "--short-option" => { $r.short ++= [$next]; $i += 2 }
      "-l" | "--long-option" => { $r.long ++= [$next]; $i += 2 }
      "-o" | "--old-option" => { $r.old ++= [$next]; $i += 2 }
      "-d" | "--description" => { $r.desc = $next; $i += 2 }
      "-a" | "--arguments" => { $r.args ++= [$next]; $i += 2 }
      "-w" | "--wraps" => { $r.wraps ++= [$next]; $i += 2 }
      "-r" | "--require-parameter" => { $r.req = true; $i += 1 }
      "-f" | "--no-files" => { $r.nofiles = true; $i += 1 }
      "-F" | "--force-files" => { $r.files = true; $i += 1 }
      "-x" | "--exclusive" => { $r.req = true; $r.nofiles = true; $i += 1 }
      "-k" | "--keep-order" | "-e" | "--erase" | "-p" | "--path" => { $i += 1 }
      _ => {
        # combined short options: -rf, -xk
        if $w =~ '^-[rfFxke]+$' {
          if ($w | str contains "r") { $r.req = true }
          if ($w | str contains "x") { $r.req = true; $r.nofiles = true }
          if ($w | str contains "f") { $r.nofiles = true }
          if ($w | str contains "F") { $r.files = true }
        }
        $i += 1
      }
    }
  }
  $r
}

# The subcommand paths a condition applies to, as a list of alternatives
# (each a list of names), or [[]] for the root. `defines_children` is true
# when the condition says "at X but no deeper" — the shape a subcommand list
# for X has.
def paths-of [conds: list<string>]: nothing -> record<paths: list, defines_children: bool> {
  mut base = []
  mut alts = []
  mut children = false
  for cond in $conds {
    for clause in ($cond | split row ";" | each {|c| $c | str trim } | where $it != "") {
      let neg = ($clause =~ '^(and |or )?not ')
      let c = ($clause | str replace --regex '^(and |or )?(not )?' '')
      let ws = ($c | split row " " | where $it != "")
      let f = ($ws | first | default "")
      let rest = ($ws | skip 1)
      if $f !~ '^__fish' { continue }                       # set -q X, test …: not a position
      if $f =~ 'nth_token|contains_opt|is_token|seen_argument|_debug' { continue }
      if $neg { $children = true; continue }                # "not seen X": defining X's children or the root
      if $f =~ 'needs_command|use_subcommand|is_first_arg|no_arguments|no_subcommand' { $children = true; continue }
      if ($rest | length) == 1 { $base ++= $rest } else if ($rest | is-not-empty) { $alts = $rest }
    }
  }
  let b = $base
  let paths = if ($alts | is-empty) { [$b] } else { $alts | each {|a| $b ++ [$a] } }
  { paths: $paths, defines_children: $children }
}

# `-a` payload → candidates: {values: [{value, description}], dynamic: [..], vars: [..]}
def candidates-of [args: list<string>]: nothing -> record {
  mut values = []
  mut dynamic = []
  mut vars = []
  for a in $args {
    let a = ($a | str trim)
    if $a =~ '^\(.*\)$' { $dynamic ++= [$a]; continue }
    if $a =~ '^\$\w+$' { $vars ++= [$a]; continue }
    let toks = ($a | str replace --all "\\n" "\n" | lines | each {|l| fish-words $l } | flatten | where $it != "")
    for tok in $toks {
      let parts = ($tok | split row "\t")
      let v = ($parts | first)
      if $v =~ '^\(' { $dynamic ++= [$v]; continue }
      if $v =~ '^\$' { $vars ++= [$v]; continue }
      let d = ($parts | skip 1 | str join "\t" | str trim --char "'" | str trim --char '"')
      $values ++= [(if ($d | is-empty) { { value: $v } } else { { value: $v, description: $d } })]
    }
  }
  { values: $values, dynamic: ($dynamic | uniq), vars: ($vars | uniq) }
}

# ── Building the tree ─────────────────────────────────────────────────────────

def node-at [tree: record, path: list<string>]: nothing -> record {
  mut node = $tree
  for p in $path { $node = ($node.subcommands | get -o $p | default { flags: [], subcommands: {} }) }
  $node
}

def with-node [tree: record, path: list<string>, f: closure]: nothing -> record {
  if ($path | is-empty) { return (do $f $tree) }
  let head = ($path | first)
  let subs = ($tree.subcommands? | default {})
  let child = ($subs | get -o $head | default { flags: [], subcommands: {} })
  $tree | upsert subcommands ($subs | upsert $head (with-node $child ($path | skip 1) $f))
}

def add-flag [tree: record, path: list<string>, flag: record]: nothing -> record {
  with-node $tree $path {|n| $n | upsert flags (($n.flags? | default []) ++ [$flag]) }
}

def add-subcommands [tree: record, path: list<string>, cands: list<record>]: nothing -> record {
  with-node $tree $path {|n|
    let subs = ($n.subcommands? | default {})
    $n | upsert subcommands ($cands | reduce -f $subs {|c, acc|
      let existing = ($acc | get -o $c.value | default { flags: [], subcommands: {} })
      let existing = if ($c.description? | default "" | is-not-empty) and ($existing.description? | default "" | is-empty) { $existing | upsert description $c.description } else { $existing }
      $acc | upsert $c.value $existing
    })
  }
}

def add-positional [tree: record, path: list<string>, c: record]: nothing -> record {
  with-node $tree $path {|n|
    let n = if ($c.values | is-not-empty) { $n | upsert values (($n.values? | default []) ++ $c.values | uniq-by value) } else { $n }
    let n = if ($c.dynamic | is-not-empty) { $n | upsert dynamic (($n.dynamic? | default []) ++ $c.dynamic | uniq) } else { $n }
    if ($c.vars | is-not-empty) { $n | upsert vars (($n.vars? | default []) ++ $c.vars | uniq) } else { $n }
  }
}

# Physical lines joined while a quote is open: clap writes `-a "a\t'x'
# b\t'y'"` across lines.
def logical-lines [text: string]: nothing -> list<string> {
  mut out = []
  mut cur = ""
  mut open = ""
  for line in ($text | lines) {
    if $open == "" and ($line =~ '^\s*#') { continue }
    if ($cur | lines | length) > 60 { $out ++= [$cur]; $cur = ""; $open = "" }
    $cur = (if ($cur | is-empty) { $line } else { $cur + "\n" + $line })
    mut esc = false
    for c in ($line | split chars) {
      if $esc { $esc = false } else if $c == "\\" and $open != "'" { $esc = true } else if $open != "" { if $c == $open { $open = "" } } else if $c in ["'" '"'] { $open = $c }
    }
    if $open == "" { $out ++= [$cur]; $cur = "" }
  }
  if ($cur | is-not-empty) { $out ++= [$cur] }
  $out
}

# Every `complete` line → the tree.
export def parse-fish [text: string, tool: string]: nothing -> record {
  # Join backslash-continued lines; a `-a "…\n…"` payload spans lines inside quotes.
  let joined = ($text | str replace --all "\\\n" " ")
  let lines = (logical-lines $joined | where $it =~ '^\s*(complete\b|__fish_\w+_complete_(sub_)?(cmd|arg)\b)')
  mut tree = { description: "", flags: [], subcommands: {}, lines: ($lines | length) }
  for line in $lines {
    let ws = (fish-words ($line | str trim))
    if ($ws | length) < 2 { continue }
    # Hand-written wrappers (brew.fish): __fish_x_complete_cmd 'install' 'desc',
    # __fish_x_complete_arg 'install' -l cask -d '…', …_sub_cmd 'a' 'b' 'desc', …_sub_arg 'a' 'b' -l …
    let head = ($ws | first)
    if $head =~ '^__fish_\w+_complete_(sub_)?(cmd|arg)$' {
      let is_sub = ($head =~ '_sub_')
      let is_cmd = ($head =~ '_cmd$')
      let npath = (if $is_sub { 2 } else { 1 })
      # 'install; and not __fish_seen_argument -l cask' → install
      let path = ($ws | skip 1 | first $npath | each {|p| $p | split row ";" | first | str trim })
      if ($path | length) < $npath { continue }
      if $is_cmd {
        let desc = ($ws | get -o ($npath + 1) | default "")
        $tree = (add-subcommands $tree ($path | drop 1) [{ value: ($path | last), description: $desc }])
      } else {
        let r = (parse-complete (["complete"] ++ ($ws | skip ($npath + 1))))
        let c = (candidates-of $r.args)
        if ($r.long | is-not-empty) or ($r.short | is-not-empty) {
          mut flag = { name: (if ($r.long | is-not-empty) { $"--($r.long | first)" } else { $"-($r.short | first)" }), description: $r.desc }
          if ($r.long | is-not-empty) and ($r.short | is-not-empty) { $flag = ($flag | insert short $"-($r.short | first)") }
          if $r.req { $flag = ($flag | insert arg true) }
          if ($c.values | is-not-empty) { $flag = ($flag | insert values $c.values) }
          if ($c.dynamic | is-not-empty) { $flag = ($flag | insert dynamic $c.dynamic) }
          $tree = (add-flag $tree $path $flag)
        } else if ($r.args | is-not-empty) {
          $tree = (add-positional $tree $path $c)
        }
      }
      continue
    }
    let r = (parse-complete $ws)
    # `-c $tool` in hand-written files: accept any -c when it is a variable.
    if ($r.cmd | is-not-empty) and ($r.cmd !~ '^\$') and $r.cmd != $tool { continue }
    let where = (paths-of $r.cond)
    let has_flag = (($r.long | is-not-empty) or ($r.short | is-not-empty) or ($r.old | is-not-empty))
    if $has_flag {
      let c = (candidates-of $r.args)
      let name = (if ($r.long | is-not-empty) { $"--($r.long | first)" } else if ($r.old | is-not-empty) { $"-($r.old | first)" } else { $"-($r.short | first)" })
      mut flag = { name: $name, description: $r.desc }
      if ($r.long | is-not-empty) and ($r.short | is-not-empty) { $flag = ($flag | insert short $"-($r.short | first)") }
      if $r.req { $flag = ($flag | insert arg true) }
      if $r.req and (not $r.nofiles) { $flag = ($flag | insert files true) }
      if ($c.values | is-not-empty) { $flag = ($flag | insert values $c.values) }
      if ($c.dynamic | is-not-empty) { $flag = ($flag | insert dynamic $c.dynamic) }
      if ($c.vars | is-not-empty) { $flag = ($flag | insert vars $c.vars) }
      for p in $where.paths { $tree = (add-flag $tree $p $flag) }
    } else if ($r.args | is-not-empty) {
      let c = (candidates-of $r.args)
      if $where.defines_children and ($c.values | is-not-empty) and ($c.dynamic | is-empty) {
        let vals = if ($c.values | length) == 1 and ($r.desc | is-not-empty) { $c.values | each {|v| $v | upsert description $r.desc } } else { $c.values }
        for p in $where.paths { $tree = (add-subcommands $tree $p $vals) }
      } else {
        for p in $where.paths { $tree = (add-positional $tree $p $c) }
      }
    }
  }
  dedupe-flags $tree
}

def dedupe-flags [node: record]: nothing -> record {
  let node = ($node | upsert flags (($node.flags? | default []) | uniq-by name))
  let subs = ($node.subcommands? | default {})
  $node | upsert subcommands ($subs | transpose k v | reduce -f {} {|r, acc| $acc | upsert $r.k (dedupe-flags $r.v) })
}

# Where a tool's fish completion may already be.
export def fish-file-candidates [tool: string]: nothing -> list<path> {
  let prefix = ($env.HOMEBREW_PREFIX? | default "/opt/homebrew")
  [
    ($prefix | path join share fish vendor_completions.d $"($tool).fish")
    ($prefix | path join completions fish $"($tool).fish")
    ($prefix | path join share fish completions $"($tool).fish")
    ("/usr/local/share/fish/vendor_completions.d" | path join $"($tool).fish")
    ("/usr/share/fish/vendor_completions.d" | path join $"($tool).fish")
    ("/usr/share/fish/completions" | path join $"($tool).fish")
    ($nu.home-dir | path join .config fish completions $"($tool).fish")
  ]
}

export def main [
  tool: string       # the command name (the `-c` the file completes)
  --file: path       # a fish completion file (default: the first found for <tool>)
  --stdin            # read the fish script from stdin (`tool --generate complete-fish | …`)
  --json
  --quiet (-q)
]: any -> string {
  let text = if $stdin { $in | into string } else {
    let f = (if $file != null { $file } else { fish-file-candidates $tool | where {|p| $p | path exists } | get -o 0 })
    if $f == null { error make { msg: $"no fish completion found for ($tool)", help: "pass --file, or generate one: <tool> --generate complete-fish | nu fish-spec.nu --stdin <tool>" } }
    if not $quiet { print -e $"reading ($f)" }
    open --raw $f
  }
  let t = (parse-fish $text $tool)
  if ($text =~ '__complete') and (($t.subcommands | columns | is-empty)) {
    print -e "this fish file delegates to `<tool> __complete` (cobra): use cobra-tree.nu instead"
  }
  if not $quiet { print -e $"($t.lines) complete lines → ($t.subcommands | columns | length) subcommands, ($t.flags | length) root flags" }
  if $json { $t | to json } else { $t | to nuon --indent 2 }
}
