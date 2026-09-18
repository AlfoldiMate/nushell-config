# stub.nu — the part of `agent` that every shell needs, loaded or not.
#
# Sourced unconditionally by conf/modules.nu, before any decision about
# laziness. It must stay free of `use agent`: the whole point is that the
# 18 ms module body is not parsed in a shell that never mentions it.

# One Claude Code session per shell. Minted here so every verb, and a
# `nu -l -c 'use agent; agent ask ...'`, has a session to attach to; the
# session itself is created on the first turn.
$env.AGENT_SESSION_ID = (random uuid)

if $nu.is-interactive and (which claude | is-not-empty) {
  # Nushell has no exit hook and background jobs die with the shell, so the
  # session a closed shell left behind is checkpointed by the next shell that
  # starts. The filtering used to happen in-process, which meant parsing the
  # module in every shell; now the job only checks whether there is anything
  # at all to look at and hands the work to a detached child that loads the
  # module itself.
  job spawn {
    let d = ($nu.data-dir | path join .state agent sessions)
    if ($d | path exists) and ((glob ($d | path join '*.nuon')) | is-not-empty) and $nu.os-info.name != "windows" {
      let log = ($nu.data-dir | path join .state agent sweep-detach.log)
      ^sh -c $"nohup '($nu.current-exe)' -l -c 'use agent; agent sweep --detach' >'($log)' 2>&1 &"
    }
  } | ignore

  # Alt+E: the line you are typing is the task, Claude's proposal replaces it
  # (the aichat pattern). Nothing runs until you press Enter. Terminal.app
  # needs "Use Option as Meta key" for Alt to reach the shell.
  # `executehostcommand` runs the command as if typed, so it goes through the
  # pre_execution hook and loads the module on the way.
  $env.config.keybindings ++= [{
    name: agent_line
    modifier: alt
    keycode: char_e
    mode: [emacs vi_normal vi_insert]
    event: { send: executehostcommand, cmd: "agent line" }
  }]
}
