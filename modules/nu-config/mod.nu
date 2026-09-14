# nu-config — maintenance commands for this configuration
#
#   nu-config doctor              health check: paths, link, tools, plugins, parse
#   nu-config tools setup         generate init files for installed tools (zoxide, atuin, ...)
#   nu-config plugins add         register the plugins shipped next to `nu`
#   nu-config fetch completion X  vendor a completion module from nu_scripts
#   nu-config fetch theme X       vendor a theme from nu_scripts
#   nu-config startup-time        time cold starts
#   nu-config edit                open the repo in $EDITOR
#
# `help nu-config` lists everything.

# Tool init files: `nu-config tools setup | status | remove | dir`
export use tools.nu *
# Completion caches, for `doctor`.
use nu-complete *

# Developer examples that ship with nu; never worth registering.
const DEV_PLUGINS = [example custom_values stress_internals]

# Root of the configuration repo.
export def root []: nothing -> path {
  $nu.config-path | path dirname | path expand
}

# The directory Nushell reads its configuration from on this platform.
# Nushell honours XDG_CONFIG_HOME on every OS, then falls back to the OS default.
export def platform-config-dir []: nothing -> path {
  if ($env.XDG_CONFIG_HOME? | default "" | is-not-empty) {
    return ($env.XDG_CONFIG_HOME | path join nushell)
  }
  match $nu.os-info.name {
    "macos" => ($nu.home-dir | path join "Library" "Application Support" "nushell")
    "windows" => ($env.APPDATA | path join "nushell")
    _ => ($nu.home-dir | path join ".config" "nushell")
  }
}

# How Nushell reaches this repo: "direct" (the repo is the config dir),
# "linked" (the config dir is a link to it), "other" (something else is live)
# or "missing" (no config dir yet).
export def link-status []: nothing -> record<state: string, config_dir: string, points_to: string> {
  let target = (platform-config-dir)
  let here = (root)
  if not ($target | path exists) {
    return { state: "missing", config_dir: $target, points_to: "" }
  }
  let resolved = ($target | path expand)
  let state = if $resolved == $here {
    if ($target | path expand --no-symlink) == $here { "direct" } else { "linked" }
  } else { "other" }
  { state: $state, config_dir: $target, points_to: $resolved }
}

# Health check for the whole setup.
export def doctor []: nothing -> nothing {
  let here = (root)
  let ok = $"(ansi green)ok(ansi reset)"
  let bad = $"(ansi red)!!(ansi reset)"

  print $"(ansi cyan_bold)Nushell(ansi reset) ((version).version)  ($nu.current-exe)"
  print $"(ansi cyan_bold)Repo(ansi reset)    ($here)"

  let link = (link-status)
  let mark = (match $link.state {
    "direct" | "linked" => $ok
    _ => $bad
  })
  print $"(ansi cyan_bold)Link(ansi reset)    ($mark) ($link.config_dir)  [($link.state)]"
  if $link.state == "other" {
    print $"          (ansi yellow)live config is ($link.points_to) — run `nu install.nu` here to switch(ansi reset)"
  }
  print ""

  print $"(ansi cyan_bold)Files(ansi reset)"
  print $"  config    ($nu.config-path)"
  print $"  history   ($nu.history-path)"
  print $"  plugins   ($nu.plugin-path)"
  print $"  autoload  ($nu.user-autoload-dirs | str join ', ')"
  # Compare resolved paths: on macOS $nu.data-dir comes back through the link
  # resolved while $nu.vendor-autoload-dirs keeps the unresolved spelling.
  let vdir = (tools dir)
  let vmark = if ($nu.vendor-autoload-dirs | any {|d| ($d | path expand) == ($vdir | path expand) }) { $ok } else { $bad }
  print $"  vendor    ($vmark) ($vdir)"
  print ""

  print $"(ansi cyan_bold)Search paths(ansi reset)"
  for d in $NU_LIB_DIRS {
    let m = if ($d | path exists) { $ok } else { $bad }
    print $"  ($m) ($d)"
  }
  print ""

  print $"(ansi cyan_bold)Parse(ansi reset)"
  let parsed = (do -i { nu-check ($here | path join config.nu) } | default false)
  print $"  (if $parsed { $ok } else { $bad }) config.nu and everything it sources"
  print ""

  print $"(ansi cyan_bold)Tools(ansi reset)"
  for t in (tools status) {
    let m = (match $t.state {
      "ok" => $ok
      "not installed" => $"(ansi dark_gray)--(ansi reset)"
      _ => $"(ansi yellow)??(ansi reset)"
    })
    print $"  ($m) ($t.tool | fill --width 9) ($t.state)"
  }
  print ""

  print $"(ansi cyan_bold)Plugins(ansi reset)"
  let pl = (plugins list)
  if ($pl | is-empty) {
    print "  none found next to nu"
  } else {
    for p in $pl {
      let m = if $p.registered { $ok } else { $"(ansi dark_gray)--(ansi reset)" }
      print $"  ($m) ($p.name)"
    }
    if ($pl | where not registered and name not-in $DEV_PLUGINS | is-not-empty) {
      print $"  (ansi dark_gray)register with: nu-config plugins add(ansi reset)"
    }
  }
  print ""

  print $"(ansi cyan_bold)Completion(ansi reset)"
  print $"  smart Tab  ($SMART_TAB)   eval ($env.NU_COMPLETE_EVAL? | default 'safe')   \(conf/settings.nu\)"
  for c in (nu-complete status | skip 1) {
    print $"  ($ok) ($c.what | fill --width 18) ($c.size | fill --width 9) ($c.age | str replace --regex ' \d+ms.*' '' ) old"
  }
  if (nu-complete status | length) == 1 { print $"  (ansi dark_gray)no caches yet — they appear on first use(ansi reset)" }
  print ""

  print $"(ansi cyan_bold)OData(ansi reset)"
  print $"  current ($env.ODATA_SERVICE? | default 'none')   pushdown ($env.ODATA_PUSHDOWN? | default true)   keys at Tab ($env.ODATA_COMPLETE_KEYS? | default false)   \(conf/settings.nu\)"
  # `odata services` is in scope because config.nu sources conf/odata.nu before `use nu-config`.
  for s in (try { odata services } catch { [] }) {
    print $"  ($ok) ($s.name | fill --width 12) V($s.version | fill --width 2) $metadata ($s.metadata)"
  }
  print ""

  let st = if $nu.startup-time >= 0ns { $"($nu.startup-time)" } else { "n/a" }
  print $"(ansi cyan_bold)Startup(ansi reset) ($st)"
}

# Time N cold interactive startups.
export def startup-time [n: int = 5]: nothing -> table<run: int, time: duration> {
  0..<$n | each {|i|
    let out = (^$nu.current-exe -l -c '$nu.startup-time' | complete)
    { run: ($i + 1), time: ($out.stdout | str trim | into duration) }
  }
}

# Files parsed in this session (find a slow import).
export def loaded-files []: nothing -> table {
  view files
  | where filename !~ '^std' and filename !~ '^entry'
  | select filename size
}

# Plugins shipped next to the nu binary, and whether each is registered.
export def "plugins list" []: nothing -> table<name: string, registered: bool, path: string> {
  let registered = (do -i { plugin list | get name } | default [])
  ls ($nu.current-exe | path dirname)
  | where name =~ 'nu_plugin_'
  | get name
  | each {|p|
      let short = ($p | path basename | str replace 'nu_plugin_' '' | str replace --regex '\.exe$' '')
      { name: $short, registered: ($short in $registered), path: $p }
    }
}

# Register every plugin next to the nu binary, except the developer examples.
# Re-run after every Nushell upgrade: plugins are protocol-versioned.
export def "plugins add" []: nothing -> nothing {
  let todo = (plugins list | where name not-in $DEV_PLUGINS)
  if ($todo | is-empty) { print "no plugins found next to nu"; return }
  for p in $todo {
    print $"  plugin add ($p.name)"
    do -i { plugin add $p.path }
  }
  print "done — restart Nushell, or `plugin use <name>` now"
}

const NU_SCRIPTS = "https://raw.githubusercontent.com/nushell/nu_scripts/main"

# Vendor a completion module from nu_scripts into completions/.
#   nu-config fetch completion docker
export def "fetch completion" [tool: string]: nothing -> nothing {
  let url = $"($NU_SCRIPTS)/custom-completions/($tool)/($tool)-completions.nu"
  let dest = (root | path join completions $"($tool)-completions.nu")
  let body = (try { http get $url } catch { error make { msg: $"nothing at ($url)" } })
  $body | save -f $dest
  print $"saved ($dest)"
  print $"add to conf/completions.nu:   use ($tool)-completions.nu *"
}

# Vendor a theme from nu_scripts into themes/, wrapped so it applies itself
# when sourced (nu_scripts themes are modules that only return the colours).
#   nu-config fetch theme tokyo-night   →   THEME = "tokyo-night" in conf/settings.nu
export def "fetch theme" [name: string]: nothing -> nothing {
  let url = $"($NU_SCRIPTS)/themes/nu-themes/($name).nu"
  let dest = (root | path join themes $"($name).nu")
  let body = (try { http get $url } catch { error make { msg: $"nothing at ($url)" } })
  [
    $"# ($name) — from ($url)"
    $"module ($name) {"
    $body
    "}"
    $"use ($name)"
    $"$env.config.color_config = \(($name)\)"
    ""
  ] | str join (char nl) | save -f $dest
  print $"saved ($dest)"
  print $"set in conf/settings.nu:   const THEME = \"($name)\""
}

# Open the repo in $EDITOR.
export def edit []: nothing -> nothing {
  let ed = ($env.EDITOR? | default "vi" | split row " ")
  ^($ed | first) ...($ed | skip 1) (root)
}
