# `themes/` — one theme, rendered for everything

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

## What there is to choose from

| | how many | what |
|---|---|---|
| **palettes** — `theme list` | 100 | files in `palettes/`: NvChad's 96 base46 themes (`palettes/nvchad/`, imported) and the four Catppuccin flavours (hand-made). A palette carries the shaded roles exactly, so these are tier three |
| **Ghostty's** — `theme list --ghostty` | 463 | Ghostty's own theme files: the sixteen, background, foreground. Tier two: the shades are blended |

The two are different kinds of thing, which is why they are two lists. A
Ghostty theme is sixteen colours; a palette is thirty — NvChad's `grey_fg`,
`one_bg2`, `orange`, `teal` are exactly what the shell's roles ask for, which
is why base46 was worth importing. `theme use <name>` looks for a palette
first and falls back to Ghostty's list; `--ghostty` skips the palettes.

## Roles, and the three tiers

Nobody writes a Nushell theme, a starship palette, a vivid theme or an icon per
theme. The four files here are templates written against a **role vocabulary**:

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
| **1 ansi** | `palettes/ansi.nuon` | every role an ANSI name. `red` is whatever the terminal paints red; `fg_muted` has to be `dark_gray` and `orange` has to be `yellow`. What a machine without Ghostty gets, and the shell before the first `theme use`. |
| **2 derived** | the sixteen as hex — a palette's `terminal` block, or Ghostty's theme file | the shaded roles are **blended**: `fg_muted` is the foreground pulled halfway to the background, `border` the background a quarter of the way to the foreground, `orange` red mixed with yellow. Every one of Ghostty's 463 gets this. |
| **3 palette** | `palettes/**/<slug>.nuon` | the shaded roles named exactly — Catppuccin's `overlay1`, NvChad's `grey_fg` and `one_bg2` — and a bat and a vivid theme that already match. |

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

`theme use` renders `icon.svg` — Jason Long's ghostty-theme-icons drawing,
with `bg`, `fg` and the four bar colours (`err`, `accent`, `ok`, `warn`) as
placeholders — to a PNG with macOS's own `qlmanage`, and hands Ghostty
`macos-icon = custom` + `macos-custom-icon = <it>`. No icon files are shipped:
a hundred themes is a hundred 2.5 MB `.icns`, and six colours is all an icon
is. `theme use --no-icon` leaves the icon alone, `theme icon --off` takes the
keys back out. Off macOS nothing happens.

## What is rendered, and where

`theme use` (and `theme sync`) writes `<your dir>/.state/theme/`:

| file | from | read by |
|---|---|---|
| `theme.nuon` | the resolved roles, name, tier, bat theme | `conf/theme.nu`, one `open` at startup — 0.36 ms |
| `starship.toml` | `starship.toml` here, `[palettes.distro]` filled in | `conf/prompt.nu` sets `STARSHIP_CONFIG` to it |
| `ls_colors` | vivid, on `vivid.yml` here or the palette's named vivid theme | `conf/theme.nu` → `LS_COLORS` |
| `ghostty/<slug>` | a palette's `terminal` block as a Ghostty theme file | Ghostty, through `theme =` in the distro's included file |
| `icons/<slug>.png` | `icon.svg` with the roles filled in | Ghostty, through `macos-custom-icon` |

Rendered rather than resolved at every start because a resolve may spawn
Ghostty to find a theme file and a render runs vivid and the rasterizer: 40 ms
to resolve, 320 ms for a whole `theme use`, against 0.4 ms to read the result.

| template | rendered for |
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

The NvChad import is `palettes/nvchad/import.nu`: it reads base46's `base_30`
(the thirty UI colours, which map onto the roles almost one to one) and writes
one file per theme. Run it by hand when base46 moves; nothing fetches at
runtime. `catppuccin-latte` is skipped because the hand-made one, which
extends Ghostty's own Catppuccin Latte with all 26 colours, has that slug.

Trying a theme without keeping it is `theme preview <name>` and `theme reset`
— the terminal only; the shell's colours change with `theme use`.
