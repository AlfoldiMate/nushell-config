# Your first theme

There is one theme and everything follows it. `theme use` hands Ghostty a
theme and a matching app icon, repaints the window you are in (and reloads
every open one), and renders the shell's own colours — tables, `ls`, `bat`,
the starship prompt — from the same palette, now and in every shell after.

```nu
theme                        # scroll a hundred palettes — NvChad's 96 and Catppuccin; the live window is the preview
theme --ghostty              # or Ghostty's own 463
theme use tokyonight         # by name, no picker; Tab completes the names
theme roles                  # what the shell made of it: each role, its colour, which tier decided it
theme status                 # what is rendered, from which theme, and whether Ghostty agrees
theme reset                  # the terminal back to what Ghostty had, after a preview
```

The picker lists each theme with its own sixteen colours beside it. Choose
one and the whole terminal — prompt, tables, scrollback — is painted in it
before you are asked whether to keep it. Nothing is written until you say
yes.

There is no `THEME` knob to set: what was rendered last is the theme, and a
new shell reads the render in 0.36 ms. `theme use` needs Ghostty for the
writing and the 463 `--ghostty` themes; the palettes list and render without
it, at the ANSI tier ([Theming](../concepts/theming.md)).

## A font

```nu
font                         # the picker: fifteen Nerd Fonts, what is installed, what is current
font preview FiraCode        # a new Ghostty window in that font, showing a specimen
font use FiraCode            # install it if needed, then make it Ghostty's
```

A font cannot be previewed in the window you are in — there is no escape
sequence for "change font" the way there is for colour — so `font preview`
opens a window of its own. `font use` installs from Homebrew's cask on macOS
and from the Nerd Fonts release archive elsewhere, then reloads Ghostty.

## Ghostty starts Nushell

If you said yes on the installer's terminal screen, this is done. Otherwise:

```nu
ghostty shell                # a new Ghostty window starts nu; `--reset` hands it back
ghostty status               # the config Ghostty reads, what the distro wrote into it, the theme it resolves
```

The distro never edits Ghostty's own config beyond one `config-file =`
include line, added once; everything it sets lives in a file of its own that
`ghostty reset` removes.

Next: [Updating](updating.md).
