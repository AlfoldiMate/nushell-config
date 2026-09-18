# modules/odata

OData V2 and V4 services (SAP Gateway included) as Nushell tables, with the
row conditions typed after the call pushed to the server. Pure Nushell
0.115.1 over the built-in `http` commands; no plugin, no external tool.

```nu
odata People | where FirstName =~ Ru and Gender == Female | select UserName FirstName | first 5
odata People | where Gender == Male | expand Trips
```

The first line sends one `GET People?$filter=…&$select=…&$top=5`, the
second `GET People?$filter=…&$expand=Trips`, and each then runs
the Nushell stages on what comes back, so the result is what Nushell would
have produced anyway with fewer rows transferred. `expand` is the module's
own stage: there is no such command in Nushell, so it can be exported.

This is the one document for the module: what each file does, every
command and flag, which query option each pipeline stage becomes, how a
request is assembled, the design and what Nushell allowed, the schema
record, the dialect differences, completion, costs, testing, extending, and
the known limits. `modules/odata (activate)` is the wiring; `your settings.nu` holds
the knobs. Verified against Nushell 0.115.1 on 2026-09-11 with the public
TripPin (V4, read-write) and Northwind (V2) services; every cost was
measured with `timeit` on this machine. SAP Gateway support follows the
documented protocol and is marked where no live system has exercised it.

## Files

| file | lines | concern |
|---|---|---|
| `mod.nu` | ~870 | the `odata …` commands, the service registry, the schema cache, the transport (`request`, `write`, CSRF), response unwrapping and V2 conversion, per-argument completers, the smart-menu provider, and `apply-pushdown` |
| `pushdown.nu` | ~340 | Nushell values → OData literals; a row condition (`Age > 30 and Name =~ "x"`) → `$filter`; `odata pushdown plan`, which reads a whole command line and records the stages after each `odata` call |
| `metadata.nu` | ~225 | `$metadata` (CSDL XML, V2 or V4) → one compact schema record; `schema type-of`, `edm-short`, `edm-nu-type` |

`mod.nu` imports the other two with `use … *`, and re-exports only
`odata pushdown plan` (the hook in `modules/odata (activate)` calls it). Everything
else in `pushdown.nu` and `metadata.nu` is internal.

Import with the glob form. The commands are named `"odata get"`,
`"odata count"` and so on, and `main` is the bare `odata`:

```nu
use odata *          # odata, odata get, odata services, …
use odata            # wrong: gives `odata odata get`
```

## Commands

Every command takes `--service (-s) <name>`; without it `$env.ODATA_SERVICE`
is used. Tab completes service names from the registry, entity sets and
singletons, keys (opt-in), navigations, fields and functions, all from the
cached schema.

### Reading

```
odata <entity> [key] [nav...] [flags]    same as `odata get`; `odata` alone lists the services
odata get <entity> [key] [nav...]
```

| flag | query option | notes |
|---|---|---|
| `--filter -f <string>` | `$filter` | OData syntax; combined with a pushed `where` using `and` |
| `--select -c <string\|list>` | `$select` | `"A,B"` or `[A B]` |
| `--expand -e <string\|list>` | `$expand` | nested options allowed: `"Trips($top=2)"`; on V2 the navigation is also added to `$select`, since V2 shows it only then |
| `--orderby -o <string\|list>` | `$orderby` | `"LastName desc,FirstName"` |
| `--top -t <int>` | `$top` | the minimum of the flag and a pushed `first` |
| `--skip -k <int>` | `$skip` | the flag and a pushed `skip` add up |
| `--search <string>` | `$search` | V4 only; dropped on V2 |
| `--count` | `/$count` | returns an int, see `odata count` |
| `--all -a` | | follows every `@odata.nextLink` / `__next`; one page otherwise, with a debug line when more was left |
| `--param -P <record>` | | extra query parameters on this request, e.g. `{sap-client: "100"}` |
| `--headers -H <record>` | | extra request headers |
| `--raw -r` | | the body exactly as the server sent it; switches pushdown off |
| `--url -u` | | the URL it would request, nothing is sent; switches pushdown off |
| `--meta -m` | | keep `@odata.*`, `__metadata`, `__deferred` columns (etags live there) |

The `key` positional is a scalar or a record for composite keys. It is
quoted from the schema: `People russellwhyte` → `People('russellwhyte')`,
`Orders 10248` → `Orders(10248)`, `Order_Details {OrderID: 10248, ProductID: 11}`
→ `Order_Details(OrderID=10248,ProductID=11)`. With a key the result is a
record; without, a table. Navigation segments are appended as a path.

```
odata count <entity> [-f <filter>] [-P <record>]
```

`GET <entity>/$count?$filter=…` on both dialects. A V4 server that refuses
a filter on `/$count` (TripPin does) gets `$count=true&$top=0` instead.

### The expand stage

```
<rows or record> | expand <nav> ["<nav>($top=2;$select=Name)"] ...
```

Adds navigation columns to the rows of an `odata` call, at any position
in the pipeline:

```nu
odata People | where Gender == Male | expand Trips Friends
odata People russellwhyte | expand "Trips($top=2)"
odata Orders -s northwind | first 5 | expand Customer Order_Details
```

Interactively the hook has already pushed the stage as `$expand`, so the
columns arrive with the rows and the command does nothing. When a `select`
in between dropped the navigation (`odata People | select UserName | expand
Trips`), the request still carried `$expand`; `odata get` keeps the dropped
values aside in the session (keyed by entity key, 10 min) and `expand` puts
them back, still without a request. Otherwise (a script, `ODATA_PUSHDOWN =
false`, a stage the planner could not push) it fetches each missing
navigation per row as `Entity(key)/Nav`, one request per row and
navigation, addressing the entity through the key columns and the call
`odata get` remembered in `$env.ODATA_LAST`. Navigations already
present are left alone; a name that is not a navigation, rows without their
key column (after a `select` that dropped it), and a shell that has made no
`odata` call are errors with a hint. Tab after `| expand ` offers the
navigations of the call at the head of the line.

### Writing

```
<record> | odata create <entity> [--raw] [-H <record>]
<record> | odata update <entity> <key> [--method PATCH|PUT|MERGE] [--if-match <etag>] [--raw] [-H <record>]
odata delete <entity> <key> [--if-match <etag>] [-H <record>]
```

`create` returns what the server stored (or the input when the server sent
no body). `update` defaults to PATCH; `PUT` replaces; `MERGE` tunnels
through POST with `X-HTTP-Method: MERGE` for gateways without PATCH.
`If-Match: *` is sent unless an etag is given, because TripPin answers 428
without it. `update` returns the stored record, or the status when the
server answered 204. `delete` returns the status.

Every write goes through `write`, which adds SAP's CSRF token and session
cookie when the service is marked `sap` (auto-detected from `/sap/opu/odata`
in the URL, or `sap: true` in the registry entry) and retries once when the
gateway answers 403 with `x-csrf-token: Required`.

### Functions and actions

```
odata call <name> [params: record] [--on <binding>] [--method <M>] [--path <prefix>] [--raw]
odata functions
```

`odata functions` lists what the schema declares: name (the import name on
V4), kind, HTTP method, what a bound one binds to (`on`: the type, or
`<type> collection`), parameters, return type.

Unbound functions and actions are called by name at the service root:

```nu
odata call GetNearestAirport {lat: 33, lon: -118}
odata call ResetDataSource
```

A bound one (V4 only; V2 has none) is addressed as
`Entity(key)/Namespace.Name`, and the binding comes from `--on` or from
the rows piped in:

```nu
odata call GetFavoriteAirline --on [People russellwhyte]                 # entity, key, navigations…
odata call GetFriendsTrips {userName: scottketchum} -o "People russellwhyte"
odata People russellwhyte | odata call GetFavoriteAirline                # the record piped in
odata People russellwhyte Trips | first 2 | odata call GetInvolvedPeople  # a table: one call per row
odata call ShareTrip {userName: scottketchum, tripId: 0} -o [People russellwhyte]   # a bound action
```

`--on` without a key binds to the collection (`People/NS.Fn()`). A piped
row is addressed through its key columns under the call `odata get`
remembered in `$env.ODATA_LAST`: a row of `odata People russellwhyte
Trips` becomes `People('russellwhyte')/Trips(0)`. The function is looked
up by name among those bound to the type at the end of the path, base
types included, and collection-bound ones only for a collection.

V4 functions inline their parameters (`GetFriendsTrips(userName='x')`),
typed from the declaration; actions send them as a JSON body. V2 function
imports pass parameters as query options with the `m:HttpMethod` from
`$metadata`. The result is unwrapped and cleaned with the declared return
type; an action that answers without a body returns the status.

### Anything else

```
odata raw <path> [-X GET|POST|PATCH|PUT|DELETE] [-d <body>] [-P <record>] [-H <record>] [--allow-errors]
```

Returns `{ status, headers, body, url }` for a path relative to the service
root (or an absolute URL). The body is parsed as JSON when the content type
says so. Write methods go through the CSRF path. Without `--allow-errors` a
4xx/5xx raises with the service's own message.

### The registry

```
odata services                                   every known service: name, current, url, version, sap, metadata age, description
odata service add <name> <url> [--user --password | --token] [-P <record>] [-H <record>] [--version 2|4] [--description] [--no-fetch]
odata service use <name>                         sets $env.ODATA_SERVICE for this shell
odata service show [name]                        the resolved entry, password and token masked
odata service remove <name>                      drops the entry and its cached schema
```

Two sources are merged: `$env.ODATA_SERVICES` from `your settings.nu`
wins over `$nu.data-dir/.state/odata/services.json`, which `service add`
writes (gitignored). An entry has this shape; every field but `url` is
optional:

```nu
{
  url: "https://host/sap/opu/odata/sap/ZMY_SRV/"
  version: "2"                                   # else read from $metadata
  auth: { type: basic, user: "me", password: {|| open ~/.config/erp.pw | str trim } }
  # or auth: { type: bearer, token: "…" }        # type is inferred from user/token when absent
  headers: { … }                                 # sent with every request
  params: { sap-client: "100" }                  # query parameters on every request
  sap: true                                      # CSRF handling; inferred from the URL
  description: "…"
}
```

A password or token may be a closure, evaluated when a request needs it.

### The schema

```
odata entities                       entity sets and singletons with type, keys, property count, navigations, label
odata schema <entity> [nav...]       fields: name, kind (key|property|navigation), type, nullable, label, enum members, extra (sap:* annotations)
odata schema                         the whole record, types and complex types listed by name
odata schema --raw                   the whole record as parsed
odata refresh [-s <name>]            re-fetch $metadata now
odata catalog [--v4] [-f <filter>]   SAP Gateway: every service on the system behind a registered one
odata status                         cache files and session memos with their age
```

## Query options, flags and pipeline stages

Every query option the module sends has a flag on `odata get` and, where a
Nushell stage means the same thing, that stage is pushed by the hook:

| query option | flag | pipeline stage | combined as |
|---|---|---|---|
| `$filter` | `--filter` | `where <cond>`, `where {\|p\| …}` | flag `and` stage |
| `$select` | `--select` | `select A B`, `get A`, `get A.B` | flag wins; stage adds what earlier stages read |
| `$expand` | `--expand` | `expand Nav …`, and any navigation a `select`/`get`/`where`/`sort-by` touches | union by navigation name |
| `$orderby` | `--orderby` | `sort-by A B.C [-r]` | flag wins |
| `$top` | `--top` | `first N`, `take N`, `is-empty`, `is-not-empty`, `columns` (1) | minimum |
| `$skip` | `--skip` | `skip N` | sum |
| `$count` (`/$count`) | `--count`, `odata count` | `length` | |
| `$search` (V4) | `--search` | `find word` | flag then stage, space-joined (AND) |
| `$format=json` (V2) | | | always |
| anything else (`sap-client`, `$apply`) | `--param {…}` | | |

`--all`, `--raw`, `--url`, `--meta`, `--headers` are not query options.
`$apply` (aggregation) has no flag of its own and no stage; `--param` or
`odata raw` reach it.

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

**The hook** (`modules/odata (activate)`) runs on every Enter. A line without the
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
re-fetched after `ODATA_METADATA_TTL` or `odata refresh`.

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

## Completion

Per-argument completers are `def`s inside `mod.nu` (a `@complete-…`
annotation on the parameter), not a `completions/*.nu` spec, which is for
externs. They read the context string to find the service (`-s name` or the
current one) and the positionals typed so far.

| position | completer | source |
|---|---|---|
| entity | `complete-entity` | sets and singletons |
| key | `complete-key` | one `$top=N` request, only when `ODATA_COMPLETE_KEYS` is true, memoised 60 s; the only completer that touches the network |
| nav | `complete-nav` | the navigations of the type at the end of the path |
| `--select`, `--filter` | `complete-field` | properties with Edm type, key marker, label |
| `--orderby` | `complete-orderby` | properties, and each again with ` desc` |
| `--expand` | `complete-expand` | navigations |
| `--service`, `service use/remove/show` | `complete-service` | the registry |
| `odata call` | `complete-function` | functions and actions, bound ones marked with what they bind to |
| `odata call … --on` | `complete-on` | the entity set only: a flag takes one value and Nushell does not complete inside `[…]` or a quoted string |
| `\| expand` | `complete-expand-stage` | navigations of the call at the head of the buffer (`commandline`), or of the last call this shell made |

`odata complete columns <segment>` is the provider the smart menu
(`modules/nu-complete/smart.nu`) asks for the columns an `odata …` call
would return, instead of running it. It returns `describe --detailed`-shaped
rows, one per enum member of the longest enum, so `where Gender == ⌶` offers
`Male`, `Female`, … and other columns carry their type and label. Expanded
navigations named on the segment appear as `table` or `record` columns.
`odata` is also on the smart menu's never-run list, so no completion mode
ever issues a request through it.

## Session memos

Short-lived values live in a `stor` table named `odata_memo` (`memo key ttl
closure`): the parsed schema per service (60 s), keys for completion (60 s),
the SAP CSRF token and cookie per service (25 min), the navigation values
kept aside for `expand` after a `select` (10 min). `odata status` lists
them with the cache files. They vanish with the shell.

## Settings

Read at call time through `setting <name> <default>`, which also converts a
string value from the process environment (`"true"`, `"7day"`) to the
default's type.

| knob | default | effect |
|---|---|---|
| `ODATA_SERVICES` | `{}` | the shared registry (see above) |
| `ODATA_SERVICE` | none | the current service for new shells |
| `ODATA_PUSHDOWN` | `true` | apply the hook's plan |
| `ODATA_PUSHDOWN_SEARCH` | `true` | let `find word` become `$search` (V4) |
| `ODATA_COMPLETE_KEYS` | `false` | let Tab fetch keys |
| `ODATA_COMPLETE_KEYS_TOP` | `50` | how many |
| `ODATA_METADATA_TTL` | `7day` | schema cache lifetime |
| `ODATA_DEBUG` | `false` | requests and pushdown decisions on stderr |

They are assigned in `your settings.nu` at startup, which overrides the
process environment; in an interactive test, set them as typed lines.

## Costs

| | |
|---|---|
| startup | +40 ms with `modules/odata (activate)` sourced (`nu-config startup-time`); Nushell parses every `use` at startup, so the module cannot be loaded lazily, trimming it is the only lever |
| hook per Enter, no `odata` on the line | 11 µs |
| hook per Enter, `odata People \| where FirstName =~ Ru or LastName == Ketchum \| select UserName FirstName \| first 2` | 3-4 ms (6.5 ms before words were rebuilt from spans) |
| translate one condition | 1-1.5 ms |
| `odata People \| where ⌶` (smart menu, schema in the session memo) | 3-4 ms |
| `from xml` on `$metadata` (TripPin 16 kB, Northwind 23 kB) | 1.6 ms; the schema walk 19 ms for Northwind's 26 types |
| fetch `$metadata` | 0.8-1.4 s, network, once per service per `ODATA_METADATA_TTL` |
| replicate one row 100 000 times for `length` | 44 ms |
| one request to the public services | 0.7-0.9 s, the network; the shell's part is milliseconds |

## Testing

Without touching the real registry or the loaded config:

```nu
nu -n
use modules/odata *
$env.ODATA_SERVICES = { trippin: { url: "https://services.odata.org/V4/(S(test))/TripPinServiceRW/" } }
$env.ODATA_SERVICE = "trippin"
$env.ODATA_DEBUG = true
odata People --url
odata People russellwhyte Trips | first 2
```

The pieces in isolation:

```nu
# the planner, no network
odata pushdown plan 'odata People | where Age > 30 and Name =~ "x" | select UserName | first 5'
odata pushdown plan 'odata People | where {|p| $p.Gender == Female } | get Trips | is-empty'
odata pushdown plan 'odata People | where Gender == Male | expand Trips'

# the expand stage without the hook: one request per row, same result
odata People | first 2 | expand Trips

# what a plan turns into, no request: set the plan by hand and ask for the URL
$env.ODATA_PUSHDOWN_PLAN = (odata pushdown plan 'odata People | select UserName Trips | first 2')
odata People --url     # …/People?$select=UserName&$expand=Trips&$top=2

# the translator with a cached schema
let s = (odata schema --raw)
use modules/odata/pushdown.nu *
filter-from-nu 'Gender == Female and FirstName =~ "Ru"' $s ($s.types.Person) "4"
# → Gender eq Microsoft.OData.SampleService.Models.TripPin.PersonGender'Female' and contains(FirstName,'Ru')
filter-from-nu 'Age > 30' $s ($s.types.Person) "4"     # → null; with ODATA_DEBUG: "odata filter: unknown field Age"

# the parser on any $metadata document
use modules/odata/metadata.nu *
http get --raw https://services.odata.org/V2/Northwind/Northwind.svc/$metadata | parse-metadata $in | get sets | columns   # --raw: http get would parse the XML itself
```

The hook itself only runs interactively, so `nu -l -c 'odata People | where …'`
runs the stages locally on one page. To test pushdown end to end, drive
`nu -l` in a Python pty (`pty.fork`, answer `ESC[6n` with `ESC[1;1R`, set
`TIOCSWINSZ` or tables render as "Couldn't fit table into 0 columns"), type
whole lines, then strip the escape sequences and drop every line starting
with the prompt, because vi mode repaints the buffer on each keystroke. Set
knobs as typed lines: `your settings.nu` assigns them at startup and
overrides the process environment. `ODATA_DEBUG` shows the `pushed down: …`
line and every request.

Public services, all answering on 2026-09-11:

- TripPin, V4, read-write, any session key in the URL:
  `https://services.odata.org/V4/(S(any))/TripPinServiceRW/`. Writes need
  `If-Match`; `/$count` refuses a `$filter`; `$search` is substring-like.
- Northwind, V2: `https://services.odata.org/V2/Northwind/Northwind.svc/`
  (a bare `d` list, `/Date()/` dates, decimals as strings).
- Northwind, V4: `https://services.odata.org/V4/Northwind/Northwind.svc/`.
- OData reference service, V4: `https://services.odata.org/V4/OData/OData.svc/`.

After any change:

```nu
nu-check modules/odata/mod.nu
nu -l -c 'nu-config doctor'
nu -l -c '"odata Peo" | commandline complete --detailed'
```

## Extending

- **A new query option** (say `$apply`): add the flag to both `odata get`
  and `main`, thread it through `get-opts` into `do-get`'s `params`, and
  add it to `VALUE_FLAGS` in `pushdown.nu` so the planner skips its value.
- **A new pushable stage**: teach `odata pushdown plan` to record it (the
  `match $s.head` block) and `apply-pushdown` to translate it; keep the
  ordering rules so the local re-run gives the same answer, add the columns
  it reads to `needed` and the navigations among them to `expand`.
- **A new condition operator**: `p-comparison` in `pushdown.nu`; add the
  word to `is-field`'s exclusion list and to the planner's "after select"
  filter list, and give it a V2 form or return `null` there.
- **Another dialect quirk**: `unwrap` for the envelope, `clean` for value
  conversion, `literal` for how a value is written into a URL.
- **`$batch`**: not covered; `odata raw` reaches it with a hand-built body.

## Known limits

- Pushdown needs the interactive hook; scripts use the explicit flags or
  `--all`. `expand` still works there, at one request per row and
  navigation.
- Two identical `odata` calls on one line with different downstream stages
  are not pushed.
- A path through a collection navigation (`get Trips.Name`,
  `where Trips.Name == x`) is not pushed; Nushell itself cannot take a cell
  path through a list of records.
- With no schema reachable, a `where` is still translated by value shape,
  but a following `select` is not pushed.
- SAP paths (CSRF, `MERGE`, `odata catalog`, `sap:` annotations) follow
  the documented protocol and are not yet exercised against a live system;
  neither is any service that needs authentication.
- `find` pushed as `$search` is exact only where the server's search is at
  least a substring match on every string property; `ODATA_PUSHDOWN_SEARCH
  = false` otherwise.
- `$batch`, `$apply`, deep inserts and media streams are out of scope.
