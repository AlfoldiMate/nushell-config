# `nu-config upgrade check | status | notice | upgrade` against a git remote
# made in a scratch directory: this checkout cloned bare as the remote (plus
# the working tree's uncommitted changes, pushed as one commit), the remote
# cloned as the distro under test, and a third clone to push commits from. The commands run from the clone's own modules/ (`distro-root` is
# where the module lives), in a `nu -n` whose $nu.data-dir — the state
# file's home — is the run's own.
use lib.nu *
use std/assert

def --wrapped git [dir: string, ...args: string] {
  let r = ^git -C $dir -c user.name=test -c user.email=test@example.com ...$args | complete
  if $r.exit_code != 0 { error make { msg: $"git ($args | str join ' '): ($r.stderr)" } }
  $r.stdout | str trim
}

# { remote, distro, work, data }, the distro level with the remote, and an
# XDG_DATA_HOME of this test's own so the state file starts absent.
def clones []: nothing -> record {
  if (which -a git | where type == external | is-empty) { skip-test "git is not installed" }
  let d = scratch
  let remote = $d | path join remote.git
  let distro = $d | path join distro
  let work = $d | path join work
  ^git clone -q --bare $ROOT $remote
  ^git clone -q $remote $work
  # The clone holds HEAD; an edit to upstream.nu not committed yet would go
  # untested. What the working tree changed is pushed as one commit first.
  let changed = (^git -C $ROOT ls-files -m -o --exclude-standard | lines)
  let deleted = (^git -C $ROOT ls-files -d | lines)
  for f in ($changed | where {|f| $f not-in $deleted }) {
    let dest = ($work | path join $f)
    mkdir ($dest | path dirname)
    cp ($ROOT | path join $f) $dest
  }
  for f in $deleted { rm -f ($work | path join $f) }
  if ($changed ++ $deleted | is-not-empty) {
    git $work add -A
    git $work commit -q -m "working tree"
    git $work push -q
  }
  ^git clone -q $remote $distro
  { remote: $remote, distro: $distro, work: $work, data: ($d | path join data) }
}

# One commit more on the remote.
def push-commit [c: record, subject: string] {
  $"($subject)\n" | save -a ($c.work | path join CHANGES.txt)
  git $c.work add CHANGES.txt
  git $c.work commit -q -m $subject
  git $c.work push -q
}

def in-distro [c: record, code: string]: nothing -> record {
  with-env { XDG_DATA_HOME: $c.data } {
    ^$nu.current-exe -n -c $"const NU_LIB_DIRS = [($c.distro | path join modules | to nuon)]; use nu-config; ($code)" | complete
  }
}

def "test check reports level, then behind by the commits pushed" [] {
  let c = clones
  let first = in-distro $c 'nu-config upgrade check | select ahead behind log error | to nuon'
  assert equal $first.exit_code 0 $first.stderr
  assert equal ($first.stdout | from nuon) { ahead: 0, behind: 0, log: [], error: null }

  push-commit $c "one more"
  push-commit $c "and another"
  let again = in-distro $c 'nu-config upgrade check | select ahead behind log error | to nuon'
  assert equal ($again.stdout | from nuon) { ahead: 0, behind: 2, log: ["and another" "one more"], error: null }
  let status = in-distro $c 'nu-config upgrade status | select behind upstream | to nuon'
  assert equal ($status.stdout | from nuon) { behind: 2, upstream: origin/main }
}

def "test status before any check says so and touches no network" [] {
  let c = clones
  let ran = in-distro $c 'nu-config upgrade status | select checked behind error | to nuon'
  assert equal ($ran.stdout | from nuon) { checked: null, behind: 0, error: "never checked" }
}

def "test notice prints one line when behind and nothing once HEAD moved" [] {
  let c = clones
  push-commit $c "shipped"
  in-distro $c 'nu-config upgrade check' | ignore
  let notice = in-distro $c 'nu-config upgrade notice'
  assert equal ($notice.stdout | ansi strip | str trim) "distro: 1 commit behind origin/main · shipped — nu-config upgrade"
  # A pull by hand retires the notice at once: the recorded HEAD is stale.
  git $c.distro pull -q --ff-only
  let after = in-distro $c 'nu-config upgrade notice'
  assert equal ($after.stdout | str trim) ""
  assert equal (in-distro $c 'nu-config upgrade status | get behind' | get stdout | str trim) "1" "the state file still says behind"
}

def "test stale is true before a check and after the interval" [] {
  let c = clones
  assert equal (in-distro $c 'nu-config upgrade stale 1day' | get stdout | str trim) "true"
  in-distro $c 'nu-config upgrade check' | ignore
  assert equal (in-distro $c 'nu-config upgrade stale 1day' | get stdout | str trim) "false"
  assert equal (in-distro $c 'nu-config upgrade stale 0sec' | get stdout | str trim) "true"
}

def "test upgrade pulls fast-forward and lists what came in" [] {
  let c = clones
  push-commit $c "a fix"
  let ran = in-distro $c 'nu-config upgrade'
  assert equal $ran.exit_code 0 $ran.stderr
  let out = $ran.stdout | ansi strip
  assert ($out | str contains $"updated ($c.distro) → origin/main") $out
  assert ($out | str contains "  a fix") $out
  assert equal (git $c.distro rev-parse HEAD) (git $c.work rev-parse HEAD)
  # A release may add to the scaffold: what is missing from the user's
  # directory — the run's own XDG_CONFIG_HOME here — is written after the pull.
  let user = ($env.XDG_CONFIG_HOME | path join nushell)
  assert ($out | str contains $"scaffold in ($user)") $out
  assert ($out | str contains "written settings.nu") $out
  assert ($user | path join README.md | path exists) "README.md rendered"
  assert ($user | path join completions hello.nu.off | path exists) "the example rendered"
  let again = in-distro $c 'nu-config upgrade'
  assert ($again.stdout | str contains "already up to date with origin/main") $again.stdout
  assert equal (in-distro $c 'nu-config upgrade status | get behind' | get stdout | str trim) "0"
}

def "test upgrade refuses a checkout with commits of its own" [] {
  let c = clones
  push-commit $c "theirs"
  "mine\n" | save ($c.distro | path join LOCAL.txt)
  git $c.distro add LOCAL.txt
  git $c.distro commit -q -m mine
  let ran = in-distro $c 'nu-config upgrade'
  assert equal $ran.exit_code 1
  assert ($ran.stderr | str contains "git pull failed") $ran.stderr
  assert equal (git $c.distro log --format=%s -1) mine "nothing was merged"
}

def "test a checkout without a remote or without git says why" [] {
  let c = clones
  let d = scratch
  cp -r ($ROOT | path join modules) $d
  let plain = with-env { XDG_DATA_HOME: $c.data } { ^$nu.current-exe -n -c $"const NU_LIB_DIRS = [($d | path join modules | to nuon)]; use nu-config; nu-config upgrade check | get error" | complete }
  assert equal ($plain.stdout | str trim) "the distro is not a git checkout"
  git $c.distro branch -q --unset-upstream
  let untracked = in-distro $c 'nu-config upgrade check | get error'
  assert equal ($untracked.stdout | str trim) "the checked-out branch tracks no remote branch"
  let pull = in-distro $c 'nu-config upgrade'
  assert equal $pull.exit_code 1
  assert ($pull.stderr | str contains "cannot update: the checked-out branch tracks no remote branch") $pull.stderr
}

def "test a fetch that fails keeps the last counts and records the error" [] {
  let c = clones
  push-commit $c "one"
  in-distro $c 'nu-config upgrade check' | ignore
  rm -rf $c.remote
  let ran = in-distro $c 'nu-config upgrade check | select behind error | to nuon'
  let s = $ran.stdout | from nuon
  assert equal $s.behind 1
  assert ($s.error | is-not-empty) "the fetch failure is recorded"
}
