# odata — OData V2 and V4 services (SAP Gateway included) as Nushell tables
#
#   odata <entity> [key] [nav...]         read: a table, or a record for one key
#   odata get <entity> ... [--filter --select --expand --orderby --top --skip --search --all --count --raw --url]
#   … | expand <nav> [nav...]             navigation columns; pushed as $expand, or fetched per row
#   odata count <entity> [--filter]       how many, without fetching
#   odata create <entity>                 POST the record piped in
#   odata update <entity> <key>           PATCH (or PUT/MERGE) the record piped in
#   odata delete <entity> <key>
#   odata call <name> [params] [--on …]   function import / action, bound ones on an entity or a piped row
#   odata raw <path>                      any request, the response record
#   odata services | entities | schema    what the service offers (from cached $metadata)
#   odata service add | use | remove | show
#   odata catalog                         SAP Gateway: every service on the system
#   odata refresh                         re-fetch $metadata
#
# One HTTP request per call through Nushell's `http` (no plugin). $metadata
# is parsed once (metadata.nu) and cached as JSON for ODATA_METADATA_TTL;
# everything Tab offers — entities, fields, navigations, enum values — comes
# from that cache, never from the network. Row conditions typed after the
# call (`odata People | where … | first 5`) reach the server through the
# pre_execution hook in modules/odata (activate) (pushdown.nu): where, select/get,
# sort-by, first/skip, expand, length, find → $filter, $select, $orderby,
# $top/$skip, $expand, /$count, $search. docs/concepts/odata.md has the design
# and the measurements; your settings.nu the knobs.

use metadata.nu *
use pushdown.nu *
export use pushdown.nu ["odata pushdown plan"]

# ── Settings your settings.nu, with defaults ────────────────────────────────

def setting [name: string, default: any]: nothing -> any {
  let v = ($env | get -o $name)
  if $v == null { return $default }
  match [($default | describe) ($v | describe)] {
    ["bool" "string"] => ($v == "true")
    ["int" "string"] => ($v | into int)
    ["duration" "string"] => ($v | into duration)
    _ => $v
  }
}

def debug [msg: string] { if (setting ODATA_DEBUG false) { print -e $"(ansi dark_gray)odata: ($msg)(ansi reset)" } }

# ── Session memo (stor) ───────────────────────────────────────────────────────

const MEMO = "odata_memo"

def ensure-memo []: nothing -> nothing { try { stor create -t $MEMO -c { key: str, value: str, at: int } | ignore } }

def memo [key: string, ttl: duration, gen: closure]: nothing -> any {
  ensure-memo
  let now = (date now | into int)
  let hit = (stor open | query db $"select value, at from ($MEMO) where key = :k" -p { k: $key })
  if ($hit | is-not-empty) and (($now - $hit.0.at) < ($ttl | into int)) { return ($hit.0.value | from nuon) }
  let v = (do $gen)
  stor delete -t $MEMO -w $"key = '($key)'" | ignore
  { key: $key, value: ($v | to nuon), at: $now } | stor insert -t $MEMO | ignore
  $v
}

# The memoised value, or null when absent or older than ttl (no generator).
def memo-peek [key: string, ttl: duration]: nothing -> any {
  ensure-memo
  let hit = (stor open | query db $"select value, at from ($MEMO) where key = :k" -p { k: $key })
  if ($hit | is-empty) or (((date now | into int) - $hit.0.at) >= ($ttl | into int)) { null } else { $hit.0.value | from nuon }
}

def memo-forget [key: string]: nothing -> nothing { ensure-memo; stor delete -t $MEMO -w $"key = '($key)'" | ignore }

# ── The registry ──────────────────────────────────────────────────────────────
# Services come from $env.ODATA_SERVICES your settings.nu; closures allowed
# for secrets) merged over $nu.data-dir/.state/odata/services.nuon in your own
# config directory, which
# `odata service add` writes. The current one is $env.ODATA_SERVICE.
#
# NUON, because this is the one file here a person opens and edits: it holds
# the URLs and the auth they typed. It costs nothing at this size — 160 B
# parses in 81 µs as NUON against 51 µs as JSON. The schema cache below is the
# other way round and stays JSON.

def state-dir []: nothing -> path {
  let d = ($nu.data-dir | path join .state odata)
  if not ($d | path exists) { mkdir $d }
  $d
}
def registry-file []: nothing -> path { state-dir | path join services.nuon }

# The registry was JSON until this file switched formats. It is read for as
# long as it is there and removed by the next write, so nobody has to migrate
# anything by hand.
def legacy-registry-file []: nothing -> path { state-dir | path join services.json }

def stored-services []: nothing -> record {
  let f = (registry-file)
  if ($f | path exists) { return (open $f) }
  let old = (legacy-registry-file)
  if ($old | path exists) { open $old } else { ({}) }
}

# Indented, so a diff of this file is readable and `service add` does not
# rewrite every line.
def save-services [reg: record]: nothing -> nothing {
  $reg | to nuon --indent 2 | save -f (registry-file)
  let old = (legacy-registry-file)
  if ($old | path exists) { rm -f $old }
}
def all-services []: nothing -> record { stored-services | merge (setting ODATA_SERVICES {}) }

def normalise-service [name: string, s: record]: nothing -> record {
  let url = ($s.url | str trim)
  {
    name: $name
    url: (if ($url | str ends-with "/") { $url } else { $url + "/" })
    version: ($s.version? | default null | if $in == null { null } else { $in | into string | str substring 0..1 })
    auth: ($s.auth? | default {})
    headers: ($s.headers? | default {})
    params: ($s.params? | default {})
    sap: ($s.sap? | default ($url =~ '/sap/opu/odata'))
    description: ($s.description? | default "")
  }
}

def current-name []: nothing -> any { $env.ODATA_SERVICE? }

# The service named, or the current one.
def service-of [name: any]: nothing -> record {
  let n = ($name | default (current-name))
  if $n == null {
    error make { msg: "no OData service selected", help: "odata service use <name>, or --service <name>; `odata services` lists the registry, `odata service add <name> <url>` extends it" }
  }
  let s = (all-services | get -o $n)
  if $s == null {
    error make { msg: $"unknown OData service '($n)'", help: "`odata services` lists the registry; `odata service add <name> <url>` extends it" }
  }
  normalise-service $n $s
}

# ── Schema cache ──────────────────────────────────────────────────────────────

def cache-dir []: nothing -> path {
  let d = ($nu.cache-dir | path join odata)
  if not ($d | path exists) { mkdir $d }
  $d
}
def schema-file [svc: record]: nothing -> path { cache-dir | path join $"($svc.name).json" }

# The parsed $metadata of a service: from the JSON cache while younger than
# ODATA_METADATA_TTL, else fetched (about 1 s on the public services).
#
# JSON and not NUON, against the rule for everything else here, because this
# file is machine-written, nobody reads it, and it is on the Tab path — the
# entity sets, fields and navigations come out of it. Measured on the cached
# Northwind schema (25 kB): 0.47 ms to parse as JSON, 3.0 ms as NUON. Same
# shape at every size tried; NUON's parser costs about 6x per byte.
def schema-for [svc: record, --refresh]: nothing -> record {
  let f = (schema-file $svc)
  let ttl = (setting ODATA_METADATA_TTL 7day)
  if not $refresh and ($f | path exists) and (((date now) - (ls -D $f | get 0.modified)) < $ttl) {
    return (memo $"schema:($svc.name)" 60sec { open $f })
  }
  debug $"fetching ($svc.url)$metadata"
  let r = (request $svc GET '$metadata' {} --accept "application/xml")
  let schema = (parse-metadata $r.body | insert fetched_at (date now | format date "%+") | insert url $svc.url)
  $schema | to json | save -f $f
  memo-forget $"schema:($svc.name)"
  $schema
}

# Schema or null when the service cannot be reached; the commands that only
# need it for convenience (quoting keys, converting V2 values) go on without.
def schema-maybe [svc: record]: nothing -> any { try { schema-for $svc } catch {|e| debug $"no schema: ($e.msg)"; null } }

def version-of [svc: record, schema: any]: nothing -> string {
  $svc.version | default ($schema | get -o version) | default "4"
}

# ── Transport ─────────────────────────────────────────────────────────────────

def secret [v: any]: nothing -> string { if ($v | describe) == "closure" { do $v | into string | str trim } else { $v | into string } }

def auth-headers [svc: record]: nothing -> record {
  let a = $svc.auth
  let kind = ($a.type? | default (if ($a.user? | default null) != null { "basic" } else if ($a.token? | default null) != null { "bearer" } else { "none" }))
  match $kind {
    "basic" => { Authorization: ("Basic " + ($"($a.user):(secret ($a.password? | default ''))" | encode base64)) }
    "bearer" => { Authorization: ("Bearer " + (secret $a.token)) }
    _ => ({})
  }
}

# Percent-encode a query value, keeping the characters OData syntax needs readable.
def encode-value [v: string]: nothing -> string {
  $v | url encode --all
  | str replace -a "%24" "$" | str replace -a "%28" "(" | str replace -a "%29" ")" | str replace -a "%2C" ","
  | str replace -a "%3D" "=" | str replace -a "%3B" ";" | str replace -a "%27" "'" | str replace -a "%2F" "/"
  | str replace -a "%3A" ":" | str replace -a "%2E" "." | str replace -a "%2D" "-" | str replace -a "%5F" "_"
}

def build-url [svc: record, path: string, params: record]: nothing -> string {
  let base = (if ($path =~ '^https?://') { $path } else { $svc.url + ($path | str trim -l -c "/") })
  let qs = ($svc.params | merge $params | transpose k v | where v != null | each {|r| $"($r.k)=(encode-value ($r.v | into string))" } | str join "&")
  if ($qs | is-empty) { $base } else if ($base | str contains "?") { $base + "&" + $qs } else { $base + "?" + $qs }
}

def content-type-of [headers: table]: nothing -> string { $headers | where name == content-type | get -o 0.value | default "" }

def odata-error-message [body: any]: nothing -> string {
  let b = (if ($body | describe) == "string" { try { $body | from json } catch { null } } else { $body })
  if $b == null { return ($body | into string | str substring 0..300) }
  let e = ($b | get -o error)
  if $e == null { return ($b | to json -r | str substring 0..300) }
  let m = ($e | get -o message)
  let msg = (if ($m | describe) =~ '^record' { $m | get -o value | default ($m | to json -r) } else { $m | into string })
  let inner = ($e | get -o innererror | get -o errordetails | default [] | each {|d| $d | get -o message } | compact | str join "; ")
  if ($inner | is-empty) { $msg } else { $"($msg) \(($inner)\)" }
}

# One HTTP request. Returns { status, headers, body, url }; raises on 4xx/5xx
# with the service's own message unless --allow.
def request [
  svc: record, method: string, path: string, params: record
  --body: any, --headers: record = {}, --accept: string = "application/json", --allow
]: nothing -> record {
  let url = (build-url $svc $path $params)
  let h = ({ Accept: $accept } | merge (auth-headers $svc) | merge $svc.headers | merge $headers)
  let t0 = (date now)
  let r = (match $method {
    "GET" => (http get --full -e -r -H $h $url)
    "POST" => (http post --full -e -r -H $h -t application/json $url ($body | default {} | to json -r))
    "PATCH" => (http patch --full -e -r -H $h -t application/json $url ($body | default {} | to json -r))
    "PUT" => (http put --full -e -r -H $h -t application/json $url ($body | default {} | to json -r))
    "DELETE" => (http delete --full -e -r -H $h $url)
    _ => (error make { msg: $"unsupported HTTP method ($method)" })
  })
  debug $"($method) ($url) → ($r.status) ((date now) - $t0)"
  let ct = (content-type-of $r.headers.response)
  let body = (if ($ct | str contains "json") and ($r.body | describe) == "string" and ($r.body | str trim | is-not-empty) { try { $r.body | from json } catch { $r.body } } else { $r.body })
  if $r.status >= 400 and not $allow {
    error make { msg: $"($method) ($url) → ($r.status): (odata-error-message $body)", help: "odata raw <path> --allow-errors returns the response as it is" }
  }
  { status: $r.status, headers: $r.headers.response, body: $body, url: $url }
}

# SAP Gateway protects writes with a CSRF token bound to the session cookie:
# fetched with `X-CSRF-Token: Fetch` on the service root, memoised 25 min.
def csrf-headers [svc: record]: nothing -> record {
  if not ($svc.sap or ($svc | get -o csrf | default false)) { return ({}) }
  memo $"csrf:($svc.name)" 25min {
    let h = ({ "X-CSRF-Token": "Fetch", Accept: "application/json" } | merge (auth-headers $svc) | merge $svc.headers)
    let r = (http get --full -e -r -H $h (build-url $svc "" {}))
    let token = ($r.headers.response | where name == x-csrf-token | get -o 0.value)
    let cookie = ($r.headers.response | where name == set-cookie | get value | each {|c| $c | split row ";" | first } | str join "; ")
    if $token == null { ({}) } else { { "X-CSRF-Token": $token, Cookie: $cookie } }
  }
}

# A write, with the CSRF dance for SAP and one retry when the token expired.
def write [svc: record, method: string, path: string, params: record, --body: any, --headers: record = {}]: nothing -> record {
  let h = ($headers | merge (csrf-headers $svc))
  let r = (request $svc $method $path $params --body $body --headers $h --allow)
  if $r.status == 403 and ($r.headers | where name == x-csrf-token | get -o 0.value | default "" | str lowercase) == "required" {
    memo-forget $"csrf:($svc.name)"
    return (request $svc $method $path $params --body $body --headers ($headers | merge (csrf-headers $svc)))
  }
  if $r.status >= 400 { error make { msg: $"($method) ($r.url) → ($r.status): (odata-error-message $r.body)" } }
  $r
}

# ── Response → rows ───────────────────────────────────────────────────────────

# The rows, next link and inline count of a response body, whatever the dialect.
def unwrap [body: any, version: string]: nothing -> record {
  let kind = ($body | describe)
  if not ($kind =~ '^record') { return { rows: [$body], next: null, count: null, single: true } }
  if $version == "2" {
    let d = ($body | get -o d)
    if $d == null { return { rows: [$body], next: null, count: null, single: true } }
    if ($d | describe) =~ '^(list|table)' { return { rows: $d, next: null, count: null, single: false } }
    let results = ($d | get -o results)
    if $results != null { return { rows: $results, next: ($d | get -o __next), count: ($d | get -o __count | if $in == null { null } else { $in | into int }), single: false } }
    return { rows: [$d], next: null, count: null, single: true }
  }
  let value = ($body | get -o value)
  if $value != null and (($value | describe) =~ '^(list|table)') {
    return { rows: $value, next: ($body | get -o "@odata.nextLink"), count: ($body | get -o "@odata.count"), single: false }
  }
  { rows: [$body], next: null, count: null, single: true }
}

# V2 wire formats: "/Date(836438400000)/" and "/Date(…+0120)/" for dates,
# strings for Edm.Decimal and Edm.Int64, { results: [...] } for expanded
# collections, { __deferred: {...} } for the ones not expanded.
def v2-date [s: any]: nothing -> any {
  if ($s | describe) != "string" { return $s }
  let m = ($s | parse --regex '^/Date\((?<ms>-?\d+)(?<tz>[+-]\d{4})?\)/$' | get -o 0)
  if $m == null { return $s }
  let base = (($m.ms | into int) * 1_000_000 | into datetime)
  if ($m.tz | is-empty) { $base } else {
    let sign = (if ($m.tz | str starts-with "-") { -1 } else { 1 })
    let mins = ($m.tz | str substring 1..2 | into int) * 60 + ($m.tz | str substring 3..4 | into int)
    $base + ($sign * $mins * 1min)
  }
}

# Strip the protocol's own keys and convert what the schema says is a date or
# a number; one `update` per column that needs it, never a closure per cell.
def clean [rows: list, version: string, schema: any, type: any, --meta]: nothing -> list {
  if ($rows | is-empty) { return $rows }
  let first = ($rows | first)
  if not (($first | describe) =~ '^record') { return $rows }
  # A server may leave a key out of the rows where it is null (TripPin: an
  # expanded single navigation without a target), so the columns are the
  # union over the rows, filled with null, and each column is judged by its
  # first non-null value rather than the first row's.
  let cols = ($rows | each {|r| $r | columns } | flatten | uniq)
  mut out = $rows
  for c in ($cols | where {|c| $rows | any {|r| $c not-in ($r | columns) } }) { $out = ($out | default null $c) }
  if not $meta {
    let drop = ($cols | where {|c| ($c | str starts-with "@odata.") or ($c | str starts-with "__") or ($c | str contains "@odata.") })
    if ($drop | is-not-empty) { $out = ($out | reject -o ...$drop) }
  }
  let props = ($type | get -o props | default [])
  let navs = ($type | get -o navs | default [])
  for c in $cols {
    if $c not-in ($out | first | columns) { continue }
    let p = ($props | where name == $c | get -o 0)
    let n = ($navs | where name == $c | get -o 0)
    let sample = ($out | each {|r| $r | get -o $c } | compact | get -o 0)
    let skind = ($sample | describe)
    if $version == "2" and $skind == "string" and ($sample =~ '^/Date\(') {
      $out = ($out | update $c {|r| v2-date ($r | get $c) })
    } else if $version == "2" and $p != null and $skind == "string" and (edm-short $p.type) in ["Edm.Decimal" "Edm.Double" "Edm.Single"] {
      $out = ($out | update $c {|r| let v = ($r | get $c); if $v == null { null } else { try { $v | into float } catch { $v } } })
    } else if $version == "2" and $p != null and $skind == "string" and (edm-short $p.type) == "Edm.Int64" {
      $out = ($out | update $c {|r| let v = ($r | get $c); if $v == null { null } else { try { $v | into int } catch { $v } } })
    } else if ($skind =~ '^record') and ($sample | get -o __deferred) != null {
      if not $meta { $out = ($out | reject -o $c) }
    } else if ($skind =~ '^record') and $n != null {
      let target = ($schema | get -o types | default {} | get -o $n.target)
      $out = ($out | update $c {|r|
        let v = ($r | get $c)
        if $v == null { null } else if ($v | get -o results) != null { clean $v.results $version $schema $target --meta=$meta } else if ($v | get -o __deferred) != null { null } else { clean [$v] $version $schema $target --meta=$meta | first }
      })
    } else if ($skind =~ '^(list|table)') and $n != null and ($sample | is-not-empty) and (($sample | first | describe) =~ '^record') {
      let target = ($schema | get -o types | default {} | get -o $n.target)
      $out = ($out | update $c {|r| let v = ($r | get $c); if $v == null { null } else { clean $v $version $schema $target --meta=$meta } })
    }
  }
  $out
}

# ── Resource paths ────────────────────────────────────────────────────────────

# `People('russellwhyte')`, `Orders(10248)`, `Order_Details(OrderID=1,ProductID=2)`.
def key-literal [schema: any, set: string, key: any, version: string]: nothing -> string {
  let type = (if $schema == null { null } else { schema type-of $schema $set })
  let keys = ($type | get -o keys | default [])
  let props = ($type | get -o props | default [])
  if ($key | describe) =~ '^record' {
    return ($key | transpose k v | each {|r| $"($r.k)=(literal $r.v ($props | where name == $r.k | get -o 0.type) $version)" } | str join ",")
  }
  let edm = (if ($keys | length) == 1 { $props | where name == $keys.0 | get -o 0.type } else { null })
  literal $key $edm $version
}

def resource-path [schema: any, entity: string, key: any, nav: list<string>, version: string]: nothing -> string {
  let base = (if $key == null { $entity } else { $"($entity)\((key-literal $schema $entity $key $version)\)" })
  if ($nav | is-empty) { $base } else { $base + "/" + ($nav | str join "/") }
}

# The entity type at the end of a nav path (People('x')/Trips → Trip), or null.
def type-at [schema: any, entity: string, nav: list<string>]: nothing -> any {
  if $schema == null { return null }
  mut t = (schema type-of $schema $entity)
  for seg in $nav {
    if $t == null { return null }
    let n = ($t.navs | where name == $seg | get -o 0)
    $t = (if $n == null { null } else { $schema.types | get -o $n.target })
  }
  $t
}

# ── Completion (per-argument completers; the smart menu asks `odata complete columns`) ──

def ctx-words [context: string]: nothing -> list<string> {
  $context | str replace --regex '^\s*odata\s+(get\s+)?' "" | split row " " | where {|w| $w | is-not-empty }
}

# The service named on the line, or the current one; null when none.
def ctx-service [context: string]: nothing -> any {
  let w = ($context | split row " ")
  let i = ($w | enumerate | where item in [--service -s] | get -o 0.index)
  let name = (if $i == null { null } else { $w | get -o ($i + 1) })
  try { service-of $name } catch { null }
}

# Positionals typed so far after `odata [get]`, flags and their values removed.
def ctx-positionals [context: string]: nothing -> list<string> {
  let w = (ctx-words $context)
  mut out = []
  mut skip = false
  for t in $w {
    if $skip { $skip = false; continue }
    if ($t | str starts-with "-") { if $t in [--filter -f --select -c --expand -e --orderby -o --top -t --skip -k --search --param -P --headers -H --service -s --if-match --method] { $skip = true }; continue }
    $out ++= [$t]
  }
  $out
}

def complete-service [] { all-services | transpose name s | each {|r| { value: $r.name, description: ($r.s.url? | default "") } } }

def complete-entity [context: string] {
  let svc = (ctx-service $context)
  if $svc == null { return [] }
  let schema = (try { schema-for $svc } catch { return [] })
  # one parenthesised expression: a `++` that starts a line is parsed as a command
  (
    ($schema.sets | transpose name s | each {|r| { value: $r.name, description: ($r.s.label | default $r.s.type) } })
    ++ ($schema.singletons | transpose name s | each {|r| { value: $r.name, description: $"singleton · ($r.s.type)" } })
  )
}

# Keys of the entity typed before the cursor: from the service, when
# ODATA_COMPLETE_KEYS allows a request at Tab time (memoised 60 s).
def complete-key [context: string] {
  if not (setting ODATA_COMPLETE_KEYS false) { return [] }
  let svc = (ctx-service $context)
  let pos = (ctx-positionals $context)
  if $svc == null or ($pos | is-empty) { return [] }
  let entity = $pos.0
  let schema = (try { schema-for $svc } catch { return [] })
  let type = (schema type-of $schema $entity)
  if $type == null or ($type.keys | length) != 1 { return [] }
  let key = $type.keys.0
  let label = ($type.props | where key == false and (edm-short type) == "Edm.String" | get -o 0.name)
  memo $"keys:($svc.name):($entity)" 60sec {
    try {
      let rows = (do-get $svc $entity null [] { top: (setting ODATA_COMPLETE_KEYS_TOP 50), select: ([$key] ++ (if $label == null { [] } else { [$label] })) } $schema)
      $rows | each {|r| { value: ($r | get $key | into string), description: (if $label == null { "" } else { $r | get -o $label | default "" | into string }) } }
    } catch { [] }
  }
}

def complete-nav [context: string] {
  let svc = (ctx-service $context)
  let pos = (ctx-positionals $context)
  if $svc == null or ($pos | length) < 2 { return [] }
  let schema = (try { schema-for $svc } catch { return [] })
  let t = (type-at $schema $pos.0 ($pos | skip 2))
  if $t == null { return [] }
  $t.navs | each {|n| { value: $n.name, description: (if $n.collection { $"→ [($n.target)]" } else { $"→ ($n.target)" }) } }
}

def entity-type-in [context: string]: nothing -> any {
  let svc = (ctx-service $context)
  let pos = (ctx-positionals $context)
  if $svc == null or ($pos | is-empty) { return null }
  let schema = (try { schema-for $svc } catch { return null })
  { schema: $schema, type: (type-at $schema $pos.0 ($pos | skip 2)) }
}

def prop-items [ctx: any]: nothing -> list<record> {
  if $ctx == null or $ctx.type == null { return [] }
  $ctx.type.props | each {|p| { value: $p.name, description: ((edm-short $p.type) + (if $p.key { " · key" } else { "" }) + (if $p.label != null { $" · ($p.label)" } else { "" })) } }
}

def complete-field [context: string] { prop-items (entity-type-in $context) }
def complete-orderby [context: string] {
  let items = (prop-items (entity-type-in $context))
  $items ++ ($items | each {|i| { value: $"($i.value) desc", description: $i.description } })
}
def complete-expand [context: string] {
  let ctx = (entity-type-in $context)
  if $ctx == null or $ctx.type == null { return [] }
  $ctx.type.navs | each {|n| { value: $n.name, description: (if $n.collection { $"[($n.target)]" } else { $n.target }) } }
}
def complete-function [context: string] {
  let svc = (ctx-service $context)
  if $svc == null { return [] }
  let schema = (try { schema-for $svc } catch { return [] })
  $schema.functions | each {|f| { value: ($f | get -o import | default $f.name), description: ($"($f.kind) ($f.method) · (($f.params | get name) | str join ', ')" + (if $f.bound { $" · on ($f.binding)" + (if $f.binding_collection { " collection" } else { "" }) } else { "" })) } }
}

# `--on` of `odata call`: the entity set. A flag takes one value and Nushell
# does not complete inside a `[…]` or a quoted string, so the key and the
# navigations are typed by hand (or the row is piped in instead).
def complete-on [context: string] { complete-entity $context }

# Whether the last navigation of `nav` is a collection (false for none).
def nav-is-collection [schema: any, entity: string, nav: list<string>]: nothing -> bool {
  if ($nav | is-empty) or $schema == null { return false }
  let t = (type-at $schema $entity ($nav | drop 1))
  $t | get -o navs | default [] | where name == ($nav | last) | get -o 0.collection | default false
}

# The bound function or action `name` for the type at the end of `nav`
# (or the entity's own type; a set without a key binds to the collection).
def bound-function [schema: record, name: string, type: any, collection: bool]: nothing -> any {
  if $type == null { return null }
  let tname = ($schema.types | items {|k, v| if $v == $type { $k } else { null } } | compact | get -o 0)
  $schema.functions | where bound and name == $name and binding_collection == $collection | where {|f|
    mut t = $tname
    mut hit = false
    for _ in 1..4 { if $t == null { break }; if $t == $f.binding { $hit = true; break }; $t = ($schema.types | get -o $t | get -o base) }
    $hit
  } | get -o 0
}

# For the smart menu: the columns `odata …` will return, as the rows
# `describe --detailed` would give, so `where`/`select`/`sort-by` complete
# from the schema without a request. `segment` is the text of the call.
export def "odata complete columns" [segment: string]: nothing -> list<record> {
  let ctx = (entity-type-in $segment)
  if $ctx == null or $ctx.type == null { return [] }
  let schema = $ctx.schema
  # One row per enum member (the longest enum decides how many), so the
  # menu offers `Male`, `Female`, … after `Gender ==`; other columns carry
  # their Edm type and label as the description and no value.
  let enums = ($ctx.type.props | each {|p| $schema.enums | get -o (edm-short $p.type) | default [] | length })
  let nrows = ([1 ($enums | math max)] | math max)
  let props = (0..<$nrows | each {|i|
    $ctx.type.props | each {|p|
      let t = (edm-nu-type $schema $p.type)
      let en = ($schema.enums | get -o (edm-short $p.type))
      let desc = ((edm-short $p.type) + (if $p.key { " · key" } else { "" }) + (if $p.label != null { $" · ($p.label)" } else { "" }))
      if $en != null {
        let m = ($en | get -o $i | default ($en | first))
        { $p.name: { type: $t, value: $m.name, detailed_type: $t, description: $"($t) · ($desc): ($en | get name | str join ' | ')" } }
      } else { { $p.name: { type: $t, value: null, detailed_type: $t, description: $"($t) · ($desc)" } } }
    } | into record
  })
  let words = (ctx-words $segment)
  let expanded = ($words | enumerate | where item in [--expand -e] | each {|e| $words | get -o ($e.index + 1) | default "" | split row "," } | flatten | each {|n| $n | split row "(" | first })
  let navs = ($ctx.type.navs | where name in $expanded | each {|n|
    let t = (if $n.collection { "table" } else { "record" })
    { $n.name: { type: $t, value: null, detailed_type: $t, description: $"($t) · ($n.target)" } }
  })
  let navs = ($navs | into record)
  $props | each {|row| { columns: ($row | merge $navs) } }
}

# ── Reads ─────────────────────────────────────────────────────────────────────

# opts: { filter select expand orderby top skip search count all params headers raw url meta }
def do-get [svc: record, entity: string, key: any, nav: list<string>, opts: record, schema: any]: nothing -> any {
  let version = (version-of $svc $schema)
  let path = (resource-path $schema $entity $key $nav $version)
  let type = (type-at $schema $entity $nav)
  let o = (apply-pushdown $svc $schema $type $version $entity $key $nav $opts)
  let count_only = ($o.count? | default false)
  let list = {|v| if $v == null { null } else if ($v | describe) =~ '^list' { $v | str join "," } else { $v | into string } }
  # V2 shows an expanded navigation only when $select names it too.
  let expand = (do $list $o.expand?)
  let select = (do $list $o.select?)
  let select = (if $version == "2" and $select != null and $expand != null {
    let navs = ($expand | split row "," | each {|e| $e | split row "/" | first | split row "(" | first })
    ($select | split row ",") ++ ($navs | where {|n| $n not-in ($select | split row ",") }) | str join ","
  } else { $select })
  mut params = {
    '$filter': $o.filter?
    '$select': $select
    '$expand': $expand
    '$orderby': (do $list $o.orderby?)
    '$top': $o.top?
    '$skip': $o.skip?
  }
  if $version == "4" { $params = ($params | merge { '$search': $o.search? }) }
  if $version == "2" and not $count_only { $params = ($params | merge { '$format': "json" }) }
  $params = ($params | merge ($o.params? | default {}))
  if $count_only {
    # /$count with the filter is the standard form (V2 and V4). A server that
    # refuses it (TripPin: "$filter can only be applied to collection
    # resources") gets $count=true&$top=0 instead; TripPin then counts after
    # $top and answers 0 — its bug, SAP and modern servers count first.
    let cp = ($params | reject -o '$select' '$expand' '$orderby' '$top' '$skip' '$format')
    if ($o.url? | default false) { return (build-url $svc ($path + '/$count') $cp) }
    let r = (request $svc GET ($path + '/$count') $cp --headers ($o.headers? | default {}) --accept "text/plain" --allow)
    if $r.status < 400 { return ($r.body | into string | str trim | into int) }
    if $version == "2" { error make { msg: $"GET ($r.url) → ($r.status): (odata-error-message $r.body)" } }
    let r2 = (request $svc GET $path ($cp | merge { '$count': "true", '$top': 0 }) --headers ($o.headers? | default {}))
    return ($r2.body | get -o "@odata.count" | default 0 | into int)
  }
  # `… | length` pushed: the server counts (/$count with the filter and
  # search) and `length` counts that many placeholders: integers when
  # `length` follows the call directly, else copies of one real row so the
  # stages before `length` (a `where`, a `select`) still pass. A server that
  # refuses /$count (TripPin, with a filter) gets the rows with only the
  # keys and the columns those stages read; never `$count=true&$top=0`,
  # which TripPin answers 0.
  if ($o.count_rows? | default false) {
    let cp = ($params | select -o '$filter' '$search' | merge ($o.params? | default {}))
    let r = (request $svc GET ($path + '/$count') $cp --headers ($o.headers? | default {}) --accept "text/plain" --allow)
    if $r.status < 400 {
      let n = ($r.body | into string | str trim | into int)
      debug $"counted on the server: ($n)"
      if $n == 0 { return [] }
      if ($o.count_plain? | default true) { return (seq 1 $n) }
      let one = (request $svc GET $path ($params | upsert '$top' 1) --headers ($o.headers? | default {}))
      let row = (clean (unwrap $one.body $version).rows $version $schema $type | get -o 0)
      if $row == null { return [] }
      return (seq 1 $n | each {|| $row })
    }
    debug $"/$count refused \(($r.status)\), fetching the keys instead"
    let sel = ($o.count_select? | default null)
    if $sel != null and ($sel | is-not-empty) and ($params | get -o '$select') == null { $params = ($params | upsert '$select' ($sel | str join ",")) }
  }
  if ($o.url? | default false) { return (build-url $svc $path $params) }
  let r = (request $svc GET $path $params --headers ($o.headers? | default {}))
  if ($o.raw? | default false) { return $r.body }
  let u = (unwrap $r.body $version)
  mut rows = $u.rows
  mut next = $u.next
  if ($o.all? | default false) {
    while $next != null {
      let n = (request $svc GET $next {} --headers ($o.headers? | default {}))
      let page = (unwrap $n.body $version)
      $rows ++= $page.rows
      $next = $page.next
    }
  } else if $next != null {
    debug $"more rows on the server: --all follows ($next)"
  }
  let meta = ($o.meta? | default false)
  let out = (clean $rows $version $schema $type --meta=$meta)
  let stash = ($o.stash? | default [])
  if ($stash | is-not-empty) and $type != null and ($type.keys | is-not-empty) and not $u.single {
    let kept = ($out | each {|r| { ($type.keys | each {|k| $r | get -o $k | into string } | str join "|"): ($r | select -o ...$stash) } } | into record)
    stor delete -t $MEMO -w $"key = 'stash:($svc.name):($entity)'" | ignore
    { key: $"stash:($svc.name):($entity)", value: ($kept | to nuon), at: (date now | into int) } | stor insert -t $MEMO | ignore
    debug $"kept ($stash | str join ', ') aside for `expand` after the select"
  }
  if $u.single { $out | get -o 0 } else { $out }
}

# The columns a row condition reads: its bare words on the left of an
# operator and `$it.x` references, kept to the entity's own names.
def condition-columns [cond: string, known: list<string>]: nothing -> list<string> {
  $cond | parse --regex '(?:^|[\s(])(?:\$it\.)?(?<col>[A-Za-z_]\w*)' | get col | each {|c| $c | split row "." | first } | where {|c| ($known | is-empty) or ($c in $known) } | uniq
}

# Merge what the pre_execution hook planned for this call into its options.
def apply-pushdown [svc: record, schema: any, type: any, version: string, entity: string, key: any, nav: list<string>, opts: record]: nothing -> record {
  if not (setting ODATA_PUSHDOWN true) { return $opts }
  let plans = ($env.ODATA_PUSHDOWN_PLAN? | default [])
  if ($plans | is-empty) or ($opts.raw? | default false) or ($opts.count? | default false) { return $opts }
  let mine = ([$entity] ++ (if $key == null { [] } else { [($key | into string)] }) ++ $nav)
  let hits = ($plans | where positionals == $mine)
  if ($hits | is-empty) { return $opts }
  if ($hits | length) > 1 and ($hits | get stages | uniq | length) > 1 { debug "ambiguous pushdown, skipped"; return $opts }
  mut o = $opts
  mut pushed = []
  # Columns the Nushell stages still need after the server answered: a
  # pushed `where` or `sort-by` runs again locally, so a pushed `$select`
  # must keep what they read (nu's own `select` drops them afterwards).
  mut needed = []
  # Navigations a pushed stage reads (`select UserName Trips`, `get
  # Airline.Name`, `where Airline.Name == x`, `sort-by Airline.Name`): the
  # payload has no navigation unless it is expanded, so each one becomes
  # $expand, or the local re-run would fail on a missing column.
  mut expand = []
  let props = (if $type == null { [] } else { $type.props | get name })
  let navs = (if $type == null { [] } else { $type.navs | get name })
  let known = $props ++ $navs
  let single_navs = (if $type == null { [] } else { $type.navs | where collection == false | get name })
  let first_seg = {|c| $c | str replace --regex '^\$it\.' "" | split row "." | first }
  for st in $hits.0.stages {
    match $st.kind {
      "where" => {
        let f = (filter-from-nu $st.cond $schema $type $version)
        if $f == null { break }
        let cur = ($o.filter? | default null)
        $o = ($o | upsert filter (if $cur == null { $f } else { $"\(($cur)\) and \(($f)\)" }))
        let cols = (condition-columns $st.cond $known)
        $needed ++= $cols
        $expand ++= ($cols | where {|c| $c in $navs })
      }
      "select" => {
        if ($o.select? | default null) == null {
          let firsts = ($st.cols | each {|c| do $first_seg $c } | uniq)
          if $type == null and (($needed | is-not-empty) or ($st.cols | any {|c| $c | str contains "." })) { break }
          if $type != null and ($firsts | any {|c| $c not-in $known }) { break }
          # a path through a collection (`get Trips.Name`) fails in Nushell too
          if ($st.cols | any {|c| ($c | str contains ".") and (do $first_seg $c) in $navs and (do $first_seg $c) not-in $single_navs }) { break }
          let sel_navs = ($firsts | where {|c| $c in $navs })
          let sel_props = ($firsts | where {|c| $c not-in $navs })
          # only navigations asked for: transfer the keys, not every property
          let base = (if ($sel_props | is-empty) and ($sel_navs | is-not-empty) { $type.keys } else { $sel_props })
          $o = ($o | upsert select ($base ++ ($needed | where {|c| $c not-in $base and $c not-in $navs })))
          $expand ++= $sel_navs
        }
      }
      "sort" => {
        let firsts = ($st.cols | each {|c| do $first_seg $c })
        if $type == null and ($st.cols | any {|c| $c | str contains "." }) { break }
        if $type != null and ($firsts | any {|c| $c not-in $props and $c not-in $single_navs }) { break }
        # every path must end on a primitive: a server cannot order by a complex value
        if $type != null and ($st.cols | any {|c| (field-edm $schema $type $c) == null }) { break }
        $o = ($o | upsert orderby ($st.cols | each {|c| let p = ($c | str replace -a "." "/"); if $st.reverse { $"($p) desc" } else { $p } }))
        $needed ++= $firsts
        $expand ++= ($firsts | where {|c| $c in $navs })
      }
      "top" => { $o = ($o | upsert top ([($o.top? | default $st.n) $st.n] | math min)) }
      "skip" => { $o = ($o | upsert skip (($o.skip? | default 0) + $st.n)) }
      "expand" => {
        if $type != null and ($st.navs | any {|n| ($n | split row "(" | first) not-in $navs }) { break }
        $expand ++= $st.navs
        # after a `select` that drops the navigation, nu's select removes the
        # column before `expand` sees it: do-get keeps the values aside
        # (session stash) and `expand` puts them back without a request
        if ($o.select? | default null) != null and $type != null {
          let dropped = ($st.navs | each {|n| $n | split row "(" | first } | where {|n| $n not-in ($o.select | each {|c| $c | split row "/" | first }) })
          if ($dropped | is-not-empty) { $o = ($o | upsert stash (($o.stash? | default []) ++ $dropped)) }
        }
      }
      "search" => {
        if $version != "4" or not (setting ODATA_PUSHDOWN_SEARCH true) { break }
        let cur = ($o.search? | default null)
        $o = ($o | upsert search (if $cur == null { $st.term } else { $"($cur) ($st.term)" }))
      }
      "count" => {
        # do-get counts on the server; the stages before `length` re-run on
        # what comes back, so they need real rows (one, replicated) and, in
        # the keys-only fallback, the columns they read
        $o = ($o | upsert count_rows true | upsert count_plain ($pushed | is-empty) | upsert count_select (if $type == null { null } else { $type.keys ++ ($needed | where {|c| $c not-in $type.keys and $c not-in $navs }) }))
      }
      _ => { break }
    }
    if $st.kind != "expand" { $pushed ++= [$st.kind] }
  }
  # a pushed `$select` keeps the navigations a `where`/`sort-by` reads out of
  # the property list (V4 does not want them there; do-get adds them for V2)
  if ($o.select? | default null) != null and ($o.select | describe) =~ '^list' { $o = ($o | update select ($o.select | where {|c| $c not-in $navs })) }
  # one entry per navigation: an explicit --expand first, then the stages'
  # entries, an entry with options (`Trips($top=2)`) over a bare name
  let nav_name = {|e| $e | split row "(" | first | split row "/" | first }
  let given = ($o.expand? | default null | if $in == null { [] } else if ($in | describe) =~ '^list' { $in } else { $in | split row "," })
  let merged = ($given ++ ($expand | sort-by {|e| $e | str contains "(" } -r) | reduce -f [] {|e, acc|
    if (do $nav_name $e) in ($acc | each {|a| do $nav_name $a }) { $acc } else { $acc ++ [$e] }
  })
  if ($merged | length) > ($given | length) {
    $o = ($o | upsert expand $merged)
    $pushed ++= [$"expand ($merged | where {|e| $e not-in $given } | str join ',')"]
  }
  if ($pushed | is-not-empty) { debug $"pushed down: ($pushed | str join ', ')" }
  $o
}

def get-opts [filter, select, expand, orderby, top, skip, search, count, all, param, headers, raw, url, meta]: nothing -> record {
  { filter: $filter, select: $select, expand: $expand, orderby: $orderby, top: $top, skip: $skip, search: $search, count: $count, all: $all, params: ($param | default {}), headers: ($headers | default {}), raw: $raw, url: $url, meta: $meta }
}

# Read an entity set, one entity, or what a navigation leads to.
#
#   odata get People                            the set (one page; --all for every page)
#   odata get People russellwhyte               one entity, keys quoted from the schema
#   odata get People russellwhyte Trips         a navigation
#   odata get Order_Details {OrderID: 10248, ProductID: 11}
#   odata get People --filter "Gender eq 'Female'" --select UserName,FirstName --expand Trips --orderby "LastName desc" --top 5 --skip 10
#   odata get People | where FirstName =~ Ru | select UserName | first 5      # pushed to the server by the hook
export def --env "odata get" [
  entity: string@complete-entity        # entity set or singleton
  key?: any@complete-key                # key value, or a record for composite keys
  ...nav: string@complete-nav           # navigation properties to follow
  --service (-s): string@complete-service   # registry name; default $env.ODATA_SERVICE
  --filter (-f): string                 # $filter, OData syntax
  --select (-c): any@complete-field     # $select: "A,B" or [A B]
  --expand (-e): any@complete-expand    # $expand: "Trips,Friends" or [Trips]; nested options allowed ("Trips($top=2)")
  --orderby (-o): any@complete-orderby  # $orderby: "LastName desc,FirstName"
  --top (-t): int                       # $top
  --skip (-k): int                      # $skip
  --search: string                      # $search (V4)
  --count                               # only the number of matching entities
  --all (-a)                            # follow every next link
  --param (-P): record                  # extra query parameters ({sap-client: "100"})
  --headers (-H): record                # extra request headers
  --raw (-r)                            # the response body as the server sent it
  --url (-u)                            # print the URL instead of requesting it
  --meta (-m)                           # keep @odata.* / __metadata columns (etags)
]: nothing -> any {
  let svc = (service-of $service)
  let schema = (schema-maybe $svc)
  $env.ODATA_LAST = { service: $svc.name, entity: $entity, key: $key, nav: $nav }
  do-get $svc $entity $key $nav (get-opts $filter $select $expand $orderby $top $skip $search $count $all $param $headers $raw $url $meta) $schema
}

# `odata People [key] [nav...]` — the same as `odata get`.
export def --env main [
  entity?: string@complete-entity
  key?: any@complete-key
  ...nav: string@complete-nav
  --service (-s): string@complete-service
  --filter (-f): string
  --select (-c): any@complete-field
  --expand (-e): any@complete-expand
  --orderby (-o): any@complete-orderby
  --top (-t): int
  --skip (-k): int
  --search: string
  --count
  --all (-a)
  --param (-P): record
  --headers (-H): record
  --raw (-r)
  --url (-u)
  --meta (-m)
]: nothing -> any {
  if $entity == null { return (odata services) }
  let svc = (service-of $service)
  let schema = (schema-maybe $svc)
  $env.ODATA_LAST = { service: $svc.name, entity: $entity, key: $key, nav: $nav }
  do-get $svc $entity $key $nav (get-opts $filter $select $expand $orderby $top $skip $search $count $all $param $headers $raw $url $meta) $schema
}

# How many entities match, without fetching them.
export def "odata count" [entity: string@complete-entity, --service (-s): string@complete-service, --filter (-f): string, --param (-P): record]: nothing -> int {
  let svc = (service-of $service)
  let schema = (schema-maybe $svc)
  do-get $svc $entity null [] { filter: $filter, count: true, params: ($param | default {}) } $schema
}

# ── The expand stage ──────────────────────────────────────────────────────────

# Navigations for `| expand ⌶`: a completer only sees its own segment
# (`expand `), so the `odata …` call is read from the whole buffer, or,
# when there is none (`commandline complete` in a test), from the last
# call this shell made.
def complete-expand-stage [context: string] {
  let line = (try { commandline } catch { "" })
  let call = (if ($line | str contains "|") { $line | split row "|" | first } else { "" })
  let ctx = (if ($call | str trim | str starts-with "odata") { entity-type-in $call } else {
    let last = ($env.ODATA_LAST? | default null)
    if $last == null { null } else {
      # a composite key is a record; any placeholder keeps the navs in position
      let key = (if $last.key == null { [] } else if ($last.key | describe) =~ '^record' { ["x"] } else { [($last.key | into string)] })
      entity-type-in ($"odata ($last.entity) " + ($key ++ $last.nav | str join " ") + " -s " + $last.service)
    }
  })
  if $ctx == null or $ctx.type == null { return [] }
  $ctx.type.navs | each {|n| { value: $n.name, description: (if $n.collection { $"[($n.target)]" } else { $n.target }) } }
}

# `Trips($top=2;$select=Name)` → { name: Trips, params: { $top: "2", $select: "Name" } }
def parse-expand-entry [e: string]: nothing -> record {
  let m = ($e | parse --regex '^(?<name>\w+)(?:\((?<opts>.*)\))?$' | get -o 0)
  if $m == null { error make { msg: $"expand: cannot read '($e)'" } }
  let params = ($m.opts | default "" | split row ";" | where {|o| $o | is-not-empty } | each {|o| $o | split row "=" | { ($in.0 | str trim): ($in | skip 1 | str join "=") } } | into record)
  { name: $m.name, params: $params }
}

# Add navigation columns to the rows of an `odata` call:
#
#   odata People | where Gender == Male | expand Trips Friends
#   odata People russellwhyte | expand "Trips($top=2)"
#
# Interactively the pre_execution hook has already turned this stage into
# $expand, so the columns are there and this is a no-op. Otherwise (a
# script, ODATA_PUSHDOWN off, a stage the planner could not push) it fetches
# each missing navigation per row: `Entity(key)/Nav`, one request per row
# and navigation, using the key columns and the call `odata get` remembered
# in $env.ODATA_LAST.
export def expand [...navs: string@complete-expand-stage]: any -> any {
  let input = $in
  if ($navs | is-empty) { return $input }
  let single = (($input | describe) =~ '^record')
  let rows = (if $single { [$input] } else { $input })
  if ($rows | is-empty) { return $input }
  let entries = ($navs | each {|n| parse-expand-entry $n })
  let have = ($rows | first | columns)
  let missing = ($entries | where {|e| $e.name not-in $have })
  if ($missing | is-empty) { return $input }
  let last = ($env.ODATA_LAST? | default null)
  if $last == null { error make { msg: "expand: no odata call to expand from", help: "pipe the rows of `odata <entity>` into expand, or use `odata <entity> --expand <nav>`" } }
  let svc = (service-of $last.service)
  let schema = (schema-maybe $svc)
  let version = (version-of $svc $schema)
  let type = (type-at $schema $last.entity $last.nav)
  if $type == null { error make { msg: $"expand: no schema for ($last.entity) on ($svc.name)", help: "use `odata <entity> --expand <nav>` instead" } }
  let unknown = ($missing | where {|e| $e.name not-in ($type.navs | get name) })
  if ($unknown | is-not-empty) { error make { msg: $"expand: ($unknown | get name | str join ', ') is not a navigation of ($type | get -o name | default $last.entity)", help: $"navigations: ($type.navs | get name | str join ', ')" } }
  if not $single and ($type.keys | any {|k| $k not-in $have }) { error make { msg: $"expand: the rows have no ($type.keys | str join ', ') column to address the entities by", help: "put `expand` before `select`, or select the key too" } }
  let base = (resource-path $schema $last.entity $last.key $last.nav $version)
  let params = (if $version == "2" { { '$format': "json" } } else { ({}) })
  # values do-get kept aside when the hook pushed this stage past a `select`
  let stash = (if $single or ($last.nav | is-not-empty) { null } else { memo-peek $"stash:($svc.name):($last.entity)" 10min })
  let rowkey = {|row| $type.keys | each {|k| $row | get -o $k | into string } | str join "|" }
  let stashed = ($stash != null and ($rows | all {|row| let k = ($stash | get -o (do $rowkey $row)); $k != null and ($missing | all {|e| ($k | columns) | any {|c| $c == $e.name } }) }))
  if $stashed {
    debug $"expand ($missing | get name | str join ', ') from the rows kept aside, no request"
    let out = ($rows | each {|row| $row | merge ($stash | get (do $rowkey $row) | select ...($missing | get name)) })
    return (if $single { $out | first } else { $out })
  }
  debug $"expand ($missing | get name | str join ', ') locally: ($rows | length) row\(s\), one request per row and navigation"
  let out = ($rows | each {|row|
    let keylit = (if $single { "" } else {
      "(" + (if ($type.keys | length) == 1 { literal ($row | get $type.keys.0) ($type.props | where name == $type.keys.0 | get 0.type) $version } else { $type.keys | each {|k| $"($k)=(literal ($row | get $k) ($type.props | where name == $k | get 0.type) $version)" } | str join "," }) + ")"
    })
    $missing | reduce -f $row {|e, r|
      let n = ($type.navs | where name == $e.name | first)
      let target = ($schema.types | get -o $n.target)
      let resp = (request $svc GET $"($base)($keylit)/($e.name)" ($params | merge $e.params) --allow)
      let v = (if $resp.status == 204 or $resp.status == 404 or $resp.body == null or $resp.body == "" { null } else if $resp.status >= 400 { error make { msg: $"GET ($resp.url) → ($resp.status): (odata-error-message $resp.body)" } } else {
        let u = (unwrap $resp.body $version)
        let c = (clean $u.rows $version $schema $target)
        if $n.collection { $c } else { $c | get -o 0 }
      })
      $r | upsert $e.name $v
    }
  })
  if $single { $out | first } else { $out }
}

# ── Writes ────────────────────────────────────────────────────────────────────

# Create an entity from the record piped in; returns what the server stored.
export def "odata create" [entity: string@complete-entity, --service (-s): string@complete-service, --raw (-r), --headers (-H): record]: record -> any {
  let body = $in
  let svc = (service-of $service)
  let schema = (schema-maybe $svc)
  let version = (version-of $svc $schema)
  let params = (if $version == "2" { { '$format': "json" } } else { ({}) })
  let r = (write $svc POST $entity $params --body $body --headers ($headers | default {}))
  if $raw { return $r.body }
  if $r.body == null or $r.body == "" { return $body }
  clean (unwrap $r.body $version).rows $version $schema (type-at $schema $entity []) | get -o 0
}

# Change fields of one entity with the record piped in (PATCH; --method PUT
# replaces, MERGE for old SAP gateways). --if-match "*" unless you pass the etag.
export def "odata update" [
  entity: string@complete-entity, key: any@complete-key
  --service (-s): string@complete-service, --method: string = "PATCH", --if-match: string = "*", --headers (-H): record, --raw (-r)
]: record -> any {
  let body = $in
  let svc = (service-of $service)
  let schema = (schema-maybe $svc)
  let version = (version-of $svc $schema)
  let path = (resource-path $schema $entity $key [] $version)
  let h = ({ "If-Match": $if_match } | merge ($headers | default {}))
  let r = (if $method == "MERGE" { write $svc POST $path {} --body $body --headers ($h | merge { "X-HTTP-Method": "MERGE" }) } else { write $svc $method $path {} --body $body --headers $h })
  if $raw { $r.body } else if $r.status == 204 { $r.status } else { clean (unwrap $r.body $version).rows $version $schema (type-at $schema $entity []) | get -o 0 }
}

# Delete one entity.
export def "odata delete" [entity: string@complete-entity, key: any@complete-key, --service (-s): string@complete-service, --if-match: string = "*", --headers (-H): record]: nothing -> int {
  let svc = (service-of $service)
  let schema = (schema-maybe $svc)
  let version = (version-of $svc $schema)
  let path = (resource-path $schema $entity $key [] $version)
  (write $svc DELETE $path {} --headers ({ "If-Match": $if_match } | merge ($headers | default {}))).status
}

# ── Functions and actions ─────────────────────────────────────────────────────

# Call a function or action.
#
#   odata call GetNearestAirport {lat: 33, lon: -118}                    unbound (import)
#   odata call GetFavoriteAirline --on [People russellwhyte]            bound to one entity
#   odata call GetFriendsTrips {userName: scottketchum} -o [People russellwhyte]
#   odata People russellwhyte | odata call GetFavoriteAirline           bound to the entity piped in
#   odata People russellwhyte Trips | first 1 | odata call GetInvolvedPeople   … or the row piped in
#   odata call ShareTrip {userName: scottketchum, tripId: 1001} -o [People russellwhyte]   bound action
#
# V4 functions take their parameters inline, actions as a JSON body; V2
# function imports take them as query parameters with the method $metadata
# declares. A bound one (V4) is addressed as `Entity(key)/Namespace.Name`;
# the binding comes from --on (entity, key, navigations, as a list or one
# string) or from the record piped in, whose keys address it under the
# call `odata get` remembered in $env.ODATA_LAST.
export def "odata call" [
  name: string@complete-function
  params?: record
  --on (-o): any@complete-on            # binding: [People russellwhyte Trips] or "People russellwhyte"
  --service (-s): string@complete-service
  --method: string
  --raw (-r)
  --path: string                        # literal prefix for the request path
]: any -> any {
  let input = $in
  let p = ($params | default {})
  # a table piped in: one call per row, a list of results
  if $on == null and (($input | describe) =~ '^(list|table)') {
    return ($input | each {|row| $row | odata call $name $p --service=$service --method=$method --raw=$raw --path=$path })
  }
  let svc = (service-of $service)
  let schema = (schema-maybe $svc)
  let version = (version-of $svc $schema)
  # binding: --on, or the record piped in
  let on = (if $on == null { null } else if ($on | describe) == "string" { $on | split row " " | where {|w| $w | is-not-empty } } else { $on | each {|w| $w | into string } })
  let bound = (if $on != null {
    let entity = $on.0
    let key = ($on | get -o 1)
    let nav = ($on | skip 2)
    let path = (resource-path $schema $entity $key $nav $version)
    { path: $path, type: (type-at $schema $entity $nav), collection: ($key == null or (nav-is-collection $schema $entity $nav)) }
  } else if (($input | describe) =~ '^record') {
    let last = ($env.ODATA_LAST? | default null)
    if $last == null or $schema == null { error make { msg: "odata call: cannot tell which entity the record belongs to", help: "pipe a row of `odata <entity> …` in, or give the binding with --on [Entity key nav…]" } }
    let t = (type-at $schema $last.entity $last.nav)
    if $t == null { error make { msg: $"odata call: no schema for ($last.entity)" } }
    let base = (resource-path $schema $last.entity $last.key $last.nav $version)
    # a row of a collection is addressed by its keys; a single entity as it is
    let was_single = ($last.key != null and not (nav-is-collection $schema $last.entity $last.nav))
    let keylit = (if $was_single { "" } else {
      "(" + (if ($t.keys | length) == 1 { literal ($input | get $t.keys.0) ($t.props | where name == $t.keys.0 | get 0.type) $version } else { $t.keys | each {|k| $"($k)=(literal ($input | get $k) ($t.props | where name == $k | get 0.type) $version)" } | str join "," }) + ")"
    })
    { path: ($base + $keylit), type: $t, collection: false }
  } else { null })
  let f = (if $bound == null {
    $schema | get -o functions | default [] | where {|f| not $f.bound and ($f | get -o import | default $f.name) == $name } | get -o 0
  } else {
    let hit = (bound-function $schema $name $bound.type $bound.collection)
    if $hit == null { error make { msg: $"odata call: no function or action '($name)' bound to ($bound.path)", help: "`odata functions` lists them with what they bind to" } }
    $hit
  })
  let method = ($method | default ($f | get -o method | default "GET"))
  let base = ($path | default "") + (if $bound == null { $name } else { $"($bound.path)/($f.namespace).($f.name)" })
  let ptype = {|k| $f | get -o params | default [] | where name == $k | get -o 0.type }
  let r = (if $version == "4" {
    if $method == "GET" {
      let args = ($p | transpose k v | each {|r| $"($r.k)=(literal $r.v (do $ptype $r.k) $version)" } | str join ",")
      request $svc GET $"($base)\(($args)\)" {}
    } else { write $svc $method $base {} --body $p }
  } else {
    let q = ($p | transpose k v | each {|r| { $r.k: (literal $r.v (do $ptype $r.k) $version) } } | into record | merge { '$format': "json" })
    if $method == "GET" { request $svc GET $base $q } else { write $svc $method $base $q }
  })
  if $raw { return $r.body }
  if $r.body == null or $r.body == "" { return $r.status }
  let u = (unwrap $r.body $version)
  let rt = ($f | get -o returns)
  let type = (if $rt == null or $schema == null { null } else { $schema.types | get -o (edm-short $rt) })
  let out = (clean $u.rows $version $schema $type)
  if $u.single { $out | get -o 0 } else { $out }
}

# Any request against the service: the response as { status, headers, body, url }.
export def "odata raw" [path: string, --service (-s): string@complete-service, --method (-X): string = "GET", --body (-d): any, --param (-P): record, --headers (-H): record, --allow-errors]: nothing -> record {
  let svc = (service-of $service)
  if $method in [POST PATCH PUT DELETE] {
    write $svc $method $path ($param | default {}) --body $body --headers ($headers | default {})
  } else {
    request $svc $method $path ($param | default {}) --headers ($headers | default {}) --allow=$allow_errors
  }
}

# ── The registry and the schema, for people ───────────────────────────────────

# Every service known, with its dialect and the age of its cached $metadata.
export def "odata services" []: nothing -> table {
  let cur = (current-name)
  all-services | transpose name s | each {|r|
    let svc = (normalise-service $r.name $r.s)
    let f = (schema-file $svc)
    let cached = ($f | path exists)
    {
      name: $r.name
      current: ($r.name == $cur)
      url: $svc.url
      version: ($svc.version | default (if $cached { open $f | get -o version } else { null }) | default "?")
      sap: $svc.sap
      metadata: (if $cached { (date now) - (ls -D $f | get 0.modified) | into string | str replace --regex ' \d+ms.*' '' | $"($in) old" } else { "not fetched" })
      description: $svc.description
    }
  }
}

# Register a service (persisted in .state/odata/services.nuon) and fetch its
# $metadata. Auth: --user/--password (basic) or --token (bearer); keep
# secrets in your settings.nu as closures instead when they matter.
export def "odata service add" [
  name: string, url: string
  --user: string, --password: string, --token: string
  --param (-P): record       # query parameters on every request ({sap-client: "100"})
  --headers (-H): record
  --version: string          # "2" | "4"; detected from $metadata otherwise
  --description: string
  --no-fetch                 # register without fetching $metadata now
]: nothing -> record {
  let auth = (if $user != null { { type: "basic", user: $user, password: ($password | default "") } } else if $token != null { { type: "bearer", token: $token } } else { ({}) })
  # Empty and null fields are dropped rather than stored: normalise-service
  # defaults every one of them back, and the file is meant to be read.
  let entry = ({ url: $url, auth: $auth, params: ($param | default {}), headers: ($headers | default {}), version: $version, description: ($description | default "") } | transpose k v | where {|r| $r.v != null and $r.v != {} and $r.v != "" } | transpose -r -d)
  save-services (stored-services | upsert $name $entry)
  let svc = (service-of $name)
  if not $no_fetch {
    let schema = (schema-for $svc --refresh)
    print $"($name): OData V($schema.version), ($schema.sets | columns | length) entity sets, ($schema.functions | length) functions"
  }
  odata services | where name == $name | first
}

# Forget a service and its cached $metadata.
export def "odata service remove" [name: string@complete-service]: nothing -> nothing {
  save-services (stored-services | reject -o $name)
  let f = (cache-dir | path join $"($name).json")
  if ($f | path exists) { rm $f }
}

# Make a service the default for this shell ($env.ODATA_SERVICE).
export def --env "odata service use" [name: string@complete-service]: nothing -> nothing {
  service-of $name | ignore
  $env.ODATA_SERVICE = $name
}

# The resolved settings of a service (secrets hidden).
export def "odata service show" [name?: string@complete-service]: nothing -> record {
  service-of $name | update auth {|s| $s.auth | items {|k v| { $k: (if $k in [password token] { "•••" } else { $v }) } } | into record }
}

# Re-fetch $metadata (after a service changed, or ODATA_METADATA_TTL passed).
export def "odata refresh" [--service (-s): string@complete-service]: nothing -> record {
  let svc = (service-of $service)
  let schema = (schema-for $svc --refresh)
  { service: $svc.name, version: $schema.version, sets: ($schema.sets | columns | length), types: ($schema.types | columns | length), functions: ($schema.functions | length) }
}

# Entity sets (and singletons) of a service, from the cached $metadata.
export def "odata entities" [--service (-s): string@complete-service]: nothing -> table {
  let svc = (service-of $service)
  let schema = (schema-for $svc)
  ($schema.sets | transpose name s | each {|r|
    let t = ($schema.types | get -o $r.s.type | default { keys: [], props: [], navs: [] })
    { name: $r.name, type: $r.s.type, keys: ($t.keys | str join ", "), properties: ($t.props | length), navigations: ($t.navs | get name | str join ", "), label: ($r.s.label | default ($r.s.extra | get -o label | default "")) }
  }) ++ ($schema.singletons | transpose name s | each {|r|
    let t = ($schema.types | get -o $r.s.type | default { keys: [], props: [], navs: [] })
    { name: $r.name, type: $"($r.s.type) \(singleton\)", keys: "", properties: ($t.props | length), navigations: ($t.navs | get name | str join ", "), label: "" }
  })
}

# Fields and navigations of an entity set: name, kind, type, nullable, label, target.
export def "odata schema" [entity?: string@complete-entity, ...nav: string@complete-nav, --service (-s): string@complete-service, --raw (-r)]: nothing -> any {
  let svc = (service-of $service)
  let schema = (schema-for $svc)
  if $raw { return $schema }
  if $entity == null { return ($schema | reject types complex | insert types ($schema.types | columns) | insert complex ($schema.complex | columns)) }
  let t = (type-at $schema $entity $nav)
  if $t == null { error make { msg: $"unknown entity set '($entity)' on ($svc.name)", help: "odata entities lists them" } }
  ($t.props | each {|p|
    { name: $p.name, kind: (if $p.key { "key" } else { "property" }), type: (edm-short $p.type), nullable: $p.nullable, label: ($p.label | default ""), target: (if ($schema.enums | get -o (edm-short $p.type)) != null { $schema.enums | get (edm-short $p.type) | get name | str join " | " } else { "" }), extra: $p.extra }
  }) ++ ($t.navs | each {|n|
    { name: $n.name, kind: "navigation", type: (if $n.collection { $"list<($n.target)>" } else { $n.target }), nullable: true, label: "", target: $n.target, extra: $n.extra }
  })
}

# Functions and actions the service exposes.
export def "odata functions" [--service (-s): string@complete-service]: nothing -> table {
  let svc = (service-of $service)
  (schema-for $svc).functions | each {|f| { name: ($f | get -o import | default $f.name), kind: $f.kind, method: $f.method, on: (if $f.bound { $f.binding + (if $f.binding_collection { " collection" } else { "" }) } else { "" }), params: ($f.params | each {|p| $"($p.name): (edm-short $p.type)" } | str join ", "), returns: (edm-short $f.returns | default "") } }
}

# SAP Gateway's catalog: every OData service on the system behind a
# registered service, from CATALOGSERVICE;v=2 (V2) or the V4 service groups.
# Written from the documented shapes; not yet verified against a live system.
export def "odata catalog" [--service (-s): string@complete-service, --v4, --filter (-f): string]: nothing -> table {
  let svc = (service-of $service)
  let origin = ($svc.url | parse --regex '^(?<o>https?://[^/]+)' | get -o 0.o)
  if $origin == null { error make { msg: $"cannot derive the host from ($svc.url)" } }
  if $v4 {
    let r = (request $svc GET $"($origin)/sap/opu/odata4/iwfnd/config/default/iwfnd/catalog/0002/ServiceGroups" { '$expand': "DefaultSystem($expand=Services)", '$filter': $filter })
    (unwrap $r.body "4").rows | each {|g| $g | get -o DefaultSystem | get -o Services | default [] | each {|s| { group: $g.GroupId, id: ($s | get -o ServiceId), version: ($s | get -o ServiceVersion), alias: ($s | get -o ServiceAlias), url: ($s | get -o ServiceUrl) } } } | flatten
  } else {
    let r = (request $svc GET $"($origin)/sap/opu/odata/IWFND/CATALOGSERVICE;v=2/ServiceCollection" { '$format': "json", '$filter': $filter })
    (unwrap $r.body "2").rows | each {|s| { id: ($s | get -o ID), title: ($s | get -o Title), name: ($s | get -o TechnicalServiceName), version: ($s | get -o TechnicalServiceVersion), url: ($s | get -o ServiceUrl), author: ($s | get -o Author), updated: (v2-date ($s | get -o UpdatedDate)) } }
  }
}

# Caches this module keeps: per-service schema files and session memos.
export def "odata status" []: nothing -> table {
  ensure-memo
  let memos = (stor open | query db $"select key, at from ($MEMO)" | each {|r| { what: $"memo ($r.key)", where: "stor", age: ((date now) - ($r.at | into datetime) | into string | str replace --regex ' \d+ms.*' '') } })
  let files = (ls (cache-dir) | each {|f| { what: ($f.name | path basename), where: $f.name, age: ((date now) - $f.modified | into string | str replace --regex ' \d+ms.*' '') } })
  $files ++ $memos
}

# ── Activation ────────────────────────────────────────────────────────────────
# Everything this module needs wired into the shell, in one place, so that
# loading it eagerly (modules/odata/load.nu) and loading it lazily on the first
# line that says "odata" run exactly the same code. docs/concepts/modules.md.
export def --env "odata activate" []: nothing -> nothing {
  # Defaults. `default` rather than assignment, because your settings.nu was
  # sourced long before this ran and must win.
  $env.ODATA_SERVICES = ($env.ODATA_SERVICES? | default {
    trippin: { url: "https://services.odata.org/V4/(S(nushell))/TripPinServiceRW/", description: "OData V4 sandbox, read-write" }
    northwind: { url: "https://services.odata.org/V2/Northwind/Northwind.svc/", description: "OData V2 sample, read-only" }
  })
  $env.ODATA_SERVICE = ($env.ODATA_SERVICE? | default "trippin")
  $env.ODATA_PUSHDOWN = ($env.ODATA_PUSHDOWN? | default true)
  $env.ODATA_PUSHDOWN_SEARCH = ($env.ODATA_PUSHDOWN_SEARCH? | default true)
  $env.ODATA_COMPLETE_KEYS = ($env.ODATA_COMPLETE_KEYS? | default false)
  $env.ODATA_COMPLETE_KEYS_TOP = ($env.ODATA_COMPLETE_KEYS_TOP? | default 50)
  $env.ODATA_METADATA_TTL = ($env.ODATA_METADATA_TTL? | default 7day)
  $env.ODATA_DEBUG = ($env.ODATA_DEBUG? | default false)

  # Pushdown. `where` cannot be overloaded (a parser keyword) and a hook cannot
  # rewrite the line, but the $env a pre_execution hook sets is visible to the
  # command that runs. So the hook leaves the plan of what follows each
  # `odata …` call, and `odata get` sends as much of it as it can translate.
  # Cost per Enter: a `str contains` (µs); with "odata" on the line, `ast
  # --flatten` plus the walk (docs/concepts/odata.md).
  $env.config.hooks.pre_execution = ($env.config.hooks.pre_execution? | default [])
  $env.config.hooks.pre_execution ++= [{||
    let line = (commandline)
    $env.ODATA_PUSHDOWN_PLAN = (if ($line | str contains "odata") { try { odata pushdown plan $line } catch { [] } } else { [] })
  }]

  # The smart Tab menu asks a provider for the columns a command returns
  # instead of running it: `odata People | where ⌶` lists fields, typed, with
  # enum members as values, from the cached $metadata.
  $env.NU_COMPLETE_PROVIDERS = (($env.NU_COMPLETE_PROVIDERS? | default {}) | merge { odata: {|segment| odata complete columns $segment } })

  # The hook above cannot help the line that loaded this module: when the
  # module is lazy, that line is already mid-`pre_execution` and the closure
  # was only just appended. Without this, the FIRST `odata … | where …` in a
  # shell fetched the whole entity set and filtered locally — verified with
  # ODATA_DEBUG, which showed a bare `GET /People` for line one and
  # `?$filter=…&$select=…` only from line two.
  #
  # `commandline` still holds the line about to run, so the plan can be built
  # here. Loaded eagerly at startup it returns "", and the plan is empty —
  # which is correct, there is no line yet.
  $env.ODATA_PUSHDOWN_PLAN = (try { odata pushdown plan (commandline) } catch { [] })
}
