# themes/ — palettes of your own, and any template you want to change

There is no theme knob. `theme use <name>` renders one palette for
everything at once — Ghostty and its app icon, tables, `ls`, bat and the
prompt — into `.state/theme/`, and what was rendered last is the theme.
`theme` alone is the picker, with the window you are in as the preview.

## A palette of your own

`palettes/example.nuon.off` is a complete palette: its own sixteen colours
in a `terminal` block, so `theme use` writes it as a Ghostty theme too, and
six roles named from its `colours`. Rename it `example.nuon` and it is in
`theme list` as `yours`; `theme use Example` renders it end to end. As
`.off` it is inert — the palette reader opens only `*.nuon`.

The shell's colours are written in **roles** — `accent`, `ok`, `warn`,
`err`, `fg_muted`, `border` and the rest — and a palette names them. What
you leave unnamed is blended from the palette's own background and
foreground; the sixteen stay the terminal's, always by name. A palette that
borrows the sixteen from a theme Ghostty ships says `ghostty: "Gruvbox
Dark"` instead of carrying a `terminal` block, and six colours is then a
whole palette. The file's stem is the slug of its `name` — `theme slug
"TokyoNight Storm"` → `tokyonight-storm` — and one with the same slug as a
shipped palette shadows it.

```nu
theme list | where kind == yours             # listed?
theme roles Example                          # every role, its colour, and which tier decided it
theme resolve Example | select name by tier  # the record, nothing written
theme use Example
```

## A template of your own

The four files a theme is rendered through — `nushell.nu` for
`$env.config.color_config`, `starship.toml`, `vivid.yml`, `icon.svg` — are
in the checkout's `themes/`. A copy here, under the same name, is the one
used: edit it in roles, never hexes, so that every theme keeps fitting it,
and `theme sync` re-renders.

- [Pick a theme and make it stick](../../../docs/cookbook/theme.md) — the picker, a palette from six colours, keeping it after a `git pull`
- [Theming](../../../docs/concepts/theming.md) — the roles, the three tiers, how the terminal side works
- the shipped palettes: [`../../../themes/palettes/`](../../../themes/palettes/) — Catppuccin's four by hand, NvChad's 96 imported
