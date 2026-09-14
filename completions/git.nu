# git — native positional completion for git
#
# Carapace knows git well but takes 50-60 ms per Tab (measured 2026-09-10);
# git itself answers in 10-20 ms and knows this repository. So:
#
#   subcommands           `git help -a` (13 ms, cached for the session) + your aliases
#   refs                  `git for-each-ref`, branches by recency, then remotes, tags
#   files                 `git status --porcelain` for add/restore/diff/checkout --
#   remotes, stashes      `git remote`, `git stash list`
#   flags                 `git <cmd> -h`, parsed and cached for the session
#
# Anything the spec has no opinion on (config keys, rev ranges, ...) is
# handed to carapace via `fallback: external`.

use nu-complete *

def --wrapped git-out [...args: string]: nothing -> list<string> {
  let r = (^git ...$args | complete)
  if $r.exit_code != 0 { [] } else { $r.stdout | lines }
}

def in-repo []: nothing -> bool {
  nu-complete cache $"git:in-repo:($env.PWD)" 10sec { (^git rev-parse --is-inside-work-tree | complete).exit_code == 0 }
}

# Branches (most recently committed first), then remote branches and tags.
def refs [kinds: list<string>]: nothing -> list<record> {
  if not (in-repo) { return [] }
  let all = (nu-complete cache $"git:refs:($env.PWD)" 5sec {
    git-out for-each-ref --sort=-committerdate "--format=%(refname)%09%(refname:short)%09%(subject)" refs/heads refs/remotes refs/tags
    | parse "{ref}\t{value}\t{subject}"
    | each {|r|
        let kind = (if ($r.ref | str starts-with "refs/heads/") { "branch" } else if ($r.ref | str starts-with "refs/tags/") { "tag" } else { "remote" })
        { value: $r.value, kind: $kind, description: ($r.subject | str substring 0..60) }
      }
    | where value !~ '/HEAD$'
  })
  let order = { branch: 0, remote: 1, tag: 2 }
  $all | where kind in $kinds | sort-by {|r| $order | get $r.kind } | each {|r| { value: $r.value, description: $"($r.kind) · ($r.description)" } }
}

def remotes []: nothing -> list<record> {
  if not (in-repo) { return [] }
  nu-complete cache $"git:remotes:($env.PWD)" 30sec {
    git-out remote -v | parse --regex '^(?<value>\S+)\s+(?<url>\S+) \(fetch\)' | each {|r| { value: $r.value, description: $r.url } }
  }
}

# Paths from `git status`, filtered by status letters (XY of --porcelain).
def status-files [which: string]: nothing -> list<record> {
  if not (in-repo) { return [] }
  let rows = (nu-complete cache $"git:status:($env.PWD)" 5sec {
    git-out status --porcelain=v1 -uall | parse --regex '^(?<x>.)(?<y>.) (?<path>.+)$'
    | each {|r| { path: ($r.path | str replace --regex '^.* -> ' ""), x: $r.x, y: $r.y } }
  })
  let picked = (match $which {
    "unstaged" => ($rows | where y != " " or x == "?")
    "staged" => ($rows | where x not-in [" " "?"])
    _ => $rows
  })
  # Paths are relative to the repo root; make them relative to here.
  let root = (nu-complete cache $"git:root:($env.PWD)" 30sec { git-out rev-parse --show-toplevel | get -o 0 | default $env.PWD })
  $picked | each {|r|
    let full = ($root | path join $r.path)
    let rel = (try { $full | path relative-to $env.PWD } catch { $full })
    let what = (match [$r.x $r.y] {
      ["?" "?"] => "untracked"
      [_ "M"] => "modified"
      ["M" " "] => "staged"
      ["A" _] => "added"
      [_ "D"] | ["D" _] => "deleted"
      ["R" _] => "renamed"
      _ => $"($r.x)($r.y)"
    })
    { value: $rel, description: $what }
  }
}

def stashes []: nothing -> list<record> {
  if not (in-repo) { return [] }
  git-out stash list "--format=%gd%x09%s" | parse "{value}\t{description}"
}

def tracked-files []: nothing -> list<record> {
  if not (in-repo) { return [] }
  nu-complete cache $"git:tracked:($env.PWD)" 10sec { git-out ls-files | each {|f| { value: $f } } }
}

# Every subcommand with its one-line description, plus aliases.
def subcommands []: nothing -> record {
  nu-complete cache "git:subcommands" 1hr {
    let cmds = (git-out help -a | parse --regex '^\s{3}(?<name>[\w-]+)\s{2,}(?<desc>.+)$')
    let aliases = (git-out config --get-regexp '^alias\.' | parse --regex '^alias\.(?<name>\S+) (?<desc>.+)$' | each {|a| $a | update desc $"alias → ($a.desc)" })
    $cmds ++ $aliases | reduce -f {} {|c, acc| $acc | upsert $c.name { description: $c.desc } }
  }
}

# Flags from `git <cmd> -h`; git prints the short usage to stderr for
# builtins and to stdout for a few scripts.
def flags-of [cmd: string]: nothing -> list<record> {
  nu-complete cache $"git:flags:($cmd)" 1hr {
    let r = (^git $cmd -h | complete)
    ($r.stdout + (char nl) + $r.stderr) | lines
    | parse --regex '^\s+(?:(?<short>-\w),\s+)?--(?<no>\[no-\])?(?<name>[\w-]+)(?:[ =]<?[^ ]*>?)?\s{2,}(?<desc>.+)$'
    | uniq-by name
    | each {|f|
        let flag = ({ name: $"--($f.name)", description: $f.desc } | merge (if ($f.short | is-empty) { {} } else { { short: $f.short } }))
        # `--[no-]quiet` is two flags.
        if ($f.no | is-empty) { [$flag] } else { [$flag { name: $"--no-($f.name)", description: $"negate: ($f.desc)" }] }
      }
    | flatten
  }
}

# What each subcommand's positionals want. Everything not listed here still
# gets its flags from `git <cmd> -h` and its positionals from carapace.
def positional-plan []: nothing -> record {
  let all_refs = {|ctx| refs [branch remote tag] }
  let branches = {|ctx| refs [branch remote] }
  let files_after_dashdash = {|ctx| if "--" in $ctx.args { status-files all } else { (refs [branch remote tag]) ++ (status-files unstaged) } }
  {
    checkout: { rest: $files_after_dashdash }
    switch: { rest: $branches }
    merge: { rest: $all_refs }
    rebase: { rest: $all_refs }
    reset: { rest: {|ctx| (refs [branch remote tag]) ++ (status-files staged) } }
    revert: { rest: $all_refs }
    "cherry-pick": { rest: $all_refs }
    log: { rest: $all_refs }
    show: { rest: $all_refs }
    diff: { rest: {|ctx| (status-files all) ++ (refs [branch remote tag]) } }
    branch: { rest: {|ctx| refs [branch] } }
    tag: { rest: {|ctx| refs [tag] } }
    add: { rest: {|ctx| status-files unstaged } }
    restore: { rest: {|ctx| status-files all } }
    rm: { rest: {|ctx| tracked-files } }
    mv: { positionals: [ {|ctx| tracked-files } ], rest: "files" }
    push: { positionals: [ {|ctx| remotes } {|ctx| refs [branch] } ] }
    pull: { positionals: [ {|ctx| remotes } {|ctx| refs [branch remote] } ] }
    fetch: { positionals: [ {|ctx| remotes } ] }
    remote: {
      subcommands: {
        add: { description: "Add a remote", positionals: [ [] "files" ] }
        remove: { description: "Remove a remote", positionals: [ {|ctx| remotes } ] }
        rename: { description: "Rename a remote", positionals: [ {|ctx| remotes } ] }
        show: { description: "Show a remote", positionals: [ {|ctx| remotes } ] }
        prune: { description: "Delete stale remote-tracking branches", positionals: [ {|ctx| remotes } ] }
        "get-url": { description: "Print the remote's URL", positionals: [ {|ctx| remotes } ] }
        "set-url": { description: "Change the remote's URL", positionals: [ {|ctx| remotes } ] }
      }
    }
    stash: {
      subcommands: {
        push: { description: "Save your local modifications to a new stash", rest: {|ctx| status-files all } }
        pop: { description: "Remove a stash and apply it", positionals: [ {|ctx| stashes } ] }
        apply: { description: "Apply a stash on top of the working tree", positionals: [ {|ctx| stashes } ] }
        drop: { description: "Remove a stash", positionals: [ {|ctx| stashes } ] }
        show: { description: "Show the changes recorded in a stash", positionals: [ {|ctx| stashes } ] }
        list: { description: "List the stashes" }
        clear: { description: "Remove all stashes" }
      }
    }
    worktree: {
      subcommands: {
        add: { description: "Create a worktree", positionals: [ "files" {|ctx| refs [branch remote tag] } ] }
        list: { description: "List worktrees" }
        remove: { description: "Remove a worktree", positionals: [ "files" ] }
        prune: { description: "Prune worktree information" }
      }
    }
    submodule: {
      subcommands: {
        add: { description: "Add a submodule" }
        init: { description: "Initialise submodules" }
        update: { description: "Update submodules" }
        status: { description: "Show submodule status" }
        foreach: { description: "Run a command in each submodule" }
        sync: { description: "Sync submodule URLs" }
      }
    }
  }
}

export def "nu-complete git spec" []: nothing -> record {
  let plan = (positional-plan)
  let subs = (subcommands | transpose name s | reduce -f {} {|r, acc|
    let node = ($r.s | merge ($plan | get -o $r.name | default {}))
    # A record literal keeps the closure as a value (`insert` would run it).
    let node = if ($node.flags? == null) { $node | merge { flags: {|| flags-of $r.name } } } else { $node }
    $acc | upsert $r.name $node
  })
  {
    description: "the stupid content tracker"
    fallback: "external"
    flags: [
      { name: "--version", description: "Print the git version" }
      { name: "--help", description: "Print help" }
      { name: "-C", description: "Run as if started in this directory", arg: "files" }
      { name: "-c", description: "Pass a configuration parameter" }
      { name: "--no-pager", description: "Do not pipe output into a pager" }
      { name: "--git-dir", description: "Path to the repository" }
      { name: "--work-tree", description: "Path to the working tree" }
      { name: "--bare", description: "Treat the repository as bare" }
    ]
    subcommands: $subs
  }
}

def complete-git [spans: list<string>] { try { nu-complete run (nu-complete git spec) $spans } catch { null } }

# `main` so that `use git.nu *` yields `git`.
@complete "complete-git"
export extern main [...args]
