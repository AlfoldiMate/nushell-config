# Debug Tab

A completer that errors is **silent**: Nushell falls back to files, and the
menu looks like a completer that was never there. So the first move is
always to ask headless, in a shell that loads the config, and look at the
rows.

## Ask what a slot offers

```nu
nu -l -c '"brew install rip" | commandline complete --detailed'        # the rows Tab would get, with span, kind, type
nu -l -c '"git checkout " | commandline complete --detailed | first 5'
nu -l -c '"git switch ma" | commandline complete --input'              # the three inputs a completer is handed, no completer run
```

`commandline complete --detailed` runs every layer Nushell owns: built-ins,
flags, files, and the `@complete` completers behind `completions/*.nu`. It
does **not** run the Tab menu's own rewrite (columns after `where`, no files
after `ps`), which is layer three — for that:

```nu
nu -l -c 'nu-complete smart "ls | where " 11'                          # the buffer, and the cursor position
nu -l -c 'nu-complete smart "ls | where " 11 | select value description'
```

Run on 2026-09-19: `name string · CLAUDE.md`, `type string · file`, `size
filesize · 3.4 kB`, `modified datetime · …` — the columns with a sample from
a real run of `ls`.

Two commands that look right and prove nothing:

- **`nu --ide-complete`** does not run `@complete` completers; it returns
  files for every spec slot.
- **`nu -c '…'`** loads no config at all. It has to be `nu -l -c`.

## The fallback looks empty headless

`nu -l -c` does not load `vendor/autoload/`, which is where carapace is
wired, so any slot a spec leaves to `fallback: "external"` shows files (or
`ERR`) headless and carapace's answer in the REPL. To test the fallback,
source the generated file first:

```nu
nu -l -c 'source ($nu.data-dir | path join vendor autoload carapace.nu); "zoxide " | commandline complete --detailed | first 3'
```

Run on 2026-09-19: `add`, `edit`, `import` with carapace's descriptions;
without the `source`, the directory listing.

## Get the error the `try` hides

Every completer body is `try { … } catch { null }` on purpose. Call the
inside directly:

```nu
nu -l -c 'nu-complete run (nu-complete git spec) [git checkout ""]'    # the spec walk for one slot, errors and all
nu -l -c 'nu-complete git spec | get subcommands.checkout'             # what the spec says about that slot
nu -l -c 'nu-complete brew spec-data | get subcommands.install'
nu -l -c 'nu-complete cargo spec build | get subcommands.build.flags | do $in'
```

Every shipped module exports its spec as `nu-complete <tool> spec`, which is
what makes this a session instead of a guess. An unknown `sources` name
silently yields `[]`, so a slot that offers nothing is often a typo there.

## Is it slow

```nu
nu -l -c 'timeit { "brew install rip" | commandline complete --detailed }'   # 3-5 ms after the cache is built
nu -l -c 'nu-complete status'                                                # what is cached, where, how old
nu -l -c 'nu-complete cache clear'
nu-config doctor                                                             # the Completion section: knobs and cache ages
```

The menu source runs again on every keystroke while the menu is open, so a
source has to answer in single-digit milliseconds from memo or disk. A slot
that is slow the first time and fast after is the memo working; a slot that
is slow every time is a source that runs an external, and belongs in
`nu-complete cache` ([Completion specs](../reference/completion-spec.md#caching)).

## In the REPL

- **"NO RECORDS FOUND"** under the prompt is Reedline's message for an empty
  menu, not an error.
- The first Tab in a session pays the signature table (115 ms) unless the
  background job has finished; the first `ps | …` pays `ps` (150 ms).
- `SMART_TAB = false` in `settings.nu` returns to Nushell's stock menu, which
  is the quickest way to tell whether a problem is the engine's or Nushell's.
- On a Nushell built from main, `bits r` Tab Tab landing as `bits ror o` is
  the partial-completion bug, not a completer
  ([Completion](../concepts/completion.md#known-limits)).

For the real thing — what the menu showed, keystroke by keystroke — drive an
interactive `nu` in a pty: answer Reedline's cursor query (`ESC[6n`) with
`ESC[1;1R`, set the window size, type whole lines, strip the escapes. The
`completion` skill's `verify.nu` runs every slot of a spec through
`commandline complete` in one login shell and diffs against carapace, which
finds forgotten slots faster than any of this:

```nu
nu .claude/skills/completion/scripts/verify.nu git --oracle carapace
```
