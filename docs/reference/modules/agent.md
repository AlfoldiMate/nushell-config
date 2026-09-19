# agent

Ask questions, turn a sentence into a Nushell command, run Claude Code
skills and slash commands, all from the prompt, on one Claude session that
follows your shell session. Nothing runs in the background between turns
and nothing runs on your behalf: `exec` proposes, you accept.

```nu
agent ask how many files are here, and which is the newest?
agent exec kill whatever is listening on port 8080
agent skill nushell what does def --env do?
agent command context
```

Requires [Claude Code](https://code.claude.com/docs/en/quickstart) on PATH.
Optional: the [agmem](https://github.com/AlfoldiMate/agmem) plugin for
session checkpoints, and the `nu` MCP server (`claude mcp add nu -s user -- nu --mcp`)
for `agent ask` to compute answers.

Design, measurements and the reasoning behind each choice: [Agent](../../concepts/agent.md).

## Commands

| Command | Does |
|---|---|
| `agent ask <question>` | Answers, computing with read-only Nushell pipelines in your directory, then shows the pipeline so you can run it yourself |
| `agent exec <task>` | Proposes Nushell command lines and opens the menu below. `--yes` runs without the menu, `--print` returns the line |
| `agent skill <name> [text]` | Runs a Claude Code skill on this shell's session. Tab completes the names |
| `agent command <name> [text]` | Runs any slash command: `context`, `model`, `compact`, `agmem:checkpoint` ... Tab completes the names |
| `agent completion <tool> [hint]` | Teaches Tab a tool: builds `completions/<tool>.nu` with subcommands, flags, flag values and live positionals (branches, packages …), wires and verifies it. The `completion` skill does the work on a session of its own |
| `agent status` | claude version, this session, models, tool policy, caches, sessions awaiting checkpoint |
| `agent commands` | Every skill and command the session can run, with descriptions |
| `agent checkpoint` | Runs `/agmem:checkpoint` on this session now |
| `agent reset` | Starts a new session; the old one is checkpointed in the background |
| `agent line` | What Alt+E runs: the current buffer is the task, the proposal replaces it |
| `agent sweep` | Checkpoints sessions whose shell has closed (runs at startup by itself) |

Every verb accepts piped input, which joins the prompt:

```nu
ls | agent ask which of these look like build artefacts?
open Cargo.toml | agent ask what does this crate depend on?
^git log --oneline -20 | agent exec squash these into one commit message draft
```

## The exec menu

```
  1  ^lsof -ti tcp:8080 | lines | into int | each {|p| kill $p }
     find and kill the listener on port 8080  destructive

  Enter/execute  insert  revise  copy  quit
```

| Key | Does |
|---|---|
| Enter, `e` | Runs the line in this shell. It lands in history like anything you typed |
| `i` | Puts the line in the prompt buffer to edit; nothing runs until you press Enter |
| `r` | Asks for a correction ("only python processes") and regenerates on the same session |
| `c` | Copies the line to the clipboard (pbcopy, wl-copy, xclip or xsel) |
| `q`, Esc | Discards the proposal |

A line matching `AGENT_CONFIRM` (rm, kill, sudo, mv, dd, force push, reset
--hard, save -f, truncate by default) asks you to type `yes` first, even
with `--yes`. Several proposed lines run joined with `;`.

With stdout not a terminal, or with `--print`, `exec` skips the menu and
returns the line: `agent exec ... | save cmd.nu`.

## Key bindings

| Key | Where | Does |
|---|---|---|
| Alt+E | prompt, any mode | The line you are typing is the task; Claude's proposal replaces it. Press Enter to run, or edit first |
| Tab | after `agent skill` or `agent command` | Completes skill and command names with their descriptions |
| Enter `e` `i` `r` `c` `q` Esc | exec menu | See above |

Terminal.app needs "Use Option as Meta key" for Alt+E; iTerm2, Ghostty,
WezTerm, Kitty and Alacritty send it by default. To rebind, change the
`agent_line` entry in `modules/agent/stub.nu`.

## What the model knows about your shell

Each turn tells Claude: Nushell version and OS, your working directory
(Claude's own process runs in this config repo), the previous command with
its exit code and duration (`$ans`), the last eight history entries with
failures marked, and a reminder to speak Nushell rather than bash. So
"why did that fail?" and "do that again but sorted by size" work without
pasting anything.

Because the process runs in this repo, `CLAUDE.md`, the `nushell` skill and
the repo's agmem memory load on every turn. That is what keeps proposals in
0.115 syntax.

## Teaching Tab a tool

```nu
agent completion gh                      # cobra: __complete for the tree, flag enums, dynamic positionals
agent completion uv "packages in the venv"
agent completion cargo
```

The `completion` skill (`.claude/skills/completion`) discovers where the
tool's command surface lives (its own `__complete` hook, a shipped fish
file, help text, carapace, nu_scripts), maps every positional to the
cheapest local data (`references/sources.md`), writes
`completions/<tool>.nu` in the shape of brew.nu and git.nu, adds the `use`
line to `conf/completions.nu`, and verifies headless with
`scripts/verify.nu` (every subcommand, every flag slot, carapace as the
oracle). The report says which slots complete from what and what each
costs. The new shell loads it; the current one needs `use <tool>.nu *`.
A build is 20-60 turns on the default model; it runs on its own Claude
session so it does not weigh on `agent ask` afterwards.

## Sessions and checkpoints

One session per shell session, created on the first turn, resumed after.
`agent status` shows its id and turn count. `agent reset` starts a fresh
one when the conversation has drifted.

Nushell has no exit hook, so a session is checkpointed after the fact: the
next shell that starts finds sessions whose shell is gone, and hands any
with at least `AGENT_CHECKPOINT_MIN_TURNS` turns (3) to a detached process
that runs `/agmem:checkpoint` on it. Shorter sessions are dropped, since one
`ls` question has nothing worth remembering. `.state/agent/sweep.log`
records each checkpoint with its duration.

## Configuration

The defaults live in this module (`meta.nuon` declares them, `setting` in
`mod.nu` applies them), so there is nothing to uncomment to get started.
Override a knob in your own `settings.nu`; machine-local tweaks go in
`autoload/`. `nu-config knobs | where owner == agent` lists them.

| Knob | Default | Meaning |
|---|---|---|
| `AGENT_MODEL` | ask/exec `sonnet`, skill/command `null` | Model per verb: an alias (`sonnet`, `opus`, `fable`, `haiku`) or a full name; `null` is Claude Code's default |
| `AGENT_EFFORT` | ask/exec `low` | Effort per verb |
| `AGENT_CONFIRM` | see above | Regexes that force a typed `yes` |
| `AGENT_PERMISSION_MODE` | `dontAsk` | For skill and command turns; `acceptEdits` lets skills edit files |
| `AGENT_ALLOWED_TOOLS` | agmem, nu MCP, Read, Glob, Grep, WebFetch, WebSearch, git read commands | Claude Code permission rules the skill turns may use without asking |
| `AGENT_COMPLETION_TOOLS` | Bash, Read, Write, Edit, Glob, Grep, WebFetch, WebSearch, nu MCP | What a `completion` build may use; it runs with `acceptEdits` in this repo |
| `AGENT_COMPLETION_MAX_TURNS` | `150` | Cap on one build |
| `AGENT_CHECKPOINT` | `true` | Checkpoint finished sessions |
| `AGENT_CHECKPOINT_MIN_TURNS` | `3` | Fewer turns: the session is dropped instead |
| `AGENT_DEBUG` | unset | `true` prints the exact `claude` argv and the sweep's decisions |

Example, in `autoload/agent.nu`:

```nu
$env.AGENT_MODEL.exec = "opus"
$env.AGENT_PERMISSION_MODE = "acceptEdits"
$env.AGENT_CONFIRM ++= ['\bdocker\b.*\b(rm|prune)\b']
```

## Verify

```nu
nu -l -c 'agent status'
nu -l -c '"agent skill ag" | commandline complete --detailed'
cd ~/some/project; nu -l -c 'agent ask how many files are here?'
nu -l -c 'agent exec --print list the 3 largest files here'
```

In a REPL: `agent exec print todays date in iso format`, then `i` puts the
line in the buffer, Enter runs it (verified in a pty on 2026-09-11).

## Files

```
modules/agent/mod.nu        the commands, and `agent activate`
modules/agent/stub.nu       session id, startup sweep, Alt+E — loaded in every
                            shell, so the 18 ms body need not be
modules/agent/load.nu       `use agent` + activate; sourced eagerly or by the
                            lazy hook, so both paths run the same file
modules/agent/meta.nuon     description, dependencies, knobs
<your>/settings.nu          your overrides
<your>/.state/agent/        sessions/, commands.nuon (skill and command names
                            from the last turn), sweep.log
```

## Limitations

- **Print mode cannot ask.** A skill that needs a tool outside
  `AGENT_ALLOWED_TOOLS` is denied and the footer names the tool. Some
  plugin commands do nothing in print mode (`agmem:doctor` returns empty);
  `(no output)` is printed then.
- **`ask` is read-only by instruction, not enforcement.** The `nu` MCP
  `evaluate` tool can run anything; the model is told to run only read-only
  pipelines. `exec` gets a tool list without `evaluate` for that reason.
- **Latency is the model's.** Spawning `claude` costs 9 to 60 ms; a turn
  takes 2 to 6 s on sonnet at low effort, more on the default model. Nothing
  streams back until the first token.
- **No output context.** `$ans` carries the previous command, exit code and
  duration but not its output (`max_last_result_size` is 0 by default).
- **Checkpoints need a next shell.** A session is checkpointed by the next
  interactive start on this machine, not at exit. Windows keeps the sweep
  in-shell, so a short-lived shell there loses it.
- **Nushell syntax drift.** Proposals are grounded by the `nushell` skill
  and `command_help`, but a minor Nushell version can still invalidate a
  flag; the insert key exists for exactly that.
- **One session per shell, not per directory.** Change directories freely,
  each turn re-states the cwd; use `agent reset` if the thread gets confused.
- **A checkpoint job started by `nu-config startup-time`** (which opens
  interactive shells) is legitimate but is killed with them; the claim file
  is taken back after 15 minutes.

## Future ideas

- **Explain the last failure**: `agent why`, sending `$ans` plus the captured
  output once `max_last_result_size` is on, answering "what went wrong and
  what to run instead".
- **Natural language at the prompt**: a `command_not_found` hook that routes
  a line ending in `?` to `agent ask`, or a leading `?` prefix like
  butterfish, without giving up explicit verbs.
- **Output as context**: a bounded ring buffer of recent command outputs via
  the `display_output` hook, truncated per block the way butterfish does.
- **Resident process for token streaming**: a `claude -p --input-format
  stream-json` child owned by a `job spawn` (verified pattern: `to text` on
  its stdin), or a Rust plugin over ACP once Claude Code speaks it natively.
  Saves the 3 s stdin wait and the per-turn init, not the model time.
- **Fork for what-ifs**: `agent ask --fork` on `--fork-session` so a
  throwaway question does not enter the shell's thread.
- **Structured answers**: `agent ask --json <schema>` returning a Nushell
  value instead of prose, so answers compose in pipelines.
- **Per-project sessions**: key the session by git root instead of shell,
  so two tabs on the same repo share context.
- **Learning loop**: when `i` is followed by an edit before Enter, feed the
  diff back as a "revise" so the session learns your corrections.
- **`nu-config doctor` section**: surface `agent status` in the doctor
  report.
