# The module: template, spec semantics, gotchas

Verified against Nushell 0.115.1 and `modules/nu-complete/engine.nu` on
2026-09-11. Read `engine.nu` itself when in doubt: it is 180 lines and is
the truth.

`completions/README.md` in the repo is the same contract written for a
person, and is where a change to the module shape should land first; this
file is the working copy, with the draft-script and verifier detail the
README leaves out. If the two disagree, the README wins.

## Template

```nu
# <tool> — <one line: what completes, from where>
#
#   subcommands, flags   <source>            (<measured> ms, cached <ttl>)
#   <positional kind>    <source>            (<measured> ms)
#   …
# Anything the spec has no opinion on is handed to carapace
# (`fallback: external`). Generated data: `<command>` → completions/data/<tool>.json
# (only if a data file is used).

use nu-complete *

# ── Sources ───────────────────────────────────────────────────────────────────

def --wrapped tool-out [...args: string]: nothing -> list<string> {
  let r = (^<tool> ...$args | complete)
  if $r.exit_code != 0 { [] } else { $r.stdout | lines }
}

# Example: a list from one cheap command, memoised per directory.
def things []: nothing -> list<record> {
  nu-complete cache $"<tool>:things:($env.PWD)" 10sec {
    tool-out list --format json | str join | from json | each {|t| { value: $t.name, description: $t.what } }
  }
}

# ── The spec ──────────────────────────────────────────────────────────────────

export def "nu-complete <tool> spec" []: nothing -> record {
  {
    description: "<tool's own one-liner>"
    fallback: "external"
    flags: [
      { name: "--help", short: "-h", description: "Show help" }
      { name: "--config", description: "Config file", arg: "files" }
    ]
    sources: {
      things: {|ctx| things }
      kinds: [a b c]
    }
    subcommands: {
      list: { description: "List things", flags: [ { name: "--all", short: "-a", description: "…" } ] }
      show: { description: "Show a thing", positionals: [ "things" ], flags: [ { name: "--format", description: "…", arg: [json text] } ] }
      rm:   { description: "Remove things", rest: "things" }
      cfg:  { description: "…", subcommands: { get: { positionals: [ [key1 key2] ] } } }
    }
  }
}

# null on any failure: Nushell then falls back to files instead of nothing.
def complete-<tool> [spans: list<string>] { try { nu-complete run (nu-complete <tool> spec) $spans } catch { null } }

# `main`: a module cannot export an extern of its own name; `use <tool>.nu *` yields `<tool>`.
@complete "complete-<tool>"
export extern main [...args]
```

For a big static tree, keep the data in `completions/data/<tool>.json`
(the draft script's `--json` output, pruned to `description`, `flags`,
`subcommands`) and merge the sources in. JSON here and NUON everywhere else in
the distro is deliberate: 195 kB parses in 1.2 ms as JSON and 7.8 ms as NUON,
and this file is read on the Tab path (`docs/layout.md`, *Formats*).

```nu
const DATA = (path self | path dirname | path join data <tool>.json)
def spec-data []: nothing -> record { nu-complete cache "<tool>:spec" 1hr { %open $DATA } }
export def "nu-complete <tool> spec" []: nothing -> record {
  spec-data | merge { fallback: "external", sources: { … } }
  | update subcommands {|s| $s.subcommands | upsert show { $in | insert positionals [things] } }
}
```

`%open` of a 200 kB JSON is ~5 ms, once per hour per shell.

## Spec semantics (engine.nu)

- `spans` = `[tool, arg…, partial]`; the partial is `""` at a fresh slot.
- Walk: a token starting with `-` is a flag (root flags apply everywhere;
  a flag with `arg` consumes the next token, or `--flag=value`); the first
  non-flag token that names a subcommand descends; the rest are positionals.
- `positionals: [src1 src2]` are the 1st, 2nd … positional; `rest` covers
  every later one. Missing → not answered → fallback.
- A `<source>`: a list (strings or `{value, description, style}`), a closure
  `{|ctx| …}` with `ctx = {spans, partial, args, positionals, path}`, the
  string `"files"` (Nushell's path completion), or a **name in `sources`**.
  An unknown name silently yields `[]`: names must exist.
- The engine filters by the user's algorithm/case setting; sources return
  everything (or pre-filter big lists on `$ctx.partial` for speed).
- `flags` may be a closure (no params) for lists that are slow to build.
- `fallback: "external"` on the root (or a node) asks carapace when the spec
  has no opinion, and also when a typed flag matches nothing (git -h lists
  only common flags).
- Returning `null` from the completer declines the slot to Nushell (files).

## Gotchas (each one cost time)

- **`else` on its own line does not parse**: `if … { } else { }` must keep
  `else` on the `}` line. Silent misparse until runtime, with an error far
  away.
- **A closure in a record literal is kept; `insert` would run it**: build
  nodes as literals (`{ flags: {|| flags-of $c } }`), see git.nu.
- **`$last`, `$in`-like names**: avoid variable names that are commands you
  pipe into on the same line; use `prev`.
- **`%open`**, never `open`: the user may alias `open` to the macOS opener;
  a module parsed after that alias would launch apps.
- **stor caches die with the shell, `stor import` wipes them**: big lists go
  to SQLite files under `nu-complete cache-dir`; `open x.db | query db "… like 'fo%'"`
  answers 16k rows in 1-3 ms.
- **`try { } catch { null }`** around the completer: an error is otherwise
  silent and Nushell shows files. Test the inner call directly.
- **Aliases**: engine has none. Copy the node under the alias name.
- **A node with `positionals` but the user typed a subcommand name first**:
  subcommands win only while no positional has been typed.
- **Descriptions**: strip `[env: …]`, `[default: …]`; keep them under ~80
  characters or the menu wraps.
- **Nushell 0.115 `str downcase`/`str upcase` are deprecated**: `str lowercase`, `str uppercase`.
- **`nu --ide-complete` cannot exercise `@complete`**; `commandline complete --detailed` can.
- **`nu -c` does not load the config**; `nu -l -c` does, without the autoload dirs (carapace is
  wired from vendor autoload, so under `nu -l -c` the external fallback is absent: a slot that
  shows nothing there may show carapace's answer in the REPL). To check the fallback headless,
  source the vendor file: `nu -l -c 'source ($nu.data-dir | path join vendor autoload carapace.nu); …'`.
- **Tools whose first positional is a path** (`touch`, `mkdir`): never probe
  `<tool> completion …`; discovery skips them.

## Test lines

```nu
nu -l -c '"<tool> " | commandline complete --detailed | first 5'
nu -l -c '"<tool> sub " | commandline complete --detailed | select value description | first 5'
nu -l -c '"<tool> sub --" | commandline complete --detailed | get value'
nu -l -c '"<tool> sub --flag " | commandline complete --detailed | get value'
nu -l -c 'nu-complete run (nu-complete <tool> spec) [<tool> sub ""]'      # the error the try hides
nu -l -c 'timeit { "<tool> sub " | commandline complete --detailed }'
nu -l -c 'nu-complete smart "<tool> sub " 12'                              # the Tab menu path
nu ${CLAUDE_SKILL_DIR}/scripts/verify.nu <tool> --cases cases.nuon --oracle carapace
```

A case file:

```nu
[
  { line: "gh pr ",             has: [checkout list view], no_files: true, max_ms: 30 }
  { line: "gh pr checkout ",    min: 1, no_files: true }
  { line: "gh pr list --state ", has: [open closed merged all] }
  { line: "gh repo clone ",     no_files: true }
]
```
