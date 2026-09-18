# terminal — the terminal you are running in: its theme, and its configuration
#
#   theme              pick one of Ghostty's 463 themes, the terminal as preview
#   ghostty status     what this distro has written into Ghostty's config
#
# The two belong together because of how this distro does colour: THEME =
# "terminal" makes Nushell's theme the terminal's own sixteen ANSI colours, so
# "change the Nushell theme" means "change Ghostty's theme", which means writing
# Ghostty's configuration and repainting the running window. theme.nu is the
# choosing and the painting, ghostty.nu is the writing.
#
# Lazy, and measured: parsing these two files costs 10 ms of every shell start
# (95 ms against 87 ms, medians of 15 cold starts), for commands a shell uses
# once in a while. So `theme` and `ghostty` are trigger words — see meta.nuon.

export use ghostty.nu *
export use theme.nu *

# Nothing to wire: no hooks, no completion providers, no knobs. The contract
# (docs/modules.md) wants an `activate` and this is the honest one — both files
# read Ghostty's own configuration at the moment you ask, so there is no state
# to set up and nothing for the user's settings.nu to have to win against.
export def "terminal activate" []: nothing -> nothing { }
