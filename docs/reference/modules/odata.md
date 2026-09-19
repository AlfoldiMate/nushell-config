# odata

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

This page is the reference: what each file does, every command and flag,
which query option each pipeline stage becomes, completion, the knobs, costs,
testing, extending, and the known limits. How a request is assembled, how the
pushdown is planned and translated, the schema record and the dialect
differences are the design record, [OData](../../concepts/odata.md).
`odata activate` is the wiring; your `settings.nu` holds the knobs. Verified
against Nushell 0.115.1 on 2026-09-11 with the public TripPin (V4,
read-write) and Northwind (V2) services; every cost was measured with
`timeit` on this machine. SAP Gateway support follows the documented protocol
and is marked where no live system has exercised it.

## Files

| file | lines | concern |
|---|---|---|
| `mod.nu` | ~870 | the `odata …` commands, the service registry, the schema cache, the transport (`request`, `write`, CSRF), response unwrapping and V2 conversion, per-argument completers, the smart-menu provider, and `apply-pushdown` |
| `pushdown.nu` | ~340 | Nushell values → OData literals; a row condition (`Age > 30 and Name =~ "x"`) → `$filter`; `odata pushdown plan`, which reads a whole command line and records the stages after each `odata` call |
| `metadata.nu` | ~225 | `$metadata` (CSDL XML, V2 or V4) → one compact schema record; `schema type-of`, `edm-short`, `edm-nu-type` |

`mod.nu` imports the other two with `use … *`, and re-exports only
`odata pushdown plan` (the hook in `odata activate` calls it). Everything
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
wins over `$nu.data-dir/.state/odata/services.nuon`, which `service add`
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

## Configuration

Read at call time through `setting <name> <default>`, which also converts a
string value from the process environment (`"true"`, `"7day"`) to the
default's type.

| knob | default | effect |
|---|---|---|
| `ODATA_SERVICES` | `{}` | the shared registry (*The registry*, above) |
| `ODATA_SERVICE` | none | the current service for new shells |
| `ODATA_PUSHDOWN` | `true` | apply the hook's plan |
| `ODATA_PUSHDOWN_SEARCH` | `true` | let `find word` become `$search` (V4) |
| `ODATA_COMPLETE_KEYS` | `false` | let Tab fetch keys |
| `ODATA_COMPLETE_KEYS_TOP` | `50` | how many |
| `ODATA_METADATA_TTL` | `7day` | schema cache lifetime |
| `ODATA_DEBUG` | `false` | requests and pushdown decisions on stderr |

They are assigned in `your settings.nu` at startup, which overrides the
process environment; in an interactive test, set them as typed lines.

## Measured

| | |
|---|---|
| loading the module | 97 ms, paid on the first line that mentions `odata` or `expand`, not at startup — it is lazy (`meta.nuon`). +40 ms of startup when it was eager, 2026-09-11 |
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
