#!/usr/bin/env python3
"""c0316 mutation check for acceptance/escapes.spec.luau.

usage: ./zn run --time 1500 -- python3 mutants.py <worktree path>

In a fresh clone under the system temp folder it applies prototype.patch, copies the spec in, runs the baseline, then
applies M1..M14 one at a time (one text replacement in z-nile/engine/lessons.luau, the old text found exactly once),
runs the spec and records the mutant killed when a case fails on an ASSERTION (a t.expect message, "expected ...").
A load error or a runtime error alone is not a kill. Prints one line per mutant and `killed N of 14`.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

SPEC = "z-nile/.tracker/issues/c0316/acceptance/escapes.spec.luau"
PATCH = "z-nile/.tracker/issues/c0316/experiments/prototype.patch"
LESSONS = "z-nile/engine/lessons.luau"

T = "\t"
UNCOVERED_OLD = (
    T * 2 + "for _, stem in stems(item) do\n"
    + T * 3 + "for _, f in sortedFindings(item.reviews[stem]) do\n"
    + T * 4 + "if not named[`{stem} {f}`] then\n"
    + T * 5 + "table.insert(out, `{item.id} {stem} {f}`)\n"
    + T * 4 + "end\n"
    + T * 3 + "end\n"
    + T * 2 + "end\n"
    + T * 2 + "for _, e in lessons.escapes(item) do\n"
    + T * 3 + "if e.kind ~= \"finding\" and not named[`escape {e.ref}`] then\n"
    + T * 4 + "table.insert(out, `{item.id} escape {e.ref}`)\n"
    + T * 3 + "end\n"
    + T * 2 + "end\n"
)
UNCOVERED_NEW = (
    T * 2 + "for _, e in lessons.escapes(item) do\n"
    + T * 3 + "if e.kind ~= \"finding\" and not named[`escape {e.ref}`] then\n"
    + T * 4 + "table.insert(out, `{item.id} escape {e.ref}`)\n"
    + T * 3 + "end\n"
    + T * 2 + "end\n"
    + T * 2 + "for _, stem in stems(item) do\n"
    + T * 3 + "for _, f in sortedFindings(item.reviews[stem]) do\n"
    + T * 4 + "if not named[`{stem} {f}`] then\n"
    + T * 5 + "table.insert(out, `{item.id} {stem} {f}`)\n"
    + T * 4 + "end\n"
    + T * 3 + "end\n"
    + T * 2 + "end\n"
)

# (id, case prefix the row names, old text, new text)
MUTANTS = [
    ("M1", "AC2: an escape entry parses", "if not ESCAPE_KINDS[ekind] then", "if false then"),
    ("M2", "AC2: an escape entry parses", "elseif not stage then", "elseif false then"),
    (
        "M3",
        "AC2: an escape entry parses",
        T * 3 + "if seen[key] then\n" + T * 4 + "table.insert(problems, `{item}/harvest.md: {key}: a second entry for the same escape`)",
        T * 3 + "if false then\n" + T * 4 + "table.insert(problems, `{item}/harvest.md: {key}: a second entry for the same escape`)",
    ),
    ("M4", "AC2: a finding's stage is read", "inBlock = head == finding", "inBlock = inBlock or head == finding"),
    ("M5", "AC2: a design-review finding marked idea", "if stage and RANK[stage] < RANK[own] then", "if stage then"),
    (
        "M6",
        "AC2: a design-review finding marked idea",
        'return if string.sub(stem, 1, 14) == "design-review-" then "design" else "implementation"',
        'return "design"',
    ),
    ("M7", "AC3: uncovered lists a second approval", "for n = 2, item.approvals or 0 do", "for n = 1, item.approvals or 0 do"),
    (
        "M8",
        "AC3: uncovered lists a second approval",
        "not named[`escape {e.ref}`] then",
        "not (named[`escape {e.ref}`] or named[`escape {e.kind} 2`]) then",
    ),
    (
        "M9",
        "AC3: uncovered lists a second approval",
        "for n = 1, item.stops or 0 do",
        "for n = math.max(1, item.stops or 0), item.stops or 0 do",
    ),
    # the row names the "prints exactly what it printed before" case; that case has no escape to order, so the
    # ordering is asserted in the "lists a second approval" case (see the report)
    ("M10", "AC3: uncovered lists a second approval", UNCOVERED_OLD, UNCOVERED_NEW),
    ("M11", "AC4: unstaged names every finding", "if exempt[stem] then", "if next(exempt) ~= nil then"),
    (
        "M12",
        "AC4: unstaged names every finding",
        T * 2 + 'return "implementation"\n' + T + "end\n" + T + "return nil\nend",
        T * 2 + 'return "implementation"\n' + T + "end\n" + T + "return word :: any\nend",
    ),
    (
        "M13",
        "AC2: check refuses an escape entry",
        'elseif esc.kind == "stop" and esc.n > (item.stops or 0) then',
        'elseif esc.kind == "stop" and false then',
    ),
    (
        "M14",
        "AC7: escapeCounts puts each escape",
        'ref = "rework 1", made = made["rework 1"], found = "merged" }',
        'ref = "rework 1", made = made["rework 1"], found = "implementation" }',
    ),
]


def run(cmd, cwd, timeout=300):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)


def spec_result(clone):
    """(passed, failures) where failures is a list of (case name, first message line)."""
    home = os.path.join(clone, "z-nile")
    spec = os.path.join(clone, SPEC)
    p = run(["lune", "run", "tests/run", "--", spec], home)
    lines = (p.stdout + p.stderr).splitlines()
    fails = []
    for i, line in enumerate(lines):
        if line.startswith("FAIL ") and " :: " in line:
            msg = lines[i + 1].strip() if i + 1 < len(lines) else ""
            fails.append((line.split(" :: ", 1)[1], msg))
        elif line.startswith("FAIL "):
            fails.append(("(load) " + line, line))
    return p.returncode == 0, fails, p.stdout + p.stderr


def is_assertion(msg):
    return re.search(r":\d+: expected ", msg) is not None


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: mutants.py <worktree path>")
    worktree = os.path.realpath(sys.argv[1])
    tmp = os.path.realpath(tempfile.mkdtemp(prefix="c0316-mut-"))
    if tmp == worktree or tmp.startswith(worktree + os.sep):
        shutil.rmtree(tmp, ignore_errors=True)
        sys.exit("refusing: the temp folder is inside the worktree")
    clone = os.path.join(tmp, "clone")
    try:
        subprocess.run(["git", "clone", "-q", "--no-hardlinks", worktree, clone], check=True)
        subprocess.run(["git", "-C", clone, "remote", "remove", "origin"], check=True)
        subprocess.run(["git", "-C", clone, "apply", os.path.join(worktree, PATCH)], check=True)
        dest = os.path.join(clone, SPEC)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        shutil.copy(os.path.join(worktree, SPEC), dest)
        passed, fails, out = spec_result(clone)
        print("baseline:", "pass" if passed else "FAIL")
        if not passed:
            print(out)
            sys.exit(1)
        path = os.path.join(clone, LESSONS)
        original = open(path).read()
        killed = 0
        for mid, case, old, new in MUTANTS:
            n = original.count(old)
            if n != 1:
                print(f"{mid}: BAD MUTANT: old text occurs {n} times")
                continue
            open(path, "w").write(original.replace(old, new))
            try:
                ok, fails, out = spec_result(clone)
            finally:
                open(path, "w").write(original)
            hits = [f for f in fails if is_assertion(f[1])]
            if hits:
                killed += 1
                names = sorted({h[0].split(":")[0] for h in hits})
                row = "row case" if any(h[0].startswith(case) for h in hits) else "OTHER case only"
                print(f"{mid}: killed ({row}) by {', '.join(names)}")
            elif fails:
                print(f"{mid}: SURVIVED (failed without an assertion: {fails[0][1][:100]})")
            else:
                print(f"{mid}: SURVIVED")
        print(f"killed {killed} of {len(MUTANTS)}")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


main()
