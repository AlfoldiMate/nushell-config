# metadata.nu — $metadata (CSDL XML, OData V2 and V4) → one compact schema record
#
# `from xml` parses TripPin (16 kB) or Northwind (23 kB) in 1.6 ms (measured
# 2026-09-11); the walk below is the cost that matters, so it touches each
# element once and keeps only what the shell needs: which entity sets exist,
# their key and property types (to quote keys and convert V2 values), their
# navigation targets (for --expand and nav paths), enums (for value
# completion), and functions/actions (for `odata call`). Prefixed attributes
# arrive with the prefix stripped (`sap:label` → `label`, `m:HttpMethod` →
# `HttpMethod`), which is what makes SAP annotations free to keep.
#
# Shape:
#   { version: "2" | "4", namespaces: [..], fetched_at, url
#     sets:       { People: { type: "Person", bindings: { Trips: "Trips" }, extra: { pageable: "true" } } }
#     singletons: { Me: { type: "Person" } }
#     types:      { Person: { keys: [UserName], base: null,
#                             props: [{ name, type: "Edm.String", nullable, key: bool, label, extra }]
#                             navs:  [{ name, target: "Trip", collection: bool, extra }] } }
#     complex:    { Location: { props: [...] } }
#     enums:      { PersonGender: [{ name: Male, value: "0" }] }
#     functions:  [{ name, namespace, kind: function | action, method: GET | POST, bound: bool,
#                    binding: "Person" | null, binding_collection: bool, params: [{ name, type }], returns, set, import? }] }

const STD_PROP_ATTRS = [Name Type Nullable MaxLength Precision Scale FixedLength Unicode DefaultValue Collation ConcurrencyMode SRID Relationship ToRole FromRole Partner ContainsTarget EntityType Function Action ReturnType HttpMethod IsBound IsComposable EntitySetPath IncludeInServiceDocument]

def kids [node: any, tag: string]: nothing -> list<record> {
  let c = ($node | get -o content)
  if $c == null or ($c | describe) == "string" { return [] }
  $c | where {|k| ($k | get -o tag) == $tag }
}

# "Collection(NS.Person)" → "Person", "NS.Person" → "Person", "Edm.String" stays.
export def "edm-short" [t: any]: nothing -> any {
  if $t == null { return null }
  let inner = ($t | str replace --regex '^Collection\((.*)\)$' '$1')
  if ($inner | str starts-with "Edm.") { $inner } else { $inner | split row "." | last }
}

export def "edm-collection" [t: any]: nothing -> bool { $t != null and ($t | str starts-with "Collection(") }

def extra-attrs [attrs: record]: nothing -> record {
  $attrs | reject -o ...$STD_PROP_ATTRS
}

def parse-props [node: record, keys: list<string>]: nothing -> list<record> {
  kids $node Property | each {|p|
    let a = $p.attributes
    {
      name: $a.Name
      type: $a.Type
      nullable: (($a.Nullable? | default "true") == "true")
      key: ($a.Name in $keys)
      label: ($a.label? | default null)
      extra: (extra-attrs $a)
    }
  }
}

def parse-params [node: record]: nothing -> list<record> {
  kids $node Parameter | each {|p| { name: $p.attributes.Name, type: $p.attributes.Type, mode: ($p.attributes.Mode? | default null) } }
}

# The whole document → the schema record. `xml` is the raw text of $metadata.
export def "parse-metadata" [xml: string]: nothing -> record {
  let root = ($xml | from xml)
  let edmx_version = ($root.attributes.Version? | default "1.0")
  let ds = (kids $root DataServices | get -o 0)
  if $ds == null { error make { msg: "not an OData $metadata document (no DataServices element)" } }
  let version = if ($edmx_version | str starts-with "4") { "4" } else { "2" }
  let schemas = (kids $ds Schema)

  mut types = {}
  mut complex = {}
  mut enums = {}
  mut assocs = {}
  mut sets = {}
  mut singletons = {}
  mut functions = []
  mut imports = []
  mut namespaces = []

  for s in $schemas {
    let ns = ($s.attributes.Namespace? | default "")
    $namespaces ++= [$ns]

    for et in (kids $s EntityType) {
      let keys = (kids $et Key | get -o 0 | default { content: [] } | kids $in PropertyRef | get attributes.Name)
      let navs = (kids $et NavigationProperty | each {|n|
        let a = $n.attributes
        if $version == "4" {
          { name: $a.Name, target: (edm-short $a.Type), collection: (edm-collection $a.Type), partner: ($a.Partner? | default null), extra: (extra-attrs $a) }
        } else {
          { name: $a.Name, relationship: (edm-short $a.Relationship), to_role: $a.ToRole, extra: (extra-attrs $a) }
        }
      })
      $types = ($types | insert $et.attributes.Name {
        keys: $keys
        base: (edm-short ($et.attributes.BaseType? | default null))
        abstract: (($et.attributes.Abstract? | default "false") == "true")
        label: ($et.attributes.label? | default null)
        props: (parse-props $et $keys)
        navs: $navs
      })
    }

    for ct in (kids $s ComplexType) {
      $complex = ($complex | insert $ct.attributes.Name { props: (parse-props $ct []), base: (edm-short ($ct.attributes.BaseType? | default null)) })
    }

    for en in (kids $s EnumType) {
      $enums = ($enums | insert $en.attributes.Name (kids $en Member | each {|m| { name: $m.attributes.Name, value: ($m.attributes.Value? | default null) } }))
    }

    # V2: associations give navigation properties their target and cardinality.
    for as in (kids $s Association) {
      $assocs = ($assocs | insert $as.attributes.Name {
        ends: (kids $as End | each {|e| { role: $e.attributes.Role, type: (edm-short $e.attributes.Type), multiplicity: ($e.attributes.Multiplicity? | default "*") } })
      })
    }

    # V4: schema-level functions and actions; imports in the container refer to them.
    # A bound one takes the entity (or entity collection) it is called on
    # as its first parameter; that parameter becomes `binding`, and the
    # namespace is kept because the URL needs the qualified name.
    for f in (kids $s Function) {
      let bound = (($f.attributes.IsBound? | default "false") == "true")
      let params = (parse-params $f)
      $functions ++= [{ name: $f.attributes.Name, namespace: $ns, kind: "function", method: "GET", bound: $bound, binding: (if $bound { edm-short ($params | get -o 0.type) } else { null }), binding_collection: ($bound and (edm-collection ($params | get -o 0.type))), params: (if $bound { $params | skip 1 } else { $params }), returns: (kids $f ReturnType | get -o 0.attributes.Type), set: null }]
    }
    for a in (kids $s Action) {
      let bound = (($a.attributes.IsBound? | default "false") == "true")
      let params = (parse-params $a)
      $functions ++= [{ name: $a.attributes.Name, namespace: $ns, kind: "action", method: "POST", bound: $bound, binding: (if $bound { edm-short ($params | get -o 0.type) } else { null }), binding_collection: ($bound and (edm-collection ($params | get -o 0.type))), params: (if $bound { $params | skip 1 } else { $params }), returns: (kids $a ReturnType | get -o 0.attributes.Type), set: null }]
    }

    for c in (kids $s EntityContainer) {
      for es in (kids $c EntitySet) {
        let a = $es.attributes
        $sets = ($sets | insert $a.Name {
          type: (edm-short $a.EntityType)
          bindings: (kids $es NavigationPropertyBinding | each {|b| { $b.attributes.Path: $b.attributes.Target } } | into record)
          label: ($a.label? | default null)
          extra: (extra-attrs $a)
        })
      }
      for sg in (kids $c Singleton) {
        $singletons = ($singletons | insert $sg.attributes.Name { type: (edm-short $sg.attributes.Type) })
      }
      for fi in (kids $c FunctionImport) {
        let a = $fi.attributes
        if $version == "4" {
          $imports ++= [{ name: $a.Name, ref: (edm-short $a.Function), set: ($a.EntitySet? | default null) }]
        } else {
          $functions ++= [{ name: $a.Name, namespace: $ns, kind: "function", method: ($a.HttpMethod? | default "GET"), bound: false, binding: null, binding_collection: false, params: (parse-params $fi), returns: ($a.ReturnType? | default null), set: ($a.EntitySet? | default null) }]
        }
      }
      for ai in (kids $c ActionImport) {
        let a = $ai.attributes
        $imports ++= [{ name: $a.Name, ref: (edm-short $a.Action), set: ($a.EntitySet? | default null) }]
      }
    }
  }

  # V2 navigation targets from the association ends.
  if $version == "2" {
    let assocs = $assocs
    $types = ($types | items {|tname, t|
      { $tname: ($t | update navs {|| $t.navs | each {|n|
        let end = ($assocs | get -o $n.relationship | default { ends: [] } | get ends | where role == $n.to_role | get -o 0)
        { name: $n.name, target: ($end.type? | default null), collection: (($end.multiplicity? | default "*") == "*"), partner: null, extra: $n.extra }
      } }) }
    } | into record)
  }

  # Inheritance: a derived type sees its base's keys, properties and navigations.
  for _ in 1..3 {
    let cur = $types
    $types = ($cur | items {|tname, t|
      let base = (if $t.base != null { $cur | get -o $t.base } else { null })
      if $base == null { { $tname: $t } } else {
        let own = ($t.props | get name)
        let ownn = ($t.navs | get name)
        { $tname: ($t
          | update keys (if ($t.keys | is-empty) { $base.keys } else { $t.keys })
          | update props (($base.props | where name not-in $own) ++ $t.props)
          | update navs (($base.navs | where name not-in $ownn) ++ $t.navs)) }
      }
    } | into record)
  }

  # V4 imports: mark the unbound functions/actions that are callable by name.
  let imports = $imports
  let functions = ($functions | each {|f|
    let imp = ($imports | where ref == $f.name | get -o 0)
    if $imp == null { $f } else { $f | update set $imp.set | insert import $imp.name }
  })

  {
    version: $version
    edmx: $edmx_version
    namespaces: ($namespaces | uniq)
    sets: $sets
    singletons: $singletons
    types: $types
    complex: $complex
    enums: $enums
    functions: $functions
  }
}

# The entity type record behind an entity set (or singleton), or null.
export def "schema type-of" [schema: record, set: string]: nothing -> any {
  let s = ($schema.sets | get -o $set | default ($schema.singletons | get -o $set))
  if $s == null { return null }
  $schema.types | get -o $s.type
}

# Edm type → the Nushell type the smart menu reasons with (operators, samples).
export def "edm-nu-type" [schema: record, t: any]: nothing -> string {
  if $t == null { return "any" }
  if (edm-collection $t) { return "list" }
  let short = (edm-short $t)
  match $short {
    "Edm.String" | "Edm.Guid" => "string"
    "Edm.Int16" | "Edm.Int32" | "Edm.Int64" | "Edm.Byte" | "Edm.SByte" => "int"
    "Edm.Decimal" | "Edm.Double" | "Edm.Single" => "float"
    "Edm.Boolean" => "bool"
    "Edm.DateTime" | "Edm.DateTimeOffset" | "Edm.Date" => "datetime"
    "Edm.Duration" | "Edm.Time" | "Edm.TimeOfDay" => "duration"
    "Edm.Binary" | "Edm.Stream" => "binary"
    _ => (if ($schema.enums | get -o $short) != null { "string" } else if ($schema.complex | get -o $short) != null { "record" } else if ($schema.types | get -o $short) != null { "record" } else { "any" })
  }
}
