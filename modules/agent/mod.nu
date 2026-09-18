# agent — a Claude Code session inside this shell
#
#   agent ask <question>          answer, computed with Nushell pipelines
#   agent exec <task>             propose Nushell commands; you execute/insert/revise
#   agent skill <name> [text]     run a Claude Code skill      (Tab completes names)
#   agent command <name> [text]   run a slash command          (Tab completes names)
#   agent completion <tool>       teach Tab a tool: builds completions/<tool>.nu
#   agent status | commands | checkpoint | reset | line | sweep
#
# One Claude Code session per shell session. Every turn is one `claude -p`
# run from this repo (so CLAUDE.md, the nushell skill and agmem load) with
# `--session-id` on the first turn and `--resume` after; spawning claude
# costs 9-60 ms against a 3-6 s model round-trip, so nothing stays resident.
# `exec` never lets Claude run anything: it returns JSON through --json-schema
# and the live shell runs the chosen line via `commandline edit --accept`,
# so it sees your aliases and $env and lands in history. Nushell has no exit
# hook, so a finished session is checkpointed (/agmem:checkpoint) by the next
# shell that starts and finds its pid gone (`agent sweep`, modules/agent/stub.nu).
# docs/agent.md has the design, the measurements and the knobs.

# modules/agent/mod.nu → the repo, for files in it.
const ROOT = (path self | path dirname | path dirname | path dirname)

# Where claude runs. Claude Code keys its project (sessions, memory dir) by
# the cwd string, so this must be the path you use yourself: the config path
# as Nushell was given it (~/.config/nushell), not the link target `path self`
# resolves to on macOS (~/Library/Application Support/nushell).
def repo []: nothing -> path { $nu.config-path | path dirname }

# ── Settings your settings.nu, with defaults ────────────────────────────────

# A knob from settings.nu, or its default. A value that came through the
# process environment (the detached sweep, `AGENT_DEBUG=true nu`) is a
# string, so it is coerced to the default's type.
def setting [name: string, default: any]: nothing -> any {
  let v = ($env | get -o $name)
  if $v == null { return $default }
  match [($default | describe) ($v | describe)] {
    ["bool" "string"] => ($v == "true")
    ["int" "string"] => ($v | into int)
    _ => $v
  }
}

def model-for [verb: string]: nothing -> any { setting AGENT_MODEL {} | get -o $verb }
def effort-for [verb: string]: nothing -> any { setting AGENT_EFFORT {} | get -o $verb }

# ── State: $nu.data-dir/.state/agent (your config dir, never the distro) ──────

def state-dir []: nothing -> path { $nu.data-dir | path join .state agent }
def sessions-dir []: nothing -> path { state-dir | path join sessions }
def commands-cache []: nothing -> path { state-dir | path join commands.nuon }
def sweep-log []: nothing -> path { state-dir | path join sweep.log }

def session-id []: nothing -> string {
  let id = ($env.AGENT_SESSION_ID? | default "")
  if ($id | is-empty) {
    error make {msg: "AGENT_SESSION_ID is not set", help: "modules/agent/stub.nu sets one per shell at startup; run `agent reset` to mint one now"}
  }
  $id
}

def session-file [id: string]: nothing -> path { sessions-dir | path join $"($id).nuon" }

def new-session [id: string]: nothing -> record {
  {id: $id, pid: $nu.pid, started: (date now), cwd: $env.PWD, turns: 0, last: null, checkpointed: false}
}

def session-read [id: string]: nothing -> record {
  let f = (session-file $id)
  if ($f | path exists) { open $f } else { new-session $id }
}

def session-write [rec: record]: nothing -> nothing {
  mkdir (sessions-dir)
  $rec | save -f (session-file $rec.id)
}

def pid-alive [pid: int]: nothing -> bool {
  if $nu.os-info.name == "windows" {
    ps | where pid == $pid | is-not-empty
  } else {
    (do { ^kill -0 $pid } | complete).exit_code == 0
  }
}

def claude-bin []: nothing -> path {
  let c = (which claude | get -o 0.path)
  if $c == null {
    error make {msg: "claude (Claude Code) is not on PATH", help: "https://code.claude.com/docs/en/quickstart"}
  }
  $c
}

# ── Context: what the model is told about this shell, every turn ──────────────

def recent-commands []: nothing -> list<string> {
  try {
    history | last 8 | each {|h|
      let code = ($h | get -o exit_status | default 0)
      if $code == 0 { $h.command } else { $"($h.command)   # exit ($code)" }
    }
  } catch { [] }
}

def context [instructions: string]: nothing -> string {
  let last = (if ($ans | describe -d).type == "record" {
    $"Last command: `($ans.command)` → exit ($ans.exit_code) in ($ans.duration)"
  } else { "" })
  let recent = (recent-commands)
  let recent_block = (if ($recent | is-empty) { "" } else {
    $"Recent commands \(oldest first\):\n(($recent | each {|c| $'  ($c)' } | str join "\n"))"
  })
  [
    $"You are `agent`, an assistant inside the user's interactive Nushell ((version).version) session on ($nu.os-info.name) ($nu.os-info.arch)."
    $"The user's working directory is ($env.PWD) — that is what \"here\" and \"this folder\" mean. Your own process runs in their Nushell config repo \((repo)\); do not confuse the two."
    $last
    $recent_block
    "Speak Nushell, never bash: `;` not `&&`, `ls | where size > 1mb`, `open file.json | get key`, `http get`, `$env.HOME`, `^cmd` for an external, `| lines`, `| into int`, `str contains`, `each {|x| ... }`. Nushell changes syntax between minor versions: when unsure about a command's flags, check `command_help` from the nu MCP server rather than guessing."
    $instructions
  ] | where ($it | is-not-empty) | str join "\n\n"
}

# ── One turn ──────────────────────────────────────────────────────────────────

def tool-label [name: string]: nothing -> string {
  $name | str replace --regex '^mcp__' '' | str replace --all '__' ' '
}

def compact-input [input: any]: nothing -> string {
  let s = (match ($input | describe -d).type {
    "record" => ($input | values | each {|v| $v | to text } | str join " · ")
    _ => ($input | to text)
  })
  let s = ($s | str replace --all "\n" "⏎")
  if ($s | str length) > 100 { ($s | str substring 0..99) + "…" } else { $s }
}

# Fold one stream-json line into the accumulator, printing as it goes.
def fold-line [acc: record, line: string, quiet: bool]: nothing -> record {
  let ev = (do -i { $line | from json })
  if ($ev | describe -d).type != "record" { return $acc }
  match ($ev | get -o type) {
    "system" => {
      if ($ev | get -o subtype) == "init" {
        mkdir (state-dir)
        {skills: ($ev | get -o skills | default []), commands: ($ev | get -o slash_commands | default []), at: (date now)}
        | save -f (commands-cache)
      }
      $acc
    }
    "stream_event" => {
      let e = $ev.event
      match $e.type {
        "content_block_delta" => {
          if (not $quiet) and $e.delta.type == "text_delta" {
            print -n $e.delta.text
            $acc | update text true | update printed true
          } else { $acc }
        }
        "content_block_stop" => {
          if $acc.text { print "" }
          $acc | update text false
        }
        _ => $acc
      }
    }
    "assistant" => {
      for b in ($ev | get -o message.content | default []) {
        # StructuredOutput is how --json-schema answers come back, not a tool the user cares about.
        if ($b | get -o type) == "tool_use" and $b.name != "StructuredOutput" {
          print $"(ansi dark_gray)  ⟶ (tool-label $b.name)  (compact-input ($b | get -o input | default {}))(ansi reset)"
        }
      }
      $acc
    }
    "user" => {
      for b in ($ev | get -o message.content | default []) {
        if ($b | describe -d).type == "record" and ($b | get -o type) == "tool_result" and ($b | get -o is_error | default false) {
          print $"(ansi yellow)  ✗ (compact-input ($b | get -o content | default ''))(ansi reset)"
        }
      }
      $acc
    }
    "result" => { $acc | update result $ev }
    _ => $acc
  }
}

# One `claude -p` turn on a session. Streams text unless --quiet; returns the
# result record ({subtype, is_error, result, structured_output, duration_ms,
# total_cost_usd, num_turns, permission_denials, session_id}).
def turn [
  prompt: string
  --verb: string = "ask"           # picks model and effort from settings
  --instructions: string = ""      # appended to the system prompt
  --tools: string                  # built-in tool set, e.g. "Read,Glob,Grep"
  --allow: list<string> = []       # --allowedTools rules
  --mode: string = "dontAsk"       # --permission-mode
  --schema: string                 # --json-schema → structured_output
  --max-turns: int = 12
  --quiet                          # no text streaming (structured output, sweep)
  --session: record                # session record to use instead of this shell's
]: nothing -> record {
  let bin = (claude-bin)
  let rec = ($session | default (session-read (session-id)))
  # The prompt travels on stdin: as an argument it would have to come before
  # the variadic --allowedTools/--tools/--add-dir, and with stdin open but
  # silent claude waits 3 s for it before starting (measured: 2.9 s per
  # trivial haiku turn either way once stdin is fed or closed).
  mut args = [
    "-p" "--output-format" "stream-json" "--verbose" "--include-partial-messages"
    "--permission-mode" $mode "--max-turns" ($max_turns | into string)
    "--append-system-prompt" (context $instructions)
  ]
  $args ++= (if $rec.turns > 0 { ["--resume" $rec.id] } else { ["--session-id" $rec.id] })
  let model = (model-for $verb)
  if $model != null { $args ++= ["--model" $model] }
  let effort = (effort-for $verb)
  if $effort != null { $args ++= ["--effort" $effort] }
  if $tools != null { $args ++= ["--tools" $tools] }
  if ($allow | is-not-empty) { $args ++= ["--allowedTools" ($allow | str join ",")] }
  if $schema != null { $args ++= ["--json-schema" $schema] }
  let cwd = (repo)
  if ($env.PWD | path expand) != ($cwd | path expand) { $args ++= ["--add-dir" $env.PWD] }
  let argv = $args
  if (setting AGENT_DEBUG false) { print $"(ansi dark_gray)claude ($argv | each {|a| if ($a =~ '[\s"]') { $a | to json } else { $a } } | str join ' ')(ansi reset)" }

  let acc = (try {
    do { cd $cwd; $prompt | ^$bin ...$argv }
    | lines
    | reduce -f {result: null, text: false, printed: false} {|line, acc| fold-line $acc $line $quiet }
  } catch {|e|
    {result: null, text: false, printed: false, error: $e.msg}
  })
  if $acc.result == null {
    error make {msg: $"claude exited without a result(if ($acc | get -o error) != null { $': ($acc.error)' })", help: "the message above is claude's own; `agent status` shows the session"}
  }
  let r = $acc.result
  # Built-in slash commands (/context, /model, ...) answer in the result only.
  if (not $quiet) and (not $acc.printed) {
    let text = ($r | get -o result | default "")
    if ($text | is-not-empty) { print $text } else { print $"(ansi dark_gray)\(no output\)(ansi reset)" }
  }
  if not ($r | get -o is_error | default false) {
    session-write ($rec | update turns ($rec.turns + 1) | update last (date now) | update cwd $env.PWD)
  }
  $r
}

def footer [r: record, verb: string]: nothing -> nothing {
  let secs = (($r | get -o duration_ms | default 0) / 1000 | math round --precision 1)
  let cost = ($r | get -o total_cost_usd | default 0)
  let cost_s = (if $cost > 0 { $"  ·  $($cost | math round --precision 3)" } else { "" })
  print $"(ansi dark_gray)(model-for $verb | default 'default model')  ·  ($secs) s($cost_s)(ansi reset)"
  let denied = ($r | get -o permission_denials | default [])
  if ($denied | is-not-empty) {
    let names = ($denied | each {|d| tool-label ($d | get -o tool_name | default '?') } | uniq | str join ", ")
    print $"(ansi yellow)denied: ($names) — add a rule to AGENT_ALLOWED_TOOLS or change AGENT_PERMISSION_MODE \your settings.nu\)(ansi reset)"
  }
  if ($r | get -o is_error | default false) {
    print $"(ansi red)claude reported ($r | get -o subtype | default 'an error')(ansi reset)"
  }
}

# Text piped into a verb becomes part of the prompt.
def with-input [prompt: string, piped: any]: nothing -> string {
  if $piped == null { return $prompt }
  let text = (if (($piped | describe) =~ '^(table|record|list)') { $piped | to nuon --indent 2 } else { $piped | to text })
  let text = (if ($text | str length) > 30000 { ($text | str substring 0..29999) + "\n…(truncated)" } else { $text })
  $"($prompt)\n\nInput piped from the shell:\n```\n($text)\n```"
}

# ── ask ───────────────────────────────────────────────────────────────────────

# Ask a question; Claude computes the answer with Nushell pipelines in your directory.
export def ask [...question: string]: any -> nothing {
  let piped = $in
  let q = ($question | str join " ")
  if ($q | is-empty) { error make {msg: "agent ask <question>"} }
  let r = (turn (with-input $q $piped) --verb ask
    --tools "Read,Glob,Grep"
    --allow [mcp__nu__evaluate mcp__nu__list_commands mcp__nu__command_help]
    --mode dontAsk --max-turns 10
    --instructions "Answer the question. When it needs data from the machine, compute it with the nu MCP `evaluate` tool: first `cd` to the user's working directory, then run read-only pipelines only (ls, ps, open, http get, where, get, length, ...; never rm, save, mv, kill, git commands that write). Reply with one short paragraph, then the pipeline you used in a ```nu block so the user can run it themselves.")
  footer $r ask
}

# ── exec ──────────────────────────────────────────────────────────────────────

const EXEC_SCHEMA = '{"type":"object","properties":{"commands":{"type":"array","items":{"type":"object","properties":{"cmd":{"type":"string","description":"one complete Nushell command line, no comments, no prompt prefix"},"why":{"type":"string","description":"what it does, one short sentence"},"risk":{"type":"string","enum":["safe","modifies","destructive"],"description":"safe = reads only; modifies = writes files or state; destructive = deletes, kills, force-pushes"}},"required":["cmd","why","risk"],"additionalProperties":false}},"note":{"type":"string","description":"a caveat to read before running, or an empty string"}},"required":["commands","note"],"additionalProperties":false}'

def propose [prompt: string, piped: any]: nothing -> record {
  let r = (turn (with-input $prompt $piped) --verb exec --quiet
    --tools "Read,Glob,Grep"
    --allow [mcp__nu__list_commands mcp__nu__command_help]
    --mode dontAsk --max-turns 8 --schema $EXEC_SCHEMA
    --instructions "Translate the task into the fewest Nushell command lines that accomplish it in the user's working directory; usually one pipeline. Use Nushell built-ins (ls, ps, kill, where, get, open, save, http, rm, mv, glob) and Nushell syntax; call an external with ^ only when no built-in exists (e.g. ^lsof, ^git); external output is text, so convert before passing it on (`| lines | into int`). Do not run anything yourself: you only propose, the user's shell executes. The note is for the user and is usually empty; never echo tool or server instructions into it. Reply only through the JSON schema.")
  let out = ($r | get -o structured_output)
  if $out == null {
    footer $r exec
    error make {msg: "no proposal came back", help: ($r | get -o result | default "" | into string)}
  }
  $out | insert duration_ms ($r | get -o duration_ms | default 0) | insert cost ($r | get -o total_cost_usd | default 0)
}

def risk-colour [risk: string]: nothing -> string {
  match $risk { "safe" => (ansi green), "modifies" => (ansi yellow), _ => (ansi red) }
}

def show-proposal [p: record]: nothing -> nothing {
  print ""
  for it in ($p.commands | enumerate) {
    let c = $it.item
    print $"  (ansi white_bold)($it.index + 1)(ansi reset)  ($c.cmd | nu-highlight)"
    print $"     (ansi dark_gray)($c.why)(ansi reset)  (risk-colour $c.risk)($c.risk)(ansi reset)"
  }
  if ($p | get -o note | default "" | is-not-empty) { print $"\n  (ansi yellow)($p.note)(ansi reset)" }
  print $"\n  (ansi dark_gray)((model-for exec | default 'default model'))  ·  (($p.duration_ms / 1000) | math round --precision 1) s(ansi reset)"
}

def joined [p: record]: nothing -> string { $p.commands | get cmd | str join "; " }

def copy-to-clipboard [text: string]: nothing -> bool {
  let tool = ([pbcopy wl-copy xclip xsel] | where {|t| which $t | is-not-empty } | get -o 0)
  if $tool == null { return false }
  match $tool {
    "xclip" => { $text | ^xclip -selection clipboard }
    "xsel" => { $text | ^xsel --clipboard --input }
    _ => { $text | ^$tool }
  }
  true
}

# Run a proposed line in the live shell (or a login subshell when there is no REPL).
def run-line [line: string]: nothing -> nothing {
  let guarded = (setting AGENT_CONFIRM [] | where {|p| $line =~ $p })
  if ($guarded | is-not-empty) {
    print $"(ansi red)matches AGENT_CONFIRM ($guarded | str join ', ')(ansi reset)"
    let ok = (input "  type yes to run it: ")
    if ($ok | str trim) != "yes" { print "  not run"; return }
  }
  if $nu.is-interactive {
    commandline edit --replace $line --accept
  } else {
    nu -l -c $line
  }
}

# Describe a task; Claude proposes Nushell commands, you choose what happens.
# --yes runs without the menu (AGENT_CONFIRM patterns still ask); --print or a
# non-terminal stdout returns the line instead of showing the menu.
export def exec [...task: string, --yes (-y), --print (-p)]: any -> any {
  let piped = $in
  let t = ($task | str join " ")
  if ($t | is-empty) { error make {msg: "agent exec <task>"} }
  mut p = (propose $"Task: ($t)" $piped)
  if $print or not (is-terminal --stdout) { return (joined $p) }
  if $yes { run-line (joined $p); return }
  loop {
    show-proposal $p
    print $"\n  (ansi white_bold)Enter(ansi reset)/(ansi white_bold)e(ansi reset)xecute  (ansi white_bold)i(ansi reset)nsert  (ansi white_bold)r(ansi reset)evise  (ansi white_bold)c(ansi reset)opy  (ansi white_bold)q(ansi reset)uit"
    let key = (input listen --types [key] | get code)
    match $key {
      "e" | "enter" => { run-line (joined $p); return }
      "i" => { commandline edit --replace (joined $p); return }
      "c" => {
        if (copy-to-clipboard (joined $p)) { print "  copied" } else { print "  no clipboard tool found (pbcopy, wl-copy, xclip, xsel)" }
        return
      }
      "r" => {
        let rev = (input "  revise › ")
        if ($rev | str trim | is-empty) { continue }
        $p = (propose $"Revise the previous proposal: ($rev)" null)
      }
      "q" | "esc" => { return }
      _ => { continue }
    }
  }
}

# Alt+E (modules/agent/stub.nu): the current line is the task, the proposal replaces it.
export def line []: nothing -> nothing {
  let buf = (commandline | str trim)
  if ($buf | is-empty) { return }
  let line = (joined (propose $"Task: ($buf)" null))
  if ($line | is-not-empty) { commandline edit --replace $line }
}

# ── skill / command ───────────────────────────────────────────────────────────

def frontmatter-description [f: path]: nothing -> string {
  do -i { open --raw $f | lines | first 20 | where $it starts-with "description:" | get -o 0 | default "" | str replace --regex '^description:\s*' '' | str trim --char '"' }
  | default ""
}

# Skills and commands found on disk, with descriptions from their frontmatter.
def scan-commands []: nothing -> table<name: string, kind: string, description: string> {
  let home = ($env.HOME | path join .claude)
  let plugins = ($home | path join plugins cache)
  let skill_files = (
    [(glob ($home | path join skills '*' SKILL.md)) (glob ($ROOT | path join .claude skills '*' SKILL.md))]
    | flatten | each {|f| {name: ($f | path dirname | path basename), kind: skill, file: $f} }
  )
  let plugin_skills = (glob ($plugins | path join '*' '*' '*' skills '*' SKILL.md) | each {|f|
    let parts = ($f | path split)
    {name: $"(($parts | get ($parts | length | $in - 5))):(($f | path dirname | path basename))", kind: skill, file: $f}
  })
  let command_files = (
    [(glob ($home | path join commands '*.md')) (glob ($ROOT | path join .claude commands '*.md'))]
    | flatten | each {|f| {name: ($f | path parse | get stem), kind: command, file: $f} }
  )
  let plugin_commands = (glob ($plugins | path join '*' '*' '*' commands '*.md') | each {|f|
    let parts = ($f | path split)
    {name: $"(($parts | get ($parts | length | $in - 4))):(($f | path parse | get stem))", kind: command, file: $f}
  })
  [$skill_files $plugin_skills $command_files $plugin_commands] | flatten
  | each {|c| {name: $c.name, kind: $c.kind, description: (frontmatter-description $c.file)} }
}

# Every skill and slash command the session can run: the list Claude Code
# reported on the last turn (cached), merged with what is on disk.
export def commands []: nothing -> table<name: string, kind: string, description: string> {
  let cached = (if ((commands-cache) | path exists) { open (commands-cache) } else { {skills: [], commands: []} })
  let disk = (scan-commands)
  let from_cache = (
    ($cached.skills | each {|s| {name: $s, kind: skill} })
    ++ ($cached.commands | where $it not-in $cached.skills | each {|c| {name: $c, kind: command} })
    | each {|c| $c | insert description ($disk | where name == $c.name | get -o 0.description | default "") }
  )
  $from_cache ++ ($disk | where name not-in ($from_cache | get name))
  | uniq-by name | sort-by kind name
}

def skill-names []: nothing -> list {
  commands | where kind == "skill" | each {|c| {value: $c.name, description: $c.description} }
}

def command-names []: nothing -> list {
  commands | each {|c| {value: $c.name, description: $c.description} }
}

def run-slash [name: string, text: list<string>, piped: any, verb: string]: nothing -> nothing {
  let name = ($name | str trim --left --char '/')
  let prompt = ($"/($name) ($text | str join ' ')" | str trim)
  let r = (turn (with-input $prompt $piped) --verb $verb
    --allow (setting AGENT_ALLOWED_TOOLS [])
    --mode (setting AGENT_PERMISSION_MODE "dontAsk")
    --max-turns (setting AGENT_MAX_TURNS 40))
  footer $r $verb
}

# Run a Claude Code skill on this shell's session (Tab completes the names).
export def skill [name: string@skill-names, ...text: string]: any -> nothing {
  run-slash $name $text $in skill
}

# Run a slash command on this shell's session (Tab completes the names).
export def command [name: string@command-names, ...text: string]: any -> nothing {
  run-slash $name $text $in command
}

# ── completion ────────────────────────────────────────────────────────────────

# Teach Tab a tool. Runs the `completion` skill (.claude/skills/completion) on
# a session of its own: it reads the tool's help and shipped completions,
# maps every positional to the tool's own data, writes completions/<tool>.nu,
# wires it in conf/completions.nu and verifies it headless. A build is a
# long multi-turn job, so it never shares the shell's session: `agent ask`
# afterwards stays cheap.
export def completion [
  tool: string            # the command to complete (must be on PATH)
  ...hints: string        # what matters most, e.g. "packages with descriptions"
]: nothing -> nothing {
  if (which $tool | is-empty) { error make {msg: $"($tool) is not on PATH"} }
  let f = ($ROOT | path join completions $"($tool).nu")
  if ($f | path exists) { print $"(ansi dark_gray)completions/($tool).nu exists — it will be extended, not replaced(ansi reset)" }
  let prompt = ($"/completion ($tool) ($hints | str join ' ')" | str trim)
  let r = (turn $prompt --verb completion
    --allow (setting AGENT_COMPLETION_TOOLS ["Bash" "Read" "Write" "Edit" "Glob" "Grep" "WebFetch" "WebSearch" "mcp__nu"])
    --mode "acceptEdits"
    --max-turns (setting AGENT_COMPLETION_MAX_TURNS 150)
    --session (new-session (random uuid)))
  footer $r completion
  if not ($f | path exists) { print $"(ansi yellow)no completions/($tool).nu was written; the output above says why(ansi reset)"; return }
  let ok = (nu-check $f)
  let wired = (open --raw ($ROOT | path join conf completions.nu) | lines | any {|l| $l =~ ("^use " + $tool + "\\.nu") })
  print $"(ansi cyan_bold)completions/($tool).nu(ansi reset)  parse (if $ok { $'(ansi green)ok(ansi reset)' } else { $'(ansi red)FAILS(ansi reset)' })  wired (if $wired { $'(ansi green)ok(ansi reset)' } else { $'(ansi yellow)no: add `use ($tool).nu *` to conf/completions.nu(ansi reset)' })"
  print $"load it in this shell:  (ansi white_bold)use ($tool).nu *(ansi reset)   \(new shells load it at startup\)"
}

# ── session lifecycle ─────────────────────────────────────────────────────────

# Store what this session learned (/agmem:checkpoint) and mark it done.
export def checkpoint [--quiet (-q)]: nothing -> nothing {
  let rec = (session-read (session-id))
  if $rec.turns == 0 { if not $quiet { print "nothing to checkpoint: this session has no turns yet" }; return }
  checkpoint-session $rec $quiet | ignore
}

def checkpoint-session [rec: record, quiet: bool]: nothing -> record {
  # The emphasis text keeps the checkpoint on this session's own subject. Without
  # it a shell session's checkpoint reads the config repo's git status and writes
  # branch-state claims about work it never did (observed 2026-09-11).
  let r = (turn "/agmem:checkpoint This was an interactive shell-assistant session (agent ask/exec/skill from Nushell), not a coding session on the config repo. Store only what a future shell session would need: facts learned about the user's machine, tools, habits or Nushell usage, and lessons from commands that failed. Do not describe or assess the config repo's branch state." --verb command --quiet=$quiet
    --allow (setting AGENT_ALLOWED_TOOLS [])
    --mode (setting AGENT_PERMISSION_MODE "dontAsk")
    --max-turns 40 --session $rec)
  if not $quiet { footer $r command }
  session-write ($rec | update checkpointed true | update turns ($rec.turns + 1) | update last (date now))
  $r
}

# Start a fresh session; the old one is checkpointed in the background.
export def --env reset [--no-checkpoint]: nothing -> nothing {
  let old = (session-read (session-id))
  if $old.turns > 0 and not $no_checkpoint and (setting AGENT_CHECKPOINT true) {
    job spawn { checkpoint-session $old true | ignore } | ignore
    print $"checkpointing ($old.id) in the background"
  } else if ($old.turns > 0) {
    session-write ($old | update checkpointed true)
  }
  $env.AGENT_SESSION_ID = (random uuid)
  print $"new session ($env.AGENT_SESSION_ID)"
}

# Checkpoint sessions whose shell is gone and that had enough turns to have
# learned something (AGENT_CHECKPOINT_MIN_TURNS); delete the rest. modules/agent/stub.nu runs
# this in a background job at every interactive startup (measured: 66 µs to
# spawn the job; claude only runs when a stale session exists).
export def sweep [
  --detach   # only look; when a session needs a checkpoint, hand the work to a detached `nu -l -c 'agent sweep'`
]: nothing -> nothing {
  let dir = (sessions-dir)
  if not ($dir | path exists) { return }
  if $detach {
    let min_turns = (setting AGENT_CHECKPOINT_MIN_TURNS 3 | into int)
    let pending = (glob ($dir | path join '*.nuon') | where {|f|
      let r = (do -i { open $f })
      ($r | describe -d).type == "record" and (not $r.checkpointed) and $r.turns >= $min_turns and (not (pid-alive $r.pid))
    })
    if (setting AGENT_DEBUG false) { print $"sweep --detach: ($pending | length) session\(s\) pending" }
    if ($pending | is-empty) or $nu.os-info.name == "windows" { return }
    # Background jobs die with the shell, and a shell can close a minute after
    # it opened. A double fork through sh reparents the sweep to init, so the
    # checkpoint finishes regardless (verified: `nohup … &` under sh survives
    # nushell's exit, a `job spawn` child does not).
    let log = (state-dir | path join sweep-detach.log)
    # `use agent` explicitly: `nu -l -c` runs no pre_execution hook, so a lazy
    # agent would not be in scope in the child.
    ^sh -c $"nohup '($nu.current-exe)' -l -c 'use agent; agent sweep' >'($log)' 2>&1 &"
    return
  }
  # A claim left behind by a shell that closed mid-checkpoint is taken back after 15 minutes.
  for f in (glob ($dir | path join '*.checkpointing')) {
    if ((date now) - (ls $f | get 0.modified)) > 15min { mv $f ($f | str replace --regex '\.checkpointing$' '') }
  }
  let debug = (setting AGENT_DEBUG false)
  for f in (glob ($dir | path join '*.nuon')) {
    let rec = (do -i { open $f })
    if ($rec | describe -d).type != "record" { rm -f $f; continue }
    let alive = (pid-alive $rec.pid)
    let worth = ($rec.turns >= (setting AGENT_CHECKPOINT_MIN_TURNS 3 | into int)) and (setting AGENT_CHECKPOINT true)
    if $debug { print $"sweep ($rec.id): pid ($rec.pid) alive=($alive) turns=($rec.turns) worth=($worth) checkpointed=($rec.checkpointed)" }
    if $alive { continue }
    if $rec.checkpointed or not $worth { rm -f $f; continue }
    let claim = $"($f).checkpointing"
    # `continue` cannot sit inside a catch closure, hence the flag.
    let claimed = (try { mv $f $claim; true } catch { false })
    if not $claimed { continue }
    let outcome = (try {
      let r = (checkpoint-session $rec true)
      rm -f $claim
      rm -f $f    # checkpoint-session rewrote it; a checkpointed session of a dead shell is done
      $"($r | get -o subtype | default '?') in ($r | get -o duration_ms | default 0) ms"
    } catch {|e|
      mv -f $claim $f
      $"failed: ($e.msg)"
    })
    $"(date now | format date '%Y-%m-%d %H:%M:%S')  ($rec.id)  ($outcome)\n" | save --append (sweep-log)
  }
}

# ── status ────────────────────────────────────────────────────────────────────

# Where things stand: claude, this session, models, caches, stale sessions.
export def status []: nothing -> nothing {
  let ok = $"(ansi green)ok(ansi reset)"
  let bad = $"(ansi red)!!(ansi reset)"
  let bin = (which claude | get -o 0.path)
  let ver = (if $bin != null { ^claude --version | str trim } else { "not on PATH" })
  print $"(ansi cyan_bold)claude(ansi reset)   (if $bin != null { $ok } else { $bad }) ($ver)"
  let id = ($env.AGENT_SESSION_ID? | default "")
  if ($id | is-empty) {
    print $"(ansi cyan_bold)session(ansi reset)  ($bad) AGENT_SESSION_ID unset — `agent reset`"
  } else {
    let rec = (session-read $id)
    let age = (if $rec.last == null { "no turns yet" } else { $"($rec.turns) turns, last ((date now) - $rec.last | format duration sec) ago" })
    print $"(ansi cyan_bold)session(ansi reset)  ($id)  ($age)(if $rec.checkpointed { '  checkpointed' })"
  }
  let m = (setting AGENT_MODEL {})
  let e = (setting AGENT_EFFORT {})
  print $"(ansi cyan_bold)models(ansi reset)   ask ($m | get -o ask | default 'default')/($e | get -o ask | default '-')  exec ($m | get -o exec | default 'default')/($e | get -o exec | default '-')  skill ($m | get -o skill | default 'default')  command ($m | get -o command | default 'default')"
  print $"(ansi cyan_bold)tools(ansi reset)    ($"(setting AGENT_PERMISSION_MODE 'dontAsk')") + (setting AGENT_ALLOWED_TOOLS [] | str join ', ')"
  let cache = (commands-cache)
  let cached = (if ($cache | path exists) { let c = (open $cache); $"($c.skills | length) skills, ($c.commands | length) commands, ((date now) - $c.at | format duration min) old" } else { "none yet — filled by the first turn; Tab falls back to a disk scan" })
  print $"(ansi cyan_bold)commands(ansi reset) ($cached)"
  let stale = (if ((sessions-dir) | path exists) { glob ((sessions-dir) | path join '*.nuon') | where {|f| let r = (do -i { open $f }); ($r | describe -d).type == "record" and $r.id != $id and not (pid-alive $r.pid) } | length } else { 0 })
  print $"(ansi cyan_bold)state(ansi reset)    (state-dir)  ($stale) stale session\(s\) awaiting sweep"
  if ((sweep-log) | path exists) {
    print $"(ansi cyan_bold)sweeps(ansi reset)   (open --raw (sweep-log) | lines | last 3 | str join (char newline + '         '))"
  }
}

# ── Activation ────────────────────────────────────────────────────────────────
# Run once the module is in scope, whether that happened at startup
# (modules/agent/load.nu) or on the first line that said "agent".
# The knobs are read through `setting`, which already carries their defaults,
# so there is nothing to seed here. stub.nu holds what has to happen in every
# shell whether or not this module is ever loaded.
export def --env activate []: nothing -> nothing {
  # Nothing yet: the session id, the Alt+E binding and the sweep are all in
  # stub.nu because they must exist before the module does. Kept as the entry
  # point so the eager and lazy paths stay identical, and so wiring added later
  # has an obvious home.
}
