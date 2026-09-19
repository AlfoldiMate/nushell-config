# `themes/` — one file per theme

A theme is a `.nu` file that assigns `$env.config.color_config` **and nothing
else**. `conf/theme.nu` sources the one named in the `THEME` knob, by bare name
through `NU_LIB_DIRS` — so a file of the same name in your own `themes/`
directory wins over the shipped one.

```nu
const THEME = "terminal"     # in your settings.nu: ls themes/ without the .nu
```

| | colours | follows the terminal |
|---|---|---|
| `terminal.nu` *(default)* | 16 ANSI names, no hex | yes — pick any of Ghostty's 463 and Nushell follows |
| `catppuccin-{latte,frappe,macchiato,mocha}.nu` | a 26-colour palette in hex | no |
| `"dark"` / `"light"` | the standard library's, no file here | no |

`terminal.nu` is the interesting one: because it names colours instead of
specifying them, the terminal's own palette *is* the theme. `VIVID_THEME` and
`BAT_THEME` default to `"ansi"` for the same reason, so `ls` colours and `bat`
follow too, and there is no generated file to keep in sync with anything. With
`THEME = "terminal"` the thing to change is the terminal: `theme` (the
`terminal` module) repaints this window as you scroll the list and keeps the one
you say yes to.

A theme must not set behaviour. `conf/theme.nu` runs *after* your `settings.nu`,
so a theme that assigns a knob would silently overwrite what you chose — this
is why `highlight_resolved_externals`, which the four Catppuccin files used to
set, lives in `defaults.nu` instead.

## Trying one without editing anything

```nu
source terminal.nu
source catppuccin-latte.nu
use std/config light-theme; $env.config.color_config = (light-theme)
```

The change lasts for the session. `theme` and `theme reset` do the same for the
terminal's palette.

## Writing your own

Drop a file that assigns `$env.config.color_config` into your `themes/`
directory and name it in `THEME`. `terminal.nu` is the smallest one to copy, and
its header has the command that re-diffs it against `std/config dark-theme`
after a Nushell upgrade — worth running, because upstream adds keys.

Nothing is fetched at runtime. The distro used to have `nu-config fetch theme`;
a theme downloaded onto a live machine is exactly the kind of state this layout
keeps out of the config directory (`docs/layout.md`).
