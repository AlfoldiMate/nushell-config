# Test a change to the distro before it is live

The distro is a live shell configuration: an edit takes effect in the next
terminal, and a parse error breaks every new terminal. So a change is tested
in a shell that loads it for real — and, if the checkout you are editing is
not the one your `config.nu` points at, in a shell pointed at *yours*.

## Which checkout is live

```nu
nu-config distro-root        # what your config.nu sources
```

If that is the directory you are editing, every command below works as
written. If you develop in a second clone (say `~/.config/nushell` while
`~/.local/share/nushell-distro` is live — the case this page was written
from), `nu -l` keeps loading the live one, and nothing you run in it says
anything about your edit. Point a scratch `config.nu` at yours:

```nu
mkdir /tmp/nu-scratch
$"const DISTRO = (pwd | to nuon)\nsource \($DISTRO | path join distro.nu\)\n" | save -f /tmp/nu-scratch/config.nu
nu -l --config /tmp/nu-scratch/config.nu -c 'nu-config distro-root'   # yours
```

`--config` replaces `config.nu` only. `$nu.data-dir` is unchanged, so
`.state/`, `vendor/autoload/` and the caches are your real ones; but
`USER_ROOT` derives from `$nu.config-path`, so it *is* the scratch directory:
your real `settings.nu` and `autoload/` are not loaded, and a `settings.nu`
next to the scratch `config.nu` is what gets read. That is also how to
override a knob for one measurement — `const MODULES_LAZY = [agent odata]`
there makes `terminal` eager without touching your own file.

Run on 2026-09-19: `distro-root` printed the checkout, `user-root` the
scratch directory, `install-status` still `split`.

## The three checks

```nu
nu-check distro.nu                       # parse, following every `source` — the check that would break terminals
nu -l -c 'nu-config doctor'              # loads the config for real; every section ok
nu -n -c '<snippet>'                     # one snippet, no config at all
```

With a scratch config, the middle one is `nu -l --config /tmp/nu-scratch/config.nu -c 'nu-config doctor'`.

`nu-check distro.nu` does not reach a **lazy** module, which is sourced by a
hook string at runtime; a syntax error there survives every startup and shows
up when someone types its name. `nu-config module lint` runs `nu-check` on
every module's `load.nu` and is the only check that covers them:

```nu
nu -l -c 'nu-config module lint'         # an empty table is the pass
```

`nu -n` has no `NU_LIB_DIRS`, so `nu-check` on a file that imports a module
reports `false` there for reasons unrelated to the file — `nu -n -c
'nu-check modules/nu-config/mod.nu'` is `false`, `nu -l -c` of the same is
`true` (2026-09-19). To exercise one module in isolation under `nu -n`, name
the search path as a const or import by path:

```nu
nu -n -c 'const NU_LIB_DIRS = ["modules"]; use terminal *; theme slug "A B"'    # a-b
nu -n -c 'use modules/terminal *; theme slug "A B"'
```

## The suite

```nu
nu tests/run.nu                          # every test; exit 1 when one fails
nu tests/run.nu completion               # the files or tests named like it
```

Each shell a test starts runs against a config directory of its own under
the run's scratch directory — `settings.nu`, `autoload/`, history, `.state/`
all there, deleted at the end — so the suite proves the checkout you are in,
whichever one is live, and leaves yours alone. Run on 2026-09-19: `135 passed,
0 failed, 0 skipped · 6.7 s`. [Tests](../reference/tests.md) is how to
write one.

## What each kind of change needs

| changed | check |
|---|---|
| `defaults.nu`, `conf/*.nu`, `distro.nu` | `nu-check distro.nu`, then `doctor` |
| a module | `module lint`, then the module's own reference page's *Verify* or *Testing* section |
| a completion | `commandline complete --detailed` on the slots, `timeit` on each ([Debug Tab](debug-tab.md)) |
| a theme template or palette | `theme resolve <name>`, `theme roles <name>` — nothing written; then `theme sync` |
| anything on the startup path | `nu-config startup-time` before and after, or the `--config` form of it: `1..15 \| each { ^$nu.current-exe -l --config /tmp/nu-scratch/config.nu -c '$nu.startup-time' \| into duration } \| math min` |
| the installer | `nu install.nu --dry-run`, then a real run with `XDG_CONFIG_HOME` pointed at a scratch directory |
| the docs | every command in the page, run as written |
| anything with a test | `nu tests/run.nu <its name>`, then the whole suite before the commit |

`nu -c '…'` and `nu script.nu` deliberately load no user config at all, so
they prove nothing about any of this. CI runs the installer, `nu-check`,
`module lint`, `doctor` and the suite on all three platforms
([Platforms](../reference/platforms.md)).

## Then make it live

If the checkout you edited is the live one, the next terminal has it. If it
is a second clone, commit, push, and `nu-config upgrade` in the live one — or
point `config.nu` at the clone you edit, which is the arrangement this page
assumes you did not want.
