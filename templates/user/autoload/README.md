# autoload/ — your drop-ins, loaded last

Every `*.nu` file in this directory is loaded by Nushell at the end of startup,
in alphabetical order: after the distro, and after the generated tool init
files. Because they run last, they override everything.

Nothing here belongs to the distro and nothing here is ever committed by it, so
this is the place for anything private or specific to one machine:

```nu
# autoload/local.nu
$env.GITHUB_TOKEN = "..."
path add "/opt/some-work-tool/bin"
$env.config.show_banner = "short"
```

`example.nu.off` is a complete drop-in — an alias, a `path add`, a keybinding,
one `$env.config` leaf — with a comment per line saying why each is here and
not in `settings.nu`. Rename it `example.nu` and the next shell loads it; as
`.off` it is inert. [Write an autoload drop-in](../../../docs/cookbook/autoload.md)
is the page, with the keybinding and hook forms and how to check one.

## autoload/ or settings.nu?

- **A value** the distro ships a default for → [`../settings.nu`](../settings.nu).
  It is sourced early, so the rest of the config reads your value.
  `nu-config knobs` lists them.
- **Behaviour** — a hook, a keybinding, an alias, a `def`, an environment
  variable the distro knows nothing about → here.

## Two limits, both inherent to autoload directories

Files here are not loaded by `nu -c`, `nu script.nu` or even `nu -l -c`, and
the distro cannot depend on them. Anything a script needs must be reachable
through an explicit `use`.
