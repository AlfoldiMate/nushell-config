# Nushell configuration

A [Nushell](https://www.nushell.sh) configuration built the way Nushell 0.101+
intends: defaults stay inside the binary, only overrides are written down, one
concern per file, every path derived from the repo's own location. Clone it
anywhere, run one script, done. Verified on Nushell **0.115**.

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

`install.nu` writes a three-line `config.nu` into Nushell's own config
directory pointing at the checkout, gives you a `settings.nu` of your own,
generates the init files for whichever tools are installed and registers the
plugins that ship with `nu`. It is safe to re-run after every `git pull`, tool
install or Nushell upgrade, and `--dry-run` prints the plan without touching
anything. Nothing you own is ever written inside the checkout — `docs/layout.md`
explains why that is the whole design.

## Layout

```
config.nu             entrypoint: search paths + the ordered list of conf/ files
env.nu, login.nu      empty; here because Nushell loads them
install.nu            bootstrap (see above)
conf/
  settings.nu         the knobs: theme, editor, vi/emacs, history, table style
  env.nu              PATH, $EDITOR, environment variables
  shell.nu            tables, errors, filesystem, terminal integration
  theme.nu            applies THEME from settings.nu
  prompt.nu           starship when installed, Nushell's prompt otherwise
  keybindings.nu      keybindings, menus, abbreviations (Nushell defaults)
  completions.nu      completion: the engine, the tool specs, the smart Tab menu
  aliases.nu          aliases and small commands
  tools.nu            hooks for tools without an init file (brew, direnv)
  odata.nu            OData services as tables: the module, the pushdown hook, the menu provider
modules/nu-config/    maintenance commands (`help nu-config`)
modules/nu-complete/  the completion engine: spec runner, caches, the smart Tab menu
modules/agent/        Claude Code in the shell: agent ask | exec | skill | command (its README is the guide)
modules/terminal/     the terminal itself: `theme` picks one of Ghostty's 463, `ghostty` writes its config
modules/odata/        OData V2/V4 (SAP Gateway) clients: odata <entity> | where ... runs on the server
completions/          one module per tool: brew.nu, git.nu (and nu_scripts vendored ones)
themes/               colour themes: terminal.nu (ANSI, the default) and Catppuccin's four flavours
autoload/             machine-local drop-ins, gitignored, loaded last
plugins/              plugin binaries you add yourself, gitignored
docs/startup-order.md what Nushell loads when, and why that shapes this layout
docs/completion.md    how Tab works here, costs, and how to add a tool
docs/agent.md         the agent verbs: design, measured costs, knobs, limits
modules/odata/README.md  OData: commands, every query option and its pipeline stage, design, dialects, costs
```

## Configure

Start with `conf/settings.nu`. Everything else is a leaf-key assignment
(`$env.config.table.mode = "psql"`) in the `conf/` file named after the
concern, with the reasoning in a comment next to it. Every available key:

```nu
config nu --doc | nu-highlight | less -R
```

Machine-specific or private settings go in `autoload/<anything>.nu`. Those
files load after everything in `conf/`, so they win, and they are never
committed.

## Extend

| Want to | Do |
|---|---|
| Add a setting | assign it in the matching `conf/` file |
| Add an alias or small command | `conf/aliases.nu` |
| Add a module | `modules/<name>.nu` or `modules/<name>/mod.nu`, then `use <name>` in `config.nu` |
| Add completions for a tool | `agent completion <tool>` builds, wires and verifies `completions/<tool>.nu`; by hand: a spec (see `docs/completion.md`) or `nu-config fetch completion <tool>`, then a `use` line in `conf/completions.nu` |
| Change the theme | `theme` — pick from Ghostty's 463, the whole terminal is the preview; `THEME = "terminal"` (the default) makes Nushell follow it. For a theme of your own, drop a file in your `themes/` and name it in `THEME` |
| Wire up a tool that emits a Nushell init file | append it to the registry in `modules/nu-config/tools.nu`, run `nu-config tools setup` |
| Wire up a tool that does not | `conf/tools.nu`, guarded with `which` |
| Add a plugin | `plugin add <path>` (resolves through `NU_PLUGIN_DIRS`), restart |

`modules/`, `completions/` and `themes/` are on `NU_LIB_DIRS`, so bare names
resolve from anywhere: `use nu-config`, `use git-completions.nu *`,
`source catppuccin-mocha.nu`.

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
  built-in; `NU_COMPLETE_EVAL` in `conf/settings.nu` widens or disables that.
- **Tools.** `brew install <Tab>` lists every formula and cask with its
  description in 3 ms, from Homebrew's own cache (carapace: 1.6 s). `git
  checkout <Tab>` lists branches by recency, then remotes and tags; `git add`
  the changed files; `git push` the remotes. Each is a spec in
  `completions/<tool>.nu`; carapace answers whatever a spec leaves open.
- **Less noise.** Nothing after commands that take no argument (`ps <Tab>`
  used to list the directory), no duplicate entries.

`SMART_TAB = false` in `conf/settings.nu` returns to Nushell's stock menu.

| Key | Does |
|---|---|
| Tab | completion menu |
| Ctrl+R | atuin history search (Nushell's history menu when atuin is absent) |
| F1 | help menu |
| → | accept the inline history hint |

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

`agent exec` never runs anything itself: the line you accept executes in
this shell, in your history, and anything matching `AGENT_CONFIRM`
(`conf/settings.nu`) asks for a typed yes first. Alt+E turns the line you
are typing into a proposal. A session whose shell closed is checkpointed
into agmem by the next shell that starts.

## OData

OData V2 and V4 services, SAP Gateway included, as tables (`modules/odata/README.md`):

```nu
odata service add erp https://host/sap/opu/odata/sap/ZMY_SRV/ --user me -P {sap-client: "100"}
odata entities                                   # from $metadata, cached a week
odata SalesOrders 4711 Items                     # one entity, then a navigation; keys quoted from the schema
odata People | where FirstName =~ Ru | select UserName | first 5   # runs on the server as $filter/$select/$top
odata People | where Gender == Male | expand Trips | length         # $filter, $expand, /$count
odata count Orders -f "Freight gt 100"
{FirstName: Zed} | odata update People russellwhyte   # PATCH, with SAP's CSRF token when needed
```

Tab knows the services, entity sets, fields, navigations and enum values
from the cached `$metadata`, also after `| where`. Nushell cannot overload
`where`, so a `pre_execution` hook plans the pushdown and `odata get`
applies it; the Nushell stages still run on the result. `expand` is the
module's own stage.

## Tool integrations

Nushell cannot `eval` shell script, so tools emit a `.nu` file instead.
`nu-config tools setup` writes those into `$nu.data-dir/vendor/autoload`,
where Nushell loads them after `config.nu`. Installation is the switch: an
installed tool gets its file, an absent one gets nothing, a stale file is
removed. Currently in the registry: **zoxide**, **atuin**, **carapace**,
**vivid** (baked into a literal because calling it at every start costs
milliseconds for nothing). Starship is wired in `conf/prompt.nu` by hand so the
vi indicators stay in control. Homebrew's command-not-found and direnv are in
`conf/tools.nu`.

## Maintenance

```nu
nu-config doctor           # link, paths, parse check, tools, plugins, startup time
nu-config tools status     # installed vs generated
nu-config plugins add      # after `brew upgrade nushell`: plugins are protocol-versioned
nu-config startup-time     # cold starts; regression-check after adding anything
nu-config loaded-files     # what was parsed this session; find a slow import
nu-config edit             # open the repo in $EDITOR
nu-complete status         # completion caches: brew package db, specs, session memo
```

Verify a change with a shell that loads the config, not with `nu -c`:

```nu
nu -l -c 'nu-config doctor'      # loads env.nu, config.nu, login.nu
nu-check config.nu               # parse only, follows every `source`
```

`nu -c '...'` and `nu script.nu` deliberately load no user config at all.

## How Nushell finds this repo

Nushell derives every path it uses (autoload dirs, plugin registry, history)
from its config directory, so the only thing that has to point here is the
`config.nu` in that directory — three lines, written by `install.nu`:

```nu
const DISTRO = "/home/you/.local/share/nushell-distro"
source ($DISTRO | path join distro.nu)
```

The checkout stays outside the config directory, which is what keeps `git
pull` clean and keeps history, `plugin.msgpackz` and generated files out of
version control. `docs/layout.md` has the reasoning and the load order.
Alternatives that were rejected: symlinking the config directory at the
checkout (user state lands in the repo), `XDG_CONFIG_HOME` (shared with every
other app, must be set before `nu` starts), `nu --config` (only redirects two
files, must be repeated at every launch site).

Undo at any time: delete that `config.nu` and delete the checkout. Nothing
else in your config directory belongs to the distro.
