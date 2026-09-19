# meta.nuon

Every module carries a `meta.nuon`, read at runtime by `nu-config` (`module
list | info | check | lint`, `knobs`, `doctor`, the installer) and never at
startup. [Modules](../concepts/modules.md) is the contract it belongs to; this
is every field.

```nu
{
  description: "OData V2/V4 services (SAP Gateway included) as tables"
  docs: "docs/reference/modules/odata.md"
  cost: 97ms
  lazy: true
  requires: [
    { bin: "claude", hard: true, why: "every verb runs one `claude -p` turn"
      paths: ["/Applications/Ghostty.app/Contents/MacOS/ghostty"]
      install: { macos: "brew install --cask claude-code", linux: "…", windows: "…" } }
  ]
  knobs: {
    ODATA_PUSHDOWN: { default: true, about: "translate where/select/first into $filter/$select/$top" }
  }
}
```

| field | required | meaning |
|---|---|---|
| `description` | yes | one line; `module list`, the installer's checkbox and `help` show it |
| `docs` | yes | the module's page. A path from the distro root (`docs/reference/modules/<name>.md`) for a shipped module; for one of yours, a path relative to the module directory (`README.md`) works too — `module info` tries the module directory first, then the root the module came from. `module lint` fails when the file is missing |
| `cost` | yes, non-zero | a duration: the median of 25 cold `nu -l` starts with the module loaded against the same 25 with it lazy or absent, from the shipped default set. `nu-config startup-time` is the same measurement on your machine. Paid at startup when eager, on first mention when lazy |
| `lazy` | no (`false`) | `true`: not parsed at startup; a `pre_execution` hook sources `load.nu` on the first line that mentions the module's name or one of its `MODULES_TRIGGERS`. Interactive-only, by nature — `nu -c` and scripts never fire the hook |
| `requires` | no (`[]`) | declared, never installed. Each entry: `bin` (what `which` looks for), `hard` (`true`: the module does not work without it; `false`: works, worse), `why`, `install` (a line per platform, `macos` / `linux` / `windows` — `lint` wants all three), and optional `paths` checked when PATH misses, for an application installed off PATH (Ghostty on macOS) |
| `knobs` | no (`{}`) | the module's own settings, each `{ default, about }`. `default` is shown, not applied: the module applies it in `activate` with `default`, never assignment, so your `settings.nu` wins. `nu-config knobs` lists them with `owner` set to the module |

What `lint` checks, in order: `meta.nuon` exists and parses, has a
`description` and a non-zero `cost`; `mod.nu` and `load.nu` exist; the `docs`
page exists; `load.nu` parses (`nu-check`, the only check that reaches a lazy
module before someone types its name); every `requires` entry has a `bin`, a
`why` and an install line for each platform.
