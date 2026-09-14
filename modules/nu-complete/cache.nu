# cache — memoisation for completion sources
#
# Two layers, both keyed by a string:
#
#   nu-complete cache <key> <ttl> { closure }   session memo in `stor`, the
#       in-memory SQLite every Nushell process has. It survives across
#       completer calls (verified: a menu source re-runs on every keystroke
#       while the menu is open, and stor kept its rows) and dies with the
#       shell. Values are stored as nuon, so keep them small — a few hundred
#       records decode in about a millisecond, sixteen thousand do not.
#
#   nu-complete cache-dir                        $nu.cache-dir/nu-complete, for
#       files that outlive the shell: SQLite databases built from a tool's
#       own cache (see completions/brew.nu). `open x.db | query db` answers a
#       LIKE query over 16k rows in 1-3 ms, which is why big lists live there
#       and not in stor (`stor import` wipes every other stor table).

const TABLE = "nu_complete_memo"

def ensure-table []: nothing -> nothing {
  try { stor create -t $TABLE -c { key: str, value: str, at: int } | ignore }
}

# Run `gen` unless a value younger than `ttl` is memoised under `key`.
export def "nu-complete cache" [key: string, ttl: duration, gen: closure]: nothing -> any {
  ensure-table
  let k = ($key | hash md5)
  let now = (date now | into int)
  let hit = (stor open | query db $"select value, at from ($TABLE) where key = :k" -p { k: $k })
  if ($hit | is-not-empty) and (($now - $hit.0.at) < ($ttl | into int)) {
    return ($hit.0.value | from nuon)
  }
  let v = (do $gen)
  stor delete -t $TABLE -w $"key = '($k)'" | ignore
  { key: $k, value: ($v | to nuon), at: $now } | stor insert -t $TABLE | ignore
  $v
}

# Drop every memoised value (after changing a source, for instance).
export def "nu-complete cache clear" []: nothing -> nothing {
  ensure-table
  stor delete -t $TABLE -w "1 = 1" | ignore
}

# Directory for caches that outlive the shell.
export def "nu-complete cache-dir" []: nothing -> path {
  let d = ($nu.cache-dir | path join nu-complete)
  if not ($d | path exists) { mkdir $d }
  $d
}

# True when `target` is missing or older than `source`.
export def "nu-complete stale" [target: path, source: path]: nothing -> bool {
  if not ($target | path exists) { return true }
  if not ($source | path exists) { return false }
  (ls -D $source | get 0.modified) > (ls -D $target | get 0.modified)
}

# What the engine has cached, and where.
export def "nu-complete status" []: nothing -> table<what: string, where: string, size: string, age: string> {
  ensure-table
  let memo = (stor open | query db ("select count(*) as n from " + $TABLE) | get 0.n)
  let files = (ls (nu-complete cache-dir) | each {|f|
    { what: ($f.name | path basename), where: $f.name, size: ($f.size | into string), age: ((date now) - $f.modified | into string) }
  })
  [{ what: "session memo (stor)", where: $"($memo) entries", size: "", age: "" }] ++ $files
}
