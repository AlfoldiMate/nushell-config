# How Nushell starts, and where this distro plugs in

Verified against Nushell 0.115. The full 29-step table is in the book's
[Configuration](https://www.nushell.sh/book/configuration.html) chapter; this is
the part that matters for organising a config, and [Layout](layout.md) is the
map of the two directories it walks.

| # | What Nushell does | What is there |
|---|---|---|
| 1 | `$NU_LIB_DIRS` / `$NU_PLUGIN_DIRS` get their defaults (`<config>/scripts`, `<data>/completions`, `<config>/plugins`, the directory of `nu`) | replaced by `distro.nu`, yours first |
| 2 | `$env.config` is filled from the internal defaults; `PATH` becomes a list | |
| 3 | std library is loaded (not imported); the `$nu` constants are built | |
| 4 | internal `default_env.nu` (the two default prompt closures), then **`<your>/env.nu`** | nothing — the distro ships none, see below |
| 5 | internal `default_config.nu` (`$env.config = {}`), then **`<your>/config.nu`** | three lines: `source` the distro's `distro.nu`, which then does everything in [Layout](layout.md) |
| 6 | **`<your>/login.nu`**, only for `nu -l` | nothing — see below |
| 7 | every `*.nu` in `$nu.vendor-autoload-dirs`, last directory wins | the generated tool init files (`nu-config tools setup`) |
| 8 | every `*.nu` in `$nu.user-autoload-dirs` = `<your>/autoload` | your drop-ins, the last word |

Three consequences:

- **`nu -c '...'` and `nu script.nu` load none of this** (only std and the
  plugin registry). A script that needs a module must `use` it by path.
  `nu -l -c` loads `env.nu`, `config.nu` and `login.nu`, but *not* the autoload
  directories — which is where carapace and zoxide are wired.
- **Autoload files run after `config.nu`**, so nothing in `conf/` can depend on
  them, and they override everything in it. That is what makes
  `<your>/autoload/*.nu` the right place for a machine-local hack.
- **`source` and `use` need parse-time paths.** That is why `distro.nu` derives
  every path from `const DISTRO_ROOT = path self | path dirname`, why an
  optional include is a const `if` around `source null`, and why tool init
  output is written to a file instead of being piped in.

## The two files this distro does not ship

Nushell loads `env.nu` (step 4) and `login.nu` (step 6) from **your** config
directory. The distro used to carry an empty copy of each, seven and twelve
lines of comment explaining why they were empty. The explanation is worth
keeping; the files were not. Neither has to exist, and a missing one is not an
error.

**`env.nu`** is a legacy slot. Since 0.101 everything, environment variables
included, belongs in `config.nu` — here, `conf/env.nu`, which builds `PATH` per
OS and picks the first editor that exists. What Nushell itself sets before that
file runs: `config env --default`.

**`login.nu`** runs only when Nushell is the login shell. A login shell is
responsible for the environment every GUI app and subshell inherits — the job
`/etc/profile` and `~/.zprofile` do for POSIX shells. Nushell cannot read those,
so anything they export has to be re-expressed. Nothing is needed while your
login shell is zsh or bash. To make `nu` the login shell: add its path to
`/etc/shells`, then `chsh -s (which nu | get 0.path)`. Capture what the current
login shell exports, from inside that shell, and keep the lines you actually
need:

```nu
nu -c '$env | reject config | transpose k v | each {|r| $"$env.($r.k) = \"($r.v)\"" } | str join (char nl)'
```

Both files live in your config directory if you ever want them, next to
`config.nu` — they are yours, not the distro's.

## What loads when: the lazy modules

Step 5 is the interesting one, because not all of it happens at step 5.
`defaults.nu` names the enabled modules and, of those, the ones that are *not*
parsed at startup:

```nu
const MODULES = [nu-config nu-complete terminal agent odata]
const MODULES_LAZY = [terminal agent odata]
```

A lazy module is loaded by a `pre_execution` hook on the first line that
mentions it. The hook fires *before* Nushell parses that line, and a hook given
as a **string** is parsed and merged into the global engine state — as if you
had typed it — so `use odata *` inside it is in scope for the very line that
triggered it. Both paths `source` the same `modules/<name>/load.nu`, so how a
module is imported is written down once ([Modules](modules.md)).

What it costs, measured on this machine:

| | |
|---|---|
| the guard, per Enter on a line that matches nothing | 828 ns |
| `terminal`, `agent` | 18 ms each, at first mention |
| `odata` | 97 ms, at first mention |
| a cold interactive start with all three lazy | ~95 ms |

Against what Nushell itself costs — minimum of nine cold starts on an
M-series Mac, `$nu.startup-time`, 2026-09-19:

| | |
|---|---|
| `nu` with an empty config — std and the plugin registry | 47 ms |
| this distro, on top of that | **84 ms** |
| the same configuration before lazy loading (2026-09-18) | 161 ms |

**The limit, and it is inherent:** `pre_execution` never fires for `nu -c` or a
script, so a lazy module is interactive-only. A script must say `use odata *`
itself. Move a name out of `MODULES_LAZY` in your `settings.nu` to have it
always loaded; `nu-config module list` shows the current state, and
`nu-config loaded-files` shows what was actually parsed this session, which is
how you find a slow import ([Enable a module, make it lazy, see what it costs](../cookbook/modules.md)).

`agent` is the one module with a `stub.nu`: it is sourced unconditionally
because every shell has to mint a session id and bind Alt+E, and that costs
nothing next to the 18 ms module body.

## Paths on this platform

```nu
$nu.config-path             # your config.nu — the distro is one `source` away from it
$nu.data-dir                # vendor/autoload and .state/ live under here
$nu.vendor-autoload-dirs    # all of them, in load order
$nu.user-autoload-dirs      # <your>/autoload
$nu.plugin-path             # plugin.msgpackz, per machine
$nu.cache-dir               # completion and schema caches
```

`nu-config doctor` prints them all, with both roots and the layout state, and
checks that they line up.
