# Override a shipped completion

Your `completions/` comes before the distro's on `NU_LIB_DIRS`, so a file of
the same name in your directory is the one `use git.nu *` resolves. Copying a
shipped module into your directory and editing it is the entire mechanism —
no fork, no flag, and the shipped copy goes on updating underneath, untouched.

**1. Copy it.**

```nu
cp ((nu-config distro-root) | path join completions git.nu) ((nu-config user-root) | path join completions git.nu)
```

**2. Check that the copy is the one loaded.** In a new shell:

```nu
nu-config loaded-files | where filename =~ "git.nu"
```

One row, and its path is under your directory. `conf/completions.nu` still
says `use git.nu *`; only the resolution changed.

**3. Edit it.** Say `git clean <Tab>` should offer only the untracked files,
instead of every file in the directory. `git.nu` keeps its per-subcommand
positionals in `positional-plan`; add a line there:

```nu
    add: { rest: {|ctx| status-files unstaged } }
    clean: { rest: {|ctx| status-files unstaged | where description == "untracked" } }
```

**4. Check it worked**, headless:

```nu
nu -l -c '"git clean " | commandline complete --detailed | select value description | first 3'
```

Run on 2026-09-19 in a checkout with new files: before the edit the three
rows were `bootstrap/`, `CLAUDE.md`, `completions/` — the directory; after,
`docs/concepts/odata.md · untracked` and two more like it.

## What to know

- **Everything shadows by name**, not only completions: a module in your
  `modules/`, a template or a palette in your `themes/`
  ([Layout](../concepts/layout.md#search-paths)).
- **A `git pull` no longer reaches you.** Your copy is frozen at the day you
  copied it; `git log -- completions/git.nu` in the checkout shows what you
  are missing, and `diff` against the shipped file is how to take it. To go
  back, delete your copy.
- **A completion you fetched** (`nu-config fetch completion docker`) lands in
  the same directory with `-completions` in its name, wired from your
  `settings.nu` rather than shadowing anything.
- **Spec and sources are one file**, so a fix to a source (how branches are
  listed) is the same copy-and-edit. The spec format, and what a module owes
  every slot, is [Completion specs](../reference/completion-spec.md).
