# Positional kinds → the cheapest local source

Costs measured on this Mac on 2026-09-11 unless marked D (documented) or U
(unverified). Prefer a file the tool maintains, then one cheap command,
then the tool's own completion engine, then the network. Memoise with
`nu-complete cache "<key>" <ttl> { … }` (session, `stor`); build big lists
into SQLite under `nu-complete cache-dir` in a `job spawn` (brew.nu).

| Kind | Source | Output | Cost | TTL |
|---|---|---|---|---|
| git refs (branches, remotes, tags) | `git for-each-ref --sort=-committerdate --format='%(refname)%09%(refname:short)%09%(subject)' refs/heads refs/remotes refs/tags` | tab lines | 10-18 ms | 5 s per dir (git.nu) |
| git changed files | `git status --porcelain=v1 -uall` | XY path | 15-200 ms (repo size) | 5 s per dir |
| git stashes | `git stash list --format='%gd%x09%s'` | tab lines | 10 ms | none |
| git remotes | `git remote -v` | | 10 ms | 30 s |
| git subcommands + aliases | `git help -a`, `git config --get-regexp '^alias\.'` | | 13 ms | 1 h |
| git flags of a subcommand | `git <cmd> -h` (stderr) or `git <cmd> --git-completion-helper-all` | | 10 ms | 1 h |
| brew formulae / casks | `~/Library/Caches/Homebrew/api/{formula_names,cask_names}.txt` (8.6k / 7.7k); descriptions from `api/internal/packages.*.jws.json.payload` + `.index` (byte offsets) → SQLite | lines / JSON | 4 ms names; 0.7 s one-off build | mtime of the payload |
| brew installed | `ls $HOMEBREW_PREFIX/Cellar`, `Caskroom` (dir names, versions inside) | | 1 ms | none |
| brew taps | `$HOMEBREW_PREFIX/Library/Taps/*/*` | | 1 ms | none |
| brew commands | `$HOMEBREW_PREFIX/completions/internal_commands_list.txt`; `brew commands --quiet --include-aliases` | lines | 1 ms / 100 ms | per brew version |
| cargo subcommands | `cargo --list` (`b   alias: build`) | | ~20 ms | per toolchain |
| cargo packages, targets (bin/example/test/bench), features | `cargo metadata --no-deps --format-version 1 \| from json \| get packages` | JSON | 44 ms | Cargo.toml mtime / 10 s per dir |
| crate names (registry) | `ls ~/.cargo/registry/cache/*/` → strip `-<ver>.crate` (2135 here) | files | ms | daily |
| cargo toolchains | `rustup toolchain list` | lines | 10 ms | 1 h |
| npm scripts | `open package.json \| get scripts \| columns` | | <1 ms | mtime |
| npm installed | `ls node_modules` (+ `@scope/*`) | dirs | ms | 10 s |
| npm commands | `COMP_CWORD=1 COMP_LINE="npm x" COMP_POINT=5 npm completion -- npm x` | lines | ~150 ms | 1 h |
| uv / pip packages | `uv pip list --format json` | `[{name, version}]` | 29 ms | venv mtime / 30 s |
| uv python versions | `uv python list --output-format json` (D) | JSON | U | 1 h |
| gh repos / PRs / issues | `gh repo list --json name --limit 30`, `gh pr list --json number,title,headRefName` | JSON | 0.7 s (network) | 5-15 min per repo |
| gh anything | `gh __complete <sub> ""` | `v\tdesc` + `:N` | 50 ms + network | |
| gh flag enums | help `{open\|closed\|merged\|all}` or `gh __complete pr list --state ""` | | 50 ms | static |
| ssh hosts | `open ~/.ssh/config \| lines \| parse -r '^Host (?<h>.+)'` (+ Include), `~/.ssh/known_hosts` col 1 (hashed here) | | ms | mtime |
| kube contexts / namespaces | `~/.kube/config` YAML `contexts[].name` (`open \| from yaml`); `kubectl config get-contexts -o name` (D) | | ms / network | mtime / 30 s |
| kube resources | `kubectl get <kind> -o name` (D) | lines | network | 30 s |
| docker containers / images | `docker ps --format json`, `docker images --format json` (D) | NDJSON | ~100 ms | 10 s |
| launchd services | `launchctl list` (544 rows here, col 3 label) | table | 8 ms | 60 s |
| processes | `^ps -Ao pid=,comm=` (25 ms) rather than nu `ps` (115 ms, samples CPU) | | 25 ms | 2 s |
| make targets | `open Makefile \| lines \| parse -r '^(?<t>[A-Za-z0-9_.-]+):([^=]\|$)'` | | ms | mtime |
| just recipes | `just --summary` (D), `just --dump --dump-format json` (U) | words / JSON | U | justfile mtime |
| mise tools | `mise ls --json` (D) | JSON | U | 60 s |
| tmux sessions | `tmux list-sessions -F '#S'` (U) | lines | ms | 5 s |
| zoxide dirs | `zoxide query -l` | lines | 12 ms | 30 s per dir (smart.nu) |
| man pages | `man -k .` / `apropos` | | slow | daily |
| files / dirs | `"files"` in the spec (Nushell's own) | | | |

## Patterns

**One cheap command, memoised** (git.nu):

```nu
def refs []: nothing -> list<record> {
  nu-complete cache $"git:refs:($env.PWD)" 5sec {
    git-out for-each-ref … | parse "{ref}\t{value}\t{subject}" | each {|r| { value: $r.value, description: $r.subject } }
  }
}
```

**Read the tool's cache, build SQLite in the background** (brew.nu):

```nu
def ensure-db []: nothing -> bool {
  if not (nu-complete stale (db-file) (payload-file)) { return true }
  if not busy { touch $lock; job spawn { try { build-db }; rm -f $lock } | ignore }
  false                                   # caller serves the plain name list meanwhile
}
%open (db-file) | query db "select name as value, desc as description from packages where name like :p limit 2000" -p { p: $"($partial)%" }
```

**A flag narrows a positional**: read `$ctx.args` (`--cask` in args →
casks only).

**Enum from help**: `arg: [auto always never]` literally in the flag record.

**Descriptions are worth a second command**: `git for-each-ref` with
`%(subject)`, `cargo metadata` with `description`, `docker ps` with image
and status. The menu shows them in a column.

**TTL guidance**: seconds for anything the user changes by hand (refs,
status), minutes for network, hours for the tool's own command list, mtime
comparisons (`nu-complete stale`) for files.
