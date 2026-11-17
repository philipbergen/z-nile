#!/usr/bin/env python3
# R0045 prep mutation check. Usage: python3 mutants.py <the pickman home of a separate clone, narrowing applied>
#   e.g. python3 mutants.py "$TMPDIR/x/clone/pickman"; python3 mutants.py --joins prints the join entries as JSON.
# Each mutant weakens a narrowed case the way a careless narrowing could; one of c0128's specs (titles, guards, golden,
# and c0103's narrowed) must fail on an assertion. c0156: the specs are the promoted ones; the join entries put a line
# onto the comment above it in each pinned file; the run refuses anything but a separate clone under the temp folder
# (it edits and restores files there), sets the guard's real-repository variable, times a run out at 120 s and kills
# its process group.
import json, os, pathlib, signal, subprocess, sys, tempfile
A = 'tests/acceptance/f0024/adapter.spec.luau'
B = 'tests/acceptance/f0026/adapters.spec.luau'
K = 'tests/acceptance/f0014/keys.spec.luau'
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
  # c0156: a line joined onto the comment line above it (a Luau comment ends at the line), one per pinned file
  ('join-f0024-comment', A, "only d0124's top-N list of runs\n", "only d0124's top-N list of runs "),
  ('join-f0026-reads-comment', B, 'each at page sizes 10 and 50\n', 'each at page sizes 10 and 50 '),
  ('join-f0026-companion-comment', B, '-- c0128: the per-player companion store is still read\n', '-- c0128: the per-player companion store is still read '),
  ('join-f0014-comment', K, 'can be added without a red main.\nlocal Movement', 'can be added without a red main. local Movement'),
]
specs = ['tests/acceptance/c0128/' + f for f in ('titles.spec.luau', 'guards.spec.luau', 'golden.spec.luau')] + ['tests/acceptance/c0103/narrowed.spec.luau']
if sys.argv[1:] == ['--joins']:
    print(json.dumps([{'name': n, 'path': r, 'old': o, 'new': w} for n, r, o, w in MUTANTS if n.startswith('join-')]))
    sys.exit(0)
if len(sys.argv) != 2:
    sys.exit('usage: mutants.py <pickman home of a separate clone under the temp folder> | --joins')
root = pathlib.Path(sys.argv[1]).resolve()
tmp = pathlib.Path(tempfile.gettempdir()).resolve()
clone = root.parent
if root.name != 'pickman' or tmp not in clone.parents or not (clone / '.git').is_dir() or (clone / '.worktree').exists():
    sys.exit(f'{root}: not the pickman home of a separate clone under {tmp}')
env = dict(os.environ)
here = pathlib.Path(__file__).resolve().parent
real = subprocess.run(['git', '-C', str(here), 'rev-parse', '--path-format=absolute', '--git-common-dir'],
                      capture_output=True, text=True, check=True).stdout.strip()
env['PICKMAN_FENCE_REAL_GIT'] = (env['PICKMAN_FENCE_REAL_GIT'] + ':' if env.get('PICKMAN_FENCE_REAL_GIT') else '') + real
def run():
    p = subprocess.Popen(['lune', 'run', 'tests/run', '--'] + specs, cwd=root, env=env, stdout=subprocess.PIPE,
                         stderr=subprocess.STDOUT, text=True, start_new_session=True)
    try:
        return p.communicate(timeout=120)[0]
    except subprocess.TimeoutExpired:
        os.killpg(p.pid, signal.SIGKILL)
        return p.communicate()[0] + '\nTIMEOUT'
bad = []
for name, rel, old, new in MUTANTS:
    path = root / rel
    src = path.read_text()
    if src.count(old) != 1:
        bad.append(f'{name}: anchor found {src.count(old)} times'); continue
    path.write_text(src.replace(old, new))
    try:
        out = run()
    finally:
        path.write_text(src)
    fails = [l for l in out.splitlines() if l.startswith('FAIL ')]
    if 'TIMEOUT' in out:
        bad.append(f'{name}: timed out')
    elif not fails or any('could not load' in l for l in fails):
        bad.append(f'{name}: {"survived" if not fails else "load error"}')
    else:
        print(f'killed {name}: {fails[0].split(" :: ", 1)[-1]}')
print('\n'.join(bad) if bad else f'ALL {len(MUTANTS)} MUTANTS KILLED ON ASSERTIONS')
sys.exit(1 if bad else 0)
