# Completion: how Tab works here, and how to teach it a new tool

Verified against Nushell 0.115.1 on 2026-09-10 and against 0.115.2 (the
unified completer inputs, #18791) on 2026-09-19; it runs on both. Every cost
below was measured with `timeit` or `hyperfine` on this machine; nothing is
estimated.

## Why not just carapace

Carapace covers ~1000 CLIs and stays as the fallback, but it asks the tool
each time: `brew install <Tab>` took **1.6 s** (it runs Ruby), `git checkout`
60 ms. The data those tools need is already on disk; reading it takes
milliseconds. And carapace, like Nushell's own completer, sees one command at
a time, so it can never know that `ls | where <Tab>` should offer `name`,
`type`, `size`, `modified`.

## Three layers

```
Tab
 └─ smart_menu ── source: nu-complete smart <buffer-up-to-cursor> <cursor>   (modules/nu-complete/smart.nu)
      ├─ 1. commandline complete --detailed          Nushell's own answer, 0.1-0.6 ms
      │      ├─ built-ins, flags, cell paths of known values, files
      │      ├─ @complete externs: brew, git ...     (completions/*.nu, via engine.nu)
      │      │     └─ fallback: external              carapace, for what the spec does not know
      │      └─ carapace for every other external
      └─ 2. rewrite that answer with what only the whole line reveals
             columns / operators / values, no files after `ps`, no duplicates
```

**Layer 1 — Nushell.** Unchanged. It still does most of the work and is what
`nu --ide-complete` and the LSP use.

**Layer 2 — specs for tools** (`modules/nu-complete/engine.nu`). Nushell 0.115
added the command-wide completer attribute: `@complete "name"` before an
`extern` hands `name` the whole argument list. `nu-complete spans` turns what
it is handed — one record on a build with #18791, one positional list on
0.115.1 — into the span list (command name, every argument, the partial
token), and `nu-complete run <spec> <spans>` walks it through a spec — subcommands, flags with values, positionals,
rest — and asks the right *source* for candidates. Sources read the tool's
own files or run one cheap command, and cache through `nu-complete cache`.
Specs work everywhere Nushell completes, including editors.

**Layer 3 — the smart menu** (`modules/nu-complete/smart.nu`). A custom
Reedline menu is the only place that receives the whole buffer: a
per-argument completer's `context` is just the current command (`get na`,
not `ls | get na`), a `@complete` completer gets only its own spans, and
`commandline` is empty while completing (all verified). The source starts
from `commandline complete --detailed` — records with value, span,
description, style, kind — and rewrites:

| Situation | What you get | How |
|---|---|---|
| `ls \| where ⌶`, `get`, `select`, `sort-by`, `update`, `str trim` … (any cell-path or condition slot; 78 built-ins) | columns, typed, with a sample: `size  filesize · 6.5 kB` | the pipeline before the command runs in a subprocess, `describe --detailed` |
| `open x.json \| get package.⌶`, `each {\|r\| $r.⌶}`, `where $it.⌶` | nested columns | same, with `get package` appended |
| `ls \| where size ⌶` | only operators valid for a filesize | Nushell's operator list, narrowed by the column's type |
| `ls \| where type == ⌶` | `file`, `dir` | distinct values of the column, as Nushell literals |
| `where … and ⌶` | columns again | |
| `ps ⌶`, `version ⌶` (216 built-ins take no positional) | nothing, instead of every file in the directory | signature says no positional at this slot |
| `first ⌶`, `skip ⌶` | nothing, instead of files | slot wants a number |
| `cd ⌶` in a folder with no subfolders, `cd nus⌶` with no local match | `..`, `~`, `-`, then zoxide's most-used directories (`~/.config/nushell` …) | slot wants a directory and Nushell found none; `zoxide query -l`, 12 ms, memoised 30 s |
| a shadowed built-in | listed once | `uniq-by value` |
| `ll \| where ⌶` | works | aliases are expanded before the pipeline runs |
| everything else | exactly Nushell's answer | |

### Running the pipeline: what is allowed

Column and value completion need the pipeline's output, so `ls | sort-by
size -r` is executed — in a subprocess (`nu -n -c`, **20 ms**, memoised in
`stor` for 45 s per directory and line) and only when `safe-to-eval` says
yes. It tokenises the prefix with `ast --flatten` (0.5 ms, lists calls
inside closures too) and requires every call to be a built-in in a read-only
category (filters, strings, conversions, math, date, path, formats …) or on a
short allow-list (`ps`, `sys *`, `ls`, `open`, `glob`, `du`, `which`,
`version`, `history`, `each`, `do`, `if` …). Any external, any redirection,
any garbage token, and an explicit never-list (`rm`, `save`, `into sqlite`,
`stor export`, `input`, `sleep`, `source`, `use`, `job spawn` …) refuse. The
knob (shipped in `defaults.nu`, overridden in your `settings.nu`):

```nu
$env.NU_COMPLETE_EVAL = "safe"   # built-ins only (default)
                       "all"    # your own commands too, via `nu -l -c` (~80 ms)
                       "off"    # never run anything; Tab still filters and dedupes
```

When the pipeline yields no rows right now (`where` matched nothing), the
columns come from the pipeline without its last stage.

A command whose columns are known without running it can register a
*provider* instead: `$env.NU_COMPLETE_PROVIDERS = { odata: {|segment| …} }`
(`modules/odata`, in its `activate`). `probe` hands the provider the first segment and expects
the same `[{ columns: { name: { type, value, detailed_type, description? } } }]`
rows `describe --detailed` would give — several rows when a column has a
fixed set of values (enum members), a `description` when words beat a
sample. Memoised 30 s per prefix. `odata People | where ⌶` answers in
3-4 ms from the cached `$metadata`, with no request (modules/odata/README.md).

### Costs

| Tab on | first time | again |
|---|---|---|
| `ls \| where ` | 28 ms (subprocess) | 2.7 ms |
| `ps \| where ` | 150 ms (`ps` itself is slow) | 2 ms |
| `brew install rip` | 3-5 ms (after a one-off 0.7 s cache build, in the background) | 3 ms |
| `brew install ` (2000 candidates) | 14 ms | |
| `git ` | 32 ms (`git help -a`) | 4 ms |
| `git checkout ` | 15-220 ms (`git status`, repo size) | 5 ms |
| `git log --one` | 60 ms (carapace) | |
| `cargo ` | 28 ms (`cargo --list`) | 4 ms |
| `cargo build -p ` (workspace members, targets, features) | 31-64 ms (`cargo metadata --no-deps` + `cargo build --help`) | 6 ms |
| `cargo add ser` (1.5k crate names from the registry cache) | 80 ms, then memoised for a day | 18 ms |
| `cargo update ` (562 lockfile packages) | 32 ms | 6 ms |
| command signatures table | 115 ms, built by a background job at startup | 0.1 ms per lookup |

The menu source runs again on every keystroke while the menu is open, which
is why everything is memoised and why the source never runs an external
itself.

## Tools with a spec

| Tool | Module | Subcommands and flags | Positionals and flag values | Left to carapace |
|---|---|---|---|---|
| brew | `completions/brew.nu` | Homebrew's zsh completion, parsed once to JSON | formulae and casks with descriptions (SQLite from the API cache), installed, taps | nothing it knows better |
| git | `completions/git.nu` | `git help -a`, `git <cmd> -h` | refs by recency, changed files, remotes, stashes | config keys, rev ranges, uncommon flags |
| cargo | `completions/cargo.nu` | `cargo --list` (aliases too), `cargo <cmd> --help` parsed lazily, nested `Commands:` (report, nextest …) | `-p`/`--bin`/`--example`/`--test`/`--bench`/`-F` from `cargo metadata --no-deps`, `--profile` from Cargo.toml, `--target` from rustup, `add`/`install` crate names from the registry cache, `remove` deps, `update`/`tree -i` lockfile, `uninstall` from `.crates.toml`, `+toolchain` | `--config`, `test <name>` (offers nothing), anything else undefined |

## The spec format

A spec is a record; `engine.nu` documents it in full. The shape:

```nu
{
  description: "…"
  flags: [ { name: "--cask", short: "-c", description: "…", arg: <source> } ]   # or a closure returning that
  positionals: [ <source> <source> ]     # 1st, 2nd … positional
  rest: <source>                         # every positional after those
  subcommands: { install: { <same shape> } }
  fallback: "external"                   # carapace when the spec has no answer
  sources: { formulae: {|ctx| … } }      # named sources, so the rest can be JSON
}
```

A `<source>` is a list of strings or `{value, description, style}` records, a
closure `{|ctx| …}` (`ctx` = `{spans, partial, args, positionals, path}`),
the string `"files"` for Nushell's path completion, or the name of an entry
in `sources`. The engine filters with the user's `completions.algorithm` and
`case_sensitive` — Nushell does not filter command-wide completer output.

## Adding a tool

1. Find where the tool already keeps what you need. In order of preference:
   a file it maintains (Homebrew's API cache, git's refs), a shell completion
   it ships (`/opt/homebrew/completions/zsh/_brew` gave every subcommand, flag
   and positional kind), one cheap subcommand (`git help -a`, `git <cmd> -h`),
   and only then `--help` scraping or carapace.
2. Write `completions/<tool>.nu`:

   ```nu
   use nu-complete *
   def spec [] { { description: "…", fallback: "external", subcommands: { … } } }
   def complete-tool [token, place?, buffer?] {
     try { nu-complete run (spec) (nu-complete spans $token (try { $place }) (try { $buffer })) } catch { null }
   }
   @complete "complete-tool"
   export extern main [...args]      # `main`: a module cannot export an extern of its own name
   ```

   Cache anything slower than a few milliseconds:
   `nu-complete cache "key" 5sec { … }` (session, `stor`) for small results;
   a SQLite file under `nu-complete cache-dir` built with `into sqlite` for
   big lists (`open x.db | query db "… like 'fo%'"` answers 16k rows in
   1-3 ms; `stor import` would wipe the session caches). Regenerate when the
   tool's file is newer (`nu-complete stale target source`); build in a
   `job spawn` and serve something simpler meanwhile, as brew.nu does.
3. `use <tool>.nu *` — in `conf/completions.nu` for a module the distro ships,
   in your own `settings.nu` for one of yours.
4. Test without a terminal:

   ```nu
   nu -l -c '"brew install rip" | commandline complete --detailed'
   nu -l -c 'nu-complete smart "ls | where " 11'
   ```

   `nu --ide-complete` does not run `@complete` completers, so it cannot test
   layer 2. For the real thing, the pty harness in the session scratchpad
   (`nupty.py`) drives an interactive `nu` and prints what the menu showed;
   it answers Reedline's cursor-position query (`ESC[6n`), without which
   `nu` never prints a prompt in a pty.

## Automating it: `agent completion <tool>`

`agent completion gh` runs the `completion` skill
(`.claude/skills/completion/SKILL.md`) on a Claude session of its own. The
deterministic parts are scripts, runnable by hand:

```nu
nu .claude/skills/completion/scripts/discover.nu gh --online   # which sources exist, in order (≈1 s)
nu .claude/skills/completion/scripts/cobra-tree.nu gh --at pr  # a cobra tool's tree via `gh __complete` (hidden subcommands, flag enums, dynamic positionals)
nu .claude/skills/completion/scripts/fish-spec.nu uv           # a fish completion file → draft spec (uv: 3902 lines in 3 s)
nu .claude/skills/completion/scripts/help-tree.nu cargo        # recursive --help → draft spec (clap, cobra, argparse, git layouts)
nu .claude/skills/completion/scripts/verify.nu git --oracle carapace   # every subcommand slot through `commandline complete`, timed, diffed against carapace
```

The skill's judgement lives in `references/`: `discovery.md` (what each
source looks like and how to read it, verified on this machine),
`sources.md` (positional kind → cheapest local data, with measured costs
and TTLs), `module-template.md` (the module shape, the spec semantics,
the gotchas). What comes out is a module in the shape of brew.nu and
git.nu, a `use` line here, and a verification run; the report names the
cost of each slot.

## Debugging

- `nu-config doctor` → the Completion section: knobs and cache ages.
- `nu-complete status`, `nu-complete cache clear`.
- `nu-complete brew spec-data | get subcommands.install`,
  `nu-complete git spec | get subcommands.checkout`,
  `nu-complete cargo spec build | get subcommands.build.flags | do $in`.
- A completer that errors is silent: Nushell falls back to files. Wrap the
  body in `try { … } catch { null }` on purpose, and test the inner command
  directly with `commandline complete`.
- "NO RECORDS FOUND" under the prompt is Reedline's message for an empty
  menu, not an error.

## The unified completer inputs

Nushell [#18791](https://github.com/nushell/nushell/pull/18791) ("unify
completer inputs and output contracts") merged upstream on 2026-09-09 and is in
every build after 0.115.1. Every completer — per-argument, `@complete`, the
external closure and a menu `source` — is handed one record whose fields bind
to the parameters it **names**: `token` (`{text, kind, span}`), `place`
(`{cursor, target, kind, flag?, index?, shape?}`) and `buffer`. Whether a given
binary has it: `nu -n -c 'attr interactive'`, exit 0 → yes.

This config is migrated and still runs on 0.115.1. Three signatures changed:

| Where | Now | What 0.115.1 puts there |
|---|---|---|
| `completions/*.nu` | `def complete-<tool> [token, place?, buffer?]` | the old span list in `token` |
| `conf/completions.nu` | `source: {\|buffer, place\| nu-complete smart $buffer $place }` | the line up to the cursor, and the old position int |
| the generated `vendor/autoload/carapace.nu` | a wrapper appended by `nu-config tools setup`, because carapace still generates `{\|spans\| …}` | the same wrapper, taking the same path |

`nu-complete spans` in `engine.nu` is the single place the two releases meet:
it returns 0.115.1's span list unchanged, and on a newer build rebuilds the
same list from `buffer` — `ast --flatten` for quote-aware tokens (30 µs),
`place.target.start` for where the token under the cursor begins, the last
command head before it for where this command's tokens start. It was checked
token for token against 0.115.1's real spans over quoted arguments,
`--flag=value`, pipelines, `;`, a fresh slot and an unterminated quote.

**The trap.** 0.115.1 does not hand the parameters it does not know a null —
it never binds them, so naming `$place` there is `variable not found` at
runtime, and a completer that errors is silent: Nushell shows files. That is
why every call site reads `(try { $place })`, and why the same guards appear in
the carapace wrapper.

What the new inputs bought, and what they did not:

- **No deprecation warnings.** The bridge for the old shapes queues one per
  session, printed in the REPL once the line editor hands back the line. Every
  slot in this config — externs, the menu, carapace's own closure — is off it.
- `place.target` is the exact range a suggestion replaces. `smart.nu` still
  computes its own (`replace-span`, four call sites): it is correct, and the
  menu path would need the same arithmetic for the items it invents. Worth
  revisiting, not urgent.
- `options.filter: true` still does **not** narrow a command-wide completer's
  output in the merged build — the flag is read, but the narrowing matches
  against an empty prefix. `nu-complete filter` stays.
- `fallback: true` in the returned envelope is **not** "chain to carapace",
  which is what the PR description reads like and what this file claimed
  before it was measured. For a *declared* extern it means "and also what
  Nushell would have offered", which is file completion; the external
  completer is never consulted. Measured: a completer returning
  `{completions: [], fallback: true}` with an external completer set offers
  files and never carapace, on the same line where an undeclared command does
  reach it. `nu-complete external` goes on calling carapace by hand, and the
  `answered` bookkeeping in `nu-complete run` stays with it.
- `@interactive` runs a completer on the line-editor thread with the terminal,
  so a slot with thousands of candidates (`brew install`) could offer an `fzf`
  picker instead of a columnar menu. Unbuilt.
- `commandline complete --input` returns the three inputs without running a
  completer, which is the fastest way to see what a slot actually looks like:

  ```nu
  nu -l -c '"git switch ma" | commandline complete --input'
  # {token: {text: ma, kind: value, span: {start: 11, end: 13}},
  #  place: {cursor: 13, target: {start: 11, end: 13}, kind: positional, index: 0, shape: any},
  #  buffer: "git switch ma"}
  ```

## Known limits

- The first Tab in a session pays the signature table (115 ms) unless the
  background job has finished, and the first `ps | …` pays `ps` (150 ms).
- Externals are never run for column completion, so `^git log | lines |
  where ⌶` gets no columns. `NU_COMPLETE_EVAL = "all"` widens to your own
  commands, not to externals.
- `git <cmd> -h` lists the common flags only; carapace fills the rest on a
  miss (`git log --one` → `--oneline`).
- The `--taps`/`--version` blocks of the zsh file are not subcommands and
  are skipped.
