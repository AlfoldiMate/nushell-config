# Updating

The distro is a git checkout, so an update is a pull — and because your
files are elsewhere, a pull never conflicts with anything you wrote.

```nu
nu-config upgrade            # git pull --ff-only in the checkout, then the commits that came in
nu-config upgrade check      # fetch now and say where the checkout stands
nu-config upgrade status     # the last check's result, no network
```

You do not have to remember to. Once every `UPDATE_CHECK_EVERY` (a day) an
interactive shell spawns a background job that fetches, and the next shell to
start prints one line when the checkout is behind:

```
distro: 2 commits behind origin/main · A new Ghostty window starts Nushell — nu-config upgrade
```

The fetch is never on the startup path — a start reads the last result out of
`<your>/.state/nu-config/upgrade.nuon` (0.3 ms) — and the line is keyed to the
HEAD the check saw, so it disappears as soon as HEAD moves, by `nu-config
upgrade` or by hand. `nu -c` and scripts neither print nor spawn anything.
`const UPDATE_CHECK_EVERY = 0sec` in your `settings.nu` turns the check off.

A knob the update added keeps its shipped value until you mention it; a
template the update changed is re-rendered by `theme sync`; a module the
update added is off until `nu-config module enable <name>`. `nu-config
doctor` after a pull says if anything needs you.

## After `brew upgrade nushell`

```nu
nu-config plugins add        # the registry is protocol-versioned against the nu that wrote it
nu-config doctor
```

The plugin registry stores each plugin's signatures against the protocol
version of the `nu` that wrote them, so after a Nushell upgrade the entries
describe a protocol the new binary no longer speaks. `plugin list` showing an
old version, or a plugin command failing after an upgrade, is this and
nothing else ([Plugins](../concepts/plugins.md)).

Nushell makes breaking changes at minor versions; the distro is verified
against 0.115, and the pin is raised deliberately.

## After installing a tool

```nu
nu-config tools setup        # generate the init file for anything newly installed, drop it for anything gone
nu-config tools status       # installed against generated
```

zoxide, atuin and carapace each emit a Nushell init file; `tools setup`
writes those into `vendor/autoload/`, where Nushell loads them after
`config.nu`. Installation is the switch. Re-running `nu install.nu` does the
same, and is safe at any time.

That is the whole of getting started. Where to go from here:
[Concepts](../README.md#concepts) for how it works, the
[Cookbook](../README.md#cookbook) for the next thing you want to do.
