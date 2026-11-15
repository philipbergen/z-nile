# c0230 prep's mutation check (run from z-nile's home with experiments/prototype.patch applied, through
# `./zn run --time 3000 -- python3 <this> [M-ids]`). Each mutant edits the prototype, runs its row's spec (or the
# one-time proof), and restores the file. KILLED means the run failed (on an assertion, or by the timeout for M26).
import subprocess, sys, shutil
A = '.tracker/issues/c0230/acceptance/'
B = ['lune', 'run', 'tests/run', '--', A + 'budget.spec.luau']
R = ['lune', 'run', 'tests/run', '--', A + 'runner-budget.spec.luau']
P = ['bash', '-c', 'ulimit -t 60; lune run ' + A + 'proof-cpu.luau']
BL = 'tests/lib/budget.luau'
RN = 'tests/run.luau'
M = [
    ('M1 defaults swapped', [(BL, 'budget.DEFAULT = { seconds = 60, cpu = 5 }', 'budget.DEFAULT = { seconds = 5, cpu = 60 }')], B),
    ('M1b cpu default left at 30 s', [(BL, 'budget.DEFAULT = { seconds = 60, cpu = 5 }', 'budget.DEFAULT = { seconds = 60, cpu = 30 }')], B),
    ('M2 one value accepted for both', [(BL, 'local a, b = string.match(value, "^([^:]+):([^:]+)$")', 'local a, b = string.match(value, "^([^:]+):?([^:]*)$"); if b == "" then b = a end')], B),
    ('M3 zero accepted', [(BL, 'if n == nil or n <= 0 then', 'if n == nil or n < 0 then')], B),
    ('M3b empty value is the default', [(BL, '	if value == nil then\n		return budget.DEFAULT, nil', '	if value == nil or value == "" then\n		return budget.DEFAULT, nil')], B),
    ('M4 the line found anywhere', [(BL, '	local text = if string.sub(stdout, -1) == "\\n"', '	local s0, e0, n0 = string.find(stdout, "zn%-spec%-cpu (%d+%.%d+)\\n?")\n	if s0 then\n		return tonumber(n0), string.sub(stdout, 1, s0 - 1) .. string.sub(stdout, e0 + 1)\n	end\n	local text = if string.sub(stdout, -1) == "\\n"')], B),
    ('M5 stdout returned whole', [(BL, 'return tonumber(n), string.sub(text, 1, start - 1)', 'return tonumber(n), stdout')], B),
    ('M26 whole-stdout pattern', [(BL, 'local last = string.match(string.sub(text, -64), "([^\\n]*)$") :: string', 'local _, last = string.match(text, "^(.-)([^\\n]*)$")')], B, 60),
    ('M27 no newline before the line', [(BL, 'if start > 1 and string.sub(text, start - 1, start - 1) ~= "\\n" then', 'if false then')], B),
    ('M6 at-limit is over', [(BL, 'if c.seconds > limits.seconds or (c.cpu ~= nil and (c.cpu :: number) > limits.cpu) then', 'if c.seconds >= limits.seconds or (c.cpu ~= nil and (c.cpu :: number) >= limits.cpu) then')], B),
    ('M7 cpu ignored', [(BL, 'if c.seconds > limits.seconds or (c.cpu ~= nil and (c.cpu :: number) > limits.cpu) then', 'if c.seconds > limits.seconds then')], B),
    ('M8 a file with no cpu skipped', [(BL, 'if c.seconds > limits.seconds or (c.cpu ~= nil and (c.cpu :: number) > limits.cpu) then', 'if c.cpu ~= nil and (c.seconds > limits.seconds or (c.cpu :: number) > limits.cpu) then')], B),
    ('M9 fastest first', [(BL, 'return x.seconds > y.seconds', 'return x.seconds < y.seconds')], B),
    ('M10 ties reversed', [(BL, 'return x.file < y.file', 'return x.file > y.file')], B),
    ('M11 no cap', [(BL, 'for i = 1, math.min(#over, budget.SHOWN) do', 'for i = 1, #over do')], B),
    ('M12 a header for zero files', [(BL, '	if #over == 0 then\n		return nil\n	end\n	local lines', '	local lines')], B),
    ('M13 own CPU only', [(BL, 'my ($cu, $cs) = (times)[2, 3];', 'my ($cu, $cs) = (times)[0, 1];')], R),
    ('M13p own CPU only (proof)', [(BL, 'my ($cu, $cs) = (times)[2, 3];', 'my ($cu, $cs) = (times)[0, 1];')], P),
    ('M20 measurer exits 0', [(BL, '"exit($st & 127 ? 128 + ($st & 127) : $st >> 8);",', '"exit 0;",')], R),
    ('M21 signal as its number', [(BL, '"exit($st & 127 ? 128 + ($st & 127) : $st >> 8);",', '"exit($st & 127 ? ($st & 127) : $st >> 8);",')], R),
    ('M14 workers without the measurer', [(RN, 'local command, args = "perl", { "-e", budget.MEASURE, "lune" }', 'local command, args = "lune", {}')], R),
    ('M23 the wall as the cpu', [(RN, 'cpu = o.cpu })', 'cpu = if o.cpu ~= nil then o.seconds else nil })')], R),
    ('M24 costs built without cpu', [(RN, 'cpu = o.cpu })', 'cpu = nil })')], R),
    ('M25 the coordinator clock as the wall', [(RN, '			o.seconds = own\n', '			local _ = own\n')], R),
    ('M25p the coordinator clock as the wall (proof)', [(RN, '			o.seconds = own\n', '			local _ = own\n')], P),
    ('M15 over budget counts as a failure', [(RN, '		print(overBudget)\n', '		print(overBudget)\n		failed += 1\n')], R),
    ('M16 printed after the summary', [(RN, '	if overBudget then\n		print(overBudget)\n	end\n	print(`{passed} passed', '	print(`{passed} passed, {failed} failed, {#files} spec files`)\n	if overBudget then\n		print(overBudget)\n	end\n	print(`')], R),
    ('M17 no early refusal', [(RN, '			if budgetError then', '			if false then')], R),
    ('M28 a missing value is the default', [(RN, 'local _, budgetError = budget.limits(process.args[i + 1] or "")', 'local _, budgetError = budget.limits(process.args[i + 1])')], R),
    ('M18 in-process prints a report', [(RN, 'print(string.format("seconds %.3f", results[1].seconds))\nend', 'print(string.format("seconds %.3f", results[1].seconds))\nend\nif not reportSeconds then local l = (budget.limits(budgetValue)) :: budget.Limits; local o = budget.render(budget.over({ { file = results[1] and results[1].file or "", seconds = 1 } }, l), l); if o then print(o) end end')], R),
    ('M19 exit 0 when over budget', [(RN, '	process.exit(if failed == 0 then 0 else 1)\nend', '	process.exit(if failed == 0 or overBudget then 0 else 1)\nend')], R),
    ('M22 the budget reaches nested runs through the environment', [(RN, '					ZN_MEASURED = "1",\n', '					ZN_MEASURED = "1",\n					ZN_SPEC_BUDGET = budgetValue,\n'), (RN, 'local limits = (budget.limits(budgetValue)) :: budget.Limits', 'local limits = (budget.limits(budgetValue or process.env.ZN_SPEC_BUDGET)) :: budget.Limits')], R),
]
sel = sys.argv[1:]
for entry in M:
    name, edits, cmd = entry[0], entry[1], entry[2]
    limit = entry[3] if len(entry) > 3 else 600
    if sel and name.split()[0] not in sel:
        continue
    saved = {}
    ok = True
    for f, old, new in edits:
        src = saved.get(f) or open(f).read()
        cur = open(f).read()
        if f not in saved:
            saved[f] = cur
        if cur.count(old) != 1:
            print(name, 'NOT APPLIED (count', cur.count(old), ')')
            ok = False
            break
        open(f, 'w').write(cur.replace(old, new))
    try:
        if ok:
            try:
                r = subprocess.run(cmd, capture_output=True, text=True, timeout=limit)
                out = r.stdout + r.stderr
                fails = [l for l in out.splitlines() if l.startswith('FAIL') or 'could not load' in l]
                print(name, '->', 'KILLED' if r.returncode != 0 else 'SURVIVED', '|', ' / '.join(fails[:2])[:300])
            except subprocess.TimeoutExpired:
                print(name, '-> KILLED (did not finish in', limit, 's)')
    finally:
        for f, src in saved.items():
            open(f, 'w').write(src)
