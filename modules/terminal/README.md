# modules/terminal

The terminal you are running in: its theme, and its configuration.

```nu
terminal list                  # which terminals this distro knows, and what is true here
theme                          # pick from Ghostty's 463, the terminal is the preview
font                           # pick a Nerd Font, install it, see it in a real window
theme use "TokyoNight Storm"   # or name one; Tab completes them
ghostty shell                  # a new Ghostty window starts Nushell
ghostty status                 # what this distro has written into Ghostty's config
```

The two belong in one module because of how this distro does colour. `THEME =
"terminal"` makes Nushell's theme the terminal's own sixteen ANSI colours, so
"change the Nushell theme" means "change Ghostty's theme": write Ghostty's
configuration, and repaint the window you are sitting in. `theme.nu` chooses and
paints, `ghostty.nu` writes, `detect.nu` answers the two questions `install.nu`
asks before either of them runs.

## Commands

| Command | Does |
|---|---|
| `theme` | the picker: all 463 with their own colours beside them, then paint, then keep or not |
| `theme list [--swatches]` | every theme Ghostty can find, with its file; `--swatches` adds the sixteen colours |
| `theme palette <name>` | one theme file as data: `palette` 0-15 and the named colours |
| `theme preview <name>` | paint this session, change nothing on disk |
| `theme reset` | hand the palette back to Ghostty's config — the way out of a preview |
| `theme use <name>` | paint, and keep: `ghostty set` persists it for new windows |
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

None. Nothing here has a knob: both files read Ghostty's own configuration at the
moment you ask, so there is no state to set up and nothing for your `settings.nu`
to have to win against. The one setting nearby is `THEME` in `defaults.nu`, which
belongs to `conf/theme.nu`, not to this module.

## Dependencies

`ghostty`, and hard: the themes, their files and the configuration being written
are all Ghostty's. `nu-config module check terminal`. Without it `theme list`
errors and `theme reset` still works — OSC is the terminal's, not Ghostty's, so
the escape sequences are understood by any terminal that implements them; only
everything that has to *know* what a theme is needs Ghostty.

## Design

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
fonts it has, and a name in a list tells you nothing. You cannot preview one you
*have* installed in the window you are sitting in either — Ghostty has no CLI
reload, and there is no escape sequence for "change font" the way OSC 4 is
"change colour". That asymmetry is why the theme picker repaints in place and
the font picker cannot.

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
| the module, loaded | 18 ms — 97.4 ms of startup with it eager against 79.0 ms with it lazy, medians of 25 cold starts |
| parsing the module | 4.6 ms — `nu -n -c 'use terminal *'` at 26.1 ms against a 21.5 ms empty run, medians of 15. `detect.nu` is 0.9 ms of it |
| `theme list` | 31 ms — it spawns `ghostty +list-themes` |
| `theme list --swatches` | 333 ms, reading all 463 theme files |
| reading all 463 files | 39 ms; `(?m)` over the whole file rather than `lines` halves the parse, 49 ms against 109 ms |
| one swatch | bit shifts rather than splitting the hex into pairs: 95 ms over all 463 against 380 ms |
| `ghostty +show-config` | 18 ms |
| `ghostty +show-face` | 26 ms per call; `font list` runs fifteen through `par-each` in 103 ms |
| installing Inconsolata from the archive | 8 MB downloaded, two faces (it has no italic) into `~/Library/Fonts` |

## Files

```
mod.nu       re-exports both halves, and `terminal activate` (which does nothing)
load.nu      `use terminal *` + activate
meta.nuon    description, the ghostty dependency, no knobs
theme.nu     listing, parsing, painting, and the picker
font.nu      the Nerd Font registry, installing, and the preview window
ghostty.nu   finding Ghostty and its config, the one line we add to it, and the shell
detect.nu    the terminal registry: installed, running, how to get one
```

## Limits

- Lazy, therefore interactive-only: `theme use X` in a script needs `use
  terminal *` first, because `pre_execution` does not fire for `nu -c`.
- Ghostty only. The OSC painting would work in any terminal that implements
  OSC 4/10/11/12/17/19, but the themes, the theme files and the config writing
  are Ghostty's. The registry in `detect.nu` is where a second terminal would
  go; nothing else assumes there is only one.
- Ghostty has no Windows build yet, so `terminal install` on Windows prints the
  download page and runs nothing.
- Ghostty cannot reload its config from the CLI (`reload_config` is a keybind
  action), so a write reaches new windows only; the running one is repainted
  over OSC instead. The two together are why `theme use` does both.
- `cursor-text` in a theme file is ignored: there is no OSC for it.
- A font takes effect in new windows only, for the same reason a theme needs
  OSC: Ghostty cannot reload its configuration from the CLI, and there is no
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
