# nu-complete — the completion engine behind Tab
#
#   nu-complete run <spec> <spans>     positional completion for an extern, from a spec (engine.nu)
#   nu-complete spans <token> <place> <buffer>   a completer's input as a span list, on either release (engine.nu)
#   nu-complete smart <buffer> <pos>   the Tab menu source: pipeline-aware, filtered, deduplicated (smart.nu)
#   nu-complete cache <key> <ttl> {}   memoise a slow source for the session (cache.nu)
#   nu-complete status                 what is cached, and where
#
# Tool specs live in completions/ (brew.nu, git.nu) and are imported from
# conf/completions.nu. docs/concepts/completion.md explains the design and how to add
# a tool.

export use engine.nu *
export use cache.nu *
export use smart.nu *

# Run once the engine is in scope. The Tab menu itself is wired in
# conf/completions.nu, because its look and its keybinding are configuration.
export def --env "nu-complete activate" []: nothing -> nothing {
  $env.NU_COMPLETE_EVAL = ($env.NU_COMPLETE_EVAL? | default "safe")
  # The engine keeps every command's signature in stor; building that table
  # costs ~115 ms, so a background job does it while you type the first line.
  if $nu.is-interactive { job spawn { nu-complete warm } | ignore }
}
