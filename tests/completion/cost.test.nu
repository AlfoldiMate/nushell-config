# The costs docs/concepts/completion.md claims, as upper bounds a regression
# would cross: each bound is ten to twenty times what was measured on an
# M-series Mac on 2026-09-19 (in the comments), because CI runners are slower
# and a test that fails on noise is worse than none. The minimum of a few
# runs is taken, the way the documented numbers were.
use lib.nu *
use std/assert
use nu-complete *

def fastest [runs: int, code: closure]: nothing -> duration {
  1..$runs | each {|_| timeit $code } | math min
}

def "test spans rebuilds a long line within its budget" [] {
  # 26 tokens: 0.24 ms.
  let line = 'git commit -m "a b" --author=x ' + (1..20 | each {|i| $"word($i)" } | str join " ")
  let place = { target: { start: ($line | str length) } }
  let took = fastest 5 { nu-complete spans { text: "" } $place $line }
  assert ($took < 5ms) $"spans took ($took)"
}

def "test quote scans two thousand plain values within its budget" [] {
  # 0.5 ms: one regex over the joined values, no closure per item.
  let plain = 1..2000 | each {|i| { value: $"formula-($i)" } }
  let took = fastest 5 { $plain | nu-complete quote }
  assert ($took < 10ms) $"quote took ($took)"
}

def "test quote rewrites two thousand values with spaces within its budget" [] {
  # 38 ms: a closure per item once one needs quoting.
  let spaced = 1..2000 | each {|i| { value: $"formula ($i)" } }
  let took = fastest 3 { $spaced | nu-complete quote }
  assert ($took < 400ms) $"quote took ($took)"
}

def "test filter narrows two thousand values within its budget" [] {
  # prefix 9.7 ms, fuzzy 8.3 ms.
  let items = 1..2000 | each {|i| { value: $"formula-($i)" } }
  $env.config.completions.algorithm = "prefix"
  let prefix = fastest 3 { $items | nu-complete filter "formula-19" }
  assert ($prefix < 100ms) $"prefix filter took ($prefix)"
  $env.config.completions.algorithm = "fuzzy"
  let fuzzy = fastest 3 { $items | nu-complete filter "f19" }
  assert ($fuzzy < 100ms) $"fuzzy filter took ($fuzzy)"
}

def "test the smart menu answers from its signature table within its budget" [] {
  # The first call builds the table (140 ms); after that `ps ` is 1.4 ms and
  # `ls | where ` 2.7 ms from the memoised probe.
  nu-complete smart "ps " 3 | ignore
  nu-complete smart "ls | where " 11 | ignore
  let ps = fastest 5 { nu-complete smart "ps " 3 }
  assert ($ps < 30ms) $"ps took ($ps)"
  let cols = fastest 5 { nu-complete smart "ls | where " 11 }
  assert ($cols < 50ms) $"ls | where took ($cols)"
}
