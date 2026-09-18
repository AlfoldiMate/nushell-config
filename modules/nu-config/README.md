# modules/nu-config

Maintenance commands for this configuration: what is installed, what is
loaded, what is stale, and what is broken.

```nu
nu-config doctor            # roots, layout, parse, tools, plugins, modules
nu-config knobs             # every knob, and whether you have overridden it
nu-config module list       # what is enabled, lazy, loaded
```

## Commands

| Command | Does |
|---|---|
| `doctor` | health check: both roots, layout state, files, search paths, parse, tools, plugins, completion caches, modules |
| `knobs [--overridden]` | every knob from `defaults.nu` and every module's `meta.nuon`, with whether your `settings.nu` sets it |
| `module list \| info \| check \| enable \| disable \| lint` | the module system — `docs/modules.md` |
| `tools setup \| status \| remove \| dir` | generated init files for installed third-party tools |
| `ghostty status \| set \| reset` | the terminal's own config, through one included file — see below |
| `plugins list \| add` | the plugin registry |
| `fetch completion <tool>` | vendor one from nu_scripts **into your directory**, never the distro |
| `startup-time [n]` | time N cold interactive starts |
| `loaded-files` | what was parsed this session — find a slow import |
| `edit` / `edit user` | open the distro / your `settings.nu` |
| `distro-root` / `user-root` / `install-status` | where things are |

## Ghostty

`THEME = "terminal"` means the terminal's sixteen colours *are* the Nushell
theme, so choosing a theme means setting Ghostty's. That happens without ever
rewriting the user's config:

```
<ghostty dir>/nushell-distro.ghostty    ours, rewritten whole
config-file = ?nushell-distro.ghostty   one line appended to theirs, once
```

An included file is applied *after* the file that includes it, wherever the
`config-file` line sits, so appending one line is enough — their own `theme =`
never has to be found or edited. The `?` makes a missing include a silent no-op,
so deleting our file is already an uninstall. Their config is copied to
`config.backup-<timestamp>` before the one append, and `ghostty reset` takes
both the file and the line away again, leaving the config byte-identical to what
it was.

`set` asks Ghostty to check its own work (`+validate-config`) and rolls the file
back if it complains — an unknown key or a theme name Ghostty cannot find never
survives. `status` reports the config Ghostty reads, any other candidate that
exists, and the theme Ghostty itself ends up with, which is the only real proof
that the include landed in the file being read.

Ghostty has no `+reload` CLI action, so a write here reaches new windows only;
the running window is repainted over OSC instead.

## Configuration

None. This module is deliberately knob-free: it is what you use when the
configuration is wrong, so it must not depend on the configuration being right.

## Dependencies

None.

## Design

Two facts shape this module.

**It is imported by `install.nu`, which runs as a script.** A script loads no
config, so none of the config's parse-time constants exist. Anything this
module reads from the config must come through `$env` — `$env.NU_LIB_DIRS`,
`$env.NU_SMART_TAB`, `$env.NU_MODULES` — never the `const`. Referencing a const
here makes the module unimportable outside a loaded shell, and the error points
at a line that looks fine.

**`module` is a Nushell keyword.** `module list` is a perfectly good exported
name, but it cannot be *called* from inside this file — the parser reads it as
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
load.nu      `use nu-config`
meta.nuon    description
```

## Limits

`doctor`'s parse check runs `nu-check` on `distro.nu`, which follows every
`source` but does not execute anything — a file that parses can still fail at
runtime.
