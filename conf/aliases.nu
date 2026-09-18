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
# AND you call it. Same for `rgt` below and ripgrep: the cost of a missing tool
# is a clear "command not found" at the moment you use it, never a broken shell.
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
#
# Two implementations because there is no portable one: `lsof` is the Unix
# answer and does not exist on Windows, `netstat -ano` is the Windows answer and
# prints a different shape. Both are normalised to one table, so a script that
# uses `port` does not have to know which ran.
def port [n: int]: nothing -> table<pid: int, name: string, address: string> {
  if $nu.os-info.name == "windows" {
    # -a all connections, -n numeric, -o owning PID. LISTENING is the state
    # word; the address column carries the port after the last colon.
    ^netstat -ano
    | lines
    | where {|l| ($l =~ '\bLISTENING\b') and ($l =~ $'[:.]($n)\s') }
    | parse -r '\s*(?<proto>\S+)\s+(?<address>\S+)\s+\S+\s+LISTENING\s+(?<pid>\d+)'
    | each {|r| { pid: ($r.pid | into int), name: (ps | where pid == ($r.pid | into int) | get -o 0.name | default "?"), address: $r.address } }
  } else if (which lsof | is-not-empty) {
    # -F is lsof's machine-readable output: one field per line, tagged by its
    # first character, p/c before the n lines they belong to. Its columnar
    # output cannot be parsed — `from ssv` mis-splits it, because USER and the
    # FD column ("5u") run together at some widths.
    let out = (^lsof -nP $"-iTCP:($n)" -sTCP:LISTEN -Fpcn | complete)
    if ($out.stdout | str trim | is-empty) { return [] }
    $out.stdout
    | lines
    | reduce -f { pid: 0, name: "", rows: [] } {|l, acc|
        match ($l | str substring 0..0) {
          "p" => ($acc | update pid ($l | str substring 1.. | into int))
          "c" => ($acc | update name ($l | str substring 1..))
          "n" => ($acc | update rows ($acc.rows | append { pid: $acc.pid, name: $acc.name, address: ($l | str substring 1..) }))
          _ => $acc
        }
      }
    | get rows
  } else {
    error make { msg: "`port` needs lsof on this platform; install it, or use `ss -ltnp`" }
  }
}
