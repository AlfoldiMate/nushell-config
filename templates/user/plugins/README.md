# plugins/ — plugin binaries you built or downloaded

Nushell has no plugin manager: `plugin add`, `list`, `rm`, `use` and `stop`
all edit one registry file (`plugin.msgpackz`, next to `config.nu`) and none
of them fetches, builds or versions anything. A plugin's life is: something
puts a binary on disk, and you register it.

This directory is first on `NU_PLUGIN_DIRS`, so a bare name resolves here
before the directory `nu` itself lives in:

```nu
cp nu_plugin_foo <this directory>/   # `cargo install nu_plugin_foo` or a release binary
plugin add nu_plugin_foo             # resolves through NU_PLUGIN_DIRS, writes the registry
plugin use foo                       # now, or just restart the shell
```

`nu-config plugins add` is the same mechanism run over whatever your package
manager installed beside `nu` — Homebrew ships `formats`, `gstat`, `inc`,
`polars` and `query` — and `nu-config plugins list` says which are
registered. Run it again after every Nushell upgrade: the registry stores
signatures against the protocol version of the `nu` that wrote them.

[Plugins](../../../docs/concepts/plugins.md) is the page.
