# Platforms: what is proven where

`.github/workflows/ci.yml` runs the real installer and then loads the config for
real on macOS, Linux and Windows, every push: install, `install-status` is
`split`, `nu-check distro.nu`, `nu-config module lint`, `nu-config doctor`, and
a default install leaving no overrides behind.

That is the floor, and it is worth being exact about the ceiling. What is
actually exercised, per platform:

| | macOS | Linux | Windows |
|---|---|---|---|
| parses, installs, loads | CI, and by hand | CI | CI |
| `bootstrap/install.sh` | by hand: clone, re-run as fast-forward, and the release-tarball path with `nu` off PATH | `sh -n` only | n/a |
| `bootstrap/install.ps1` | n/a | n/a | parse only |
| theme picker, Ghostty config | by hand | not run — no Ghostty on the runner | Ghostty has no Windows build |
| font install | by hand, archive path; the Homebrew cask path is not run | not run; `fc-cache` branch unexercised | not run; the `HKCU\…\Fonts` registry step is written from the docs only |
| `port` | `lsof`, by hand | `lsof`, not run | the `netstat -ano` branch, not run |

The pattern in everything above: what a platform *cannot* do is stated rather
than papered over. `terminal install` on Windows prints the download page and
runs nothing, because there is no Ghostty build to install; `port` errors with
the command to use instead when `lsof` is absent, rather than returning an
empty table that would read as "nothing is listening".

Two things that look platform-specific and are not: `duh` uses Nushell's own
`du`, which is a built-in and takes `--max-depth` on every platform, and `tree`
/ `lt` / `rgt` want `eza` and `ripgrep` but are `alias` and `def`, so a missing
tool costs a "command not found" the moment you use one and nothing at startup.


Running the config on Linux or Windows, and what to do about the gaps, is
[Run on Linux and Windows](../cookbook/other-platforms.md).
