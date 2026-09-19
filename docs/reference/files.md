# Files and formats

Every file the distro reads or writes, where it lives, and why it is in the
format it is in. [Layout](../concepts/layout.md) is the picture; this is the
inventory.

## Your directory

`$nu.default-config-dir` — `~/Library/Application Support/nushell` on macOS,
`~/.config/nushell` on Linux, `%APPDATA%\nushell` on Windows. `nu-config
user-root` prints it.

| | written by | what |
|---|---|---|
| `config.nu` | `install.nu`, once | three lines: `const DISTRO = …; source ($DISTRO \| path join distro.nu)` |
| `config.nu.backup-<stamp>` | `install.nu` | the previous `config.nu`, when there was one |
| `README.md` | `nu-config user init`, when missing | what every file and directory here is, and whose |
| `settings.nu` | `nu-config user init`, when missing; then you | every knob in `defaults.nu` and every module's `meta.nuon`, commented out at its shipped value — generated, not copied; uncomment to override. Sourced right after `defaults.nu` |
| `settings.nu.backup-<stamp>` | `nu-config user init --force settings.nu` | the one replaced |
| `autoload/*.nu` | you | drop-ins Nushell loads last. `README.md` and `example.nu.off` are the scaffold's |
| `completions/` | you, or `nu-config fetch completion <tool>` | completion modules; first on `NU_LIB_DIRS`. `README.md` and `hello.nu.off` are the scaffold's |
| `modules/` | you | modules of your own, `use`d from `settings.nu`. `README.md` is the scaffold's |
| `themes/` | you | a copy of any template in the distro's `themes/`, or `palettes/<slug>.nuon` of your own. `README.md` and `palettes/example.nuon.off` are the scaffold's |
| `plugins/` | you | plugin binaries; first on `NU_PLUGIN_DIRS`. `README.md` is the scaffold's |
| `history.sqlite3` | Nushell | history (`history.file_format = "sqlite"`) |
| `plugin.msgpackz` | `plugin add`, `nu-config plugins add` | the plugin registry, protocol-versioned against `nu` |
| `vendor/autoload/*.nu` | `nu-config tools setup` | generated init files: `zoxide.nu`, `atuin.nu`, `carapace.nu`, … one per installed tool |
| `.state/` | the modules | below |

On macOS `$nu.data-dir` is the config directory, so `vendor/` and `.state/`
sit next to `config.nu`; on Linux they are under `~/.local/share/nushell`.
`nu-config doctor` prints every one of these paths.

The scaffold — the READMEs, the three `.off` examples and `settings.nu` — is
`templates/user/` in the checkout, mirrored file for file, rendered by
`nu-config user init`: `@DISTRO@` becomes the checkout, and every relative
path in a template, written for the template's place in the checkout, is
rewritten for the file's place in your directory, so a link into `docs/`
works on GitHub and in your editor alike. `settings.nu`'s body is generated
from `defaults.nu` and the module `meta.nuon`s rather than copied. Init
writes only what is missing; `user status` tells `present` from `edited` by
comparing with what init would write today, never by mtime
([nu-config](modules/nu-config.md#your-directory)).

## State: `$nu.data-dir/.state/`

| | written by | read by |
|---|---|---|
| `theme/theme.nuon` | `theme use`, `theme sync` | `conf/theme.nu` at startup, 0.36 ms |
| `theme/starship.toml` | same | starship, through `STARSHIP_CONFIG` (`conf/prompt.nu`) |
| `theme/ls_colors` | same, via vivid | `conf/theme.nu` → `LS_COLORS`, 0.09 ms |
| `theme/vivid.yml` | same | vivid, when rendering |
| `theme/ghostty/<slug>` | `theme use` of a palette with a `terminal` block | Ghostty, through `theme =` in the distro's included file |
| `theme/icons/<slug>.png` | `theme use` (macOS) | Ghostty, through `macos-custom-icon` |
| `nu-config/upgrade.nuon` | the background `git fetch` (`conf/update.nu`) | every interactive start, 0.3 ms |
| `odata/services.nuon` | `odata service add` | the service registry, merged under `$env.ODATA_SERVICES` |
| `agent/sessions/<id>.nuon` | every `agent` turn | the startup sweep, which checkpoints closed sessions |
| `agent/commands.nuon` | the first `agent` turn | Tab on `agent skill` / `agent command` |
| `agent/sweep.log` | `agent sweep` | you |

## Caches: `$nu.cache-dir/`

`~/Library/Caches/nushell` on macOS, `~/.cache/nushell` on Linux. Everything
here is rebuilt when missing.

| | what | rebuilt |
|---|---|---|
| `nu-complete/brew-spec.json` | Homebrew's subcommand tree, parsed from its zsh completion | when the zsh file is newer |
| `nu-complete/brew-packages.db` | every formula and cask with its description, SQLite | when Homebrew's API cache is newer, in a background job |
| `odata/<service>.json` | the parsed `$metadata` | after `ODATA_METADATA_TTL` (7 days) or `odata refresh` |

Session-scoped memos (`stor`) hold what the Tab menu asked for in the last
seconds: `nu-complete status` and `odata status` list them. They die with the
shell.

## Ghostty

`ghostty set` writes `<ghostty config dir>/nushell-distro.ghostty` and appends
one line — `config-file = ?nushell-distro.ghostty` — to Ghostty's own config,
after copying it to `config.backup-<stamp>`. `ghostty status` shows both;
`ghostty reset` removes ours and the line ([Theming](../concepts/theming.md#one-included-file-never-their-config)).

## Formats

Two formats, and a reason for each:

| | |
|---|---|
| `.nu` | anything the **parser** must see: `defaults.nu`, `settings.nu`, the enabled modules, themes |
| NUON | anything tooling reads at **runtime**: module `meta.nuon`, state, registries, caches |

`.nu` is not a style choice. `open` and `from nuon` are not const-evaluable in
0.115 (`scope commands | where is_const` lists `path exists`, `if`, `path join`
and the `str` commands — not `open`), so a value the parser has to know cannot
come from a data file. Everything else is NUON: it is Nushell's own literal
syntax, so a state file reads like the record it is and `open` needs no `--raw`
and no converter.

No JSON — with two measured exceptions, both machine-written caches that sit on
the Tab path:

| | |
|---|---|
| `$nu.cache-dir/nu-complete/brew-spec.json` | 195 kB: 1.2 ms as JSON, 7.8 ms as NUON |
| `$nu.cache-dir/odata/<service>.json` | 25 kB: 0.47 ms as JSON, 3.0 ms as NUON |

NUON's parser costs about **6x per byte** at every size tried, which is nothing
for a 160 B registry (81 µs against 51 µs) and is most of a keystroke's budget
for a 195 kB spec. Both files carry a comment saying so. The rule those two bend
is worth keeping anyway: the files a *person* opens — `.state/odata/services.nuon`,
`.state/agent/sessions/*.nuon` — are NUON, and none of them is large.

Files rendered for another tool are in that tool's format, and are read only by
it: `.state/theme/starship.toml`, `ls_colors`, `ghostty/<slug>` and `icons/*.png` (`theme use`),
`vendor/autoload/*.nu` (`nu-config tools setup`).

Written NUON is `to nuon --indent 2`: one key per line, so a diff shows the line
that changed rather than the whole file, and empty or null fields are dropped
before saving rather than stored as `{}`.

