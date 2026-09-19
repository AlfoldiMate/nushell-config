# completions/ — one module per tool, for Tab

A file here teaches Tab one command-line tool: its subcommands with a line
of description each, its flags, the values a flag takes, and what a
positional *is* — a branch, a package, a container — read from the tool's own
data in milliseconds. This directory is first on `NU_LIB_DIRS`, so
`use hello.nu *` in [`../settings.nu`](../settings.nu) finds it, and a file
with the same name as a shipped one — `git.nu`, `brew.nu`, `cargo.nu` in the
checkout's `completions/` — shadows it.

## Three ways to get one

```nu
agent completion gh                          # let the agent build it from the tool's own sources
nu-config fetch completion docker            # vendor one from nu_scripts, plain `extern`s
```

or write the spec by hand. `hello.nu.off` is a complete module for a
fictional `hello`: two subcommands, a flag whose values are an enum, a
positional read live from disk and memoised. Rename it `hello.nu`, add
`use hello.nu *` to `settings.nu`, and `hello ` Tab works in the next shell;
as `.off` it is inert. The file is named after the tool, because its extern
is `main` and `main` in `hello.nu` is the command `hello`. Replace `hello`
with a real tool and it is a spec.

## The pages

- [Add Tab completion for a tool](../../../docs/cookbook/add-completion.md) — `starship` worked through, and the check at the end
- [Override a shipped completion](../../../docs/cookbook/override-completion.md) — copy it here and edit the copy
- [Completion specs](../../../docs/reference/completion-spec.md) — the spec format, sources, caching, the parse budget
- [Debug Tab](../../../docs/cookbook/debug-tab.md) — `commandline complete --detailed`, without a terminal

## The two rules

Every source answers in single-digit milliseconds from memo or disk — the Tab
menu re-runs it on every keystroke — and nothing on the Tab path starts the
tool's Ruby, Python or JVM. Measure with `timeit` and write the number in the
module header.
