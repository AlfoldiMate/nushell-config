#!/usr/bin/env nu
# install.nu — point Nushell at this distro, and give you a directory of your own
#
#   nu install.nu                 set up, generate tool files, register plugins
#   nu install.nu --dry-run       print the plan, change nothing
#   nu install.nu --skip-tools --skip-plugins
#
# Idempotent: safe to re-run after `git pull`, after installing a tool, or
# after upgrading Nushell.
#
# What it builds
#
#   <config dir>/config.nu     three lines, pointing here      ← Nushell loads this
#   <config dir>/settings.nu   your overrides, empty to start
#   <config dir>/autoload/     your drop-ins
#   <config dir>/completions/  what you fetch later
#
# The config dir is Nushell's own (~/.config/nushell on Linux, ~/Library/
# Application Support/nushell on macOS, %APPDATA%\nushell on Windows), because
# Nushell derives history, the plugin registry and the autoload dirs from it.
# This checkout stays out of it: nothing you own is ever written in here, so
# `git pull` is always clean.
#
# Migrating from the older layout, where this checkout WAS the config dir, is
# handled: history, the plugin registry and autoload/ are moved out, and the
# symlink is replaced by a real directory.

const ROOT = path self | path dirname

# A script loads no config, so the module search path has to be declared here
# or nu-config's own imports (`use nu-complete *`) cannot resolve.
const NU_LIB_DIRS = [($ROOT | path join modules)]
use nu-config

def main [
  --dry-run       # print what would be done
  --skip-tools    # do not generate tool init files
  --skip-plugins  # do not register plugins
] {
  print $"(ansi cyan_bold)Nushell distro(ansi reset)  ($ROOT)"
  print ""

  let user = (nu-config platform-config-dir)
  if ($user | path expand --no-symlink) == $ROOT {
    error make { msg: $"This checkout is at ($user), which is Nushell's own config directory on this platform. Move it somewhere else — ~/.local/share/nushell-distro is a good home — and run install.nu again from there." }
  }

  let migrated = (unlink-old-layout $user --dry-run=$dry_run)
  make-user-dir $user --dry-run=$dry_run --fresh=$migrated

  # Everything below depends on $nu.data-dir and $nu.plugin-path, which this
  # process computed BEFORE the user dir existed. A fresh `nu` sees it, so the
  # remaining steps run in a child that loads the new config for real.
  let steps = ([
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
    # `plugins/` ships a .gitkeep; only move it when it holds something else.
    let has = (($src | path exists) and ((try { ls -a $src | where name !~ '\.gitkeep$' } catch { [] }) | is-not-empty))
    if $has {
      print $"  moving ($d)/ out of the checkout"
      if not $dry_run { mv $src ($user | path join $d) }
    }
  }
  print ""
  true
}

def make-user-dir [user: path, --dry-run, --fresh] {
  print $"(ansi cyan_bold)Your configuration(ansi reset)  ($user)"

  let cfg = ($user | path join config.nu)
  # After a migration the directory is brand new; on a dry run it has not been
  # emptied yet, so anything still in it belongs to the layout being replaced.
  let existing = if $fresh { null } else if ($cfg | path exists) { open --raw $cfg } else { null }

  if $existing != null and ($existing | str contains $ROOT) {
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
      | str replace --all "@DISTRO@" $ROOT
      | save -f $cfg
    }
  }

  let settings = ($user | path join settings.nu)
  if (not $fresh) and ($settings | path exists) {
    print "  settings.nu is yours — left alone"
  } else {
    print "  writing settings.nu (every knob commented out)"
    if not $dry_run { cp ($ROOT | path join templates settings.nu) $settings }
  }

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
