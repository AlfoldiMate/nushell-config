# modules/terminal

The terminal you are running in: its theme, and its configuration.

```nu
theme                          # pick from Ghostty's 463, the terminal is the preview
theme use "TokyoNight Storm"   # or name one; Tab completes them
ghostty status                 # what this distro has written into Ghostty's config
```

The two belong in one module because of how this distro does colour. `THEME =
"terminal"` makes Nushell's theme the terminal's own sixteen ANSI colours, so
"change the Nushell theme" means "change Ghostty's theme": write Ghostty's
configuration, and repaint the window you are sitting in. `theme.nu` chooses and
paints, `ghostty.nu` writes.

## Commands

| Command | Does |
|---|---|
| `theme` | the picker: all 463 with their own colours beside them, then paint, then keep or not |
| `theme list [--swatches]` | every theme Ghostty can find, with its file; `--swatches` adds the sixteen colours |
| `theme palette <name>` | one theme file as data: `palette` 0-15 and the named colours |
| `theme preview <name>` | paint this session, change nothing on disk |
| `theme reset` | hand the palette back to Ghostty's config — the way out of a preview |
| `theme use <name>` | paint, and keep: `ghostty set` persists it for new windows |
| `ghostty status` | the config Ghostty reads, what we own in it, and the theme Ghostty resolves |
| `ghostty set <record>` | write keys into our own included file (a null value removes one) |
| `ghostty reset` | remove our file and the one include line; their config is left as it was |

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

### Why it is lazy

Parsing these two files costs 10 ms of every shell start, for commands a shell
uses once in a while, so `theme` and `ghostty` are trigger words
(`MODULES_TRIGGERS` in `defaults.nu`). Typing `ghostty +list-themes` loads the
module too, which is harmless.

## Measured

Nushell 0.115.1, Ghostty 1.3.1, macOS, 2026-09-18.

| What | Cost |
|---|---|
| startup with the module lazy | 87 ms, against 95 ms when it was parsed eagerly (medians of 15 cold starts) |
| `theme list` | 31 ms — it spawns `ghostty +list-themes` |
| `theme list --swatches` | 333 ms, reading all 463 theme files |
| reading all 463 files | 39 ms; `(?m)` over the whole file rather than `lines` halves the parse, 49 ms against 109 ms |
| one swatch | bit shifts rather than splitting the hex into pairs: 95 ms over all 463 against 380 ms |
| `ghostty +show-config` | 18 ms |

## Files

```
mod.nu       re-exports both halves, and `terminal activate` (which does nothing)
load.nu      `use terminal *` + activate
meta.nuon    description, the ghostty dependency, no knobs
theme.nu     listing, parsing, painting, and the picker
ghostty.nu   finding Ghostty's config, and the one line we add to it
```

## Limits

- Lazy, therefore interactive-only: `theme use X` in a script needs `use
  terminal *` first, because `pre_execution` does not fire for `nu -c`.
- Ghostty only. The OSC painting would work in any terminal that implements
  OSC 4/10/11/12/17/19, but the themes, the theme files and the config writing
  are Ghostty's.
- Ghostty cannot reload its config from the CLI (`reload_config` is a keybind
  action), so a write reaches new windows only; the running one is repainted
  over OSC instead. The two together are why `theme use` does both.
- `cursor-text` in a theme file is ignored: there is no OSC for it.
- Untested on Linux and Windows. The config candidates and the resources
  directory are derived per platform but only the macOS paths have been run.
