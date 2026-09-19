# nu-config

Maintenance commands for this configuration: what is installed, what is
loaded, what is stale, and what is broken.

```nu
nu-config doctor            # roots, layout, parse, tools, plugins, modules
nu-config knobs             # every knob, and whether you have overridden it
nu-config module list       # what is enabled, lazy, loaded
nu-config user init         # your directory's scaffold: the READMEs, the examples, settings.nu — what is missing
nu-config upgrade            # pull the distro; the shell says when there is something to pull
```

## Commands

| Command | Does |
|---|---|
| `doctor` | health check: both roots, layout state, files, search paths, parse, tools, plugins, completion caches, modules |
| `knobs [--overridden]` | every knob from `defaults.nu` and every module's `meta.nuon`, with whether your `settings.nu` sets it |
| `module list \| info \| check \| enable \| disable \| lint` | the module system — [Modules](../../concepts/modules.md) |
| `tools setup \| status \| remove \| dir` | generated init files for installed third-party tools |
| `upgrade` | `git pull --ff-only` in the checkout, then the commits that came in, then `user init` for any scaffold file the new version ships and your directory lacks (a README, an example — never a file you have) |
| `upgrade check \| status \| notice \| stale <every>` | fetch now; the last result; the startup line; is the result older than `every` — `conf/update.nu` wires the last two |
| `plugins list \| add` | the plugin registry |
| `fetch completion <tool>` | vendor one from nu_scripts **into your directory**, never the distro |
| `startup-time [n]` | time N cold interactive starts |
| `loaded-files` | what was parsed this session — find a slow import |
| `user init [--dry-run] [--force <file>]` | write every scaffold file that is missing; append to `settings.nu` the knobs it never mentions, commented; `--force` replaces one file, keeping `<file>.backup-<stamp>` |
| `user status` | every scaffold file: `present` (as init would write it), `edited`, `missing` |
| `user render <file>` | what init would write for one file, to stdout |
| `user set <line>` | one assignment into `settings.nu`, replacing the knob's line whether live or commented — what `module enable` and the installer use |
| `edit` / `edit user` | open the distro / your config directory, after `user init` |
| `distro-root` / `user-root` / `install-status` | where things are |

## Configuration

None. This module is deliberately knob-free: it is what you use when the
configuration is wrong, so it must not depend on the configuration being right.
`UPDATE_CHECK_EVERY` in `defaults.nu` belongs to `conf/update.nu`, which reads
it and passes it to `upgrade stale`; the module itself never sees the const.

## Dependencies

None.

## Design

Two facts shape this module.

**It is imported by `install.nu`, which runs as a script.** A script loads no
config, so none of the config's parse-time constants exist. Anything this
module reads from the config must come through `$env` — `$env.NU_LIB_DIRS`,
`$env.NU_SMART_TAB`, `$env.NU_MODULES` — never the `const`. Referencing a const
in the module makes it unimportable outside a loaded shell, and the error points
at a line that looks fine.

**`update` is a Nushell built-in.** `nu-config upgrade` is the name a user
expects, but a module that defines `update` shadows the built-in for everything
parsed after it in the same scope — `use nu-complete *` in `mod.nu` failed to
parse when `upstream.nu` was exported above it, because `engine.nu` calls the
built-in. So `export use upstream.nu *` is the last line of `mod.nu`, and the
file is not called `update.nu`, because a module cannot export a command with
its own name.

**The update check never touches the network at startup.** A start reads the
last result from `<your>/.state/nu-config/upgrade.nuon` (0.3 ms, measured with
`timeit`) and prints one line when it says the checkout is behind; when the
result is older than `UPDATE_CHECK_EVERY` it spawns the fetch as a `job`, whose
result the *next* start reports. The record carries the HEAD it was measured
against, read at startup from `.git/HEAD` and its ref file rather than a `git`
fork, so a pull by any means retires the line at once. A job dies with its
shell, so a window closed within a second or two loses that check and the next
one repeats it — the result is still stale.

**`module` is a Nushell keyword.** `module list` is a perfectly good exported
name, but it cannot be *called* from inside `mod.nu` — the parser reads it as
the `module` keyword. Hence the private `mod-list`, `mod-info` and `mod-check`,
which the exported commands delegate to.

## Your directory

`user.nu` renders `templates/user/` into your directory — or rather
`scaffold.nu` does, run as a script in a `nu -n` of its own. The generator is
350 lines and costs **4.4 ms** to parse (2026-09-19, minimum of fifteen
`nu -n -c "use user.nu"` against an empty `nu -n`); a `use` is parse-time and
cannot be deferred, so a shell that never regenerates its directory would pay
that at every start. `user.nu` is the 40-line face, **0.5-0.9 ms**: it names
the directory (`--dir`, or the one this shell's config came from, which a
config-less child cannot know), runs the script, and reads the NUON it prints
back into a table. A call costs one nu start: `user status`, which renders
all ten files, is 71 ms, and `doctor` pays that for its `scaffold` line. The
rules the generator keeps:

- **Write only what is missing.** A file you have is never overwritten;
  `--force <file>` is the one exception and backs the old one up first. The
  installer calls the same command, so the two cannot drift.
- **`settings.nu` is generated, not copied.** Its body is `defaults.nu` with
  every assignment commented out — sections, comments and multi-line values
  kept, the file's own header dropped — followed by one section per module
  with knobs in its `meta.nuon`, and a `Yours` section for `use` lines. The
  parser is thirty lines: a section rule, a comment block, a blank line, or a
  knob whose brackets are followed to their close. `nu-config knobs` reads
  the same two sources, so the file and the command cannot disagree.
- **A new knob is appended, commented, under a dated mark** — the only thing
  init writes into a file you have. It is a knob the file does not mention
  at all, live or commented, so a knob you deleted on purpose comes back
  once and then stays wherever you put it.
- **Links are rewritten per destination.** A relative path in a template is
  written for the template's place in the checkout (`../../docs/…` from
  `templates/user/`) and rewritten for the file's place in your directory,
  in one pass: every path is fenced with a unit separator, the text split on
  it, and the odd segments mapped. Replacing token by token would let a short
  path match inside a longer one already rewritten. A path that resolves to
  nothing in the checkout is left alone — that is what `../settings.nu` and
  `../plugins/nu_plugin_foo` do, and `templates/user/` mirrors your directory
  so they are right as written.
- **Edited is a content comparison.** `user status` renders the template
  and compares, line endings and the trailing newline ignored; mtime is
  what a `cp` or a sync changes.
- **`user set` replaces in place.** The knob's line is found whether live or
  commented, a commented multi-line value (`# const EDITORS = [` … `# ]`) is
  replaced whole, and a knob the file never mentioned is appended under a
  dated mark. So an installed `settings.nu` with two overrides reads as the
  knob list with two lines live in it, not as a template with a tail.

The three `.off` examples are complete and checked in CI: renamed, the
drop-in parses and binds its key, `hello` completes three slots, the palette
resolves at tier three ([Your directory](../../cookbook/user-directory.md)).

## Measured

Eager and never disabled: it is how you diagnose everything else, so it has to
load even when something below it is broken. `module disable nu-config` is
refused for the same reason.

## Files

```
mod.nu       the commands
user.nu      your directory's scaffold: `user init | status | render | set` — the face
scaffold.nu  the generator behind it, a script run in a `nu -n` so that startup never parses it
tools.nu     the third-party tool registry and generator
upstream.nu  `upgrade`: is the checkout behind its remote, and pulling it
load.nu      `use nu-config`
meta.nuon    description
```

## Tests

`nu tests/run.nu config` — 45 tests in `tests/config/` (2026-09-19):
`layering` (a `const` and an `$env.` leaf in `settings.nu` reaching the
`conf/` file that reads them, `knobs` against `defaults.nu` and every
`meta.nuon`, `--overridden` naming exactly the live lines, the rule that no
`conf/` file assigns a knob `defaults.nu` owns, what startup parses and
what it leaves to the lazy hook, the hook's trigger words), `modules`
(`list | info | check | lint | enable | disable` against a user directory
with a module that keeps the contract and one that breaks it every way
`lint` knows), `upgrade` (`check | status | notice | stale | upgrade`
against a bare clone of this repository as the remote, commits pushed from
a third clone, a checkout with commits of its own, no remote, a fetch that
fails), `install` (`--dry-run` writing nothing, `--defaults` writing exactly
the scaffold with no override, a second run, a foreign `config.nu` backed
up, a checkout refused) and `tools` (`setup | status | remove`, the files
parsing, the carapace rewrap). [Tests](../tests.md) is the harness.

## Limits

`doctor`'s parse check runs `nu-check` on `distro.nu`, which follows every
`source` but does not execute anything — a file that parses can still fail at
runtime.
