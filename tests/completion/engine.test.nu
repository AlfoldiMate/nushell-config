# The completion engine (modules/nu-complete/engine.nu) without a terminal:
# the span list a completer works from, filtering, quoting, and `run` walking
# a spec. The spec here is inline and small; the shipped ones are in
# specs.test.nu.
use lib.nu *
use std/assert
use nu-complete *

# ── spans ─────────────────────────────────────────────────────────────────────

# The unified completer inputs (#18791): `token.text`, `place.target.start`,
# the whole buffer. The cases checked token for token against 0.115.1's real
# spans when `spans` was written.
def spans-of [line: string, tok: string]: nothing -> list<string> {
  nu-complete spans { text: $tok } { target: { start: (($line | str length) - ($tok | str length)) } } $line
}

def "test spans rebuilds the command tokens from the buffer" [] {
  assert equal (spans-of "git checkout ch" "ch") [git checkout ch]
  assert equal (spans-of "brew install ri" "ri") [brew install ri]
}

def "test spans starts at the last command head, not the pipeline head" [] {
  assert equal (spans-of "ls | git ch" "ch") [git ch]
  assert equal (spans-of "echo a; git ch" "ch") [git ch]
  assert equal (spans-of "cd ~/x; brew install ri" "ri") [brew install ri]
}

def "test spans keeps a quoted argument and a flag=value as one token" [] {
  assert equal (spans-of 'git commit -m "a b" fi' "fi") [git commit -m '"a b"' fi]
  assert equal (spans-of "git log --oneline=x ma" "ma") [git log --oneline=x ma]
}

def "test spans ends a fresh slot with an empty token" [] {
  assert equal (spans-of "git checkout " "") [git checkout ""]
}

def "test spans survives an unterminated quote" [] {
  assert equal (spans-of 'git commit -m "ab' '"ab') [git commit -m '"ab']
}

def "test spans passes the old span list through on 0.115.1" [] {
  # There `place` is never bound, and the first parameter is the list itself.
  assert equal (nu-complete spans [git ch] null null) [git ch]
  assert equal (nu-complete spans null null null) []
}

# ── normalize · filter ────────────────────────────────────────────────────────

def "test normalize wraps strings and keeps records" [] {
  assert equal ([a { value: b, description: d }] | nu-complete normalize) [{ value: a } { value: b, description: d }]
  assert equal (null | nu-complete normalize) []
  assert equal ([1 2] | nu-complete normalize) [{ value: "1" } { value: "2" }]
}

def items [] { [{ value: alpha } { value: Beta } { value: gamma-beta }] }

def "test filter follows the completion algorithm" [] {
  $env.config.completions.case_sensitive = false
  $env.config.completions.algorithm = "prefix"
  assert equal (items | nu-complete filter "be" | get value) [Beta]
  $env.config.completions.algorithm = "substring"
  assert equal (items | nu-complete filter "be" | get value) [Beta gamma-beta]
  $env.config.completions.algorithm = "fuzzy"
  assert equal (items | nu-complete filter "gba" | get value) [gamma-beta]
  assert equal (items | nu-complete filter "" | length) 3
}

def "test filter honours case sensitivity" [] {
  $env.config.completions.algorithm = "prefix"
  $env.config.completions.case_sensitive = true
  assert equal (items | nu-complete filter "be" | get value) []
  assert equal (items | nu-complete filter "Be" | get value) [Beta]
  $env.config.completions.case_sensitive = false
  assert equal (items | nu-complete filter "be" | get value) [Beta]
}

# ── quote ─────────────────────────────────────────────────────────────────────

def "test quote makes a value with a space one argument" [] {
  assert equal ([{ value: "Catppuccin Macchiato" }] | nu-complete quote | get 0.value) '"Catppuccin Macchiato"'
  assert equal ([{ value: "a|b" } { value: 'x$y' }] | nu-complete quote | get value) ['"a|b"' '"x$y"']
}

def "test quote leaves plain, already quoted and trailing-space values alone" [] {
  assert equal ([{ value: plain } { value: "a-b_c.d/e" }] | nu-complete quote | get value) [plain "a-b_c.d/e"]
  assert equal ([{ value: '"a b"' } { value: "`a b`" } { value: "'a b'" }] | nu-complete quote | get value) ['"a b"' "`a b`" "'a b'"]
  # carapace's trailing space means "and a space after it": kept, outside the quotes.
  assert equal ([{ value: "a b " }] | nu-complete quote | get 0.value) '"a b" '
}

def "test quote never touches a command, flag or path" [] {
  let items = [
    { value: "str trim", kind: command }
    { value: "--flag x", kind: flag }
    { value: "a b", kind: file }
    { value: "a b", kind: directory }
    { value: "a b", kind: value }
  ]
  assert equal ($items | nu-complete quote | get value) ["str trim" "--flag x" "a b" "a b" '"a b"']
}

# ── run ───────────────────────────────────────────────────────────────────────

def spec [] {
  {
    description: "a tool"
    fallback: "external"
    flags: [
      { name: "--verbose", short: "-v", description: "more" }
      { name: "--config", short: "-c", description: "a file", arg: "files" }
      { name: "--level", description: "how much", arg: [low high] }
    ]
    positionals: [ [alpha beta] ]
    subcommands: {
      build: {
        description: "build it"
        flags: [
          { name: "--target", description: "for", arg: {|ctx| [$"($ctx.partial)m64" x86] } }
          { name: "--verbose", description: "the build's own" }
        ]
        positionals: [named]
        rest: "files"
      }
      run: { description: "run it", positionals: [[one two]] }
    }
    sources: { named: {|ctx| [{ value: n1, description: first } n2] } }
  }
}

def --wrapped walk [...spans: string] { nu-complete run (spec) $spans }

def "test run offers subcommands and the first positional together" [] {
  let got = walk tool ""
  assert equal ($got | get value) [build run alpha beta]
  assert equal ($got | where value == build | get 0.description) "build it"
  assert equal (walk tool b | get value) [build beta]
}

def "test run offers flags with their shorts, and no shorts after --" [] {
  assert equal (walk tool "-" | get value) [--verbose --config --level -v -c]
  assert equal (walk tool "--" | get value) [--verbose --config --level]
  assert equal (walk tool "--v" | get 0.description) more
}

def "test run offers a flag value after it and in flag=value form" [] {
  assert equal (walk tool --level "" | get value) [low high]
  assert equal (walk tool --level h | get value) [high]
  assert equal (walk tool --level=h | get value) [--level=high]
  # The value consumed, the positional is next.
  assert equal (walk tool --level low "" | get value) [build run alpha beta]
}

def "test run hands a files slot to Nushell" [] {
  assert equal (walk tool --config "") null
  assert equal (walk tool build n1 "") null
}

def "test run walks into a subcommand and runs a named source" [] {
  let got = walk tool build ""
  assert equal ($got | get value) [n1 n2]
  assert equal ($got | get 0.description) first
  assert equal (walk tool run "" | get value) [one two]
}

def "test run gives a subcommand its own flags plus the roots, its own winning" [] {
  let got = walk tool build "--"
  assert equal ($got | get value) [--target --verbose --config --level]
  assert equal ($got | where value == --verbose | get 0.description) "the build's own"
}

def "test run gives a flag closure the partial" [] {
  assert equal (walk tool build --target ar | get value) [arm64]
}

def "test run asks the external completer when the spec has no opinion" [] {
  $env.config.completions.external.completer = {|spans| [{ value: $"ext:($spans | str join ' ')" }] }
  assert equal (walk tool run one "" | get 0.value) "ext:tool run one "
  # A flag the spec does not know: outside too.
  assert equal (walk tool --unknown | get 0.value) "ext:tool --unknown"
  # Not a flag it does know.
  assert equal (walk tool --verb | get value) [--verbose]
}

def "test run answers null without an external completer" [] {
  $env.config.completions.external.completer = null
  assert equal (walk tool run one "") null
  assert equal (walk tool --unknown) null
}

def "test run filters the way the settings say and quotes what it hands out" [] {
  $env.config.completions.algorithm = "fuzzy"
  assert equal (walk tool bta | get value) [beta]
  $env.config.completions.algorithm = "prefix"
  let s = { positionals: [[{ value: "a b" } plain]] }
  assert equal (nu-complete run $s [tool ""] | get value) ['"a b"' plain]
}

def "test run treats a lone command as a fresh slot" [] {
  assert equal (nu-complete run (spec) [tool] | get value) [build run alpha beta]
}
