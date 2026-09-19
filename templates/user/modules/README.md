# modules/ — modules of your own

A module is a directory here that adds commands to the shell. This directory
is first on `NU_LIB_DIRS`, so `use mymodule` in [`../settings.nu`](../settings.nu)
finds it, and one with the same name as a shipped module shadows it.

## The contract, in five lines

```
modules/<name>/
  mod.nu       the commands, and `<name> activate` — hooks and `$env` defaults go there, with `default`, never `=`
  load.nu      `use <name> *` then `<name> activate`: the ONE place that knows how the module is imported
  meta.nuon    description, docs, measured cost, lazy, requires, knobs — read at runtime, never at startup
  README.md    what it is, every command, configuration, dependencies, costs, limits — named by `docs: README.md` in meta.nuon
```

`nu-config module lint` checks every module here against the shipped ones'
contract, `nu-config module info <name>` shows what its `meta.nuon` says,
and `nu-config module list` whether this shell loaded it. A module of yours
is wired in by a `use` in `settings.nu` — `use` is parse-time, so it cannot
sit in `autoload/` or inside an `if`.

- [Modules](../../../docs/concepts/modules.md) — the contract, `activate`, lazy loading, cost
- [meta.nuon](../../../docs/reference/meta-nuon.md) — every field, and what `lint` checks
- [`../../../templates/module-doc.md`](../../../templates/module-doc.md) — the shape of the README
- the shipped ones to copy from: [`../../../modules/`](../../../modules/) — `agent` and `odata` are lazy, `nu-complete` is eager and knob-light
