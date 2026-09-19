# Write an autoload drop-in

Every `*.nu` file in your `autoload/` is loaded by Nushell at the end of
startup, in alphabetical order: after the distro, after the generated tool
init files. Because it runs last, it overrides everything, and because the
distro never writes there, it is the place for anything private or specific
to one machine.

## settings.nu or autoload/?

| it is | goes in |
|---|---|
| a **value** the distro ships a default for — anything `nu-config knobs` lists | `settings.nu`. It is sourced second, so the rest of the config reads your value |
| **behaviour** — an alias, a `def`, a hook, a keybinding, a menu, an environment variable the distro knows nothing about, a secret | `autoload/<anything>.nu` |

The tell: if you find yourself writing `$env.config.table.mode` in
`autoload/`, it works, but `nu-config knobs` will not know you did it. If you
find yourself writing an `alias` in `settings.nu`, it works too, but it is
not a knob and belongs with the rest of your behaviour.

## Write one

`nu-config edit user` opens your directory; `autoload/README.md` is already
there. Say `autoload/local.nu`:

```nu
# local.nu — this machine only
alias gs = git status --short
$env.WORK_TOKEN = (open ~/.config/work.token | str trim)
path add ($nu.home-dir | path join .local work bin)

# A keybinding: appended, never assigned — the distro's list merges into
# Nushell's defaults by name, and `= [...]` would drop them all.
$env.config.keybindings ++= [{
  name: clear_screen
  modifier: control
  keycode: char_l
  mode: [emacs vi_insert vi_normal]
  event: { send: clearscreen }
}]

# A hook, appended the same way.
$env.config.hooks.env_change.PWD ++= [{|before, after|
  if ($after | path join .nvmrc | path exists) { print "nvm: .nvmrc here" }
}]
```

`keybindings list` shows every modifier, keycode and event; `keybindings
listen` prints what Reedline calls the key you press; `keybindings default`
and `$env.config.menus` are the defaults as records you can copy.

## Check it

Open a new shell — a drop-in is loaded by the REPL, so it has to be a real
one:

```nu
which gs                                          # alias
$env.WORK_TOKEN
$env.config.keybindings | where name == clear_screen | length   # 1
$env.PATH | where $it =~ "work/bin"
```

Run on 2026-09-19 with `XDG_CONFIG_HOME` pointed at a scratch directory: all
four, as expected, in a REPL. And the same four under `nu -l -c '…'`: the
alias is there, `WORK_TOKEN` is unset, no keybinding, no path.

## The two limits, both inherent to autoload directories

- **`nu -c`, `nu script.nu` and even `nu -l -c` do not load them.** Nushell
  loads `$nu.user-autoload-dirs` only for an interactive shell. A script that
  needs something from a drop-in must `source` or `use` it by path.
- **The distro cannot depend on them.** They run after every `conf/` file,
  so nothing in the distro can read what a drop-in sets — which is exactly
  what makes a drop-in safe to write.

The same is true of `vendor/autoload/`, where the generated zoxide, atuin and
carapace files live; that is why a headless test of carapace has to `source`
its file first ([Debug Tab](debug-tab.md)).
