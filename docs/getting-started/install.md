# Install

Two lines, one per platform. Each makes sure `nu` exists, clones this repo to
`~/.local/share/nushell-distro`, and hands over to `install.nu`:

```sh
# macOS, Linux
curl -fsSL https://raw.githubusercontent.com/AlfoldiMate/nushell-config/main/bootstrap/install.sh | sh
```

```powershell
# Windows
irm https://raw.githubusercontent.com/AlfoldiMate/nushell-config/main/bootstrap/install.ps1 | iex
```

Read either script before running it; they are short on purpose, and each
asks before installing anything. `sh install.sh --yes` takes every default;
`--dir` clones somewhere else; `NUSHELL_DISTRO_REPO`, `_DIR`, `_REF` and
`NUSHELL_VERSION` do the same from the environment. Re-running one is a
`git pull`.

Already have Nushell (0.115 or later) and a checkout? Skip them:

```nu
git clone https://github.com/AlfoldiMate/nushell-config ~/.local/share/nushell-distro
nu ~/.local/share/nushell-distro/install.nu
```

## The seven screens

`install.nu` is written in the shell it installs. Every screen is skippable,
and nothing is written before you say yes to the last one:

| | |
|---|---|
| 1. Where | the checkout, and your config directory — Nushell's own, unless you set `XDG_CONFIG_HOME` |
| 2. Modules | multi-select, with each module's measured startup cost and its dependency state |
| 3. Terminal | is Ghostty installed, are you *running* in it; if not, the install line and "install Ghostty now?" (default yes — on macOS it is the Homebrew cask; Linux and Windows get the link). Without it the screen says what you do without — the theme stays at the ANSI tier, no `font`, no `ghostty shell`, Alt keys depend on your terminal — and offers to disable the `terminal` module (default no: it is lazy and costs nothing left on). Then whether a new window starts Nushell (default yes) |
| 4. Theme | one of a hundred palettes (NvChad's, Catppuccin), previewed by painting the live terminal, then written to Ghostty with its icon and rendered for tables, `ls`, bat and the prompt |
| 5. Font | fifteen Nerd Fonts, installed on the spot, previewed in a Ghostty window of their own |
| 6. Tools | which of zoxide / atuin / carapace / vivid / starship are present. Nothing is installed here |
| 7. The plan | every line that will be written, then one yes |

```nu
nu install.nu              # the seven screens
nu install.nu --defaults   # no questions, every shipped value
nu install.nu --dry-run    # print the plan, change nothing
nu install.nu --skip-tools --skip-plugins
```

The theme preview paints the terminal and `theme reset` hands it back, so a
cancelled installer leaves Ghostty's configuration alone. Fonts are the
exception, because a font has to exist before it can be shown; the installer
asks before downloading one.

With no terminal on stdin and stdout the installer takes every default by
itself, which is what makes `curl … | sh` work without a flag.

## What it writes

- a three-line `config.nu` into Nushell's config directory, pointing at the
  checkout (the previous one is kept as `config.nu.backup-<stamp>`)
- your directory's scaffold: a `settings.nu` with every knob commented out at
  its shipped value, a `README.md` saying what every file and directory is,
  one in each of `autoload/`, `completions/`, `themes/`, `modules/` and
  `plugins/`, and an example per kind that does nothing until renamed —
  `nu-config user init` writes the same thing again later, for whatever is
  missing
- the init files for whichever of zoxide, atuin and carapace are installed
  (`vendor/autoload/`)
- the plugins that ship next to `nu`, into the plugin registry
- with Ghostty: `command = <nu>` and the theme you chose, in a file of its own
  that Ghostty's config includes ([Files](../reference/files.md#ghostty))

Nothing you own is ever written inside the checkout, and nothing the distro
owns is written into your directory except that `config.nu`
([Layout](../concepts/layout.md)).

**The test that it went right:** accept every default and `nu-config knobs
--overridden` comes back empty. Your `settings.nu` lists all 64 knobs (counted 2026-09-19) and
every one is commented out; every value keeps tracking the distro.

Safe to re-run after every `git pull`, tool install or Nushell upgrade. Undo
at any time: [Undo the whole thing](../cookbook/uninstall.md).

Next: [Your first shell](first-shell.md).
