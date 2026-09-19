# Pin a font

```nu
font list                    # fifteen Nerd Fonts: installed here, current, the family Ghostty reports
font preview FiraCode        # a new Ghostty window in that font, showing a specimen — nothing written
font use FiraCode            # install it if it is missing, write it into Ghostty's config, reload every window
```

`font use` is the whole pin. It writes `font-family = FiraCode Nerd Font`
into the file the distro owns in Ghostty's config directory — reset first,
because `font-family` is a list and the distro's file is applied after yours
([Theming](../concepts/theming.md#show-face-not-list-fonts-not-a-directory-listing))
— and asks Ghostty to reload. Check:

```nu
font list | where current    # one row
ghostty live font-family     # what Ghostty itself resolves: FiraCode Nerd Font
ghostty settings             # the keys the distro owns, font-family among them
```

Run on 2026-09-19 on a Mac whose own Ghostty config sets `JetBrainsMono Nerd
Font Mono`: after `font use FiraCode`, `current` moved to FiraCode and
`ghostty live font-family` said `FiraCode Nerd Font`; after `ghostty set {
font-family: null }`, back to JetBrainsMono. Every open window followed on
macOS; elsewhere a font reaches new windows only.

To stop pinning and let Ghostty's own config decide again:

```nu
ghostty set { font-family: null }
```

## Install one by hand

`font install <name>` uses Homebrew's cask on macOS (so `brew upgrade` keeps
the font current) and the Nerd Fonts release archive everywhere else. The
archive path has been run on macOS; on Linux and Windows the same code is
written from the documented behaviour and not yet run
([Platforms](../reference/platforms.md)). If it fails you, this is what it
does, and it is four files:

**1. The archive.** `https://github.com/ryanoasis/nerd-fonts/releases/latest/download/<asset>.tar.xz`
on Linux (`.zip` on Windows, whose `tar` reads zip). `<asset>` is the
registry's name for the font — `font list | get font`; `FiraCode`,
`JetBrainsMono`, `Meslo` — and the archive holds every variant, from 8 MB
(Inconsolata) to 620 MB (Noto).

**2. Four faces** out of it: `<stem>-Regular.ttf`, `-Bold`, `-Italic`,
`-BoldItalic`, where `<stem>` is the file stem the registry carries
(`FiraCodeNerdFont`, `MesloLGSNerdFont`, `CaskaydiaCoveNerdFont` — Nerd
Fonts renames several). A font that ships fewer faces installs fewer:
Inconsolata has no italic.

```nu
use terminal *
font list | where font == FiraCode | get 0.family   # the family Ghostty will report: "FiraCode Nerd Font"
font dir                                            # where they go
```

**3. Where they go.** `~/.local/share/fonts` on Linux, then `fc-cache -f` on
that directory (without fontconfig the font may not appear until you sign in
again). `%LOCALAPPDATA%\Microsoft\Windows\Fonts` on Windows, plus one registry
value per file or the font is visible only until the next sign-out:

```
reg add "HKCU\Software\Microsoft\Windows NT\CurrentVersion\Fonts" /v "FiraCodeNerdFont-Regular (TrueType)" /t REG_SZ /d FiraCodeNerdFont-Regular.ttf /f
```

**4. Tell Ghostty.** `font use FiraCode` now finds it installed and writes the
family; or `ghostty set { font-family: "FiraCode Nerd Font" }` directly.

Whether a font is installed is a question only the terminal can answer:
`font face "FiraCode Nerd Font"` asks Ghostty for the face it would use, with
no config loaded, and an installed family comes back as itself, a missing one
as Ghostty's built-in `JetBrains Mono`. 22 ms per question; `font list` asks
fifteen in parallel.
