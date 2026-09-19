# The layering that is the whole idea of the distro (docs/concepts/layout.md):
# defaults.nu, then your settings.nu, then conf/ reading the settled values.
# Every shell here starts against a user directory of its own (lib.nu
# `user-dir`), so what it sees is exactly what the scratch settings.nu says.
use lib.nu *
use std/assert

# ── settings.nu wins ──────────────────────────────────────────────────────────

def "test a const and an env leaf in settings.nu reach the conf file that reads them" [] {
  let dir = user-dir --settings 'const SMART_TAB = false
$env.config.edit_mode = "emacs"'
  let ran = nu-l $dir 'print $env.NU_SMART_TAB $env.config.edit_mode ($env.config.menus | where name == smart_menu | length)'
  assert equal $ran.exit_code 0 $ran.stderr
  # SMART_TAB reaches conf/completions.nu as $env.NU_SMART_TAB and decides
  # whether the smart menu is wired at all.
  assert equal ($ran.stdout | lines) ["false" emacs "0"]
}

def "test a knob never mentioned keeps its shipped value" [] {
  let dir = user-dir
  let ran = nu-l $dir 'print $env.NU_SMART_TAB $env.config.edit_mode'
  assert equal ($ran.stdout | lines) ["true" vi]
}

def "test knobs --overridden names exactly the live lines of settings.nu" [] {
  let dir = user-dir --settings '# const EDITORS = []
const SMART_TAB = false
$env.config.edit_mode = "emacs"'
  let ran = nu-l $dir 'nu-config knobs --overridden | select knob kind owner | to nuon'
  assert equal $ran.exit_code 0 $ran.stderr
  # In defaults.nu order.
  assert equal ($ran.stdout | from nuon) [
    { knob: config.edit_mode, kind: env, owner: distro }
    { knob: SMART_TAB, kind: const, owner: distro }
  ]
}

def "test a default install overrides nothing" [] {
  let dir = user-dir
  let ran = nu-l $dir 'nu-config knobs --overridden | length'
  assert equal ($ran.stdout | str trim) "0"
}

# ── the knob list ─────────────────────────────────────────────────────────────

# Every assignment in defaults.nu, read the plain way: `const NAME =` and
# `$env.path =` at the start of a line.
def defaults-knobs []: nothing -> list<string> {
  open --raw ($ROOT | path join defaults.nu) | lines
  | each {|l| $l | parse -r '^(?:const (?<c>[A-Z_][A-Z0-9_]*)|\$env\.(?<e>[A-Za-z_][\w.]*))\s*=' | get -o 0 }
  | compact
  | each {|r| if ($r.c | is-not-empty) { $r.c } else { $r.e } }
}

def "test knobs lists every assignment in defaults.nu and every module knob" [] {
  let dir = user-dir
  let ran = nu-l $dir 'nu-config knobs | to nuon'
  assert equal $ran.exit_code 0 $ran.stderr
  let knobs = $ran.stdout | from nuon
  assert equal ($knobs | where owner == distro | get knob) (defaults-knobs)
  for m in (ls ($ROOT | path join modules) | get name) {
    let declared = open ($m | path join meta.nuon) | get -o knobs | default {} | columns
    assert equal ($knobs | where owner == ($m | path basename) | get knob) $declared ($m | path basename)
  }
  assert ($knobs | all {|k| not $k.yours })
}

# ── conf/ never assigns a value defaults.nu owns ──────────────────────────────

def "test no conf file assigns a knob defaults.nu owns" [] {
  # A conf/ file runs after settings.nu, so such an assignment would silently
  # overwrite the user's value (the rule in CLAUDE.md).
  let owned = defaults-knobs
  let hits = ls ($ROOT | path join conf) | get name | each {|f|
    open --raw $f | lines
    | each {|l| $l | parse -r '^\s*(?:const (?<c>[A-Z_][A-Z0-9_]*)|\$env\.(?<e>[A-Za-z_][\w.]*))\s*=[^=]' | get -o 0 }
    | compact
    | each {|r| if ($r.c | is-not-empty) { $r.c } else { $r.e } }
    | where {|k| $k in $owned }
    | each {|k| { file: ($f | path basename), knob: $k } }
  } | flatten
  assert equal $hits [] ($hits | to nuon)
}

# ── what startup loads ────────────────────────────────────────────────────────

def "test a lazy module is not parsed at startup and an eager one is" [] {
  let dir = user-dir
  let ran = nu-l $dir 'view files | get filename | where $it =~ "modules[/\\\\]" | each {|f| $f | path dirname | path basename } | uniq | sort | to nuon'
  assert equal $ran.exit_code 0 $ran.stderr
  let parsed = $ran.stdout | from nuon
  # agent's stub.nu is parsed for every shell (the session id, Alt+E); its
  # mod.nu is not.
  assert equal $parsed [agent nu-complete nu-config]
  let stub = nu-l $dir 'view files | get filename | where $it =~ "modules[/\\\\]agent" | path basename | to nuon'
  assert equal ($stub.stdout | from nuon) [stub.nu]
}

def "test MODULES_LAZY in settings.nu makes a module eager or lazy" [] {
  let dir = user-dir --settings 'const MODULES_LAZY = [agent odata]'
  let ran = nu-l $dir 'print ("terminal" in $env.NU_MODULES_LAZY); nu-config module list | where module == terminal | get 0 | select lazy loaded | to nuon | print; view files | get filename | where $it =~ "modules[/\\\\]terminal" | length | print'
  assert equal $ran.exit_code 0 $ran.stderr
  assert equal ($ran.stdout | lines) ["false" "{lazy: false, loaded: true}" "7"]
}

def "test the lazy hook sources the module on a trigger word" [] {
  let dir = user-dir
  let ran = nu-l $dir '$env.config.hooks.pre_execution | where {|h| ($h.code? | default "") =~ "terminal" } | get 0.code'
  assert equal $ran.exit_code 0 $ran.stderr
  let code = $ran.stdout | str trim
  assert ($code | str contains ($ROOT | path join modules terminal load.nu)) $code
  # The hook's code is a string Nushell parses into the session; running it
  # from -c is the same parse, and the module's commands are there after it.
  let loaded = nu-l $dir $"($code); print \(theme slug 'A B'\) \($env.NU_MODULES_LOADED | to nuon\)"
  assert equal $loaded.exit_code 0 $loaded.stderr
  assert equal ($loaded.stdout | lines) [a-b "[terminal]"]
}

def "test the trigger words come from MODULES_TRIGGERS and fire once" [] {
  let dir = user-dir --settings 'const MODULES_TRIGGERS = { terminal: [palette], odata: [expand] }'
  # The condition reads the line being run; `commandline edit` sets it here.
  let ran = nu-l $dir '
    let cond = ($env.config.hooks.pre_execution | where {|h| ($h.code? | default "") =~ "terminal" } | get 0.condition)
    let fires = {|line| commandline edit --replace $line; do $cond }
    print (do $fires "palette list") (do $fires "ls | terminal") (do $fires "theme use x") (do $fires "ls themes")
    $env.NU_MODULES_LOADED = [terminal]
    print (do $fires "palette list")'
  assert equal $ran.exit_code 0 $ran.stderr
  # `theme` is no longer a trigger once the knob is overridden; a word inside
  # another does not count; a loaded module is not loaded twice.
  assert equal ($ran.stdout | lines) ["true" "true" "false" "false" "false"]
}

def "test startup stays under a generous budget" [] {
  # 56-70 ms here, 140-390 ms on the CI runners (2026-09-19); a module that
  # stopped being lazy would add 18-97 ms, which the file check above
  # catches — this is the sanity bound.
  let dir = user-dir
  let times = 1..5 | each {|_| nu-l $dir '$nu.startup-time' | get stdout | str trim | into duration }
  let best = $times | math min
  assert ($best < 2sec) $"startup took ($best)"
}
