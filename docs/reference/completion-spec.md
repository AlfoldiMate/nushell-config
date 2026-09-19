# Completion specs: one module per tool

Each file in `completions/` teaches Tab one command-line tool.
`conf/completions.nu` is the only thing that loads them;
`modules/nu-complete/engine.nu` is the engine that runs them, and
[Completion](../concepts/completion.md) explains how the three completion
layers fit together. This page is the contract: what a module must look like,
what it may assume, and what it has to prove before it is wired in. Building
one, step by step, is [Add Tab completion for a tool](../cookbook/add-completion.md).

Verified against Nushell 0.115.1 and against 0.115.2, the first build with
the unified completer inputs; every module here runs on both.
The completer's own signature is the one place they differ — read [The
completer's input](#the-completers-input) before writing a new module.

## What a module owes you

A module is not a pile of `export extern` lines. Those give flags and nothing
else: no positionals, no flag values, no carapace fallback. A module here
answers every slot of the tool:

| Slot | Must offer | Never |
|---|---|---|
| `tool ⌶` | subcommands with one-line descriptions, aliases included | files |
| `tool sub -⌶` | that subcommand's flags **and** the global ones, `-s` and `--long` | only the root flags |
| `tool sub --flag ⌶`, `--flag=⌶` | the flag's values: an enum from `--help`, or a live list | files, unless the flag takes a path |
| `tool sub ⌶` | what the argument *is* — branches, formulae, containers, targets — with a description column | every file in the directory, unless the argument is a path |
| anything the spec has no opinion on | carapace's answer, via `fallback: "external"` | nothing |

Speed is part of correctness. The Tab menu source re-runs **on every keystroke
while the menu is open**, so every source answers in single-digit milliseconds
from memo or disk. Nothing on the Tab path may start the tool's Ruby, Python or
JVM. A one-off build of a big list belongs in a `job spawn`.

## The shape of a module

```nu
# <tool> — <one line: what completes, and from where>
#
#   subcommands, flags   `<tool> --help`, parsed once     (13 ms, cached for the session)
#   <positional kind>    <the file or command it reads>   (4 ms)
#
# Anything the spec has no opinion on goes to carapace (`fallback: external`).

use nu-complete *

# ── Sources ───────────────────────────────────────────────────────────────────

def --wrapped tool-out [...args: string]: nothing -> list<string> {
  let r = (^<tool> ...$args | complete)
  if $r.exit_code != 0 { [] } else { $r.stdout | lines }
}

def things []: nothing -> list<record> {
  nu-complete cache $"<tool>:things:($env.PWD)" 10sec {
    tool-out list --format json | str join | from json
    | each {|t| { value: $t.name, description: $t.what } }
  }
}

# ── The spec ──────────────────────────────────────────────────────────────────

export def "nu-complete <tool> spec" []: nothing -> record {
  {
    description: "<the tool's own one-liner>"
    fallback: "external"
    flags: [ { name: "--config", description: "Config file", arg: "files" } ]
    sources: { things: {|ctx| things } }
    subcommands: {
      list: { description: "List things", flags: [ { name: "--all", short: "-a", description: "…" } ] }
      show: { description: "Show a thing", positionals: [ "things" ] }
      rm:   { description: "Remove things", rest: "things" }
    }
  }
}

# `null` on any failure: Nushell then falls back to files rather than to nothing.
# The parameter names and the inner `try`s are load-bearing on both releases —
# see "The completer's input".
def complete-<tool> [token, place?, buffer?] {
  try { nu-complete run (nu-complete <tool> spec) (nu-complete spans $token (try { $place }) (try { $buffer })) } catch { null }
}

# `main`, because a module cannot export an extern of its own name:
# `use <tool>.nu *` then yields `<tool>`.
@complete "complete-<tool>"
export extern main [...args]
```

Three parts, always in this order: private sources, one exported `spec`
command, the completer and the extern. Exporting the spec is what makes
`nu-complete <tool> spec | get subcommands.install` a debugging session instead
of a guess.

### Big static trees

A tool with hundreds of subcommands and flags does not belong in a literal —
parsing it costs startup time on every shell. Put it in
`completions/data/<tool>.json`, name the generating command in the module
header, and load it lazily:

```nu
const DATA = (path self | path dirname | path join data <tool>.json)
def spec-data []: nothing -> record { nu-complete cache "<tool>:spec" 1hr { %open $DATA } }
```

JSON, and this is the one place in the distro that is not NUON. Measured on
`brew-spec.json`, 195 kB: **1.2 ms** to `open` as JSON, **7.8 ms** as NUON, 9.3 ms
as indented NUON — NUON's parser costs roughly 6x per byte at every size tried.
Nothing but the completer reads these files, and the Tab menu source re-runs on
every keystroke, so the fast format wins here and the rule bends. State a person
reads or edits stays NUON ([Files and formats](files.md)).

## What it costs to parse

`use` is parse-time: every module in `completions/` is read and compiled by every shell that
starts, whether or not you ever touch the tool. So the directory has a budget.

hyperfine, 40 runs, nu 0.115.2, σ ≤ 1.0 ms throughout — each figure is the
delta from the line above it:

| | |
|---|---|
| `nu -n -c ''`, nothing loaded | 12.4 ms |
| `use nu-complete *` | +9.0 ms — `cache.nu` 0.7, `engine.nu` 2.2, **`smart.nu` 6.1** |
| `use brew.nu *` | +2.6 ms |
| `use git.nu *` | +2.1 ms |
| `use cargo.nu *` | +3.2 ms |
| all three, measured in a real startup (`nu -l -c ''`, 53.3 ms → 42.9 ms with them commented out) | **10.4 ms** |

**The budget: 3 ms for a module, 20 ms for the directory.** At today's 10.4 ms
that leaves room for roughly four more tools.

Two things the numbers say that the guesses did not. Most of the cost is
**code, not data**: `brew.nu` keeps its whole subcommand tree in JSON and still
costs 2.6 ms, while `cargo.nu`, which has no static tree at all, costs the
most. So moving a literal to `completions/data/<tool>.json` buys less than it
looks like — do it when a literal is genuinely large (the JSON parser is ~6x
faster per byte than NUON's, measured above), not as a way under the budget.
And the module to watch is `smart.nu`, which is not a tool spec at all: it is
more than half of what completion costs a shell that never presses Tab.

If the directory ever does pass 20 ms, the way out is not a lazy module.
An `@complete` extern must exist at parse time to be attached to a command, so
the module cannot be deferred. A *spec* can: `nu-complete run` takes a plain
record, so a tool can live as `completions/data/<tool>.json` with no module and
no extern at all, dispatched on the first word of the line by the Tab menu
source — which is a runtime closure and already sees the whole line. That
trades ~2.5 ms at every startup for the cost of reading the spec on the Tab
presses that actually hit it — 1.2-1.7 ms for the 195 kB `brew-spec.json`,
measured above and again on 2026-09-19. Unbuilt, deliberately: the directory is
at half its budget.

## The spec format

A spec is a plain record, meant to be read and edited by a person.
`engine.nu` is 220 lines and is the truth; this is what it means.

```nu
{
  description: "…"                       # shown beside the subcommand
  flags: [ { name: "--cask", short: "-c", description: "…", arg: <source> } ]
  positionals: [ <source> <source> ]     # the 1st, 2nd … positional
  rest: <source>                         # every positional after those
  subcommands: { install: { <same shape> } }
  fallback: "external"                   # carapace, when the spec has no answer
  sources: { formulae: {|ctx| … } }      # named sources, so the rest can be JSON
}
```

How the engine walks a line:

- `nu-complete spans` hands the walk `[tool, arg…, partial]`, the partial
  being `""` at a fresh slot, whichever shape the release gave the completer.
- A token starting with `-` is a flag. Root flags apply everywhere; a flag with
  an `arg` consumes the next token, and `--flag=value` is understood.
- The first non-flag token that names a subcommand descends into it.
  **Subcommands only win while no positional has been typed yet.**
- Everything else is a positional: `positionals` covers them by index, `rest`
  covers the tail. A slot with no source is *unanswered* and goes to the
  fallback — which is different from a source returning `[]`, which means "this
  slot offers nothing".

A `<source>` is any of:

- a list of strings, or of `{value, description, style}` records;
- a closure `{|ctx| … }` where `ctx` is
  `{spans, partial, args, positionals, path}` — `positionals` being what has
  already been typed for this subcommand, `path` the subcommand chain;
- the string `"files"`, handing the slot to Nushell's own path completion;
- the name of an entry in the spec's `sources` record. **An unknown name
  silently yields `[]`**, so a typo here looks like a slot that offers nothing.

`flags` may itself be a closure taking no arguments, for a list that is slow to
build and only needed once a `-` is typed. Build such a node as a record
literal — `{ flags: {|| flags-of $c } }` — because `insert` would run the
closure instead of storing it. `completions/git.nu` does this per subcommand.

Two things the engine does not do. It has no notion of **aliases**: add the
alias as its own subcommand node copied from the target, with the description
rewritten (`co: ($subs.checkout | update description "alias of checkout")`). And
Nushell does not filter a command-wide completer's output, so the engine filters
itself, honouring the user's `completions.algorithm` and `case_sensitive` — your
sources return everything, or pre-filter on `$ctx.partial` when the list is big
enough that filtering it in Nu is the slow part.

## Choosing a source

For every positional and every valued flag, in this order:

1. **An enum** from `--help`, a fish file's `-a "a b c"`, or a cobra probe: a
   literal list. Free.
2. **A file the tool already maintains** — registry caches, config files, refs.
   1-5 ms, and there is no second cache to invalidate. Homebrew's
   `~/Library/Caches/Homebrew/api/formula_names.txt` answers `brew install` in
   4 ms; carapace takes 1.6 s for the same slot because it runs Ruby.
3. **One cheap command** (10-50 ms): `git for-each-ref`, `cargo metadata
   --no-deps`, `docker ps --format json`. Always memoised.
4. **A big list** (thousands of rows): build a SQLite file under
   `nu-complete cache-dir` in a `job spawn`, serve something simpler until it is
   ready, and rebuild when the source file is newer (`nu-complete stale`).
   `completions/brew.nu` is the pattern to copy.
5. **The tool's own completion engine** — cobra's `__complete`, clap's
   `COMPLETE=fish` — for what nothing local answers. Fine for slots hit rarely.
6. **The network**, only when asked for, memoised in minutes, never on the root
   slot.
7. **`"files"`** when the argument really is a path; **`[]`** when the slot
   should stay empty.
8. Otherwise leave the slot undefined and let `fallback: "external"` ask
   carapace.

Measure each source with `timeit` before accepting it and write the number in
the module header. "Fast enough" is not a measurement.

## Caching

Three tiers, all in `modules/nu-complete/cache.nu`:

```nu
nu-complete cache "<tool>:<what>:<scope>" 10sec { … }   # session memo, in `stor`
nu-complete cache-dir                                   # $nu.cache-dir/nu-complete, for files
nu-complete stale $target $source                       # rebuild when the source moved
```

The `stor` memo survives across completer calls and dies with the shell, which
is exactly the right lifetime for "branches in this repo". Keep the values
small: a few hundred records decode from NUON in about a millisecond, sixteen
thousand do not — those belong in a SQLite file, where `open x.db | query db "…
like 'fo%'"` answers 16k rows in 1-3 ms. Never use `stor import` from a
completion source: it wipes every other `stor` table, including the engine's
signature cache.

Scope the key by whatever the answer depends on — `$env.PWD` for anything
repository-local — and pick the TTL from how fast the truth moves: 5 s for
`git status`, 30 s for remotes, an hour for a parsed help tree, a day for a
registry index.

## Wiring it in

Where the line goes depends on whose module it is. Both directories are on
`NU_LIB_DIRS`, the user's first.

| The module is | It lives in | The `use` line goes in |
|---|---|---|
| shipped by the distro | `completions/` here | `conf/completions.nu`, next to the others, with a comment naming what completes |
| yours, or fetched (`nu-config fetch completion docker`) | `completions/` in your config dir | your own `settings.nu` |

```nu
use <tool>.nu *   # subcommands, flags, <the positionals that matter>
```

Nothing a user owns is written inside this checkout, so a module you did not
write goes in the second row even when you wrote it for a tool the distro
knows about; your `completions/` shadows this one by name.

`use` is parse-time, so it cannot sit inside `if (which <tool> | is-not-empty)`.
That is fine: an extern for a tool that is not installed only ever affects
completion, never execution.

## Proving it works

A completer that errors is **silent** — Nushell just shows files — so none of
this is optional, and "it looks right" is not evidence.

```nu
nu -l -c 'nu-check distro.nu'                                   # parses, following every source
nu -l -c 'nu-config doctor'                                     # loads for real
nu -l -c '"<tool> " | commandline complete --detailed | first 5'
nu -l -c '"<tool> sub " | commandline complete --detailed | select value description'
nu -l -c '"<tool> sub --" | commandline complete --detailed | get value'
nu -l -c '"<tool> sub --flag " | commandline complete --detailed | get value'
nu -l -c 'nu-complete run (nu-complete <tool> spec) [<tool> sub ""]'   # the error the `try` hides
nu -l -c 'timeit { "<tool> sub " | commandline complete --detailed }'
nu -l -c 'nu-complete smart "<tool> sub " 12'                   # the Tab menu path
nu -l -c 'nu-config startup-time'                               # within noise of before
```

Two traps worth knowing before they cost you an hour:

- **`nu --ide-complete` does not run `@complete` completers.** It returns files
  and proves nothing. `commandline complete --detailed` is the one that runs
  them.
- **`nu -l -c` does not load the vendor autoload directory**, which is where
  carapace is wired. A slot that shows nothing headless may well show
  carapace's answer in the REPL. To test the fallback, source it first:
  `source ($nu.data-dir | path join vendor autoload carapace.nu)`.

The skill's verifier runs a whole case file at once and diffs against carapace,
which is the fastest way to find slots you forgot:

```nu
nu .claude/skills/completion/scripts/verify.nu <tool> --oracle carapace
```

## Gotchas

Each of these cost time once.

- **`else` must stay on the `}` line.** `else` starting a line parses as an
  external command and fails at runtime, far from the cause.
- **`%open`, never `open`.** The user may alias `open` to the macOS opener; a
  module parsed after that alias would launch applications instead of reading
  files.
- **Wrap the completer body in `try { … } catch { null }`**, and test the inner
  command directly when a slot misbehaves.
- **An unfilled completer parameter is unbound, not null**, on 0.115.1 — see
  "The completer's input". The symptom is a module that works on one release
  and silently offers files on the other.
- **`lines --skip-empty`, not a closure filter.** Over 16k lines the closure
  costs ~12 ms and the flag costs nothing: 15 ms → 4 ms.
- **No hard-coded home directory.** `$nu.home-dir`, `$env.HOMEBREW_PREFIX?`,
  and paths derived from `path self`.
- **Descriptions under ~80 characters**, with `[env: …]` and `[default: …]`
  stripped, or the menu wraps.
- **`str lowercase`/`str uppercase`**; `str downcase`/`str upcase` are
  deprecated as of 0.115.
- **"NO RECORDS FOUND"** under the prompt is Reedline's message for an empty
  menu, not an error.

## The completer's input

Nushell [#18791](https://github.com/nushell/nushell/pull/18791) unified how
every completer receives its input, and landed after 0.115.1. A completer's
parameters are now bound **by name** from a fixed set — `token`
(`{text, kind, span}`), `place` (`{cursor, target, kind, flag?, index?,
shape?}`) and `buffer` — instead of by position. Whether a binary has it:
`nu -n -c 'attr interactive'`, exit 0 → yes.

Every shipped module is written for both releases, and the whole of the
difference is one line:

```nu
def complete-<tool> [token, place?, buffer?] {
  try { nu-complete run (nu-complete <tool> spec) (nu-complete spans $token (try { $place }) (try { $buffer })) } catch { null }
}
```

- **The names matter.** They are what the new build binds to; name one `spans`
  and it still works, through a compatibility bridge that queues a deprecation
  warning the REPL prints once a session.
- **The `try`s matter more.** 0.115.1 fills only the first parameter, and it
  does not fill the others with null — it never binds them, so naming `$place`
  there is `variable not found` at runtime. A completer that errors is silent,
  so the whole module would quietly degrade to file completion on the older
  release. The guards are the compatibility.
- **`nu-complete spans` is the single point of change.** It returns 0.115.1's
  span list as it stands, and rebuilds the identical list from `buffer` on a
  newer build. Everything downstream — `nu-complete run`, every `{|ctx| …}`
  source, `ctx.spans` — is unchanged on both.

Two findings from testing the merged build, both of which read the other way
in the PR description:

- `options.filter: true` does **not** narrow a command-wide completer's
  output. The engine keeps filtering its own results, honouring the user's
  `completions.algorithm` and `case_sensitive`.
- `fallback: true` in the returned envelope does **not** chain to carapace.
  For a declared `extern` — which every module here has — it means "and also
  what Nushell would have offered", i.e. file completion; the external
  completer is not consulted at all. `fallback: "external"` in a spec still
  means what it says, because `nu-complete external` calls carapace by hand.

Not yet used, and worth knowing about: `place.target` is the exact range a
suggestion replaces, `place.kind` and `place.shape` say whether the cursor is
on a flag value or a positional without walking the spans, `@interactive` lets
a completer own the terminal (an `fzf` picker for `brew install`), and
`commandline complete --input` prints the three inputs for a line without
running any completer — the fastest way to see what a slot looks like.

## Where everything is

| | |
|---|---|
| the engine | `modules/nu-complete/engine.nu` |
| caching | `modules/nu-complete/cache.nu` |
| the Tab menu source | `modules/nu-complete/smart.nu` |
| wiring | `conf/completions.nu` |
| the design, with costs | [Completion](../concepts/completion.md) |
| worked examples | `completions/brew.nu` (files + SQLite), `completions/git.nu` (cheap commands), `completions/cargo.nu` (lazy help parsing) |
| generating one with an agent | `.claude/skills/completion/` |
