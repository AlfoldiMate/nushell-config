# nu-config — maintenance commands for this configuration
#
#   nu-config doctor              health check: roots, tools, plugins, parse
#   nu-config knobs               every knob, its shipped default, and your value
#   nu-config tools setup         generate init files for installed tools (zoxide, atuin, ...)
#   nu-config plugins add         register the plugins shipped next to `nu`
#   nu-config fetch completion X  vendor a completion module into YOUR directory
#   nu-config startup-time        time cold starts
#   nu-config upgrade             pull the distro; `upgrade check | status` around it
#   nu-config edit                open the distro in $EDITOR
#   nu-config edit user           open your own settings.nu
#
# `help nu-config` lists everything.

# Tool init files: `nu-config tools setup | status | remove | dir`
export use tools.nu *
# Is the checkout behind its remote: `nu-config upgrade | check | status`
export use upstream.nu *
# Completion caches, for `doctor`.
use nu-complete *

# Developer examples that ship with nu; never worth registering.
const DEV_PLUGINS = [example custom_values stress_internals]

# `path self` only runs at parse time, so the root is computed here rather
# than inside a command. This file is modules/nu-config/mod.nu, two levels down.
const MODULE_DIR = path self | path dirname

# Where the distro checkout lives — the directory holding distro.nu.
export def "distro-root" []: nothing -> path {
  $MODULE_DIR | path dirname | path dirname | path expand
}

# Where YOUR configuration lives: the directory holding the config.nu Nushell
# loaded. History, the plugin registry and the autoload dirs all hang off it.
export def "user-root" []: nothing -> path {
  $nu.config-path | path dirname | path expand
}

# True while the distro checkout is also serving as the config directory,
# which `nu install.nu` exists to undo.
export def "in-place?" []: nothing -> bool {
  (distro-root) == (user-root)
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

# How this distro is installed.
#   "split"     a user directory of its own sources this distro — the target
#   "in-place"  the checkout is still the config directory — run `nu install.nu`
#   "other"     the live config is some other distro or a hand-written one
export def install-status []: nothing -> record<state: string, user: string, distro: string> {
  let u = (user-root)
  let d = (distro-root)
  let cfg = ($u | path join config.nu)
  # Two spellings of the same path: as written, and as the backslash-escaped
  # Nushell string literal that a Windows checkout produces. `str contains $d`
  # alone reported "other" for a perfectly good split install on Windows.
  let text = (if ($cfg | path exists) { open --raw $cfg } else { "" })
  let points_here = ($text | str contains $d) or ($text | str contains ($d | to nuon))
  let state = if $u == $d {
    "in-place"
  } else if $points_here {
    "split"
  } else {
    "other"
  }
  { state: $state, user: $u, distro: $d }
}

# Health check for the whole setup.
export def doctor []: nothing -> nothing {
  let ok = $"(ansi green)ok(ansi reset)"
  let bad = $"(ansi red)!!(ansi reset)"
  let inst = (install-status)

  print $"(ansi cyan_bold)Nushell(ansi reset) ((version).version)  ($nu.current-exe)"
  let up = (upgrade status)
  let behind = (if $up.error == null and $up.behind > 0 { $"  (ansi yellow)($up.behind) behind ($up.upstream) — nu-config upgrade(ansi reset)" } else { "" })
  print $"(ansi cyan_bold)Distro(ansi reset)  ($inst.distro)($behind)"
  print $"(ansi cyan_bold)Yours(ansi reset)   ($inst.user)"
  let mark = (match $inst.state { "split" => $ok, _ => $"(ansi yellow)??(ansi reset)" })
  print $"(ansi cyan_bold)Layout(ansi reset)  ($mark) ($inst.state)"
  if $inst.state == "in-place" {
    print $"          (ansi yellow)the checkout is doubling as the config dir — `nu install.nu` splits them(ansi reset)"
  }
  print ""

  print $"(ansi cyan_bold)Files(ansi reset)"
  print $"  config    ($nu.config-path)"
  print $"  settings  ((user-root) | path join settings.nu)"
  print $"  history   ($nu.history-path)"
  print $"  plugins   ($nu.plugin-path)"
  print $"  autoload  ($nu.user-autoload-dirs | str join ', ')"
  # Compare resolved paths: a symlinked config dir comes back resolved in
  # $nu.data-dir while $nu.vendor-autoload-dirs keeps the unresolved spelling.
  let vdir = (tools dir)
  let vmark = if ($nu.vendor-autoload-dirs | any {|d| ($d | path expand) == ($vdir | path expand) }) { $ok } else { $bad }
  print $"  vendor    ($vmark) ($vdir)"
  print ""

  print $"(ansi cyan_bold)Search paths(ansi reset)  \(yours first\)"
  # $env, not the const: this module is also imported by install.nu, which
  # runs as a script and so has none of the config's parse-time constants.
  for d in ($env.NU_LIB_DIRS? | default []) {
    let m = if ($d | path exists) { $ok } else { $"(ansi dark_gray)--(ansi reset)" }
    print $"  ($m) ($d)"
  }
  print ""

  print $"(ansi cyan_bold)Parse(ansi reset)"
  let parsed = (do -i { nu-check ((distro-root) | path join distro.nu) } | default false)
  print $"  (if $parsed { $ok } else { $bad }) distro.nu and everything it sources"
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
  print $"  smart Tab  ($env.NU_SMART_TAB? | default '?')   eval ($env.NU_COMPLETE_EVAL? | default 'safe')"
  for c in (nu-complete status | skip 1) {
    print $"  ($ok) ($c.what | fill --width 18) ($c.size | fill --width 9) ($c.age | str replace --regex ' \d+ms.*' '' ) old"
  }
  if (nu-complete status | length) == 1 { print $"  (ansi dark_gray)no caches yet — they appear on first use(ansi reset)" }
  print ""

  print $"(ansi cyan_bold)Modules(ansi reset)"
  for m in (mod-list) {
    let mark = (if not $m.enabled { $"(ansi dark_gray)--(ansi reset)" } else if $m.loaded { $ok } else { $"(ansi cyan)zz(ansi reset)" })
    let how = (if not $m.enabled { "disabled" } else if $m.lazy { (if $m.loaded { "lazy, loaded" } else { "lazy, not yet loaded" }) } else { "eager" })
    let cost = (if $m.cost == 0ns { "" } else { $m.cost | into string })
    print $"  ($mark) ($m.module | fill --width 12) ($how | fill --width 22) ($cost | fill --width 7) ($m.deps)"
  }
  let broken = (mod-list | where enabled and deps =~ 'missing')
  if ($broken | is-not-empty) {
    print $"  (ansi yellow)($broken | get module | str join ', '): a required tool is missing — `nu-config module check <name>`(ansi reset)"
  }
  print ""

  let st = if $nu.startup-time >= 0ns { $"($nu.startup-time)" } else { "n/a" }
  print $"(ansi cyan_bold)Startup(ansi reset) ($st)"
}

# Every knob you can set, and whether your settings.nu overrides it.
#
# Two sources, neither of them a second list to keep in sync: the assignments
# in defaults.nu, and the `knobs` record each module declares in its meta.nuon.
# A knob added by a `git pull` shows up here with nothing else changed.
export def knobs [
  --overridden (-o)   # only the ones you have changed
]: nothing -> table<knob: string, kind: string, owner: string, yours: bool, about: string> {
  let mine = ((user-root) | path join settings.nu)
  let mine_src = if ($mine | path exists) { open --raw $mine } else { "" }
  # A knob counts as overridden only when the line mentioning it is live.
  let mine_live = ($mine_src | lines | where {|l| not ($l | str trim | str starts-with "#") } | str join (char nl))

  let from_defaults = (
    open --raw ((distro-root) | path join defaults.nu)
    | lines
    | each {|l|
        let c = ($l | parse --regex '^const (?<name>[A-Z_][A-Z0-9_]*)\s*=' | get -o 0.name)
        let e = ($l | parse --regex '^\$env\.(?<name>[A-Za-z_][\w.]*)\s*=' | get -o 0.name)
        # `else` must stay on the closing brace's line: on a new line it
        # parses as an external command and fails at runtime.
        if $c != null { { knob: $c, kind: "const", owner: "distro", about: "" } } else if $e != null { { knob: $e, kind: "env", owner: "distro", about: "" } } else { null }
      }
    | compact
  )

  let from_modules = (
    module-dirs | each {|m|
      let meta = (module-meta $m.path)
      ($meta.knobs? | default {}) | transpose knob spec | each {|k|
        { knob: $k.knob, kind: "env", owner: $m.name, about: ($k.spec.about? | default "") }
      }
    } | flatten
  )

  $from_defaults ++ $from_modules
  | insert yours {|r| $mine_live =~ $'\b($r.knob)\b' }
  | if $overridden { where yours } else { $in }
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
#
# `--registry --plugin-config` reads the registry FILE rather than the engine:
# a plain `plugin list` reports what this process loaded, which is nothing
# under `nu -n` — the installer's dry run runs there and used to report every
# plugin as unregistered. The flag needs the path spelled out, because a
# config-less nu knows $nu.plugin-path but refuses to default to it.
export def "plugins list" []: nothing -> table<name: string, registered: bool, path: string> {
  let registered = (do -i { plugin list --registry --plugin-config $nu.plugin-path | get name } | default [])
  ls ($nu.current-exe | path dirname)
  | where name =~ 'nu_plugin_'
  | get name
  | each {|p|
      let short = ($p | path basename | str replace 'nu_plugin_' '' | str replace --regex '\.exe$' '')
      { name: $short, registered: ($short in $registered), path: $p }
    }
}

# Register every plugin next to the nu binary, except the developer examples.
#
# Nushell has no plugin MANAGER: `plugin add/list/rm/use/stop` only maintain a
# registry file and never fetch, build or version anything, and `plugin add`
# needs a binary already on disk. This is that same built-in mechanism, run
# over whatever your package manager installed alongside `nu`.
#
# Re-run after every Nushell upgrade: the registry is protocol-versioned.
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

# Anything fetched belongs to you, not to the distro, so it lands in your
# directory — which is also first on NU_LIB_DIRS, so it shadows a shipped
# file of the same name.
def user-dir [sub: string]: nothing -> path {
  let d = ((user-root) | path join $sub)
  mkdir $d
  $d
}

# Vendor a completion module from nu_scripts into YOUR completions/.
#   nu-config fetch completion docker
export def "fetch completion" [tool: string]: nothing -> nothing {
  let url = $"($NU_SCRIPTS)/custom-completions/($tool)/($tool)-completions.nu"
  let dest = (user-dir completions | path join $"($tool)-completions.nu")
  let body = (try { http get $url } catch { error make { msg: $"nothing at ($url)" } })
  $body | save -f $dest
  print $"saved ($dest)"
  print $"add to your settings.nu:   use ($tool)-completions.nu *"
}

def editor-argv []: nothing -> list<string> {
  $env.EDITOR? | default "vi" | split row " "
}

# Open the distro checkout in $EDITOR.
export def edit []: nothing -> nothing {
  let ed = (editor-argv)
  ^($ed | first) ...($ed | skip 1) (distro-root)
}

# Open your own settings.nu in $EDITOR, creating it if this is the first time.
export def "edit user" []: nothing -> nothing {
  let f = ((user-root) | path join settings.nu)
  if not ($f | path exists) {
    let template = ((distro-root) | path join templates settings.nu)
    if ($template | path exists) { cp $template $f } else { "" | save -f $f }
  }
  let ed = (editor-argv)
  ^($ed | first) ...($ed | skip 1) $f
}

# ── Modules ───────────────────────────────────────────────────────────────────
# docs/modules.md is the contract. Everything here reads meta.nuon at the
# moment you ask, never at startup: a shell that does not run these commands
# pays nothing for them.

# Every module directory, yours shadowing the distro's on a name clash.
def module-dirs []: nothing -> table<name: string, path: string, source: string> {
  [[dir source]; [((user-root) | path join modules) "yours"] [((distro-root) | path join modules) "distro"]]
  | each {|d|
      if not ($d.dir | path exists) { return [] }
      ls $d.dir | where type == dir | get name | each {|p| { name: ($p | path basename), path: $p, source: $d.source } }
    }
  | flatten
  | uniq-by name
}

def module-meta [path: string]: nothing -> record {
  let f = ($path | path join meta.nuon)
  if not ($f | path exists) { return {} }
  try { open $f } catch { {} }
}

# Is a declared dependency satisfied on this machine?
#
# `paths` is checked when PATH misses, because a GUI application is installed
# without being on PATH: Ghostty on macOS lives in the app bundle and is only
# on PATH inside a Ghostty window, so `which` alone would call it missing on a
# machine where it is plainly there.
def dep-state [d: record]: nothing -> record {
  let present = (
    (which ($d.bin? | default "") | is-not-empty)
    or (($d.paths? | default []) | any {|p| $p | path expand | path exists })
  )
  let hard = ($d.hard? | default true)
  {
    bin: ($d.bin? | default "?")
    present: $present
    hard: $hard
    why: ($d.why? | default "")
    install: ($d.install? | get -o $nu.os-info.name | default "")
    state: (if $present { "ok" } else if $hard { "missing" } else { "optional" })
  }
}

# conf/modules.nu publishes the enabled list as $env.NU_MODULES. This fallback
# only matters in a shell that imported this module without the config, such as
# install.nu running as a script.
const MODULES_FALLBACK = [nu-config nu-complete agent odata]

# Private, like mod-info and mod-check: `module` is a Nushell keyword, so an
# exported `module list` cannot be called from inside this file.
def mod-list []: nothing -> table {
  module-dirs | each {|m|
    let meta = (module-meta $m.path)
    let enabled = ($m.name in ($env.NU_MODULES? | default $MODULES_FALLBACK))
    let deps = ($meta.requires? | default [] | each {|d| dep-state $d })
    {
      module: $m.name
      from: $m.source
      enabled: $enabled
      lazy: ($meta.lazy? | default false)
      # A lazy module is loaded only once something mentioned it; an eager
      # one was loaded at startup if it is enabled at all.
      loaded: (if ($meta.lazy? | default false) { $m.name in ($env.NU_MODULES_LOADED? | default []) } else { $enabled })
      deps: (if ($deps | is-empty) { "—" } else { $deps | each {|d| $"($d.bin):($d.state)" } | str join " " })
      cost: ($meta.cost? | default 0ns)
      description: ($meta.description? | default "")
    }
  }
}

# `module` is a Nushell keyword, so `module info ...` cannot be called from
# inside this file even though it is a perfectly good exported name. The body
# lives in a private command that other commands here can reach.
def mod-info [name: string]: nothing -> record {
  let dir = (module-dirs | where name == $name | get -o 0)
  if $dir == null { error make { msg: $"no module named '($name)'" } }
  let meta = (module-meta $dir.path)
  {
    module: $name
    path: $dir.path
    from: $dir.source
    description: ($meta.description? | default "")
    lazy: ($meta.lazy? | default false)
    cost: ($meta.cost? | default 0ns)
    requires: ($meta.requires? | default [] | each {|d| dep-state $d })
    knobs: ($meta.knobs? | default {})
    docs: (if ($meta.docs? | default "" | is-empty) { "" } else { $dir.path | path join $meta.docs | path expand })
  }
}

# Private for the same reason as mod-info: `module` is a Nushell keyword.
def mod-check [name: string]: nothing -> nothing {
  let info = (mod-info $name)
  let ok = $"(ansi green)ok(ansi reset)"
  print $"(ansi cyan_bold)($name)(ansi reset)  ($info.description)"
  if ($info.requires | is-empty) { print "  no dependencies"; return }
  for d in $info.requires {
    let mark = (match $d.state {
      "ok" => $ok
      "missing" => $"(ansi red)!!(ansi reset)"
      _ => $"(ansi yellow)--(ansi reset)"
    })
    print $"  ($mark) ($d.bin | fill --width 10) ($d.why)"
    if not $d.present and ($d.install | is-not-empty) {
      print $"     (ansi dark_gray)install:(ansi reset) ($d.install)"
    }
  }
}

# What modules exist, and what this shell has done with them.
export def "module list" []: nothing -> table { mod-list }

# Everything meta.nuon says about one module, plus its dependency report.
export def "module info" [name: string@module-names]: nothing -> record { mod-info $name }

# Dependency report for one module. Installs nothing, loads nothing.
export def "module check" [name: string@module-names]: nothing -> nothing { mod-check $name }

def module-names []: nothing -> list<string> { module-dirs | get name }

# The enabled set and the lazy set as this shell sees them.
def module-sets []: nothing -> record<enabled: list<string>, lazy: list<string>> {
  {
    enabled: ($env.NU_MODULES? | default $MODULES_FALLBACK)
    lazy: ($env.NU_MODULES_LAZY? | default [])
  }
}

# Write `const NAME = [a b c]` into your settings.nu, replacing the line if it
# is already there (commented or not) and appending it otherwise.
def set-const-list [name: string, values: list<string>]: nothing -> nothing {
  let f = ((user-root) | path join settings.nu)
  if not ($f | path exists) {
    let template = ((distro-root) | path join templates settings.nu)
    if ($template | path exists) { cp $template $f } else { "" | save -f $f }
  }
  let line = $"const ($name) = [($values | str join ' ')]"
  let src = (open --raw $f | lines)
  let hit = ($src | enumerate | where {|r| $r.item =~ $'^\s*#?\s*const\s+($name)\s*=' } | get -o 0)
  let out = if $hit == null {
    $src ++ ["" $"# set by `nu-config module` on (date now | format date '%Y-%m-%d')" $line]
  } else {
    $src | update $hit.index $line
  }
  $out | str join (char nl) | save -f $f
  print $"  ($f | path basename): ($line)"
}

# Turn a module on. `--lazy` loads it on first mention instead of at startup.
export def "module enable" [
  name: string@module-names
  --lazy      # load on first mention (interactive shells only)
  --eager     # load at startup
]: nothing -> nothing {
  if $lazy and $eager { error make { msg: "--lazy and --eager are opposites" } }
  if ($name not-in (module-names)) { error make { msg: $"no module named '($name)'" } }
  let sets = (module-sets)
  print $"(ansi cyan_bold)enabling ($name)(ansi reset)"
  set-const-list "MODULES" ($sets.enabled | append $name | uniq)
  if $lazy { set-const-list "MODULES_LAZY" ($sets.lazy | append $name | uniq) }
  if $eager { set-const-list "MODULES_LAZY" ($sets.lazy | where $it != $name) }
  mod-check $name
  print "  restart your shell to pick it up"
}

# Turn a module off. Its files stay where they are.
export def "module disable" [name: string@module-names]: nothing -> nothing {
  let sets = (module-sets)
  if $name in ["nu-config"] {
    error make { msg: "nu-config is how you repair everything else; disabling it would leave no way back" }
  }
  print $"(ansi cyan_bold)disabling ($name)(ansi reset)"
  set-const-list "MODULES" ($sets.enabled | where $it != $name)
  print "  restart your shell to drop it"
}

# Check every module against the contract in docs/modules.md.
#
# A contract nothing checks drifts the first time one is added in a hurry,
# and a module that half-conforms fails in ways that look like Nushell bugs.
#
# The parse check is here because nothing else covers a LAZY module: `nu-check
# distro.nu` follows `source`, and a lazy module is sourced by a hook string at
# runtime, so a syntax error in it survives every startup and surfaces only when
# someone finally types its name. That is exactly how `agent` shipped broken.
export def "module lint" []: nothing -> table<module: string, problem: string> {
  module-dirs | each {|m|
    let meta_file = ($m.path | path join meta.nuon)
    let meta = (module-meta $m.path)
    let lazy = ($meta.lazy? | default false)
    let problems = ([
      (if not ($meta_file | path exists) { "no meta.nuon" })
      (if ($meta_file | path exists) and ($meta | is-empty) { "meta.nuon does not parse" })
      (if ($meta.description? | default "" | is-empty) { "meta.nuon has no description" })
      (if ($meta.cost? | default 0ns) == 0ns { "meta.nuon has no measured cost" })
      (if not (($m.path | path join mod.nu) | path exists) { "no mod.nu" })
      (if not (($m.path | path join load.nu) | path exists) { "no load.nu — conf/modules.nu has nothing to source" })
      (if not (($m.path | path join README.md) | path exists) { "no README.md" })
      (if ((($m.path | path join load.nu) | path exists) and not ((do -i { nu-check ($m.path | path join load.nu) } | default false))) { "load.nu does not parse — the module would fail on first use" })
      ($meta.requires? | default [] | each {|d|
          if ($d.bin? | default "" | is-empty) { "a requires entry has no bin" } else if ($d.why? | default "" | is-empty) { $"requires ($d.bin) has no why" } else if (["macos" "linux" "windows"] | any {|o| ($d.install? | get -o $o | default "" | is-empty) }) { $"requires ($d.bin) is missing an install line for some platform" } else { null }
        } | compact)
    ] | flatten | compact)
    $problems | each {|p| { module: $m.name, problem: $p } }
  } | flatten
}
