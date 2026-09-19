# cargo — workspace-aware completion for cargo
#
# Carapace knows cargo's flags but its package/target/feature slots fail here
# (`cargo build -p <Tab>` → "exit status 101", measured 2026-09-11), and it
# never reads the workspace. Everything below comes from cargo's own data:
#
#   subcommands, aliases     `cargo --list`                       26 ms, memoised 1 h
#   flags of a subcommand    `cargo <cmd> --help`, parsed          32 ms, memoised 1 h
#     (also nested commands of `cargo report`, `cargo nextest` …)
#   packages, targets,       `cargo metadata --no-deps`            57 ms, memoised 10 s per workspace
#     features, dependencies   (bins, examples, tests, benches)
#   lockfile packages        Cargo.lock (`update`, `tree -i`)      1.5 ms
#   profiles                 dev/release/test/bench + [profile.*] of the root Cargo.toml
#   crate names              ~/.cargo/registry cache + sparse index cache   36 ms, memoised 1 day
#     (`add`, `install`: every crate this machine has ever fetched, 1.5k here)
#   installed binaries       ~/.cargo/.crates.toml (`uninstall`)   <1 ms
#   target triples           `rustup target list --installed`      24 ms, memoised 1 h
#   toolchains               `rustup toolchain list` for `cargo +<Tab>`
#
# Measured on 2026-09-11 in a 4-crate workspace: `cargo build -p <Tab>` 31-64 ms
# first (metadata + the help of `build`), 6 ms again; `cargo <Tab>` 28 ms
# then 4 ms; `cargo add ser<Tab>` 80 ms once a day, 18 ms after (filtering
# 1.5k names). Parsing this module costs 6 ms (git.nu: 3 ms). Outside a
# workspace the package/target/feature slots offer nothing. Slots the spec
# does not know (`--config`, third-party positionals) go to carapace via
# `fallback: external`; `cargo test <name>` and `cargo search` offer nothing
# on purpose (a test list needs a build; search needs the network).

use nu-complete *

# ── Sources ───────────────────────────────────────────────────────────────────

def --wrapped cargo-out [...args: string]: nothing -> list<string> {
  let r = (^cargo ...$args | complete)
  if $r.exit_code != 0 { [] } else { $r.stdout | lines }
}

# Nearest Cargo.toml above the current directory, or null (path checks only).
def project-root []: nothing -> any {
  mut d = $env.PWD
  mut hit: any = null
  while $hit == null and $d != ($d | path dirname) {
    if ($d | path join Cargo.toml | path exists) { $hit = $d } else { $d = ($d | path dirname) }
  }
  $hit
}

# Workspace members with their targets, features and dependencies.
# `cargo metadata --no-deps` costs 57 ms (the full graph takes 660 ms), so it
# is memoised for 10 s and the record kept small enough for stor.
def metadata []: nothing -> list<record> {
  let root = (project-root)
  if $root == null { return [] }
  nu-complete cache $"cargo:metadata:($root)" 10sec {
    let r = (^cargo metadata --no-deps --format-version 1 --manifest-path ($root | path join Cargo.toml) | complete)
    if $r.exit_code != 0 { [] } else {
      $r.stdout | from json | get packages | each {|p|
        {
          name: $p.name
          version: $p.version
          description: ($p.description? | default "" | str substring 0..70)
          targets: ($p.targets | each {|t| { name: $t.name, kind: $t.kind } })
          features: ($p.features | columns)
          dependencies: ($p.dependencies | each {|d| { name: $d.name, req: $d.req, kind: ($d.kind? | default "normal") } })
        }
      }
    }
  }
}

# `-p foo` typed before this slot narrows targets and features to that package.
def chosen-packages [ctx: record]: nothing -> list<record> {
  let all = (metadata)
  let picked = ($ctx.args | enumerate | where item in ["-p" "--package"] | each {|e| $ctx.args | get -o ($e.index + 1) } | compact)
  let picked = ($picked ++ ($ctx.args | where $it =~ '^(-p|--package)=' | each {|a| $a | split row "=" | last }))
  if ($picked | is-empty) { $all } else { $all | where name in $picked }
}

def packages []: nothing -> list<record> {
  metadata | each {|p| { value: $p.name, description: $"($p.version) · ($p.description)" } }
}

# Targets of one kind: bin, example, test, bench (a target lists its kinds).
def targets [kind: string, ctx: record]: nothing -> list<record> {
  chosen-packages $ctx | each {|p|
    $p.targets | where {|t| $kind in $t.kind } | each {|t| { value: $t.name, description: $"($kind) of ($p.name)" } }
  } | flatten
}

def features [ctx: record]: nothing -> list<record> {
  chosen-packages $ctx | each {|p|
    $p.features | each {|f| { value: $f, description: $"feature of ($p.name)" } }
  } | flatten | uniq-by value
}

# Direct dependencies of the workspace (what `cargo remove` can take).
def dependencies [ctx: record]: nothing -> list<record> {
  chosen-packages $ctx | each {|p|
    $p.dependencies | each {|d| { value: $d.name, description: $"($d.req) · ($d.kind) dep of ($p.name)" } }
  } | flatten | uniq-by value
}

# Every package in Cargo.lock: what `update`, `tree -i`, `pkgid` address.
# A regex over the raw file: 1.5 ms for 562 packages (`from toml` takes 6.5 ms).
def lock-packages []: nothing -> list<record> {
  let root = (project-root)
  if $root == null { return [] }
  let lock = ($root | path join Cargo.lock)
  if not ($lock | path exists) { return (packages) }
  nu-complete cache $"cargo:lock:($root)" 10sec {
    %open --raw $lock | parse --regex '(?m)^name = "(?<value>[^"]+)"\nversion = "(?<description>[^"]+)"' | uniq-by value
  }
}

def profiles []: nothing -> list<record> {
  let builtin = [
    { value: "dev", description: "built-in profile" }
    { value: "release", description: "built-in profile" }
    { value: "test", description: "built-in profile" }
    { value: "bench", description: "built-in profile" }
  ]
  let root = (project-root)
  if $root == null { return $builtin }
  let custom = (try { %open ($root | path join Cargo.toml) | get -o profile | default {} | columns } catch { [] })
  $builtin ++ ($custom | where $it not-in [dev release test bench] | each {|p| { value: $p, description: "[profile] in Cargo.toml" } })
}

# Crate names this machine has fetched: the `.crate` files in the registry
# cache plus the sparse-index cache entries. 36 ms to list, so memoised for a
# day (1.5k names decode from stor in 2 ms). Descriptions would need the
# network; `cargo info <crate>` has them but is not worth a request per Tab.
def crate-names []: nothing -> list<string> {
  nu-complete cache "cargo:crates" 1day {
    let reg = ($env.CARGO_HOME? | default ($nu.home-dir | path join .cargo) | path join registry)
    if not ($reg | path exists) { return [] }
    # Forward slashes: a backslash is an escape in a glob pattern.
    let reg = ($reg | str replace -a '\' '/')
    let cached = (glob $"($reg)/cache/*/*.crate" | path basename | str replace --regex '-[0-9][^-]*\.crate$' '')
    let indexed = (glob $"($reg)/index/*/.cache/**/*" --no-dir | path basename)
    $cached ++ $indexed | uniq | sort
  }
}

# `cargo install`ed binaries, from the file cargo keeps for `uninstall`.
def installed []: nothing -> list<record> {
  let f = ($env.CARGO_HOME? | default ($nu.home-dir | path join .cargo) | path join .crates.toml)
  if not ($f | path exists) { return [] }
  %open $f | get -o v1 | default {} | columns
  | parse --regex '^(?<value>\S+) (?<version>\S+) \((?<source>[^+]+)\+' | each {|r| { value: $r.value, description: $"($r.version) · ($r.source)" } }
}

def rustup-targets []: nothing -> list<string> {
  if (which rustup | is-empty) { return [] }
  nu-complete cache "cargo:targets" 1hr { ^rustup target list --installed | complete | get stdout | lines }
}

def toolchains []: nothing -> list<record> {
  if (which rustup | is-empty) { return [] }
  nu-complete cache "cargo:toolchains" 1hr {
    ^rustup toolchain list | complete | get stdout | lines
    | parse --regex '^(?<name>\S+)\s*(?<note>.*)$'
    | each {|t|
        # `stable-aarch64-apple-darwin (active, default)` → `+stable`
        let short = ($t.name | str replace --regex '-(aarch64|x86_64|i686|arm|riscv64)\S*$' '')
        { value: $"+($short)", description: ($t.name + " " + $t.note | str trim) }
      }
  }
}

# Registries named in ~/.cargo/config.toml, plus crates-io.
def registries []: nothing -> list<string> {
  let f = ($env.CARGO_HOME? | default ($nu.home-dir | path join .cargo) | path join config.toml)
  let named = if ($f | path exists) { try { %open $f | get -o registries | default {} | columns } catch { [] } } else { [] }
  ["crates-io"] ++ $named
}

# ── Command surface: `cargo --list` and `cargo <cmd> --help` ──────────────────

# Every subcommand with its description; aliases point at their target.
def subcommands []: nothing -> table<name: string, description: string, alias: string> {
  nu-complete cache "cargo:subcommands" 1hr {
    cargo-out --list | skip 1
    | parse --regex '^\s{4}(?<name>\S+)\s*(?<description>.*)$'
    | each {|c|
        let target = ($c.description | parse --regex '^alias: (?<t>\S+)$' | get -o 0.t | default "")
        { name: $c.name, description: (if $target == "" { $c.description } else { $"alias of ($target)" }), alias: $target }
      }
  }
}

# Flags and nested commands of `cargo <cmd> --help` (clap layout; continuation
# lines are joined, `[possible values: …]` becomes the flag's enum). Third-party
# subcommands (clippy, nextest, deny) print the same shape.
def help-of [cmd: string]: nothing -> record<flags: list, commands: list> {
  nu-complete cache $"cargo:help:($cmd)" 1hr {
    let r = (^cargo ...($cmd | split row " ") --help | complete)
    let all = ($r.stdout + (char nl) + $r.stderr | lines)
    # Continuation lines (indented deeper) join their flag line; `--help`
    # layouts (nextest) put the whole description on those lines.
    let blocks = ($all | reduce -f [] {|l, acc|
      if ($l =~ '^\s{2,6}-') { $acc ++ [$l] } else if ($l =~ '^\s{8,}\S') and ($acc | is-not-empty) {
        $acc | update (($acc | length) - 1) {|p| $p + "  " + ($l | str trim) }
      } else { $acc }
    })
    let flags = ($blocks
      | parse --regex '^\s+(?:(?<short>-[A-Za-z]),\s+)?(?<name>--?[\w-]+)(?:\.\.\.)?(?:[ =]\[?<(?<arg>[^>]+)>\]?(?:\.\.\.)?)?\s*(?<desc>.*)$'
      | uniq-by name
      | each {|f|
          let vals = ($f.desc | parse --regex '\[possible values: (?<v>[^\]]+)\]' | get -o 0.v | default "" | split row "," | str trim | where $it != "")
          let desc = ($f.desc | str replace --regex --all '\s*\[(possible values|default|env|aliases): [^\]]*\]' '' | str trim)
          { name: $f.name, short: $f.short, arg: $f.arg, values: $vals, description: $desc }
        })
    # `Commands:` block: `  name  description`, until the blank line.
    let start = ($all | enumerate | where item =~ '^Commands:' | get -o 0.index)
    let commands = if $start == null { [] } else {
      $all | skip ($start + 1) | take while {|l| $l !~ '^\s*$' }
      | parse --regex '^\s{2,4}(?<name>[\w-]+)(?:, (?<alias>\S+))?\s{2,}(?<description>.*)$'
      | each {|c| $c | update description ($c.description | str replace --regex '\s*\[aliases: [^\]]*\]' '') }
    }
    { flags: $flags, commands: $commands }
  }
}

# What a valued flag wants, by its name; enums from help win.
def flag-source [f: record]: nothing -> any {
  if ($f.values | is-not-empty) { return $f.values }
  match $f.name {
    "--package" | "-p" | "--exclude" => {|ctx| packages }
    "--bin" => {|ctx| targets bin $ctx }
    "--example" => {|ctx| targets example $ctx }
    "--test" => {|ctx| targets test $ctx }
    "--bench" => {|ctx| targets bench $ctx }
    "--features" | "-F" => {|ctx|
      # `-F a,b<Tab>`: complete the last element, keep the rest.
      let head = ($ctx.partial | str replace --regex '[^,]*$' '')
      features $ctx | each {|r| $r | update value ($head + $r.value) }
    }
    "--profile" => {|ctx| profiles }
    "--target" => {|ctx| rustup-targets }
    "--registry" => {|ctx| registries }
    "--prune" | "--invert" | "-i" => {|ctx| lock-packages }
    "--manifest-path" | "--path" | "--target-dir" | "--artifact-dir" | "--root" | "--out-dir" | "-C" => "files"
    "--edition" => [2015 2018 2021 2024]
    "--vcs" => [git hg pijul fossil none]
    "--explain" | "--config" | "--jobs" | "-j" | "--rename" | "--version" | "--token" => []
    _ => null
  }
}

def flags-of [cmd: string]: nothing -> list<record> {
  help-of $cmd | get flags | each {|f|
    let base = ({ name: $f.name, description: $f.description } | merge (if ($f.short | default "") == "" { {} } else { { short: $f.short } }))
    let src = (if ($f.arg | default "") == "" { null } else { flag-source $f })
    # `[<NAME>]` flags take an optional value: still consume the next token.
    if $src == null and ($f.arg | default "") != "" { $base | merge { arg: [] } } else if $src == null { $base } else { $base | merge { arg: $src } }
  }
}

# The positional plan: what each built-in subcommand's arguments are.
def positional-plan []: nothing -> record {
  let crates = {|ctx| crate-names }
  {
    add: { rest: $crates }
    install: { rest: $crates }
    remove: { rest: {|ctx| dependencies $ctx } }
    rm: { rest: {|ctx| dependencies $ctx } }
    uninstall: { rest: {|ctx| installed } }
    update: { rest: {|ctx| lock-packages } }
    pkgid: { positionals: [ {|ctx| lock-packages } ] }
    tree: { rest: [] }
    info: { positionals: [ $crates ] }
    help: { positionals: [ {|ctx| subcommands | each {|c| { value: $c.name, description: $c.description } } } ] }
    new: { positionals: [ "files" ] }
    init: { positionals: [ "files" ] }
    search: { positionals: [ [] ] }
    login: { positionals: [ [] ] }
    yank: { positionals: [ $crates ] }
    owner: { positionals: [ $crates ] }
    # A test / bench name filter needs a build to know; offer nothing, not files.
    test: { positionals: [ [] ], rest: [] }
    t: { positionals: [ [] ], rest: [] }
    bench: { positionals: [ [] ], rest: [] }
    run: { rest: "files" }
    r: { rest: "files" }
  }
}

# One node for `cargo <name>`: description from --list, flags from --help
# (lazily), nested commands from the same help when it has a `Commands:` block.
def node-for [name: string, description: string, deep: bool]: nothing -> record {
  let base = ({ description: $description, flags: {|| flags-of $name } } | merge ((positional-plan) | get -o $name | default {}))
  if not $deep { return $base }
  let nested = (help-of $name | get commands)
  if ($nested | is-empty) { $base } else {
    $base | merge { subcommands: ($nested | reduce -f {} {|c, acc|
      let sub = ({ description: $c.description, flags: {|| flags-of $"($name) ($c.name)" } })
      let acc = ($acc | upsert $c.name $sub)
      if ($c.alias | default "") == "" { $acc } else { $acc | upsert $c.alias ($sub | update description $"alias of ($c.name)") }
    }) }
  }
}

# ── The spec ──────────────────────────────────────────────────────────────────

# `focus` is the subcommand being typed: only its help is read (32 ms once),
# every other node stays a description plus a lazy flag closure.
export def "nu-complete cargo spec" [focus: string = ""]: nothing -> record {
  let subs = (subcommands | reduce -f {} {|c, acc|
    let real = if $c.alias == "" { $c.name } else { $c.alias }
    $acc | upsert $c.name (node-for $real $c.description ($c.name == $focus))
  })
  {
    description: "Rust's package manager"
    fallback: "external"
    flags: [
      { name: "--version", short: "-V", description: "Print version info and exit" }
      { name: "--list", description: "List installed commands" }
      { name: "--explain", description: "Explain a rustc error code", arg: [] }
      { name: "--verbose", short: "-v", description: "Use verbose output (-vv very verbose)" }
      { name: "--quiet", short: "-q", description: "Do not print cargo log messages" }
      { name: "--color", description: "Coloring", arg: [auto always never] }
      { name: "-C", description: "Change to DIRECTORY before doing anything (nightly)", arg: "files" }
      { name: "--locked", description: "Assert that Cargo.lock will remain unchanged" }
      { name: "--offline", description: "Run without accessing the network" }
      { name: "--frozen", description: "Both --locked and --offline" }
      { name: "--config", description: "Override a configuration value", arg: [] }
      { name: "-Z", description: "Unstable (nightly-only) flags, see `cargo -Z help`", arg: [] }
      { name: "--help", short: "-h", description: "Print help" }
    ]
    subcommands: $subs
  }
}

# `cargo +nightly build`: the toolchain token is not a flag and not a
# subcommand, so it is completed here and dropped before the spec runs.
def complete-cargo [token, place?, buffer?] {
  try {
    let spans = (nu-complete spans $token (try { $place }) (try { $buffer }))
    let partial = ($spans | last)
    if ($spans | length) == 2 and ($partial | str starts-with "+") {
      return (toolchains | nu-complete filter $partial)
    }
    let spans = if ($spans | length) > 2 and ($spans.1 | str starts-with "+") { [$spans.0] ++ ($spans | skip 2) } else { $spans }
    let focus = ($spans | get -o 1 | default "")
    nu-complete run (nu-complete cargo spec $focus) $spans
  } catch { null }
}

# `main` so that `use cargo.nu *` yields `cargo`.
@complete "complete-cargo"
export extern main [...args]
