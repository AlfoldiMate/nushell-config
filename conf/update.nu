# update.nu — tell an interactive shell when the distro is behind its remote
#
# Two things, both off the network. Read the last check's result and print one
# line when it says there is something to pull. And when that result is older
# than UPDATE_CHECK_EVERY, start a fresh check as a background job — the
# `git fetch` runs while you type, and what it finds is what the NEXT start
# reports. The commands are `nu-config upgrade …`, modules/nu-config/upstream.nu;
# `nu-config upgrade` is the pull.
#
# Interactive only: `nu -c` and a script get no notice and spawn nothing — a
# script whose output starts with "distro: 2 commits behind" is a bug. A job
# also dies with the shell that spawned it, and a script would be gone before
# the fetch returned.
if $nu.is-interactive and $UPDATE_CHECK_EVERY > 0sec {
  nu-config upgrade notice
  if (nu-config upgrade stale $UPDATE_CHECK_EVERY) {
    job spawn --description "nu-config upgrade check" {|| nu-config upgrade check | ignore } | ignore
  }
}
