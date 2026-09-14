# How Nushell starts, and where this config plugs in

Verified against Nushell 0.115. The full 29-step table is in the book's
[Configuration](https://www.nushell.sh/book/configuration.html) chapter; this
is the part that matters for organising a config.

| # | What | Here |
|---|---|---|
| 1 | `$NU_LIB_DIRS` / `$NU_PLUGIN_DIRS` get their defaults (`<config>/scripts`, `<data>/completions`, `<config>/plugins`, dir of `nu`) | replaced in `config.nu` |
| 2 | `$env.config` is filled from the internal defaults; `PATH` becomes a list | |
| 3 | std library is loaded (not imported); `$nu` constants are built | |
| 4 | internal `default_env.nu` (the two default prompt closures), then **`env.nu`** | empty |
| 5 | internal `default_config.nu` (`$env.config = {}`), then **`config.nu`** | wires `conf/*.nu` in order, imports `nu-config` |
| 6 | `login.nu`, only for `nu -l` | empty |
| 7 | every `*.nu` in `$nu.vendor-autoload-dirs`, last dir wins | generated tool files: `nu-config tools setup` |
| 8 | every `*.nu` in `$nu.user-autoload-dirs` = `<config>/autoload` | your drop-ins, gitignored |

Three consequences:

- **`nu -c '...'` and `nu script.nu` load none of this** (only std and the
  plugin registry). A script that needs a module must `use` it by path.
  `nu -l -c` loads env.nu, config.nu and login.nu but not the autoload dirs.
- **Autoload files run after `config.nu`**, so `config.nu` cannot depend on
  them, and they override anything in `conf/`.
- **`source` and `use` need parse-time paths.** That is why `config.nu`
  derives everything from `const ROOT = path self | path dirname`, and why
  tool init output is written to a file first instead of being piped in.

## Paths on this platform

```nu
$nu.default-config-dir      # where config.nu lives (the repo, via the link)
$nu.data-dir                # vendor/autoload lives under here
$nu.vendor-autoload-dirs    # all of them, in load order
$nu.user-autoload-dirs      # <config>/autoload
$nu.plugin-path             # plugin.msgpackz, per machine
```

`nu-config doctor` prints them all and checks that they line up.
