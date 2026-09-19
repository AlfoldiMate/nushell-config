# config.nu — yours. Nushell loads this file, and this file loads the distro.
#
# Everything next to it is yours too:
#   settings.nu      your overrides          (nu-config edit user)
#   autoload/*.nu    drop-ins, loaded last   — machine-local, anything goes
#   completions/     what you fetched or wrote
#   themes/          your themes
#   plugins/         plugins you built or downloaded
#
# The distro below is a git checkout you do not edit; `git pull` in it picks up
# new defaults without touching anything here.

const DISTRO = @DISTRO@
source ($DISTRO | path join distro.nu)
