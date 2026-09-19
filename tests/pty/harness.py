#!/usr/bin/env python3
"""A pty for the Tab menu: run nu in a pseudo-terminal, type lines, send
keys one at a time, and report what each line became.

    harness.py --nu /path/to/nu --config-home DIR [--cwd DIR] \
        --case "bits r|tab,tab,enter,enter" --case "ls | where |tab,esc,ctrl-c"

Some completion bugs exist only in reedline — the sourced-menu partial
completion corruption (`bits r` Tab Tab Enter → `bits ror o`) is invisible
to `commandline complete` — and this is the only way to see them without a
person at a keyboard. Python because every CI runner has it and nu has no
pty of its own.

One session runs every case in turn, which is what keeps a run under a few
seconds: each case types its line, sends its keys, and the next case starts
at the next prompt. A case whose keys end in an Enter that RUNS the line is
recorded in history, which is what the `history` list reports, exact where
reading the screen back through starship's prompt is not; a case that only
looks (`tab,esc,ctrl-c`) leaves nothing there and is judged by its
`screen`. Ctrl-D ends the session and records nothing.

Three things the harness taught, kept as its rules: reedline asks the
terminal where the cursor is (ESC[6n) before every prompt and waits for the
answer, so the harness answers or every prompt costs the timeout; keys are
sent one at a time with a quiet wait between them, because Tabs sent in a
burst land while the menu source is still computing and get folded into
one; and the wait is settle-based — until the output has been silent for
`--quiet` seconds — not a fixed sleep, which was flaky against the smart
menu's first-Tab cost (the signature table, 115 ms, more on a runner).
"""
import argparse, fcntl, json, os, pty, select, signal, sqlite3, struct, sys, termios, time

KEYS = {"tab": "\t", "enter": "\r", "esc": "\x1b", "ctrl-c": "\x03", "ctrl-d": "\x04", "space": " ", "backspace": "\x7f"}


def read_until_quiet(fd, quiet, timeout, first=3.0):
    """Everything the child writes until it has been silent for `quiet`
    seconds. Waits up to `first` seconds for the first byte — a Tab whose
    menu is still computing has written nothing yet, and returning then
    would send the next key into the computation — and gives up after
    `timeout` seconds in all."""
    out, start = b"", time.time()
    last = None
    while True:
        now = time.time()
        if last is not None and now - last >= quiet:
            return out
        if last is None and now - start >= first:
            return out
        if now - start >= timeout:
            return out
        r, _, _ = select.select([fd], [], [], quiet if last is not None else 0.05)
        if not r:
            continue
        try:
            chunk = os.read(fd, 65536)
        except OSError:
            return out
        if not chunk:
            return out
        out += chunk
        last = time.time()
        # reedline asks where the cursor is (DSR, ESC[6n) before it draws the
        # prompt and waits for the answer; a pty has no terminal to give one,
        # so the harness does, once per request, or every prompt costs the
        # timeout.
        for _ in range(chunk.count(b"\x1b[6n")):
            os.write(fd, b"\x1b[40;1R")


def run(nu, config_home, cwd, cases, quiet, timeout, env_extra):
    env = dict(os.environ)
    env.update({"XDG_CONFIG_HOME": config_home, "TERM": "xterm-256color", "COLUMNS": "120", "LINES": "40"})
    env.update(env_extra)
    pid, fd = pty.fork()
    if pid == 0:
        os.chdir(cwd)
        os.execvpe(nu, [nu, "-l", "-i"], env)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
    read_until_quiet(fd, quiet, timeout)                       # the first prompt
    screens = []
    for line, keys in cases:
        os.write(fd, line.encode())
        seen = read_until_quiet(fd, quiet, timeout)
        for k in keys:
            os.write(fd, KEYS.get(k, k).encode())
            seen += read_until_quiet(fd, quiet, timeout)
        screens.append(strip_ansi(seen.decode("utf-8", "replace")))
    os.write(fd, KEYS["ctrl-d"].encode())
    read_until_quiet(fd, quiet, timeout)
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    os.waitpid(pid, 0)
    return screens


def history(config_home):
    """Every line reedline recorded, in order, from the sqlite history under
    the config directory (the distro's history.file_format) or the text file."""
    d = os.path.join(config_home, "nushell")
    db = os.path.join(d, "history.sqlite3")
    if os.path.exists(db):
        con = sqlite3.connect(db)
        rows = con.execute("select command_line from history order by id").fetchall()
        con.close()
        return [r[0] for r in rows]
    txt = os.path.join(d, "history.txt")
    if os.path.exists(txt):
        return [l for l in open(txt, encoding="utf-8").read().splitlines() if l.strip()]
    return []


def strip_ansi(s):
    import re
    s = re.sub(r"\x1b\[[0-9;? ]*[A-Za-z@]", "", s)            # CSI, cursor shape (ESC[6 q) included
    s = re.sub(r"\x1b\][^\x07\x1b]*(\x07|\x1b\\)", "", s)      # OSC: titles, cwd, prompt marks
    s = re.sub(r"\x1b[()][A-Za-z0-9]", "", s)                  # charset
    s = re.sub(r"\x1b[78=>]", "", s)                            # DECSC/DECRC, keypad
    return s.replace("\r", "")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--nu", required=True)
    p.add_argument("--config-home", required=True)
    p.add_argument("--cwd", default=os.getcwd())
    p.add_argument("--case", action="append", default=[], help='"<line>|<key>,<key>,..." — keys by name (tab, enter, esc, ctrl-c, ctrl-d, space, backspace) or literal')
    p.add_argument("--quiet", type=float, default=0.2)
    p.add_argument("--timeout", type=float, default=15.0)
    p.add_argument("--env", action="append", default=[], help="NAME=value for the child")
    a = p.parse_args()
    cases = []
    for c in a.case:
        line, _, keys = c.rpartition("|")
        cases.append((line, [k for k in keys.split(",") if k]))
    extra = dict(e.split("=", 1) for e in a.env)
    screens = run(a.nu, a.config_home, a.cwd, cases, a.quiet, a.timeout, extra)
    print(json.dumps({"history": history(a.config_home), "screens": screens}))


if __name__ == "__main__":
    main()
