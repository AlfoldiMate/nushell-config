# odata.nu — OData services as tables: odata <entity> [key] [nav] | where …
#
# The commands live in modules/odata; the knobs in settings.nu; the design,
# the measurements and the SAP notes in modules/odata/README.md. Nothing here touches
# the network at startup: $metadata is fetched on first use and cached.
use odata *

# Pushdown. `where` cannot be overloaded (a parser keyword) and a hook cannot
# rewrite the line, but the $env a pre_execution hook sets is visible to the
# command that runs. So the hook leaves the plan of what follows each
# `odata …` call, and `odata get` sends as much of it as it can translate.
# Cost per Enter: a `str contains` (µs); with "odata" on the line, `ast
# --flatten` plus the walk (see modules/odata/README.md).
$env.config.hooks.pre_execution = ($env.config.hooks.pre_execution? | default [])
$env.config.hooks.pre_execution ++= [{||
  let line = (commandline)
  $env.ODATA_PUSHDOWN_PLAN = (if ($line | str contains "odata") { try { odata pushdown plan $line } catch { [] } } else { [] })
}]

# The smart Tab menu asks a provider for the columns a command returns
# instead of running it: `odata People | where ⌶` lists fields, typed, with
# enum members as values, from the cached $metadata.
$env.NU_COMPLETE_PROVIDERS = (($env.NU_COMPLETE_PROVIDERS? | default {}) | merge { odata: {|segment| odata complete columns $segment } })
