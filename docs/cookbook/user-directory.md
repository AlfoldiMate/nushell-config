# Your directory

Your config directory is generated with a structure that explains itself: a
`README.md` at the top saying what every file and directory is and whose, one
in each of `autoload/`, `completions/`, `themes/`, `modules/` and `plugins/`,
an example per kind that does nothing until renamed, and a `settings.nu`
that is every knob commented out. The installer writes it once;
`nu-config user init` writes it again, for whatever is missing.

```nu
nu-config user-root          # where it is
nu-config edit user          # open it whole in $EDITOR; the READMEs are there when it opens
nu-config user status        # every scaffold file: present (as written), edited, missing
```

## Get a README back

Delete one — or move to a machine where the directory was made by hand —
and:

```nu
nu-config user init --dry-run    # what would be written
nu-config user init              # write it; everything you have is left alone
```

Run on 2026-09-19 in a scratch directory with `README.md` and
`plugins/README.md` deleted: `status` listed both as `missing`, `init`
reported `written` for the two and `kept` for the other eight, `doctor`'s
`scaffold` line went from `2 files missing` to `complete`.

## Switch an example on

Each `*.off` file is complete and inert only because of its name — Nushell
loads `*.nu` from `autoload/`, the palette reader opens `*.nuon`:

```nu
cd (nu-config user-root)
cp autoload/example.nu.off autoload/example.nu                        # an alias, a path add, a keybinding, one $env.config leaf
cp completions/hello.nu.off completions/hello.nu                      # Tab for a fictional `hello`; uncomment `use hello.nu *` in settings.nu
cp themes/palettes/example.nuon.off themes/palettes/example.nuon      # a palette of its own; `theme use Example`
```

Then check each the way its kind is checked, in a new shell — a drop-in is
loaded by the REPL, so it has to be a real one:

```nu
which gs | get 0.type                                     # alias
$env.config.keybindings | where name == clear_screen_example | length   # 1
"hello " | commandline complete                           # [greet, wave]
"hello greet --lang " | commandline complete              # [en, fr, de]
theme list | where theme == Example | get 0.kind          # yours
theme resolve Example | select name by tier               # by palette, tier palette
```

Run on 2026-09-19 with `XDG_CONFIG_HOME` pointed at a scratch directory, in
a pty: all six as shown, `"hello greet " | commandline complete` listing the
home directories on the machine in 2.5 ms — with one thing worth knowing.
The drop-in sets `completions.algorithm = "fuzzy"`, and with it on Nushell's
own command matching adds `nu-complete hello spec` to the `hello ` list, the
module's exported spec command; prefix matching, the default, does not.
`cp`, not `mv`, so that `user status` still reads the `.off` file as `present`;
`settings.nu` reads `edited` from here on, which it is.

## After an upgrade: the knobs that are new

`settings.nu` is the knob list; a knob a `nu-config upgrade` brought in is
missing from it. `init` appends what the file never mentions, commented,
under a dated mark, and touches nothing else:

```nu
nu-config user status | where file == settings.nu   # note: "3 knobs not mentioned"
nu-config user init                                 # appended  3 new knobs, commented: …
```

Run on 2026-09-19 with three knob lines cut out of a fresh `settings.nu`:
`status` said `3 knobs not mentioned`, `init --dry-run` said `would append`,
`init` appended `config.footer_mode`, `SMART_TAB` and `ODATA_DEBUG` with their
comments under `# ── Added by nu-config user init on 2026-09-19 ──`, and
`knobs --overridden` stayed empty.

## Start settings.nu over

```nu
nu-config user init --force settings.nu    # the old one is settings.nu.backup-<stamp>
nu-config user render settings.nu          # or just look at what it would write
```

Run on 2026-09-19: `replaced`, with the backup named in the `note` column.

## What edited means

`user status` compares a file with what `init` would write today — the
template with the checkout's path and the links to its docs filled in,
`settings.nu` regenerated from `defaults.nu` — never with an mtime. So a
`cp` or a sync does not turn `present` into `edited`, and a `settings.nu`
with one line uncommented does.
