# nu-complete

The completion engine behind Tab: pipeline-aware, spec-driven, and quiet where
Nushell's own completer has nothing useful to say.

```nu
ls | where <Tab>          # name, type, size, modified — typed, with a sample value
brew install <Tab>        # 16,340 formulae and casks with descriptions, in 3 ms
git checkout <Tab>        # branches by recency, then remotes and tags
```

## Commands

| Command | Does |
|---|---|
| `nu-complete run <spec> <spans>` | positional completion for an extern, from a spec (`engine.nu`) |
| `nu-complete spans <token> <place> <buffer>` | the completer's input as a span list, on 0.115.1 and on #18791 builds alike (`engine.nu`) |
| `nu-complete smart <buffer> <pos>` | the Tab menu source: the only place that sees the whole line (`smart.nu`). `<pos>` is an int or a `place` record |
| `nu-complete quote` | quote a candidate the line would otherwise split (`Catppuccin Macchiato` → `"Catppuccin Macchiato"`); `run` and `smart` apply it to spec and `string@completer` values, never to commands, flags or paths (`engine.nu`) |
| `nu-complete cache <key> <ttl> {}` | memoise a slow source for the session (`cache.nu`) |
| `nu-complete status` | what is cached, and where |
| `nu-complete warm` | build the signature table (run in a background job at startup) |
| `nu-complete activate` | seed defaults and spawn the warm job |

## Configuration

| Knob | Default | Meaning |
|---|---|---|
| `NU_COMPLETE_EVAL` | `safe` | run the typed pipeline in a subprocess to offer real columns: `safe` (read-only built-ins only), `all`, `off` |

`SMART_TAB` in `defaults.nu` chooses between this engine's Tab menu and
Nushell's stock one. The menu's look and its keybinding are configuration, so
they live in `conf/completions.nu` rather than here.

## Dependencies

`carapace` is soft: it answers any slot a spec has no opinion on
(`fallback: "external"`). Without it those slots fall back to Nushell's own
knowledge and then to file paths.

## Design

Three layers, in the order they answer:

1. Nushell's own completer — built-ins, flags, cell paths, files.
2. `@complete` externs with a spec per tool in `completions/`.
3. The Tab menu source `nu-complete smart`, which sees the whole buffer and so
   can offer columns, operators and values for `where`/`get`/`select`, suppress
   file noise after commands that take no argument, and deduplicate.

A custom menu is the only kind whose `source` closure receives the buffer — a
`source` on the stock `completion_menu` is ignored by 0.115 — which is why Tab
is rebound rather than configured.

[Completion](../../concepts/completion.md) has the full design;
[Completion specs](../completion-spec.md) is the contract for a tool spec.

## Measured

Eager by design: it owns the Tab menu, which has to answer on the first
keystroke of the first line, so it cannot be lazy. 2 ms to load — the specs it
runs are parsed by `conf/completions.nu` and are not part of that. Building
the signature table costs ~115 ms, which is why `activate` hands it to a
background job instead of blocking startup.

## Files

```
mod.nu       re-exports engine, cache and smart; `nu-complete activate`
engine.nu    the spec runner
cache.nu     three cache tiers: stor memo, cache-dir files, staleness
smart.nu     the Tab menu source
load.nu      `use nu-complete *` + activate
meta.nuon    description, dependencies, knobs
```

## Tests

`nu tests/run.nu completion` — four files under `tests/completion/`, 43
tests, 2.4 s on the user's build and 2.9 s on the 0.115.1 release
(2026-09-19): `engine` (spans, filter, quote, `run` over an inline spec),
`smart` (columns, operators, values, the no-files rules, the eval gating with
a `save` that must not run), `specs` (brew against `tests/fixtures/brew`,
git and cargo against a scratch repository and workspace) and `cost` (the
numbers above as upper bounds, ten to twenty times the measurement).
[Tests](../tests.md) is how to add one.

## Limits

`nu --ide-complete` does not run `@complete` completers, so it proves nothing;
use `commandline complete --detailed`. `nu -l -c` does not load the vendor
autoload dir, where carapace is wired, so the external fallback looks empty
headless even when it works in the REPL.

Nushell [#18791](https://github.com/nushell/nushell/pull/18791) changed how
every completer receives its input, after 0.115.1. `nu-complete spans` is the
one place the two shapes meet, and every spec runs on both
([Completion](../../concepts/completion.md#the-unified-completer-inputs)).
