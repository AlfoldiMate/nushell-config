# Knobs

Every value the distro ships, and where to change it. `defaults.nu` is the
file: read it, copy a line into your `settings.nu`, change it there. A knob
you never mention keeps its shipped value, including one added by a later
`git pull` ([Layout](../concepts/layout.md#how-the-layering-works)).

```nu
nu-config knobs              # every knob, its kind, its owner, and whether you set it
nu-config knobs --overridden # just yours
nu-config edit user          # your directory; settings.nu is created the first time
config nu --doc | nu-highlight | less -R   # every $env.config key Nushell has, whether the distro mentions it or not
```

A `const` is shadowed by a `const` of the same name in `settings.nu`; an
`$env.` assignment is replaced by one. Both are plain Nushell.

## Editor

| knob | default | meaning |
|---|---|---|
| `const EDITORS` | `[["zed" "--wait"] ["nvim"] ["vim"] ["vi"]]` | candidates in order; the first found on PATH becomes `$env.EDITOR`, `$env.VISUAL` and the Ctrl+O buffer editor. GUI editors need their blocking flag |

## Line editing

| knob | default | meaning |
|---|---|---|
| `$env.config.edit_mode` | `"vi"` | `emacs`, `vi` or `helix` |
| `$env.config.highlight_resolved_externals` | `true` | paint an external differently once it resolves on PATH, so a typo shows before Enter |
| `$env.config.cursor_shape.emacs` | `"line"` | |
| `$env.config.cursor_shape.vi_insert` | `"line"` | the cursor is how you see which vi mode you are in |
| `$env.config.cursor_shape.vi_normal` | `"block"` | |
| `$env.config.abbreviations` | `{}` | Reedline abbreviations, `{ gs: "git status" }`, expanded in place as you type. None shipped: an abbreviation is muscle memory and yours |

## Banner and history

| knob | default | meaning |
|---|---|---|
| `$env.config.show_banner` | `false` | `true`, `"short"` or `false` |
| `$env.config.history.file_format` | `"sqlite"` | keeps timestamps, cwd and exit codes, queryable with `history`; `"plaintext"` is one command per line |
| `$env.config.history.max_size` | `1_000_000` | |
| `$env.config.history.isolation` | `false` | `true`: ↑ shows only this session's history |
| `$env.config.history.sync_on_enter` | `true` | |
| `$env.config.history.ignore_space_prefixed` | `true` | `" secret-cmd"` stays out of history |

## Tables and values

| knob | default | meaning |
|---|---|---|
| `$env.config.table.mode` | `"markdown"` | border style; `table --list` shows every option |
| `$env.config.table.index_mode` | `"always"` | |
| `$env.config.table.header_on_separator` | `false` | |
| `$env.config.table.show_empty` | `true` | |
| `$env.config.footer_mode` | `25` | repeat the header at the bottom past this many rows |
| `$env.config.filesize.unit` | `"metric"` | kB/MB/GB; `"binary"` for KiB/MiB/GiB |
| `$env.config.filesize.precision` | `1` | |
| `$env.config.float_precision` | `2` | |
| `$env.config.datetime_format.table` | `null` | `null` is humanised ("2 hours ago"); or a strftime string |
| `$env.config.datetime_format.normal` | `null` | |

## Errors and the filesystem

| knob | default | meaning |
|---|---|---|
| `$env.config.error_style` | `"fancy"` | `"plain"` for screen readers |
| `$env.config.display_errors.exit_code` | `false` | externals already print their own error |
| `$env.config.display_errors.termination_signal` | `true` | |
| `$env.config.rm.always_trash` | `false` | `true`: `rm` moves to the system trash by default |
| `$env.config.auto_cd_implicit` | `false` | require `./` or an absolute path to auto-cd |

## Terminal integration

| knob | default | meaning |
|---|---|---|
| `$env.config.shell_integration.osc2` | `true` | window and tab title |
| `$env.config.shell_integration.osc7` | `true` | report the cwd, so new tabs inherit it |
| `$env.config.shell_integration.osc8` | `true` | clickable links in `ls` |
| `$env.config.shell_integration.osc133` | `true` | prompt marks: jump between prompts |
| `$env.config.shell_integration.osc633` | `true` | VS Code's extension of osc133 |
| `$env.config.use_ansi_coloring` | `"auto"` | |
| `$env.config.bracketed_paste` | `true` | |
| `$env.config.use_kitty_protocol` | `false` | `true` lets Tab and Ctrl+I be bound separately, which needs a terminal that speaks the Kitty keyboard protocol (Ghostty does). Left off because a shell started somewhere else would lose the keys |
| `$env.PAGER` | `"less"` | |
| `$env.LESS` | `"-RFX"` | keeps colour, quits when it fits on one screen, leaves output visible |

## Completion

| knob | default | meaning |
|---|---|---|
| `const SMART_TAB` | `true` | Tab runs the pipeline-aware engine in `modules/nu-complete`; `false` is Nushell's stock completion menu |
| `$env.NU_COMPLETE_EVAL` | `"safe"` | to offer columns and values the engine runs the pipeline typed so far in a subprocess: `"safe"` only when every command is a read-only built-in, `"all"` your own commands too (~80 ms instead of ~20), `"off"` never — Tab still filters and deduplicates. Declared again by the module's `meta.nuon`, which is why `nu-config knobs` lists it twice |
| `$env.config.completions.partial` | `false` | Tab first inserts what every candidate shares, then opens the menu. Off because Nushell main (0.115.2, reedline c9e7035) corrupts the line after that insert in a sourced menu; 0.115.1 is clean and may turn it back on ([Completion](../concepts/completion.md#known-limits)) |

## Modules

| knob | default | meaning |
|---|---|---|
| `const MODULES` | `[nu-config nu-complete terminal agent odata]` | which modules this shell has; `nu-config module enable\|disable` edits it for you |
| `const MODULES_LAZY` | `[terminal agent odata]` | of those, the ones not parsed at startup — loaded by a `pre_execution` hook on the first line that mentions them (828 ns per Enter to check, against 18 ms for `agent` and 97 ms for `odata` to load). Interactive-only: a script has to `use odata *` itself |
| `const MODULES_TRIGGERS` | `{ odata: [expand], terminal: [theme ghostty font] }` | extra words that load a lazy module, for commands that do not repeat its name |

## Updates

| knob | default | meaning |
|---|---|---|
| `const UPDATE_CHECK_EVERY` | `1day` | how often an interactive shell runs a background `git fetch` in the checkout; the next start prints one line when there is something to pull. `0sec`: never |

## Module knobs

A module's knobs are not in `defaults.nu`: the module declares them in its
`meta.nuon` and applies them in `activate`. Set them in `settings.nu` the same
way; `nu-config knobs | where owner == <module>` lists them.

| module | knobs |
|---|---|
| [agent](modules/agent.md#configuration) | `AGENT_MODEL`, `AGENT_EFFORT`, `AGENT_CONFIRM`, `AGENT_PERMISSION_MODE`, `AGENT_ALLOWED_TOOLS`, `AGENT_COMPLETION_TOOLS`, `AGENT_COMPLETION_MAX_TURNS`, `AGENT_CHECKPOINT`, `AGENT_CHECKPOINT_MIN_TURNS`, `AGENT_DEBUG` |
| [odata](modules/odata.md#configuration) | `ODATA_SERVICES`, `ODATA_SERVICE`, `ODATA_PUSHDOWN`, `ODATA_PUSHDOWN_SEARCH`, `ODATA_COMPLETE_KEYS`, `ODATA_COMPLETE_KEYS_TOP`, `ODATA_METADATA_TTL`, `ODATA_DEBUG` |
| [nu-complete](modules/nu-complete.md#configuration) | `NU_COMPLETE_EVAL` |
| [terminal](modules/terminal.md#configuration), [nu-config](modules/nu-config.md#configuration) | none, on purpose |

## Not a knob

The theme. `theme use <name>` renders it for everything at once and what was
rendered last is the theme ([Theming](../concepts/theming.md)).
