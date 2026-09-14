---
name: completion
description: Teach Tab a command-line tool. Builds completions/<tool>.nu for this Nushell config the way brew.nu and git.nu work - every subcommand and flag, flag values, and live positionals (branches, packages, containers, hosts) read from the tool's own data, measured in milliseconds, carapace as the fallback. Use when asked to add, generate, fix or extend completion for a CLI ("agent completion gh", "complete cargo", "make docker Tab-able", "uv install has no package completion").
argument-hint: <tool> [what matters most, e.g. "packages with descriptions"]
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, WebFetch, WebSearch, mcp__nu
---

# Completion for a tool

Input: `$0` is the tool; anything after it is a hint about what to get right
first. Skill files: `${CLAUDE_SKILL_DIR}` (scripts in `scripts/`, catalogues
in `references/`). The repo: `${CLAUDE_PROJECT_DIR}`. Its engine is
`modules/nu-complete/engine.nu`; the two finished examples are
`completions/brew.nu` (data read from files the tool maintains, a SQLite
cache built in the background) and `completions/git.nu` (one cheap command
per source, memoised for seconds). Read both before writing anything: the
new module must look like them.

The deliverable is `completions/<tool>.nu`, wired in `conf/completions.nu`,
verified headless, its costs measured, documented in `docs/completion.md`.
Not a nu_scripts-style pile of `export extern` lines: those give flags but
never positionals, never carapace fallback, and never the smart menu.

## What "smart" means here

| Slot | Must offer | Never |
|---|---|---|
| `tool ⌶` | subcommands with one-line descriptions, aliases included | files |
| `tool sub -⌶` | that subcommand's flags plus the global ones, `-s` and `--long` | only the root flags |
| `tool sub --flag ⌶`, `--flag=⌶` | the flag's values: an enum from help, or a live list | files, unless the flag takes a path |
| `tool sub ⌶` (positional) | what the argument *is*: branches, formulae, containers, hosts, targets, scripts, with a description column | every file in the directory, unless the argument is a path |
| anything the spec has no opinion on | carapace's answer (`fallback: "external"`) | nothing |

Speed is part of correctness: the menu source runs on every keystroke. A
source answers in single-digit milliseconds from memo or disk; the one-off
build of a big list runs in a background job; nothing spawns the tool's
Ruby/Python/JVM on the Tab path.

## Procedure

Work through every step. Do not skip verification because the module
"looks right": a completer that errors is silent, Nushell just shows files.

### 1. Discover (2 min)

```nu
nu ${CLAUDE_SKILL_DIR}/scripts/discover.nu <tool> --online
```

Read `recommended`: it orders the sources that exist for this tool.
`existing.spec` set means extend that file, do not start over. Load
`references/discovery.md` for what each source looks like and how to read
it; it also lists what is installed on this machine.

### 2. Collect the command surface (5 min)

Run the drafts the discovery named and save each to `/tmp` or the
session scratchpad (never into the repo):

| Source | Command | Gives |
|---|---|---|
| cobra program (`cobra.ok`) | `nu scripts/cobra-tree.nu <tool> --depth 3` | every subcommand incl. hidden, flags, enum values of valued flags, whether each leaf positional is dynamic (`positional.directive`, `sample`) |
| shipped or generated fish file | `nu scripts/fish-spec.nu <tool>` or `<tool> <gen> fish \| nu scripts/fish-spec.nu --stdin <tool>` | subcommands, flags with `arg`/`files`/`values`, and the **dynamic sources verbatim** (`dynamic: ["(__fish_complete_directories)"]`, `(brew formulae)`) |
| help text (always) | `nu scripts/help-tree.nu <tool> --depth 3` | subcommands, flags with types and `[possible values]`, positional names from the usage line (`args`), aliases |
| native nushell generator (`native.nushell`) | run it, read it | a clap tool's complete static surface as externs; mine it for enums and types, do not install it |
| zsh file (`shipped.zsh`) | read the `_<tool>_<name>()` bodies | the command behind each dynamic helper |
| carapace | `carapace <tool> nushell <tool> sub ""` | an oracle for coverage, and a fallback |
| nu_scripts (`nu_scripts.url`) | WebFetch it | ready `nu-complete <tool> <x>` closures to copy |

`--depth`/`--at "pr list"` bound the walk; cobra tools spawn ~60 ms per
node (gh at depth 3 is ~60 s), clap tools are instant. Merge into one
picture: subcommand tree, per node flags (name, short, description,
takes-value, values), per node positionals (name, rest, optional) with a
hint of what they are.

### 3. Map every positional and valued flag to a source (the real work)

For each positional / valued flag decide, in this order:

1. **Enum** (`values` from help, fish `-a "a b c"`, cobra probe): a literal list.
2. **A file the tool maintains**: registry caches, config files, refs. Read
   it; 1-5 ms. `references/sources.md` has the catalogue with paths and
   measured costs (git refs, brew API cache, cargo metadata, npm
   package.json, ssh config, kube contexts, launchd, tmux …).
3. **One cheap command of the tool** (10-50 ms): `git for-each-ref`,
   `cargo metadata --no-deps`, `docker ps --format json`, `just --summary`.
   Memoise with `nu-complete cache "<tool>:<what>:<scope>" <ttl> { … }`.
4. **Big lists** (thousands): build a SQLite file under `nu-complete cache-dir`
   in a `job spawn`, serve names without descriptions until it is ready,
   regenerate when the source is newer (`nu-complete stale`). brew.nu is the
   pattern; copy it.
5. **The tool's own completion engine** for what nothing local answers:
   cobra `__complete` (50 ms + whatever it does), clap `COMPLETE=fish`,
   `carapace --macro tools.<x>.<Y> ""`. Acceptable for slots hit rarely.
6. **Network** (`gh pr list`, registries): only if the hint asked for it;
   memoise minutes, never on the root slot.
7. **`"files"`** when the argument is a path; **`[]`** when the slot should
   offer nothing (an id the user types).
8. Otherwise leave the slot undefined so `fallback: "external"` asks
   carapace.

Every closure returns `{value, description}` records (a description
column is what makes the menu readable), reads `$ctx.args` for flags that
narrow the slot (`--cask`), and never runs the tool's slow path. Measure
each source with `timeit` before accepting it; write the number in a
comment.

Aliases: the engine has no alias notion. Add the alias as its own
subcommand node copied from the target (`co: ($subs.checkout | update
description "alias of pr checkout")`).

### 4. Write `completions/<tool>.nu`

Use the template in `references/module-template.md` and its gotchas list
(it exists because each item cost an hour once). Rules from `CLAUDE.md`
apply: no hard-coded home directory (`$nu.home-dir`, `$env.HOMEBREW_PREFIX?`),
`%open` for files, `which` guards, comments say why and quote measured
costs. Big static trees (hundreds of flags) go to
`completions/data/<tool>.json` written by the draft script's `--json`
output and loaded lazily, with the generating command in the module header;
small ones are a literal record in the module. `flags` of a node may be a
closure when the list is slow to get.

### 5. Wire and verify

1. `use <tool>.nu *` in `conf/completions.nu`, next to brew and git, with a
   one-line comment of what completes.
2. `nu-check config.nu` and `nu -l -c 'nu-config doctor'` both clean.
3. Headless, before trusting anything:
   ```nu
   nu -l -c '"<tool> " | commandline complete --detailed | first 5'
   nu -l -c '"<tool> sub " | commandline complete --detailed | select value description | first 5'
   nu -l -c '"<tool> sub --" | commandline complete --detailed | length'
   nu -l -c 'timeit { "<tool> sub " | commandline complete --detailed }'
   ```
   The inner call, not the completer wrapper, when a slot returns files
   unexpectedly: `nu -l -c 'nu-complete run (nu-complete <tool> spec) [<tool> sub ""]'`
   shows the error the `try` swallows.
4. Write a case file (scratchpad) for the slots the hint cared about plus
   one per subcommand, and run the verifier; it fails on any miss and on
   files where none belong:
   ```nu
   nu ${CLAUDE_SKILL_DIR}/scripts/verify.nu <tool>                       # auto cases
   nu ${CLAUDE_SKILL_DIR}/scripts/verify.nu <tool> --cases cases.nuon --oracle carapace
   ```
   `carapace_only` lists what carapace knows that the spec does not: each
   entry is either a flag to add or a slot to leave to the fallback.
5. `nu -l -c 'nu-config startup-time'` must stay within noise of before
   (record both numbers). A module that costs more than ~3 ms to parse is
   too big for a literal: move data to JSON.
6. `nu --ide-complete` does not run `@complete`: never use it as evidence.

### 6. Document and report

- Module header: what each source reads, measured Tab costs, what falls to
  carapace, known limits.
- `docs/completion.md`: a row in the tools table (add the table if it is
  not there yet) and the new costs.
- Final report to the user: which slots complete from what, the measured
  costs (first Tab, again), what still goes to carapace, what was not
  possible and why, and the line to load it in the current shell:
  `use <tool>.nu *`.

## When things do not fit

- Tool not on PATH: stop, say so.
- No help, no completions, not in carapace (`recommended` empty beyond
  help): a spec with subcommands from help and `fallback: "external"` is
  still worth it; say what is missing.
- Tool with one positional and no subcommands (`rg`, `fd`): flags with
  values are the whole job; enums from help; positional `"files"`.
- The tool prints help to stderr with a non-zero exit (`uv`, `rustup`,
  `npm --help` exits 1): the scripts already read both streams.
- A source needs the network or is slower than 100 ms: memoise, keep it
  off the root slot, mention it in the report.
