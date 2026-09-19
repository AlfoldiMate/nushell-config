# Your first setting

Nothing in the checkout is yours to edit. Every value the distro ships is in
its `defaults.nu`, and the way to change one is to say so in **your**
`settings.nu`:

```nu
nu-config edit user          # your directory in $EDITOR; settings.nu holds every knob, commented out
nu-config knobs              # every knob, its shipped value, and whether you set it
nu-config knobs --overridden # just yours
```

Say you want emacs keys and a plain table border. Both lines are already in
`settings.nu`, commented out in their sections; uncomment and change them:

```nu
$env.config.edit_mode = "emacs"
$env.config.table.mode = "rounded"
```

Open a new shell — the file is read at startup — and `nu-config knobs
--overridden` lists exactly those two.

## Why that works

`settings.nu` is sourced immediately after the distro's `defaults.nu`, so a
`const` there shadows the one here and an `$env.` assignment replaces it.
**You override by mentioning.** A knob you never write down keeps its shipped
value, including one added by a later `git pull` — there is no schema to
migrate and no generated file to regenerate, because the layering is a
language feature rather than a build step
([Layout](../concepts/layout.md#how-the-layering-works)).

`defaults.nu` is the catalogue, and its comments say what each knob does:
read it (`nu-config edit` opens the checkout), copy the line you want, change
it in your file. [Knobs](../reference/knobs.md) is the same list as a table.
For every `$env.config` key Nushell has, whether the distro mentions it or
not:

```nu
config nu --doc | nu-highlight | less -R
```

## Values or behaviour

Two user layers, and the difference matters:

| | goes in | loaded |
|---|---|---|
| a **value** the distro ships a default for — a knob | `settings.nu` | second, right after `defaults.nu`, so everything after it reads your value |
| **behaviour** — an alias, a hook, a keybinding, a `def`, a secret, anything the distro knows nothing about | a `.nu` file in your `autoload/` | last, after everything, so it wins |

```nu
# autoload/local.nu
alias ll = ls -l
$env.GITHUB_TOKEN = (open ~/.config/gh.token | str trim)
$env.config.keybindings ++= [{ name: clear, modifier: control, keycode: char_l, mode: [emacs vi_insert], event: { send: clearscreen } }]
```

Keybindings and menus are appended with `++=`, never assigned whole: the
distro's lists merge into Nushell's defaults by name, and assigning would drop
them ([Write an autoload drop-in](../cookbook/autoload.md)).

A module's knobs — `AGENT_MODEL`, `ODATA_SERVICE` — go in `settings.nu` too;
they are not in `defaults.nu` because a module carries its own defaults, but
`nu-config knobs` lists them with the rest.

Next: [Your first theme](first-theme.md).
