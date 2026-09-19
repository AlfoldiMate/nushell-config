# Nushell distro

A [Nushell](https://www.nushell.sh) configuration you **install** rather than
copy. The distro is a git checkout you never edit; your settings live in your
own config directory, in a file the distro does not ship. `git pull` updates one
without touching the other, and a knob you never mention keeps tracking the
distro. Verified on Nushell **0.115**, on macOS, Linux and Windows by CI on
every push.

```sh
# macOS, Linux
curl -fsSL https://raw.githubusercontent.com/AlfoldiMate/nushell-config/main/bootstrap/install.sh | sh
```

```powershell
# Windows
irm https://raw.githubusercontent.com/AlfoldiMate/nushell-config/main/bootstrap/install.ps1 | iex
```

Those two scripts have exactly two jobs — make sure `nu` exists, and clone this
repo — and then hand over to `install.nu`, which is the installer proper and is
written in the shell it installs. Read either one before running it; they are
short on purpose. Already have Nushell and a checkout? Skip them:

```nu
git clone https://github.com/AlfoldiMate/nushell-config ~/.local/share/nushell-distro
nu ~/.local/share/nushell-distro/install.nu
```

`install.nu` is seven screens and every one of them is skippable: where things
go, which modules to enable, your terminal (and that a new Ghostty window
starts Nushell), the theme (previewed by painting the live terminal), the font,
the tools it finds, and then the plan. Nothing is written before you say yes to
that last screen.

```nu
nu install.nu              # the seven screens
nu install.nu --defaults   # no questions, every shipped value
nu install.nu --dry-run    # print the plan, change nothing
```

It writes a three-line `config.nu` into Nushell's own config directory pointing
at the checkout, gives you a `settings.nu` of your own, generates the init files
for whichever tools are installed and registers the plugins that ship with `nu`.
Safe to re-run after every `git pull`, tool install or Nushell upgrade. Undo at
any time: delete that `config.nu` and delete the checkout.

## Two directories

```
YOUR config directory                     THE DISTRO (this checkout)
~/Library/Application Support/nushell     ~/.local/share/nushell-distro
  config.nu        3 lines, points here ──▶  distro.nu     entrypoint
  settings.nu      your overrides            defaults.nu   every knob, shipped value
  autoload/*.nu    drop-ins, loaded last     conf/         behaviour
  completions/     what you fetched          modules/ completions/ themes/
  themes/          your themes               templates/ docs/
  plugins/         plugins you built
  history.sqlite3, plugin.msgpackz, vendor/, .state/
```

Nushell only ever knows about the left-hand side: it loads `config.nu` from its
own config directory and derives history, the plugin registry, the autoload
directories and `$nu.data-dir` from that same place. **Nothing you own is ever
written inside the checkout** — which is what keeps `git pull` clean, and is the
whole design. `docs/layout.md` has the reasoning, the load order and the
platform table.

## Configure

Start with **your** `settings.nu`, next to your `config.nu`:

```nu
nu-config edit user          # opens it, from a commented template the first time
nu-config knobs              # all 65 knobs, their shipped value, and yours
nu-config knobs --overridden # just yours
```

It is sourced immediately after the distro's `defaults.nu`, so a `const` there
shadows the one here and an `$env.` assignment replaces it. **You override by
mentioning.** A knob you never write down keeps its shipped value, including one
added by a later `git pull` — there is no schema to migrate and no generated
file to regenerate, because the layering is a language feature rather than a
build step.

`defaults.nu` is the catalogue: read it, copy the line you want, change it in
your file. Every `$env.config` key that exists, whether this distro mentions it
or not:

```nu
config nu --doc | nu-highlight | less -R
```

Two user layers, and the difference matters: **values** go in `settings.nu`,
**behaviour** — a hook, a keybinding, a machine-local secret, a module of your
own — goes in a `.nu` file in your `autoload/`. Those load after everything else
and win.

## Extend

| Want to | Do |
|---|---|
| Change a setting | your `settings.nu` — `nu-config edit user` |
| Add an alias, a hook, a keybinding | a file in your `autoload/`, loaded last |
| Add a module | drop it in your `modules/`, `use` it from `settings.nu`; `docs/modules.md` is the contract `nu-config module lint` enforces |
| Turn a shipped module off | `const MODULES = [...]` without it, or `nu-config module disable <name>` |
| Add completions for a tool | `nu-config fetch completion <tool>` vendors one from nu_scripts into your `completions/`, then `use <tool>-completions.nu *` in `settings.nu`. To write one: `agent completion <tool>`, or `completions/README.md` by hand |
| Change the theme | `theme` — pick one of Ghostty's 463 with the whole terminal as the preview. See *Theming* below |
| Wire up a tool that emits a Nushell init file | add it to the registry in `modules/nu-config/tools.nu`, run `nu-config tools setup` |
| Wire up a tool that does not | a file in your `autoload/`, guarded with `which` |
| Add a plugin | put the binary in your `plugins/`, `plugin add <name>`, restart — `docs/plugins.md` explains why that is all there is |

Your `modules/`, `completions/` and `themes/` come **first** on `NU_LIB_DIRS`,
before the distro's. So a bare name resolves to your copy if you have one and
the shipped copy otherwise — copying a shipped file into your own directory and
editing it is the entire override mechanism, for themes and completions alike.

## Startup

A distro that claims to be fast should print the number. Minimum of nine cold
starts on an M-series Mac, `$nu.startup-time`, 2026-09-19:

| | |
|---|---|
| `nu` with an empty config — std and the plugin registry | 47 ms |
| this distro, on top of that | **84 ms** |
| the same configuration before lazy loading (2026-09-18) | 161 ms |

The difference is that the three biggest modules are not parsed at startup at
all. A `pre_execution` hook loads one on the first line that mentions it:

| module | cost, paid at first mention |
|---|---|
| `odata` | 97 ms |
| `agent`, `terminal` | 18 ms each |
| the guard, per Enter on a line that mentions none of them | 828 ns |

The catch is inherent and worth knowing: `pre_execution` does not fire for
`nu -c` or a script, so a lazy module is interactive-only and a script must
`use` it itself. `docs/startup-order.md` has the mechanism; `nu-config
startup-time` and `nu-config loaded-files` are how you check a change did not
cost anything.

## Completion

Tab opens a one-entry-per-line menu driven by `modules/nu-complete`
(`docs/completion.md` has the design and the measurements). Nushell's own
completer still answers first; the engine adds what needs more context:

- **Pipelines.** `ls | where <Tab>` offers `name`, `type`, `size`, `modified`
  with a sample value; `where size <Tab>` only the operators a filesize
  accepts; `where type == <Tab>` the values `file` and `dir`. Works for
  `get`, `select`, `sort-by`, `update`, nested paths (`get package.<Tab>`),
  closure params (`each {|r| $r.<Tab>}`) and aliases (`ll | where`). The
  pipeline runs in a subprocess only when every command in it is a read-only
  built-in; the `NU_COMPLETE_EVAL` knob widens or disables that.
- **Tools.** `brew install <Tab>` lists every formula and cask with its
  description in 3 ms, from Homebrew's own cache (carapace: 1.6 s). `git
  checkout <Tab>` lists branches by recency, then remotes and tags; `git add`
  the changed files; `git push` the remotes. Each is a spec in
  `completions/<tool>.nu`; carapace answers whatever a spec leaves open.
- **Less noise.** Nothing after commands that take no argument (`ps <Tab>`
  used to list the directory), no duplicate entries.

`SMART_TAB = false` returns to Nushell's stock menu.

| Key | Does |
|---|---|
| Tab | completion menu |
| Ctrl+R | atuin history search (Nushell's history menu when atuin is absent) |
| F1 | help menu |
| → | accept the inline history hint |

## Theming

The default theme, `"terminal"`, is sixteen ANSI colour **names** and no hex, so
the terminal's palette *is* the theme. That makes the terminal the source of
truth, and theming the shell means theming the terminal:

```nu
theme                        # scroll Ghostty's 463 themes; the live window is the preview
theme use "Catppuccin Mocha" # by name, no picker
theme list                   # every theme, with its sixteen colours
theme reset                  # back to what Ghostty had before
```

Nothing is generated and there is nothing to keep in sync — `VIVID_THEME` (`ls`
colours) and `BAT_THEME` (`bat`, `help`, git diffs) default to `"ansi"` for the
same reason and follow along. For a palette that ignores the terminal there are
the four Catppuccin flavours, `const THEME = "catppuccin-mocha"`; for one of your
own, drop a file into your `themes/` and name it in `THEME`. `themes/README.md`
is the guide.

The same module configures the terminal itself: `terminal current` says what you
are running in, `terminal install` offers to install Ghostty, `ghostty shell`
makes Nushell what a new window starts, `ghostty settings` shows what this
config set and `font` installs one of fifteen Nerd Fonts and previews it in a
window of its own.

## Agent

With Claude Code installed, four verbs share one Claude session per shell
(`docs/agent.md` has the design, the measured costs and the knobs):

```nu
agent ask how many files are here, and which is the newest?   # computed with nu pipelines
agent exec kill whatever listens on port 8080   # proposes; Enter runs it here, i inserts, r revises
agent skill nushell what does def --env do      # Tab completes skill names
agent command context                           # any slash command
agent completion gh                             # teach Tab a tool: completions/gh.nu, built and verified
ls | agent ask which of these is a log?         # piped input joins the prompt
```

`agent exec` never runs anything itself: the line you accept executes in this
shell, in your history, and anything matching the `AGENT_CONFIRM` knob asks for a
typed yes first. Alt+E turns the line you are typing into a proposal. A session
whose shell closed is checkpointed into agmem by the next shell that starts.

## OData

OData V2 and V4 services, SAP Gateway included, as tables
(`modules/odata/README.md`):

```nu
odata service add erp https://host/sap/opu/odata/sap/ZMY_SRV/ --user me -P {sap-client: "100"}
odata entities                                   # from $metadata, cached a week
odata SalesOrders 4711 Items                     # one entity, then a navigation; keys quoted from the schema
odata People | where FirstName =~ Ru | select UserName | first 5   # runs on the server as $filter/$select/$top
odata People | where Gender == Male | expand Trips | length         # $filter, $expand, /$count
odata count Orders -f "Freight gt 100"
{FirstName: Zed} | odata update People russellwhyte   # PATCH, with SAP's CSRF token when needed
```

Tab knows the services, entity sets, fields, navigations and enum values from the
cached `$metadata`, also after `| where`. Nushell cannot overload `where`, so a
`pre_execution` hook plans the pushdown and `odata get` applies it; the Nushell
stages still run on the result. `expand` is the module's own stage.

## Tool integrations

Nushell cannot `eval` shell script, so tools emit a `.nu` file instead.
`nu-config tools setup` writes those into `$nu.data-dir/vendor/autoload`, where
Nushell loads them after `config.nu`. Installation is the switch: an installed
tool gets its file, an absent one gets nothing, a stale file is removed.
Currently in the registry: **zoxide**, **atuin**, **carapace**, **vivid** (baked
into a literal because calling it at every start costs milliseconds for nothing).
Starship is wired in `conf/prompt.nu` by hand so the vi indicators stay in
control. Homebrew's command-not-found and direnv are in `conf/tools.nu`.

## Plugins

Nushell has no plugin manager. `plugin add/list/rm/use/stop` all edit one
registry file and none of them fetches, builds or versions anything, so
`nu-config plugins add` is that same built-in mechanism run over the
`nu_plugin_*` binaries your package manager installed next to `nu`:

```nu
nu-config plugins list     # what is there, and what is registered
nu-config plugins add      # after every `brew upgrade nushell` — the registry is protocol-versioned
```

`docs/plugins.md` is the whole story, including where a plugin you built
yourself goes.

## Maintenance

```nu
nu-config doctor           # both roots, layout, paths, parse check, tools, plugins, startup time
nu-config knobs            # every knob, and whether you have overridden it
nu-config module list      # enabled, eager or lazy, measured cost, dependencies
nu-config tools status     # installed vs generated
nu-config plugins add      # after `brew upgrade nushell`
nu-config startup-time     # cold starts; regression-check after adding anything
nu-config loaded-files     # what was parsed this session; find a slow import
nu-config edit             # open the distro in $EDITOR
nu-config edit user        # open your settings.nu
nu-complete status         # completion caches: brew package db, specs, session memo
```

Verify a change to the distro with a shell that loads the config, not with
`nu -c`:

```nu
nu-check distro.nu               # parse only, follows every `source`
nu -l -c 'nu-config doctor'      # loads the config for real
nu -n -c '<snippet>'             # isolated snippet, no config
```

`nu -c '...'` and `nu script.nu` deliberately load no user config at all.

## How Nushell finds this distro

Nushell derives every path it uses — autoload dirs, plugin registry, history,
`$nu.data-dir` — from its config directory, so the only thing that has to point
here is the `config.nu` in that directory. Three lines, written by `install.nu`:

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

## Where everything is

| | |
|---|---|
| `docs/layout.md` | the two directories, the layering, formats, platforms — the map |
| `docs/startup-order.md` | what Nushell loads when, and how lazy modules work |
| `docs/modules.md` | the module contract: `mod.nu`, `load.nu`, `meta.nuon`, README |
| `docs/completion.md` | how Tab works here, with costs |
| `docs/plugins.md` | why there is no plugin manager |
| `docs/agent.md` | the agent verbs: design, measured costs, knobs, limits |
| `completions/README.md` | writing a completion module for a tool |
| `themes/README.md` | the shipped themes, and writing one |
| `modules/*/README.md` | one per module: what it is, its commands, its knobs |
