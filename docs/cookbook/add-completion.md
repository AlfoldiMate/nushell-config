# Add Tab completion for a tool

Two ways: let the agent build it, or write the spec by hand. Both end in a
`completions/<tool>.nu` in **your** directory and one `use` line in your
`settings.nu`; both are checked the same way at the end.

## With the agent

```nu
agent completion gh                          # cobra: __complete for the tree, flag enums, dynamic positionals
agent completion uv "packages in the venv"   # a hint about what a positional is
```

This runs the `completion` skill on a Claude session of its own: it finds
where the tool's command surface lives (its own `__complete` hook, a shipped
fish file, help text, carapace, nu_scripts), maps every positional to the
cheapest local data, writes the module in the shape of `brew.nu` and
`git.nu`, wires it and verifies it headless. A build is 20-60 turns on the
default model. The deterministic parts are scripts you can run yourself:

```nu
nu .claude/skills/completion/scripts/discover.nu gh --online   # which sources exist, in order (≈1 s)
nu .claude/skills/completion/scripts/cobra-tree.nu gh --at pr  # a cobra tool's tree via `gh __complete`
nu .claude/skills/completion/scripts/fish-spec.nu uv           # a fish completion file → draft spec (uv: 3902 lines in 3 s)
nu .claude/skills/completion/scripts/help-tree.nu cargo        # recursive --help → draft spec (clap, cobra, argparse, git layouts)
nu .claude/skills/completion/scripts/verify.nu git --oracle carapace   # every slot through `commandline complete`, timed, diffed against carapace
```

(Paths are relative to the checkout: `nu-config distro-root`.)

## By hand

The worked example is `starship`: thirteen subcommands from `--help`, and
`starship preset <Tab>` should offer the preset names, which `starship
preset --list` prints in 4 ms.

**1. Find where the tool already keeps what you need.** In order of
preference: a file it maintains (Homebrew's API cache, git's refs), a shell
completion it ships (`/opt/homebrew/completions/zsh/_brew` gave every
subcommand, flag and positional kind), one cheap subcommand (`git help -a`,
`starship preset --list`), and only then `--help` scraping or carapace.
Measure it with `timeit` before you accept it.

**2. Write `completions/starship.nu` in your config directory** (`nu-config
user-root`):

```nu
# starship — subcommands from `starship --help` (5 ms, cached for the session),
# preset names from `starship preset --list` (4 ms). Everything else: carapace.

use nu-complete *

# ── Sources ───────────────────────────────────────────────────────────────────

def --wrapped starship-out [...args: string]: nothing -> list<string> {
  let r = (^starship ...$args | complete)
  if $r.exit_code != 0 { [] } else { $r.stdout | lines }
}

# The `Commands:` block of --help: "  name  description" until the blank line.
def subcommands []: nothing -> record {
  nu-complete cache "starship:subcommands" 1hr {
    starship-out --help
    | skip until {|l| $l starts-with "Commands:" } | skip 1
    | take while {|l| $l | str trim | is-not-empty }
    | parse -r '^\s+(?<name>\S+)\s+(?<description>.+)$'
    | reduce -f {} {|it, acc| $acc | insert $it.name { description: $it.description } }
  }
}

def presets []: nothing -> list<string> {
  nu-complete cache "starship:presets" 1hr { starship-out preset --list }
}

# ── The spec ──────────────────────────────────────────────────────────────────

export def "nu-complete starship spec" []: nothing -> record {
  {
    description: "The minimal, blazing-fast, and infinitely customizable prompt"
    fallback: "external"
    sources: { presets: {|ctx| presets } }
    subcommands: (subcommands | merge {
      preset: {
        description: "Prints a preset config"
        positionals: [ "presets" ]
        flags: [
          { name: "--output", short: "-o", description: "Output the preset to a file", arg: "files" }
          { name: "--force", short: "-f", description: "Overwrite the output file" }
          { name: "--list", short: "-l", description: "List out all preset names" }
        ]
      }
    })
  }
}

def complete-starship [token, place?, buffer?] {
  try { nu-complete run (nu-complete starship spec) (nu-complete spans $token (try { $place }) (try { $buffer })) } catch { null }
}

@complete "complete-starship"
export extern main [...args]
```

Three parts, always in this order: private sources, one exported `spec`
command, the completer and the extern. The last four lines are the same in
every module and the parameter names and the inner `try`s are load-bearing —
[Completion specs](../reference/completion-spec.md) says why, and has the
whole spec format. `main`, because a module cannot export an extern of its
own name.

Cache anything slower than a few milliseconds: `nu-complete cache "key" 5sec
{ … }` for small results; a SQLite file under `nu-complete cache-dir` for big
lists, built in a `job spawn`, as `brew.nu` does.

**3. Wire it.** In your `settings.nu`:

```nu
use starship.nu *   # subcommands, preset names
```

Your `completions/` is first on `NU_LIB_DIRS`, so the bare name resolves
there. A module shipped by the distro is wired in `conf/completions.nu`
instead, and lives in the distro's `completions/`.

**4. Check it — headless, in a shell that loads the config.** A completer
that errors is *silent*: Nushell shows files. So none of this is optional.

```nu
nu -l -c '"starship " | commandline complete --detailed | select value description | first 4'
nu -l -c '"starship preset " | commandline complete --detailed | get value'
nu -l -c '"starship preset --" | commandline complete --detailed | get value'
nu -l -c '"starship preset gru" | commandline complete --detailed | get value'      # gruvbox-rainbow
nu -l -c 'nu-complete run (nu-complete starship spec) [starship preset ""]'         # the error the `try` hides, if any
nu -l -c 'timeit { "starship preset " | commandline complete --detailed }'          # 1.6 ms
nu -l -c 'nu-complete smart "starship preset " 16 | get value'                      # the Tab menu path
nu -l -c 'nu-config startup-time'                                                    # within noise of before
```

Run on 2026-09-19: the four subcommand rows with their descriptions, the
twelve presets, `--output --force --list`, `gruvbox-rainbow`, 1.6 ms for the
preset slot, 1.4 ms for the subcommand slot, startup 57-66 ms over five runs.

`nu --ide-complete` does **not** run `@complete` completers, so it proves
nothing; and `nu -l -c` does not load the vendor autoload directory, where
carapace is wired, so a slot left to the fallback looks empty headless even
when it works in the REPL ([Debug Tab](debug-tab.md)).

A module that gets its whole tree from a big literal belongs in
`completions/data/<tool>.json` and parses in a budget of 3 ms per module
([Completion specs](../reference/completion-spec.md#what-it-costs-to-parse)).
