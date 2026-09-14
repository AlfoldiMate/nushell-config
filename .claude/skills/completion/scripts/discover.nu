#!/usr/bin/env nu
# discover.nu — where a tool's command surface can be read from, in order
#
#   nu discover.nu <tool> [--online]
#
# Probes, cheapest first, and prints one record so the next step is a
# lookup, not a guess:
#
#   existing         completions/<tool>.nu already in this config?
#   help             which help form works, layout (clap | cobra | argparse | git | unknown)
#   native           `<tool> … nushell|fish` generators the tool itself offers
#   cobra            answers `__complete` (gh, kubectl, docker, helm …)
#   clap_dynamic     answers COMPLETE=fish (cargo +nightly, jj …)
#   shipped          fish / zsh / bash completion files on this machine
#   carapace         known to carapace, and what `carapace <tool> nushell <tool> ""` costs
#   man              man page path
#   nu_scripts       (--online) a ready module in nushell/nu_scripts
#
# Probes run in a scratch directory: a tool that treats `completion` as a
# path argument (touch, mkdir) leaves its mess there. Tools whose first
# positional is a file are never probed for generators at all.

const NO_PROBE = [rm mv cp dd mkdir touch kill sudo chmod chown ln cat less more tee rmdir install unlink shred truncate]

# modules/… → the repo root: scripts/completion/skills/.claude/<repo>
const ROOT = (path self | path dirname | path dirname | path dirname | path dirname | path dirname)

def run-in [dir: path, argv: list<string>, env_extra: record = {}]: nothing -> record {
  let r = (do { cd $dir; with-env ({ PAGER: cat, GIT_PAGER: cat, NO_COLOR: "1", TERM: dumb, COLUMNS: "200" } | merge $env_extra) { echo "" | ^$argv.0 ...($argv | skip 1) | complete } })
  $r | update stdout { ansi strip } | update stderr { ansi strip }
}

def help-layout [text: string]: nothing -> string {
  if $text =~ '(?m)^(CORE |AVAILABLE |ADDITIONAL )?COMMANDS\s*$' or $text =~ '(?m)^(INHERITED )?FLAGS\s*$' or $text =~ '(?m)^Available Commands:' { "cobra" } else if $text =~ '(?m)^(Commands|Options|Arguments):\s*$' and $text =~ '(?m)^Usage: ' { "clap" } else if $text =~ '(?m)^(positional arguments|optional arguments|options):\s*$' { "argparse" } else if $text =~ '(?m)^usage: ' and $text =~ '(?m)^\s+-\S' { "git" } else { "unknown" }
}

def probe-help [tool: string, dir: path]: nothing -> record {
  for form in [["--help"] ["-h"] ["help"]] {
    let r = (run-in $dir ([$tool] ++ $form))
    let text = if ($r.stdout | str trim | is-not-empty) { $r.stdout } else { $r.stderr }
    if $text =~ '(?im)^\s*usage' or $text =~ '(?m)^[A-Z][A-Za-z ]*(commands|options|flags|arguments):?\s*$' {
      return { form: ($form | str join " "), stream: (if ($r.stdout | str trim | is-not-empty) { "stdout" } else { "stderr" }), exit_code: $r.exit_code, lines: ($text | lines | length), layout: (help-layout $text) }
    }
  }
  { form: null, layout: "unknown" }
}

# Generators tools offer, by shell. The first that prints something plausible wins.
def probe-native [tool: string, dir: path, shell: string]: nothing -> any {
  let forms = [
    ["generate-shell-completion" $shell] ["completions" $shell] ["completion" $shell] ["completion" "-s" $shell]
    ["util" "completion" $shell] ["--completions" $shell] ["--completion" $shell] ["--generate" $"complete-($shell)"]
    ["--gen-completions" $shell] ["gen-completions" "--shell" $shell] ["--generate-completion" $shell]
  ]
  let marker = (if $shell == "nushell" { 'extern|def ' } else { '(?m)^complete ' })
  for f in $forms {
    let r = (run-in $dir ([$tool] ++ $f))
    if $r.exit_code == 0 and ($r.stdout | lines | length) > 5 and ($r.stdout =~ $marker) {
      return { command: ([$tool] ++ $f | str join " "), lines: ($r.stdout | lines | length) }
    }
  }
  null
}

def probe-cobra [tool: string, dir: path]: nothing -> record {
  let r = (run-in $dir [$tool "__complete" ""] { (($tool | str uppercase | str replace --regex --all '[^A-Z0-9]' '_') + "_ACTIVE_HELP"): "0" })
  let ok = ($r.exit_code == 0 and ($r.stdout | lines | where $it =~ '^:\d+$' | is-not-empty))
  { ok: $ok, listed: (if $ok { $r.stdout | lines | where $it !~ '^:' | length } else { 0 }) }
}

def probe-clap-dynamic [tool: string, dir: path]: nothing -> record {
  let var = (($tool | str uppercase | str replace --regex --all '[^A-Z0-9]' '_') + "_COMPLETE")
  for v in ["COMPLETE" $var] {
    let r = (run-in $dir [$tool "--" $tool ""] { $v: "fish" })
    if $r.exit_code == 0 and ($r.stdout | lines | length) > 1 and ($r.stdout !~ '(?i)usage') { return { ok: true, env: $"($v)=fish" } }
  }
  { ok: false }
}

def shipped [tool: string]: nothing -> record {
  let prefix = ($env.HOMEBREW_PREFIX? | default "/opt/homebrew")
  let find = {|cands| $cands | where {|p| $p | path exists } | get -o 0 }
  {
    fish: (do $find [($prefix | path join share fish vendor_completions.d $"($tool).fish") ($prefix | path join completions fish $"($tool).fish") ("/usr/local/share/fish/vendor_completions.d" | path join $"($tool).fish") ("/usr/share/fish/vendor_completions.d" | path join $"($tool).fish") ("/usr/share/fish/completions" | path join $"($tool).fish")])
    zsh: (do $find [($prefix | path join share zsh site-functions $"_($tool)") ($prefix | path join completions zsh $"_($tool)") ("/usr/local/share/zsh/site-functions" | path join $"_($tool)") ("/usr/share/zsh/site-functions" | path join $"_($tool)") ("/usr/share/zsh/functions/Completion/Unix" | path join $"_($tool)")])
    bash: (do $find [($prefix | path join etc bash_completion.d $tool) ($prefix | path join completions bash $tool) ("/usr/share/bash-completion/completions" | path join $tool) ("/etc/bash_completion.d" | path join $tool)])
  }
}

def probe-carapace [tool: string, dir: path]: nothing -> record {
  if (which carapace | is-empty) { return { installed: false } }
  let known = (do -i { ^carapace --list | from json | columns } | default [] | any {|n| $n == $tool })
  if not $known { return { installed: true, known: false } }
  let t = (timeit { run-in $dir [carapace $tool nushell $tool ""] | ignore })
  let n = (run-in $dir [carapace $tool nushell $tool ""] | get stdout | do -i { from json } | default [] | length)
  { installed: true, known: true, root_candidates: $n, root_ms: ($t | into int | $in / 1_000_000 | math round) }
}

def probe-man [tool: string]: nothing -> any {
  let r = (^man -w $tool | complete)
  if $r.exit_code == 0 { $r.stdout | str trim } else { null }
}

def probe-nu-scripts [tool: string]: nothing -> any {
  let url = $"https://raw.githubusercontent.com/nushell/nu_scripts/main/custom-completions/($tool)/($tool)-completions.nu"
  let r = (do -i { http get --full --raw --max-time 5sec $url } )
  if $r != null and $r.status == 200 { { url: $url, lines: ($r.body | lines | length), dynamic_defs: ($r.body | lines | where $it =~ '^\s*(export )?def "?nu-complete' | length) } } else { null }
}

# What is already here for this tool.
def existing [tool: string]: nothing -> record {
  let spec = ($ROOT | path join completions $"($tool).nu")
  let vendored = ($ROOT | path join completions $"($tool)-completions.nu")
  {
    spec: (if ($spec | path exists) { $spec } else { null })
    vendored: (if ($vendored | path exists) { $vendored } else { null })
    wired: (do -i { open --raw ($ROOT | path join conf completions.nu) | lines | where $it =~ $"^use ($tool)(-completions)?\\.nu" | is-not-empty } | default false)
  }
}

export def main [
  tool: string
  --online      # also look in nushell/nu_scripts on GitHub
  --json
]: nothing -> string {
  let bin = (which $tool | get -o 0.path)
  if $bin == null { error make { msg: $"($tool) is not on PATH" } }
  let dir = (mktemp -d)
  let safe = ($tool not-in $NO_PROBE)
  let r = {
    tool: $tool
    path: $bin
    version: (do -i { run-in $dir [$tool --version] | get stdout | lines | first | default "" } | default "")
    existing: (existing $tool)
    help: (probe-help $tool $dir)
    native: (if $safe { { nushell: (probe-native $tool $dir nushell), fish: (probe-native $tool $dir fish) } } else { { skipped: "first positional is a path" } })
    cobra: (if $safe { probe-cobra $tool $dir } else { { ok: false } })
    clap_dynamic: (if $safe { probe-clap-dynamic $tool $dir } else { { ok: false } })
    shipped: (shipped $tool)
    carapace: (probe-carapace $tool $dir)
    man: (probe-man $tool)
    nu_scripts: (if $online { probe-nu-scripts $tool } else { "not checked (--online)" })
  }
  rm -rf $dir
  let r = ($r | insert recommended (recommend $r))
  if $json { $r | to json } else { $r | to nuon --indent 2 }
}

# The order to read sources in, given what exists.
def recommend [r: record]: nothing -> list<string> {
  mut steps = []
  if $r.existing.spec != null { $steps ++= [$"completions/($r.tool).nu exists: extend it, do not start over"] }
  if ($r.native | get -o nushell) != null { $steps ++= [$"native nushell: `($r.native.nushell.command)` — subcommands, flags, enums; add dynamic sources"] }
  if $r.cobra.ok { $steps ++= ["cobra: scripts/cobra-tree.nu (hidden subcommands, flag enums, dynamic positionals)"] }
  if $r.shipped.fish != null and not $r.cobra.ok { $steps ++= [$"fish file: scripts/fish-spec.nu --file ($r.shipped.fish)"] } else if ($r.native | get -o fish) != null and not $r.cobra.ok { $steps ++= [$"fish generator: `($r.native.fish.command) | nu scripts/fish-spec.nu --stdin ($r.tool)`"] }
  if $r.clap_dynamic.ok { $steps ++= [$"clap dynamic: `($r.clap_dynamic.env) ($r.tool) -- ($r.tool) <sub> \"\"` answers like fish would"] }
  if $r.shipped.zsh != null { $steps ++= [$"zsh file ($r.shipped.zsh): read the _<fn> bodies for dynamic sources"] }
  if $r.help.form != null { $steps ++= [$"help \(($r.help.layout)\): scripts/help-tree.nu ($r.tool)"] }
  if ($r.carapace | get -o known | default false) { $steps ++= [$"carapace knows ($r.tool) \(($r.carapace.root_ms) ms at root\): oracle for coverage, fallback: external"] }
  if $r.man != null { $steps ++= ["man page: descriptions and positional kinds the help lacks"] }
  $steps
}
