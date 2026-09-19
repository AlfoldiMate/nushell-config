# tools.nu — hooks and keybindings for tools that ship no Nushell init file
#
# Tools that DO emit a .nu init file (zoxide, atuin, carapace) are handled by
# `nu-config tools setup`, which writes them into the vendor autoload dir where
# Nushell loads them after this config. See modules/nu-config/tools.nu for the
# registry. vivid and starship are the theme's: `theme use` renders both.
#
# Everything here is guarded with `which`, so a missing binary is a no-op.

# ── Homebrew: suggest a formula for an unknown command ────────────────────────
if (which brew | is-not-empty) {
  $env.config.hooks.command_not_found = {|cmd|
    let found = (do -i { ^brew which-formula $cmd | complete })
    if ($found | is-not-empty) and $found.exit_code == 0 and ($found.stdout | str trim | is-not-empty) {
      $"(ansi cyan)($cmd)(ansi reset) is available via Homebrew: (ansi green)brew install ($found.stdout | str trim)(ansi reset)"
    } else {
      null
    }
  }
}

# ── direnv: load .envrc on directory change ───────────────────────────────────
# From the Nushell cookbook. direnv hands PATH back as a string; the std
# conversion turns it into the list Nushell expects.
if (which direnv | is-not-empty) {
  use std/config env-conversions
  $env.config.hooks.env_change.PWD = ($env.config.hooks.env_change.PWD? | default [])
  $env.config.hooks.env_change.PWD ++= [{||
    direnv export json
    | from json
    | default {}
    | update cells --columns [PATH] { do (env-conversions).path.from_string $in }
    | load-env
  }]
}
