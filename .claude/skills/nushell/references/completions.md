# Completions and externs

Nushell 0.114.1, with two sections at the end: **0.115.1** (command-wide
completers, `commandline complete`, menu sources — the installed binary, and
what this config runs on) and **the next release** (#18791 unified every
completer's input and output; merged upstream, not released). Read the 0.115.1
section first for anything that touches the engine in this config
(`modules/nu-complete`, `docs/reference/completion-spec.md`, `docs/concepts/completion.md`), and the
last one before writing a completer that has to survive the upgrade.

## Custom completions

Two steps: define a command that returns candidates, then attach it to an
argument's type with `@`.

```nu
def animals [] { ["cat" "dog" "eel"] }
def my-command [animal: string@animals] { print $animal }
```

`string@animals` gives the parser both the **type** (for checking) and the
**completer** (for suggestions).

- Return `[]` to suppress completion for an argument.
- Return `null` to fall back to Nushell's file completion.

### Records for descriptions and styling

```nu
def commits [] {
  [
    { value: "5c2464", description: "Add .gitignore", style: red }
    { value: "f3a377", description: "Initial commit",
      style: { fg: green, bg: "#66078c", attr: ub } }
  ]
}
```

Only `value` is inserted; `description` and `style` are display only.

### Per-completer options

Return a record with `completions` and `options` to override global settings:

```nu
def animals [] {
  {
    options: {
      case_sensitive: false
      completion_algorithm: substring    # prefix | substring | fuzzy
      sort: false                        # keep your order (e.g. by date)
      match_description: true            # also match against descriptions
    }
    completions: [cat rat bat]
  }
}
```

`match_description` is what lets you type a person's name and complete to their
opaque email address.

### Context-aware

The completer can accept the command line typed so far, and the cursor position:

```nu
def animal-names [context: string] {
  match ($context | split words | last) {
    cat => ["Missy" "Phoebe"]
    dog => ["Lulu" "Enzo"]
    _ => []
  }
}
def my-command [animal: string@animals, name: string@animal-names] { }

def completer [context: string, position: int] { }   # both, if needed
```

### Put completers in modules

Completers are implementation detail; don't export them.

```nu
module commands {
  def animals [] { ["cat" "dog"] }        # private
  export def my-command [a: string@animals] { }
}
```

Completers attach at **parse time**, so changing a completer requires reparsing
the command that uses it. Re-running `use` does both at once — which is the real
reason modules are the recommended home for them.

## `extern` — signatures for external commands

Declares an external's interface so Nushell can type-check, highlight, and
complete it.

```nu
module "ssh extern" {
  def none [] { [] }
  def identities [] {
    ls ~/.ssh/id_* | where {|f| ($f.name | path parse | get extension) != "pub" } | get name
  }

  export extern ssh [
    destination?: string@none    # Destination host
    -p: int                      # Port
    -i: string@identities        # Identity file
  ]
}
use "ssh extern" ssh
```

`?` marks an optional positional; `...name: type` marks rest args. A trailing
comment becomes the flag's description — **it needs a space before the `#`**.

Without a completer returning `[]`, Nushell falls back to file completion for
that argument, which is usually wrong for things like hostnames.

### Limits

- Cannot express required flag/positional **ordering**.
- Cannot require `=` between a flag and its value.
- Cannot express single-dash long flags (`-long`).
- Does not apply to externals called with `^` (`^ssh`).

## External completers

A global fallback closure, used when Nushell has no completion of its own.
Receives `$spans` (tokens typed so far); returns records or `null`.

```nu
$env.config.completions.external = {
  enable: true
  max_results: 100
  completer: {|spans| carapace $spans.0 nushell ...$spans | from json }
}
```

[Carapace](https://carapace.sh) covers ~1000 CLIs and is the usual choice.
A more robust version, which falls back to files when carapace errors:

```nu
let carapace = {|spans|
  carapace $spans.0 nushell ...$spans
  | from json
  | if ($in | default [] | where value =~ '^-.*ERR$' | is-empty) { $in } else { null }
}
```

Dispatch to different engines per command:

```nu
let external = {|spans|
  match $spans.0 {
    git => (do $fish_completer $spans)
    _   => (do $carapace_completer $spans)
  }
}
$env.config.completions.external.completer = $external
```

**Alias caveat:** Nushell expands aliases before the completer sees the spans,
while carapace expects the original. Recover the typed text with
`commandline | split words` if this matters.

More recipes: <https://www.nushell.sh/cookbook/external_completers.html>

## Debugging completions without a terminal

`nu --ide-complete <cursor> <file>` asks Nushell what it would offer at a cursor
position, and prints JSON. This is the fastest way to reason about completion
behaviour — no pty, no keypresses, no menu.

```nu
"ps " | save -f /tmp/q.nu
nu --ide-complete 3 /tmp/q.nu
# => {"completions": ["project/", "ps-notes.md", "psfolder/", "readme.md"]}
```

Related: `--ide-hover`, `--ide-goto-def`, `--ide-check`, `--ide-ast`.

## File-path fallback in argument position

Nushell falls back to **file and directory completion** for an argument position
even when the command declares no positional parameters. Verified on 0.114.1:

```
'ps'    → ["ps"]                          # command position, fine
'ps '   → every file and folder in cwd    # despite `ps` taking no positionals
'ps -'  → ["--help", "--long", "-h", "-l"]  # flags are correct
```

`scope commands | where name == ps | get signatures.0` confirms `ps` has only
flags. The path list is a pure fallback, not something the signature asked for.

You rarely notice this with Tab-triggered completion, because you only press Tab
when you want something. With an always-on menu it is visible constantly.

There is no setting to suppress it. For *external* commands you care about,
declare an `extern` and attach a completer that returns `[]` to the positions
that should offer nothing:

```nu
def none [] { [] }
export extern "ps" [ ...args: string@none ]
```

That is the documented technique for suppressing an argument's completions, and
it is the same trick the book's `ssh` example uses to stop hostnames falling
back to filenames.

### Suppressing the fallback

Declaring fewer parameters does **not** stop it. Verified with `--ide-complete`:

```
def foo [] { }                    'foo ' -> every file and folder
def bar [--long] { }              'bar ' -> every file and folder
def qux [...a: string] { }        'qux ' -> every file and folder
def baz [...a: string@none] { }   'baz ' -> []            <- only this works
```

Only a rest parameter carrying a completer that returns `[]` suppresses it. For
a built-in that means shadowing it (see below), and the rest parameter exists
purely to hold the completer — so reject anything actually passed:

```nu
def none [] { [] }
export def ps [--long (-l), ...args: string@none] {
  if ($args | is-not-empty) { error make {msg: "ps takes no positional arguments"} }
  %ps --long=$long
}
```

`%ps ...$args` is not an option: the built-in has no rest parameter, so
spreading into it is a parse error.

**The cost:** a shadowed command appears **twice** in command-position
completion, because the completer lists both the built-in and the custom
declaration — even though `scope commands` shows one.

```
'ps' -> ["ps", "ps"]   shadowed
'ps' -> ["ps"]         stock
```

There is no config-side fix, so this is a trade. Worth it where the gain is real
(`kill` completing PIDs by name); not worth it for commands you rarely pass
arguments to, where you would duplicate every entry for nothing.

### Built-ins: shadow to attach a completer

`extern` only declares *external* commands. A built-in's signature cannot be
annotated from outside, so to give one a completer you shadow it with a custom
command and delegate to the original with `%`:

```nu
export def kill [
  ...pid: int@"nu-complete pids"
  --force (-f)
  --quiet (-q)
  --signal (-s): int
] {
  if $signal != null {
    %kill --signal $signal --force=$force --quiet=$quiet ...$pid
  } else {
    %kill --force=$force --quiet=$quiet ...$pid
  }
}
```

Two rules: a bare `kill` in the body recurses to the recursion limit — `%kill`
is what makes it safe; and switches forward as `--flag=$flag`, not by
re-testing them with `if`.

Match on the description to complete a number by a name:

```nu
export def "nu-complete pids" [] {
  {
    options: { match_description: true, completion_algorithm: substring, sort: false }
    completions: (
      ^ps -Ao pid=,comm=
      | lines
      | parse -r (r#'^\s*(?<pid>\d+)\s+(?<cmd>.+)$'#)
      | each {|r| { value: $r.pid, description: ($r.cmd | path basename) } }
    )
  }
}
```

`kill ghost<TAB>` then inserts Ghostty's PID. Note `^ps` (~25 ms), not Nushell's
`ps` (~115 ms) — the built-in samples CPU over an interval, which is wasted work
when you only need names.

## Overriding a slow external completer

Nushell consults the external completer **only when it has no completion of its
own**. So declaring an `extern` is the way to bypass carapace for a specific
command — useful when carapace is too slow.

Real case, measured on 0.114.1 / carapace 1.7.3:

| Completion | Cost |
|---|---|
| carapace `brew install fo` | **~1650 ms** (2653 results) |
| carapace `brew info fo` | ~127 ms |
| carapace `brew uninstall fo` | ~36 ms |
| carapace `brew ` (subcommands) | ~16 ms |
| reading Homebrew's own name cache | **~4 ms** (16,469 entries) |

With Tab-triggered completion 1.6 s is merely annoying; with an always-on menu
it is unusable.

**zsh is not faster at generating the list — it caches.** `__brew_formulae` in
`/opt/homebrew/share/zsh/site-functions/_brew` calls `brew formulae` once and
stores it with `_store_cache`, re-running only when the cache is two weeks old
or a tap index is newer.

Better still, read whatever cache the tool already maintains, so there is no
second cache to invalidate:

```nu
def read-lines [f: path] {
  if ($f | path exists) { %open --raw $f | lines --skip-empty } else { [] }
}
export def "nu-complete brew all" [] {
  let d = ($env.HOME | path join "Library" "Caches" "Homebrew" "api")
  (read-lines ($d | path join formula_names.txt)) ++
  (read-lines ($d | path join cask_names.txt))
}
export extern "brew install" [ ...packages: string@"nu-complete brew all" ]
```

Three things that matter in that snippet:

- **`lines --skip-empty`, not `where {|l| $l | is-not-empty}`.** Over 16k lines
  the closure filter costs ~12 ms; the built-in flag is free. 15 ms → 4 ms.
- **`%open`**, in case the user has `alias open = ^open` (the macOS fix). A
  module parsed after that alias would otherwise shell out to `/usr/bin/open`.
- **Declare only positionals.** Undeclared flags pass through to the external
  untouched — verified — so there is no need to enumerate every flag, and no
  risk of rejecting a valid one.

Prefer reading files over shelling out. `brew formulae` costs ~97 ms and
`brew list --formula` ~16 ms, both paying Ruby startup; the Cellar directory
listing that answers the same question takes ~1 ms.

Declare externs only for the slow subcommands and let the external completer
keep handling the rest.

## Global completion settings

```nu
$env.config.completions.algorithm = "prefix"   # prefix | substring | fuzzy
$env.config.completions.sort = "smart"         # smart | alphabetical
$env.config.completions.case_sensitive = false
$env.config.completions.quick = true           # auto-accept a lone candidate
$env.config.completions.partial = true         # complete the common prefix
$env.config.completions.use_ls_colors = true
$env.config.completions.external.enable = true # scan PATH for command names
```

## Ready-made completions

[`nu_scripts/custom-completions`](https://github.com/nushell/nu_scripts/tree/main/custom-completions)
has modules for 100+ tools: git, cargo, docker, gh, npm, pnpm, just, make, man,
rg, ssh, tar, curl, kubectl, poetry, zellij, and more.

```nu
use git-completions.nu *      # after placing it on NU_LIB_DIRS
```

On this machine, `nu-fetch-completions <tool>` downloads one into
`~/.nu/completions/`.

## Nushell 0.115.1: the engine's new surface (verified 2026-09-10)

Everything below was verified against the binary with `nu --ide-complete`,
`commandline complete` and a pty-driven interactive `nu`; the source that
backs it is `crates/nu-cli/src/completions/` at tag 0.115.1.

### `@complete` — a completer for the whole command

```nu
def complete-foo [spans: list<string>] { ... }   # spans: [cmd, arg, arg, partial]
@complete "complete-foo"
export extern foo [...args]                       # works on `def` too
```

- `spans` carries the command name, every argument typed so far and the
  partial token — an empty string at a fresh slot (`foo ⌶` → `[foo ""]`).
- Precedence per slot: per-argument `@completer` → command-wide → shape
  (files). A per-argument completer returning `null` falls through.
- **Nushell does not filter the result by the typed prefix**; the completer
  filters itself (`nu-complete filter` in engine.nu honours
  `completions.algorithm` and `case_sensitive`).
- Returning `null` declines the slot (files); an error is silent and also
  declines — wrap the body in `try { } catch { null }` and test the inner
  call directly.
- `@complete external` on a `def --wrapped` routes its arguments to the
  external completer (carapace).
- A module cannot export an extern named like itself: `completions/brew.nu`
  exports `extern main`, and `use brew.nu *` yields `brew`.
- `nu --ide-complete` does **not** run `@complete` completers (files come
  back); `"brew inst" | commandline complete --detailed` does.

### `commandline complete --detailed`

Runs the engine on a string (cursor at its end) and returns records
`{value, span, description, style, kind, type}` — `kind` is one of command,
file, directory, value, operator, cell-path, flag, variable... — in 0.1-0.6 ms,
no REPL needed. With no input it uses the REPL buffer. This is the way to
test completion from a script.

### Menus with a `source` closure

- Only a custom menu's `source: {|buffer, position| ...}` sees the whole
  line (`input_mode: cursor_prefix` → text up to the cursor). A per-argument
  completer's `context` is the current command element only (`get na`, not
  `ls | get na`); `commandline` and `commandline get-cursor` return `""` and
  `0` inside any completer or menu source.
- Putting `source` on the stock `completion_menu` (merge by name) is
  ignored. Use a new menu name and rebind Tab with the stock chain:
  `until: [{send: menu, name: smart_menu}, {send: menunext}, {edit: complete}]`.
- The source runs again on every keystroke while the menu is open (verified
  with a `stor` counter); keep it in the low milliseconds and cache.
- Records may carry `span: {start, end}` (absolute in the buffer) to replace
  only part of the token, e.g. the last segment of `get package.ve`.
- An empty result paints Reedline's "NO RECORDS FOUND"; the menu still
  counts as handled, so the `until` chain does not continue.
- `stor` tables survive across completer and menu calls in a session (good
  for memoisation); `stor import` wipes every other stor table.
- Lone candidates are inserted immediately (quick completion), so a source
  that returns one item auto-completes.

### What the engine still lacks (motivates modules/nu-complete)

- No column completion for `where`, `get`, `select`, `sort-by` or any of
  the 78 built-ins with cell-path positionals; `ls | get ⌶` offers files.
- `where name ⌶` offers every operator (column type unknown); with a known
  type the list would narrow (see `operator_completions.rs`).
- Cell-path completion works only for parse-time-known values
  (`$env.config.⌶`, `let x = {..}; $x.⌶`), not for pipeline input.
- 216 of 476 built-ins take no positional yet `ps ⌶` lists files;
  shadowing one with a `def` (even after `hide`) lists it twice in command
  position.

### Measuring

`ast --flatten "<line>"` (0.5 ms) lists every token with its shape
(`shape_internalcall`, `shape_external`, `shape_pipe`, `shape_garbage`...),
closures included — the cheap way to classify a line. `scope commands`
costs 18 ms and 476 `stor insert`s ~115 ms, which is why the signature
table is built once in a background `job spawn`.

## The next release: one input contract for every completer

[#18791](https://github.com/nushell/nushell/pull/18791) landed on main on
2026-09-09 (merge `b2637148`). **It is not in 0.115.1** — the installed binary
has neither `attr interactive` nor `commandline complete --input`, which is the
one-line check for whether a given `nu` has it:

```nu
nu -n -c 'attr interactive' | complete | get exit_code    # 0 → has it, 1 → 0.115.x
```

Everything below was verified on 2026-09-18 against a local `cargo build` of
that commit (it reports version 0.115.2), not read off the PR description —
which is worth the trouble, because the PR text is wrong or incomplete in two
places noted below.

### Inputs are bound by name, not by position

Every completion entry point — a parameter completer (`arg: string@c`), a
command-wide completer (`@complete c`), the external completer closure, and a
menu `source` — is now handed **one record**, and its positional parameters are
filled from that record **by name**. Order does not matter; a name outside the
set gets `nothing` plus a diagnostic in the completion log.

```nu
def complete-branch [token: record] { ... }          # just the token
def complete-at-place [place: record] { ... }        # where the cursor is
def carapace [buffer: string] { ... }                # the whole line
def both [place: record, token: record] { ... }      # any subset, any order
```

The three recognized names (`INPUT_FIELDS` in the source):

| `token` | the token at the cursor | `{text, kind, span}` — `kind` is `head`, `flag`, `value` or `block`; `span` is `nothing` for alias-expanded tokens. A cursor after a space is an empty `value` token whose span is zero-width at the cursor. |
| `place` | what is being completed | `{cursor, target, kind, flag?, index?, shape?}` — `cursor` is a byte offset, `target` the `{start, end}` a suggestion replaces. `flag` is present for a flag value, `index` for a positional or external arg, `shape` when the declared syntax shape is known. |
| `buffer` | the line up to the cursor | the exact typed text, across pipes, closures and `;`. Never anything past the cursor. |

The PR description lists four values for `place.kind`. There are **eleven**
(`ResolvedCursor::kind` in `completions/completer.rs`), and the one you meet
first is not among the four:

```
command  flag-name  flag-value  positional  operator  cell-path
variable  attribute-name  attributable-item  external-arg  file
```

`external-arg` is what an *undeclared* external's arguments get — `git checkout
mai` with no extern for git gives `kind: external-arg, index: 1`. Declare the
extern (as `completions/*.nu` do) and the same slot becomes `positional`.
Measured on the build: `ls ` → `positional` with `shape: "oneof<glob, string>"`,
`ls -` → `flag-name`, `[1 2] | each {|x| $x ` → `operator`.

Two rules worth memorising. **Use `place.target`, not `token.span`,** when
returning a custom span — they differ wherever a completion covers more than one
token (a multi-word command head, a cell path). And **use `buffer` instead of
calling `commandline`** inside a completer: `buffer` is always the line being
completed, while `commandline` reads editor state and can come back empty.

`std/util structure` turns a buffer into a `{text, kind, span}` table — it is
`ast --flatten | rename text kind span | update kind { str replace "shape_" "" }
| uniq-by span`, i.e. the parser's view with duplicate spans collapsed. Its own
docs call the parser lossy; reach for the raw `buffer` when exact text matters.

### The old shapes still work, and warn

There is a compatibility bridge. Only the **first two** positionals, and only
those whose names are *not* `token`/`place`/`buffer`, receive their old values:

| Completer | Legacy slot 0 | Legacy slot 1 |
|---|---|---|
| parameter | the old `context` string | the old `position` int |
| command-wide / external | the old `spans` list | `nothing` |
| menu source | the buffer | the position int |

Using one queues a deprecation warning (`ReportMode::FirstUse`) that the REPL
prints after completion finishes — the warning is deferred because printing from
the completion thread would land in the middle of the line being edited.

The mixed case is the one that surprises: a menu source written
`{|buffer, position| ... }` keeps working, but `buffer` is now a *recognized*
name, so it is filled with the new whole-line semantics while `position` comes
from the bridge — and the pair still warns. `def c [spans: list<string>]` on a
`@complete` extern likewise keeps receiving its span list and starts warning.

Migration, per the source's own `migration()` strings:

| Was | Becomes |
|---|---|
| `def c [context, pos]` (parameter) | `[buffer, place]`; `$place.cursor` for the position |
| `def c [spans]` (command-wide/external) | `[buffer]`, parsed — or `[token, place]` if the token is all you needed |
| `{\|spans\| ...}` external closure | `{\|buffer\| ...}` |
| `{\|buffer, position\| ...}` menu source | `{\|buffer, place\| ...}`; `$place.cursor` for the position |

### Output: strings, records, or an envelope

A completer may return `null` to **decline** (the next source runs), a list of
strings, a list of suggestion records, a single record, or an envelope:

```nu
{
  completions: [ {value: main, description: "default branch"} ]
  options: { filter: true, completion_algorithm: "substring", match_description: true }
  fallback: true          # keep these results AND continue to the next source
}
```

Suggestion fields: `value`, `display_override`, `description`, `kind`, `style`,
`span` (either end omittable), `extra`, `append_whitespace`, `match_indices`.
`options` takes `filter`, `sort`, `case_sensitive`, `match_description`,
`completion_algorithm`.

**Filtering defaults differ by kind**: parameter completers are filtered by
Nushell, command-wide and external ones are not (they usually filter
themselves).

> **`options.filter: true` does not work on a command-wide completer in this
> build.** Verified: a parameter completer returning `[alpha alptest beta]` at
> `p alp` correctly yields `[alpha, alptest]`, while the same list from a
> `@complete` completer with `options: {filter: true}` yields all three, on both
> a `def` and an `extern`. The flag itself is read — asking for
> `{filter: false, sort: true}` logs "Sorting won't happen because filtering is
> disabled" and `{filter: true, sort: true}` does not — so the narrowing is
> being asked for and then matching against an empty prefix
> (`ctx.prefix_str()`), which matches everything. File completion reached
> through `fallback` *does* narrow on the same line, so the prefix exists; it
> just does not reach this path.
>
> **Consequence: a command-wide completer must still filter its own output.**
> Do not delete hand-rolled filtering on the strength of this option.

`fallback: true` does work as documented, and is the declarative form of "and
also ask the next source". Verified: a completer returning
`{completions: [CUSTOM], fallback: true}` at `f1 alp` yields
`[CUSTOM, alpaca.txt]` — its own result plus prefix-matched file completion —
where `fallback: false` yields `[CUSTOM]` and returning `null` yields
`[alpaca.txt]`.

> **It is not a way to reach carapace.** "The next source" for a *declared*
> `extern` is Nushell's own argument completion, which is files; the external
> completer is never consulted for a command it has an `extern` for. Verified:
> a `@complete` completer on an extern returning `{completions: [], fallback:
> true}` with `$env.config.completions.external.completer` set offers files and
> nothing from the external closure, while an undeclared command on the same
> line reaches it. A completer that wants carapace still calls it by hand.

Malformed output is isolated: a bad suggestion, style, span or option is
reported in the completion log without discarding the valid ones around it.

### `@interactive`

Completers run on a background worker with stdin suppressed — correct for
normal completion, fatal for anything that wants the terminal. `@interactive`
moves one onto the line-editor thread instead:

```nu
@interactive
def pick-file [token: record] { ls | get name | to text | ^fzf --query $token.text | lines }
def open-file [path: string@pick-file] { open $path }
```

It only chooses *where* a completer runs; it does not attach it. The external
completer is a closure and cannot carry an attribute, so to make it interactive
have the closure call an `@interactive` command — the engine sees through the
dispatch. Declare `token: record` even when the body ignores it, so a direct
call fails at the call site rather than deep in the body; `commandline complete
--input` is how you get a real record to test with.

### Debugging

```nu
'git checkout mai' | commandline complete --input   # {token, place, buffer}, no completer run
```

`--input` works for an `@interactive` completer too, which cannot otherwise run
outside the line editor. It cannot be combined with `--detailed` or `--type`.
`--detailed` now returns suggestions in the custom-completer output form, and
`--type` asks for one kind of completion, which is what lets a completer add to
Nushell's own answer:

```nu
def complete-command [token: record] { [my-shortcut] ++ ($token.text | commandline complete --type command) }
```

### Behaviour changes to watch for

- The experimental global `background-completions` option is **removed**;
  `@interactive` is the per-completer replacement.
- A parameter completer that **fails** now returns no suggestions instead of
  falling back to the working directory.
- Command-wide and external completers may decline with `null`.
- Completion state is resolved at the cursor, including inside nested closures,
  through aliases, and at multi-word command heads and empty argument slots.
- Aliases resolve through to the completion command, `@interactive` included.

### What it means for this config

Migrated on 2026-09-19, and still running on 0.115.1. Three signatures moved:
`def complete-<tool> [token, place?, buffer?]` in each `completions/*.nu`,
`source: {|buffer, place| ... }` for the Tab menu in `conf/completions.nu`, and
a wrapper appended to the generated `vendor/autoload/carapace.nu` by
`nu-config tools setup`, because carapace itself still emits `{|spans| ... }`
and every fallthrough to it was printing the warning.

`nu-complete spans` in `engine.nu` is the only place that knows which release
it is on: it returns the old span list unchanged, and rebuilds the same list
from `buffer` (`ast --flatten`, `place.target.start`, cut at the last command
head) on a newer build. Everything downstream is untouched.

**The trap that cost the most.** 0.115.1 binds only the first parameter and
leaves the rest *unbound* rather than null, so `if $place == null` is
`variable not found` there — and since a completer that errors is silent, the
symptom is file completion on the old release and nothing in the log. Every
call site reads `(try { $place })` for that reason.

Still open: `place.target` could replace the hand-computed replacement spans in
`smart.nu`, and `@interactive` could give `brew install` an `fzf` picker.
`nu-complete filter` stays until the `options.filter` bug above is fixed, and
`nu-complete external` stays because `fallback: true` does not reach carapace
for a declared extern (see above).
