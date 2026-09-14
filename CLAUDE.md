# CLAUDE.md

This repo is the live Nushell configuration: the platform config dir is a
symlink to it, so an edit takes effect in the next shell and a parse error
breaks every new terminal. Verify before reporting done:

```nu
nu-check config.nu                       # parse, follows every `source`
nu -l -c 'nu-config doctor'              # loads the config for real
nu -n -c '<snippet>'                     # isolated snippet, no config
```

`nu -c` does NOT load the config; use `nu -l -c` to test anything in here.

## Rules

- Settings are leaf-key assignments (`$env.config.a.b = ...`), never whole
  records, and never `$env.config = {...}`.
- One concern per `conf/` file; `config.nu` only wires them in order. Knobs a
  user is expected to change live in `conf/settings.nu`.
- Paths are parse-time constants derived from `$ROOT` (`path self`). Never a
  hard-coded home directory.
- Optional tools are guarded with `which`; `alias` and `extern` cannot be
  inside an `if`, they are parse-time.
- Generated files (`vendor/autoload/*.nu`), `plugin.msgpackz`, history and
  `autoload/*` are gitignored. Change the generator in
  `modules/nu-config/tools.nu`, never the generated file.
- Comments explain why, and state measured costs (`timeit`,
  `nu-config startup-time`), not estimates.
- Nushell makes breaking changes at minor versions. `help <cmd>` and
  `config nu --doc` on the installed binary beat memory and web snippets.
- OData (`modules/odata` and its README, `conf/odata.nu`): `where` cannot be
  overloaded (parser keyword), so a `pre_execution` hook plans the pushdown
  and `odata get` applies it. Test the module without touching real state:
  `nu -n` + `use modules/odata *` + `$env.ODATA_SERVICES = {…}` (the scratch
  registry); the hook only in a pty.
- Completion lives in `modules/nu-complete` + `completions/<tool>.nu`
  (`docs/completion.md`). Test it without a terminal:
  `nu -l -c '"brew install rip" | commandline complete --detailed'` and
  `nu -l -c 'nu-complete smart "ls | where " 11'`. `nu --ide-complete` does
  not run `@complete` completers.
