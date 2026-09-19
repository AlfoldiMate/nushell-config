# settings.nu — yours. Override anything the distro ships.
#
# Sourced straight after the distro's defaults.nu, so a `const` here shadows
# the one there and an `$env.` assignment here replaces it. Every knob is
# below, in its section, commented out at its shipped value — the same list
# `nu-config knobs` prints, from the same source. Uncomment a line and change
# it. Everything you leave commented keeps tracking the distro, including a
# knob added by a later `nu-config upgrade`: the next `nu-config user init`
# appends it here, commented, so that this file stays the whole list.
#
#   nu-config knobs              every knob, and whether you have overridden it
#   nu-config knobs --overridden just yours
#   nu-config user init          append the knobs the distro has grown since this file was written
#
# For anything that is not a knob — an alias, a hook, a keybinding, a secret —
# drop a .nu file in autoload/ instead (autoload/README.md). Those load last
# and win. ../../docs/getting-started/first-setting.md is the page.
