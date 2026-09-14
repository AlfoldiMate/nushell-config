# prompt.nu — prompt
#
# Starship owns the prompt when it is installed (config: ~/.config/starship.toml).
# Without it, Nushell's built-in prompt stays: path on the left, time on the right.
#
# This is written by hand instead of generated with `starship init nu` on
# purpose. The generated file would land in the vendor autoload dir, which
# loads AFTER this config and would overwrite the indicators below.

# What Nushell reports before any command has run.
const NO_DURATION = "0823"

def starship-prompt [--right]: nothing -> string {
  let ms = ($env.CMD_DURATION_MS? | default $NO_DURATION)
  let duration = if $ms == $NO_DURATION { 0 } else { $ms }
  let side = if $right { ["--right"] } else { [] }
  ^starship prompt ...$side --cmd-duration $duration $"--status=($env.LAST_EXIT_CODE? | default 0)" --terminal-width (term size).columns --jobs (job list | length)
}

if (which starship | is-not-empty) {
  $env.STARSHIP_SHELL = "nu"
  $env.STARSHIP_SESSION_KEY = (random chars --length 16)
  $env.PROMPT_COMMAND = {|| starship-prompt }
  $env.PROMPT_COMMAND_RIGHT = {|| starship-prompt --right }
  # A closure, so starship is only asked for the continuation prompt when a
  # multi-line command is actually being typed (a call at startup costs ~9 ms).
  $env.PROMPT_MULTILINE_INDICATOR = {|| ^starship prompt --continuation }
  $env.config.render_right_prompt_on_last_line = true
} else {
  $env.PROMPT_MULTILINE_INDICATOR = "::: "
}

# ── Indicators ────────────────────────────────────────────────────────────────
# Drawn after the prompt; they are how you see which vi mode you are in.
$env.PROMPT_INDICATOR = ""
$env.PROMPT_INDICATOR_VI_INSERT = ": "
$env.PROMPT_INDICATOR_VI_NORMAL = "〉"

# ── Transient prompt ──────────────────────────────────────────────────────────
# Redraws past prompts more simply once a command has run, keeping scrollback
# compact. Nushell already blanks the right side and the multiline indicator.
# $env.TRANSIENT_PROMPT_COMMAND = {|| $"(ansi green)❯(ansi reset) " }
