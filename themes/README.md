# `themes/` — one theme, rendered for everything

```nu
theme                          # pick one of Ghostty's 463; the window is the preview
theme use "Catppuccin Mocha"   # by name — Ghostty, tables, ls, bat and the prompt, now and persistently
theme roles                    # every role, its colour, and which tier decided it
theme status                   # what is rendered, from which theme, and whether Ghostty agrees
theme sync                     # re-render after a `git pull` changed a template, or a copy of yours
```

There is one theme and it is the terminal's. `theme use` writes Ghostty's
configuration, repaints the window you are in, and renders the shell's own
colours from the same palette, so a table separator, a `ls` directory, a `bat`
keyword and a prompt segment all come from the theme you named — in this window
now and in every shell after, because the render is a file. No `THEME` knob:
what was rendered last is the theme.

## Roles, and the three tiers

Nobody writes a Nushell theme, a starship palette or a vivid theme per theme.
The three files here are templates written against a **role vocabulary**:

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
| **2 derived** | the Ghostty theme file | the sixteen, background and foreground as hex, so the shaded roles are **blended**: `fg_muted` is the foreground pulled halfway to the background, `border` the background a quarter of the way to the foreground, `orange` red mixed with yellow. Every one of Ghostty's 463 gets this. |
| **3 palette** | `palettes/<slug>.nuon` | the shaded roles named exactly — Catppuccin's `overlay1`, `surface1`, `peach` — and a bat and a vivid theme that already match. Shipped for the four Catppuccin flavours. |

The sixteen stay names in every tier on purpose. A hex is right only while the
terminal paints the palette it came from; a name is right in an SSH session, in
tmux, and after someone edits Ghostty's config by hand. So the shell pins only
what ANSI has no word for, and `theme roles` shows which is which.

## What is rendered, and where

`theme use` (and `theme sync`) writes `<your dir>/.state/theme/`:

| file | from | read by |
|---|---|---|
| `theme.nuon` | the resolved roles, name, tier, bat theme | `conf/theme.nu`, one `open` at startup — 0.36 ms |
| `starship.toml` | `starship.toml` here, `[palettes.distro]` filled in | `conf/prompt.nu` sets `STARSHIP_CONFIG` to it |
| `ls_colors` | vivid, on `vivid.yml` here or the palette's named vivid theme | `conf/theme.nu` → `LS_COLORS` |

Rendered rather than resolved at every start because a resolve spawns Ghostty
to find the theme file and a render runs vivid: 40 ms, against 0.4 ms to read
the result.

| template | rendered for |
|---|---|
| `nushell.nu` | `$env.config.color_config` and `explore`. Reads `$c`, the roles; sourced by `conf/theme.nu` at startup and by `theme use` in the running session |
| `starship.toml` | the prompt. Its own `[palettes.distro]` block is tier one, so it works unrendered |
| `vivid.yml` | `LS_COLORS`. vivid's `ansi` rules with the `colors:` block rendered |

## Changing a template, or adding a palette

Your `themes/` directory comes first on `NU_LIB_DIRS` and is checked first by
the renderer, so a copy of any of the three templates there is the one used —
`theme sync` after editing it. Stick to roles and every theme keeps fitting it.

A palette of your own is `<your dir>/themes/palettes/<slug>.nuon`, where the
slug is the Ghostty theme name lowercased with runs of anything but letters
and digits turned into `-` (`theme slug "TokyoNight Storm"` →
`tokyonight-storm`). Copy a Catppuccin one: `colours` may hold any names, a
role may name one of them or carry a colour of its own, and `bat` / `vivid`
name themes those tools ship (`bat --list-themes`, `vivid themes`); leave them
out and bat gets `ansi` and vivid the rendered template.

Trying a theme without keeping it is `theme preview <name>` and `theme reset`
— the terminal only; the shell's colours change with `theme use`.

Nothing is fetched at runtime, and nothing here is written by anything but
`theme use`. The distro used to ship four hand-written Catppuccin themes and a
`THEME` knob to choose one; the knob and the Ghostty picker were two ways to
say "theme" that did not know about each other, which is why they went.
