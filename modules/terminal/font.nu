# font — pick a Nerd Font, install it, and let Ghostty render the preview
#
#   font                    the picker: fifteen popular Nerd Fonts, install and keep
#   font list               what is in the registry, and what is installed here
#   font install <name>     download and install it, after asking
#   font preview <name>     a real Ghostty window in that font, showing a specimen
#   font specimen           the sample text, in the font this terminal is using now
#   font use <name>         install if needed, then keep it (ghostty.nu persists it)
#
# Why a new window is the preview
#
# You cannot preview a font you have not installed — the terminal renders with
# the fonts it has, and a name in a list tells you nothing. Nor can you preview
# one you HAVE installed in the window you are sitting in without keeping it:
# there is no escape sequence for "change font" the way OSC 4 is "change
# colour", which is what makes the theme picker able to repaint in place, and
# `ghostty reload` (macOS only) reloads the written configuration — a choice,
# not a preview.
#
# What Ghostty does have is `--font-family` on its own command line, so a new
# window can be opened in the candidate font running a specimen. That is a real
# preview: Ghostty's own rasterizer, Ghostty's own shaper, the actual ligatures
# and the actual Nerd Font glyphs, at the size you will use. It costs one window
# you close again.
#
# The alternative the design started with was pre-rendered PNG samples pushed
# over the Kitty graphics protocol, which Ghostty supports. It was dropped:
# nothing on a stock machine can rasterize a font file (no ImageMagick, no PIL,
# and macOS `qlmanage -t` returns a generic "Aa" icon, not a specimen), so the
# images would have to be built elsewhere and shipped or fetched — ~450 kB that
# can go stale against a Nerd Fonts release, to show something less true than
# the terminal itself already shows.

use ghostty.nu *

# ── The registry ──────────────────────────────────────────────────────────────
#
# Fifteen, by download count on the Nerd Fonts releases. Four fields do the work:
#
#   asset   the release asset base name — <asset>.zip / <asset>.tar.xz
#   stem    the exact file stem to install out of it. An asset holds every
#           variant (Mono, Propo, NL, and whole sub-families), so this picks one
#           — MesloLGS out of six Meslo variants, MonaspiceNe out of five.
#   family  what Ghostty calls it once installed. Nerd Fonts RENAMES several
#           fonts to avoid trademark collisions (CascadiaCode → CaskaydiaCove,
#           SourceCodePro → SauceCodePro, Monaspace → Monaspice, Terminus →
#           Terminess), so this is never derived from the name.
#   cask    Homebrew's cask, which is the fast path on macOS.
#
# `family` is a claim about the installed font, so nothing trusts it: what gets
# written into Ghostty's config is the family `ghostty +list-fonts` reports, and
# this value is only the pattern used to find it.
def registry []: nothing -> table {
  [
    { name: "JetBrainsMono"   asset: "JetBrainsMono"   stem: "JetBrainsMonoNerdFont"   family: "JetBrainsMono Nerd Font"   cask: "font-jetbrains-mono-nerd-font"   what: "ligatures, the most installed of them all — and Ghostty's own built-in font" }
    { name: "FiraCode"        asset: "FiraCode"        stem: "FiraCodeNerdFont"        family: "FiraCode Nerd Font"        cask: "font-fira-code-nerd-font"        what: "the original programming ligatures" }
    { name: "Hack"            asset: "Hack"            stem: "HackNerdFont"            family: "Hack Nerd Font"            cask: "font-hack-nerd-font"            what: "no ligatures, very legible small" }
    { name: "Meslo"           asset: "Meslo"           stem: "MesloLGSNerdFont"        family: "MesloLGS Nerd Font"        cask: "font-meslo-lg-nerd-font"        what: "Menlo with adjustable line gap; what powerlevel10k recommends" }
    { name: "CascadiaCode"    asset: "CascadiaCode"    stem: "CaskaydiaCoveNerdFont"   family: "CaskaydiaCove Nerd Font"   cask: "font-caskaydia-cove-nerd-font"   what: "Microsoft's terminal font, ligatures, cursive italics" }
    { name: "SourceCodePro"   asset: "SourceCodePro"   stem: "SauceCodeProNerdFont"    family: "SauceCodePro Nerd Font"    cask: "font-sauce-code-pro-nerd-font"    what: "Adobe's, conservative and quiet" }
    { name: "IosevkaTerm"     asset: "IosevkaTerm"     stem: "IosevkaTermNerdFont"     family: "IosevkaTerm Nerd Font"     cask: "font-iosevka-term-nerd-font"     what: "narrow: more columns per screen, terminal-tuned" }
    { name: "Iosevka"         asset: "Iosevka"         stem: "IosevkaNerdFont"         family: "Iosevka Nerd Font"         cask: "font-iosevka-nerd-font"         what: "the same, at the normal width" }
    { name: "UbuntuMono"      asset: "UbuntuMono"      stem: "UbuntuMonoNerdFont"      family: "UbuntuMono Nerd Font"      cask: "font-ubuntu-mono-nerd-font"      what: "warm and round, tight vertical rhythm" }
    { name: "RobotoMono"      asset: "RobotoMono"      stem: "RobotoMonoNerdFont"      family: "RobotoMono Nerd Font"      cask: "font-roboto-mono-nerd-font"      what: "Google's, neutral, many weights" }
    { name: "Monaspace"       asset: "Monaspace"       stem: "MonaspiceNeNerdFont"     family: "MonaspiceNe Nerd Font"     cask: "font-monaspice-nerd-font"     what: "GitHub's superfamily; Neon is the grotesque one" }
    { name: "Terminus"        asset: "Terminus"        stem: "TerminessNerdFont"       family: "Terminess Nerd Font"       cask: "font-terminess-ttf-nerd-font"       what: "bitmap-derived, crisp at small sizes" }
    { name: "DejaVuSansMono"  asset: "DejaVuSansMono"  stem: "DejaVuSansMNerdFont"     family: "DejaVuSansM Nerd Font"     cask: "font-dejavu-sans-mono-nerd-font"     what: "the Linux default; enormous Unicode coverage" }
    { name: "Inconsolata"     asset: "Inconsolata"     stem: "InconsolataNerdFont"     family: "Inconsolata Nerd Font"     cask: "font-inconsolata-nerd-font"     what: "humanist, a classic" }
    { name: "Noto"            asset: "Noto"            stem: "NotoMonoNerdFont"        family: "NotoMono Nerd Font"        cask: "font-noto-nerd-font"        what: "Google's no-tofu family, monospace cut" }
  ]
}

const NERD_FONTS_RELEASE = "https://github.com/ryanoasis/nerd-fonts/releases/latest/download"

# Where the archives come from: the release, or NERD_FONTS_RELEASE in the
# environment — a mirror's URL, or a directory holding the assets for a
# machine without GitHub (and for the tests, which install from a fixture).
def release-source []: nothing -> string {
  $env.NERD_FONTS_RELEASE? | default $NERD_FONTS_RELEASE
}

# The four faces a terminal needs. Everything else in the archive — Mono, Propo,
# NL, the other weights — is left there, which is why one font is a few MB
# installed out of an archive that can be a few hundred.
const FACES = ["Regular" "Bold" "Italic" "BoldItalic"]

# ── What is installed ─────────────────────────────────────────────────────────

# The face Ghostty would actually use for a family, which is the only test that
# means anything: Ghostty is what has to find the font, and it answers in the
# spelling its own `font-family` key wants.
#
# It has to be `+show-face` and not `+list-fonts`. Verified on macOS 27.2 with
# Ghostty 1.3.1: after installing Inconsolata Nerd Font into ~/Library/Fonts,
# `+list-fonts` still reported only the five system monospace families and never
# mentioned it, while `+show-face --font-family="Inconsolata Nerd Font"` answered
# "found in face Inconsolata Nerd Font". A directory listing is no better — the
# file being there is not the same as CoreText or fontconfig having it.
#
# The catch that makes this work at all: a family Ghostty cannot find does NOT
# fail, it silently falls back to the configured font. So the test is whether
# the face it names is the family we asked for. 26 ms per call.
#
# `font-family` is a repeatable key — a LIST of families, first found wins —
# and Ghostty builds that list as: its default config files, then the command
# line, then the files those include (`config-file`). So a `--font-family=X`
# on the command line lands behind whatever the user's config set, and in
# front of whatever our included file sets — an empty `--font-family=` reset
# clears the user's entry but not ours, and once `font use` has written a
# family every other font read as "not installed". `--config-default-files=
# false` loads no configuration at all, so the answer is about X alone.
# Verified with Ghostty 1.3.1, 2026-09-19: an installed family comes back as
# itself, one that is not as Ghostty's built-in "JetBrains Mono", whatever
# the user's config and ours say.
export def "font face" [family: string]: nothing -> any {
  let g = (ghostty-bin)
  if $g == null { return null }
  ^$g +show-face --config-default-files=false $"--font-family=($family)" --string=A
  | parse -r 'found in face .(?<face>[^“”"]+).'
  | get -o 0.face
}

def installed? [family: string]: nothing -> bool {
  let face = (font face $family)
  $face != null and ($face | str starts-with $family)
}

# The registry, with what is true on this machine. One Ghostty spawn per font,
# in parallel: 15 sequential calls are 400 ms, `par-each` brings that under 100.
#
# `current` is judged by what Ghostty reports it is using, not by what this
# distro wrote: a `font-family` in the user's own config is just as current, and
# the variant they chose ("JetBrainsMono Nerd Font Mono") is the same font.
export def "font list" []: nothing -> table<font: string, installed: bool, current: bool, family: string, what: string> {
  let now = (ghostty live font-family | default "")
  registry | par-each {|f|
    {
      font: $f.name
      installed: (installed? $f.family)
      current: ($now | str starts-with $f.family)
      family: $f.family
      what: $f.what
    }
  } | sort-by {|r| registry | get name | enumerate | where item == $r.font | get 0.index }
}

def font-names []: nothing -> list<string> { registry | get name }

def entry [name: string]: nothing -> record {
  let f = (registry | where name == $name | get -o 0)
  if $f == null { error make { msg: $"no font called '($name)' — `font list`" } }
  $f
}

# ── Installing ────────────────────────────────────────────────────────────────

# Where a user's own fonts go on this platform.
export def "font dir" []: nothing -> path {
  match $nu.os-info.name {
    "macos" => ($nu.home-dir | path join Library Fonts)
    "windows" => ($env.LOCALAPPDATA | path join Microsoft Windows Fonts)
    _ => ($nu.home-dir | path join .local share fonts)
  }
}

# Install one font. Homebrew's cask is preferred on macOS because it is what
# will also upgrade the font later; everywhere else the release archive is
# fetched and exactly four files are taken out of it.
export def "font install" [
  name: string@font-names
  --yes (-y)      # do not ask
  --archive       # skip the package manager and use the release archive
]: nothing -> nothing {
  let f = (entry $name)
  if ((font list | where font == $name | get 0.installed)) {
    print $"($name) is already installed"
    return
  }
  let brew = ($nu.os-info.name == "macos" and (which brew | is-not-empty) and not $archive)
  let how = if $brew { $"brew install --cask ($f.cask)" } else { $"download ($f.asset) from the Nerd Fonts release into (font dir)" }
  if not $yes {
    if not ((is-terminal --stdin) and (is-terminal --stdout)) {
      error make { msg: $"($name) is not installed, and there is no terminal to ask on — `font install ($name) --yes`" }
    }
    if ([$how "no"] | input list $"install ($name)?") != $how { print "left alone"; return }
  }
  if $brew {
    ^brew install --cask $f.cask
  } else {
    install-from-archive $f
  }
  if not (installed? $f.family) {
    print $"(ansi yellow)installed, but Ghostty still resolves '($f.family)' to ((font face $f.family)) — the Nerd Fonts naming may have changed(ansi reset)"
  } else {
    print $"($name) installed — Ghostty renders it as '($f.family)'"
  }
}

# Fetch the release archive and take the four faces out of it.
#
# The archive is extracted whole into a temporary directory and then thinned,
# rather than asking tar for four members by name: the .zip variants run to
# hundreds of MB (Iosevka is 403 MB) and a streaming .tar.xz would have to be
# decompressed twice to do it in two passes. The temporary directory is removed
# either way, including when the download fails.
def install-from-archive [f: record]: nothing -> nothing {
  # .zip on macOS and Windows, whose `tar` is libarchive/bsdtar and reads zip;
  # .tar.xz on Linux, whose GNU tar does not.
  let ext = if $nu.os-info.name == "linux" { "tar.xz" } else { "zip" }
  let source = (release-source)
  let url = $"($source)/($f.asset).($ext)"
  let tmp = (mktemp -d -t nerd-font-XXXXXX)
  let archive = ($tmp | path join $"($f.asset).($ext)")
  try {
    if ($source | str starts-with "http") {
      print $"  downloading ($url)"
      # Streams to disk rather than through a variable: these archives are large.
      http get $url | save -f $archive
    } else {
      print $"  copying ($url)"
      cp $url $archive
    }
    print $"  unpacking ((ls $archive | get 0.size))"
    ^tar -xf $archive -C $tmp
    let dest = (font dir)
    mkdir $dest
    let wanted = ($FACES | each {|face| $"($f.stem)-($face).ttf" })
    # Nerd Fonts archives are flat today, but a glob costs nothing and a
    # subdirectory tomorrow would otherwise look like "naming has changed".
    let found = (glob ($tmp | path join "**" "*.ttf") | where {|p| ($p | path basename) in $wanted })
    if ($found | is-empty) {
      error make { msg: $"($f.asset).($ext) holds no ($f.stem)-*.ttf — the Nerd Fonts naming may have changed" }
    }
    for file in $found { cp $file $dest }
    print $"  installed ($found | length) faces into ($dest)"
    register-fonts $found
  } catch {|e|
    rm -rf $tmp
    error make { msg: $"could not install ($f.name): ($e.msg)" }
  }
  rm -rf $tmp
}

# What each platform needs after the files land. macOS needs nothing: it scans
# ~/Library/Fonts. Linux needs the fontconfig cache rebuilt, and fc-cache is
# not always there. Windows needs a registry value per file, or the font is
# visible only until the next sign-out — this branch is written from the
# documented behaviour and has NOT been run.
def register-fonts [files: list<path>]: nothing -> nothing {
  match $nu.os-info.name {
    "linux" => {
      if (which fc-cache | is-not-empty) { ^fc-cache -f (font dir) } else {
        print "  fontconfig's fc-cache is not installed — the font may not appear until you log in again"
      }
    }
    "windows" => {
      for file in $files {
        let name = ($file | path basename)
        # `\(TrueType\)` escaped: bare parentheses inside an interpolated
        # string are a subexpression, and this one has to be literal text.
        ^reg add 'HKCU\Software\Microsoft\Windows NT\CurrentVersion\Fonts' /v $"($name | str replace --regex '\.ttf$' '') \(TrueType\)" /t REG_SZ /d $name /f
      }
    }
    _ => {}
  }
}

# ── Previewing ────────────────────────────────────────────────────────────────

# The specimen: what a terminal font actually has to get right. The glyphs are
# written as \u escapes rather than pasted, so this file reads the same in an
# editor that has no Nerd Font — which is most of them, before you install one.
#
#   e0a0-e0b3  powerline (Ghostty draws the separators itself, from sprites,
#              so those two are the control: they look right in ANY font)
#   e7xx       devicons     f0xx-f1xx  Font Awesome
def specimen-lines [family: string]: nothing -> list<string> {
  [
    $"  ($family)"
    ""
    "  ABCDEFGHIJKLM abcdefghijklm 0123456789"
    "  the quick brown fox jumps over the lazy dog"
    "  0O o0 1lI i1 !|\u{a6} '\"` {} [] \(\) <> ;:,."
    "  -> => != !== <= >= := |> <|  ... ++ --"
    "  ls | where size > 1mb | get name"
    ""
    $"  nerd font  \u{e0a0} \u{f07b} \u{f121} \u{f09b} \u{f17c} \u{e7a8} \u{e73c} \u{e718} \u{f023} \u{f017}"
    $"  powerline  \u{e0b0}\u{e0b1} \u{e0b2}\u{e0b3}   \(these two are sprites, and look right in any font\)"
  ]
}

# Print the specimen in whatever font this terminal is using. Honest about it:
# unless the font named IS the current one, this shows your font, not that one.
export def "font specimen" []: nothing -> nothing {
  let now = (ghostty settings | get -o font-family | default "your terminal's current font")
  specimen-lines $now | each {|l| print $l }
  print ""
}

# Open a new Ghostty window in this font, showing the specimen. The window is
# yours to close; it is a separate Ghostty instance and touches no config.
export def "font preview" [name: string@font-names]: nothing -> nothing {
  let f = (entry $name)
  let row = (font list | where font == $name | get 0)
  if not $row.installed {
    error make { msg: $"($name) is not installed, and a font cannot be rendered before it exists — `font install ($name)`" }
  }
  let g = (ghostty-bin)
  if $g == null { error make { msg: "ghostty is not installed — `terminal install ghostty`" } }
  let script = (specimen-lines $row.family | each {|l| $"print '($l | str replace --all "'" "''")'" } | str join "; ")
  let argv = [
    $"--font-family=($row.family)"
    "--font-size=14"
    "--window-width=78"
    "--window-height=16"
    "--title=font preview"
    "-e" $nu.current-exe "-n" "-c" $"($script); print ''; input 'press Enter to close '"
  ]
  # On macOS Ghostty refuses to start a window from the CLI — "launching the
  # terminal emulator from the CLI is not supported" — and says to use `open`.
  if $nu.os-info.name == "macos" {
    ^open -na Ghostty.app --args ...$argv
  } else {
    ^$g ...$argv
  }
  print $"opened a Ghostty window in ($row.family) — close it when you have seen enough"
}

# ── Choosing one ──────────────────────────────────────────────────────────────

# Keep a font: Ghostty's config, then `ghostty reload` so every open window
# takes it — on macOS, where the AppleScript reload exists; elsewhere the
# window you are in keeps the font it started with.
export def "font use" [name: string@font-names]: nothing -> nothing {
  let row = (font list | where font == $name | get 0)
  if not $row.installed { font install $name }
  let after = (font list | where font == $name | get 0)
  if not $after.installed { error make { msg: $"($name) is still not installed; nothing was written" } }
  ghostty set { font-family: $after.family }
  print (if (ghostty reload) { $"font is ($after.family) — every open window and new ones" } else { $"font is ($after.family) — new windows will use it; this one keeps the font it started with" })
}

# The picker. Installed fonts are marked, because an uninstalled one costs a
# download before it can be seen, and that is the only real difference between
# the rows.
export def main []: nothing -> nothing {
  if not ((is-terminal --stdin) and (is-terminal --stdout)) {
    error make { msg: "`font` is the interactive picker; `font use <name>` is not" }
  }
  mut picking = true
  while $picking {
    let rows = (font list)
    let pick = (
      $rows
      | input list --fuzzy --display {|r|
          let mark = (if $r.current { "● " } else if $r.installed { "✓ " } else { "  " })
          $"($mark)($r.font | fill --width 16) ($r.what)"
        } "font"
    )
    if $pick == null { print "unchanged"; return }

    if not $pick.installed {
      font install $pick.font
      if not (font list | where font == $pick.font | get 0.installed) { continue }
    }
    let row = (font list | where font == $pick.font | get 0)

    match ([$"keep ($pick.font)" "see it in a new window" "pick another" "leave it as it was"] | input list $"($row.family)") {
      $a if ($a | default "" | str starts-with "keep") => {
        font use $pick.font
        $picking = false
      }
      "see it in a new window" => { font preview $pick.font }
      "pick another" => { }
      _ => { print "unchanged"; $picking = false }
    }
  }
}
