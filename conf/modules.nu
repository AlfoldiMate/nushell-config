# modules.nu — load the enabled modules, eagerly or on first mention
#
# Which modules exist and which are lazy is decided in defaults.nu (MODULES,
# MODULES_LAZY) and overridable in your settings.nu. docs/modules.md explains
# the contract; `nu-config module list` shows the current state.
#
# Why this file is repetitive: `use` is parse-time and cannot sit inside an
# `if` or a loop, so a module cannot be enabled by iterating a list. What CAN
# be done is `source` a const path chosen by a const `if` — `source null` is a
# no-op — so each module gets two lines. That is the whole mechanism, and it
# costs nothing at runtime because it is all resolved while parsing.

const MOD_DIR = $DISTRO_ROOT | path join modules

# Published for tooling (`nu-config module list`); the consts are parse-time
# and invisible to a command.
$env.NU_MODULES = $MODULES
$env.NU_MODULES_LAZY = $MODULES_LAZY

# ── nu-config ─────────────────────────────────────────────────────────────────
# First, and never lazy: `nu-config doctor` is how you diagnose everything
# below it, so it has to load even when something below is broken.
const M_CONFIG = (if ("nu-config" in $MODULES) { ($MOD_DIR | path join nu-config load.nu) } else { null })
source $M_CONFIG

# ── nu-complete ───────────────────────────────────────────────────────────────
const M_COMPLETE = (if ("nu-complete" in $MODULES) and ("nu-complete" not-in $MODULES_LAZY) { ($MOD_DIR | path join nu-complete load.nu) } else { null })
source $M_COMPLETE

# ── agent ─────────────────────────────────────────────────────────────────────
# stub.nu is unconditional while the module is enabled: it mints the session
# id and binds Alt+E without parsing the 18 ms body.
const M_AGENT_STUB = (if ("agent" in $MODULES) { ($MOD_DIR | path join agent stub.nu) } else { null })
source $M_AGENT_STUB
const M_AGENT = (if ("agent" in $MODULES) and ("agent" not-in $MODULES_LAZY) { ($MOD_DIR | path join agent load.nu) } else { null })
source $M_AGENT

# ── terminal ──────────────────────────────────────────────────────────────────
const M_TERMINAL = (if ("terminal" in $MODULES) and ("terminal" not-in $MODULES_LAZY) { ($MOD_DIR | path join terminal load.nu) } else { null })
source $M_TERMINAL

# ── odata ─────────────────────────────────────────────────────────────────────
const M_ODATA = (if ("odata" in $MODULES) and ("odata" not-in $MODULES_LAZY) { ($MOD_DIR | path join odata load.nu) } else { null })
source $M_ODATA

# ── Lazy loading ──────────────────────────────────────────────────────────────
# A `pre_execution` hook fires before Nushell parses the line you typed, and a
# hook given as a STRING is parsed and merged into the global engine state —
# "as if you typed it into the REPL". So `use odata *` in such a hook is in
# scope for the very line that triggered it. Verified in a live REPL against
# 0.115.1; nushell repl.rs:400 and hook.rs:126-144 are the mechanism.
#
# The guard costs 828 ns per Enter on a line that matches nothing.
#
# Limit, by nature: pre_execution never fires for `nu -c` or a script, so a
# lazy module is interactive-only. Scripts must `use <module>` explicitly.
# The hook sources the SAME load.nu the eager path does, so there is exactly
# one place that knows how a given module is imported (`use odata *` and
# `use agent` differ) and the two paths cannot drift apart.
$env.NU_MODULES_LOADED = []
for m in $MODULES_LAZY {
  let words = ([$m] ++ ($MODULES_TRIGGERS | get -o $m | default []) | str join "|")
  let loader = ($MOD_DIR | path join $m load.nu)
  $env.config.hooks.pre_execution ++= [{
    condition: {|| $m not-in $env.NU_MODULES_LOADED and (commandline) =~ $'\b($words)\b' }
    code: $"source '($loader)'; $env.NU_MODULES_LOADED = \($env.NU_MODULES_LOADED | append '($m)'\)"
  }]
}
