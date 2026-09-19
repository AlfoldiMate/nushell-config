# agent: Claude Code inside the shell

This is the design record. The commands, the exec menu, the key bindings and
the knobs are in the [agent reference](../reference/modules/agent.md).

Verified against Nushell 0.115.1 and Claude Code 2.1.268 on 2026-09-11.
Every cost below was measured with `timeit` or read from Claude's own
`duration_ms`; nothing is estimated.

```
agent ask <question>          answer, computed with Nushell pipelines in your directory
agent exec <task>             Nushell commands proposed; you execute, insert, revise, copy
agent skill <name> [text]     a Claude Code skill on this session, Tab completes the names
agent command <name> [text]   a slash command (/context, /model, agmem:checkpoint ...)
agent status                  claude, session, models, caches, stale sessions
agent commands                every skill and command the session can run
agent checkpoint              /agmem:checkpoint now
agent reset                   new session; the old one is checkpointed in the background
agent completion <tool>       teach Tab a tool: the `completion` skill writes completions/<tool>.nu
Alt+E                         the line you are typing is the task; the proposal replaces it
```

Pipe text or tables into any verb: `ls | agent ask "which of these is a log?"`.

## Why it is shaped like this

**One `claude -p` per turn, no resident process.** The idea started as a
plugin holding one Claude Code session open over ACP. Measured, the case
for that disappears: spawning `claude` costs 9 to 60 ms, a model round-trip
2.7 to 6 s. Session continuity is what matters, and Claude Code gives it
with `--session-id <uuid>` on the first turn and `--resume <uuid>` after,
persisted in its own store. Claude Code has no native ACP anyway; the
adapter (`@agentclientprotocol/claude-agent-acp`) would add a node process
for two things this design gets elsewhere: permission requests (not needed,
see exec) and the command list (the init record, below).

**Runs from the config repo.** Every turn does `cd ~/.config/nushell` first,
so CLAUDE.md, `.claude/skills/nushell` and the agmem memory of this project
load, and the model is grounded in 0.115 syntax. The two most reported
failures of shell assistants are bash-in-Nushell and invented commands
(codex discussion 296, nushell discussion 16109); the grounding plus the
`nu` MCP server's `command_help` are the mitigation. Your actual directory
travels as `--add-dir` and is spelled out in the system prompt. The cwd is
`$nu.config-path | path dirname`, the path you use yourself, because Claude
Code keys its project by the cwd string and `path self` resolves the macOS
link to `~/Library/Application Support/nushell`.

**exec proposes, the shell executes.** Every prior tool converged on this
(sgpt, aichat, gh copilot's `ghcs`, Warp): a child process cannot touch the
parent's buffer or history. Claude answers through `--json-schema` with
`{commands: [{cmd, why, risk}], note}` and no Bash tool at all; the line you
accept runs through `commandline edit --replace --accept`, in this shell,
with your aliases and `$env`, and lands in history. The aichat menu follows:
execute, insert into the line, revise (the correction goes to the same
session, so "no, with grep" works), copy, quit. Lines matching
`AGENT_CONFIRM` ask for a typed `yes` even with `--yes` (Warp's denylist
that always wins). With stdout not a terminal, or `--print`, exec just
returns the line, so `agent exec ... | save` composes.

**ask runs pipelines through the `nu` MCP server**, registered at user
scope (`claude mcp get nu`), allowlisted under `--permission-mode dontAsk`.
That server loads this config in its own process, so the model's `cd` and
`let` persist within a turn. It is read-only by instruction, not by
enforcement: `evaluate` can run anything, which is why `ask` and `exec` get
different tool lists.

**The prompt travels on stdin.** As an argument it would have to precede
the variadic `--allowedTools`, `--tools` and `--add-dir` (which otherwise
swallow it), and with stdin open but silent, as under `nu -l -c`, claude
waits 3 s before starting. Fed or closed, a trivial haiku turn is 2.9 s
either way.

**Context per turn** (`--append-system-prompt`): Nushell version, OS, your
directory, `$ans` (the previous command, its exit code and duration), the
last eight history entries with non-zero exit codes marked, and the
Nushell-not-bash reminders. Butterfish's author found "see the previous
command and its result" is what makes "why did that fail?" work; `$ans.last`
would add the previous output but needs `max_last_result_size`, off by
default.

**Skill and command names come from Claude itself.** The first line of
every stream-json turn is an init record listing `slash_commands` (59 here)
and `skills` (20); it is cached in `.state/agent/commands.nuon`. Before the
first turn, Tab falls back to a disk scan of `~/.claude/skills`,
`.claude/skills`, `~/.claude/commands` and the plugin cache, which also
supplies descriptions from frontmatter. `agent commands` is the merged
table (10 ms).

**Checkpoint at the next start, not at exit.** Nushell 0.115 has no exit
hook (only pre_prompt, pre_execution, env_change, display_output,
command_not_found), and background jobs die with the shell. So each turn
records `{id, pid, turns, checkpointed}` in `.state/agent/sessions/`, and
every interactive startup spawns a job (66 µs) that lists that directory.
A session whose pid is gone and that had at least
`AGENT_CHECKPOINT_MIN_TURNS` turns is handed to a detached
`nu -l -c 'agent sweep'` (a double fork through `sh`, verified to outlive
the shell where a `job spawn` child does not), which runs
`/agmem:checkpoint` on it with `--resume`, logs one line to
`.state/agent/sweep.log`, and deletes the file. Two shells starting at once
cannot both checkpoint the same session: the file is renamed to
`.checkpointing` first, and a claim older than 15 minutes is taken back.
The min-turns rule exists because one `ls` question has nothing worth
remembering and a checkpoint is a full turn on the default model.

**`completion` is a skill, not code in the module.** Building a completer
is research (which of a tool's seven possible sources exist), judgement
(what each positional *is* and where the cheapest copy of that list lives)
and verification; the module only launches `/completion <tool>` on a fresh
session with `acceptEdits` and the tools in `AGENT_COMPLETION_TOOLS`, then
checks the result parses and is wired. The deterministic parts are scripts
in `.claude/skills/completion/scripts/` (discovery, help/fish/cobra
parsers, a verifier that runs every slot through `commandline complete` in
one login shell); the judgement is in `SKILL.md` and its references.
[Completion](completion.md) has the engine side.

## Measured

| What | Cost |
|---|---|
| `claude --version` (spawn) | 9 ms warm, 60 ms cold |
| trivial turn, `claude-haiku-4-5` | 2.7 s |
| `agent ask` from ~/Development, sonnet, low effort, one `nu evaluate` call | 3.9 s |
| `agent exec` proposal, sonnet, low effort | 2.1 to 4.3 s |
| `/context` through `agent command` | 1.0 s |
| `agent commands` (cache + disk scan) | 10 ms |
| `history \| last 8` (sqlite) | 1 ms |
| `use agent` at startup | 3 ms (25.2 ms vs 22.5 ms for an empty `nu -n -c`) |
| startup with the module lazy (stub only) | 88 ms, down from 89 to 94 ms when the module body was parsed at startup |
| `job spawn` at startup | 66 µs |

What it does not do, and what is untested, is in the
[reference's limitations](../reference/modules/agent.md#limitations).
