# nu-config

Maintenance commands for this configuration: what is installed, what is
loaded, what is stale, and what is broken.

```nu
nu-config doctor            # roots, layout, parse, tools, plugins, modules
nu-config knobs             # every knob, and whether you have overridden it
nu-config module list       # what is enabled, lazy, loaded
nu-config upgrade            # pull the distro; the shell says when there is something to pull
```

## Commands

| Command | Does |
|---|---|
| `doctor` | health check: both roots, layout state, files, search paths, parse, tools, plugins, completion caches, modules |
| `knobs [--overridden]` | every knob from `defaults.nu` and every module's `meta.nuon`, with whether your `settings.nu` sets it |
| `module list \| info \| check \| enable \| disable \| lint` | the module system — [Modules](../../concepts/modules.md) |
| `tools setup \| status \| remove \| dir` | generated init files for installed third-party tools |
| `upgrade` | `git pull --ff-only` in the checkout, then the commits that came in |
| `upgrade check \| status \| notice \| stale <every>` | fetch now; the last result; the startup line; is the result older than `every` — `conf/update.nu` wires the last two |
| `plugins list \| add` | the plugin registry |
| `fetch completion <tool>` | vendor one from nu_scripts **into your directory**, never the distro |
| `startup-time [n]` | time N cold interactive starts |
| `loaded-files` | what was parsed this session — find a slow import |
| `edit` / `edit user` | open the distro / your config directory (creating `settings.nu` the first time) |
| `distro-root` / `user-root` / `install-status` | where things are |

## Configuration

None. This module is deliberately knob-free: it is what you use when the
configuration is wrong, so it must not depend on the configuration being right.
`UPDATE_CHECK_EVERY` in `defaults.nu` belongs to `conf/update.nu`, which reads
it and passes it to `upgrade stale`; the module itself never sees the const.

## Dependencies

None.

## Design

Two facts shape this module.

**It is imported by `install.nu`, which runs as a script.** A script loads no
config, so none of the config's parse-time constants exist. Anything this
module reads from the config must come through `$env` — `$env.NU_LIB_DIRS`,
`$env.NU_SMART_TAB`, `$env.NU_MODULES` — never the `const`. Referencing a const
in the module makes it unimportable outside a loaded shell, and the error points
at a line that looks fine.

**`update` is a Nushell built-in.** `nu-config upgrade` is the name a user
expects, but a module that defines `update` shadows the built-in for everything
parsed after it in the same scope — `use nu-complete *` in `mod.nu` failed to
parse when `upstream.nu` was exported above it, because `engine.nu` calls the
built-in. So `export use upstream.nu *` is the last line of `mod.nu`, and the
file is not called `update.nu`, because a module cannot export a command with
its own name.

**The update check never touches the network at startup.** A start reads the
last result from `<your>/.state/nu-config/upgrade.nuon` (0.3 ms, measured with
`timeit`) and prints one line when it says the checkout is behind; when the
result is older than `UPDATE_CHECK_EVERY` it spawns the fetch as a `job`, whose
result the *next* start reports. The record carries the HEAD it was measured
against, read at startup from `.git/HEAD` and its ref file rather than a `git`
fork, so a pull by any means retires the line at once. A job dies with its
shell, so a window closed within a second or two loses that check and the next
one repeats it — the result is still stale.

**`module` is a Nushell keyword.** `module list` is a perfectly good exported
name, but it cannot be *called* from inside `mod.nu` — the parser reads it as
the `module` keyword. Hence the private `mod-list`, `mod-info` and `mod-check`,
which the exported commands delegate to.

## Measured

Eager and never disabled: it is how you diagnose everything else, so it has to
load even when something below it is broken. `module disable nu-config` is
refused for the same reason.

## Files

```
mod.nu       the commands
tools.nu     the third-party tool registry and generator
upstream.nu  `upgrade`: is the checkout behind its remote, and pulling it
load.nu      `use nu-config`
meta.nuon    description
```

## Limits

`doctor`'s parse check runs `nu-check` on `distro.nu`, which follows every
`source` but does not execute anything — a file that parses can still fail at
runtime.
