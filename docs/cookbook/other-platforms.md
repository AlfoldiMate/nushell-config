# Run on Linux and Windows

The distro installs, parses and loads on macOS, Linux and Windows — CI runs
the real installer and then `nu-check`, `module lint` and `doctor` on all
three, every push. That is the floor. This page is the ceiling: what is
different, what is not run there, and what to do about it.
[Platforms](../reference/platforms.md) is the table this is written from.

## Install

```sh
# Linux
curl -fsSL https://raw.githubusercontent.com/AlfoldiMate/nushell-config/main/bootstrap/install.sh | sh
```

```powershell
# Windows
irm https://raw.githubusercontent.com/AlfoldiMate/nushell-config/main/bootstrap/install.ps1 | iex
```

Each makes sure `nu` exists — from a release tarball into `~/.local/bin` when
it does not, `NUSHELL_BIN_DIR` to choose — clones to
`~/.local/share/nushell-distro` (`NUSHELL_DISTRO_DIR`), and runs `install.nu`.
`install.sh` is exercised by hand on macOS, including the tarball path with
`nu` off PATH; on Linux only `sh -n` has run it. `install.ps1` has been parsed,
not run. Both are short enough to read first, and both fall back to asking.

Where things land:

| | Linux | Windows |
|---|---|---|
| your config directory | `~/.config/nushell` | `%APPDATA%\nushell` |
| `$nu.data-dir` (`.state/`, `vendor/autoload/`) | `~/.local/share/nushell` | `%APPDATA%\nushell` |
| caches | `~/.cache/nushell` | `%LOCALAPPDATA%\nushell` |
| fonts | `~/.local/share/fonts` | `%LOCALAPPDATA%\Microsoft\Windows\Fonts` |

`nu-config doctor` prints every one of them.

## What is the same

The shell. `defaults.nu`, `conf/`, the modules, the completion engine, the
plugin registry, the update check and the layering are platform-neutral
Nushell, and CI proves they load. `path add` in `conf/env.nu` picks a PATH
per OS (`/home/linuxbrew/.linuxbrew/bin` on Linux, nothing Homebrew-shaped
on Windows) and never fails on a directory that is not there. `duh` uses
Nushell's own `du`, which takes `--max-depth` everywhere.

## What is different

**Ghostty.** The theme picker, `theme use`, `ghostty shell` and the font
installer are Ghostty's. On Linux Ghostty exists and the config paths are
derived for it, but none of it has been run there; in particular whether a
bare `command = <nu>` starts a *login* shell on Linux has not been checked,
only that it starts one. There is no `ghostty reload` off macOS (it is
AppleScript), so a written theme, icon or font reaches new windows only,
while the running window is repainted over OSC. On Windows Ghostty has no
build: `terminal install` prints the download page and runs nothing,
`terminal list` says so, and the shell's colours stay at the ANSI tier —
whatever your terminal paints — until a theme can be written.

**Fonts.** `font install` on Linux downloads the Nerd Fonts `.tar.xz`, takes
four faces into `~/.local/share/fonts` and runs `fc-cache -f` when fontconfig
is there; on Windows it takes them from the `.zip` into your user font
directory and adds one `HKCU\…\Fonts` registry value per file. The Linux
branch is unexercised and the Windows branch is written from the documented
behaviour only. [Pin a font](font.md) says what to do by hand.

**`port`.** `lsof` on macOS and Linux (not run on Linux), the `netstat -ano`
branch on Windows (not run). Without `lsof` it errors with the command to use
instead, rather than returning an empty table that would read as "nothing is
listening".

**`agent`.** The startup sweep that checkpoints closed sessions needs `sh`
and `nohup`; on Windows it stays an in-shell job and dies with a short-lived
shell. Everything else in the module is `claude -p` and works wherever Claude
Code does.

**Tools.** `tree`, `lt` and `rgt` want `eza` and `ripgrep`; they are `alias`
and `def`, so a missing tool costs a "command not found" the moment you use
one and nothing at startup. zoxide, atuin and carapace are wired only when
found, on every platform.

**Plugins.** `nu-config plugins add` registers the `nu_plugin_*` binaries next
to `nu`. A package-manager `nu` on Linux ships them; a release tarball does
not, and the CI runner's `nu` has none, which is why CI passes
`--skip-plugins`.

The pattern throughout: what a platform *cannot* do is stated rather than
papered over. When you run one of the unexercised branches and it works — or
does not — that is a bug report worth filing, and the table in
[Platforms](../reference/platforms.md) is what changes.
