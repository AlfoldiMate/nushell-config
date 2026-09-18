# detect.nu — which terminals this distro knows, and which one you are in
#
#   terminal list       every terminal in the registry: installed, running, how to get it
#   terminal current    the one this session is running in, or null
#   terminal install    install the current platform's build, after asking
#
# Two different questions, and the installer asks both. "Is it installed?" is
# what decides whether the theme picker can write a config at all. "Are we
# running in it?" is what decides whether the live OSC preview will be visible:
# painting the terminal you are looking at only works if it is the terminal
# being configured — from Terminal.app or an SSH session the preview is a lie.
#
# Ghostty is the only entry, deliberately. It is a registry rather than three
# `if`s so that adding WezTerm or Kitty later is a record, not a refactor — the
# same shape as the tool registry in modules/nu-config/tools.nu, where
# "installed" is likewise the switch.

use ghostty.nu *

def registry []: nothing -> table {
  [
    {
      name: "ghostty"
      what: "GPU-accelerated, 463 themes, OSC and Kitty graphics — what this distro themes"
      # Ghostty exports these into every shell it starts; TERM_PROGRAM alone
      # is not enough, because a multiplexer inside another terminal keeps it.
      running: {|| ($env.TERM_PROGRAM? | default "") == "ghostty" }
      bin: {|| ghostty-bin }
      config: {|| ghostty config-path }
      # Written by `ghostty set`, so the distro's mark is one included file.
      configured: {|| (ghostty status).included }
      install: {
        macos: { run: [brew install --cask ghostty], needs: "brew", note: "or https://ghostty.org/download" }
        linux: { run: null, needs: null, note: "your distribution's package, or https://ghostty.org/download" }
        windows: { run: null, needs: null, note: "Ghostty has no Windows build yet — https://ghostty.org/download" }
      }
    }
  ]
}

# Every terminal this distro knows about, and what is true of it here.
export def "terminal list" []: nothing -> table<terminal: string, installed: bool, running: bool, configured: bool, path: any, what: string> {
  registry | each {|t|
    let bin = (do $t.bin)
    {
      terminal: $t.name
      installed: ($bin != null)
      running: (do $t.running)
      configured: (if $bin == null { false } else { do $t.configured })
      path: $bin
      what: $t.what
    }
  }
}

# The terminal this session is running in, as a registry row — null when it is
# one this distro does not know. Cheap: an environment variable, no processes.
export def "terminal current" []: nothing -> any {
  terminal list | where running | get -o 0
}

# What the current platform would have to run to get one, and whether it can.
export def "terminal install-plan" [name: string = "ghostty"]: nothing -> record {
  let t = (registry | where name == $name | get -o 0)
  if $t == null { error make { msg: $"no terminal called '($name)' in the registry" } }
  let plan = ($t.install | get -o $nu.os-info.name | default { run: null, needs: null, note: "" })
  {
    terminal: $name
    installed: ((do $t.bin) != null)
    # A run line is only a plan if what it runs is there.
    runnable: ($plan.run != null and ($plan.needs == null or (which $plan.needs | is-not-empty)))
    command: (if $plan.run == null { null } else { $plan.run | str join " " })
    note: $plan.note
  }
}

# Install it, having asked. Never runs anything on a platform where the plan is
# only a URL: printing the link is the honest outcome there.
export def "terminal install" [
  name: string = "ghostty"
  --yes (-y)   # do not ask
]: nothing -> nothing {
  let plan = (terminal install-plan $name)
  if $plan.installed { print $"($name) is already installed"; return }
  if not $plan.runnable {
    print $"($name) has to be installed by hand on ($nu.os-info.name): ($plan.note)"
    return
  }
  if not $yes {
    if ([$"run: ($plan.command)" "no"] | input list $"install ($name)?") != $"run: ($plan.command)" {
      print "left alone"
      return
    }
  }
  let argv = ($plan.command | split row " ")
  ^($argv | first) ...($argv | skip 1)
}
