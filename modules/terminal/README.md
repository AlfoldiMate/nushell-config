# modules/terminal

The terminal you are running in: its theme, and its configuration.

```nu
terminal list                  # which terminals this distro knows, and what is true here
theme                          # pick from a hundred palettes, the terminal is the preview
theme --ghostty                # or from Ghostty's own 463
font                           # pick a Nerd Font, install it, see it in a real window
theme use tokyonight           # or name one; Tab completes them
theme roles                    # what the shell made of it: every role, its colour, which tier
ghostty shell                  # a new Ghostty window starts Nushell
ghostty status                 # what this distro has written into Ghostty's config
```

The two belong in one module because of how this distro does colour: there is
one theme and it is the terminal's. `theme use` writes Ghostty's configuration,
repaints the window you are sitting in, and renders the shell's own colours —
tables, `ls`, bat, the prompt — from the same palette, so they follow in this
window now and in every shell after. `theme.nu` reads and paints, `palette.nu`
resolves and renders, `ghostty.nu` writes, `detect.nu` answers the two
questions `install.nu` asks before any of them runs.

## Commands

| Command | Does |
|---|---|
| `theme [--ghostty]` | the picker: the hundred palettes (or Ghostty's 463) with their own colours beside them, then paint, then keep or not |
| `theme list [--ghostty] [--swatches]` | the palettes, or Ghostty's own themes with their files; `--swatches` adds the sixteen colours |
| `theme preview <name> [--ghostty]` | paint this session, change nothing on disk |
| `theme reset` | hand the palette back to Ghostty's config — the way out of a preview |
| `theme use <name> [--ghostty] [--no-icon]` | write Ghostty's theme and icon, paint, reload every window, render the shell's colours |
| `theme icon [--off]` | render the app icon for the current theme again, or remove the icon keys |
| `theme roles [name]` | every role, its resolved colour and the tier that decided it, with a swatch |
| `theme palettes` | every palette file: name, dark, kind, the Ghostty theme it extends |
| `theme palette <name>` | one Ghostty theme file as data: `palette` 0-15 and the named colours |
| `ghostty themes [--swatches]` | every theme Ghostty can find, with its file |
| `ghostty reload` | reload Ghostty's config in every open window (macOS, AppleScript); true when it did |
| `theme status` | what is rendered, from which theme, at which tier, and whether Ghostty agrees |
| `theme sync [name]` | re-resolve and re-render — after a `git pull` changed a template, or `--none` to forget the theme |
| `theme resolve [name]` | the resolved theme as data, nothing written |
| `theme names [--ghostty]` | the names alone — palettes, or Ghostty's. Tab on a `<name>` offers the palettes, or Ghostty's once `--ghostty` is on the line |
| `ghostty status` | the config Ghostty reads, what we own in it, and the theme and shell Ghostty resolves |
| `ghostty shell [--reset]` | make Nushell what a new window starts; `--reset` hands that back to `SHELL` / passwd |
| `ghostty nu-path` | the nu that `shell` writes: the one on PATH, not the running binary |
| `ghostty set <record>` | write keys into our own included file (a null value removes one) |
| `ghostty reset` | remove our file and the one include line; their config is left as it was |
| `terminal list` | every terminal in the registry: installed, running, configured, where its binary is |
| `terminal current` | the row for the terminal this session runs in, or null |
| `terminal install-plan [name]` | what this platform would have to run, and whether it can |
| `terminal install [name]` | run it, after asking |
| `font` | the picker: fifteen Nerd Fonts, install what you choose, keep it |
| `font list` | the registry, and what is installed here |
| `font install <name>` | Homebrew's cask on macOS, the release archive otherwise |
| `font preview <name>` | a new Ghostty window in that font, showing a specimen |
| `font specimen` | the sample text in the font this terminal is using now |
| `font use <name>` | install if needed, then keep it |
| `font face <family>` | the face Ghostty would actually use for a family |

Theme names are Tab-completable everywhere they are taken.

## Configuration

No knobs. The one piece of state is what `theme use` renders into `<your
dir>/.state/theme/` — `theme.nuon`, `starship.toml`, `ls_colors`, a Ghostty
theme file and an icon per palette used — which `conf/theme.nu`, `conf/prompt.nu`
and Ghostty read; `theme status` shows it.
Ghostty's own configuration is read at the moment you ask, never cached. The
templates being rendered live in `themes/` (`themes/README.md`), and a copy in
your own `themes/` is the one used.

## Dependencies

`ghostty`, and hard: the configuration being written is Ghostty's, and so are
the 463 themes behind `--ghostty`. `nu-config module check terminal`. Without
it the palettes still list and resolve (at tier three, with no window to
paint), `theme list --ghostty` errors and `theme reset` still works — OSC is the terminal's, not Ghostty's, so
the escape sequences are understood by any terminal that implements them; only
everything that has to *know* what a theme is needs Ghostty.

## Design

### One palette, three tiers, every tool rendered from it

The long form is the header of `palette.nu`; this is the short one. A theme is
a record of **roles** — `fg_muted`, `border`, `accent`, `orange`, the sixteen —
and `themes/nushell.nu`, `themes/starship.toml` and `themes/vivid.yml` are
written against those roles rather than against colours. Resolving a theme is
three tiers, each filling in only what the one before could not say: the
terminal's sixteen by ANSI name (tier one, `themes/palettes/ansi.nuon`); shades
blended from the Ghostty theme file's hexes — foreground pulled halfway to
background is `fg_muted`, red mixed with yellow is `orange` (tier two, every
theme Ghostty has); and a palette file naming the shaded roles exactly, with a
bat and a vivid theme that match (tier three, shipped for Catppuccin).

The rule that shapes it: **the sixteen are never a hex, in any tier.** A hex is
right only while the terminal paints the palette it came from; a name is right
over SSH, in tmux, and after a hand edit of Ghostty's config. So the shell pins
exactly what ANSI has no word for, and `theme roles` shows which is which.

It is rendered, not resolved at startup, because a resolve spawns Ghostty to
find the theme file and the render runs vivid — 40 ms — while reading the
result is one `open` of a 1 kB NUON, 0.36 ms. `theme use` is `def --env` so the
session it runs in gets the same three things a startup gets, from the same
files. There is no `THEME` knob any more: the knob and this picker were two
ways to say "theme" that did not know about each other, and the installer put
users on the wrong side of the split.

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

## Measured

Nushell 0.115.1, Ghostty 1.3.1, macOS, 2026-09-18.

| What | Cost |
|---|---|
| the module, loaded | 18 ms — 78.4 ms of startup with it eager against 60.1 ms with it lazy, medians of 25 cold starts, 2026-09-19 with palette.nu |
| parsing the module | 13.8 ms — `nu -n -c 'use terminal *'` against an empty run, medians of 15; 8.2 ms before palette.nu on the same day, so the renderer is 5.6 ms of parse. `detect.nu` is 0.9 ms of it |
| `ghostty themes` | 31 ms — it spawns `ghostty +list-themes` |
| `ghostty themes --swatches` | 333 ms, reading all 463 theme files |
| `theme list` | 24 ms: a hundred palette files opened; 133 ms with `--swatches` (the four Catppuccins read Ghostty's files, through one listing) |
| `theme names` | 55 ms: the palettes plus Ghostty's list — what Tab pays on `theme use ` |
| `theme resolve <name>` | 40 ms for a Ghostty theme, of which 31 ms is `theme palette` spawning `ghostty +list-themes` to find the file; a palette with its own `terminal` block spawns nothing |
| `theme sync` | 44 ms: the resolve, vivid, three files written |
| `theme use` | 320 ms: the resolve, the icon through `qlmanage`, `ghostty set` validating through `+validate-config`, the paint, `ghostty reload` through osascript, then the render |
| reading the render at startup | 0.36 ms for `theme.nuon` (1 kB), 0.09 ms for `ls_colors` (6 kB), medians of 21 |
| reading all 463 files | 39 ms; `(?m)` over the whole file rather than `lines` halves the parse, 49 ms against 109 ms |
| one swatch | bit shifts rather than splitting the hex into pairs: 95 ms over all 463 against 380 ms |
| `ghostty +show-config` | 18 ms |
| `ghostty +show-face` | 26 ms per call; `font list` runs fifteen through `par-each` in 103 ms |
| installing Inconsolata from the archive | 8 MB downloaded, two faces (it has no italic) into `~/Library/Fonts` |

## Files

```
mod.nu       re-exports every file, and `terminal activate` (which does nothing)
load.nu      `use terminal *` + activate
meta.nuon    description, the ghostty dependency, no knobs
theme.nu     listing, reading and painting Ghostty's themes
palette.nu   roles, the three tiers, rendering, the picker, `theme use`
font.nu      the Nerd Font registry, installing, and the preview window
ghostty.nu   finding Ghostty and its config, the one line we add to it, and the shell
detect.nu    the terminal registry: installed, running, how to get one
```

## Limits

- Lazy, therefore interactive-only: `theme use X` in a script needs `use
  terminal *` first, because `pre_execution` does not fire for `nu -c`.
- A hand-written `~/.config/starship.toml` is not read any more: the distro
  owns starship's configuration and points `STARSHIP_CONFIG` at the rendered
  one. The way to change the prompt is a copy of `themes/starship.toml` in your
  own `themes/`.
- The user's copy of a template is picked at parse time for `theme use` in the
  running session (`source` needs a constant), so a `themes/nushell.nu` dropped
  in after the module loaded is seen by the next shell.
- Tier two blends in sRGB, not linear light. For the small steps between a
  background and its foreground the difference is invisible; it is noted here
  in case someone measures.
- Ghostty only. The OSC painting would work in any terminal that implements
  OSC 4/10/11/12/17/19, but the themes, the theme files and the config writing
  are Ghostty's. The registry in `detect.nu` is where a second terminal would
  go; nothing else assumes there is only one.
- Ghostty has no Windows build yet, so `terminal install` on Windows prints the
  download page and runs nothing.
- Off macOS there is no `ghostty reload` (it is AppleScript), so a write
  reaches new windows only; the running one is repainted over OSC instead.
- `cursor-text` in a theme file is ignored: there is no OSC for it.
- Off macOS a font takes effect in new windows only: no reload, and no
  escape sequence for changing font.
- That the preview window renders in the requested family is Ghostty's
  documented CLI behaviour (`ghostty --help` gives `--font-family="Fira Code"`
  as its own example) and the window was verified to open and run the specimen;
  it has not been checked pixel by pixel.
- `font install` without Homebrew downloads the whole release archive and throws
  most of it away, because a GitHub release asset cannot be extracted in part.
  Iosevka is 402 MB and Noto is 620 MB for four files.
- The Windows branch of `font install` — the per-file `HKCU\...\Fonts` registry
  value a user-installed font needs — is written from the documented behaviour
  and has not been run.
- Untested on Linux and Windows. The config candidates and the resources
  directory are derived per platform but only the macOS paths have been run.
  That includes `ghostty shell`: whether Ghostty on Linux starts a bare
  `command` as a login shell has not been checked, only that it starts it.
