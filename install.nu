#!/usr/bin/env nu
# install.nu — point Nushell at this distro, and give you a directory of your own
#
#   nu install.nu                 the interactive installer
#   nu install.nu --defaults      every shipped default, no questions
#   nu install.nu --dry-run       print the plan, change nothing
#   nu install.nu --skip-tools --skip-plugins
#
# Idempotent: safe to re-run after `git pull`, after installing a tool, or
# after upgrading Nushell.
#
# What it builds
#
#   <config dir>/config.nu     three lines, pointing here      ← Nushell loads this
#   <config dir>/settings.nu   your overrides — and ONLY your overrides
#   <config dir>/autoload/     your drop-ins
#   <config dir>/completions/  what you fetch later
#
# The config dir is Nushell's own (~/.config/nushell on Linux, ~/Library/
# Application Support/nushell on macOS, %APPDATA%\nushell on Windows), because
# Nushell derives history, the plugin registry and the autoload dirs from it.
# This checkout stays out of it: nothing you own is ever written in here, so
# `git pull` is always clean.
#
# The test that the layering is right: accept every default and your
# settings.nu ends up with no assignments in it at all — `nu-config knobs
# --overridden` comes back empty. Nothing is copied out of defaults.nu "so you
# can see it"; what you never mention keeps its shipped value, including values
# added by a later `git pull`.
#
# Migrating from the older layout, where this checkout WAS the config dir, is
# handled: history, the plugin registry and autoload/ are moved out, and the
# symlink is replaced by a real directory.

const ROOT = path self | path dirname

# A script loads no config, so the module search path has to be declared here
# or nu-config's own imports (`use nu-complete *`) cannot resolve.
const NU_LIB_DIRS = [($ROOT | path join modules)]
use nu-config
# The pickers. They are the same ones the installed shell gets — `theme`,
# `font`, `ghostty set`, `terminal list` — so the installer is a demonstration
# of the thing it installs rather than a second implementation of it.
use terminal *
# The shipped values, so a choice can be compared against them and only the
# differences written down. Sourcing beats restating them: one file owns them.
source ($ROOT | path join defaults.nu)

def main [
  --dry-run       # print what would be done
  --defaults      # no questions; every shipped default
  --skip-tools    # do not generate tool init files
  --skip-plugins  # do not register plugins
] {
  print $"(ansi cyan_bold)Nushell distro(ansi reset)  ($ROOT)"
  print ""

  # A terminal on both ends is what the pickers need. A script is never
  # "interactive" even when you launched it from a shell, so this is the test —
  # and it is also what makes `curl … | sh` fall back to defaults by itself.
  let ask = (not $defaults) and (is-terminal --stdin) and (is-terminal --stdout)
  if (not $ask) and (not $defaults) {
    print $"(ansi yellow)no terminal on stdin/stdout — taking every default(ansi reset)"
    print ""
  }

  let plan = (
    {}
    | merge (screen-where --ask=$ask)
    | merge (screen-modules --ask=$ask)
    | merge (screen-terminal --ask=$ask --dry-run=$dry_run)
    | merge (screen-theme --ask=$ask)
    | merge (screen-font --ask=$ask --dry-run=$dry_run)
  )
  screen-tools
  if $ask and (not (confirm $plan)) {
    print "nothing was changed"
    return
  }

  apply $plan --dry-run=$dry_run --skip-tools=$skip_tools --skip-plugins=$skip_plugins
}

# ── 1. Where ──────────────────────────────────────────────────────────────────

def screen-where [--ask]: nothing -> record {
  print $"(ansi cyan_bold)1. Where(ansi reset)"
  let default = (nu-config platform-config-dir)
  print $"  this checkout   ($ROOT)"
  print $"  your config     ($default)"
  print $"  (ansi dark_gray)Nushell reads config.nu from that directory and derives history, the(ansi reset)"
  print $"  (ansi dark_gray)plugin registry and the autoload dirs from it, so it is not a choice(ansi reset)"
  print $"  (ansi dark_gray)unless you also set XDG_CONFIG_HOME.(ansi reset)"

  let user = if not $ask { $default } else {
    # Short labels: the path is printed above, and an option long enough to
    # wrap makes the menu unusable (and unscriptable — it stopped submitting).
    match (["use the default" "somewhere else"] | input list "your configuration directory") {
      "somewhere else" => {
        # Emptiness is checked BEFORE expanding, because `"" | path expand` is
        # the current directory — which, running this script, is this checkout.
        let typed = (input "path: " | str trim)
        if ($typed | is-empty) { $default } else { $typed | path expand --no-symlink }
      }
      _ => $default
    }
  }
  # Two checks, because the obvious one is not enough: `path expand` keeps a
  # trailing separator, so a plain `==` against $ROOT silently passed a path
  # that WAS this checkout and wrote a config.nu into the repository.
  # `path split | path join` normalises; distro.nu catches any checkout.
  let same = (($user | path expand --no-symlink | path split | path join) == ($ROOT | path expand --no-symlink | path split | path join))
  if $same or (($user | path join distro.nu) | path exists) {
    error make { msg: $"($user) is a checkout of the distro. Your configuration has to live somewhere else — that separation is the whole point, and it is what keeps `git pull` clean and your history out of version control." }
  }
  print ""
  { user: $user }
}

# ── 2. Modules ────────────────────────────────────────────────────────────────

def screen-modules [--ask]: nothing -> record {
  print $"(ansi cyan_bold)2. Modules(ansi reset)"
  let all = (nu-config module list)
  for m in $all {
    let dep = (if $m.deps == "—" { "" } else { $"  ($m.deps)" })
    let cost = (if $m.cost == 0ns { "" } else { $"($m.cost)" })
    print $"  ($m.module | fill --width 12) ($cost | fill --width 7) ($m.description)($dep)"
  }
  print $"  (ansi dark_gray)cost is what the module adds to startup when it loads; a lazy one pays it(ansi reset)"
  print $"  (ansi dark_gray)on the first line that mentions it, not at every shell start(ansi reset)"

  if not $ask { print ""; return { modules: null } }

  let chosen = if (yes-no "choose which modules to enable?" --default-no) {
    # nu-config is not offered: it is how you repair everything else.
    let optional = ($all | where module != "nu-config")
    let picked = (
      $optional
      | input list --multi --display {|m| $"($m.module | fill --width 12) ($m.cost)  ($m.description)" } "space to toggle, enter to accept"
    )
    (["nu-config"] ++ ($picked | get module))
  } else { $MODULES }

  # Lazy is the shipped answer for everything that has a trigger word, and the
  # question "should this cost you 97 ms at every start" has one sensible reply.
  let lazy = ($MODULES_LAZY | where {|m| $m in $chosen })
  print ""
  { modules: (if ($chosen | sort) == ($MODULES | sort) { null } else { { enabled: $chosen, lazy: $lazy } }) }
}

# ── 3. Terminal ───────────────────────────────────────────────────────────────

def screen-terminal [--ask, --dry-run]: nothing -> record {
  print $"(ansi cyan_bold)3. Terminal(ansi reset)"
  let t = (terminal list | get 0)
  let here = (terminal current)
  print $"  ($t.terminal | fill --width 10) (if $t.installed { $"installed at ($t.path)" } else { "not installed" })"
  if $here != null {
    print $"  (ansi green)you are running in it(ansi reset) — the theme preview below will be real"
  } else {
    print $"  (ansi yellow)this session is not Ghostty(ansi reset) — a theme can still be chosen and written,"
    print $"  (ansi yellow)but the live preview would paint a terminal that is not the one being(ansi reset)"
    print $"  (ansi yellow)configured, so it is a lie and it is skipped(ansi reset)"
  }
  if not $t.installed {
    let plan = (terminal install-plan)
    print $"  install:  ($plan.command | default $plan.note)"
    if $ask and (not $dry_run) and $plan.runnable and (yes-no "install Ghostty now?" --default-no) {
      terminal install --yes
    }
  }
  # Re-read: the install above may just have changed the answer.
  let installed = (terminal list | get 0.installed)
  { ghostty: $installed, in_ghostty: ($here != null), shell: (screen-shell --ask=$ask --installed=$installed) }
}

# What a new Ghostty window starts. Left alone, Ghostty runs SHELL, then the
# passwd shell — zsh on a stock Mac — so a Nushell distro that has configured
# the terminal and then leaves it opening zsh has not installed anything. This
# is why it is the one question here whose default is yes, and why `--defaults`
# and a `curl … | sh` run do it unasked: it is the distro's own file in
# Ghostty's config (`ghostty shell --reset` takes it out again), not an override
# in settings.nu, so the "no overrides" test the other screens live by is not
# touched. Returns the nu to write, or null when there is nothing to do.
def screen-shell [--ask, --installed]: nothing -> any {
  if not $installed { print ""; return null }
  let now = ((ghostty status).shell | default "your login shell")
  let want = (ghostty nu-path)
  print $"  shell      a new window starts ($now)"
  # `nu` by whichever path: theirs already does the job, so nothing is written.
  if ($now | path basename | str replace -r '\.exe$' '') == "nu" { print ""; return null }
  let yes = if $ask { yes-no $"start Nushell instead? \(($want)\)" } else { true }
  print ""
  if $yes { $want } else { null }
}

# ── 4. Theme ──────────────────────────────────────────────────────────────────
#
# One theme for everything: a palette is written to Ghostty as a theme and an
# icon, and rendered for the shell — tables, `ls`, bat and the prompt — by
# `theme use`, which is what `apply` runs for the choice made here. Nothing
# chosen means the ANSI tier: the shell follows whatever sixteen colours the
# terminal paints.

def screen-theme [--ask]: nothing -> record {
  print $"(ansi cyan_bold)4. Theme(ansi reset)"
  print $"  (ansi dark_gray)a hundred palettes \(NvChad's and Catppuccin\), rendered for the terminal, its icon, Nushell, ls, bat and the prompt; `theme` changes it later, `theme --ghostty` picks among Ghostty's own 463(ansi reset)"
  if not $ask { print ""; return { ghostty_theme: null } }

  mut ghostty_theme = null
  if (terminal list | get 0.installed) {
    # Default no, like every question here but the shell: pressing Enter
    # through the whole installer has to end with nothing written.
    if (yes-no "pick a theme?" --default-no) {
      $ghostty_theme = (pick-ghostty-theme)
    }
  } else {
    print $"  (ansi dark_gray)no Ghostty: the shell uses the terminal's sixteen colours by name(ansi reset)"
  }
  print ""
  { ghostty_theme: $ghostty_theme }
}

# The theme picker, but choosing only: nothing is written here, because the
# whole plan is confirmed before anything is. `theme preview` paints the live
# terminal and `theme reset` hands it back, so the preview costs nothing either.
# The list is the palettes — NvChad's and the hand-made ones — the same list
# `theme` shows; Ghostty's own 463 are a `theme --ghostty` away afterwards.
def pick-ghostty-theme []: nothing -> any {
  let rows = (theme list --swatches | select theme colours)
  mut chosen = null
  mut picking = true
  while $picking {
    let pick = ($rows | input list --fuzzy --display {|r| $"($r.theme) ($r.colours)" } "Ghostty theme")
    if $pick == null { $picking = false; continue }
    theme preview $pick.theme
    match ([$"keep ($pick.theme)" "pick another" "leave it as it was"] | input list $"($pick.theme) — this is it") {
      $a if ($a | default "" | str starts-with "keep") => { $chosen = $pick.theme; $picking = false }
      "pick another" => { theme reset }
      _ => { theme reset; $picking = false }
    }
  }
  # The paint is left on the screen when a theme was kept; the write happens in
  # `apply`, so a cancelled confirmation still leaves Ghostty's config alone.
  if $chosen == null { theme reset }
  $chosen
}

# ── 5. Font ───────────────────────────────────────────────────────────────────

def screen-font [--ask, --dry-run]: nothing -> record {
  print $"(ansi cyan_bold)5. Font(ansi reset)"
  if not ((terminal list | get 0.installed)) {
    print "  Ghostty is not installed, so there is nothing to set a font on"
    print ""
    return { font: null }
  }
  let rows = (font list)
  # What Ghostty is using, whoever configured it — not only what we wrote.
  let now = (ghostty live font-family)
  print $"  current   ($now | default "Ghostty's own built-in JetBrains Mono")"
  print $"  installed ((($rows | where installed | get font) | str join ', ') | default 'none of the fifteen')"
  if (not $ask) or $dry_run {
    if $dry_run { print $"  (ansi dark_gray)a font has to be downloaded to be seen, so the picker is skipped on a dry run(ansi reset)" }
    print ""
    return { font: null }
  }
  if not (yes-no "pick a Nerd Font?" --default-no) { print ""; return { font: null } }

  mut chosen = null
  mut picking = true
  while $picking {
    let pick = (
      font list
      | input list --fuzzy --display {|r|
          let mark = (if $r.installed { "✓ " } else { "  " })
          $"($mark)($r.font | fill --width 16) ($r.what)"
        } "Nerd Font"
    )
    if $pick == null { $picking = false; continue }
    if not $pick.installed { font install $pick.font }
    let row = (font list | where font == $pick.font | get 0)
    if not $row.installed { continue }
    match ([$"keep ($row.family)" "see it in a new window" "pick another"] | input list $row.family) {
      $a if ($a | default "" | str starts-with "keep") => { $chosen = $row.family; $picking = false }
      "see it in a new window" => { font preview $pick.font }
      "pick another" => { }
      _ => { $picking = false }
    }
  }
  print ""
  { font: $chosen }
}

# ── 6. Tools ──────────────────────────────────────────────────────────────────
#
# Reporting only. Nothing here is installed by this script: these are other
# people's package managers, and a tool that appears later is picked up by
# re-running `nu-config tools setup`, which is the whole point of installation
# being the switch.

def screen-tools []: nothing -> nothing {
  print $"(ansi cyan_bold)6. Tools(ansi reset)"
  for t in (nu-config tools status) {
    let mark = (if $t.installed { $"(ansi green)ok(ansi reset)" } else { $"(ansi dark_gray)--(ansi reset)" })
    print $"  ($mark) ($t.tool | fill --width 9) ($t.what)"
  }
  let missing = (nu-config tools status | where not installed | get tool)
  if ($missing | is-not-empty) {
    print $"  (ansi dark_gray)not installed: ($missing | str join ', ') — install them and re-run `nu-config tools setup`(ansi reset)"
  }
  # Starship and vivid are the theme's (conf/prompt.nu, `theme use`) rather
  # than generated init files, so they are not in the registry and are
  # mentioned here.
  if (which starship | is-empty) {
    print $"  (ansi dark_gray)-- starship   prompt; without it Nushell's own prompt is used(ansi reset)"
  }
  if (which vivid | is-empty) {
    print $"  (ansi dark_gray)-- vivid      `ls` colours from the theme; without it Nushell's own apply(ansi reset)"
  }
  print ""
}

# ── 7. Confirm ────────────────────────────────────────────────────────────────

def confirm [plan: record]: nothing -> bool {
  print $"(ansi cyan_bold)7. The plan(ansi reset)"
  for line in (plan-lines $plan) { print $"  ($line)" }
  print ""
  yes-no "apply this?"
}

def plan-lines [plan: record]: nothing -> list<string> {
  let settings = (settings-block $plan)
  ([
    $"write ($plan.user | path join config.nu), pointing at ($ROOT)"
    (if ($settings | is-empty) {
      "settings.nu: no overrides — every value stays the distro's"
    } else {
      $"settings.nu: ($settings | length) override\(s\)"
    })
  ]
  ++ ($settings | each {|l| $"  ($l)" })
  ++ [
    (if ($plan.shell? | default null) != null { $"Ghostty command = ($plan.shell) — a new window starts Nushell" })
    (if ($plan.ghostty_theme? | default null) != null { $"theme ($plan.ghostty_theme) — Ghostty, its icon, and the shell's colours" })
    (if ($plan.font? | default null) != null { $"Ghostty font-family = ($plan.font)" })
    "render the theme, generate tool init files, register plugins"
  ]) | compact
}

# The lines that go into settings.nu, and nothing else. A choice equal to the
# shipped value produces no line at all — that is what makes an untouched knob
# keep tracking the distro across a `git pull`.
def settings-block [plan: record]: nothing -> list<string> {
  ([
    (if ($plan.modules? | default null) != null {
      $"const MODULES = [($plan.modules.enabled | str join ' ')]"
    })
    (if ($plan.modules? | default null) != null {
      $"const MODULES_LAZY = [($plan.modules.lazy | str join ' ')]"
    })
  ] | compact)
}

# ── Applying ──────────────────────────────────────────────────────────────────

def apply [plan: record, --dry-run, --skip-tools, --skip-plugins]: nothing -> nothing {
  let user = $plan.user

  let migrated = (unlink-old-layout $user --dry-run=$dry_run)
  make-user-dir $user (settings-block $plan) --dry-run=$dry_run --fresh=$migrated

  # The theme is not set here: `theme use`, in the child below, writes it
  # together with the icon and the rendered shell colours.
  if ($plan.shell? | default null) != null or ($plan.font? | default null) != null {
    print $"(ansi cyan_bold)Ghostty(ansi reset)"
    let settings = (
      {}
      | merge (if ($plan.shell? | default null) != null { { command: $plan.shell } } else { {} })
      | merge (if ($plan.font? | default null) != null { { font-family: $plan.font } } else { {} })
    )
    for s in ($settings | transpose k v) { print $"  ($s.k) = ($s.v)" }
    if not $dry_run { ghostty set $settings }
    print ""
  }

  # Everything below depends on $nu.data-dir and $nu.plugin-path, which this
  # process computed BEFORE the user dir existed. A fresh `nu` sees it, so the
  # remaining steps run in a child that loads the new config for real.
  #
  # The theme is first: `theme use` writes Ghostty's theme and icon, paints
  # this window, and renders tables, ls, bat and the prompt from it. No theme
  # chosen re-renders whatever was chosen before, or the ANSI tier on a first
  # install — never a reset.
  let theme_name = (if ($plan.ghostty_theme? | default null) != null { $plan.ghostty_theme | to nuon } else { "" })
  let steps = ([
    (if $dry_run {
      'print $"(ansi cyan_bold)Theme(ansi reset)"; use terminal *; theme resolve ' + (if $theme_name == "" { "(theme current | default {} | get -o name)" } else { $theme_name }) + ' | select name tier bat | print; print ""'
    } else {
      'print $"(ansi cyan_bold)Theme(ansi reset)"; use terminal *; ' + (if $theme_name == "" { "theme sync" } else { "theme use " + $theme_name }) + '; print ""'
    })
    (if $skip_tools { null } else if $dry_run {
      'print $"(ansi cyan_bold)Tool init files(ansi reset)  → (nu-config tools dir)"; nu-config tools status | select tool installed state | print; print ""'
    } else {
      'print $"(ansi cyan_bold)Tool init files(ansi reset)  → (nu-config tools dir)"; nu-config tools setup; print ""'
    })
    (if $skip_plugins { null } else if $dry_run {
      'print $"(ansi cyan_bold)Plugins(ansi reset)"; nu-config plugins list | select name registered | print; print ""'
    } else {
      'print $"(ansi cyan_bold)Plugins(ansi reset)"; nu-config plugins add; print ""'
    })
  ] | compact)
  if ($steps | is-not-empty) {
    if $dry_run {
      # -n: report against this checkout without loading anything. NU_LIB_DIRS
      # has to be handed over, because a config-less nu has no search path.
      let script = ([$"use nu-config"] ++ $steps | str join "; ")
      with-env { NU_LIB_DIRS: ($ROOT | path join modules) } {
        ^$nu.current-exe -n -c $script
      }
    } else {
      # -l: load the config that was just written, so $nu.data-dir and
      # $nu.plugin-path are the new ones rather than the ones this process
      # computed before the user directory existed.
      ^$nu.current-exe -l -c ($steps | str join "; ")
    }
  }

  if $dry_run {
    print $"(ansi yellow)dry run — nothing was changed(ansi reset)"
  } else {
    print $"(ansi green_bold)Done.(ansi reset) Open a new terminal, then run `nu-config doctor`."
  }
}

# Does this config.nu source THIS checkout? The path appears in it as a Nushell
# string literal, so on Windows it is backslash-escaped and a plain `str
# contains` of the raw path misses it.
def points-here [text: string, root: path]: nothing -> bool {
  ($text | str contains $root) or ($text | str contains ($root | to nuon))
}

# ── Asking ────────────────────────────────────────────────────────────────────

# `input list` rather than a typed y/n: it needs one keystroke, it cannot be
# mistyped, and Esc means no without a special case.
def yes-no [question: string, --default-no]: nothing -> bool {
  let options = if $default_no { ["no" "yes"] } else { ["yes" "no"] }
  ($options | input list $question) == "yes"
}

# ── The user directory ────────────────────────────────────────────────────────

# The previous layout symlinked the config dir at this checkout. Replace that
# link with a real directory and carry the state that lived in here out to it.
# Returns true when the old layout was found, so the caller knows the user
# directory is starting empty.
def unlink-old-layout [user: path, --dry-run]: nothing -> bool {
  if not ($user | path exists) { return false }
  # `path type` reports the link itself; `path expand` resolves it.
  if ($user | path type) != "symlink" or ($user | path expand) != $ROOT { return false }

  print $"(ansi cyan_bold)Previous layout(ansi reset)"
  print $"  ($user) is a link to this checkout — replacing it with a directory of your own"
  if not $dry_run {
    if $nu.os-info.name == "windows" { ^cmd /c rmdir $user } else { ^rm $user }
    mkdir $user
  }
  # State Nushell wrote into the checkout through that link.
  for f in [history.txt history.sqlite3 history.sqlite3-wal history.sqlite3-shm plugin.msgpackz] {
    let src = ($ROOT | path join $f)
    if ($src | path exists) {
      print $"  moving ($f) out of the checkout"
      if not $dry_run { mv $src ($user | path join $f) }
    }
  }
  for d in [autoload vendor .state plugins] {
    let src = ($ROOT | path join $d)
    # A pre-split checkout ships a plugins/.gitkeep; only move the directory
    # when it holds something other than that.
    let has = (($src | path exists) and ((try { ls -a $src | where name !~ '\.gitkeep$' } catch { [] }) | is-not-empty))
    if $has {
      print $"  moving ($d)/ out of the checkout"
      if not $dry_run { mv $src ($user | path join $d) }
    }
  }
  print ""
  true
}

def make-user-dir [user: path, overrides: list<string>, --dry-run, --fresh] {
  print $"(ansi cyan_bold)Your configuration(ansi reset)  ($user)"

  let cfg = ($user | path join config.nu)
  # After a migration the directory is brand new; on a dry run it has not been
  # emptied yet, so anything still in it belongs to the layout being replaced.
  let existing = if $fresh { null } else if ($cfg | path exists) { open --raw $cfg } else { null }

  # Both spellings: the path as written on Unix, and the backslash-escaped
  # literal on Windows. Checking only one makes a re-run rewrite a config.nu
  # that was already correct.
  if $existing != null and (points-here $existing $ROOT) {
    print "  config.nu already points here"
  } else {
    if $existing != null {
      let backup = $"($cfg).backup-(date now | format date '%Y%m%d-%H%M%S')"
      print $"  config.nu exists and points somewhere else — keeping it as ($backup | path basename)"
      if not $dry_run { cp $cfg $backup }
    }
    print $"  writing config.nu → ($ROOT)"
    if not $dry_run {
      mkdir $user
      open --raw ($ROOT | path join templates config.nu)
      # `to nuon`, not the bare path: a DOUBLE-quoted Nushell string processes
      # escapes, so a Windows checkout at D:\a\nushell-config turned \a into
      # BEL and \n into a newline and the sourced path did not exist. CI found
      # it on the first Windows run. `to nuon` emits a valid literal, quotes
      # included, and handles an apostrophe in the path too.
      | str replace --all "@DISTRO@" ($ROOT | to nuon)
      | save -f $cfg
    }
  }

  write-settings ($user | path join settings.nu) $overrides --dry-run=$dry_run --fresh=$fresh

  for d in [autoload completions themes modules plugins] {
    let p = ($user | path join $d)
    if not ($p | path exists) {
      print $"  creating ($d)/"
      if not $dry_run { mkdir $p }
    }
  }

  # Explain the drop-in layer where someone will actually find it.
  let ar = ($user | path join autoload README.md)
  if not ($ar | path exists) {
    if not $dry_run { cp ($ROOT | path join templates autoload-README.md) $ar }
  }
  print ""
}

# settings.nu is the template's header — which is guidance, all of it commented
# — plus the chosen overrides and nothing else. An existing one is never
# rewritten: it is yours, and the overrides are appended under a dated mark so
# it is obvious what put them there.
def write-settings [file: path, overrides: list<string>, --dry-run, --fresh] {
  let exists = (not $fresh) and ($file | path exists)
  if $exists and ($overrides | is-empty) {
    print "  settings.nu is yours — left alone"
    return
  }
  let head = if $exists { (open --raw $file | str trim --right --char (char nl)) } else {
    (open --raw ($ROOT | path join templates settings.nu) | str trim --right --char (char nl))
  }
  let body = if ($overrides | is-empty) { [] } else {
    ["" $"# chosen with `nu install.nu` on (date now | format date '%Y-%m-%d')"] ++ $overrides
  }
  if ($overrides | is-empty) {
    print "  writing settings.nu — no overrides, every value stays the distro's"
  } else {
    print $"  writing settings.nu with ($overrides | length) override\(s\):"
    for o in $overrides { print $"    ($o)" }
  }
  if not $dry_run { ([$head] ++ $body ++ [""]) | str join (char nl) | save -f $file }
}
