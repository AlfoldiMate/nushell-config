# The distro and your directory

This configuration is two directories, not one.

```
YOUR config directory                     THE DISTRO (a git checkout)
~/Library/Application Support/nushell     ~/.local/share/nushell-distro
  config.nu        3 lines, points here ──▶  distro.nu     entrypoint
  settings.nu      every knob, commented     defaults.nu   every knob, shipped value
  README.md        what is here, and whose   conf/         behaviour
  autoload/*.nu    drop-ins, loaded last     modules/ completions/ themes/
  completions/     what you fetched          templates/user/  the scaffold of the left-hand side
  themes/          your themes               docs/
  plugins/         plugins you built
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

## How Nushell finds the distro

Nushell derives every path it uses — autoload dirs, plugin registry, history,
`$nu.data-dir` — from its config directory, so the only thing that has to point
at the checkout is the `config.nu` in that directory. Three lines, written by
`install.nu`:

```nu
const DISTRO = "/home/you/.local/share/nushell-distro"
source ($DISTRO | path join distro.nu)
```

The checkout stays outside the config directory, which is what keeps `git pull`
clean and keeps history, `plugin.msgpackz` and generated files out of version
control. Alternatives that were rejected: symlinking the config directory at the
checkout (user state lands in the repo, and on macOS `$nu.data-dir` *is* the
config directory, so generated files land there too), `XDG_CONFIG_HOME` (shared
with every other app, and must be set before `nu` starts), `nu --config` (only
redirects two files, and must be repeated at every launch site).

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
knobs cannot be read from a NUON file and why `settings.nu` is `.nu`
([Files and formats](../reference/files.md)).

**The test that the layering is right:** accept every default in the installer
and your `settings.nu` has no live assignment in it at all — `nu-config knobs
--overridden` comes back empty, against 64 knobs that exist (2026-09-19). Every knob *is*
in the file, commented out at its shipped value, so that the file you open is
the list; but a commented line is not a mention, and a value you never
mention keeps tracking the distro, including across a `git pull` that changes
it ([Your directory](../cookbook/user-directory.md)).

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

A module's knobs are the exception that proves it: they are not in
`defaults.nu` at all. A module declares them in its `meta.nuon` and applies
them in `activate` with `default`, never assignment, so your `settings.nu`
still wins ([Modules](modules.md)).

## Load order

1. `<your>/config.nu` — sources the distro
2. `defaults.nu` — every knob, shipped values
3. `<your>/settings.nu` — your overrides *(optional)*
4. `conf/*.nu` — behaviour, reading the values settled above
5. `use nu-config` — maintenance commands
6. `$nu.vendor-autoload-dirs/*.nu` — generated tool init files
7. `<your>/autoload/*.nu` — your drop-ins, the last word

Steps 6 and 7 are Nushell's own doing, not this config's; [Startup](startup.md)
has Nushell's side of the table and what the lazy modules do to step 4.

## Search paths

`NU_LIB_DIRS` lists **your** directories first:

```
<your>/modules  <your>/completions  <your>/themes
<distro>/modules  <distro>/completions  <distro>/themes
```

So `use git.nu *` resolves your copy if you have one and the shipped copy
otherwise. Copying a shipped completion into your own `completions/` and
editing it is the whole override mechanism
([Override a shipped completion](../cookbook/override-completion.md)); the same
holds for a theme template or a palette in your `themes/`.

`NU_PLUGIN_DIRS` is the same shape: your `plugins/`, then the directory `nu`
itself lives in ([Plugins](plugins.md)).

## Where a thing goes

| Want to | Do |
|---|---|
| Change a setting | uncomment it in your `settings.nu` — `nu-config edit user` |
| See what is in your directory, get a README or an example back | `README.md` there; `nu-config user status`, `nu-config user init` ([Your directory](../cookbook/user-directory.md)) |
| Add an alias, a hook, a keybinding | a file in your `autoload/`, loaded last |
| Add a module | drop it in your `modules/`, `use` it from `settings.nu`; [Modules](modules.md) is the contract `nu-config module lint` enforces |
| Turn a shipped module off | `const MODULES = [...]` without it, or `nu-config module disable <name>` |
| Add completions for a tool | `agent completion <tool>`, or by hand ([Add Tab completion for a tool](../cookbook/add-completion.md)) |
| Change the theme | `theme` ([Theming](theming.md)) |
| Wire up a tool that emits a Nushell init file | add it to the registry in `modules/nu-config/tools.nu`, run `nu-config tools setup` |
| Wire up a tool that does not | a file in your `autoload/`, guarded with `which` |
| Add a plugin | put the binary in your `plugins/`, `plugin add <name>`, restart ([Plugins](plugins.md)) |

`nu-config doctor` reports the layout as `split` (the target), `in-place` (the
checkout is still doubling as the config directory — run `nu install.nu`) or
`other` (something else is live).
