# terminal — the terminal you are running in: its theme, and its configuration
#
#   theme              pick one of Ghostty's 463 themes, the terminal as preview
#   ghostty status     what this distro has written into Ghostty's config
#   ghostty shell      a new Ghostty window starts Nushell
#   terminal list      the terminals this distro knows: installed, running, how to get one
#   font               pick a Nerd Font, install it, and let a new window render it
#
# The two belong together because of how this distro does colour: there is one
# theme and it is the terminal's. `theme use` writes Ghostty's configuration,
# repaints the running window, and renders the shell's own colours — tables,
# ls, bat, the prompt — from the same palette. theme.nu reads and paints,
# palette.nu resolves and renders, ghostty.nu writes, and detect.nu answers the
# two questions the installer asks first: is it installed, and are we in it.
#
# Lazy, and measured: loading these files costs 18 ms (meta.nuon carries the
# number and docs/concepts/modules.md the method), for commands a shell uses once in a
# while. So `theme`, `ghostty` and `font` are trigger words — see meta.nuon.

export use ghostty.nu *
export use theme.nu *
export use palette.nu *
export use detect.nu *
export use font.nu *

# One knob and nothing else to wire: no hooks, no completion providers. Both
# files read Ghostty's own configuration at the moment you ask, so there is no
# state to set up. `default`, never assignment: the user's settings.nu was
# sourced long before this ran (docs/concepts/modules.md).
export def --env "terminal activate" []: nothing -> nothing {
  $env.NERD_FONTS_RELEASE = ($env.NERD_FONTS_RELEASE? | default "https://github.com/ryanoasis/nerd-fonts/releases/latest/download")
}
