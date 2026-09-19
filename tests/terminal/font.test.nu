# modules/terminal/font.nu against the fake ghostty: what Ghostty is asked
# about a family, the registry with what is installed, an install from a
# release archive (a fixture directory stands in for the release, through
# NERD_FONTS_RELEASE), and `font use`. The font directory is under the run's
# fake HOME, so nothing is installed for real.
use lib.nu *
use std/assert
use terminal *

def faces [fake: record, ...families: string] {
  $families | str join "\n" | save -f ($fake.root | path join faces)
}

def "test face asks Ghostty with no config loaded and the family last" [] {
  let fake = fake-ghostty
  faces $fake "Hack Nerd Font"
  assert equal (font face "Hack Nerd Font") "Hack Nerd Font"
  assert equal (font face "Nope Nerd Font") "JetBrains Mono" "an unknown family falls back to the built-in font"
  let call = ghostty-calls $fake | where {|c| $c.0 == "+show-face" } | first
  # `--config-default-files=false` must come before the family, or the
  # user's own font-family answers instead (the bug fixed in M10).
  assert equal $call ["+show-face" "--config-default-files=false" "--font-family=Hack Nerd Font" "--string=A"]
}

def "test list marks what Ghostty finds and what it is using" [] {
  let fake = fake-ghostty
  faces $fake "Hack Nerd Font" "FiraCode Nerd Font"
  "font-family = FiraCode Nerd Font Mono\n" | save ($fake.root | path join show-config)
  let rows = font list
  assert equal ($rows | columns) [font installed current family what]
  assert equal ($rows | where installed | get font) [FiraCode Hack] "in registry order"
  assert equal ($rows | where current | get font) [FiraCode] "a variant of the family counts as current"
  assert equal ($rows | where font == Hack | get 0.family) "Hack Nerd Font"
  assert equal ($rows | length) 15
}

def "test installed means the face Ghostty names starts with the family" [] {
  let fake = fake-ghostty
  # A face that merely contains the family is a different font.
  faces $fake "Not Hack Nerd Font"
  assert equal (font list | where font == Hack | get 0.installed) false
}

# A release directory with Hack's archive: the four faces the installer
# wants, plus the noise a real archive has. .tar.xz on Linux, .zip elsewhere,
# the way `font install` chooses.
def release-with-hack [--without-faces]: nothing -> string {
  let release = scratch
  let src = scratch
  let files = if $without_faces { [] } else { [Regular Bold Italic BoldItalic] | each {|f| $"HackNerdFont-($f).ttf" } }
  for f in ($files ++ [HackNerdFontMono-Regular.ttf HackNerdFontPropo-Bold.ttf README.md LICENSE]) {
    $"not really a font: ($f)\n" | save ($src | path join $f)
  }
  cd $src
  if $nu.os-info.name == "linux" {
    ^tar -cJf ($release | path join Hack.tar.xz) ...(ls | get name | path basename)
  } else {
    ^tar -a -cf ($release | path join Hack.zip) ...(ls | get name | path basename)
  }
  $release
}

def temp-dirs []: nothing -> list<string> {
  glob ($nu.temp-dir + "/nerd-font-*")
}

def "test install --archive takes exactly the four faces and cleans up" [] {
  let fake = fake-ghostty
  $env.NERD_FONTS_RELEASE = release-with-hack
  let before = temp-dirs
  font install Hack --yes --archive
  let dest = font dir
  assert ($dest | str starts-with $nu.home-dir) "the font dir is under HOME"
  assert equal (ls $dest | get name | path basename | sort) [HackNerdFont-Bold.ttf HackNerdFont-BoldItalic.ttf HackNerdFont-Italic.ttf HackNerdFont-Regular.ttf]
  assert equal (temp-dirs) $before "the temporary directory is removed"
}

def "test install --archive fails cleanly when the archive has no faces" [] {
  let fake = fake-ghostty
  $env.NERD_FONTS_RELEASE = release-with-hack --without-faces
  let before = temp-dirs
  let err = try { font install Hack --yes --archive; null } catch {|e| $e.msg }
  assert ($err | str contains "holds no HackNerdFont-*.ttf") $err
  assert equal (temp-dirs) $before "the temporary directory is removed on failure too"
  assert not (font dir | path join HackNerdFontMono-Regular.ttf | path exists)
}

def "test install says so when the font is already there" [] {
  let fake = fake-ghostty
  faces $fake "Hack Nerd Font"
  $env.NERD_FONTS_RELEASE = "/nowhere"
  font install Hack --yes --archive
  # Ghostty was asked what is installed and what is current, nothing else.
  assert equal (ghostty-calls $fake | each {|c| $c.0 } | uniq | sort) ["+show-config" "+show-face"]
}

def "test use writes the family Ghostty reports and reloads" [] {
  let fake = fake-ghostty
  faces $fake "Hack Nerd Font"
  "font-family = Their Font\n" | save ($fake.config | path join config.ghostty)
  font use Hack
  assert equal (ghostty settings | get font-family) "Hack Nerd Font"
  assert equal (ghostty live font-family) "Hack Nerd Font" "ours wins over theirs through the reset line"
  assert equal (font list | where current | get font) [Hack]
}

def "test use of a font that is not installed asks first, and cannot here" [] {
  let fake = fake-ghostty
  # `font use` installs after asking; headless there is no one to ask.
  let err = try { font use Hack; null } catch {|e| $e.msg }
  assert ($err | str contains "no terminal to ask on") $err
  assert equal (ghostty settings) {}
}
