#!/usr/bin/env python3
"""c0258 prep's mutation check: with prototype.patch applied, apply each mutant to the prototype, run the row's spec,
and record whether it fails on an assertion (killed) or not. Every file is restored in a `finally`.
Run from the checkout's top, bounded: ./zn run --time 2400 -- python3 -I <this> <out-file>"""
import os, subprocess, sys

TOP = os.getcwd()
A = ".tracker/issues/c0258/acceptance"
M = "z-nile/engine/main.luau"
L = "z-nile/engine/landrace.luau"
U = "z-nile/engine/usage.luau"

# id, file, old, new, spec (in z-nile/), what it is
MUTANTS = [
    ("M0", None, None, None, "retries", "baseline: the retries spec on the prototype passes"),
    ("M1", U, 'return opts["-h"] ~= nil or opts["--help"] ~= nil', 'return opts["-h"] ~= nil', "usage", "--help is not help"),
    ("M2", U, "inside = word == name", "inside = string.sub(word, 1, #name) == name", "usage", "a command matches a prefix"),
    ("M3", M, "if usageLib.wantsHelp(opts) then", "if false then", "help", "help after a command never prints"),
    ("M4", "zn", "[[ $arg == --check || $arg == -h || $arg == --help ]]", "[[ $arg == --check ]]", "help", "approve --help refused"),
    ("M5", "z-nile/lib/bounded.pl", "if ( $o eq '-h' || $o eq '--help' ) {", "if ( 0 ) {", "help", "run --help is not the runner's"),
    ("M6", M, "if usageLib.wantsHelp(opts) then", 'if table.find(rest, "-h") or table.find(rest, "--help") then', "help", "a value -h is help"),
    ("M7", L, "if f.trackerWhy then", "if false then", "landrace", "a code move pushes with no gate"),
    ("M8", L, "if #f.touched > 0 then", "if false then", "landrace", "a move of a capture file pushes with no gate"),
    ("M9", L, 'return "again", nil', 'return "regate", "always"', "landrace", "every race regates"),
    ("M10", M, 'if step == "regate" then', "if false then", "race", "the command never regates (main's behaviour)"),
    ("M11", M, "\t\tunfold()\n\t\tif step == \"no-answer\" then", "\t\tif step == \"no-answer\" then", "race", "no unfold before the merge"),
    ("M12", M, "\t\tfold()\n\t\tparent = now", "\t\tparent = now", "race", "the row is not folded again after a race"),
    ("M13", L, "if f.pushed or f.contains then", "if f.pushed then", "landrace", "a lying push is not landed"),
    ("M14", L, 'return if own > 0 then "already" else "nothing"', 'return "nothing"', "landrace", "already landed is nothing to land"),
    ("M15", L, "landrace.TRIES = 10", "landrace.TRIES = 3", "landrace", "three tries"),
    ("M16", M, "for attempt = 1, landrace.TRIES do", "for attempt = 1, landrace.TRIES - 1 do", "retries", "one push fewer than TRIES"),
    ("M17", M, "\t\tunfold()\n\t\tif step == \"no-answer\" then", "\t\tif step ~= \"give-up\" then\n\t\t\tunfold()\n\t\tend\n\t\tif step == \"no-answer\" then", "retries", "giving up leaves the fold staged"),
    ("M18", M, "\t\t\tgated = now\n", "\t\t\tgated = gated\n", "race", "after a regate races are judged from the first gate"),
    ("M19", M, "\t\tif start == \"already\" then\n\t\t\treturn true", "\t\tif false then\n\t\t\treturn true", "landed", "the command says nothing to land for a landed branch"),
    ("M20", M, "print(usageLib.of(USAGE, name :: string) or USAGE)", "print(USAGE)", "help", "a command's help is the whole usage"),
    ("M21", M, "facts.contains = facts.moved and sh.run(", "facts.contains = false and sh.run(", "landed", "the command ignores a push that landed"),
    ("M22", M, 'if name == "-h" or name == "--help" then', "if false then", "help", "./zn -h is an unknown command"),
    # design review 001's revision
    ("M25", M, '{ "log", "--no-merges", "--format=", "--name-only", `{base}..HEAD` }', '{ "diff", "--name-only", sh.git({ "merge-base", "HEAD", base }), "HEAD" }', "landed", "own is the diff from the merge base (F2)"),
    ("M26", M, "\t\tif take(now) then\n\t\t\talready(now)\n\t\t\treturn\n\t\tend\n\t\tif step == \"regate\" then\n\t\t\tprint(`{why}: running the gate again`)\n\t\t\trunGate()\n\t\t\tgated = now\n\t\tend\n",
     "\t\tif step == \"regate\" then\n\t\t\tprint(`{why}: running the gate again`)\n\t\t\trunGate()\n\t\t\tgated = now\n\t\tend\n\t\tif take(now) then\n\t\t\talready(now)\n\t\t\treturn\n\t\tend\n", "race", "the regate gates the unmerged tree (F6 A)"),
    ("M27", M, "\t\tif take(now) then\n\t\t\talready(now)\n\t\t\treturn\n\t\tend\n", "\t\ttake(now)\n", "race", "a mid-loop already landed is ignored (F6 B)"),
    ("M28", L, "if not f.answered then", "if false then", "landrace", "a broker with no answer is retried (F8)"),
    ("M29", M, " (last push: {last})", "", "retries", "giving up drops the last push's output (F8)"),
]


def run(spec):
    r = subprocess.run(
        ["lune", "run", "tests/run", "--", f"{A}/{spec}.spec.luau"],
        cwd=os.path.join(TOP, "z-nile"),
        capture_output=True,
        text=True,
    )
    return r.returncode, r.stdout + r.stderr


def verdict(code, out):
    if code == 0:
        return "survived"
    fails = [l for l in out.splitlines() if l.startswith("FAIL ") and "::" in l]
    if not fails:
        return "error (no case failed: " + (out.strip().splitlines() or ["?"])[-1][:120] + ")"
    bad = ("syntax", "attempt to call", "attempt to index", "module not found", "TypeError")
    if any(b in out for b in bad) and "expected" not in out:
        return "error (not an assertion)"
    return "killed by " + "; ".join(f.split("::", 1)[1].strip()[:90] for f in fails[:3])


def main():
    out_path = sys.argv[1]
    only = set(sys.argv[2:])
    with open(out_path, "w") as log:
        for mid, path, old, new, spec, what in MUTANTS:
            if only and mid not in only:
                continue
            original = None
            try:
                if path:
                    with open(path) as f:
                        original = f.read()
                    if original.count(old) != 1:
                        log.write(f"{mid}\t{spec}\tnot applied: the old text is not there once\t{what}\n")
                        log.flush()
                        continue
                    with open(path, "w") as f:
                        f.write(original.replace(old, new))
                code, out = run(spec)
                v = verdict(code, out) if path else ("passes" if code == 0 else "FAILS: " + out[-400:])
                log.write(f"{mid}\t{spec}\t{v}\t{what}\n")
                log.flush()
            finally:
                if path and original is not None:
                    with open(path, "w") as f:
                        f.write(original)


main()
