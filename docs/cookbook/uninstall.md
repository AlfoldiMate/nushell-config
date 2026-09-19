# Undo the whole thing

Nothing the distro did is hidden. It wrote one file into Nushell's config
directory, one file plus one line into Ghostty's, and everything else it
owns is under the checkout or under `.state/`. Undoing it is removing those,
in this order.

## 1. Ghostty, if you let it in

```nu
ghostty status               # what the distro wrote: theme, icon, command, font
ghostty reset                # remove its file and the one include line; your config is left byte-identical
```

The distro's settings live in `nushell-distro.ghostty` next to Ghostty's
config, included from it by one `config-file = ?nushell-distro.ghostty` line.
`reset` removes both and nothing else; the `<config>.backup-<stamp>` it made
when it first added the line stays for you to compare. Do this while the
module is still loadable — it is the distro's command.

## 2. The pointer

```nu
rm $nu.config-path           # the three-line config.nu; the previous one is beside it as config.nu.backup-<stamp>
```

That is the uninstall. Nushell now starts with no configuration — its own
defaults, the standard library and the plugin registry — and nothing sources
the checkout any more. Run on 2026-09-19 with `XDG_CONFIG_HOME` pointed at a
scratch directory: `install-status` was `split` before, and after removing
`config.nu` a `nu -l` had no `nu-config` command and nothing else of the
distro's.

If you had a `config.nu` before, `mv config.nu.backup-<stamp> config.nu` is
the way back to it.

## 3. The checkout

```nu
rm -rf ~/.local/share/nushell-distro     # or wherever `nu-config distro-root` said
```

## 4. What is left, and yours

Everything else in your config directory is yours, and the distro never
needed any of it removed:

| | keep or remove |
|---|---|
| `settings.nu`, `autoload/`, `completions/`, `themes/`, `modules/`, `plugins/` | yours. `settings.nu`, the READMEs and the `.off` examples came from the distro's `templates/user/`, but you own them now; nothing reads them once the distro is gone |
| `history.sqlite3`, `plugin.msgpackz` | Nushell's own; a plain `nu` goes on using them |
| `vendor/autoload/*.nu` | generated init files for zoxide, atuin, carapace. Nushell loads them without the distro too, so remove them if you do not want those tools wired: `nu-config tools remove <tool>` for each before step 2, or `rm` after |
| `.state/` | the theme render, the update check, agent sessions, the OData registry. Nothing reads them once the distro is gone; `rm -rf` |
| `$nu.cache-dir/nu-complete`, `$nu.cache-dir/odata` | caches; `rm -rf` |

Fonts installed by `font install` stay installed — they are files in your
font directory (`~/Library/Fonts`, `~/.local/share/fonts`) or a Homebrew
cask, and removing a font you may be using elsewhere is not the distro's
call.

## Keeping the shell, dropping the distro

If what you want is the same shell without the moving parts, that is not an
uninstall: `nu-config module disable <name>` for each module you do not want,
`const UPDATE_CHECK_EVERY = 0sec` in `settings.nu` for the update check, and
`SMART_TAB = false` for Nushell's own Tab menu
([Knobs](../reference/knobs.md)). What is left is `defaults.nu` and `conf/`,
which is a few hundred lines of values you can read in one sitting.
