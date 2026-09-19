# This machine's Nushell setup

macOS (arm64), Nushell **0.115.1** via Homebrew, login shell `/bin/zsh`,
terminal Ghostty, prompt Starship. One theme, the terminal's: `theme use`
writes Ghostty's config and renders Nushell's colours, LS_COLORS, the bat
theme and starship's config from the same palette (`docs/concepts/theming.md`).

## Two directories, and which one to edit

This is a **distro** with a user layer, not a config you edit in place:

```
THE DISTRO (a git checkout)          YOUR config directory
~/.config/nushell                    ~/Library/Application Support/nushell
  distro.nu    entrypoint      ◀──── config.nu     3 lines, sources the distro
  defaults.nu  every knob            settings.nu   the overrides
  conf/        behaviour             autoload/*.nu drop-ins, loaded last
  modules/ completions/ themes/      completions/ themes/ modules/ plugins/
  docs/ templates/ bootstrap/        history.sqlite3, plugin.msgpackz, vendor/, .state/
```

Nushell only knows the right-hand side: it loads `config.nu` from its own config
directory and derives history, the plugin registry, the autoload dirs and
`$nu.data-dir` from that same place.

- **Changing the distro** (this repo) — edit it here. A parse error breaks every
  new terminal, so `nu-check distro.nu` before reporting anything done.
- **Changing this machine only** — a knob goes in the user's `settings.nu`
  (`nu-config edit user`), behaviour goes in a file in the user's `autoload/`.
- **Never write user state into the checkout.** History, the plugin registry,
  generated tool files and module state all live in the user directory; the
  `.gitignore` is four lines because of it.

`docs/README.md` is the map of the documentation; `docs/concepts/layout.md`
the layering and load order, `docs/reference/files.md` the formats,
`docs/reference/platforms.md` the per-platform coverage, `docs/concepts/startup.md`
what Nushell loads when.

## The rules that shape the files

- Settings are leaf-key assignments (`$env.config.a.b = ...`), never whole
  records, never `$env.config = {...}`.
- **Values in `defaults.nu`, behaviour in `conf/`.** A `conf/` file must never
  assign a value `defaults.nu` owns: it runs after the user's `settings.nu` and
  would silently overwrite it.
- Paths are parse-time constants derived from `path self`; never a hard-coded
  home directory. `use`/`source` need parse-time paths, which is why an optional
  include is a const `if` around `source null`.
- Optional tools are guarded with `which`; `alias` and `extern` cannot sit
  inside an `if` — they are parse-time.
- `.nu` for anything the parser must see, NUON for anything tooling reads at
  runtime. The two JSON caches that remain are measured and commented.
- Modules follow `docs/concepts/modules.md`: `mod.nu` + `load.nu` + `meta.nuon`,
  code only — the page is `docs/reference/modules/<name>.md` — wiring in
  `activate`, knobs in `meta.nuon`. `nu-config module lint` enforces it.

## Commands this config adds

| | |
|---|---|
| `nu-config` | `doctor`, `knobs`, `module list\|lint\|enable\|disable`, `tools setup\|status`, `plugins list\|add`, `startup-time`, `loaded-files`, `fetch completion`, `edit`, `edit user` |
| `nu-complete` | the Tab engine: `status`, `cache clear`, `run`, `smart` |
| `theme` / `ghostty` / `font` / `terminal` | the terminal itself (lazy module) |
| `agent` | Claude Code in the shell: `ask`, `exec`, `skill`, `command`, `completion` (lazy) |
| `odata` | OData V2/V4 services as tables (lazy) |

`nu-config doctor` is the first thing to run when something looks wrong: both
roots, the layout state (`split` is the target), every derived path, a parse
check, tools, plugins, modules and startup time.

## Current configuration

- **Edit mode** vi; cursor `line` in insert, `block` in normal
- **Editor** first of `zed --wait`, `nvim`, `vim`, `vi` that exists
- **Tables** `markdown`, index always, footer at 25 rows
- **Banner** off · **History** sqlite, 1M entries
- **Tab** the smart menu (`SMART_TAB`), pipeline-aware, `NU_COMPLETE_EVAL = "safe"`
- **Theme** whatever `theme use` rendered last into `.state/theme/` (no knob);
  tables, `ls`, bat and the starship prompt all come from it. `theme status`,
  `theme roles`
- **Modules** `nu-config` and `nu-complete` eager; `terminal`, `agent`, `odata`
  lazy — loaded by a `pre_execution` hook on the first line that mentions them,
  which means they do **not** load for `nu -c` or a script
- **`open`** left alone: it is Nushell's parser. Use `start <path>` to launch a
  file in its app, and `%open` inside completion modules in case a user aliased it

## Tools

Generated into the user's `vendor/autoload/` by `nu-config tools setup`, from
the registry in `modules/nu-config/tools.nu`: **zoxide**, **atuin**,
**carapace**. Installed → generated, absent → pruned, so presence on PATH is
the switch. vivid and starship are the theme's: `theme use` renders LS_COLORS
and a starship.toml into `.state/theme/`, and starship is wired by hand in
`conf/prompt.nu`. Homebrew's `command_not_found` and direnv are in
`conf/tools.nu`, each guarded with `which`.

`nu -l -c` does **not** load the vendor autoload directory, so carapace and
zoxide are absent there — source the generated file if a test needs one.

## Verifying a change

```nu
nu-check distro.nu                 # parse, follows every `source`
nu -l -c 'nu-config doctor'        # loads the config for real
nu -l -c 'nu-config module lint'   # the only check that reaches a lazy module
nu -n -c '<snippet>'               # isolated snippet, no config
nu -l -c 'nu-config startup-time'  # ~84 ms; regression-check after adding anything
```

`nu -c '...'` and `nu script.nu` load no user config at all and prove nothing
about this config. `nu -n` also has no `NU_LIB_DIRS`, so `nu-check` on a file
that imports a module reports `false` there for reasons unrelated to the file.

## After `brew upgrade nushell`

```nu
nu-config plugins add    # the registry is protocol-versioned against the binary
nu-config doctor
```

Nushell makes breaking changes at minor versions: when the pin moves, the config
is what has to be re-checked. `docs/concepts/plugins.md` explains why there is no plugin
manager to do this for you.
