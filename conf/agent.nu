# agent.nu — Claude Code inside the shell: `agent ask | exec | skill | command`
#
# The commands live in modules/agent; the knobs (models, effort, confirm
# patterns, tool allowlist, checkpointing) in settings.nu; design, measured
# costs and the reasoning in docs/agent.md. Nothing here runs claude at
# startup: the module is parsed, a UUID is minted, and a background job
# checks for sessions left behind by closed shells.
use agent

# One Claude Code session per shell. Minted here so every verb, and a
# `nu -l -c 'agent ask ...'`, has a session to attach to; the session itself
# is created on the first turn.
$env.AGENT_SESSION_ID = (random uuid)

# Nushell has no exit hook and background jobs die with the shell, so the
# session a closed shell left behind is checkpointed by the next shell that
# starts. The job (66 µs to spawn) only lists one directory; when it finds
# a session worth checkpointing it hands off to a detached `nu -l -c 'agent
# sweep'` that outlives this shell.
if $nu.is-interactive and (which claude | is-not-empty) {
  job spawn { agent sweep --detach } | ignore
}

# Alt+E: the line you are typing is the task, Claude's proposal replaces it
# (the aichat pattern). Nothing runs until you press Enter. Terminal.app
# needs "Use Option as Meta key" for Alt to reach the shell.
$env.config.keybindings ++= [{
  name: agent_line
  modifier: alt
  keycode: char_e
  mode: [emacs vi_normal vi_insert]
  event: { send: executehostcommand, cmd: "agent line" }
}]
