# nu-complete — the completion engine behind Tab
#
#   nu-complete run <spec> <spans>     positional completion for an extern, from a spec (engine.nu)
#   nu-complete smart <buffer> <pos>   the Tab menu source: pipeline-aware, filtered, deduplicated (smart.nu)
#   nu-complete cache <key> <ttl> {}   memoise a slow source for the session (cache.nu)
#   nu-complete status                 what is cached, and where
#
# Tool specs live in completions/ (brew.nu, git.nu) and are imported from
# conf/completions.nu. docs/completion.md explains the design and how to add
# a tool.

export use engine.nu *
export use cache.nu *
export use smart.nu *
