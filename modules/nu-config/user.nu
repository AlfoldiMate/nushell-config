# user — your configuration directory as a scaffold: generated once, never overwritten
#
#   nu-config user init                      write every scaffold file that is missing;
#                                            append the knobs settings.nu has never heard of, commented
#   nu-config user init --dry-run            the list only, nothing written
#   nu-config user init --force settings.nu  replace one file, keeping <file>.backup-<stamp>
#   nu-config user status                    every scaffold file: present / edited / missing
#   nu-config user render settings.nu        what init would write for one file, to stdout
#   nu-config user set 'const MODULES = [nu-config]'   one assignment into settings.nu, in place
#
# The work is scaffold.nu, next to this file, run as a script in a `nu -n`
# of its own: parsing it costs 4.4 ms (2026-09-19), which a shell that never
# regenerates its directory should not pay at every start, and a `use` is
# parse-time so it cannot be deferred any other way. This file is the face:
# it names the directory — `--dir`, or the one this shell's config came
# from, which a config-less child cannot know — and turns the NUON the
# script prints back into a table. A call costs one nu start, about 20 ms.

const SCRIPT = path self | path dirname | path join scaffold.nu
const TEMPLATES = path self | path dirname | path dirname | path dirname | path join templates user

def user-root []: nothing -> path { $nu.config-path | path dirname | path expand --no-symlink }

# Run one verb of scaffold.nu and read its NUON back. `-n`: no config, so
# nothing the parent's settings.nu or autoload/ does can reach the render.
def scaffold-run [args: list<string>]: nothing -> any {
  let r = (^$nu.current-exe -n $SCRIPT ...$args | complete)
  if $r.exit_code != 0 {
    # The script's own `error make` text, without miette's frame around it.
    let msg = ($r.stderr | lines | where $it =~ '^\s*(x|×)\s' | str join " " | str replace --regex '^\s*[x×]\s+' '')
    error make { msg: (if ($msg | is-empty) { $r.stderr | str trim } else { $msg }) }
  }
  $r.stdout | from nuon
}

# The scaffold files, for Tab on `user render`: templates/user/ mirrored.
# In-process because a completer runs on every keystroke.
def scaffold []: nothing -> list<string> {
  walk $TEMPLATES | each {|f| $f | path relative-to $TEMPLATES } | sort
}

def walk [dir: path]: nothing -> list<string> {
  ls --all $dir | each {|e| if $e.type == "dir" { walk $e.name } else { [$e.name] } } | flatten
}

# What `user init` would write for one scaffold file, rendered for your directory.
export def "user render" [
  file: string@scaffold   # a path relative to your directory: settings.nu, autoload/README.md, …
  --dir: path             # render for another directory
]: nothing -> string {
  scaffold-run ["render" $file "--dir" ($dir | default (user-root))]
}

# Every scaffold file, and whether your directory has it as written, edited, or not at all.
export def "user status" [
  --dir: path   # another directory than yours
]: nothing -> table<file: string, state: string, note: string> {
  scaffold-run ["status" "--dir" ($dir | default (user-root))]
}

# Write every scaffold file that is missing, and nothing that exists — except
# that settings.nu gets the knobs it has never mentioned appended, commented,
# under a dated mark. Safe to run at any time: after an upgrade, after
# deleting a README to see whether it comes back, on a directory made by hand.
export def "user init" [
  --dir: path        # the directory to scaffold; install.nu passes the one it is creating
  --dry-run          # report what would be done, write nothing
  --force: string    # one scaffold file to replace even though it exists; the old one is kept as <file>.backup-<stamp>
  --fresh            # treat the directory as empty (install.nu's dry run over a layout it is about to replace)
]: nothing -> table<file: string, action: string, note: string> {
  scaffold-run (
    ["init" "--dir" ($dir | default (user-root))]
    ++ (if $dry_run { ["--dry-run"] } else { [] })
    ++ (if $fresh { ["--fresh"] } else { [] })
    ++ (if $force == null { [] } else { ["--force" $force] })
  )
}

# Write one assignment into settings.nu — `const MODULES = [a b]` or
# `$env.config.table.mode = "rounded"` — replacing the knob's line whether it
# is live or commented out, so the value lands in its section, and appending
# under a dated mark when the file never mentioned it.
export def "user set" [
  line: string   # the assignment, as it would be written in settings.nu
  --dir: path    # another directory than yours
]: nothing -> nothing {
  let r = (scaffold-run ["set" $line "--dir" ($dir | default (user-root))])
  print $"  ($r.file): ($r.line)"
}
