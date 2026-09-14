# settings.nu — the knobs. Start here.
#
# Everything a new machine or a new user is likely to change. `const` values
# are read at parse time because they pick files; the rest are ordinary
# settings. Machine-specific overrides go in autoload/ (gitignored), which
# loads after everything here.

# ── Colours ───────────────────────────────────────────────────────────────────
# A file in themes/ without its .nu, or "dark" / "light" for the neutral themes
# from Nushell's standard library.
#   ls themes/  →  catppuccin-latte  catppuccin-frappe  catppuccin-macchiato  catppuccin-mocha
const THEME = "catppuccin-macchiato"

# vivid theme for `ls` file colours (LS_COLORS); only used when vivid is
# installed. `vivid themes` lists them. Re-run `nu-config tools setup` after
# changing it.
$env.VIVID_THEME = "catppuccin-macchiato"

# ── Editor ────────────────────────────────────────────────────────────────────
# Candidates in order; the first one found on PATH becomes $env.EDITOR,
# $env.VISUAL and the Ctrl+O buffer editor. GUI editors need their blocking flag.
const EDITORS = [
  ["zed" "--wait"]
  ["nvim"]
  ["vim"]
  ["vi"]
]

# ── Line editing ──────────────────────────────────────────────────────────────
# emacs | vi | helix
$env.config.edit_mode = "vi"

# ── Banner ────────────────────────────────────────────────────────────────────
# true | "short" | false
$env.config.show_banner = false

# ── History ───────────────────────────────────────────────────────────────────
# "sqlite" keeps timestamps, cwd and exit codes and is queryable with `history`;
# "plaintext" is one command per line. These are read once at startup.
$env.config.history.file_format = "sqlite"
$env.config.history.max_size = 1_000_000
$env.config.history.isolation = false     # true: ↑ shows only this session's history
$env.config.history.sync_on_enter = true

# ── Completion ────────────────────────────────────────────────────────────────
# Tab runs the pipeline-aware engine in modules/nu-complete (columns, operators
# and values for `where`/`get`/`select`..., no file noise after `ps`, one entry
# per command). false: Nushell's stock completion menu.
const SMART_TAB = true

# To offer columns and values, the engine runs the pipeline typed so far in a
# subprocess. "safe": only when every command in it is a read-only built-in
# (ls, ps, open, where, ...; never an external, never rm/save/http).
# "all": your own commands too, with the config loaded (~80 ms instead of ~20).
# "off": never; Tab still filters and deduplicates.
$env.NU_COMPLETE_EVAL = "safe"

# ── Agent: Claude Code in the shell ───────────────────────────────────────────
# `agent ask | exec | skill | command` (docs/agent.md). One Claude Code
# session per shell, one `claude -p` turn per call, from this repo.
#
# Model and effort per verb: a Claude Code alias (sonnet, opus, fable,
# haiku) or a full model name; null keeps Claude Code's own default. Measured
# on 2026-09-11: a trivial turn takes 2.7 s on haiku, 4.3 s on sonnet at
# low effort, 3.9 s on the default model; ask and exec are short-answer
# work, so they run on sonnet at low effort. Skills keep the default.
$env.AGENT_MODEL = { ask: "sonnet", exec: "sonnet", skill: null, command: null, completion: null }
$env.AGENT_EFFORT = { ask: "low", exec: "low", skill: null, command: null, completion: null }

# `agent exec` never runs anything itself; the line you accept runs in this
# shell. A proposal matching one of these regexes asks for a typed "yes"
# first, even with --yes.
$env.AGENT_CONFIRM = ['\brm\b' '\bkill\b' '\bsudo\b' '\bmv\b' '\bdd\b' 'git push .*(-f\b|--force)' 'reset --hard' '\bsave -f\b' '\btruncate\b']

# What a skill or command turn may do without asking (there is nobody to
# ask in -p mode; anything else is denied and reported). Rules are Claude
# Code permission rules: a tool name, `mcp__<server>` for a whole MCP
# server, `Bash(git status:*)` for a command prefix. Mode: dontAsk denies
# writes; acceptEdits lets skills edit files under the repo and $env.PWD.
$env.AGENT_PERMISSION_MODE = "dontAsk"
$env.AGENT_ALLOWED_TOOLS = ["mcp__plugin_agmem_agmem" "mcp__agmem" "mcp__nu" "Read" "Glob" "Grep" "WebFetch" "WebSearch" "Bash(git branch:*)" "Bash(git status:*)" "Bash(git log:*)"]

# `agent completion <tool>` builds completions/<tool>.nu: it runs the tool's
# help and shipped completions, writes into this repo (acceptEdits) and
# verifies with `nu -l -c`, so it needs Bash and the editing tools. A build
# is 20-60 claude turns; MAX_TURNS caps a runaway one.
$env.AGENT_COMPLETION_TOOLS = ["Bash" "Read" "Write" "Edit" "Glob" "Grep" "WebFetch" "WebSearch" "mcp__nu"]
$env.AGENT_COMPLETION_MAX_TURNS = 150

# Run /agmem:checkpoint on a session once its shell has closed (done by the
# next shell that starts) and on `agent reset`. false: sessions just end.
# A session with fewer turns than MIN_TURNS is dropped instead: one `ls`
# question has nothing worth remembering, and the checkpoint costs a turn.
$env.AGENT_CHECKPOINT = true
$env.AGENT_CHECKPOINT_MIN_TURNS = 3

# ── Tables ────────────────────────────────────────────────────────────────────
# Border style; `table --list` shows every option.
$env.config.table.mode = "markdown"

# ── OData ─────────────────────────────────────────────────────────────────────
# `odata <entity>` reads OData V2/V4 services (SAP Gateway included) as
# tables; modules/odata/README.md. Services you want everywhere go here; `odata service
# add` keeps machine-local ones in .state/odata/services.json (gitignored).
# A password or token may be a closure, read when a request needs it.
$env.ODATA_SERVICES = {
  trippin: { url: "https://services.odata.org/V4/(S(nushell))/TripPinServiceRW/", description: "OData V4 sandbox, read-write" }
  northwind: { url: "https://services.odata.org/V2/Northwind/Northwind.svc/", description: "OData V2 sample, read-only" }
  # erp: { url: "https://host/sap/opu/odata/sap/ZMY_SRV/", params: { sap-client: "100" }
  #        auth: { type: basic, user: "me", password: {|| open ~/.config/erp.pw | str trim } } }
}
$env.ODATA_SERVICE = "trippin"        # default for new shells; `odata service use` changes it

# `odata People | where FirstName =~ Ru | select UserName | first 5`: a
# pre_execution hook turns those stages into $filter/$select/$top so the
# server does the work; the Nushell stages still run on what comes back.
$env.ODATA_PUSHDOWN = true
# `odata People | find russ` → $search=russ (V4). A server whose $search is
# narrower than a substring match on every string property would hide rows
# `find` would show: turn this off for such a service.
$env.ODATA_PUSHDOWN_SEARCH = true

# Tab after `odata <entity> ` fetches keys with one request (memoised 60 s):
# the only completion that touches the network. Off by default.
$env.ODATA_COMPLETE_KEYS = false
$env.ODATA_COMPLETE_KEYS_TOP = 50

$env.ODATA_METADATA_TTL = 7day        # re-fetch $metadata after this (or `odata refresh`)
$env.ODATA_DEBUG = false              # every request and pushdown decision on stderr
