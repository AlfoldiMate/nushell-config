# Plugins: there is no plugin manager

The question this page answers: *why does this distro have its own
`nu-config plugins add`, instead of using Nushell's plugin manager?*

Because Nushell does not have one.

## What the built-ins actually do

Nushell ships five plugin commands, and all five edit one file — the **plugin
registry**, `$nu.plugin-path`, a `plugin.msgpackz` in your config directory:

| | |
|---|---|
| `plugin add <path>` | runs the binary to read its command signatures, writes them into the registry |
| `plugin list` | what the registry holds, with each plugin's version and commands |
| `plugin rm <name>` | drops an entry |
| `plugin use <name>` | loads a registered plugin into the current scope |
| `plugin stop <name>` | stops a running plugin process |

None of them fetches, builds, downloads or versions anything, and `plugin add`
takes a path to an executable that must already exist. There is no index, no
resolver and no lockfile. Nushell's own words for `plugin add`: *"it runs the
plugin to get its command signatures, and then edits the plugin registry
file"*.

So a plugin's life cycle is: **something else puts a binary on disk, and you
register it.** That is the whole model, and the "something else" is your
package manager.

One trap in `plugin list`: by default it reports what the **engine** loaded, not
what the file holds. `plugin list --registry --plugin-config $nu.plugin-path`
reports the file, and is what `nu-config plugins list` asks for — under `nu -n`
nothing is loaded, so the plain form comes back empty and every plugin looks
unregistered. A config-less `nu` also refuses to default that flag to
`$nu.plugin-path`, although it will happily print the path.

## What `nu-config plugins add` is

The same mechanism, run over whatever was installed next to `nu`:

```nu
nu-config plugins list     # nu_plugin_* beside the nu binary, and whether each is registered
nu-config plugins add      # plugin add, for each one that is not a developer example
```

Homebrew ships eight `nu_plugin_*` binaries alongside `nu`. Three of them —
`example`, `custom_values`, `stress_internals` — exist to test Nushell itself
and would only add noise to your shell, so they are skipped by name. The other
five are registered, which on this machine is:

```
formats  gstat  inc  polars  query        all 0.115.1, polars alone adding 187 commands
```

`nu-config doctor` lists them with `ok` when registered and `--` when not, and
tells you to run `nu-config plugins add` when something is missing. The
installer runs it once at the end, which is the only reason it is not a manual
step on a fresh machine.

## Re-run it after every Nushell upgrade

This is the one thing worth remembering. The registry stores each plugin's
signatures **against the protocol version of the `nu` that wrote them**, so
after `brew upgrade nushell` the entries describe a protocol the new binary no
longer speaks:

```nu
nu-config plugins add      # after every `brew upgrade nushell`
```

The binaries are upgraded by Homebrew at the same time as `nu`; it is only the
registry that goes stale. `plugin list` showing an old version, or a plugin
command failing after an upgrade, is this and nothing else.

## Plugins you build or download yourself

`distro.nu` sets the search path `plugin add <name>` resolves a bare name
through:

```nu
const NU_PLUGIN_DIRS = [
  ($USER_ROOT | path join plugins)     # yours
  ($nu.current-exe | path dirname)     # shipped next to `nu`
]
```

Your own directory comes first. The installer creates it, and it is the only
path for a plugin nothing else installs — one you wrote, `cargo install
nu_plugin_<name>`, or a release binary:

```nu
cp nu_plugin_foo ~/Library/Application\ Support/nushell/plugins/   # or wherever `nu-config doctor` says
plugin add nu_plugin_foo      # resolves through NU_PLUGIN_DIRS
plugin use foo                # now, or just restart the shell
```

The distro checkout has no `plugins/` directory. It used to, back when the
checkout *was* the config directory; after the split it was not on
`NU_PLUGIN_DIRS` at all, and a plugin binary is the least portable thing in a
configuration — per platform, per architecture, per protocol version. It
belongs in your directory with the rest of your machine's state
([Layout](layout.md)), not in a git repository.

## And nupm?

[nupm](https://github.com/nushell/nupm) is Nushell's experimental package
manager: it installs modules and scripts from git repositories, described by a
`nupm.nuon`. Its README still opens with

> This project is in an experimentation stage and not intended for serious use!

(checked 2026-09-19). It also does not solve the problem above — it installs
Nushell source packages, not plugin binaries. So this distro vendors what it
needs: modules live in `modules/`, completions in `completions/`, both as plain
files a `git pull` updates, and nothing is fetched at runtime.
