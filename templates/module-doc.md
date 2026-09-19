# <name>

One sentence: what this module lets you do.

```nu
<name> <verb> ...        # the one example that shows why it exists
```

This is the reference page: `docs/reference/modules/<name>.md`, named by
`docs:` in the module's `meta.nuon`. If the module has a design worth a page
— decisions someone would otherwise re-litigate — that is
`docs/concepts/<name>.md`, and this page links to it here.

## Commands

| Command | Does |
|---|---|
| `<name> ...` | |

## Configuration

Defaults live in this module (`meta.nuon` declares them, `activate` applies
them). Override in your own `settings.nu`; `nu-config knobs | where owner ==
<name>` lists them.

| Knob | Default | Meaning |
|---|---|---|

## Dependencies

What must be installed, why, and what degrades without it. `nu-config module
check <name>`.

## Design

One paragraph, and a link to the concept page if there is one. Not the whole
story twice.

## Measured

Real numbers from `timeit` / `nu-config startup-time`, with the date and the
Nushell version. Not adjectives.

## Files

```
mod.nu      the commands, and `<name> activate`
load.nu     `use` + activate
meta.nuon   description, dependencies, knobs, docs
```

## Limits

What it does not do, and what is untested.
