# Documentation

One tree, four kinds of page. Start at the top if the distro is new to you;
jump to a section if it is not.

| | for |
|---|---|
| [Getting started](#getting-started) | the first hour: install it, meet the shell, change one thing, pick a theme, keep it updated |
| [Concepts](#concepts) | how it works and why it is built that way — the design records, with every measured number |
| [Reference](#reference) | what a command takes, what a knob does, what a file holds |
| [Cookbook](#cookbook) | one task per page, in the order you do it, ending with how to check it worked |

Every number in these pages was measured (`timeit`, `nu-config
startup-time`, `hyperfine`) on the day stated next to it, on an M-series Mac
unless it says otherwise; nothing is estimated. Nushell **0.115**.
`assets/` holds the one image the top-level README shows: `demo.gif`, a
hundred seconds of the shipped defaults in a real Ghostty window, recorded
2026-09-19.

## Getting started

1. [Install](getting-started/install.md) — the two bootstrap lines, the seven screens, what is written where
2. [Your first shell](getting-started/first-shell.md) — `nu-config doctor`, the keys, the two directories
3. [Your first setting](getting-started/first-setting.md) — `settings.nu`, knobs, values against behaviour
4. [Your first theme](getting-started/first-theme.md) — `theme`, `font`, `ghostty shell`
5. [Updating](getting-started/updating.md) — `nu-config upgrade`, the notice, after a Nushell upgrade

## Concepts

| | |
|---|---|
| [Layout](concepts/layout.md) | the distro and your directory, the layering by `const` shadowing, values against behaviour, load order, search paths — **the map** |
| [Startup](concepts/startup.md) | what Nushell loads when, where the distro plugs in, the lazy modules and what they save |
| [Modules](concepts/modules.md) | the module contract: `mod.nu`, `load.nu`, `meta.nuon`, `activate`, dependencies, cost |
| [Completion](concepts/completion.md) | the three layers behind Tab, the smart menu, what may run, the unified completer inputs |
| [Theming](concepts/theming.md) | one palette in roles, resolved in three tiers, rendered for every tool; the terminal as the preview; Ghostty's facts |
| [Agent](concepts/agent.md) | Claude Code inside the shell: one `claude -p` per turn, exec proposes, the checkpoint sweep |
| [OData](concepts/odata.md) | pushing `where`/`select`/`first` to the server through a `pre_execution` hook |
| [Plugins](concepts/plugins.md) | why there is no plugin manager, and what `nu-config plugins add` is instead |

## Reference

| | |
|---|---|
| [Knobs](reference/knobs.md) | every value `defaults.nu` ships, and where the module knobs are |
| [Files and formats](reference/files.md) | every file the distro reads or writes, `.nu` against NUON against JSON |
| [meta.nuon](reference/meta-nuon.md) | every field a module declares, and what `module lint` checks |
| [Completion specs](reference/completion-spec.md) | the spec format, sources, caching, the parse budget, the completer's input |
| [Platforms](reference/platforms.md) | what is proven on macOS, Linux and Windows, and what is not |
| [Tests](reference/tests.md) | `nu tests/run.nu`: the runner, writing a test, `lib.nu`, the isolation, the cost |
| **Modules** | |
| [nu-config](reference/modules/nu-config.md) | `doctor`, `knobs`, `module`, `user`, `tools`, `plugins`, `upgrade`, `startup-time`, `edit` |
| [nu-complete](reference/modules/nu-complete.md) | the engine behind Tab: `run`, `spans`, `smart`, `quote`, `cache`, `status` |
| [terminal](reference/modules/terminal.md) | `theme`, `ghostty`, `font`, `terminal` — every command, with costs |
| [agent](reference/modules/agent.md) | `ask`, `exec`, `skill`, `command`, `completion`; the exec menu; the knobs |
| [odata](reference/modules/odata.md) | every command and flag, the query-option table, completion, knobs, testing |

## Cookbook

| | |
|---|---|
| [Add Tab completion for a tool](cookbook/add-completion.md) | `agent completion <tool>`, or a spec by hand — `starship` worked through |
| [Override a shipped completion](cookbook/override-completion.md) | copy it into your `completions/`; everything shadows by name |
| [Write an autoload drop-in](cookbook/autoload.md) | an alias, a hook, a keybinding, a secret — and when it is `settings.nu` instead |
| [Your directory](cookbook/user-directory.md) | what is there and whose, switching an example on, getting a README back, the knobs an upgrade added |
| [Pick a theme and make it stick](cookbook/theme.md) | the picker, a palette of your own from six colours, keeping it after a `git pull` |
| [Pin a font](cookbook/font.md) | `font use`, and installing one by hand on Linux and Windows |
| [Enable a module, make it lazy, see what it costs](cookbook/modules.md) | `module enable`, `MODULES_LAZY`, `startup-time`, `loaded-files` |
| [Debug Tab](cookbook/debug-tab.md) | `commandline complete --detailed`, `nu-complete smart`, the error the `try` hides |
| [Test a change to the distro before it is live](cookbook/test-a-change.md) | `nu-check`, `doctor`, `module lint`, a scratch `config.nu` for a second checkout |
| [Run on Linux and Windows](cookbook/other-platforms.md) | what is the same, what is different, what has not been run |
| [Undo the whole thing](cookbook/uninstall.md) | `ghostty reset`, `rm config.nu`, the checkout; what is yours and stays |

## Writing a page

A concept page explains a mechanism and the decisions someone would
otherwise re-litigate, with the numbers that decided them. A reference page
follows `templates/module-doc.md`: what it is, every command, configuration,
dependencies, measured costs, files, limits. A cookbook page is one task,
run once as written before it is committed, ending with what was seen. A
measured number moves with its subject and never loses its date.
