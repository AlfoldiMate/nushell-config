# Modules

A module is a directory under `modules/` that adds commands to the shell. This
file is the contract: what a module must contain, what it may assume, and how
it gets loaded. `nu-config module lint` checks it.

## The shape

```
modules/<name>/
  mod.nu       the commands, and `<name> activate`
  load.nu      `use` + `activate` — the ONLY place that knows how to import it
  meta.nuon    description, dependencies, knobs        (read at runtime, never at startup)
  README.md    what it is, commands, configuration, design, costs, limits
  stub.nu      optional: what every shell needs whether the module loads or not
```

## Why `load.nu` exists

There are two ways a module gets loaded and they must not drift apart:

```nu
# eager — conf/modules.nu, at parse time
source (modules/odata/load.nu)

# lazy — a pre_execution hook, on the first line that says "odata"
source '/…/modules/odata/load.nu'
```

Both source the same file, so the fact that `odata` imports with `use odata *`
while `agent` imports with `use agent` is written down once.

## `activate`

Everything the module wires into the shell — hooks, completion providers,
`$env` defaults — belongs in `activate`, not at the module's top level:

```nu
export def --env "odata activate" []: nothing -> nothing {
  $env.ODATA_PUSHDOWN = ($env.ODATA_PUSHDOWN? | default true)
  $env.config.hooks.pre_execution ++= [{|| … }]
}
```

Two rules:

- **`default`, never assignment.** The user's `settings.nu` was sourced long
  before `activate` ran and has to win.
- **Namespace it to match the import.** `use odata *` means the command must be
  `export def "odata activate"`; `use agent` means plain `export def activate`.
  Get this wrong and the eager path fails with "command not found".

## Lazy loading

`meta.nuon` says `lazy: true`, and the name goes in `MODULES_LAZY`.

The mechanism: a `pre_execution` hook fires **before** Nushell parses the line
you typed, and a hook given as a **string** is parsed and merged into the
global engine state — the book's phrasing is "as if you typed the string into
the REPL". So a `source` in that hook is in scope for the very line that
triggered it. (nushell 0.115.1: `repl.rs:400` for the ordering,
`hook.rs:126-144` for the `merge_delta`. Confirmed in a live REPL.)

Measured: the guard costs **828 ns** per Enter on a line that matches nothing.
Making `odata` and `agent` lazy took startup from **161 ms to 73 ms** when it was
done; on the same machine today the shipped set starts in **79 ms**, and loading
all three lazy modules eagerly would add **133 ms** of it (see Cost, below).

**The limit, and it is inherent:** `pre_execution` never fires for `nu -c` or a
script, so a lazy module is interactive-only. A script must `use odata *`
itself. If a module has to work in scripts, it cannot be lazy.

If something must happen in every shell regardless — `agent` mints a session id
and binds Alt+E — put it in `stub.nu`, which `conf/modules.nu` sources
unconditionally. `stub.nu` must never `use` the module; that would defeat the
whole thing.

## Dependencies

Declared, never installed:

```nu
requires: [
  { bin: "claude", hard: true, why: "every verb runs one `claude -p` turn"
    install: { macos: "…", linux: "…", windows: "…" } }
]
```

`hard: false` means the module works without it, worse. `nu-config module check
<name>` reports; `nu-config doctor` flags a missing hard dependency. Nothing
here ever runs an installer.

## Cost

`meta.nuon` declares what the module costs, as a duration:

```nu
cost: 18ms
```

One method for all of them, so the numbers can be compared: the median of 25
cold `nu -l` startups with the module loaded, against the same 25 with it lazy
or absent, from the shipped default set. `nu-config startup-time` is the same
measurement on your own machine, and the number is a property of the machine as
much as of the module — what it is for is deciding whether to make something
lazy, and telling the installer what a checkbox costs.

A lazy module's cost is paid on the first line that mentions it, not at startup.

An optional `paths: [...]` is consulted when PATH misses — a GUI application is
installed without being on PATH. Ghostty on macOS is the case that forced it:
its binary lives inside `Ghostty.app` and is only on PATH inside a Ghostty
window, so `which` alone calls it missing on a machine where it plainly is not.

## Knobs

A module carries its own defaults, so its knobs do **not** go in `defaults.nu`.
Declare them in `meta.nuon` so `nu-config knobs` can find them:

```nu
knobs: {
  ODATA_PUSHDOWN: { default: true, about: "translate where/select into $filter/$select" }
}
```

## Enabling

`const MODULES` and `const MODULES_LAZY` in `defaults.nu`, overridable in your
`settings.nu`, edited for you by `nu-config module enable|disable`.

`use` is parse-time and cannot sit inside an `if` or a loop, so a module cannot
be enabled by iterating a list. What works is a `source` of a const path chosen
by a const `if` — `source null` is a no-op — which is why `conf/modules.nu` has
two repetitive lines per module. That repetition is the price of resolving it
all at parse time, and it costs nothing at runtime.

Adding a module of your own does not need `conf/modules.nu` at all: drop it in
`<your>/modules/` and `use` it from your `settings.nu`, which is parse-time too.

## Checking

```nu
nu-config module list        every module, enabled, lazy, loaded, deps
nu-config module info <n>    meta.nuon plus the dependency report
nu-config module check <n>   dependencies only
nu-config module lint        the contract above, enforced
```
