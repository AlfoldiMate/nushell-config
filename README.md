# Nushell distro

A [Nushell](https://www.nushell.sh) configuration you **install** rather than
copy. The distro is a git checkout you never edit; your settings live in your
own config directory, in a file the distro does not ship, and a `const` there
shadows the one here. So `git pull` never conflicts, a knob you never mention
keeps tracking the distro, and nothing you own is ever written inside the
checkout. Nushell **0.115**; macOS, Linux and Windows, by CI on every push.

## Install

```sh
# macOS, Linux
curl -fsSL https://raw.githubusercontent.com/AlfoldiMate/nushell-config/main/bootstrap/install.sh | sh
```

```powershell
# Windows
irm https://raw.githubusercontent.com/AlfoldiMate/nushell-config/main/bootstrap/install.ps1 | iex
```

Each has two jobs — make sure `nu` exists, clone this repo — and hands over to
`install.nu`, written in the shell it installs. Read either first; they are
short on purpose. Already have Nushell and a checkout?

```nu
git clone https://github.com/AlfoldiMate/nushell-config ~/.local/share/nushell-distro
nu ~/.local/share/nushell-distro/install.nu          # seven screens, every one skippable
nu ~/.local/share/nushell-distro/install.nu --defaults   # no questions
nu ~/.local/share/nushell-distro/install.nu --dry-run    # print the plan, change nothing
```

Nothing is written before you say yes to the last screen. Undo at any time:
delete the three-line `config.nu` it wrote and delete the checkout.

## The first ten minutes

```nu
nu-config doctor             # both directories, every path, parse, tools, theme, plugins, modules, startup time
theme                        # a hundred palettes; the window you are in is the preview
font                         # fifteen Nerd Fonts, installed on the spot, previewed in a window of their own
nu-config edit user          # your directory: a README in every directory, settings.nu with every knob commented out
nu-config knobs              # every value the distro ships, and whether you changed it
nu-config upgrade            # git pull; a shell tells you when there is something to pull
```

Tab opens a pipeline-aware menu: `ls | where <Tab>` offers the columns with
a sample value, `brew install <Tab>` every formula in 3 ms, `git checkout
<Tab>` branches by recency. Ctrl+R is history, F1 help, Alt+E hands the line
you are typing to Claude.

## What is in the box

Startup is **84 ms** on an M-series Mac against 47 ms for Nushell with no
config at all (minimum of nine cold starts, 2026-09-19). The three biggest
modules are not parsed at startup; each loads on the first line that mentions
it.

| | | cost |
|---|---|---|
| `nu-config` | doctor, knobs, modules, tools, plugins, upgrade, startup time | 14 ms |
| `nu-complete` | the engine behind Tab: pipeline columns, specs per tool, carapace as the fallback | 2 ms |
| `terminal` | `theme`, `font`, `ghostty`: one palette rendered for the terminal, tables, `ls`, bat, the prompt and the app icon | 18 ms, lazy |
| `agent` | Claude Code at the prompt: `ask`, `exec` (proposes; you run it), `skill`, `command`, `completion` | 18 ms, lazy |
| `odata` | OData V2/V4 services as tables, `where`/`select`/`first` pushed to the server | 97 ms, lazy |
| `completions/` | brew (16k formulae with descriptions, 3 ms), git (refs by recency, changed files), cargo (workspace members, crates, features) | 10 ms for all three |
| `themes/` | NvChad's 96 palettes and Catppuccin's four, plus Ghostty's own 463 | rendered once |

## Documentation

[`docs/`](docs/README.md) is one tree:

| | |
|---|---|
| [Getting started](docs/README.md#getting-started) | install, the first shell, the first setting, the first theme, updating |
| [Concepts](docs/README.md#concepts) | how it works and why — the two directories, startup, modules, completion, theming, the agent, OData, plugins — with every measured number |
| [Reference](docs/README.md#reference) | every command, every knob, every file; one page per module |
| [Cookbook](docs/README.md#cookbook) | one task per page: add a completion, override one, write a drop-in, make a palette, pin a font, debug Tab, test a change, uninstall |

## Platforms

CI runs the real installer and then loads the config for real on macOS,
Linux and Windows, every push. That is the floor. The ceiling: Ghostty and
fonts have been run by hand on macOS only; there is no Ghostty for Windows,
and no `ghostty reload` off macOS. [Platforms](docs/reference/platforms.md)
is the exact table.
