# aliases.nu — aliases and small commands
#
# `alias` is a parse-time substitution: no pipelines, no arguments, position
# dependent. `def` is a real command; use it for anything with a pipeline.
# Shadowing a built-in with a `def` of the same name recurses; call the
# original with the `%` sigil (`%ls`) or alias it away first.

# ── Listing ───────────────────────────────────────────────────────────────────
# `ls` stays Nushell's: it returns a table you can `where`, `sort-by`, `get`.
alias ll = ls -l
alias la = ls -a
alias lla = ls -la

# eza for the views nu does not do (tree, icons). An alias is parse-time, so
# it cannot sit inside an `if (which eza ...)`; it only fails if eza is absent
# AND you call it.
alias tree = eza --tree --icons --git-ignore
alias lt = eza --tree --level=2 --icons

# ── Git ───────────────────────────────────────────────────────────────────────
alias g = git
alias gs = git status
alias gd = git diff
alias gl = git log --oneline --graph --decorate -20
alias ga = git add
alias gc = git commit
alias gco = git checkout
alias gp = git push
alias gpl = git pull

# ── This config ───────────────────────────────────────────────────────────────
alias nu-reload = exec nu

# ── Small commands ────────────────────────────────────────────────────────────

# Sizes of the directories under a path, largest first.
def duh [path: path = "."]: nothing -> table {
  ls -a $path
  | where type == dir
  | update size {|r| du --max-depth 0 $r.name | get physical.0 }
  | select name size
  | sort-by size --reverse
}

# ripgrep as a table (file, line, text) instead of text.
def rgt [pattern: string, path: path = "."]: nothing -> table {
  ^rg --line-number --no-heading --with-filename --color never $pattern $path
  | complete
  | get stdout
  | lines
  | parse "{file}:{line}:{text}"
  | update line {|r| $r.line | into int }
}

# What is listening on TCP port N; empty table when nothing is.
def port [n: int]: nothing -> table {
  let out = (^lsof -nP $"-iTCP:($n)" -sTCP:LISTEN | complete)
  if ($out.stdout | str trim | is-empty) { [] } else { $out.stdout | from ssv }
}
