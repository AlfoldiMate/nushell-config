# autoload/ — machine-local drop-ins

Every `*.nu` file in this directory is loaded by Nushell at the end of
startup, in alphabetical order, after `config.nu` and after the generated
tool files. Nothing here is committed (see `.gitignore`), so this is the place
for anything private or specific to one machine:

```nu
# autoload/local.nu
$env.GITHUB_TOKEN = "..."
path add "/opt/some-work-tool/bin"
$env.config.show_banner = "short"
```

Because these files run last, they override everything in `conf/`.

Two limits, both inherent to autoload directories: files here are not loaded
by `nu -c`, `nu script.nu` or `nu -l -c`, and `config.nu` cannot depend on
them. Anything the tracked config needs belongs in `conf/`, not here.
