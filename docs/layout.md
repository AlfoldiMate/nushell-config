# Layout: the distro and your directory

This configuration is two directories, not one.

```
YOUR config directory                     THE DISTRO (this checkout)
~/Library/Application Support/nushell     ~/.local/share/nushell-distro
  config.nu        3 lines, points here ──▶  distro.nu     entrypoint
  settings.nu      your overrides            defaults.nu   every knob, shipped value
  autoload/*.nu    drop-ins, loaded last     conf/         behaviour
  completions/     what you fetched          modules/ completions/ themes/
  themes/          your themes               templates/    what install.nu writes
  plugins/         plugins you built         docs/
  history.sqlite3, plugin.msgpackz, vendor/, .state/
```

Nushell only ever knows about the left-hand side. It loads `config.nu` from its
own config directory and derives everything else — history, the plugin
registry, the autoload directories, `$nu.data-dir` — from that same directory.
Your `config.nu` then sources the distro.

## Why

The obvious layout is to clone the repo *into* the config directory and be
done. That is what this configuration used to do, and it has three problems
that get worse the moment anyone else uses it:

- **Every `git pull` is a conflict.** The file you are told to edit
  (`settings.nu`) is a file the distro also ships.
- **User state lands in a git repository.** `history.sqlite3`,
  `plugin.msgpackz`, generated tool init files and module state all get written
  next to `config.nu`, which is inside the checkout. The old `.gitignore` spent
  most of its lines excluding them.
- **On macOS it is worse still.** `$nu.data-dir` is the config directory there,
  so `nu-config tools setup` wrote generated files *into the repo*.

Splitting the two fixes all three at once, and the `.gitignore` drops to four
lines.

## How the layering works

`distro.nu` sources `defaults.nu`, then your `settings.nu`, then `conf/`:

```nu
source ($DISTRO_ROOT | path join defaults.nu)   # const SMART_TAB = true
source $USER_SETTINGS                           # const SMART_TAB = false
```

A `const` in a later `source` **shadows** an earlier one, and a later `$env.`
assignment overwrites an earlier one. So `$SMART_TAB` is `false`, and
`conf/completions.nu` — which runs afterwards and reads `$SMART_TAB` — sees
your value.

Two consequences worth stating plainly:

- **You override by mentioning.** A knob you never write down keeps its shipped
  value, *including a knob added by a later `git pull`*. There is no schema to
  migrate and no generated file to regenerate.
- **No codegen.** The layering is a language feature, not a build step. Nothing
  compiles `settings.nu` into anything.

The optional include is guarded at parse time, because a missing `settings.nu`
must not be a parse error — that would mean no shell at all:

```nu
const USER_SETTINGS_PATH = ($USER_ROOT | path join settings.nu)
const USER_SETTINGS = (if ($USER_SETTINGS_PATH | path exists) { $USER_SETTINGS_PATH } else { null })
source $USER_SETTINGS     # `source null` is a no-op
```

`if` and `path exists` are const-evaluable in Nushell 0.115, which is what
makes that work. `open` and `from nuon` are **not**, which is why the enabled
knobs cannot be read from a NUON file and why `settings.nu` is `.nu`.

## Values versus behaviour

The split is also a rule about what goes where:

| | holds | you edit it |
|---|---|---|
| `defaults.nu` | values only — one flat list of every knob | no, you copy lines out of it |
| `conf/*.nu` | behaviour — hooks, menus, keybindings, wiring | no |
| `settings.nu` | your values | yes |
| `autoload/*.nu` | your behaviour | yes |

That is why `conf/shell.nu` and `conf/settings.nu` no longer exist: both were
lists of plain assignments, so both became `defaults.nu`. What is left in
`conf/` genuinely computes something — `conf/env.nu` builds `PATH` per OS and
picks the first editor that exists, `conf/theme.nu` loads the rendered theme.

The rule that makes layering work: **a `conf/` file must never assign a value
`defaults.nu` owns.** It would run after your `settings.nu` and silently
overwrite it.

## Formats

Two formats, and a reason for each:

| | |
|---|---|
| `.nu` | anything the **parser** must see: `defaults.nu`, `settings.nu`, the enabled modules, themes |
| NUON | anything tooling reads at **runtime**: module `meta.nuon`, state, registries, caches |

`.nu` is not a style choice. `open` and `from nuon` are not const-evaluable in
0.115 (`scope commands | where is_const` lists `path exists`, `if`, `path join`
and the `str` commands — not `open`), so a value the parser has to know cannot
come from a data file. Everything else is NUON: it is Nushell's own literal
syntax, so a state file reads like the record it is and `open` needs no `--raw`
and no converter.

No JSON — with two measured exceptions, both machine-written caches that sit on
the Tab path:

| | |
|---|---|
| `$nu.cache-dir/nu-complete/brew-spec.json` | 195 kB: 1.2 ms as JSON, 7.8 ms as NUON |
| `$nu.cache-dir/odata/<service>.json` | 25 kB: 0.47 ms as JSON, 3.0 ms as NUON |

NUON's parser costs about **6x per byte** at every size tried, which is nothing
for a 160 B registry (81 µs against 51 µs) and is most of a keystroke's budget
for a 195 kB spec. Both files carry a comment saying so. The rule those two bend
is worth keeping anyway: the files a *person* opens — `.state/odata/services.nuon`,
`.state/agent/sessions/*.nuon` — are NUON, and none of them is large.

Files rendered for another tool are in that tool's format, and are read only by
it: `.state/theme/starship.toml` and `.state/theme/ls_colors` (`theme use`),
`vendor/autoload/*.nu` (`nu-config tools setup`).

Written NUON is `to nuon --indent 2`: one key per line, so a diff shows the line
that changed rather than the whole file, and empty or null fields are dropped
before saving rather than stored as `{}`.

## Load order

1. `<your>/config.nu` — sources the distro
2. `defaults.nu` — every knob, shipped values
3. `<your>/settings.nu` — your overrides *(optional)*
4. `conf/*.nu` — behaviour, reading the values settled above
5. `use nu-config` — maintenance commands
6. `$nu.vendor-autoload-dirs/*.nu` — generated tool init files
7. `<your>/autoload/*.nu` — your drop-ins, the last word

Steps 6 and 7 are Nushell's own doing, not this config's.

## Search paths

`NU_LIB_DIRS` lists **your** directories first:

```
<your>/modules  <your>/completions  <your>/themes
<distro>/modules  <distro>/completions  <distro>/themes
```

So `use git.nu *` resolves your copy if you have one and the shipped copy
otherwise. Copying a shipped completion into your own `completions/` and
editing it is the whole override mechanism.

## Installing

`install.nu` is seven screens, and every one of them is skippable:

| | |
|---|---|
| 1. Where | the checkout, and your config directory — Nushell's own, unless you set `XDG_CONFIG_HOME` |
| 2. Modules | multi-select, with each module's measured startup cost and its dependency state |
| 3. Terminal | is Ghostty installed, are you *running* in it, the install line if not — and whether a new window starts Nushell (the one question whose default is yes) |
| 4. Theme | one of Ghostty's 463, previewed by painting the live terminal, then rendered for tables, `ls`, bat and the prompt |
| 5. Font | fifteen Nerd Fonts, installed on the spot, previewed in a Ghostty window of their own |
| 6. Tools | which of zoxide / atuin / carapace / vivid / starship are present. Nothing is installed here |
| 7. The plan | every line that will be written, then one yes |

```nu
nu install.nu              # the seven screens
nu install.nu --defaults   # no questions, every shipped value
nu install.nu --dry-run    # print the plan, change nothing
```

Nothing is written before screen 7 — the theme preview paints the terminal and
`theme reset` hands it back, so even a cancelled installer leaves Ghostty's
configuration alone. Fonts are the exception, because a font has to exist
before it can be rendered; the installer asks before downloading one.

With no terminal on stdin and stdout the installer takes every default by
itself, which is what makes `curl … | sh` work without a flag.

**The test that the layering is right:** accept every default and your
`settings.nu` has no assignments in it at all — `nu-config knobs --overridden`
comes back empty, against 65 knobs that exist. Nothing is copied out of
`defaults.nu` "so you can see it". A value you never mention keeps tracking the
distro, including across a `git pull` that changes it.

## Checking it

```nu
nu-config doctor            # both roots, the layout state, parse, tools, plugins
nu-config knobs             # every knob, and whether you have overridden it
nu-config knobs --overridden
nu-config edit user         # your settings.nu
```

`nu-config doctor` reports the layout as `split` (the target), `in-place` (the
checkout is still doubling as the config directory — run `nu install.nu`) or
`other` (something else is live).

## Updating

```nu
nu-config upgrade            # git pull --ff-only in the checkout, and what came in
nu-config upgrade check      # fetch now and say where the checkout stands
nu-config upgrade status     # the last check's result, no network
```

You do not have to remember to: once every `UPDATE_CHECK_EVERY` (a day) an
interactive shell spawns a background job that fetches, and the next start
prints one line when the checkout is behind. The fetch is never on the startup
path — a start reads the last result out of `<your>/.state/nu-config/
upgrade.nuon` (0.3 ms) — and the line is keyed to the HEAD the check saw, so it
disappears as soon as HEAD moves, by `nu-config upgrade` or by hand. `nu -c` and
scripts neither print nor spawn anything. `conf/update.nu` is the wiring,
`modules/nu-config/upstream.nu` the commands.

## Verifying a change to the distro

```nu
nu-check distro.nu                 # parse only, follows every `source`
nu -l -c 'nu-config doctor'        # loads the config for real
nu -n -c '<snippet>'               # isolated snippet, no config
```

`nu -c '...'` and `nu script.nu` deliberately load no user config at all, so
they prove nothing about this file. Note that `nu -n` also has no
`NU_LIB_DIRS`, so `nu-check` on a file that imports a module will report
`false` there for reasons that have nothing to do with the file.

## Platforms

`.github/workflows/ci.yml` runs the real installer and then loads the config for
real on macOS, Linux and Windows, every push: install, `install-status` is
`split`, `nu-check distro.nu`, `nu-config module lint`, `nu-config doctor`, and
a default install leaving no overrides behind.

That is the floor, and it is worth being exact about the ceiling. What is
actually exercised, per platform:

| | macOS | Linux | Windows |
|---|---|---|---|
| parses, installs, loads | CI, and by hand | CI | CI |
| `bootstrap/install.sh` | by hand: clone, re-run as fast-forward, and the release-tarball path with `nu` off PATH | `sh -n` only | n/a |
| `bootstrap/install.ps1` | n/a | n/a | parse only |
| theme picker, Ghostty config | by hand | not run — no Ghostty on the runner | Ghostty has no Windows build |
| font install | by hand, archive path; the Homebrew cask path is not run | not run; `fc-cache` branch unexercised | not run; the `HKCU\…\Fonts` registry step is written from the docs only |
| `port` | `lsof`, by hand | `lsof`, not run | the `netstat -ano` branch, not run |

The pattern in everything above: what a platform *cannot* do is stated rather
than papered over. `terminal install` on Windows prints the download page and
runs nothing, because there is no Ghostty build to install; `port` errors with
the command to use instead when `lsof` is absent, rather than returning an
empty table that would read as "nothing is listening".

Two things that look platform-specific and are not: `duh` uses Nushell's own
`du`, which is a built-in and takes `--max-depth` on every platform, and `tree`
/ `lt` / `rgt` want `eza` and `ripgrep` but are `alias` and `def`, so a missing
tool costs a "command not found" the moment you use one and nothing at startup.

## Undoing it

Delete your `config.nu` (or point `DISTRO` at something else) and delete the
checkout. Nothing else in your config directory belongs to the distro.
