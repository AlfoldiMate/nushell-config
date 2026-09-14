#!/usr/bin/env nu
# install.nu — make this checkout the live Nushell configuration
#
#   nu install.nu                 link, generate tool files, register plugins, doctor
#   nu install.nu --dry-run       print the plan, change nothing
#   nu install.nu --skip-tools --skip-plugins
#
# Idempotent: safe to re-run after `git pull`, after installing a tool, or
# after upgrading Nushell.
#
# How the link works: Nushell derives every path (autoload dirs, plugin
# registry, history) from its config directory, so pointing that one
# directory at this repo redirects all of them. On Linux the default config
# dir is ~/.config/nushell, so a clone there needs no link at all. On macOS
# (~/Library/Application Support/nushell) and Windows (%APPDATA%\nushell) a
# symlink / junction is created. An existing real directory is renamed, not
# deleted, and its history is copied over.

const ROOT = path self | path dirname
use modules/nu-config

def main [
  --dry-run       # print what would be done
  --skip-tools    # do not generate tool init files
  --skip-plugins  # do not register plugins
] {
  print $"(ansi cyan_bold)Installing Nushell configuration from(ansi reset) ($ROOT)"
  print ""

  link-config-dir --dry-run=$dry_run
  ensure-autoload --dry-run=$dry_run

  # Everything below depends on $nu.data-dir and $nu.plugin-path, which this
  # process computed BEFORE the link existed (and with the symlink resolved).
  # A fresh `nu` sees the new link, so the remaining steps run in a child.
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
    let script = ([$"use ($ROOT | path join modules nu-config)"] ++ $steps | str join "; ")
    ^$nu.current-exe -n -c $script
  }

  if $dry_run {
    print $"(ansi yellow)dry run — nothing was changed(ansi reset)"
  } else {
    print $"(ansi green_bold)Done.(ansi reset) Open a new terminal, then run `nu-config doctor`."
  }
}

def link-config-dir [--dry-run] {
  let target = (nu-config platform-config-dir)
  print $"(ansi cyan_bold)Config dir(ansi reset)  ($target)"

  if ($target | path expand --no-symlink) == $ROOT {
    print "  this repo IS the config dir — nothing to link"
    print ""
    return
  }

  let kind = (entry-kind $target)
  if $kind == "symlink" and ($target | path expand) == $ROOT {
    print "  already linked here"
    print ""
    return
  }

  match $kind {
    "symlink" => {
      let old = ($target | path expand)
      print $"  currently a link to ($old) — replacing it \(that directory is left untouched\)"
      if not $dry_run { remove-link $target }
      if not $dry_run { copy-history-from $old }
    }
    "dir" => {
      let backup = $"($target).backup-(date now | format date '%Y%m%d-%H%M%S')"
      print $"  currently a real directory — renaming it to ($backup)"
      if not $dry_run { mv $target $backup }
      if not $dry_run { copy-history-from $backup }
    }
    "missing" => {
      print "  does not exist yet"
      if not $dry_run { mkdir ($target | path dirname) }
    }
    _ => { error make { msg: $"($target) exists but is not a directory or link; move it aside first" } }
  }

  print $"  linking ($target) → ($ROOT)"
  if not $dry_run { make-link $target }
  print ""
}

# "symlink" | "dir" | "file" | "missing"
def entry-kind [path: path]: nothing -> string {
  if not ($path | path exists) { return "missing" }
  let row = (ls -la ($path | path dirname) | where name == $path | get -o 0)
  if $row == null { return "missing" }
  $row.type
}

def make-link [target: path] {
  if $nu.os-info.name == "windows" {
    ^cmd /c mklink /J $target $ROOT | ignore
  } else {
    ^ln -s $ROOT $target
  }
}

def remove-link [target: path] {
  if $nu.os-info.name == "windows" {
    ^cmd /c rmdir $target
  } else {
    ^rm $target      # removes the link only; `rm -r` would follow it
  }
}

# Carry history over from the previous config dir if this repo has none yet.
def copy-history-from [old: path] {
  for f in [history.txt history.sqlite3] {
    let src = ($old | path join $f)
    let dst = ($ROOT | path join $f)
    if ($src | path exists) and not ($dst | path exists) {
      cp $src $dst
      print $"  copied ($f) from the previous config"
    }
  }
}

def ensure-autoload [--dry-run] {
  let dir = ($ROOT | path join autoload)
  if not ($dir | path exists) {
    print $"(ansi cyan_bold)autoload/(ansi reset)  creating ($dir) for machine-local drop-ins"
    if not $dry_run { mkdir $dir }
    print ""
  }
}
