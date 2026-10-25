#!/usr/bin/env python3
# R0045 prep mutation check. Usage: python3 mutants.py <tree with narrowing.patch applied>
# Each mutant weakens a narrowed case the way a careless narrowing could; one of c0128's specs (titles, guards, golden)
# must fail on an assertion.
import subprocess, sys, pathlib
root = pathlib.Path(sys.argv[1])
A = 'tests/acceptance/f0024/adapter.spec.luau'
B = 'tests/acceptance/f0026/adapters.spec.luau'
MUTANTS = [
  ('drop-a-per-player-store', A, '\t\t\t"Hiscores|all",\n\t\t\t"Hiscores|day:2026-10-16",', '\t\t\t"Hiscores|day:2026-10-16",'),
  ('count-any-updates', A, 't.expect(updates).toBe(6)', 't.expect(updates >= 6).toBe(true)'),
  ('drop-whole-answer-compare', B, 't.expect(four(w.answers(p1))[3]).toEqual({ "all", healthy[2], 2, true } :: { any })', ''),
  ('opens-any-companion', B, '''t.expect(open == "companion|HiscoreEntries|all" or open == "companion|HiscoreTop|all")
						.toBe(true)''', 't.expect(true).toBe(true)'),
  ('page50-no-floor', B, 't.expect(rowReads > 0 and rowReads <= Hiscores.N).toBe(true)', 't.expect(rowReads <= Hiscores.N).toBe(true)'),
  ('rename-a-case', B, '"a healthy empty board is an answer, not a failure"', '"a healthy empty board answers"'),
  ('top-skips-budget-check', A, '''				if string.sub(entry, 1, #"update:ordered") == "update:ordered" then''', '''				if string.sub(entry, -#":HiscoreTop") == ":HiscoreTop" then
					-- skipped
				elseif string.sub(entry, 1, #"update:ordered") == "update:ordered" then'''),
  ('opens-drop-entries-required', B, '''			t.expect(table.find(w.opens, "companion|HiscoreEntries|all") ~= nil).toBe(true)''', ''),
  ('stores-no-count', A, '''		t.expect(#names).toBe(if table.find(names, "HiscoreTop|all") then 7 else 6)''', ''),
  ('unnarrowed-case-loses-assert', B, '''		t.expect(#w.reads).toBe(0)
''', '''
'''),
  ('comment-edit', A, '-- c0128: the six per-player stores', '-- c0128: the per-player stores'),
]
specs = [str(root / 'tracker/issues/c0128/acceptance' / f) for f in ('titles.spec.luau', 'guards.spec.luau', 'golden.spec.luau')]
bad = []
for name, rel, old, new in MUTANTS:
    path = root / rel
    src = path.read_text()
    if src.count(old) != 1:
        bad.append(f'{name}: anchor found {src.count(old)} times'); continue
    path.write_text(src.replace(old, new))
    try:
        out = subprocess.run(['lune', 'run', 'tests/run', '--'] + specs, cwd=root, capture_output=True, text=True).stdout
    finally:
        path.write_text(src)
    fails = [l for l in out.splitlines() if l.startswith('FAIL ')]
    if not fails or any('could not load' in l for l in fails):
        bad.append(f'{name}: {"survived" if not fails else "load error"}')
    else:
        print(f'killed {name}: {fails[0].split(" :: ", 1)[-1]}')
print('\n'.join(bad) if bad else f'ALL {len(MUTANTS)} MUTANTS KILLED ON ASSERTIONS')
sys.exit(1 if bad else 0)
