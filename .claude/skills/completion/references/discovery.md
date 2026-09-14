# Where a tool's command surface can be read from

Verified on this Mac on 2026-09-11 (Homebrew at /opt/homebrew, nu 0.115.1,
carapace 1.7.3, gh 2.100, uv 0.12, cargo 1.98). **V** = ran here, **D** =
from the cited doc. `scripts/discover.nu <tool>` checks all of this for one
tool in about a second.

## Ranking

1. **The tool's own completion engine** when it has one: cobra `__complete`
   (gh, kubectl, docker, helm), clap `COMPLETE=fish` (cargo nightly, jj).
   Complete, includes hidden commands and dynamic values.
2. **A shipped or generated fish file** (clap, argparse, hand-written): a
   flat list of `complete` calls, one per (context, flag), with the dynamic
   source spelled out in `-a "(cmd)"`. fish > zsh > bash for parsing.
3. **Native nushell output** (`uv generate-shell-completion nushell`,
   `starship completions nushell`, `atuin gen-completions --shell nushell`):
   clap_complete_nushell externs, static, enums as `def "nu-complete uv x"`.
4. **Help text** (always available, always incomplete): clap / cobra /
   argparse / git-short-usage layouts, `scripts/help-tree.nu` parses them.
5. **zsh `_tool`**: `_arguments` specs; dynamic helpers `_tool_<x>` whose
   body is the command to run (brew: `__brew_formulae` → `brew formulae`).
6. **carapace**: `carapace <tool> export` (structure, cobra-shaped JSON, no
   sources), `carapace <tool> nushell <tool> sub ""` (an oracle), `carapace
   --macro tools.git.LocalBranches ""` (runs one source). The Go completer
   at `github.com/carapace-sh/carapace-bin/tree/master/completers/common/<tool>_completer/cmd/<sub>.go`
   names the exact source per positional and flag (`git.ActionRefs(...)`).
7. **nu_scripts** `custom-completions/<tool>/<tool>-completions.nu`
   (85 tools, V): hand-written `nu-complete <tool> <x>` closures to copy.
8. **man**: `man -P cat <tool> | col -bx`, `MANWIDTH=200`.

## Shipped files on this machine (V)

| Shell | Directory | Count |
|---|---|---|
| fish | `/opt/homebrew/share/fish/vendor_completions.d/<tool>.fish` | 26 |
| zsh | `/opt/homebrew/share/zsh/site-functions/_<tool>` | 26 |
| bash | `/opt/homebrew/etc/bash_completion.d/<tool>` | 31 |
| brew's own | `/opt/homebrew/completions/{zsh/_brew,bash/brew,fish/brew.fish}`, `internal_commands_list.txt` | |
| git (Apple) | `/Library/Developer/CommandLineTools/usr/share/git-core/git-completion.{bash,zsh}` | |

`brew list <formula> | grep -E 'completion|site-functions|fish'` finds a
formula's files (formula ≠ binary: ripgrep→`_rg`, git-delta→`_delta`,
node→`npm`, tlrc→`_tldr`).

**cobra tools ship trampolines**: `_gh` and `gh.fish` only call
`gh __complete …` at runtime; nothing static to parse. `npm`'s bash file
calls `npm completion`. `bat.fish` runs `bat --list-themes`. So step 2 pays
off for clap/argparse/hand-written files only.

## Formats

### fish (`scripts/fish-spec.nu`)

```fish
complete -c uv -n "__fish_uv_needs_command" -f -a "add" -d 'Add dependencies to the project'         # subcommand
complete -c uv -n "__fish_uv_using_subcommand add" -s r -l requirements -d 'Add…' -r -F              # flag, takes a value, files ok
complete -c uv -n "__fish_uv_using_subcommand pip; and __fish_seen_subcommand_from install" -l target -r -f -a "(__fish_complete_directories)"
complete -c uv -n "__fish_uv_needs_command" -l color -r -f -a "auto\t'desc'\nalways\t'desc'"         # enum with descriptions
complete -c rg -s f -l file -d 'Search…' -r -F
complete -c $bat -l theme -x -a "(command $bat --list-themes | command cat)"                         # dynamic source
__fish_brew_complete_cmd 'install' 'Install a formula or cask'                                       # hand-written wrappers (brew)
__fish_brew_complete_arg 'install; and not __fish_seen_argument -l cask' -a '(__fish_brew_suggest_formulae_all)'
```

Tokens: `-c cmd`, `-n cond`, `-s`/`-l`/`-o`, `-d desc`, `-a args`, `-r`
value required, `-f` no files, `-F` files, `-x` = `-r -f`, `-w` wraps
(D: fishshell.com/docs/current/cmds/complete.html). Conditions:
`__fish_seen_subcommand_from a b` (any of), `__fish_<tool>_using_subcommand x`,
`__fish_<tool>_needs_command` / `__fish_use_subcommand` / `__fish_is_first_arg`
(root), `not …` (defining children). Payloads of `-a` are fish command
lines: `\t` separates value and description, `\n` entries, `(…)` dynamic,
`$var` a variable defined earlier in the file (read it).

### zsh `_arguments` (clap output, V from `_uv`)

```
'--cache-dir=[Path to the cache directory]:CACHE_DIR:_files -/'
'*--allow-insecure-host=[desc]:ALLOW_INSECURE_HOST:_urls'                # * repeatable
'--color=[desc]:COLOR_CHOICE:((auto\:"desc" always\:"desc" never\:"desc"))'
'(-v --verbose)*-q[Use quiet output]'                                     # exclusion group
":: :_uv_commands"  "*::: :-&gt;uv"   then  case $line[1] in (pip) _arguments … ;;
{-A+,--after-context=}'[desc]: :_guard …'                                 # hand-written (rg)
'*:file:_files'
```

Regex: `^'(?P<excl>\([^)]*\))?(?P<rep>\*)?(?P<flag>-{1,2}[\w.-]+)(?P<takes>=?)\[(?P<desc>(?:[^\]\\]|\\.)*)\](?::(?P<argname>[^:]*):(?P<completer>.*))?'`.
Value spec: `_files`, `_files -/` (dirs), `_urls`, `((a\:"d" …))` enum,
`_<tool>_<name>` custom fn → read its body for the command. `_describe -t
formulae 'all formulae' list` marks a dynamic list (brew).

### bash

clap: `case "${cmd}" in uv__pip__install) opts="-r -e … --requirements …"`,
`COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )`; value flags under
`case "${prev}" in --requirements) COMPREPLY=($(compgen -f …))`. No
descriptions. Hand-written (git-completion.bash): `_git_checkout ()`,
`__git_complete_refs`, `__git_heads`, `__git_remotes` — read function bodies.

### cobra `__complete` (`scripts/cobra-tree.nu`, V)

```
gh __complete pr ""            → checkout<TAB>Check out a pull request in git … then `:4`
gh __complete pr list --       → --assignee<TAB>Filter by assignee …
gh __complete pr list --state "" → open closed merged all :4
gh __complete pr checkout ""   → :0   (dynamic, needs a repo with a remote/network)
```

Directives (D): Error=1 NoSpace=2 NoFileComp=4 FilterFileExt=8
FilterDirs=16 KeepOrder=32. Set `<TOOL>_ACTIVE_HELP=0`. ~50-60 ms per call
for gh. Flag *types* are not given: take them from help.

### clap dynamic (D: docs.rs/clap_complete/latest/clap_complete/env)

`COMPLETE=fish tool -- tool <args…> ""` (or `<TOOL>_COMPLETE`); shells
bash/fish/zsh/elvish/powershell, **no nushell**; needs the
`unstable-dynamic` feature. V: uv, rg, fd, bat, rustup, cargo stable ignore
it; `CARGO_COMPLETE=fish cargo +nightly -- cargo bu` works. jj supports it (D).

### Native generators (V unless D)

| Tool | Nushell | Fish |
|---|---|---|
| uv | `uv generate-shell-completion nushell` (5810 lines) | `… fish` |
| starship | `starship completions nushell` | |
| atuin | `atuin gen-completions --shell nushell` | |
| gh | no | `gh completion -s fish` (trampoline) |
| rustup / cargo | no | `rustup completions fish [cargo]` (cargo's zsh one just sources rustc's) |
| rg | no | `rg --generate complete-fish` |
| fd | no | `fd --gen-completions fish` |
| bat | no | `bat --completion fish` |
| delta | no | `delta --generate-completion fish` |
| npm | no | `npm completion` (bash/zsh) |
| jj (D) | `jj util completion nushell` | |
| just (D) | `just --completions nushell` | |
| mise (D) | no | `mise completion fish` |
| docker / kubectl / helm / deno / pnpm (D) | no | `<tool> completion fish` |

clap_complete_nushell output shape:

```nu
module completions {
  def "nu-complete uv color" [] { [ "auto" "always" "never" ] }
  export extern "uv pip install" [
    --requirements(-r): path  # Install the packages listed…
    --color: string@"nu-complete uv color"
    ...package: string
  ]
}
export use completions *
```

No dynamic sources (D: clap-rs/clap#5840). Mine it for enums and types.

### Help layouts (`scripts/help-tree.nu`)

- **clap v4**: `Usage: uv pip install [OPTIONS] <PACKAGE|…>`, `Commands:`,
  `Arguments:`, `Options:` (+ named groups `Cache options:`), 2-space
  indent, `[possible values: a, b]`, `[env: X=]`, `[default: …]`; `--help`
  long form puts the description on the next line, `-h` is one-line.
- **cobra**: `USAGE`, `CORE COMMANDS` / `ADDITIONAL COMMANDS`, `ALIASES`,
  `FLAGS`, `INHERITED FLAGS`; commands `name:   desc`; flags `-b, --branch
  string   desc`.
- **argparse**: `usage:`, `positional arguments:`, `optional arguments:` or
  `options:`, `--prompt PROMPT`.
- **git**: `git <cmd> -h` short usage on stdout, `--help` opens the man
  page; `git --list-cmds=main,others,alias`, `git <cmd>
  --git-completion-helper-all` prints every flag (needs a repo cwd).
- **npm**: `npm -l`; headless completion `COMP_CWORD=1 COMP_LINE="npm ins"
  COMP_POINT=7 npm completion -- npm ins`.
- **cargo**: `cargo --list` marks aliases (`b   alias: build`).
- Streams (V): uv/rustup/brew bare → stderr with non-zero exit; `npm
  --help` → stdout exit 1; gh/cargo/git → stdout 0. Read both streams,
  ignore the exit code. Env: `PAGER=cat GIT_PAGER=cat MANPAGER=cat
  NO_COLOR=1 TERM=dumb COLUMNS=200`.

### carapace (V, 1.7.3)

- `carapace --list` → JSON of 653 completers.
- `carapace <tool> export` → `{Name, Short, Commands[], LocalFlags[{Longhand, Shorthand, Usage, Type}], PersistentFlags}`.
- `carapace <tool> nushell <tool> sub ""` → `[{value, display, description, style}]`.
- `carapace --macro` lists 824 macros; `carapace --macro tools.brew.AllFormulae ""` runs one.
- Spec YAML (D: carapace-sh.github.io/carapace-spec): `completion: {positional: [["$_tools.git.LocalBranches"]], flag: {--f: ["$files"]}}`.
- Timing here: `brew install` 1.6 s (Ruby), `git checkout` 60 ms, `gh` root 21 ms, `cargo` root 41 ms.

### nu_scripts (V, 85 dirs)

`https://raw.githubusercontent.com/nushell/nu_scripts/main/custom-completions/<tool>/<tool>-completions.nu`:
ack adb aerospace ani-cli as aws bat bend bitwarden-cli bmc btm cargo-loco
cargo-make cargo claude codex composer croc curl dart docker dotnet eza
fastboot flutter fsharpc fsharpi gh git glow godoc gradlew jj just komorebi
kw less lftp loco lsd make man mask md-to-clip mix mvn mysql nano nix npm op
pass pdm pnpm podman poetry pre-commit pytest reflector rg rustup rye scoop
ssh swift-bundler tar tcpdump television tldr toipe ttyper typst uv virsh
vscode windows winget xgettext yarn zef zellij zig zmx zoxide.
`auto-generate/completions/` holds ~700 more, fish-converted, static.
`nu-config fetch completion <tool>` vendors one into `completions/`.

## Installed here (V, 2026-09-11)

carapace, gh, cargo, rustup (stable+nightly), uv, rg, fd, bat, npm/node,
python3, starship, zoxide, atuin, git, brew, make, eza, delta, jq.
Missing: fish, kubectl, docker, helm, jj, mise, just, pnpm, deno, bun, pip,
poetry, ffmpeg, tmux, yq. (fish being absent means `fish -c 'complete -C'`
is not an oracle here.)
