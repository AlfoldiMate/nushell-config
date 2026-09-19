# Pick a theme and make it stick

## Pick one

```nu
theme                        # scroll the hundred palettes; the window you are in is the preview
theme --ghostty              # or Ghostty's own 463
theme use tokyonight         # by name — Tab completes them
```

That is the whole of it. `theme use` writes Ghostty's theme and app icon,
repaints this window and reloads every open one, and renders the shell's
colours, `LS_COLORS`, the bat theme and the starship prompt into
`<your>/.state/theme/`, which every new shell reads in 0.36 ms. There is no
knob to set: what was rendered last is the theme.

```nu
theme status                 # what is rendered, from which theme, at which tier, and whether Ghostty agrees
theme roles                  # every role, its colour, and which tier decided it
theme reset                  # only after a `theme preview`: hand the terminal back to Ghostty's config
```

## Make a palette of your own

The shell's colours are written in **roles** — `accent`, `ok`, `warn`, `err`,
`fg_muted`, `border`, and the rest ([Theming](../concepts/theming.md#roles-and-the-three-tiers)).
A palette file names them. The shortest one extends a theme Ghostty already
ships, borrowing its sixteen, and names only the roles you care about:

```nu
# <your dir>/themes/palettes/harbour.nuon
{
  name: Harbour
  ghostty: "Gruvbox Dark"      # the Ghostty theme whose file supplies the sixteen
  dark: true
  colours: {
    sea: "#1d3557"
    foam: "#a8dadc"
    rope: "#e9c46a"
    rust: "#e76f51"
    kelp: "#2a9d8f"
    fog: "#8d99ae"
  }
  roles: {
    accent: foam
    ok: kelp
    warn: rope
    err: rust
    fg_muted: fog
    border: sea
  }
}
```

The file's stem is the slug of its `name` — lowercased, runs of anything but
letters and digits turned into `-`; `theme slug "TokyoNight Storm"` prints
`tokyonight-storm`. A role may name one of your `colours` or carry a hex of
its own. Every role you do not name is blended from the Ghostty theme's own
hexes (tier two), and the sixteen stay the terminal's (tier one), so six
colours is a complete palette.

For a theme that is entirely yours, copy one of NvChad's
(`themes/palettes/nvchad/tokyonight.nuon` in the checkout) and change the
`terminal` block — all sixteen plus background, foreground, cursor and
selection — and `theme use` writes it as a Ghostty theme file too.

Check it before you keep it:

```nu
theme list | where theme == Harbour          # kind: yours
theme roles Harbour                          # from: palette for the six, ansi for the sixteen, derived for the rest
theme resolve Harbour | select name by tier  # the record, nothing written
theme use Harbour
```

Run on 2026-09-19 with the file above in a scratch user directory: listed as
`yours`; `accent` `#a8dadc` from `palette`, `red` `red` from `ansi`;
`theme use` took 492 ms and `theme status` then showed `Harbour`, Ghostty
resolving `Gruvbox Dark`, and `icons/harbour.png` rendered.

A palette with the same slug as a shipped one shadows it — the same rule as
a completion ([Override a shipped completion](override-completion.md)).

## Keep it after a `git pull`

Your theme is not in the checkout, so a pull cannot take it away. What a
pull *can* change is a template — `themes/nushell.nu`, `starship.toml`,
`vivid.yml`, `icon.svg` — which the rendered files were made from:

```nu
theme sync                   # re-resolve and re-render the current theme from the templates as they are now
```

The update notice at startup says when to; `nu-config doctor`'s Theme line
shows when the render was made.

To change a template rather than a palette — a different prompt layout, say
— copy it into your `themes/` and edit the copy there. It is picked up over
the shipped one, `theme sync` renders it, and it must be written in roles,
never hexes, so that every theme keeps fitting it. The user's copy is chosen
at parse time for `theme use` in the running session, so a template dropped
in after the module loaded is seen by the next shell.
