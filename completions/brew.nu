# brew — Homebrew completion, native and fast
#
# Carapace answers `brew install <Tab>` in about 1.6 s because it asks Ruby.
# Homebrew already keeps everything needed on disk, so this module reads that:
#
#   subcommands, flags, positional kinds   $HOMEBREW_PREFIX/completions/zsh/_brew,
#                                          parsed once into a JSON spec, redone
#                                          when Homebrew updates the file
#   every formula and cask, with desc      the API payload in Homebrew's cache,
#                                          parsed once into a SQLite file in the
#                                          background; names come from the
#                                          plain-text name lists (1 ms) until
#                                          that is ready
#   installed packages                     directory names under Cellar/Caskroom
#   taps                                   directory names under Library/Taps
#
# Measured on 2026-09-10: `brew install rip<Tab>` answers in 3-5 ms with
# descriptions. `brew install` is not special-cased; every subcommand in the
# zsh file gets its own positional and flag completion.

use nu-complete *

# ── Where Homebrew keeps things ───────────────────────────────────────────────

def prefix []: nothing -> path {
  $env.HOMEBREW_PREFIX? | default (which brew | get -o 0.path | default "/opt/homebrew/bin/brew" | path dirname | path dirname)
}

def api-dir []: nothing -> path {
  let cache = ($env.HOMEBREW_CACHE? | default (
    if $nu.os-info.name == "macos" { $nu.home-dir | path join Library Caches Homebrew } else { $nu.home-dir | path join .cache Homebrew }
  ))
  $cache | path join api
}

def read-lines [f: path]: nothing -> list<string> {
  if ($f | path exists) { %open --raw $f | lines --skip-empty } else { [] }
}

# ── The spec: parsed from Homebrew's zsh completion ───────────────────────────

# Sources named in the zsh file → sources of this module.
def helper-source [helper: string]: nothing -> string {
  match $helper {
    "__brew_formulae" => "formulae"
    "__brew_casks" => "casks"
    "__brew_installed_formulae" | "__brew_outdated_formulae" | "__brew_services" => "installed_formulae"
    "__brew_installed_casks" | "__brew_outdated_casks" => "installed_casks"
    "__brew_any_tap" | "__brew_tapped" | "__brew_official_taps" => "taps"
    "__brew_internal_commands" | "__brew_commands" => "commands"
    "__brew_installed" => "installed"
    "_files" | "_directories" => "files"
    _ => "none"
  }
}

# Parse the zsh completion into a serialisable spec (sources by name).
export def "nu-complete brew spec-from-zsh" [file: path]: nothing -> record {
  let lines = (%open --raw $file | lines)
  let n = ($lines | length)

  # `__brew_internal_commands` holds every subcommand with its description.
  let cmd_start = ($lines | enumerate | where item =~ '^__brew_internal_commands\(\)' | get -o 0.index | default (-1))
  let descs = if $cmd_start < 0 { {} } else {
    $lines | skip ($cmd_start + 1) | take while {|l| $l !~ '^\}' }
    | parse --regex r#'^\s+'(?<name>[\w.-]+):(?<desc>.*)'\s*$'#
    | reduce -f {} {|r, acc| $acc | upsert $r.name ($r.desc | str replace -a "'\\''" "'") }
  }

  # One `_brew_<name>() { ... }` block per subcommand.
  # (`_brew_--taps`-style blocks are flags of `brew` itself, not subcommands.)
  let starts = ($lines | enumerate | where item =~ '^_brew_[A-Za-z][\w-]*\(\) \{' | select index item)
  let subcommands = ($starts | reduce -f {} {|s, acc|
    let name = ($s.item | parse --regex '^_brew_(?<n>[\w-]+)' | get 0.n | str replace -a "_" "-")
    let body = ($lines | skip ($s.index + 1) | take while {|l| $l !~ '^\}' })
    let flags = ($body
      | parse --regex r#''(?:\([^)]*\))?(?<name>--[\w-]+)=?\[(?<desc>.*)\]''#
      | uniq-by name
      | each {|f| { name: $f.name, description: ($f.desc | str replace -a "'\\''" "'") } })
    let pos = ($body | parse --regex r#''(?<slot>\*|\d+):[\w-]*:(?<helper>__brew_\w+|_files|_directories)''#)
    let rest_kinds = ($pos | where slot == "*" | get helper | each {|h| helper-source $h } | uniq | where $it != "none")
    let rest = (match $rest_kinds {
      [] => null
      [$one] => $one
      _ => (if ("formulae" in $rest_kinds and "casks" in $rest_kinds) { "packages" }
            else if ("installed_formulae" in $rest_kinds and "installed_casks" in $rest_kinds) { "installed" }
            else { $rest_kinds | first })
    })
    let node = ({ description: ($descs | get -o $name | default ""), flags: $flags } | merge (if $rest == null { {} } else { { rest: $rest } }))
    # A command like `brew help` completes other commands; `1:` slots.
    let firsts = ($pos | where slot == "1" | get helper | each {|h| helper-source $h } | where $it != "none")
    let node = if ($firsts | is-empty) { $node } else { $node | insert positionals [($firsts | first)] }
    $acc | upsert $name $node
  })

  {
    description: "The missing package manager for macOS"
    generated_from: $file
    subcommands: $subcommands
  }
}

# JSON, where the rest of this config writes NUON, because this file is big
# and sits on the Tab path: 195 kB parses in 1.2 ms as JSON and 7.8 ms as NUON
# (`to nuon --indent 2`: 9.3 ms). Nothing reads it but the completer.
def spec-file []: nothing -> path { nu-complete cache-dir | path join brew-spec.json }

# The spec as data, regenerated when Homebrew ships a new zsh completion.
export def "nu-complete brew spec-data" []: nothing -> record {
  let zsh = (prefix | path join completions zsh _brew)
  let f = (spec-file)
  if (nu-complete stale $f $zsh) and ($zsh | path exists) {
    nu-complete brew spec-from-zsh $zsh | to json | save -f $f
  }
  if ($f | path exists) { %open $f } else {
    # No zsh file (unusual install): subcommands only, from `brew commands`.
    { description: "Homebrew", subcommands: (^brew commands --quiet --include-aliases | lines | reduce -f {} {|c, acc| $acc | upsert $c {} }) }
  }
}

# ── Package list: Homebrew's API payload → SQLite ─────────────────────────────

def payload-file []: nothing -> any {
  glob ($"(api-dir)/internal/packages.*.jws.json.payload") | get -o 0
}

def db-file []: nothing -> path { nu-complete cache-dir | path join brew-packages.db }

# Build the SQLite package table from the API payload (~0.5 s, so it runs in
# a background job and the caller falls back to the name lists meanwhile).
export def "nu-complete brew build-db" []: nothing -> nothing {
  let payload = (payload-file)
  if $payload == null { return }
  let idx = (%open --raw $"($payload).index" | from json)
  let raw = (%open --raw $payload | into binary)
  # First line is the JWS header; offsets in the index are into the second.
  let body = ($raw | bytes at (($raw | bytes index-of 0x[0a]) + 1)..)
  let section = {|key|
    let r = ($idx.top_level | get $key)
    $body | bytes at $r.0..<($r.0 + $r.1) | decode | from json
  }
  let formulae = (do $section formulae | transpose name v | each {|r|
    { name: $r.name, kind: "formula", desc: ($r.v.desc? | default ""), version: ($r.v.stable_version? | default "") }
  })
  let casks = (do $section casks | transpose name v | each {|r|
    { name: $r.name, kind: "cask", desc: ($r.v.desc? | default ""), version: ($r.v.version? | default "") }
  })
  let db = (db-file)
  let tmp = $"($db).tmp"
  rm -f $tmp
  $formulae ++ $casks | into sqlite $tmp -t packages
  mv -f $tmp $db
}

# Make sure the database is fresh; when it is not, start building it in the
# background and say so (the caller then serves names without descriptions).
def ensure-db []: nothing -> bool {
  let db = (db-file)
  let payload = (payload-file)
  if $payload == null { return false }
  if not (nu-complete stale $db $payload) { return true }
  let lock = $"($db).building"
  let busy = (($lock | path exists) and ((date now) - (ls -D $lock | get 0.modified)) < 3min)
  if not $busy {
    touch $lock
    job spawn { try { nu-complete brew build-db }; rm -f $lock } | ignore
  }
  false
}

# Every formula and/or cask matching the partial, with descriptions when the
# database is ready. `kinds` ⊆ [formula cask].
def packages [partial: string, kinds: list<string>]: nothing -> list<record> {
  if (ensure-db) {
    let pat = if $env.config.completions.algorithm == "prefix" { $"($partial)%" } else { $"%($partial)%" }
    let ks = ($kinds | each {|k| $"'($k)'" } | str join ", ")
    %open (db-file)
    | query db $"select name as value, desc as description from packages where kind in \(($ks)\) and name like :p order by name limit 2000" -p { p: $pat }
  } else {
    let api = (api-dir)
    let names = (
      (if "formula" in $kinds { read-lines ($api | path join formula_names.txt) } else { [] })
      ++ (if "cask" in $kinds {
        let f = ($api | path join cask_names.txt)
        read-lines (if ($f | path exists) { $f } else { $api | path join cask_names.before.txt })
      } else { [] })
    )
    $names | wrap value
  }
}

# --cask / --formula narrow what a mixed slot offers.
def kinds-from [ctx: record, default: list<string>]: nothing -> list<string> {
  if "--cask" in $ctx.args { ["cask"] } else if "--formula" in $ctx.args { ["formula"] } else { $default }
}

def installed [kind: string]: nothing -> list<record> {
  let dir = (prefix | path join (if $kind == "formula" { "Cellar" } else { "Caskroom" }))
  if not ($dir | path exists) { return [] }
  ls $dir | where type == dir | each {|d|
    let versions = (ls $d.name | get name | path basename | where $it != ".metadata")
    { value: ($d.name | path basename), description: ($versions | str join ", ") }
  }
}

def taps []: nothing -> list<record> {
  let dir = (prefix | path join Library Taps)
  if not ($dir | path exists) { return [] }
  # Sorted: `glob` returns directory order, which differs by file system.
  glob $"($dir)/*/*" | sort | each {|p| { value: ($p | path relative-to $dir | str replace "homebrew-" "") } }
}

# ── The spec with its sources, as the engine wants it ─────────────────────────

export def "nu-complete brew spec" []: nothing -> record {
  nu-complete brew spec-data | merge {
    fallback: "external"
    flags: [
      { name: "--help", short: "-h", description: "Show this message" }
      { name: "--verbose", short: "-v", description: "Make some output more verbose" }
      { name: "--debug", short: "-d", description: "Display any debugging information" }
      { name: "--quiet", short: "-q", description: "Make some output more quiet" }
    ]
    sources: {
      packages: {|ctx| packages $ctx.partial (kinds-from $ctx [formula cask]) }
      formulae: {|ctx| packages $ctx.partial [formula] }
      casks: {|ctx| packages $ctx.partial [cask] }
      installed: {|ctx|
        let ks = (kinds-from $ctx [formula cask])
        ($ks | each {|k| installed $k } | flatten)
      }
      installed_formulae: {|ctx| installed formula }
      installed_casks: {|ctx| installed cask }
      taps: {|ctx| taps }
      commands: {|ctx| nu-complete brew spec-data | get subcommands | transpose name s | each {|r| { value: $r.name, description: ($r.s.description? | default "") } } }
      none: []
    }
  }
}

# null on any failure: Nushell then falls back to file completion instead of
# showing nothing.
# `[token, place?, buffer?]` fits both the unified completer inputs and
# 0.115.1's single positional; `nu-complete spans` resolves it either way. The
# inner `try`s are not defensive style — on 0.115.1 those two parameters are
# never bound at all, and naming one is a runtime error. See `nu-complete
# spans` in engine.nu.
def complete-brew [token, place?, buffer?] {
  try { nu-complete run (nu-complete brew spec) (nu-complete spans $token (try { $place }) (try { $buffer })) } catch { null }
}

# `main` so that `use brew.nu *` yields `brew` (a module cannot export an
# extern of its own name any other way).
@complete "complete-brew"
export extern main [...args]
