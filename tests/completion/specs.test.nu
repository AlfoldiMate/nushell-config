# The shipped specs (completions/brew.nu, git.nu, cargo.nu) through the real
# path: the extern's `@complete` completer, called by `commandline complete`.
# brew runs against tests/fixtures/brew — a trimmed zsh completion, name
# lists, a Cellar, a Caskroom and Taps — so it needs no Homebrew; git and
# cargo run against a repository and a workspace made in a scratch directory,
# and are skipped where the tool is missing.
use lib.nu *
use std/assert
use nu-complete *
use brew.nu *
use git.nu *
use cargo.nu *

def values-of [line: string]: nothing -> list<string> { $line | commandline complete }
def detailed [line: string]: nothing -> table { $line | commandline complete --detailed }

# ── brew ──────────────────────────────────────────────────────────────────────

def --env brew-fixture [] {
  $env.HOMEBREW_PREFIX = ($ROOT | path join tests fixtures brew)
  $env.HOMEBREW_CACHE = ($ROOT | path join tests fixtures brew cache)
}

def "test brew lists its subcommands with descriptions from the zsh file" [] {
  brew-fixture
  let got = detailed "brew "
  assert equal ($got | get value) [alias install list tap uninstall]
  assert equal ($got | where value == install | get 0.description) "Install a formula or cask"
  # zsh's '\'' is an apostrophe.
  assert equal ($got | where value == alias | get 0.description) "Show an alias's command"
}

def "test brew install offers formulae and casks, narrowed by --cask and --formula" [] {
  brew-fixture
  assert equal (values-of "brew install ri") [ripgrep ripgrep-all]
  assert equal (values-of "brew install gho") [ghostty]
  assert equal (values-of "brew install --cask ") [firefox ghostty]
  assert equal (values-of "brew install --formula ") [bat fd ripgrep ripgrep-all]
}

def "test brew flags are the subcommand flags from the zsh file plus the root ones" [] {
  brew-fixture
  let got = values-of "brew install --"
  assert ([--HEAD --dry-run --cask --formula --help --verbose --debug] | all {|f| $f in $got }) ($got | to nuon)
  assert equal (values-of "brew tap --") [--custom-remote --help --repair --verbose --debug --quiet]
}

def "test brew uninstall and list offer what is installed, with versions" [] {
  brew-fixture
  let got = detailed "brew uninstall "
  assert equal ($got | get value) [bat ripgrep ghostty]
  assert equal ($got | where value == bat | get 0.description) "0.24.0, 0.25.0"
  assert equal (values-of "brew list --cask ") [ghostty]
  assert equal (values-of "brew uninstall --formula ") [bat ripgrep]
}

def "test brew tap offers the tapped repositories" [] {
  brew-fixture
  assert equal (values-of "brew tap ") [homebrew/core someone/tools]
}

def "test brew spec is parsed once and cached in the run cache dir" [] {
  brew-fixture
  values-of "brew " | ignore
  let f = nu-complete cache-dir | path join brew-spec.json
  assert ($f | path exists) $f
  assert ($f | str starts-with $env.XDG_CACHE_HOME) "the cache is not under the run's XDG_CACHE_HOME"
  assert equal (open $f | get subcommands | columns) [alias install list tap uninstall]
}

# ── git ───────────────────────────────────────────────────────────────────────

def --env git-repo [] {
  if (which -a git | where type == external | is-empty) { skip-test "git is not installed" }
  let d = scratch
  cd $d
  ^git init -q -b main
  let c = [-c user.name=test -c user.email=test@example.com]
  ^git ...$c commit -q --allow-empty -m first
  ^git tag v1
  "x" | save changed.txt
  ^git add changed.txt
  ^git ...$c commit -q -m second
  ^git checkout -q -b feature
  ^git ...$c commit -q --allow-empty -m onfeature
  ^git checkout -q main
  "y" | save -f changed.txt
  "z" | save new.txt
}

def "test git checkout offers branches by recency, then tags" [] {
  git-repo
  let got = detailed "git checkout " | where description !~ '^(modified|untracked)'
  assert equal ($got | get value) [feature main v1]
  assert equal ($got | get description) ["branch · onfeature" "branch · second" "tag · first"]
}

def "test git add offers the changed and untracked files" [] {
  git-repo
  assert equal (values-of "git add " | path basename) [changed.txt new.txt]
}

def "test git lists its subcommands and a subcommand flags" [] {
  git-repo
  let subs = values-of "git "
  assert ([checkout commit status rebase] | all {|s| $s in $subs })
  let flags = values-of "git checkout --"
  assert ([--quiet --detach --patch] | all {|f| $f in $flags }) ($flags | to nuon)
}

def "test git -C hands the slot to file completion" [] {
  git-repo
  assert ("file" in (detailed "git -C " | get kind? | compact | uniq))
}

# ── cargo ─────────────────────────────────────────────────────────────────────

def --env cargo-workspace [] {
  if (try { (^cargo --version | complete).exit_code } catch { 1 }) != 0 { skip-test "cargo is not installed" }
  let d = scratch
  mkdir ($d | path join alpha src) ($d | path join beta src)
  "[workspace]\nmembers = [\"alpha\", \"beta\"]\nresolver = \"2\"\n" | save ($d | path join Cargo.toml)
  "[package]\nname = \"alpha\"\nversion = \"0.1.0\"\nedition = \"2021\"\n\n[features]\ndefault = []\nfast = []\nserde = []\n" | save ($d | path join alpha Cargo.toml)
  "[package]\nname = \"beta\"\nversion = \"0.1.0\"\nedition = \"2021\"\n" | save ($d | path join beta Cargo.toml)
  "" | save ($d | path join alpha src lib.rs)
  "" | save ($d | path join beta src lib.rs)
  cd $d
}

def "test cargo lists its subcommands" [] {
  cargo-workspace
  let subs = values-of "cargo "
  assert ([build test run add] | all {|s| $s in $subs }) ($subs | to nuon)
}

def "test cargo -p offers the workspace members and --features the chosen package features" [] {
  cargo-workspace
  assert equal (values-of "cargo build -p " ) [alpha beta]
  assert equal (values-of "cargo build -p alpha --features ") [default fast serde]
}

def "test cargo flags come from --help" [] {
  cargo-workspace
  let flags = values-of "cargo build --"
  assert ([--release --features --package] | all {|f| $f in $flags }) ($flags | to nuon)
}
