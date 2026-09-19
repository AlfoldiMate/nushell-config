# install.nu, headless: `--dry-run` prints the plan and writes nothing;
# `--defaults` writes exactly the scaffold, pointing at this checkout, with
# no override in settings.nu; a second run changes nothing; a config.nu that
# points elsewhere is kept as a backup. XDG_CONFIG_HOME names the directory
# the installer writes, so each test gets a fresh one, and HOME is the run's
# fake, so nothing here reaches a real Ghostty config.
use lib.nu *
use std/assert

def --env fresh-config-home []: nothing -> string {
  let d = scratch
  $env.XDG_CONFIG_HOME = $d
  $d | path join nushell
}

def --wrapped install [...flags: string]: nothing -> record {
  ^$nu.current-exe ($ROOT | path join install.nu) --skip-tools --skip-plugins ...$flags | complete
}

def files-under [dir: string]: nothing -> list<string> {
  if not ($dir | path exists) { return [] }
  glob ($dir + "/**/*") --no-dir | each {|f| $f | path relative-to $dir } | sort
}

const SCAFFOLD = [
  README.md
  autoload/README.md
  autoload/example.nu.off
  completions/README.md
  completions/hello.nu.off
  config.nu
  modules/README.md
  plugins/README.md
  settings.nu
  themes/README.md
  themes/palettes/example.nuon.off
]

def "test --dry-run prints the plan and writes nothing" [] {
  let user = fresh-config-home
  let ran = install --dry-run
  assert equal $ran.exit_code 0 $ran.stderr
  let out = $ran.stdout | ansi strip
  assert ($out | str contains $"writing config.nu → ($ROOT)") $out
  assert ($out | str contains "would write   settings.nu") $out
  assert ($out | str contains "dry run — nothing was changed") $out
  assert equal (files-under $user) []
}

def "test --defaults writes exactly the scaffold, pointing here, with no override" [] {
  let user = fresh-config-home
  let ran = install --defaults
  assert equal $ran.exit_code 0 $ran.stderr
  assert equal (files-under $user) $SCAFFOLD
  let cfg = open --raw ($user | path join config.nu)
  assert ($cfg | str contains ($ROOT | to nuon)) $cfg
  # The shell it wrote: split layout, the scaffold as written, no override.
  let shell = with-env { XDG_DATA_HOME: (scratch) } { ^$nu.current-exe -l -c 'print (nu-config install-status | get state) (nu-config knobs --overridden | length) (nu-config user status | where state != present | length)' | complete }
  assert equal $shell.exit_code 0 $shell.stderr
  assert equal ($shell.stdout | lines) [split "0" "0"]
}

def "test a second run keeps everything as it is" [] {
  let user = fresh-config-home
  install --defaults | ignore
  "# mine\n" | save -a ($user | path join settings.nu)
  let before = files-under $user | each {|f| { file: $f, hash: (open --raw ($user | path join $f) | hash md5) } }
  let ran = install --defaults
  assert equal $ran.exit_code 0 $ran.stderr
  assert ($ran.stdout | ansi strip | str contains "config.nu already points here")
  let after = files-under $user | each {|f| { file: $f, hash: (open --raw ($user | path join $f) | hash md5) } }
  assert equal $after $before
}

def "test a config.nu pointing elsewhere is kept as a backup" [] {
  let user = fresh-config-home
  mkdir $user
  "# someone else's config\n" | save ($user | path join config.nu)
  let ran = install --defaults
  assert equal $ran.exit_code 0 $ran.stderr
  assert ($ran.stdout | ansi strip | str contains "config.nu exists and points somewhere else — keeping it as config.nu.backup-")
  let backups = files-under $user | where $it =~ '^config\.nu\.backup-'
  assert equal ($backups | length) 1
  assert equal (open --raw ($user | path join ($backups | first))) "# someone else's config\n"
  assert (open --raw ($user | path join config.nu) | str contains ($ROOT | to nuon))
}

def "test the installer refuses to write into a checkout of the distro" [] {
  # The test is on distro.nu being there, whichever checkout it is.
  let d = scratch
  mkdir ($d | path join nushell)
  "# a checkout\n" | save ($d | path join nushell distro.nu)
  $env.XDG_CONFIG_HOME = $d
  let ran = install --defaults
  assert equal $ran.exit_code 1
  assert ($ran.stderr | str contains "is a checkout of the distro") $ran.stderr
  assert equal (files-under ($d | path join nushell)) [distro.nu]
}
