# Enable a module, make it lazy, see what it costs

```nu
nu-config module list        # every module: enabled, lazy, loaded in this shell, dependencies, measured cost
```

| module | from | enabled | lazy | loaded | deps | cost |
|---|---|---|---|---|---|---|
| agent | distro | true | true | false | claude:ok | 18ms |
| nu-complete | distro | true | false | true | carapace:ok | 2ms |
| nu-config | distro | true | false | true | — | 14ms |
| odata | distro | true | true | false | — | 97ms |
| terminal | distro | true | true | false | ghostty:ok | 18ms |

`loaded: false` on a lazy module means nothing has mentioned it yet in this
shell. `cost` is the module's own declaration, measured the same way for all
of them ([Modules](../concepts/modules.md#cost)).

## Turn one off, or on

```nu
nu-config module disable odata
nu-config module enable odata
```

Each edits one line in your `settings.nu` — `const MODULES = [nu-config
nu-complete terminal agent]` — and says to restart the shell. It is the same
line you could write yourself; a module you disable is not parsed at all.
`nu-config` itself refuses to be disabled: it is how you repair everything
else.

Run on 2026-09-19 in a scratch user directory: after `disable`, `module
list` showed `odata` with `enabled: false`; `enable` put it back and printed
the module's dependency report (`no dependencies`).

## Make one eager, or lazy

A lazy module is not parsed at startup; a `pre_execution` hook loads it on the
first line that mentions its name or one of its trigger words. That is
interactive-only by nature — `nu -c` and scripts never fire the hook — so a
module you use from scripts has to be eager. In `settings.nu`:

```nu
const MODULES_LAZY = [agent odata]           # terminal always loaded; the shipped list is [terminal agent odata]
```

`module list` then shows `terminal` as `lazy: false, loaded: true`, and
`nu-config loaded-files | where filename =~ modules/terminal` lists its seven
files as parsed. Measured on 2026-09-19, minimum of fifteen cold starts of
this checkout on an M-series Mac: **69.7 ms** with `terminal` eager against
**53.4 ms** lazy — 16 ms, which is what its `meta.nuon` says it costs.

The other direction — making a module lazy that ships eager — is the same
line with the name added, and works for any module whose commands are never
needed by a script. `MODULES_TRIGGERS` in `defaults.nu` is where extra words
go for a module whose commands do not repeat its name.

## See what it costs

```nu
nu-config startup-time       # five cold starts of the live config; `startup-time 25` for a median worth quoting
nu-config loaded-files       # every file this shell parsed, with its size — find the slow import
nu-config doctor             # the Modules section: state and cost per module, then the startup time
```

`startup-time` runs `nu -l -c '$nu.startup-time'`, so it measures the
configuration Nushell actually loads. To measure a change *before* it is
live, run the same thing against a scratch `config.nu`
([Test a change to the distro](test-a-change.md)).

A module of your own goes in `<your>/modules/<name>/` and is `use`d from
your `settings.nu`; `nu-config module lint` checks it against the contract,
and its `cost` line is yours to measure.
