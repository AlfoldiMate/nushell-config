# OData: pushing the pipeline to the server

The design record for `modules/odata`: how a request is assembled, how the
stages typed after an `odata` call become query options, the schema record
and the two dialects. The commands, flags, knobs, costs and tests are in the
[odata reference](../reference/modules/odata.md).

```nu
odata People | where FirstName =~ Ru and Gender == Female | select UserName FirstName | first 5
```

sends one `GET People?$filter=…&$select=…&$top=5` and then runs the Nushell
stages on what comes back, so the result is what Nushell would have produced
anyway with fewer rows transferred. Nushell cannot overload `where`, so a
`pre_execution` hook plans the pushdown and `odata get` applies it; because
every pushed stage still runs locally, a translation can only shrink what is
transferred, never change the answer.

## How a request is assembled

`odata get` → `do-get` → `request`. In order:

1. **Service** (`service-of`): the registry entry, normalised (trailing
   slash, `auth`/`headers`/`params` defaulted, `sap` inferred).
2. **Schema** (`schema-maybe`): the parsed `$metadata` from
   `$nu.cache-dir/odata/<service>.json` when younger than
   `ODATA_METADATA_TTL`, else fetched and written. The parsed record is also
   memoised in the session for 60 s so Tab does not re-read the file. A
   service that cannot be reached yields `null`, and the read goes on with
   untyped keys and no V2 conversion.
3. **Path** (`resource-path`): `Entity(key)/nav/…`, keys quoted by the
   key property's Edm type and dialect.
4. **Pushdown** (`apply-pushdown`): the hook's plan for this exact call is
   merged into the options (below).
5. **Query** (`do-get`): `$filter $select $expand $orderby $top $skip`,
   `$search` on V4, `$format=json` on V2, plus the service's own `params`
   and the call's `--param`. Values are percent-encoded with
   `url encode --all`, then the characters OData syntax needs
   (`$ ( ) , = ; ' / : . - _`) are restored so the URL stays readable and
   `$expand=Trips($select=Name;$top=2)` survives.
6. **Count** (`length` pushed): `GET <path>/$count` with the filter and
   search. `length` then counts that many placeholders: integers when it
   follows the call directly, else copies of one real row (one more
   request, `$top=1`) so the stages before it still pass. A server that
   refuses `/$count` with a filter (TripPin) gets the rows with only the
   keys and the columns those stages read. `$count=true&$top=0` is never
   used: TripPin counts after `$top` and answers 0.
7. **Request** (`request`): one `http <method> --full -e -r` with
   `Accept: application/json` (`application/xml` for `$metadata`,
   `text/plain` for `/$count`), the `Authorization` header from `auth`, the
   service's headers, then the call's. A JSON body is parsed. 4xx/5xx
   raise with the message from `error.message` (V4), `error.message.value`
   (V2) and `innererror.errordetails` (SAP), unless `--allow`.
8. **Unwrap** (`unwrap`): rows from `value` (V4), `d.results` (V2, SAP),
   a bare `d` list (Northwind V2), or a single record; the next link from
   `@odata.nextLink` / `__next`; the inline count.
9. **Clean** (`clean`): first make the rows rectangular. A server may leave
   a key out of the rows where it is null (TripPin omits an expanded
   single navigation such as `Photo` for people without one), which would
   make a later `select` fail, so every column any row lacks is filled
   with null, and each column is judged by its first non-null value.
   Then, unless `--meta`, drop `@odata.*`, `__metadata`,
   `__deferred` columns. On V2 convert by column from the schema:
   `/Date(ms±zone)/` → datetime, `Edm.Decimal|Double|Single` strings →
   float, `Edm.Int64` → int, `{results: [...]}` expansions → tables.
   Expanded navigations are cleaned recursively with their target type.
   One `update` per column that needs it, never a closure per cell.

With `ODATA_DEBUG = true` every request is printed to stderr as
`METHOD URL → status duration`, plus the pushdown decisions and the next
link left unfollowed.

## Pushdown

Two constraints shape the design, both verified on 0.115.1: `where` is a
parser keyword and cannot be overloaded, and a `pre_execution` hook cannot
change the line about to run. But the `$env` a closure hook sets is visible
to the commands on that line. So:

Four facts, all verified on 2026-09-11, fix the design:

1. `where` is a parser keyword: `def where`, an overlay and a module
   export all fail with "Parser keywords cannot be shadowed", and
   `row_condition` is not a type a custom `def` can declare. `select`,
   `first`, `sort-by` could be shadowed, which is pointless without `where`.
2. A `pre_execution` hook cannot rewrite the line (`commandline edit
   --replace` inside it is ignored), but `$env` it sets is visible to the
   commands that then run.
3. `ast --json` stores a row condition as a block id; `ast --flatten` gives
   its tokens with shapes, and splits cell paths into members without the
   dots. Translation therefore works on source text and token spans.
4. Everything else is built in: `http` with headers and `--full`, `from
   xml`, `stor`, hooks. A plugin would mean a Rust build and a registered
   binary for nothing measured to be slow: `from xml` parses TripPin's or
   Northwind's `$metadata` in 1.6 ms, `ast --flatten` a line in 0.5 ms.
   Revisit only if a service's metadata is in the megabytes (SAP can be)
   and `from xml` is measured to hurt; the cache makes even that a one-off.

**The hook** (`odata activate`) runs on every Enter. A line without the
substring `odata` costs a `str contains`. Otherwise it calls
`odata pushdown plan <line>` and stores the result in
`$env.ODATA_PUSHDOWN_PLAN`.

**`odata pushdown plan`** (`pushdown.nu`) tokenises the line with
`ast --flatten`, splits it into pipeline segments (at pipes, `;` and
newlines) and, for every segment whose head is `odata` or `odata get`,
records its positionals (entity, key, navs, quotes stripped) and the stages
that follow it. Cell paths come out of `ast --flatten` as separate members
with the dots dropped, so words are rebuilt from the token spans first.

| stage | recorded as | rule |
|---|---|---|
| `where <cond>` | `{kind: where, cond}` | row condition or closure (`{\|p\| $p.Age > 30 }`, rewritten to `$it.`); not after `first`/`skip` |
| `select A B.C` / `get A B.C` | `{kind: select, cols}` | column names or cell paths, once |
| `sort-by A B.C [-r]` | `{kind: sort, cols, reverse}` | not after `first`/`skip`; only `-r`/`--reverse` |
| `first N` / `take N` | `{kind: top, n}` | `first` alone is 1 |
| `is-empty` / `is-not-empty` / `columns` | `{kind: top, n: 1}` | one row is all they need |
| `expand Trips "Friends($top=2)"` | `{kind: expand, navs}` | any position |
| `length` | `{kind: count}` | not after `first`/`skip`; ends the plan |
| `find word` | `{kind: search, term}` | one plain term, not a number, no flags; not after `first`/`skip` |
| `skip N` | `{kind: skip, n}` | not after `first` |

Planning stops at the first stage that does not fit (a closure that does
more than read `$p.field`, `sort-by -n`, `each`, `reject`, anything else).
After a `select`, a `where` or `sort-by` may only touch selected columns.
A segment with `--raw`, `--count` or `--url` is skipped. Value flags
(`--filter x`, `-s name`, …) are skipped with their value so they are not
mistaken for positionals.

**`apply-pushdown`** (`mod.nu`) finds the plan whose positionals equal the
call's own `[entity key nav…]` (two calls with the same positionals but
different stages are ambiguous and skipped), and merges the stages in order,
stopping at the first it cannot translate:

- `where`: `filter-from-nu` turns the condition into `$filter`; `null`
  means "cannot", and everything after it is dropped. The result is
  `and`-ed with an explicit `--filter`.
- `select`: becomes `$select` only when no `--select` was given and every
  column's first segment is known to the schema. A cell path selects its
  first segment (`get HomeAddress.City` → `$select=HomeAddress`; Nushell
  takes `City` locally). Every column an earlier pushed `where` or `sort-by`
  reads is added, because those Nushell stages run again on the returned
  rows and would fail with "Cannot find column" otherwise. Nushell's own
  `select` removes the extras afterwards.
- `sort`: `$orderby`, with `A.B` as `A/B`. Every path must end on a
  primitive: a server refuses to order by a complex value (TripPin's
  `Location.City` is a record; `Location.City.Name` works).
- `top`: `$top`, the minimum with `--top`.
- `skip`: `$skip`, added to `--skip`.
- `expand`: every name must be a navigation of the type; the entries join
  the `$expand` list below, nested options kept. After a `select` that
  drops the navigation, `do-get` keeps the values aside for `expand`.
- `count`: `do-get` counts on the server (step 6 above).
- `search`: `$search` on V4 when `ODATA_PUSHDOWN_SEARCH` is true, joined
  to an explicit `--search` with a space (AND); on V2 the plan stops here.
  The local `find` narrows what the server returns, so this is only exact
  when the server's `$search` is at least a substring match over every
  string property (TripPin: `uss` finds `russellwhyte`, `example` finds
  every e-mail); the knob is there for a server whose search is narrower.

Because every pushed stage still runs locally, a translation can only
shrink what is transferred, never change the answer.

### `$expand` from the stages

A payload carries no navigation property unless it is expanded, and
`clean` drops the deferred placeholders, so a stage that reads a navigation
would fail locally on a missing column. `apply-pushdown` therefore collects
every navigation a pushed stage touches and sends it as `$expand`:

| Nushell | pushed |
|---|---|
| `expand Trips Friends` | `$expand=Trips,Friends` |
| `expand "Trips($top=2)"` | `$expand=Trips($top=2)` |
| `select UserName \| expand Trips` | `$select=UserName&$expand=Trips`; the values `select` drops are kept aside for `expand` |
| `select UserName Trips` | `$select=UserName&$expand=Trips` |
| `get Trips` (only navigations asked for) | `$select=<keys>&$expand=Trips`, so the properties are not transferred |
| `where Customer.CompanyName =~ Alfreds` (single navigation) | `$filter=substringof('Alfreds',Customer/CompanyName) eq true&$expand=Customer` |
| `sort-by Customer.CompanyName -r` | `$orderby=Customer/CompanyName desc&$expand=Customer` |
| `-e "Trips($top=1)" \| select UserName Trips Friends` | `$expand=Trips($top=1),Friends`: the explicit flag is kept, missing navigations are added |
| `get Trips.Name` (a path through a collection) | not pushed; Nushell cannot take that path either |

One entry per navigation: the explicit flag's entries first, then the
stages', an entry with options over a bare name. On V4 the pushed `$select`
lists properties only; on V2 `do-get` appends each expanded navigation to
`$select`, as the dialect requires.

### The condition translator

`filter-from-nu cond schema type version` is a recursive-descent parser over
the condition's *source text* (`ast --json` stores a row condition as a
block id, not as an expression tree). Grammar, lowest precedence first:
`or` → `and` → `not` / parentheses → comparison.

| Nushell | V4 `$filter` | V2 `$filter` |
|---|---|---|
| `A == x` `!=` `<` `<=` `>` `>=` | `A eq x` `ne lt le gt ge` | same |
| `x < A` (literal on the left) | mirrored: `A gt x` | same |
| `A =~ "x"` / `!~` | `contains(A,'x')` / `not contains(…)` | `substringof('x',A) eq true` / `eq false` |
| `A starts-with "x"` / `ends-with` | `startswith(A,'x')` / `endswith(…)` | same |
| `A in [1 2]` / `not-in` | `A in (1,2)` / `not (…)` | `(A eq 1 or A eq 2)` / `not (…)` |
| `A has "x"` / `not-has` (collection property) | `A/any(e:e eq 'x')` | not pushed |
| `A` (a boolean column alone) | `A eq true` | same |
| `A == $it.B` | `A eq B` (a column on the right) | same |
| `A.B == x` | `A/B eq x` (complex type or single navigation; the navigation is expanded) | same |
| `{\|p\| $p.A == x }` (closure form) | as `A == x` | same |
| `and` `or` `not` `( )` | same | same |

A bare word on the left is a column; on the right it is a string, as in
Nushell. Literals are typed by the property's Edm type when the schema
knows it: strings are quoted with `''` escaping, V4 enums are qualified
(`NS.PersonGender'Female'`), dates become `datetime'…'` on V2 and ISO on V4,
V2 numbers get their `L` `M` `d` `f` suffixes, GUIDs `guid'…'` on V2.
Without a schema, literals are typed by their Nushell shape only.

Anything the grammar does not cover, an unknown field, a comparison of a
whole complex value, a closure that does more than read `$p.field`, or a
path through a collection navigation returns `null`: "not pushed", never
"wrong". The reason is printed with `ODATA_DEBUG`.

Stages with no OData equivalent, or whose local re-run would break, are
never pushed: `reject` (the local `reject` would fail on the column the
server no longer sends), `last N` (the order would flip), `get N` for a
row index, `uniq`, `group-by` and the `math` commands (`$apply` is not
implemented), and any closure beyond `where {|p| $p.field …}`.

## The schema record

`parse-metadata` walks the CSDL once and keeps what the shell needs:

```nu
{
  version: "2" | "4", edmx: "1.0" | "4.0", namespaces: [..], fetched_at, url
  sets:       { People: { type: "Person", bindings: { Trips: "Trips" }, label, extra: { pageable: "true" } } }
  singletons: { Me: { type: "Person" } }
  types:      { Person: { keys: [UserName], base: null, abstract: false, label,
                          props: [{ name, type: "Edm.String", nullable, key: bool, label, extra }],
                          navs:  [{ name, target: "Trip", collection: bool, partner, extra }] } }
  complex:    { Location: { props: [...], base } }
  enums:      { PersonGender: [{ name: Male, value: "0" }] }
  functions:  [{ name, namespace, kind: function | action, method: GET | POST, bound: bool,
                 binding: "Person" | null, binding_collection: bool,
                 params: [{ name, type, mode }], returns, set, import? }]
}
```

Details worth knowing:

- Namespaced type names are shortened (`NS.Person` → `Person`,
  `Collection(NS.Trip)` → `Trip` with `collection: true`).
- V2 navigation targets and cardinality are resolved through `Association`
  ends, so `navs` has the same shape on both dialects.
- Base types are merged into derived types (keys, properties, navigations),
  three levels deep.
- Every attribute that is not part of the standard CSDL vocabulary lands in
  `extra` with its prefix stripped: `sap:creatable="false"` becomes
  `extra.creatable: "false"`, `sap:label` is promoted to `label`.
- V4 function and action imports set `import` (the callable name) and `set`
  on the function they refer to; V2 function imports are functions
  directly, with the `m:HttpMethod`. A bound one keeps its namespace (the
  URL needs the qualified name) and its first parameter becomes `binding`
  (the type it is called on, `binding_collection` when a whole set).
- `edm-nu-type` maps an Edm type to the Nushell type the smart menu reasons
  with (`string int float bool datetime duration binary list record any`).

The record is cached as JSON under `$nu.cache-dir/odata/<service>.json` and
re-fetched after `ODATA_METADATA_TTL` or `odata refresh`. JSON, where the
registry (`.state/odata/services.nuon`) is NUON, because this file is machine-written and on the Tab
path: the Northwind schema is 25 kB and parses in 0.47 ms as JSON against
3.0 ms as NUON ([Files and formats](../reference/files.md)).

## V2 and V4, side by side

| | V4 | V2 |
|---|---|---|
| JSON envelope | `value` | `d.results`, `d` for one entity, a bare `d` list on Northwind; needs `$format=json` |
| next page | `@odata.nextLink` | `__next` |
| count | `/$count`; inline `$count=true` → `@odata.count` | `/$count`; inline `$inlinecount=allpages` → `__count` |
| substring | `contains(f,'x')` | `substringof('x',f) eq true` |
| `in` | `f in (a,b)` | a chain of `eq … or` |
| search | `$search` | none |
| enum literal | `NS.Type'Member'` | none (V2 has no enums) |
| datetime literal | `2020-01-01T00:00:00Z` | `datetime'2020-01-01T00:00:00'` |
| numbers | plain | `L` `M` `d` `f` suffixes for Int64, Decimal, Double, Single; Decimal and Int64 arrive as strings |
| dates in the payload | ISO | `/Date(ms±zone)/` |
| expand | `$expand=Nav($select=A;$top=2)` | `$expand=Nav`, and `$select` must name `Nav` too |
| navigations in metadata | `NavigationProperty` + bindings | `NavigationProperty` + `Association` ends |
| unexpanded navigation | absent | `{ __deferred: … }` (dropped) |
| concurrency | `@odata.etag`; TripPin needs `If-Match` (428 without) | `__metadata.etag` |
| functions | inline parameters; actions POST a body | function imports with query parameters and `m:HttpMethod` |
| writes without PATCH | | `--method MERGE` tunnels through POST with `X-HTTP-Method` |

## Session memos

Short-lived values live in a `stor` table named `odata_memo` (`memo key ttl
closure`): the parsed schema per service (60 s), keys for completion (60 s),
the SAP CSRF token and cookie per service (25 min), the navigation values
kept aside for `expand` after a `select` (10 min). `odata status` lists
them with the cache files. They vanish with the shell.
