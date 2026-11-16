#!/usr/bin/env python3
"""c0322 mutation check. Run from the top of a throwaway clone under $TMPDIR with experiments/prototype.patch applied, through
`./zn run --time 300 -- python3 <this file>`: for each
mutant, edit the engine, run the fast spec, expect a failed assertion in the named case, put the engine back.
Not run by any check."""
import os, subprocess, sys

# It rewrites engine files in place, so it runs only in a throwaway clone: the repository must lie under $TMPDIR.
_top = os.path.realpath(subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True).stdout.strip())
_tmp = os.path.realpath(os.environ.get("TMPDIR") or "/tmp")
if not _top.startswith(_tmp.rstrip("/") + "/") or os.path.realpath(os.getcwd()) != _top:
    sys.exit(f"mutants.py: run it from the top of a throwaway clone under $TMPDIR ({_tmp}), not {_top}")

LED = "z-nile/engine/ledger.luau"
MAIN = "z-nile/engine/main.luau"
DIR = ".tracker/issues/c0322/acceptance/"
if not os.path.isdir("z-nile/" + DIR):
    DIR = "tests/acceptance/c0322/"  # after ./zn done promoted it

SUBJECT = 'local subject = string.match(message, "^[^\\n]*") or message'
CALL = '\t\treading,\n\t\tif reading then sessionread.flags(reading) else ""\n'
MUTANTS = [
    ("M1 the note-bearing message is the subject (no first line)", LED, SUBJECT, 'local subject = message',
     "every row's subject is the commit's first line"),
    ("M2 every row gets the reading", LED, 'local mine = if i == 1 then reading else nil', 'local mine = reading',
     "the reading goes on the first row only"),
    ("M3 no row gets the reading", LED, 'local mine = if i == 1 then reading else nil', 'local mine = nil :: Reading?',
     "the reading goes on the first row only"),
    ("M4 the reading's tokens are dropped", LED, 'tokens = if mine then mine.tokens else nil,', 'tokens = nil,',
     "the reading goes on the first row only"),
    ("M5 the reading's AI seconds are dropped", LED, 'ai = if mine then mine.ai else nil,', 'ai = nil,',
     "the reading goes on the first row only"),
    ("M6 the reading's model beats a named one", LED, 'model = model or (if mine then mine.model else nil),',
     'model = (if mine then mine.model else nil) or model,', "a model the caller names wins"),
    ("M7 a bare row takes the reading's flags", LED, 'unmeasured = if mine then readingFlags else "tokens,wall,cpu,ai",',
     'unmeasured = if reading then readingFlags else "tokens,wall,cpu,ai",', "the reading goes on the first row only"),
    ("M8 no Session trailer", LED, '\tif note ~= nil and note ~= "" then\n', '\tif false then\n',
     "the trailers are one Issue line per row"),
    ("M9 an empty note still writes a Session line", LED, 'if note ~= nil and note ~= "" then', 'if note ~= nil then',
     "the trailers are one Issue line per row"),
    ("M10 the Session line comes first", LED, '\t\ttable.insert(lines, `Session: {note}`)', '\t\ttable.insert(lines, 1, `Session: {note}`)',
     "the trailers are one Issue line per row"),
    ("M11 the CLI folds the note into the message it hands the builder (review X1)", MAIN, '\tlocal rows = ledger.commitRows(\n\t\tmessage,',
     '\tlocal rows = ledger.commitRows(\n\t\tif reading then message .. " " .. reading.note else message,',
     "one call builds the rows, from the commit's own message"),
    ("M12 the CLI hands the builder no reading (review X3)", MAIN, CALL, '\t\tnil,\n\t\tif reading then sessionread.flags(reading) else ""\n',
     "one call builds the rows, from the commit's own message"),
    ("M13 the CLI adds the note to a row after the call", MAIN, '\t\ttable.insert(list, rows[i])\n',
     '\t\tif reading and i == 1 then\n\t\t\trows[i].subject ..= " " .. reading.note\n\t\tend\n\t\ttable.insert(list, rows[i])\n',
     "one call builds the rows, from the commit's own message"),
    ("M14 the CLI no longer prints the note", MAIN, '\tif reading then\n\t\tprint(`session: {reading.note}`)\n\tend\n', '',
     "the note is printed and handed to the trailers"),
    ("M15 the CLI hands the trailers no note", MAIN, 'kept, rows, if reading then reading.note else nil)', 'kept, rows, nil)',
     "the note is printed and handed to the trailers"),
]
bad = 0
for name, path, old, new, case in MUTANTS:
    text = open(path).read()
    if text.count(old) != 1:
        print(f"{name}: CANNOT APPLY ({text.count(old)} matches)"); bad += 1; continue
    open(path, "w").write(text.replace(old, new, 1))
    try:
        r = subprocess.run(["lune", "run", "tests/run", "--", DIR + "bind-subject.spec.luau", DIR + "wiring.spec.luau"], cwd="z-nile", capture_output=True, text=True)
    finally:
        open(path, "w").write(text)
    out = r.stdout + r.stderr
    failed = [l for l in out.splitlines() if l.startswith("FAIL ") and " :: " in l]
    hit = any(case in l for l in failed)
    verdict = "killed" if r.returncode != 0 and hit else "SURVIVED"
    bad += verdict != "killed"
    print(f"{name}: {verdict} ({'; '.join(l.split(' :: ', 1)[1][:60] for l in failed)})")
sys.exit(1 if bad else 0)
