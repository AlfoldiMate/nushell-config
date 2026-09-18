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
source ($DISTRO_ROOT | path join defaults.nu)   # const THEME = "terminal"
source $USER_SETTINGS                           # const THEME = "catppuccin-mocha"
```

A `const` in a later `source` **shadows** an earlier one, and a later `$env.`
assignment overwrites an earlier one. So `$THEME` is `catppuccin-mocha`, and
`conf/theme.nu` — which runs afterwards and reads `$THEME` — sees your value.

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
picks the first editor that exists, `conf/theme.nu` applies `$THEME`.

The rule that makes layering work: **a `conf/` file must never assign a value
`defaults.nu` owns.** It would run after your `settings.nu` and silently
overwrite it.

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
| 3. Terminal | is Ghostty installed, are you *running* in it, and the install line if not |
| 4. Theme | the Nushell theme, and — when it is `"terminal"` — one of Ghostty's 463, previewed by painting the live terminal |
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
comes back empty, against 64 knobs that exist. Nothing is copied out of
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

## Undoing it

Delete your `config.nu` (or point `DISTRO` at something else) and delete the
checkout. Nothing else in your config directory belongs to the distro.
