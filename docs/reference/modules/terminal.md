# terminal

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
templates being rendered live in `themes/` ([Theming](../../concepts/theming.md)), and a copy in
your own `themes/` is the one used.

## Dependencies

`ghostty`, and hard: the configuration being written is Ghostty's, and so are
the 463 themes behind `--ghostty`. `nu-config module check terminal`. Without
it the palettes still list and resolve (at tier three, with no window to
paint), `theme list --ghostty` errors and `theme reset` still works — OSC is the terminal's, not Ghostty's, so
the escape sequences are understood by any terminal that implements them; only
everything that has to *know* what a theme is needs Ghostty.

## Design

Why the theme is the terminal's, why the picker paints the window instead of
drawing swatches, why a font is previewed in a window of its own, and every
Ghostty fact the module rests on: [Theming](../../concepts/theming.md).

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
| `theme use` | 320 ms: the resolve, the icon through AppKit (`rasterize.js`, 100 ms), `ghostty set` validating through `+validate-config`, the paint, `ghostty reload` through osascript, then the render |
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
