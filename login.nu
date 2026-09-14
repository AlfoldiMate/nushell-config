# login.nu — runs only when Nushell is the login shell (`nu -l`)
#
# A login shell is responsible for the environment every GUI app and subshell
# inherits, the job /etc/profile and ~/.zprofile do for POSIX shells. Nushell
# cannot read those files, so anything they export must be re-expressed here.
#
# Nothing is needed while the login shell is zsh/bash. To make nu the login
# shell: add its path to /etc/shells, then `chsh -s (which nu | get 0.path)`.
#
# Capture what the current login shell exports, from inside that shell:
#   nu -c '$env | reject config | transpose k v | each {|r| $"$env.($r.k) = \"($r.v)\"" } | str join (char nl)'
# and copy the lines you actually need below.
