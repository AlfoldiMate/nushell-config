# update — is the distro checkout behind its remote, and pulling it
#
#   nu-config upgrade            git pull --ff-only in the checkout, then say what changed
#   nu-config upgrade check      fetch now and report where the checkout stands
#   nu-config upgrade status     the last check's result; touches no network
#   nu-config upgrade notice     the one-line "there is an update" the shell prints at start
#
# The check that runs by itself is wired in conf/update.nu. The network is
# never on the startup path: at an interactive start the LAST result is read
# out of a small state file and, when it says the checkout is behind, one line
# is printed; when that result is older than UPDATE_CHECK_EVERY a fresh check
# runs as a background job (`job spawn`), and its result is what the NEXT start
# reports. A job dies with the shell that spawned it, so a window closed
# within a second or two of opening loses that check — and the next window
# simply runs it again, because the result is still stale.
#
# The state file lives in your directory, `.state/nu-config/upgrade.nuon`,
# never in the checkout: `git pull` has to stay clean. It records the HEAD the
# check was made against, so a pull done by hand — or by `nu-config upgrade` —
# retires the notice at once rather than a day later.
#
# A checkout without a `.git`, without a remote-tracking branch, or without git
# on PATH records why and stays quiet: the notice is for the one case where
# there is something to do.

# This file is modules/nu-config/upstream.nu: a module cannot export a command
# named after itself. And the command is `upgrade`, not `update`, because
# `update` is a built-in and a module that defines one shadows it for
# everything parsed after — `use nu-complete *` in mod.nu stopped parsing.; `distro-root` lives in mod.nu,
# which imports this file and so is not visible from it.
const ROOT = path self | path dirname | path dirname | path dirname

def distro-root []: nothing -> path { $ROOT | path expand }

def state-path []: nothing -> path {
  $nu.data-dir | path join .state nu-config upgrade.nuon
}

# git, run in the checkout, output captured. The arguments come as a list,
# because a rest parameter would read `--abbrev-ref` as a flag of ours.
# `GIT_TERMINAL_PROMPT=0` so a fetch that wants credentials fails instead of
# asking a background job for a password.
def git-in [args: list<string>]: nothing -> record<stdout: string, stderr: string, exit_code: int> {
  let root = (distro-root)
  with-env { GIT_TERMINAL_PROMPT: "0" } {
    ^git -C $root ...$args | complete
  }
}

# Its stdout, trimmed, or null when git said no.
def git-ok [args: list<string>]: nothing -> any {
  let r = (git-in $args)
  if $r.exit_code == 0 { $r.stdout | str trim } else { null }
}

# What the checkout is a git checkout OF: null with the reason when the check
# cannot be made at all.
def unable []: nothing -> any {
  if (which git | is-empty) { return "git is not on PATH" }
  if not ((distro-root) | path join .git | path exists) { return "the distro is not a git checkout" }
  if (git-ok [rev-parse --abbrev-ref --symbolic-full-name '@{u}']) == null { return "the checked-out branch tracks no remote branch" }
  null
}

# Where HEAD stands against its upstream, from what is already fetched.
def measure []: nothing -> record {
  let counts = (git-ok [rev-list --left-right --count 'HEAD...@{u}'] | default "0\t0" | split row "\t")
  {
    checked: (date now)
    head: (git-ok [rev-parse HEAD])
    upstream: (git-ok [rev-parse --abbrev-ref '@{u}'])
    ahead: ($counts | get 0 | into int)
    behind: ($counts | get 1 | into int)
    # Newest first, the way `git log` lists them.
    log: (git-ok [log --format=%s 'HEAD..@{u}'] | default "" | lines)
    error: null
  }
}

def save-state [s: record]: nothing -> record {
  let f = (state-path)
  mkdir ($f | path dirname)
  $s | to nuon | save -f $f
  $s
}

# The last check's result, or an empty record when there has never been one.
export def "upgrade status" []: nothing -> record {
  let f = (state-path)
  if ($f | path exists) { open $f } else { { checked: null, head: null, upstream: null, ahead: 0, behind: 0, log: [], error: "never checked" } }
}

# Fetch, measure, remember. Silent by design — it is what the background job
# runs — and the record it returns is what `status` will report from now on.
export def "upgrade check" []: nothing -> record {
  let why = (unable)
  if $why != null {
    return (save-state { checked: (date now), head: null, upstream: null, ahead: 0, behind: 0, log: [], error: $why })
  }
  let f = (git-in [fetch --quiet])
  if $f.exit_code != 0 {
    # Offline, most days. Keep the previous counts — they were true when made —
    # and note that this attempt did not get through.
    return (save-state ((upgrade status) | merge { checked: (date now), error: ($f.stderr | str trim | lines | get -o 0 | default "fetch failed") }))
  }
  save-state (measure)
}

# Has the last check gone stale, so the shell should spawn a new one?
export def "upgrade stale" [
  every: duration   # how old a result may be before a start re-checks
]: nothing -> bool {
  let s = (upgrade status)
  $s.checked == null or ((date now) - $s.checked) > $every
}

# HEAD without spawning git: `.git/HEAD` names a ref, and the ref is a file
# under `.git/` until git packs it, when it is a line in `packed-refs`. The
# startup path reads two small files where `git rev-parse` would fork. Null
# when it cannot be told, and null never matches, so an unreadable HEAD errs on
# the side of silence.
def head-now []: nothing -> any {
  let git = ((distro-root) | path join .git)
  let head = ($git | path join HEAD)
  if not ($head | path exists) { return null }
  let h = (open --raw $head | str trim)
  if not ($h | str starts-with "ref: ") { return $h }
  let ref = ($h | str replace "ref: " "")
  let loose = ($git | path join $ref)
  if ($loose | path exists) { return (open --raw $loose | str trim) }
  let packed = ($git | path join packed-refs)
  if not ($packed | path exists) { return null }
  open --raw $packed | lines | parse "{sha} {name}" | where name == $ref | get -o 0.sha
}

# One line, when — and only when — the last check found the checkout behind
# the HEAD it still has. Read from the state file; no git, no network.
export def "upgrade notice" []: nothing -> nothing {
  let s = (upgrade status)
  if $s.error != null or $s.behind == 0 or $s.head != (head-now) { return }
  let n = (if $s.behind == 1 { "1 commit" } else { $"($s.behind) commits" })
  let latest = ($s.log | get -o 0 | default "")
  let tail = (if ($latest | is-empty) { "" } else { $" · ($latest)" })
  print $"(ansi dark_gray)distro: ($n) behind ($s.upstream)($tail) — (ansi reset)(ansi cyan)nu-config upgrade(ansi reset)"
}

# Pull. Fast-forward only: a checkout with commits of its own is a development
# checkout, and merging on its behalf is not a maintenance command's call.
export def upgrade []: nothing -> nothing {
  let why = (unable)
  if $why != null { error make { msg: $"cannot update: ($why)" } }
  let before = (git-ok [rev-parse HEAD])
  let r = (git-in [pull --ff-only --quiet])
  if $r.exit_code != 0 {
    error make { msg: $"git pull failed in ((distro-root))", label: { text: ($r.stderr | str trim), span: (metadata $why).span } }
  }
  let after = (save-state (measure))
  if $before == $after.head {
    print $"already up to date with ($after.upstream)"
    return
  }
  print $"updated ((distro-root)) → ($after.upstream)"
  for l in (git-ok [log --format=%s $"($before)..($after.head)"] | default "" | lines) { print $"  ($l)" }
  print $"(ansi dark_gray)a new shell loads it; `nu-config doctor` checks it parsed(ansi reset)"
}
