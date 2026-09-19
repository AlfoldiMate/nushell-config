# Theming: one theme, rendered for everything

```nu
theme                          # pick from a hundred palettes; the window is the preview
theme --ghostty                # pick from Ghostty's own 463 instead
theme use tokyonight           # by name: terminal, app icon, tables, ls, bat, prompt — now and persistently
theme use --ghostty "Gruvbox Dark"
theme list [--ghostty]         # the palettes (or Ghostty's list), with swatches
theme roles                    # every role, its colour, and which tier decided it
theme status                   # what is rendered, from which theme, and what Ghostty has
theme sync                     # re-render after a `git pull` changed a template, or a copy of yours
theme icon [--off]             # the app icon again, or none
```

There is one theme and everything is rendered from it. `theme use` hands
Ghostty a theme and an app icon, repaints the window you are in (and reloads
every open one, on macOS), and renders the shell's own colours from the same
palette, so a table separator, a `ls` directory, a `bat` keyword, a prompt
segment and the icon in the dock all come from the theme you named — in this
window now and in every shell after, because the render is a file. No `THEME`
knob: what was rendered last is the theme.

Every command and flag, with what each costs, is in the
[terminal reference](../reference/modules/terminal.md); picking a theme and
keeping it, or making a palette of your own, is
[Pick a theme and make it stick](../cookbook/theme.md).

## What there is to choose from

| | how many | what |
|---|---|---|
| **palettes** — `theme list` | 100 | files in `themes/palettes/`: NvChad's 96 base46 themes (`themes/palettes/nvchad/`, imported) and the four Catppuccin flavours (hand-made). A palette carries the shaded roles exactly, so these are tier three |
| **Ghostty's** — `theme list --ghostty` | 463 | Ghostty's own theme files: the sixteen, background, foreground. Tier two: the shades are blended |

The two are different kinds of thing, which is why they are two lists. A
Ghostty theme is sixteen colours; a palette is thirty — NvChad's `grey_fg`,
`one_bg2`, `orange`, `teal` are exactly what the shell's roles ask for, which
is why base46 was worth importing. `theme use <name>` looks for a palette
first and falls back to Ghostty's list; `--ghostty` skips the palettes.

## Roles, and the three tiers

Nobody writes a Nushell theme, a starship palette, a vivid theme or an icon per
theme. The four files in `themes/` are templates written against a **role vocabulary**:

| roles | what they are for |
|---|---|
| `fg` `fg_dim` `fg_muted` | text, secondary text, hints and the row index |
| `bg` `bg_alt` `bg_surface` `border` | background, a panel, a highlighted surface, table separators |
| `black` `red` `green` `yellow` `blue` `magenta` `cyan` `white` and `bright_*` | the sixteen — **always ANSI names, in every tier** |
| `orange` `purple` `pink` `teal` | hues the sixteen lack |
| `accent` `accent_alt` `ok` `warn` `err` `info` `hint` `on_accent` | meaning: headers, the prompt's last segment, status, text drawn on a coloured surface |

`modules/terminal/palette.nu` decides what each role is, in three tiers that
each fill in only what the one before could not say:

| tier | source | what it gives |
|---|---|---|
| **1 ansi** | `themes/palettes/ansi.nuon` | every role an ANSI name. `red` is whatever the terminal paints red; `fg_muted` has to be `dark_gray` and `orange` has to be `yellow`. What a machine without Ghostty gets, and the shell before the first `theme use`. |
| **2 derived** | the sixteen as hex — a palette's `terminal` block, or Ghostty's theme file | the shaded roles are **blended**: `fg_muted` is the foreground pulled halfway to the background, `border` the background a quarter of the way to the foreground, `orange` red mixed with yellow. Every one of Ghostty's 463 gets this. |
| **3 palette** | `themes/palettes/**/<slug>.nuon` | the shaded roles named exactly — Catppuccin's `overlay1`, NvChad's `grey_fg` and `one_bg2` — and a bat and a vivid theme that already match. |

The sixteen stay names in every tier on purpose. A hex is right only while the
terminal paints the palette it came from; a name is right in an SSH session, in
tmux, and after someone edits Ghostty's config by hand. So the shell pins only
what ANSI has no word for, and `theme roles` shows which is which.

## Two kinds of palette file

| key | means | shipped |
|---|---|---|
| `terminal: {…}` | the palette **is** a terminal theme: its own sixteen, background, foreground, cursor, selection. `theme use` writes it as a Ghostty theme file under the state dir and points `theme =` at it (Ghostty takes an absolute path) | NvChad's 96 |
| `ghostty: "Name"` | the palette **extends** a theme Ghostty ships, whose file supplies the sixteen | Catppuccin ×4 |

Both carry `colours` (any names) and `roles` (role → a colour name or a colour),
plus optional `bat` / `vivid` naming themes those tools ship and `dark`.

## The app icon

`theme use` renders `themes/icon.svg` — Jason Long's ghostty-theme-icons drawing,
with `bg`, `fg` and the four bar colours (`err`, `accent`, `ok`, `warn`) as
placeholders — to a PNG through AppKit (`modules/terminal/rasterize.js`, run
by `osascript`, so the padding round the tile is transparent), and hands Ghostty
`macos-icon = custom` + `macos-custom-icon = <it>`. No icon files are shipped:
a hundred themes is a hundred 2.5 MB `.icns`, and six colours is all an icon
is. `theme use --no-icon` leaves the icon alone, `theme icon --off` takes the
keys back out. Off macOS nothing happens.

## What is rendered, and where

`theme use` (and `theme sync`) writes `<your dir>/.state/theme/`:

| file | from | read by |
|---|---|---|
| `theme.nuon` | the resolved roles, name, tier, bat theme | `conf/theme.nu`, one `open` at startup — 0.36 ms |
| `starship.toml` | `themes/starship.toml`, `[palettes.distro]` filled in | `conf/prompt.nu` sets `STARSHIP_CONFIG` to it |
| `ls_colors` | vivid, on `themes/vivid.yml` or the palette's named vivid theme | `conf/theme.nu` → `LS_COLORS` |
| `ghostty/<slug>` | a palette's `terminal` block as a Ghostty theme file | Ghostty, through `theme =` in the distro's included file |
| `icons/<slug>.png` | `icon.svg` with the roles filled in | Ghostty, through `macos-custom-icon` |

Rendered rather than resolved at every start because a resolve may spawn
Ghostty to find a theme file and a render runs vivid and the rasterizer: 40 ms
to resolve, 320 ms for a whole `theme use`, against 0.4 ms to read the result.
`theme use` is `def --env`, so the session it runs in gets the same three
things a startup gets, from the same files.

| template in `themes/` | rendered for |
|---|---|
| `nushell.nu` | `$env.config.color_config` and `explore`. Reads `$c`, the roles; sourced by `conf/theme.nu` at startup and by `theme use` in the running session |
| `starship.toml` | the prompt. Its own `[palettes.distro]` block is tier one, so it works unrendered |
| `vivid.yml` | `LS_COLORS`. vivid's `ansi` rules with the `colors:` block rendered |
| `icon.svg` | the app icon |

## Changing a template, or adding a palette

Your `themes/` directory comes first on `NU_LIB_DIRS` and is checked first by
the renderer, so a copy of any of the four templates there is the one used —
`theme sync` after editing it. Stick to roles and every theme keeps fitting it.

A palette of your own is `<your dir>/themes/palettes/<slug>.nuon`, where the
slug is the name lowercased with runs of anything but letters and digits turned
into `-` (`theme slug "TokyoNight Storm"` → `tokyonight-storm`); yours shadows
a shipped one of the same slug. Copy an NvChad one for a theme of your own
(with `terminal`), a Catppuccin one to extend a theme Ghostty ships (with
`ghostty`).

The NvChad import is `themes/palettes/nvchad/import.nu`: it reads base46's `base_30`
(the thirty UI colours, which map onto the roles almost one to one) and writes
one file per theme. Run it by hand when base46 moves; nothing fetches at
runtime. `catppuccin-latte` is skipped because the hand-made one, which
extends Ghostty's own Catppuccin Latte with all 26 colours, has that slug.

Trying a theme without keeping it is `theme preview <name>` and `theme reset`
— the terminal only; the shell's colours change with `theme use`.

## How the terminal side works

### The terminal is the preview

A Ghostty theme file is exactly `palette = N=#hex` for 0-15 plus `background`,
`foreground`, `cursor-color` and the two selection colours — and every one of
those can be set at runtime over OSC:

```
OSC 4;N;#hex  palette entry N        OSC 104  reset every palette entry
OSC 10;#hex   foreground             OSC 110  reset foreground
OSC 11;#hex   background             OSC 111  reset background
OSC 12;#hex   cursor                 OSC 112  reset cursor
OSC 17;#hex   selection background   OSC 117  reset selection background
OSC 19;#hex   selection foreground   OSC 119  reset selection foreground
```

So applying a theme to the running session is a dozen escape sequences and no
reload, and the preview is the whole terminal — prompt, tables, scrollback — not
a pane with swatches in it. "Reset" means back to whatever Ghostty's own config
says, which is why `theme reset` needs no memory of what was there before.

### Ghostty can be reloaded from the CLI after all — through AppleScript

There is no `ghostty +reload`; `reload_config` is a keybind action. But the
app's AppleScript dictionary (`sdef /Applications/Ghostty.app`) has `perform
action`, which takes any action string, so

```
osascript -e 'tell application "Ghostty" to perform action "reload_config" on (first terminal of first tab of first window)'
```

reloads the configuration in every open window and returns `true`. `ghostty
reload` wraps it, and `theme use`, `theme icon` and `font use` call it, which
is how a written theme, icon or font reaches the windows already open rather
than only new ones. macOS only (`macos-applescript`, default on); the OSC
repaint stays for the preview and for everything else. Verified with Ghostty
1.3.1 on 2026-09-19.

### It does not repaint as you arrow through the list

`input list` cannot call back on cursor movement, and the alternative — driving
`input listen` and drawing a scrolling fuzzy list by hand — is a TUI written in
Nushell to save one keystroke. So nothing is painted while you are choosing,
which also means a cancelled list leaves the terminal exactly as it was. The one
moment a palette is applied but not yet kept is a single yes/no you answer while
looking at it, and `theme reset` is the way out of one left behind.

The list itself is not colourless, though: each row carries the theme's own
sixteen colours as truecolor blocks, so all 463 are previewed at once.

### A font is previewed in a window of its own

You cannot preview a font you have not installed: the terminal renders with the
fonts it has, and a name in a list tells you nothing. Nor is there an escape
sequence for "change font" the way OSC 4 is "change colour", so previewing one
you *have* installed in the window you are sitting in would mean writing it to
the config and reloading — a preview that is already a change. That asymmetry
is why the theme picker repaints in place and the font picker cannot.

What Ghostty does have is `--font-family` on its own command line, so `font
preview` opens a new window in the candidate font running a specimen: Ghostty's
own rasterizer and shaper, the real ligatures, the real Nerd Font glyphs, at the
size you will use. It costs one window you close again, and it touches no
configuration.

The design started from the issue's first choice — pre-rendered PNG samples
pushed over the Kitty graphics protocol, which Ghostty supports — and dropped
it. Nothing on a stock machine can rasterize a font file: no ImageMagick, no
PIL, and macOS `qlmanage -t` returns a generic "Aa" icon rather than a specimen
(checked). So the images would have to be built elsewhere and shipped or
fetched — a few hundred kB that goes stale against each Nerd Fonts release, to
show something less true than a real window already shows.

### `+show-face`, not `+list-fonts`, not a directory listing

Whether a font is installed is a question only the terminal can answer, and only
one of its two commands answers it. After installing Inconsolata Nerd Font into
`~/Library/Fonts`, `ghostty +list-fonts` still reported only the five system
monospace families and never mentioned it — while `ghostty +show-face
--font-family="Inconsolata Nerd Font"` answered *found in face Inconsolata Nerd
Font*. Deleting the two files flipped that back to *JetBrains Mono*. (macOS 27.2,
Ghostty 1.3.1.)

The trick that makes `+show-face` usable is its failure mode: a family Ghostty
cannot find does not error, it silently falls back to the configured font. So
the test is whether the face it names is the family that was asked for. One
spawn per font, 26 ms each, run through `par-each`: 103 ms for all fifteen.

One more thing has to be true for the question to reach Ghostty at all:
`font-family` is a *repeatable* key, a list of families of which the first
found wins, and Ghostty builds the list in a fixed order — its default config
files, then the command line, then the files those include with
`config-file`. So `--font-family=X` lands behind the user's own entry and in
front of the distro's, and with a family configured on either side the answer
was that family for every X: every font read as not installed, and `font use`
tried to install what was already there. `font face` therefore asks with
`--config-default-files=false`, which loads no configuration at all, so the
answer is about X alone: the family itself when installed, Ghostty's built-in
"JetBrains Mono" when not. (Verified 2026-09-19, Ghostty 1.3.1.)

The same order is why the distro's included file has to *reset* a repeatable
key before setting it. Applied last, a plain `font-family = X` in it would sit
behind the user's own `font-family` and lose; `ghostty set` writes an empty
`font-family =` line first, which clears the list, then the value. Scalar keys
(`theme`, `command`) need nothing of the kind: last assignment wins.
`ghostty live font-family` reports the first entry of the resolved list, which
is what `font list` marks as current.

### The registry never trusts its own family names

Nerd Fonts renames several fonts to avoid trademark collisions — CascadiaCode
becomes CaskaydiaCove, SourceCodePro becomes SauceCodePro, Monaspace becomes
Monaspice, Terminus becomes Terminess — and each archive holds every variant and
sub-family, so "Meslo" is six families and "Monaspace" is five. The registry
therefore carries the release asset, the exact file stem to take out of it
(`MesloLGSNerdFont`, `MonaspiceNeNerdFont`), the family Ghostty will report, and
the Homebrew cask, all four separately. Every cask name and every file stem in
it was read out of `brew info --cask --json=v2`, not recalled.

Only four faces are installed out of an archive — Regular, Bold, Italic,
BoldItalic of the one chosen stem — which is why a font is a few MB installed out
of an archive that runs from 8 MB (Inconsolata) to 620 MB (Noto). Fonts that
ship fewer faces install fewer: Inconsolata has no italic, and two files is the
right answer there, not an error.

### Installed, and running in it, are two questions

`install.nu` asks both, and they have different answers. *Installed* decides
whether a theme can be written at all. *Running in it* decides whether the live
OSC preview will be visible — painting the terminal you are looking at is only a
preview if it is the terminal being configured; from Terminal.app or an SSH
session it is a lie. `TERM_PROGRAM` answers the second in one environment-variable
read, no processes.

Detection is a registry rather than three `if`s, the same shape as the tool
registry in `modules/nu-config/tools.nu` where "installed" is likewise the
switch, so adding WezTerm or Kitty later is a record and not a refactor.
Ghostty is the only entry, deliberately.

### Ghostty is not on PATH

On macOS the binary lives inside `Ghostty.app` and reaches PATH only through
Ghostty's own shell integration, which prepends `GHOSTTY_BIN_DIR` to every shell
it starts. So `which ghostty` finds it in a Ghostty window and misses it
everywhere else — from Terminal.app, over SSH, in CI, and in the installer that
is trying to decide whether to offer to install it. Every call here goes through
`ghostty-bin`, which falls back to `$env.GHOSTTY_BIN_DIR` and the two app-bundle
locations; `meta.nuon` carries the same paths in `requires.paths`, which is what
makes `nu-config doctor` agree.

### One included file, never their config

`ghostty set` writes `<ghostty dir>/nushell-distro.ghostty` and appends exactly
one line — `config-file = ?nushell-distro.ghostty` — to the user's own config,
once, after copying it to `config.backup-<timestamp>`. `ghostty reset` removes
both and leaves their config byte-identical.

Four properties of Ghostty 1.3.1, each checked with `XDG_CONFIG_HOME` pointed at
a scratch directory:

- An included file is applied **after** the file that includes it, no matter
  where the `config-file` line sits. So appending is enough: their own `theme =`
  line never has to be found, let alone edited.
- `?` makes a missing include a silent no-op, so deleting our file is already an
  uninstall.
- A relative include resolves next to the file holding the directive.
- `config.ghostty` beats the legacy `config` in the same directory, and only one
  of the two is loaded.

`set` then asks Ghostty to check its own work (`+validate-config`) and rolls our
file back if it complains, so an unknown key or a theme Ghostty cannot find never
survives the call. `status` reports the theme `ghostty +show-config` actually
resolves, which is the only real proof the include landed in the file Ghostty
reads — `+show-config` echoes an invalid theme name happily, so that check proves
plumbing, not validity, and both are needed.

A user with no Ghostty config at all gets `~/.config/ghostty/config.ghostty`
created, even on macOS where `ghostty +edit-config` would have picked Application
Support: a file under `~/.config` is the one a dotfiles repo can keep, and
Ghostty reads it as long as Application Support holds nothing.

### Nushell is the shell because Ghostty is told so, not `chsh`

Ghostty starts `SHELL`, and failing that the passwd shell — zsh on a stock Mac —
so a freshly installed distro would open a terminal that runs something else.
`ghostty shell` (and `install.nu`, screen 3, the one question there whose
default is yes) writes `command = <nu>` into our included file, where it wins
over a `command =` in the user's own config like every other key we own, and
`ghostty shell --reset` takes it out again.

Not `chsh`: macOS refuses a shell that is not in `/etc/shells`, a Homebrew `nu`
moves at every upgrade, and the scripts and tools that read `$SHELL` expecting
POSIX would break. Telling the terminal leaves the login shell alone.

The value is the `nu` found on PATH (`ghostty nu-path`), not `$nu.current-exe`:
PATH holds the path the user installed — `/opt/homebrew/bin/nu`,
`~/.cargo/bin/nu` — while the running binary can be the versioned Cellar file
behind that symlink, which stops existing at the next `brew upgrade`. It is a
bare absolute path with no `-l`: verified on macOS with Ghostty 1.3.1 that a
`command` with no arguments is still launched through `login -flp <user>
/bin/sh -c "exec -l <nu>"`, and Nushell reads the dash in `argv[0]` the way
every shell does, so the window gets a login nu (`$nu.is-login == true`) with
`login`'s environment. The check was a scratch `XDG_CONFIG_HOME` whose
`config.nu` wrote `$nu.is-login` to a file and exited, opened with `ghostty
--command=<nu>`.

### Why it is lazy

Loading these files costs 18 ms, for commands a shell uses once in a while,
so `theme`, `ghostty` and `font` are trigger words
(`MODULES_TRIGGERS` in `defaults.nu`). Typing `ghostty +list-themes` loads the
module too, which is harmless.
