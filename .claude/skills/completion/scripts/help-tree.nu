#!/usr/bin/env nu
# help-tree.nu — a tool's command surface from its own --help, recursively
#
#   nu help-tree.nu <tool> [--depth 3] [--max 150] [--json]
#
# Walks `<tool> [sub...] --help` (then `<tool> help sub`, then `-h`), parses
# the layouts of clap (Commands:/Options:/Arguments:), cobra (CORE COMMANDS /
# FLAGS / INHERITED FLAGS), argparse (positional arguments:/options:) and
# git-style short usage, and prints a draft spec in the shape
# modules/nu-complete/engine.nu reads — minus the sources, which need a
# person: every positional is reported under `args` as the name the help
# used (`<BRANCH>`, `ENV_DIR`, `[<number> | <url>]`) for you to map to a
# source, and never under `positionals`, where an unknown name would
# silently complete nothing.
#
# Draft shape:
#   { description, usage: [..], flags: [{name, short, arg, values, description}],
#     args: [{name, rest, optional}], aliases: {b: build},
#     subcommands: {name: {same}}, probed: "cargo add --help" }

def env-for-help []: nothing -> record {
  { PAGER: cat, GIT_PAGER: cat, MANPAGER: cat, NO_COLOR: "1", TERM: dumb, COLUMNS: "200", CLICOLOR: "0", GH_NO_UPDATE_NOTIFIER: "1", HOMEBREW_NO_AUTO_UPDATE: "1", CARGO_TERM_COLOR: never }
}

# Run one help form; text from stdout, else stderr (git prints -h there).
export def run-help [argv: list<string>]: nothing -> record<text: string, ok: bool> {
  let r = (with-env (env-for-help) { ^$argv.0 ...($argv | skip 1) | complete })
  let out = ($r.stdout | ansi strip)
  let err = ($r.stderr | ansi strip)
  let text = if ($out | str trim | is-not-empty) { $out } else { $err }
  # A usage/help text has a Usage line or a section header; an error does not.
  let ok = ($text =~ '(?im)^\s*(usage|USAGE)\b' or $text =~ '(?m)^[A-Z][A-Za-z ]*(COMMANDS|Commands|Options|OPTIONS|FLAGS|Flags|arguments|Arguments):?\s*$')
  { text: $text, ok: $ok }
}

export def help-of [tool: string, path: list<string>]: nothing -> record<text: string, form: string> {
  let forms = [
    { form: "--help", argv: ([$tool] ++ $path ++ ["--help"]) }
    { form: "help",   argv: ([$tool "help"] ++ $path) }
    { form: "-h",     argv: ([$tool] ++ $path ++ ["-h"]) }
  ]
  mut manpage: any = null
  for f in $forms {
    if ($f.form == "help") and ($path | is-empty) { continue }
    let r = (run-help $f.argv)
    if $r.ok {
      # `git clone --help` is the man page; the short `-h` usage parses better.
      if ($r.text =~ '^\S+\(\d\)\s') and $f.form != "-h" { if $manpage == null { $manpage = { text: $r.text, form: ($f.argv | str join " ") } }; continue }
      return { text: $r.text, form: ($f.argv | str join " ") }
    }
  }
  if $manpage != null { return $manpage }
  { text: "", form: "" }
}

# ── Parsing one help text ─────────────────────────────────────────────────────

# Section headers: `Commands:`, `Options:`, `Cache options:`, `USAGE`,
# `CORE COMMANDS`, `INHERITED FLAGS`, `positional arguments:`.
def header-kind [line: string]: nothing -> any {
  let l = ($line | str trim)
  if ($l | str length) > 90 or ($l | is-empty) { return null }
  let is_header = ($line =~ '^\S' and ($l =~ ':$' or $l =~ '^[A-Z][A-Z ]+$'))
  if not $is_header { return null }
  let t = ($l | str lowercase | str trim --right --char ':')
  if $t =~ 'command' { "commands" } else if $t =~ 'positional argument' or $t == "arguments" or $t == "args" { "args" } else if $t =~ '(option|flag)' { "flags" } else if $t =~ '^usage' { "usage" } else if $t =~ '^alias' { "aliases" } else { "other" }
}

# The first sentence, at most 140 characters: long help is a paragraph per flag.
def short-desc [d: string]: nothing -> string {
  let first = ($d | str replace --regex '(?<=[a-z0-9)])\.\s+[A-Z].*$' '' )
  if ($first | str length) > 140 { ($first | str substring 0..137 | str trim) + "…" } else { $first }
}

# `--[no-]quiet` is two flags.
def expand-no [f: record]: nothing -> list<record> {
  if ($f.name !~ '\[no-\]') { return [$f] }
  let plain = ($f.name | str replace '[no-]' '')
  [($f | update name $plain) ({ name: ($f.name | str replace '[no-]' 'no-'), description: $"negate: ($f.description)" })]
}

def clean-desc [d: string]: nothing -> string {
  $d | str replace --regex --all '\s*\[(env|default|aliases?): [^\]]*\]' '' | str trim
}

# `[possible values: a, b, c]` → [a b c]
def values-in [d: string]: nothing -> list<string> {
  let m = ($d | parse --regex '\[possible values: (?<v>[^\]]+)\]' | get -o 0.v)
  if $m == null { [] } else { $m | split row "," | each {|v| $v | str trim | str replace --regex '\s.*' '' } | where $it != "" }
}

# One flag line: `-b, --branch string   desc`, `--cache-dir <CACHE_DIR>  desc`,
# `-C <DIRECTORY>  desc`, `--prompt PROMPT`, `--[no-]quiet`, `-v, --verbose...`.
export def parse-flag [line: string]: nothing -> any {
  let m = ($line | parse --regex '^\s+(?:(?<short>-[A-Za-z0-9])(?:[ ,]+|$))?(?:(?<long>--(?:\[no-\])?[\w][\w.-]*(?:\[no-\][\w.-]*)?)?)(?:\.{3})?(?:(?:[ =]|(?=\[=))(?<arg>(?:<[^>]+>|\[=?<[^>]+>\]|\[[^\]]+\]|[A-Z][A-Z0-9_-]{1,}|strings?|ints?|bool|path|file|dir|dur(?:ation)?|list|url|glob|number|float)\S*))?(?:\.{3})?(?:\s{2,}(?<desc>\S.*))?\s*$' | get -o 0)
  if $m == null or (($m.short | is-empty) and ($m.long | is-empty)) { return null }
  let d = ($m.desc | default "")
  let base = { name: (if ($m.long | is-empty) { $m.short } else { $m.long } | str replace --regex '\.{3}$' ''), description: (clean-desc $d) }
  let base = if ($m.long | is-not-empty) and ($m.short | is-not-empty) { $base | insert short $m.short } else { $base }
  let base = if ($m.arg | is-not-empty) { $base | insert arg ($m.arg | str replace --regex --all '[<>\[\]=]' '') } else { $base }
  let vals = (values-in $d)
  if ($vals | is-not-empty) { $base | insert values $vals } else { $base }
}

# One command line: `  add        desc`, `    build, b    desc`, `  auth:   desc`, `  co:  Alias for "pr checkout"`.
export def parse-command [line: string]: nothing -> any {
  let m = ($line | parse --regex '^\s{1,8}(?<name>[a-z][\w.:+-]*?)(?<aliases>(?:,\s*[\w.-]+)*):?(?:\s{2,}(?<desc>\S.*))?$' | get -o 0)
  if $m == null { return null }
  if $m.name =~ '^-' or $m.name in [usage see run] { return null }
  let aliases = ($m.aliases | split row "," | each {|a| $a | str trim } | where $it != "")
  { name: ($m.name | str trim --right --char ':'), aliases: $aliases, description: (clean-desc ($m.desc | default "")) }
}

# Positional tokens of a usage line: `<DEP_ID>...`, `[PATH]`, `ENV_DIR [ENV_DIR ...]`, `[<number> | <url> | <branch>]`.
def usage-args [usage: list<string>]: nothing -> list<record> {
  $usage | each {|u|
    let rest = ($u | str replace --regex '^\s*(usage:?\s*)?' '' | str replace --regex '^\S+' '')
    let rest = ($rest | str replace --regex --all '\[(OPTIONS|options|flags|FLAGS|<?options>?)\]|\[flags\]|\[--\]|\[@<[^>]*>\]' '')
    $rest | parse --regex '(?<tok>\[<[^\]]+>\]|<[^>]+>(?:\.\.\.)?|\[[A-Za-z_][\w-]*\.{3}?\]|\b[A-Z][A-Z0-9_]{2,}\b(?:\.\.\.)?)' | get tok
  } | flatten | uniq | where $it !~ '^(\[)?(OPTIONS|FLAGS|COMMAND|SUBCOMMAND|<command>|<subcommand>)' | each {|t|
    { name: ($t | str replace --regex --all '[<>\[\]]' '' | str replace --regex '\.{3}$' ''), rest: ($t =~ '\.{3}'), optional: ($t =~ '^\[') }
  }
}

export def parse-help [text: string]: nothing -> record {
  let lines = ($text | lines)
  mut section = "usage"
  mut usage = []
  mut flags = []
  mut cmds = []
  mut arg_lines = []
  mut description = ""
  mut glue = false
  mut i = 0
  for line in $lines {
    let hk = (header-kind $line)
    if $hk != null {
      $section = $hk
      # `Usage: tool ...` on the header line itself
      if $hk == "usage" and ($line =~ '(?i)^usage:\s*\S') { $usage ++= [$line] }
      $i += 1
      continue
    }
    if ($line | str trim | is-empty) { $glue = false; $i += 1; continue }
    match $section {
      "usage" => {
        let f = (if ($usage | is-not-empty) and ($line =~ '^\s+-') { parse-flag $line } else { null })
        if $f != null { $flags ++= [$f]; $section = "flags" } else if $line =~ '(?i)^\s*usage:\s*\S' or ($line =~ '^\s{2,}\S') { $usage ++= [$line] } else if ($description | is-empty) and ($line =~ '^\S') and ($i < 3) { $description = ($line | str trim) }
      }
      "flags" | "other" => {
        let f = (parse-flag $line)
        if $f != null { $flags ++= [$f]; $glue = true } else if $glue and ($flags | is-not-empty) and ($line =~ '^\s{8,}\S') {
          # wrapped description
          let prev = ($flags | last)
          let joined = (clean-desc ([$prev.description ($line | str trim)] | where $it != "" | str join " "))
          let prev = ($prev | update description $joined)
          let vals = (values-in $joined)
          let prev = if ($vals | is-not-empty) and ($prev.values? == null) { $prev | insert values $vals } else { $prev }
          $flags = ($flags | drop 1 | append $prev)
        }
      }
      "commands" | "aliases" => {
        let c = (parse-command $line)
        if $c != null { $cmds ++= [$c] }
      }
      "args" => { $arg_lines ++= [$line] }
      _ => {}
    }
    $i += 1
  }
  # argparse and clap list positionals under a header; take their names too.
  let listed = ($arg_lines | each {|l| $l | parse --regex '^\s{1,8}(?<name>[<\[]?[A-Za-z][\w-]*[>\]]?(?:\.{3})?)(?:\s{2,}(?<desc>.*))?$' | get -o 0 } | compact)
  let from_usage = (usage-args $usage)
  let args = if ($from_usage | is-not-empty) { $from_usage } else {
    $listed | each {|a| { name: ($a.name | str replace --regex --all '[<>\[\]]' '' | str replace --regex '\.{3}$' ''), rest: ($a.name =~ '\.{3}'), optional: ($a.name =~ '^\[') } }
  }
  let args = ($args | each {|a|
    let d = ($listed | where {|l| ($l.name | str replace --regex --all '[<>\[\].]' '') == $a.name } | get -o 0.desc | default "")
    if ($d | is-empty) { $a } else { $a | insert description (clean-desc $d) }
  })
  {
    description: $description
    usage: ($usage | each {|u| $u | str trim })
    flags: ($flags | each {|f| expand-no $f } | flatten | each {|f| $f | update description (short-desc $f.description) } | uniq-by name)
    args: $args
    commands: ($cmds | uniq-by name)
  }
}

# ── Walking the tree ──────────────────────────────────────────────────────────

def walk [tool: string, path: list<string>, depth: int, max: int, seen: list<string>, quiet: bool]: nothing -> record {
  let h = (help-of $tool $path)
  let label = ([$tool] ++ $path | str join " ")
  if ($h.text | is-empty) {
    if not $quiet { print -e $"  ✗ ($label): no help text" }
    return { description: "", probed: "", flags: [], args: [], subcommands: {} }
  }
  let p = (parse-help $h.text)
  if not $quiet { print -e $"  ($label): ($p.commands | length) commands, ($p.flags | length) flags, ($p.args | length) args" }
  let fp = ($h.text | lines | first 3 | str join "|")
  let aliases = ($p.commands | where ($it.aliases | is-not-empty) | reduce -f {} {|c, acc| $c.aliases | reduce -f $acc {|a, acc2| $acc2 | upsert $a $c.name } })
  let alias_cmds = ($p.commands | where {|c| $c.description =~ '(?i)^alias for' } | get name)
  mut subs = {}
  mut count = 0
  if $depth > 0 {
    for c in $p.commands {
      if $c.name in [help completion completions] or $c.name in $alias_cmds { continue }
      if $count >= $max { break }
      let child = (walk $tool ($path ++ [$c.name]) ($depth - 1) $max ($seen ++ [$fp]) $quiet)
      # Some tools print the parent's help for an unknown subcommand: drop those.
      let child_fp = ($child | get -o fingerprint | default "")
      let node = ($child | reject -o fingerprint)
      let node = if ($node.description | is-empty) { $node | update description $c.description } else { $node }
      let node = if ($c.aliases | is-not-empty) { $node | upsert also $c.aliases } else { $node }
      if $child_fp != $fp and $child_fp not-in $seen {
        $subs = ($subs | upsert $c.name $node)
      } else {
        $subs = ($subs | upsert $c.name { description: $c.description, flags: [], args: [], subcommands: {} })
      }
      $count += 1
    }
  }
  {
    description: $p.description
    probed: $h.form
    usage: $p.usage
    flags: $p.flags
    args: $p.args
    aliases: $aliases
    subcommands: $subs
    fingerprint: $fp
  }
}

# The draft spec for `tool`, from its help texts.
export def main [
  tool: string        # the command (must be on PATH)
  --at: string = ""   # start at this subcommand path, e.g. "pr checkout"
  --depth: int = 3    # how deep to follow subcommands
  --max: int = 150    # at most this many subcommands per level
  --json              # print JSON (default: nuon)
  --quiet (-q)        # no progress on stderr
]: nothing -> string {
  if (which $tool | is-empty) { error make { msg: $"($tool) is not on PATH" } }
  let start = ($at | split row " " | where $it != "")
  let t = (walk $tool $start $depth $max [] $quiet | reject -o fingerprint)
  let n = (count-subs $t)
  if not $quiet { print -e $"($tool): ($n) subcommands in the tree" }
  if $json { $t | to json } else { $t | to nuon --indent 2 }
}

def count-subs [node: record]: nothing -> int {
  let subs = ($node.subcommands? | default {})
  let below = ($subs | values | each {|s| count-subs $s })
  ($subs | columns | length) + (if ($below | is-empty) { 0 } else { $below | math sum })
}
