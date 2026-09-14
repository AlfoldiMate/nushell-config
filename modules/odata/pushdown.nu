# pushdown.nu — Nushell expressions → OData literals, $filter, and the hints
# a pre_execution hook leaves for `odata get`.
#
# `where` cannot be overloaded in Nushell 0.115 (it is a parser keyword), and
# a pre_execution hook cannot change the line about to run — but the `$env`
# it sets is visible to that line (both verified 2026-09-11). So the hook
# reads the whole line with `ast --flatten` (0.5 ms), records the stages
# that follow each `odata` call as a plan, and `odata get` turns as many of
# them as it can into query options. The Nushell stages still run on the
# result: pushdown only shrinks what is transferred, never what is returned.
#
# Row conditions are translated from their source text by a small
# recursive-descent parser (below), not from the AST: `ast --json` stores a
# row condition as a block id, not as an expression tree.

use metadata.nu *

# ── Literals ──────────────────────────────────────────────────────────────────

def quote [s: string]: nothing -> string { "'" + ($s | str replace -a "'" "''") + "'" }

# A Nushell value as an OData literal for a property of Edm type `edm`
# (null when unknown). V2 needs type suffixes and typed string literals.
export def "literal" [v: any, edm: any, version: string]: nothing -> string {
  let t = (edm-short $edm | default "")
  let kind = ($v | describe)
  if $v == null { return "null" }
  if $t == "Edm.String" { return (quote ($v | into string)) }
  if $t == "Edm.Guid" { return (if $version == "2" { $"guid'($v)'" } else { $v | into string }) }
  if $t in ["Edm.DateTime" "Edm.DateTimeOffset" "Edm.Date"] {
    let iso = (if $kind == "datetime" { $v | format date "%Y-%m-%dT%H:%M:%S%:z" } else { $v | into string })
    if $version == "2" {
      let plain = ($iso | str replace --regex '(Z|[+-]\d\d:\d\d)$' '')
      return $"datetime'(if ($plain | str contains 'T') { $plain } else { $plain + 'T00:00:00' })'"
    }
    return $iso
  }
  if $t == "Edm.Int64" and $version == "2" { return $"($v)L" }
  if $t == "Edm.Decimal" and $version == "2" { return $"($v)M" }
  if $t == "Edm.Double" and $version == "2" { return $"($v)d" }
  if $t == "Edm.Single" and $version == "2" { return $"($v)f" }
  if $t == "Edm.Boolean" { return ($v | into bool | into string) }
  if ($t | str starts-with "Edm.") { return ($v | into string) }
  if ($t | is-not-empty) and $kind == "string" and $version == "4" { return $"($edm)'($v)'" }   # enum member
  match $kind {
    "string" => (quote $v)
    "int" | "float" => ($v | into string)
    "bool" => ($v | into string)
    "datetime" => (literal $v "Edm.DateTimeOffset" $version)
    _ => (quote ($v | into string))
  }
}

# ── Row conditions → $filter ──────────────────────────────────────────────────

const TOKEN_RE = '(?<str>"(?:[^"\\]|\\.)*"|' + "'[^']*')" + '|(?<date>\d{4}-\d{2}-\d{2}(?:T\d{2}:\d{2}(?::\d{2})?(?:Z|[+-]\d{2}:\d{2})?)?)|(?<num>-?\d+(?:\.\d+)?)|(?<op>==|!=|<=|>=|=~|!~|<|>)|(?<word>[\w$.-]+)|(?<punct>[()\[\],])'

# Tokens of a condition: [{ kind, text }]. Null when any character is not a token.
def tokenize [cond: string]: nothing -> any {
  let toks = ($cond | parse --regex $TOKEN_RE | each {|r|
    let hit = ($r | transpose kind text | where text != null and text != "" | get -o 0)
    if $hit == null { null } else { $hit }
  } | compact)
  let covered = ($toks | get text | str join | str replace -a --regex '\s' '' | str length)
  let expected = ($cond | str replace -a --regex '\s' '' | str length)
  if $covered != $expected { return null }
  $toks
}

def tok [toks: list, pos: int]: nothing -> record { $toks | get -o $pos | default { kind: "end", text: "" } }

def fail [msg: string] { error make { msg: $msg } }

def unquote [s: string]: nothing -> string {
  if ($s | str starts-with '"') { $s | from json } else { $s | str substring 1..-2 }
}

# The Edm type of `a/b/c` inside `type` (an entry of schema.types), or null.
# A path through a collection navigation cannot be filtered directly.
def field-type [ctx: record, path: string]: nothing -> any {
  if $ctx.type == null { return null }
  mut t: any = $ctx.type
  mut edm: any = null
  for seg in ($path | split row "/") {
    if $t == null { return null }
    let p = ($t.props | where name == $seg | get -o 0)
    if $p != null {
      $edm = $p.type
      let short = (edm-short $p.type)
      $t = ($ctx.schema.complex | get -o $short | default null)
    } else {
      let n = ($t.navs | where name == $seg | get -o 0)
      if $n == null { fail $"unknown field ($path)" }
      if $n.collection { fail $"($path) goes through a collection" }
      $edm = null
      $t = ($ctx.schema.types | get -o $n.target | default null)
    }
  }
  $edm
}

# For `odata get`: the Edm type at the end of a cell path, or null when the
# path is unknown, goes through a collection, or ends on a complex type
# (a server cannot order by or compare a whole complex value).
export def "field-edm" [schema: any, type: any, path: string]: nothing -> any {
  let ctx = { schema: ($schema | default { types: {}, complex: {}, enums: {} }), type: $type }
  let edm = (try { field-type $ctx ($path | str replace -a "." "/") } catch { return null })
  if $edm == null { return null }
  let short = (edm-short $edm)
  if ($short | str starts-with "Edm.") or (($ctx.schema.enums | get -o $short) != null) { $edm } else { null }
}

def field-name [text: string]: nothing -> string {
  $text | str replace --regex '^\$it\.' "" | str replace -a "." "/"
}

# A bare word on the left of an operator is a column; on the right it is a
# string, unless it is written `$it.column`.
def is-field [t: record]: nothing -> bool {
  $t.kind == "word" and $t.text not-in [true false null and or not in not-in starts-with ends-with like not-like has not-has] and ($t.text !~ '^-?\d')
}
def is-column-ref [t: record]: nothing -> bool { $t.kind == "word" and ($t.text | str starts-with "$it.") }

def literal-of [ctx: record, t: record, edm: any]: nothing -> string {
  let v = (match $t.kind {
    "str" => (unquote $t.text)
    "num" => (if ($t.text | str contains ".") { $t.text | into float } else { $t.text | into int })
    "date" => $t.text
    "word" => (match $t.text { "true" => true, "false" => false, "null" => null, _ => $t.text })
    _ => (fail $"unexpected ($t.text)")
  })
  let edm = (if $edm == null and $t.kind == "date" { "Edm.DateTimeOffset" } else { $edm })
  literal $v $edm $ctx.version
}

const MIRROR = { "<": ">", ">": "<", "<=": ">=", ">=": "<=", "==": "==", "!=": "!=" }
const OPS = { "==": "eq", "!=": "ne", "<": "lt", "<=": "le", ">": "gt", ">=": "ge" }

def p-comparison [ctx: record, toks: list, pos: int]: nothing -> record {
  let a = (tok $toks $pos)
  let op = (tok $toks ($pos + 1))
  let b = (tok $toks ($pos + 2))
  # literal op field → field mirrored-op literal
  if not (is-field $a) and (is-column-ref $b) and $op.kind == "op" and ($op.text in ($MIRROR | columns)) {
    return (p-comparison $ctx [$b ($op | update text ($MIRROR | get $op.text)) $a] 0 | update pos ($pos + 3))
  }
  if not (is-field $a) { fail "expected a column" }
  let f = (field-name $a.text)
  let edm = (field-type $ctx $f)
  if $edm != null and not ((edm-short $edm | str starts-with "Edm.") or (($ctx.schema.enums | get -o (edm-short $edm)) != null)) { fail $"($f) is not a primitive value" }
  if $op.kind == "op" {
    let rhs = (if (is-column-ref $b) { field-name $b.text } else { literal-of $ctx $b $edm })
    let s = (match $op.text {
      "=~" => (if $ctx.version == "2" { $"substringof\(($rhs),($f)\) eq true" } else { $"contains\(($f),($rhs)\)" })
      "!~" => (if $ctx.version == "2" { $"substringof\(($rhs),($f)\) eq false" } else { $"not contains\(($f),($rhs)\)" })
      _ => $"($f) ($OPS | get $op.text) ($rhs)"
    })
    return { s: $s, pos: ($pos + 3) }
  }
  if $op.kind == "word" and $op.text in [starts-with ends-with] {
    let rhs = (literal-of $ctx $b $edm)
    let fn = (if $op.text == "starts-with" { "startswith" } else { "endswith" })
    return { s: $"($fn)\(($f),($rhs)\)", pos: ($pos + 3) }
  }
  if $op.kind == "word" and $op.text in [in not-in] {
    if $b.text != "[" { fail "expected a list" }
    mut i = ($pos + 3)
    mut items = []
    loop {
      let t = (tok $toks $i)
      if $t.text == "]" { break }
      if $t.text == "," { $i += 1; continue }
      if $t.kind == "end" { fail "unterminated list" }
      $items ++= [(literal-of $ctx $t $edm)]
      $i += 1
    }
    if ($items | is-empty) { fail "empty list" }
    let s = (if $ctx.version == "2" { "(" + ($items | each {|v| $"($f) eq ($v)" } | str join " or ") + ")" } else { $"($f) in \(($items | str join ',')\)" })
    return { s: (if $op.text == "not-in" { $"not ($s)" } else { $s }), pos: ($i + 1) }
  }
  if $op.kind == "word" and $op.text in [has not-has] and $ctx.version == "4" {
    let rhs = (literal-of $ctx $b ($edm | default "" | str replace --regex '^Collection\((.*)\)$' '$1' | if ($in | is-empty) { null } else { $in }))
    let s = $"($f)/any\(e:e eq ($rhs)\)"
    return { s: (if $op.text == "not-has" { $"not ($s)" } else { $s }), pos: ($pos + 3) }
  }
  # a bare boolean column
  if $edm != null and (edm-short $edm) == "Edm.Boolean" { return { s: $"($f) eq true", pos: ($pos + 1) } }
  fail $"unsupported operator ($op.text)"
}

def p-not [ctx: record, toks: list, pos: int]: nothing -> record {
  let t = (tok $toks $pos)
  if $t.text == "not" and $t.kind == "word" {
    let r = (p-not $ctx $toks ($pos + 1))
    return { s: $"not \(($r.s)\)", pos: $r.pos }
  }
  if $t.text == "(" {
    let r = (p-or $ctx $toks ($pos + 1))
    if (tok $toks $r.pos).text != ")" { fail "expected )" }
    return { s: $"\(($r.s)\)", pos: ($r.pos + 1) }
  }
  p-comparison $ctx $toks $pos
}

def p-and [ctx: record, toks: list, pos: int]: nothing -> record {
  mut r = (p-not $ctx $toks $pos)
  loop {
    let t = (tok $toks $r.pos)
    if not ($t.kind == "word" and $t.text == "and") { break }
    let n = (p-not $ctx $toks ($r.pos + 1))
    $r = { s: $"($r.s) and ($n.s)", pos: $n.pos }
  }
  $r
}

def p-or [ctx: record, toks: list, pos: int]: nothing -> record {
  mut r = (p-and $ctx $toks $pos)
  loop {
    let t = (tok $toks $r.pos)
    if not ($t.kind == "word" and $t.text == "or") { break }
    let n = (p-and $ctx $toks ($r.pos + 1))
    $r = { s: $"($r.s) or ($n.s)", pos: $n.pos }
  }
  $r
}

# A Nushell row condition (`Age > 30 and Name =~ "Ru"`) as an OData $filter,
# or null when any part of it has no OData equivalent. `type` is the entity
# type record (schema.types.X) or null; without it literals are typed by
# their Nushell shape only.
export def "filter-from-nu" [cond: string, schema: any, type: any, version: string]: nothing -> any {
  let toks = (tokenize $cond)
  if $toks == null or ($toks | is-empty) { return null }
  let ctx = { schema: ($schema | default { types: {}, complex: {}, enums: {} }), type: $type, version: $version }
  try {
    let r = (p-or $ctx $toks 0)
    if $r.pos != ($toks | length) { return null }
    $r.s
  } catch {|e| if ($env.ODATA_DEBUG? | default "false") == "true" { print -e $"odata filter: ($e.msg)" }; null }
}

# ── The plan a hook leaves for `odata get` ────────────────────────────────────

const VALUE_FLAGS = [--filter -f --select -c --expand -e --orderby -o --top -t --skip -k --search --param -P --headers -H --service -s --nav]
const NO_PUSH_FLAGS = [--raw -r --count --url -u]

# Segments of a line: [{ head, tokens: [{content, shape, start, end}], text }].
def segments [line: string]: nothing -> list<record> {
  let toks = (try { ast --flatten $line } catch { return [] })
  mut segs = []
  mut cur = []
  mut prev_end = 0
  for t in $toks {
    let gap = ($line | str substring $prev_end..<($t.span.start))
    if $t.shape == "shape_pipe" or ($gap =~ '[;\n]') {
      if ($cur | is-not-empty) { $segs ++= [$cur] }
      $cur = []
    }
    $prev_end = $t.span.end
    if $t.shape == "shape_pipe" { continue }
    $cur ++= [$t]
  }
  if ($cur | is-not-empty) { $segs ++= [$cur] }
  $segs | each {|s|
    let a = ($s | first | get span.start)
    let b = ($s | last | get span.end)
    # `ast --flatten` splits a cell path into its members and drops the dots
    # (`HomeAddress.City` → `HomeAddress`, `City`), so words are rebuilt from
    # the spans: tokens with no whitespace between them are one word.
    let words = ($s | reduce -f [] {|t, acc|
      let last = ($acc | last | default null)
      let gap = (if $last == null { " " } else { $line | str substring $last.end..<($t.span.start) })
      if $last != null and ($gap !~ '\s') { ($acc | drop 1) ++ [{ text: ($last.text + $gap + $t.content), end: $t.span.end }] } else { $acc ++ [{ text: $t.content, end: $t.span.end }] }
    } | get text)
    { head: ($s | first | get content), tokens: ($s | each {|t| { content: $t.content, shape: $t.shape, start: $t.span.start, end: $t.span.end } }), words: $words, text: ($line | str substring $a..<$b) }
  }
}

# The positionals of an `odata …` segment (entity, key, navs), and whether
# it uses a flag that rules pushdown out.
def odata-args [seg: record]: nothing -> record {
  let toks = ($seg.tokens | skip 1 | if ($in | get -o 0.content) == "get" { $in | skip 1 } else { $in })
  mut positionals = []
  mut skip_next = false
  mut blocked = false
  for t in $toks {
    if $skip_next { $skip_next = false; continue }
    if $t.shape == "shape_flag" or ($t.content | str starts-with "-") {
      if $t.content in $NO_PUSH_FLAGS { $blocked = true }
      if $t.content in $VALUE_FLAGS { $skip_next = true }
      continue
    }
    $positionals ++= [($t.content | str trim -c '"' | str trim -c "'")]
  }
  { positionals: $positionals, blocked: $blocked }
}

# Words of a segment after its head, with quotes stripped; flags kept.
def seg-words [seg: record]: nothing -> list<string> {
  $seg.words | skip 1 | each {|w| $w | str trim -c '"' | str trim -c "'" }
}

# The condition of a `where`: the row-condition text as it is, or the body
# of a closure (`{|p| $p.Age > 30 }`) with `$p.` rewritten to `$it.`. Null
# when the closure uses its parameter in any other way.
def normalise-cond [text: string]: nothing -> any {
  let m = ($text | parse --regex '^\s*\{\s*\|\s*(?<v>\w+)\s*\|(?<body>[\s\S]*)\}\s*$' | get -o 0)
  if $m == null { return (if ($text | str trim | str starts-with "{") { null } else { $text }) }
  let body = ($m.body | str replace -a $"$($m.v)." '$it.')
  if ($body | str contains $"$($m.v)") { null } else { $body }
}

const PATH_RE = '^\w+(\.\w+)*$'
def first-seg [w: string]: nothing -> string { $w | str replace --regex '^\$it\.' "" | split row "." | first }

# What follows each `odata` call, as an ordered list of stages:
#   { kind: where, cond } | { kind: select, cols } | { kind: sort, cols, reverse }
#   | { kind: top, n } | { kind: skip, n }
# `select`/`get`/`sort-by` columns may be cell paths (`HomeAddress.City`,
# `Airline.Name`); `odata get` turns a navigation among them into $expand.
# `where` accepts the closure form; `is-empty`, `is-not-empty` and `columns`
# need one row and become { kind: top, n: 1 }; the module's own `expand`
# stage is { kind: expand, navs } and may sit anywhere; `length` is
# { kind: count } and ends the plan; `find word` is { kind: search, term }.
# Stops at the first stage that cannot be pushed; `odata get` stops again at
# the first it cannot translate. Returns [{ positionals, stages }].
export def "odata pushdown plan" [line: string]: nothing -> list<record> {
  let segs = (segments $line)
  mut plans = []
  for i in 0..<($segs | length) {
    let seg = ($segs | get $i)
    if not ($seg.head == "odata" or $seg.head == "odata get") { continue }
    let args = (odata-args $seg)
    if $args.blocked { continue }
    mut stages = []
    mut have_top = false
    mut have_skip = false
    mut selected: list<string> = []
    for j in ($i + 1)..<($segs | length) {
      let s = ($segs | get $j)
      let words = (seg-words $s)
      let stage = (match $s.head {
        "where" => (
          if $have_top or $have_skip { null } else {
            let cond = (normalise-cond ($s.text | str substring 5..))
            if $cond == null { null } else { { kind: "where", cond: $cond } }
          }
        )
        "select" | "get" => (
          if ($words | any {|w| $w !~ $PATH_RE }) or ($words | is-empty) or ($selected | is-not-empty) { null } else { { kind: "select", cols: $words } }
        )
        "sort-by" => (
          if $have_top or $have_skip { null } else {
            let flags = ($words | where {|w| $w | str starts-with "-" })
            let cols = ($words | where {|w| not ($w | str starts-with "-") })
            if ($flags | any {|f| $f not-in [-r --reverse] }) or ($cols | is-empty) or ($cols | any {|c| $c !~ $PATH_RE }) { null } else { { kind: "sort", cols: $cols, reverse: ($flags | is-not-empty) } }
          }
        )
        "is-empty" | "is-not-empty" | "columns" => (if ($words | is-not-empty) { null } else { { kind: "top", n: 1 } })
        # `expand Trips "Friends($top=2)"`: the module's own stage, any position
        "expand" => (
          if ($words | is-empty) or ($words | any {|w| ($w | str starts-with "-") or ($w !~ '^\w+(\(.*\))?$') }) { null }
          else { { kind: "expand", navs: $words } }
        )
        # `length`: the server counts, nothing else can follow on the server
        "length" => (if $have_top or $have_skip or ($words | is-not-empty) { null } else { { kind: "count" } })
        # `find word`: one plain term, V4 $search (odata get decides)
        "find" => (
          if $have_top or $have_skip or ($words | length) != 1 or ($words.0 | str starts-with "-") or ($words.0 =~ '^-?\d') { null } else { { kind: "search", term: $words.0 } }
        )
        "first" | "take" => (
          if ($words | length) > 1 or ($words | any {|w| $w !~ '^\d+$' }) { null } else { { kind: "top", n: ($words | get -o 0 | default "1" | into int) } }
        )
        "skip" => (
          if $have_top or ($words | length) != 1 or ($words.0 !~ '^\d+$') { null } else { { kind: "skip", n: ($words.0 | into int) } }
        )
        _ => null
      })
      if $stage == null { break }
      # a stage after `select` may only touch selected columns
      if ($selected | is-not-empty) and $stage.kind in [where sort] {
        let used = (if $stage.kind == "sort" { $stage.cols | each {|c| first-seg $c } } else { tokenize $stage.cond | default [] | where kind == word | get text | each {|w| first-seg $w } })
        if ($used | any {|u| $u not-in $selected and $u not-in [and or not in not-in starts-with ends-with true false null] }) { break }
      }
      match $stage.kind {
        "top" => { $have_top = true }
        "skip" => { $have_skip = true }
        "select" => { $selected = ($stage.cols | each {|c| first-seg $c }) }
        _ => ({})
      }
      $stages ++= [$stage]
      if $stage.kind == "count" { break }
    }
    if ($stages | is-not-empty) { $plans ++= [{ positionals: $args.positionals, stages: $stages }] }
  }
  $plans
}
