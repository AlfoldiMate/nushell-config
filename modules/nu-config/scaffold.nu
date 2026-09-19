# scaffold.nu — your configuration directory as a scaffold: generated once, never overwritten
#
# A SCRIPT, run by user.nu in a `nu -n` of its own, never parsed at startup:
# these 350 lines cost 4.4 ms to parse (measured 2026-09-19, minimum of
# fifteen `nu -n -c "use user.nu"` against an empty `nu -n`), and a shell
# that never regenerates its directory should not pay that at every start.
# user.nu is the 40-line face — `nu-config user init | status | render |
# set` — and hands every call here with `--dir` spelled out, because a
# config-less child does not know which directory the parent's config came
# from. Each verb prints NUON, which user.nu turns back into the table.
#
#   nu scaffold.nu init --dir <yours>                write every scaffold file that is missing;
#                                                    append the knobs settings.nu has never heard of, commented
#   nu scaffold.nu init --dir <yours> --dry-run      the list only, nothing written
#   nu scaffold.nu init --dir <yours> --force settings.nu   replace one file, keeping <file>.backup-<stamp>
#   nu scaffold.nu status --dir <yours>              every scaffold file: present / edited / missing
#   nu scaffold.nu render settings.nu --dir <yours>  what init would write for one file
#   nu scaffold.nu set 'const MODULES = [nu-config]' --dir <yours>   one assignment into settings.nu, in place
#
# The scaffold is templates/user/ in the checkout, mirrored file for file into
# your directory: a README per directory saying what the directory is for, and
# one example per kind — autoload/example.nu.off, completions/hello.nu.off,
# themes/palettes/example.nuon.off — complete and working, doing nothing until
# renamed, because Nushell loads only *.nu and the palette reader only *.nuon.
#
# settings.nu is the one file that is generated rather than copied. Its body is
# every knob in defaults.nu and every module's meta.nuon, in its section, with
# its comment, commented out at its shipped value: the file you open IS the
# knob list, and `nu-config knobs` reads the same two sources. A knob the
# distro grows later is appended by the next `user init`, commented, under a
# dated mark — the only thing init ever writes into a file you have.
#
# Rendering substitutes two things. A relative path in a template — a
# markdown link, a path in a comment — is written for the template's place in
# the checkout, so it works on GitHub, and rewritten for the file's place in
# your directory, so it works in your editor: templates/user/ mirrors your
# directory, so `../settings.nu` stays `../settings.nu` and `../../docs/x.md`
# becomes the way to the checkout's docs from wherever your directory is.
# `@DISTRO@` is the checkout itself.
#
# "Edited" is judged by comparing a file with what init would write today —
# never by mtime, which a `cp` or a sync changes.

# This file is modules/nu-config/scaffold.nu, three levels down.
const ROOT = path self | path dirname | path dirname | path dirname

def distro-root []: nothing -> path { $ROOT | path expand }
def templates-dir []: nothing -> path { distro-root | path join templates user }

# ── The scaffold ──────────────────────────────────────────────────────────────

# Every file templates/user/ holds, as a path relative to it — which is also
# its path in your directory.
def scaffold []: nothing -> list<string> {
  let t = (templates-dir)
  walk $t | each {|f| $f | path relative-to $t } | sort
}

# Every file under a directory. Not `glob`: its pattern syntax and Windows
# separators disagree.
def walk [dir: path]: nothing -> list<string> {
  ls --all $dir | each {|e| if $e.type == "dir" { walk $e.name } else { [$e.name] } } | flatten
}

# A file's contents with every substitution applied, for a directory.
def render-file [rel: string, root: path]: nothing -> string {
  let t = (templates-dir | path join $rel)
  if not ($t | path exists) { error make { msg: $"no scaffold file called ($rel) — `nu-config user status` lists them" } }
  let text = (open --raw $t)
  let text = (if $rel == "settings.nu" { ($text | str trim --right --char (char nl)) + (char nl) + (char nl) + (settings-body $root) } else { $text })
  render-text $text ($t | path dirname) ($root | path join $rel | path dirname)
}

# Substitutions: @DISTRO@, and every relative path that resolves to a file in
# the checkout, rewritten from the destination's directory. One pass: each
# path is fenced with a unit separator, the text split on it, and the odd
# segments (the paths) mapped — replacing token by token would let a short
# path match inside a longer one already rewritten.
def render-text [text: string, tdir: path, ddir: path]: nothing -> string {
  let fence = (char us)
  $text
  | str replace --all "@DISTRO@" (distro-root)
  | str replace --all --regex '(?m)(^|[^\w./])((?:\.\./)+[\w.-][\w./-]*)' ("$1" + $fence + "$2" + $fence)
  | split row $fence
  | enumerate
  | each {|s| if ($s.index mod 2) == 1 { relink $s.item $tdir $ddir } else { $s.item } }
  | str join
}

# One relative path out of a template, rewritten for the destination — or
# left alone when it points at nothing in the checkout, which is what a path
# into your own directory (`../plugins/nu_plugin_foo`) does. A path at the end
# of a sentence carries its full stop; it is tried without it.
def relink [tok: string, tdir: path, ddir: path]: nothing -> string {
  let bare = ($tok | str trim --right --char '.')
  let tail = ($tok | str substring ($bare | str length)..)
  let target = ($tdir | path join $bare | path expand --no-symlink)
  if not ($target | path exists) { return $tok }
  (relative-path $ddir $target) + $tail
}

# `to` relative to the directory `from`; absolute when they share no root
# (a Windows drive apart). Neither side resolves symlinks, so a directory
# reached through a link gets a path that works from where the link is.
def relative-path [from: path, to: path]: nothing -> string {
  let a = ($from | path expand --no-symlink | path split)
  let b = ($to | path expand --no-symlink | path split)
  let n = ([($a | length) ($b | length)] | math min)
  let common = (0..<$n | each {|i| $i } | take while {|i| ($a | get $i) == ($b | get $i) } | length)
  if $common == 0 { return $to }
  let ups = (0..<(($a | length) - $common) | each { ".." })
  ($ups ++ ($b | skip $common)) | path join
}

# Line endings and a trailing newline are not an edit.
def same-text [a: string, b: string]: nothing -> bool {
  ($a | lines | str join (char nl) | str trim --right) == ($b | lines | str join (char nl) | str trim --right)
}

# ── settings.nu, generated ────────────────────────────────────────────────────

# The section rule, the width defaults.nu uses.
def section-line [name: string]: nothing -> string {
  $"# ── ($name) " | fill --alignment left --character "─" --width 80
}

# The knob a line assigns, or null.
def knob-name [line: string]: nothing -> any {
  let c = ($line | parse --regex '^const (?<name>[A-Z_][A-Z0-9_]*)\s*=' | get -o 0.name)
  let e = ($line | parse --regex '^\$env\.(?<name>[A-Za-z_][\w.]*)\s*=' | get -o 0.name)
  if $c != null { $c } else { $e }
}

# Brackets opened minus brackets closed, the trailing comment dropped —
# enough to follow `const EDITORS = [` to its `]`.
def bracket-delta [line: string]: nothing -> int {
  let code = ($line | str replace --regex '\s#.*$' '')
  let opens = ($code | str replace --all --regex '[^\[{(]' '' | str length)
  let closes = ($code | str replace --all --regex '[^\]})]' '' | str length)
  $opens - $closes
}

# defaults.nu as items, in order: a section rule, a comment block, a blank
# line, or a knob — its comment block and the lines of its assignment. The
# header before the first section is defaults.nu's own and is dropped.
def default-items []: nothing -> list<record> {
  mut items = []
  mut comments = []
  mut knob: any = null
  mut started = false
  for l in (open --raw (distro-root | path join defaults.nu) | lines) {
    if $knob != null {
      $knob.lines = ($knob.lines | append $l)
      $knob.depth = ($knob.depth + (bracket-delta $l))
      if $knob.depth <= 0 { $items = ($items | append ($knob | reject depth)); $knob = null }
    } else if ($l | str starts-with "# ── ") {
      $started = true
      $items = ($items | append { kind: "section", name: null, comments: [], lines: [$l] })
      $comments = []
    } else if not $started {
      # defaults.nu's header: "read this file, do not edit it" — not for settings.nu
    } else if ($l | str starts-with "#") {
      $comments = ($comments | append $l)
    } else if ($l | str trim | is-empty) {
      if ($comments | is-not-empty) { $items = ($items | append { kind: "comment", name: null, comments: [], lines: $comments }) }
      $items = ($items | append { kind: "blank", name: null, comments: [], lines: [""] })
      $comments = []
    } else {
      let name = (knob-name $l)
      let k = { kind: (if $name == null { "code" } else { "knob" }), name: $name, comments: $comments, lines: [$l], depth: (bracket-delta $l) }
      $comments = []
      if $k.depth > 0 { $knob = $k } else { $items = ($items | append ($k | reject depth)) }
    }
  }
  if ($comments | is-not-empty) { $items = ($items | append { kind: "comment", name: null, comments: [], lines: $comments }) }
  $items
}

# The knobs a module declares, as the same kind of item: one commented
# assignment per knob, its `about` beside it. A default given as an
# abbreviation ("{ask: sonnet, ...}") is shown as written; a real string is
# quoted so the line is valid Nushell once uncommented.
def module-items [root: path]: nothing -> list<record> {
  module-metas $root | where ($it.knobs | is-not-empty) | each {|m|
    # Paths as seen from templates/user/, where settings.nu's template lives;
    # rendering rewrites them for your directory. A module of yours is
    # already relative to it.
    let where = (if $m.from == "distro" { $"../../modules/($m.name)/meta.nuon" } else { $"modules/($m.name)/meta.nuon" })
    let docs = (if ($m.docs | is-empty) { "" } else if $m.from == "distro" { $"../../($m.docs)" } else { $m.docs })
    let head = [
      { kind: "section", name: null, comments: [], lines: [(section-line $"Module: ($m.name)")] }
      { kind: "comment", name: null, comments: [], lines: ([$"# Read by the module when it loads; declared in ($where)"] ++ (if ($docs | is-empty) { [] } else { [$"# and explained in ($docs)"] })) }
    ]
    let knobs = ($m.knobs | transpose knob spec | each {|k|
      let d = ($k.spec.default? | default null)
      let shown = (if ($d | describe) == "string" and (($d | str contains "...") or ($d | str starts-with "{") or ($d | str starts-with "[")) { $d } else { $d | to nuon })
      let about = ($k.spec.about? | default "")
      { kind: "knob", name: $k.knob, comments: [], lines: [(($"$env.($k.knob) = ($shown)" | fill --alignment left --width 42) + $"  # ($about)")] }
    })
    # A leading `++` on a line of its own parses as a command, so one expression.
    $head ++ $knobs ++ [{ kind: "blank", name: null, comments: [], lines: [""] }]
  } | flatten
}

# meta.nuon of every module, yours shadowing the distro's on a name clash.
def module-metas [root: path]: nothing -> table<name: string, from: string, knobs: record, docs: string> {
  [[dir from]; [($root | path join modules) "yours"] [(distro-root | path join modules) "distro"]]
  | each {|d|
      if not ($d.dir | path exists) { return [] }
      ls $d.dir | where type == dir | get name | each {|p|
        let meta = (try { open ($p | path join meta.nuon) } catch { {} })
        { name: ($p | path basename), from: $d.from, knobs: ($meta.knobs? | default {}), docs: ($meta.docs? | default "") }
      }
    }
  | flatten
  | uniq-by name
}

def render-item [it: record]: nothing -> list<string> {
  match $it.kind {
    "knob" | "code" => ($it.comments ++ ($it.lines | each {|l| $"# ($l)" }))
    _ => $it.lines
  }
}

const TRAILER = [
  "# `use` is parse-time, so a module of your own is wired in here rather than"
  "# in autoload/. completions/ and modules/ are on the search path, yours first."
  "# use hello.nu *                            # completions/hello.nu — the example, once renamed"
  "# use mymodule                              # modules/mymodule/mod.nu"
]

# The body: defaults.nu commented out, the module knobs, then where a `use` goes.
def settings-body [root: path]: nothing -> string {
  (
    (default-items | each {|it| render-item $it } | flatten)
    ++ [""]
    ++ (module-items $root | each {|it| render-item $it } | flatten)
    ++ [(section-line "Yours")]
    ++ $TRAILER
  ) | str join (char nl) | str replace --all --regex '\n{3,}' "\n\n" | str trim --right | append-nl
}

def append-nl []: string -> string { $in + (char nl) }

# The knobs a settings.nu never mentions, live or commented: what a later
# `nu-config upgrade` brought in. Each comes with its comment block.
def missing-knobs [text: string, root: path]: nothing -> list<record> {
  ((default-items) ++ (module-items $root))
  | where kind == "knob"
  | where {|it| not ($text =~ ('\b' + ($it.name | str replace --all '.' '\.') + '\b')) }
}

# ── The verbs ─────────────────────────────────────────────────────────────────
# Each takes --dir, always passed by user.nu, and prints NUON.

def main [] { print "a script user.nu runs: init | status | render | set, each with --dir" }

# What init would write for one scaffold file, rendered for a directory.
def "main render" [file: string, --dir: path] {
  render-file $file $dir | to nuon
}

# Every scaffold file, and whether the directory has it as written, edited, or not at all.
def "main status" [--dir: path] {
  scaffold | each {|rel|
    let dest = ($dir | path join $rel)
    if not ($dest | path exists) { return { file: $rel, state: "missing", note: "" } }
    let have = (open --raw $dest)
    let note = (if $rel == "settings.nu" {
      let n = (missing-knobs $have $dir | length)
      if $n == 0 { "" } else { $"($n) knob(if $n == 1 { '' } else { 's' }) not mentioned — `nu-config user init` appends them" }
    } else { "" })
    { file: $rel, state: (if (same-text $have (render-file $rel $dir)) { "present" } else { "edited" }), note: $note }
  } | to nuon
}

# Write every scaffold file that is missing, and nothing that exists — except
# that settings.nu gets the knobs it has never mentioned appended, commented,
# under a dated mark.
def "main init" [
  --dir: path        # the directory to scaffold
  --dry-run          # report what would be done, write nothing
  --force: string    # one scaffold file to replace even though it exists; the old one is kept as <file>.backup-<stamp>
  --fresh            # treat the directory as empty (install.nu's dry run over a layout it is about to replace)
] {
  let stamp = (date now | format date '%Y%m%d-%H%M%S')
  if $force != null and $force not-in (scaffold) {
    error make { msg: $"no scaffold file called ($force) — `nu-config user status` lists them" }
  }
  let said = (if $dry_run { { write: "would write", replace: "would replace", append: "would append" } } else { { write: "written", replace: "replaced", append: "appended" } })
  scaffold | each {|rel|
    let dest = ($dir | path join $rel)
    let want = (render-file $rel $dir)
    let have = (if $fresh or not ($dest | path exists) { null } else { open --raw $dest })
    if $have == null {
      if not $dry_run { mkdir ($dest | path dirname); $want | save --force --raw $dest }
      { file: $rel, action: $said.write, note: "" }
    } else if $rel == $force {
      let backup = $"($dest).backup-($stamp)"
      if not $dry_run { cp $dest $backup; $want | save --force --raw $dest }
      { file: $rel, action: $said.replace, note: $"the old one is ($backup | path basename)" }
    } else if $rel == "settings.nu" and (missing-knobs $have $dir | is-not-empty) {
      let add = (missing-knobs $have $dir)
      let block = (
        ["" (section-line $"Added by `nu-config user init` on (date now | format date '%Y-%m-%d')")]
        ++ ["# Knobs the distro has grown since this file was written, at their shipped values."]
        ++ ($add | each {|it| [""] ++ (render-item $it) } | flatten)
      )
      if not $dry_run { (($have | str trim --right --char (char nl)) + (char nl) + ($block | str join (char nl)) + (char nl)) | save --force --raw $dest }
      { file: $rel, action: $said.append, note: $"($add | length) new knob(if ($add | length) == 1 { '' } else { 's' }), commented: ($add | get name | str join ', ')" }
    } else {
      { file: $rel, action: "kept", note: (if (same-text $have $want) { "" } else { "edited" }) }
    }
  } | to nuon
}

# Write one assignment into settings.nu — `const MODULES = [a b]` or
# `$env.config.table.mode = "rounded"` — replacing the knob's line whether it
# is live or commented out, so the value lands in its section, and appending
# under a dated mark when the file never mentioned it. A commented multi-line
# value (`# const EDITORS = [` … `# ]`) is replaced whole.
def "main set" [line: string, --dir: path] {
  let name = (knob-name $line)
  if $name == null { error make { msg: $"not an assignment: ($line) — expected `const NAME = …` or `$env.name = …`" } }
  let f = ($dir | path join settings.nu)
  if not ($f | path exists) { render-file settings.nu $dir | save --raw $f }
  let src = (open --raw $f | lines)
  let head = (if ($line | str starts-with "const") { '^\s*#?\s*const\s+' } else { '^\s*#?\s*\$env\.' })
  let pattern = ($head + ($name | str replace --all '.' '\.') + '\s*=')
  let hit = ($src | enumerate | where {|r| $r.item =~ $pattern } | get -o 0)
  let out = if $hit == null {
    $src ++ ["" $"# set by `nu-config user set` on (date now | format date '%Y-%m-%d')" $line]
  } else {
    # How many lines the old value spans: its own, plus continuation lines
    # while a bracket is still open — commented ones included.
    mut span = 1
    mut depth = (bracket-delta ($hit.item | str replace --regex '^\s*#\s?' ''))
    while $depth > 0 and ($hit.index + $span) < ($src | length) {
      $depth = ($depth + (bracket-delta ($src | get ($hit.index + $span) | str replace --regex '^\s*#\s?' '')))
      $span = ($span + 1)
    }
    ($src | take $hit.index) ++ [$line] ++ ($src | skip ($hit.index + $span))
  }
  $out | str join (char nl) | append-nl | save --force --raw $f
  { file: ($f | path basename), line: $line } | to nuon
}
