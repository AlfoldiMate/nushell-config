# smart — the Tab menu source
#
# Nushell's own completer sees each command in isolation; only a custom menu
# `source` closure gets the whole line (verified on 0.115.1: per-argument
# completers get `get na`, not `ls | get na`, and `commandline` is empty while
# completing). So Tab is bound to a menu whose source is `nu-complete smart`,
# which starts from what Nushell would offer — `commandline complete
# --detailed`, 0.1-0.6 ms, including every extern and carapace — and then:
#
#   1. Columns.   `ls | where ⌶`, `get`, `select`, `sort-by`, `update` and every
#                 other cell-path or condition slot offers the columns of the
#                 pipeline so far, typed and with a sample value. Nested paths
#                 (`get package.⌶`) and closure params (`each {|r| $r.⌶}`) too.
#   2. Operators. `where size ⌶` narrows Nushell's operator list to the ones
#                 that make sense for the column's type.
#   3. Values.    `where type == ⌶` offers the distinct values of that column
#                 as Nushell literals.
#   4. No noise.  A command that takes no positional (`ps ⌶`, 216 built-ins)
#                 stops offering the files in the directory.
#   5. No twins.  A shadowed built-in is listed once, not twice.
#   6. Somewhere. `cd ⌶` in a folder with nothing to enter offers `..`, `~`,
#                 `-` and zoxide's most-used directories instead of
#                 NO RECORDS FOUND; `cd nus⌶` matches ~/.config/nushell.
#
# 1-3 need the pipeline's output. It is produced by running the pipeline up
# to the current command in a subprocess (`nu -n -c`, ~20 ms, memoised for
# 45 s per directory) — only when every command in it is a read-only
# built-in; see `safe-to-eval`. $env.NU_COMPLETE_EVAL turns it off ("off") or
# extends it to your own commands ("all", loads the config, ~80 ms).
#
# The source runs again on every keystroke while the menu is open, which is
# why everything here is cached and why the only external it runs, zoxide for
# a `cd` with nothing local to enter, is memoised too.

use engine.nu *
use cache.nu *

# ── Tokenising the line ───────────────────────────────────────────────────────

# The pipe-separated segments of the last top-level statement in `buf`,
# ignoring pipes inside quotes, parens, brackets and braces.
def segments [buf: string]: nothing -> list<string> {
  mut depth = 0
  mut quote = ""
  mut esc = false
  mut segs = []
  mut cur = ""
  for c in ($buf | split chars) {
    if $quote != "" {
      $cur += $c
      if $esc { $esc = false } else if $c == "\\" and $quote == '"' { $esc = true } else if $c == $quote { $quote = "" }
    } else if $c in ['"' "'" '`'] {
      $quote = $c
      $cur += $c
    } else if $c in ["(" "[" "{"] {
      $depth += 1
      $cur += $c
    } else if $c in [")" "]" "}"] {
      $depth = ([($depth - 1) 0] | math max)
      $cur += $c
    } else if $depth == 0 and $c == "|" {
      $segs ++= [$cur]
      $cur = ""
    } else if $depth == 0 and ($c == ";" or $c == "\n") {
      $segs = []
      $cur = ""
    } else {
      $cur += $c
    }
  }
  $segs ++ [$cur]
}

# Whitespace-separated words of one segment (quotes and brackets kept
# together), and whether the segment ends in whitespace — a fresh slot.
def words [seg: string]: nothing -> record<tokens: list<string>, fresh: bool> {
  mut depth = 0
  mut quote = ""
  mut esc = false
  mut toks = []
  mut cur = ""
  mut fresh = false
  for c in ($seg | split chars) {
    if $quote != "" {
      $cur += $c
      $fresh = false
      if $esc { $esc = false } else if $c == "\\" and $quote == '"' { $esc = true } else if $c == $quote { $quote = "" }
    } else if $c in ['"' "'" '`'] {
      $quote = $c
      $cur += $c
      $fresh = false
    } else if $c in ["(" "[" "{"] {
      $depth += 1
      $cur += $c
      $fresh = false
    } else if $c in [")" "]" "}"] {
      $depth = ([($depth - 1) 0] | math max)
      $cur += $c
      $fresh = false
    } else if $depth == 0 and ($c == " " or $c == "\t") {
      if $cur != "" { $toks ++= [$cur]; $cur = "" }
      $fresh = true
    } else {
      $cur += $c
      $fresh = false
    }
  }
  if $cur != "" { $toks ++= [$cur] }
  { tokens: $toks, fresh: $fresh }
}

# ── Command signatures, kept in stor after the first Tab ──────────────────────

const SIGS = "nu_complete_sigs"

# Fill the signature table now, so the first Tab does not pay for it.
export def "nu-complete warm" []: nothing -> nothing {
  ensure-sigs
}

def ensure-sigs []: nothing -> nothing {
  let created = (try { stor create -t $SIGS -c { name: str, npos: int, rest: int, shapes: str, valued: str, builtin: int, category: str } | ignore; true } catch { false })
  if not $created { return }
  scope commands | each {|c|
    let sig = ($c.signatures | values | first)
    let pos = ($sig | where parameter_type in [positional rest])
    let valued = ($sig | where parameter_type == named and syntax_shape != null
      | each {|p| [$"--($p.parameter_name)" (if ($p.short_flag? | default "") != "" { $"-($p.short_flag)" } else { null })] } | flatten | compact)
    {
      name: $c.name
      npos: ($pos | where parameter_type == positional | length)
      rest: (if ($pos | where parameter_type == rest | is-not-empty) { 1 } else { 0 })
      shapes: ($pos | get syntax_shape | to json -r)
      valued: ($valued | to json -r)
      builtin: (if $c.type == "built-in" { 1 } else { 0 })
      category: $c.category
    } | stor insert -t $SIGS
  } | ignore
}

def sig [name: string]: nothing -> any {
  ensure-sigs
  let hit = (stor open | query db $"select * from ($SIGS) where name = :n" -p { n: $name })
  if ($hit | is-empty) { null } else {
    $hit.0 | update shapes { from json } | update valued { from json } | update rest { $in == 1 } | update builtin { $in == 1 }
  }
}

# The command a segment starts with (`str trim` is one command), and how
# many tokens it took.
def resolve-cmd [toks: list<string>]: nothing -> any {
  if ($toks | length) >= 2 {
    let two = ($toks | first 2 | str join " ")
    let s = (sig $two)
    if $s != null { return { sig: $s, ntok: 2 } }
  }
  if ($toks | is-empty) { return null }
  let s = (sig ($toks | first))
  if $s == null { null } else { { sig: $s, ntok: 1 } }
}

# Which positional the cursor is on, skipping flags and their values.
def slot-of [args: list<string>, s: record]: nothing -> record<index: int, valued: bool> {
  mut i = 0
  mut valued = false
  for a in $args {
    if $valued { $valued = false; continue }
    if ($a | str starts-with "-") {
      if ($a in $s.valued) { $valued = true }
      continue
    }
    $i += 1
  }
  { index: $i, valued: $valued }
}

def shape-at [s: record, index: int]: nothing -> string {
  let shapes = $s.shapes
  if $index < $s.npos { $shapes | get $index } else if $s.rest { $shapes | last } else { "" }
}

# ── Running the pipeline so far ───────────────────────────────────────────────

# Read-only built-ins outside the always-safe categories.
const SAFE_EXTRA = [ps "sys cpu" "sys disks" "sys host" "sys mem" "sys net" "sys temp" "sys users" which whoami uname ls open glob du cd pwd version history "date now" "date list-timezone" do each "par-each" if match try describe table "help commands" "help modules" "help aliases" "scope commands" "scope aliases" "scope modules" "scope variables" "scope externs" "scope engine-stats" random "random int" "random float" "random bool" "random chars" "random uuid" "random dice"]
const SAFE_CATEGORIES = [filters strings conversions math date path formats hash bits bytes generators default core env debug history viewers]
const NEVER = ["odata" "into sqlite" "stor export" "stor import" "stor reset" "stor create" "stor insert" "stor delete" "stor update" save explore "config reset" "config nu" "config env" "history import" "history session" "load-env" "hide-env" "commandline edit" "commandline set-cursor" "commandline set-prompt" "keybindings listen" "term query" "input" "input listen" "input list" "input listen" clear sleep "view source" "view files" "view blocks" "view ir" "view span" "nu-check" "nu-highlight" "ansi link" "start" "run-external" exec kill "job spawn" "job kill" "job send" "job recv" "job flush" "job tag" "job unfreeze" "overlay use" "overlay new" "overlay hide" "overlay list" "plugin add" "plugin rm" "plugin stop" "plugin use" "plugin list" "attr" "def" "export" "extern" "module" "source" "source-env" "use" "hide" "alias" "const" "register" "let" "mut" "for" "while" "loop"]
const OK_KEYWORDS = [if else match try catch and or not xor in "not-in"]

# Can `prefix` run without side effects? Every call in it (closures
# included — `ast --flatten` lists them all) must be a read-only built-in, and
# nothing may be external. With NU_COMPLETE_EVAL = "all", your own commands
# pass too and the pipeline runs with the config loaded.
def safe-to-eval [prefix: string]: nothing -> record<ok: bool, custom: bool> {
  let mode = ($env.NU_COMPLETE_EVAL? | default "safe")
  if $mode == "off" { return { ok: false, custom: false } }
  let toks = (try { ast --flatten $prefix } catch { return { ok: false, custom: false } })
  mut custom = false
  for t in $toks {
    let bad = (match $t.shape {
      "shape_internalcall" => {
        if $t.content in $NEVER { true } else {
          let s = (sig $t.content)
          if $s == null { true } else if not $s.builtin { $custom = true; $mode != "all" } else {
            not (($s.category in $SAFE_CATEGORIES) or ($t.content in $SAFE_EXTRA))
          }
        }
      }
      "shape_keyword" => ($t.content not-in $OK_KEYWORDS)
      "shape_external" | "shape_externalarg" | "shape_garbage" | "shape_redirection" | "shape_raw_string" => true
      "shape_variable" => ($t.content not-in ["$env" "$nu" "$in" "$it"] and not ($t.content =~ '^\$[a-z_]\w*$'))
      _ => false
    })
    if $bad { return { ok: false, custom: $custom } }
  }
  { ok: true, custom: $custom }
}

# `ll | where` — an alias at the head of a segment is replaced by what it
# stands for, so the safety check and the subprocess see real commands.
def expand-aliases [prefix: string]: nothing -> string {
  let aliases = (scope aliases)
  if ($aliases | is-empty) { return $prefix }
  segments $prefix | each {|seg|
    let head = ($seg | str trim | split row " " | first)
    let hit = ($aliases | where name == $head)
    if ($hit | is-empty) { $seg } else { $seg | str replace $head $hit.0.expansion }
  } | str join "|"
}

# Rows of the pipeline's output as `describe --detailed` records:
# [{ columns: { name: { type, value } } }]. At most 60 rows, memoised.
def probe [prefix: string]: nothing -> list<record> {
  let prefix = (expand-aliases $prefix)
  # A provider (modules/odata (activate): $env.NU_COMPLETE_PROVIDERS) answers for a
  # command whose columns are known without running it. It sees the first
  # segment; the stages after it do not change the columns except `get`,
  # which is left to the probe (and refused for a non-built-in).
  let segs = (segments $prefix)
  let head = ($segs | first | str trim | split row " " | first)
  let provider = ($env.NU_COMPLETE_PROVIDERS? | default {} | get -o $head)
  if $provider != null and not ($segs | skip 1 | any {|s| ($s | str trim) starts-with "get " }) {
    return (nu-complete cache $"provider:($prefix)" 30sec { try { do $provider ($segs | first | str trim) } catch { [] } })
  }
  let safe = (safe-to-eval $prefix)
  if not $safe.ok { return [] }
  let key = $"probe:($env.PWD):($prefix)"
  nu-complete cache $key 45sec {
    let code = $"($prefix) | do { let v = $in; let t = \($v | describe -d); if $t.type == record { [$v] } else if $t.type in [list stream table] { $v | first 60 } else { [] } } | describe -d | to json -r"
    let out = if $safe.custom { ^$nu.current-exe -l -c $code | complete } else { ^$nu.current-exe -n -c $code | complete }
    if $out.exit_code != 0 { [] } else {
      let d = (try { $out.stdout | from json } catch { {} })
      let rows = ($d.value? | default [])
      $rows | where {|r| ($r.columns? | default null) != null } | each {|r| { columns: $r.columns } }
    }
  }
}

# Rows at `path` inside the pipeline's output. When the pipeline yields no
# rows (a `where` that matches nothing right now), fall back to the pipeline
# without its last stage, whose columns are the same.
def rows-at [prefix: string, path: string]: nothing -> list<record> {
  let rows = (if ($path | is-empty) { probe $prefix } else { probe $"($prefix) | get ($path)" })
  if ($rows | is-not-empty) { return $rows }
  let segs = (segments $prefix)
  if ($segs | length) < 2 { return [] }
  rows-at ($segs | drop 1 | str join "|" | str trim) $path
}

# ── Turning rows into candidates ──────────────────────────────────────────────

def sample-text [c: record]: nothing -> string {
  let v = ($c.value? | default null)
  if $v == null { return "" }
  let s = (match $c.type {
    "filesize" => ($v | into filesize | into string)
    "datetime" | "date" => ($v | into string | str substring 0..18)
    "duration" => (try { $v | into duration | into string } catch { $v | into string })
    "record" | "list" | "table" => ($v | to nuon)
    _ => (try { $v | into string } catch { $v | to nuon })
  })
  $s | str replace -a (char nl) " " | str substring 0..48
}

def column-items [rows: list<record>, exclude: list<string>]: nothing -> list<record> {
  if ($rows | is-empty) { return [] }
  let first = ($rows | first | get columns)
  $first | transpose name c | where name not-in $exclude | each {|r|
    # A provider may say what a column is in words (`string · Edm.String · key`).
    let desc = if ($r.c | get -o description) != null { $r.c.description } else if $r.c.type in [record list table] { $r.c.detailed_type | str substring 0..60 } else {
      let sample = (sample-text $r.c)
      if ($sample | is-empty) { $r.c.type } else { $"($r.c.type) · ($sample)" }
    }
    { value: $r.name, description: $desc }
  }
}

# A column value as something you can paste into a condition.
def literal [c: record]: nothing -> any {
  let v = ($c.value? | default null)
  if $v == null { return null }
  match $c.type {
    "string" => (if ($v =~ '^[\w./@:+-]+$') and ($v !~ '^[\d.-]') { $v } else { $v | to json -r })
    "int" | "float" | "bool" => ($v | into string)
    "filesize" => ($v | into filesize | into string | str replace " " "")
    _ => null
  }
}

def value-items [rows: list<record>, col: string]: nothing -> list<record> {
  $rows | each {|r| $r.columns | get -o $col } | compact | each {|c| literal $c } | compact | uniq | each {|v| { value: $v } }
}

const OPS = {
  string: ["==" "!=" "=~" "!~" like not-like starts-with ends-with not-starts-with not-ends-with in not-in]
  number: ["==" "!=" "<" "<=" ">" ">=" in not-in]
  bool: ["==" "!=" and or xor]
  list: [has not-has in not-in "==" "!="]
}

def ops-for [type: string]: nothing -> list<string> {
  match $type {
    "string" => $OPS.string
    "int" | "float" | "number" | "filesize" | "duration" | "datetime" | "date" => $OPS.number
    "bool" => $OPS.bool
    _ => (if ($type =~ '^(list|table)') { $OPS.list } else { [] })
  }
}

def dedupe []: list<record> -> list<record> { uniq-by value }

def replace-span [position: int, len: int]: nothing -> record { { start: ($position - $len), end: $position } }

# ── Directories to go to when the current one has none ────────────────────────

# `..`, `~`, `-` and zoxide's ranking (`zoxide query -l`, 12 ms, memoised 30 s
# per directory), matched on the whole path or on the last component so that
# `cd nus` finds ~/.config/nushell. Paths with spaces are backtick-quoted the
# way Nushell's own file completer does it.
def dir-fallback [partial: string, position: int]: nothing -> list<record> {
  let fixed = [
    { value: "..", description: "parent" }
    { value: "~", description: "home" }
    { value: "-", description: "previous directory" }
  ]
  let frecent = if (which zoxide | is-empty) { [] } else {
    nu-complete cache $"zoxide:($env.PWD)" 30sec {
      ^zoxide query -l --exclude $env.PWD | lines | first 20
    } | each {|d| { value: ($d | str replace $env.HOME "~"), description: "zoxide" } }
  }
  let by_path = ($fixed ++ $frecent | nu-complete filter $partial)
  let by_name = ($frecent | where {|r| [{ value: ($r.value | path basename) }] | nu-complete filter $partial | is-not-empty })
  $by_path ++ $by_name | uniq-by value | each {|r|
    let v = if ($r.value =~ '\s') { $"`($r.value)`" } else { $r.value }
    { value: $v, description: $r.description, span: (replace-span $position ($partial | str length)), kind: directory }
  }
}

# ── The menu source ───────────────────────────────────────────────────────────

# Candidates for `buffer` at `position`.
#
# `position` is an int on 0.115.1, where the menu source is called
# `{|buffer, position| ...}`, and the `place` record on a build with #18791,
# where the source names `place` and gets it bound by name. The two also
# disagree about `buffer`: `input_mode: cursor_prefix` made it the line up to
# the cursor, the unified inputs hand the whole recorded line, so it is cut
# here. Everything below therefore sees what it always saw — the prefix, and a
# byte offset into it (`str length` and `str substring` are byte-indexed).
export def "nu-complete smart" [buffer: string, position: any]: nothing -> list<record> {
  let position = if ($position | describe) == "int" { $position } else { $position.cursor }
  let buffer = ($buffer | str substring 0..<$position)
  # A custom completer's values (`theme use Cat⌶` → `Catppuccin Macchiato`)
  # arrive unquoted and would be inserted as two arguments; files and
  # carapace's values arrive quoted already.
  let base = (try { $buffer | commandline complete --detailed } catch { [] } | nu-complete quote)
  let segs = (segments $buffer)
  let seg = ($segs | last)
  let prefix = ($segs | drop 1 | str join "|" | str trim)
  let w = (words $seg)
  if ($w.tokens | is-empty) { return ($base | dedupe) }
  let partial = if $w.fresh { "" } else { $w.tokens | last }
  let before = if $w.fresh { $w.tokens } else { $w.tokens | drop 1 }
  let cmd = (resolve-cmd $before)
  if $cmd == null { return ($base | dedupe) }
  let s = $cmd.sig
  let args = ($before | skip $cmd.ntok)
  let slot = (slot-of $args $s)
  let shape = (shape-at $s $slot.index)
  # A row condition is one positional however many words it spans.
  let is_condition = ((shape-at $s 0) =~ 'condition')
  let no_files = ($base | where kind not-in [file directory])

  # A closure parameter's field: `each {|r| $r.na⌶}` → columns.
  let closure_field = ($partial | parse --regex '^\{\|\s*(?<var>\w+)\s*\|.*\$(?<same>\w+)\.(?<path>[\w.]*)$' | get -o 0)
  if $closure_field != null and $closure_field.var == $closure_field.same and ($prefix | is-not-empty) {
    let parts = ($closure_field.path | split row ".")
    let sub = ($parts | drop 1 | str join ".")
    let last = ($parts | last)
    let items = (column-items (rows-at $prefix $sub) [] | nu-complete filter $last | each {|r| $r | insert span (replace-span $position ($last | str length)) })
    return (if ($items | is-empty) { $base | dedupe } else { $items })
  }

  # `cd ⌶` in a leaf folder: parents and the places you go, not NO RECORDS FOUND.
  if $shape == "directory" and ($base | where kind == directory | is-empty) {
    let items = (dir-fallback $partial $position)
    if ($items | is-not-empty) { return $items }
  }

  # Nothing before the command, a flag, or a flag's value: no columns to
  # offer, but the slot may still refuse files — `ps ⌶` takes no positional
  # and `first ⌶` wants a number (the tests found the number rule applied
  # only after a pipe, 2026-09-19).
  if $slot.valued or ($partial | str starts-with "-") or ($prefix | is-empty) {
    let full = ($slot.index >= $s.npos and not $s.rest)
    let bare = (not ($partial | str starts-with "-") and not $slot.valued)
    return (if $bare and ($full or (wants-number $shape)) { $no_files | dedupe } else { $base | dedupe })
  }

  # where / any / all: column, operator, value, and again after and/or.
  if $is_condition {
    let cond = $args
    let rows = (rows-at $prefix "")
    if ($rows | is-empty) { return ($base | dedupe) }
    let cols = ($rows | first | get columns | columns)
    let last = ($cond | last | default "")
    let prev = ($cond | drop 1 | last | default "")
    let at_start = (($cond | is-empty) or ($last in [and or xor not "(" "and" "or"]))
    let field = ($partial | str replace --regex '^\$it\.' "")
    if $at_start {
      let items = (column-items $rows [] | nu-complete filter $field | each {|r| $r | insert span (replace-span $position ($field | str length)) })
      return (if ($items | is-empty) { $base | dedupe } else { $items ++ ($no_files | where kind != operator) })
    }
    let last_col = ($last | str replace --regex '^\$it\.' "")
    if $last_col in $cols and ($partial | is-empty) {
      let type = ($rows | first | get columns | get $last_col | get type)
      let allowed = (ops-for $type)
      let ops = ($base | where kind == operator)
      let narrowed = ($ops | where value in $allowed)
      return (if ($narrowed | is-empty) { $base | dedupe } else { $narrowed })
    }
    let prev_col = ($prev | str replace --regex '^\$it\.' "")
    if $prev_col in $cols and ($last | str starts-with "-" | not $in) and ($last in ($OPS | values | flatten)) {
      let raw = ($partial | str trim --left --char '"' | str trim --left --char "'")
      let items = (value-items $rows $prev_col | nu-complete filter $raw | each {|r| $r | insert span (replace-span $position ($partial | str length)) })
      return (if ($items | is-empty) { $no_files | dedupe } else { $items })
    }
    return ($base | dedupe)
  }

  # Cell-path slots: get, select, reject, sort-by, update, insert, str trim ...
  if ($shape =~ 'cell-path') {
    let parts = ($partial | split row ".")
    let sub = ($parts | drop 1 | str join ".")
    let last = ($parts | last)
    let used = if $s.rest and $slot.index >= $s.npos { $args | where {|a| not ($a | str starts-with "-") } } else { [] }
    let items = (column-items (rows-at $prefix $sub) $used | nu-complete filter $last | each {|r| $r | insert span (replace-span $position ($last | str length)) })
    return (if ($items | is-empty) { $no_files | dedupe } else { $items })
  }

  if $slot.index >= $s.npos and not $s.rest { return ($no_files | dedupe) }
  if (wants-number $shape) { return ($no_files | dedupe) }
  $base | dedupe
}

# `first ⌶`, `skip ⌶`, `sleep ⌶`: a number is wanted, not a file.
def wants-number [shape: string]: nothing -> bool {
  ($shape =~ '^(oneof<)?(int|number|float|duration|filesize|range)[,>]?') and ($shape !~ 'path|string|glob|any')
}
