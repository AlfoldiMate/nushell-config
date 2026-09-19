# Tests

`tests/` is the suite; `nu tests/run.nu` runs it. It is written in Nushell
on `std assert`, needs no terminal, and touches nothing of yours: every shell
a test starts has a config directory of its own under the run's scratch
directory, deleted at the end.

```nu
nu tests/run.nu                 # everything
nu tests/run.nu completion      # only files or tests whose name contains it
nu tests/run.nu --timing        # ... and the ten slowest at the end
nu tests/run.nu -v              # every file's output, not only a failing one's
nu tests/run.nu --serial        # one file at a time, in order
```

One line per test, a summary, exit 1 when anything failed:

```
  ✓ harness · a user directory keeps the shell state to itself  67.7 ms
  - terminal · the icon is rendered  skipped: no rasterizer off macOS
  ✗ harness · the runner reports each verdict and exits 1
      Error: nu::shell::error
        x These are not equal.
        ...

6 passed, 1 failed, 1 skipped  ·  332.3 ms
```

## Layout

```
tests/
  run.nu              the runner
  lib.nu              what a test needs: scratch, user-dir, nu-l, skip-test
  harness.test.nu     the harness tested with itself
  completion/         engine, smart, specs, cost — the engine behind Tab
  terminal/           ghostty, theme, font — against a fake ghostty
  config/             layering, modules, upgrade, install, tools — the distro's own mechanics
  pty/                harness.py and menu.test.nu — Tab in a real terminal
  <concern>.test.nu   one file per module or concern
  fixtures/           brew/ (a trimmed zsh completion, name lists, a Cellar),
                      ghostty/ (the fake, three theme files); the runner's own
                      sample files — never searched for tests
```

## A test file

A test file is `tests/**/*.test.nu`; a test is a `def "test <name>"` in it.
The runner lists them with `scope commands` after sourcing the file, so a
test is whatever parses as one, and runs them in order of name.

```nu
use lib.nu *
use std/assert

def "test a knob in settings.nu wins" [] {
  let dir = user-dir --settings 'const SMART_TAB = false'
  let ran = nu-l $dir 'print $env.NU_SMART_TAB'
  assert equal $ran.exit_code 0 $ran.stderr
  assert equal ($ran.stdout | str trim) "false"
}

def "test the icon is rendered" [] {
  if $nu.os-info.name != macos { skip-test "no rasterizer off macOS" }
  ...
}
```

A name holds letters, digits, spaces and `._+/=:,-` only. The runner splices
each name into a script as a command call — a command cannot be called by a
name held in a variable — and a quote in one would open a string there and
pair with the next, silently swallowing the tests in between; a name outside
the set fails the file with the reason.

Each **file** runs in a fresh `nu -n` with `NU_LIB_DIRS` set to `modules/`,
`completions/`, `themes/` and then `tests/` of the checkout (last, so that
`tests/terminal/` does not shadow the module), so `use lib.nu *`,
`use nu-complete` and `use git.nu *` resolve the way they do in a shell, and
nothing the user's config sets is present: the file's shells get
`XDG_CONFIG_HOME`, `XDG_DATA_HOME` and `XDG_CACHE_HOME` under a sandbox of
the file's own in the run's scratch directory, so `$nu.cache-dir` (where
`completions/brew.nu` writes its spec) and `$nu.data-dir` (the theme's
state) are that file's alone, and so is `HOME` off Windows (where
`$nu.home-dir` does not follow it), so `~/Library/Fonts` and
`~/Library/Application Support` are scratch too; rustup's
`CARGO_HOME`/`RUSTUP_HOME` are passed through so the real cargo still runs.
Files run **concurrently** (`par-each`), which the sandboxes make safe, and
a file's lines are printed together once it is done; `--serial` runs them
one at a time in order. Tests within a file share a process and a sandbox,
so a test must not assume a file it did not write is absent. Tests within a file share that process; state a test wants alone
goes in a `scratch` directory.

**Never name a helper after a built-in.** A file's `def`s are declared before
its `use` lines are parsed, and a module parsed in that scope resolves names
against it: a `def complete` in a test file broke `lib.nu`'s `| complete`,
and `lib.nu`'s own skip helper was `skip` until the engine's `skip $n` ran
it — hence `skip-test`. `commandline complete` lists files from the
process's working directory, which a `cd` in a test does not move; the
externals a completer runs, and the pipeline probe, do follow `$env.PWD`.

Inside the file each test runs in a `try`: an `assert` that fails is the
failure (its diagnostic, with `left` and `right`, is what the runner prints),
`skip-test` is a skip, reaching the end is the pass. `print` from a test goes to
the file's output, shown after a failing file or with `-v`.

## Tab in a real terminal

Some completion bugs exist only in reedline: the sourced-menu partial
completion corruption (`bits r` Tab Tab Enter → `bits ror o` on nushell
main) is invisible to `commandline complete`. `tests/pty/harness.py` forks
a pseudo-terminal, runs `nu -l -i` in it against a `user-dir`, types each
case's line, sends its keys one at a time, and reports what reedline
recorded in history (exact, where reading the screen back through
starship's prompt is not) and the screen each case produced.
`tests/pty/menu.test.nu` holds the cases as data — `{line, keys, want}`,
with `corrupt` for what the bug makes of a line and `screen` for a case
that only looks — and runs them once under the shipped defaults and once
with `completions.partial = true`, where the corruption is asserted per
version: 0.115.1 clean, the 0.115.2 main build corrupted, a later release
expected clean, so the test documents the upstream bug rather than hiding
it. Python because every runner has it and nu has no pty; skipped on
Windows, which has none either.

What the harness taught, kept as its rules: reedline asks the terminal
where the cursor is (`ESC[6n`) before every prompt and waits for the
answer, so the harness answers or every prompt costs the timeout; keys go
one at a time with a settle-based wait — until the output has been quiet
for 0.2 s, after at least one byte — because Tabs sent in a burst land
while the menu source is still computing and get folded into one, and a
fixed sleep was flaky against the smart menu's first-Tab cost. One session
runs every case (8.5 s for eight cases; two sessions, 17.6 s for the file,
which is the suite's long pole under `par-each`).

## `lib.nu`

| | |
|---|---|
| `ROOT` | the checkout under test (a `const`) |
| `scratch` | a fresh directory under the run's scratch root, named after the test; deleted with the run |
| `user-dir [--settings <body>]` | a user directory: `config.nu` sourcing this checkout's `distro.nu`, a `settings.nu` if given, and an `XDG_CONFIG_HOME` / `XDG_DATA_HOME` of its own. Returns `{root, config, data, env}` |
| `nu-l <dir> <code>` | `nu -l -c <code>` under that directory's environment; returns `complete`'s `{stdout, stderr, exit_code}` |
| `fake-ghostty` | a `ghostty` that answers from files, first on PATH, with a Ghostty config directory of its own; returns `{root, bin, log, config, themes}`. Skips the test on Windows. `ghostty-calls <fake>` lists what it was asked |
| `skip-test <reason>` | stop the test, counted apart from the failures. Not `skip`: a module `use`d after `lib.nu` resolves names against the scope it is parsed in, and the engine's `skip $n` became the test helper |

`user-dir` sets the XDG variables rather than passing `--config`: Nushell
derives `$nu.data-dir`, the history, the plugin registry and the autoload
directories from its config *directory*, so under `--config` those stay the
user's real ones ([Test a change](../cookbook/test-a-change.md)). Under the
two variables every one of them is inside the scratch directory — the
harness test checks each — and `nu -l` loads the scratch `config.nu` without
being told, the way it loads yours.

## Cost

A file costs two `nu -n` starts (one lists the tests, one runs them) and a
test that starts a shell against a user directory costs one `nu -l`: about
60 ms with the distro loaded, 105 ms on the 0.115.1 release build
(2026-09-19, M-series Mac). The harness file alone, six tests, four of them
starting a shell: 332 ms. The whole suite, 137 tests in fourteen files:
18 s concurrent (the pty file is the long pole), 38 s `--serial`, the same
on 0.115.1 (0.55 s for
the harness alone on the Linux runner, 1.4 s on the macOS one). The slow
tests are the ones that clone this repository three times (`config/upgrade`,
0.5-0.8 s each), run the installer (`config/install`, 0.5-1 s) decode the
icon's PNG in Python (1.3 s) or drive a terminal (`pty/menu`, 8.5 s a
session). The whole suite is budgeted under 30 s so it
is run before every commit; `--timing` names what to look at when it is
not.

## CI

`nu tests/run.nu` runs on macOS, Linux and Windows after `doctor`. A test
that only makes sense on one platform or with a tool installed says so with
`skip-test` rather than passing vacuously; the summary counts them apart.
