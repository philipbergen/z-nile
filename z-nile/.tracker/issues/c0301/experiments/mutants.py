#!/usr/bin/env python3
# c0301 prep mutation check: apply each mutant to the scratch prototype, run its spec, restore.
# A record of what prep ran (Unknowns E6). The prototype is a standalone clone under /tmp (prototype.patch applied on
# ed6943a6, the c0301 specs copied to z-nile/tests/acceptance/c0301), named by /tmp/c0301-proto-path; the script refuses
# any other place, edits only files and puts each back with `git checkout -- <file>`, and moves no ref.
# Each spec runs as `./zn run --time 600 -- experiments/run-plain.sh <spec>` (no ZN_* variables, no z-nile/bin on
# PATH), so the run and everything it starts stop at the limit. Run the script itself through `./zn run --time`.
# Usage: mutants.py [row ...]
import subprocess, sys, os
P = open('/tmp/c0301-proto-path').read().strip() + '/repo'
assert P.startswith('/tmp/') or P.startswith('/private/tmp/'), P
T = 'z-nile/engine/trace.luau'; M = 'z-nile/engine/main.luau'; R = 'z-nile/engine/raftplan.luau'
REV = 'z-nile/skills/zz-review/SKILL.md'
A = 'tests/acceptance/c0301/'
HERE = os.path.dirname(os.path.abspath(__file__))
TOP = subprocess.run(['git', '-C', HERE, 'rev-parse', '--show-toplevel'], capture_output=True, text=True, check=True).stdout.strip()
RUN = [os.path.join(TOP, 'zn'), 'run', '--time', '600', '--', os.path.join(HERE, 'run-plain.sh')]
SEAL = 'z-nile/tests/lib/seal.luau'
OLD_TOUCHED = '''local function touchedModules(item: store.Item): { string }?
	local text = fs.readFile(item.doc)
	local section = string.match(text, "\\n### Touched modules\\n(.-)\\n##")
	if not section then
		return nil
	end
	local out: { string } = {}
	for path in string.gmatch("\\n" .. section, "\\n%-%s+`([^`]+)`") do
		table.insert(out, (string.gsub(path, "/+$", "")))
	end
	if #out == 0 then
		return nil
	end
	return out
end
'''
MUTANTS = [
 ('R1', T, 'if not emptySection then', 'if true then', 'claims'),
 ('R1-land', T, 'if not emptySection then', 'if true then', 'land'),
 ('R2', T, '(item.heading == "judged" or item.heading == "observed")', 'true', 'claims'),
 ('R3', T, '(item.heading == "judged" or item.heading == "observed")', '(string.find(item.heading, "^judged") ~= nil or string.find(item.heading, "^observed") ~= nil)', 'claims'),
 ('R4', T, '\t\t\tand perGroup[item.group] == 1\n', '', 'claims'),
 ('R5a', T, '\tlocal t = string.lower(trim(text))\n', '\tif true then return trim(text) == "None." end\n\tlocal t = string.lower(trim(text))\n', 'claims'),
 ('R5b', T, 'return trim(t) == "none"', 'return string.sub(trim(t), 1, 4) == "none"', 'claims'),
 ('R6', T, 'table.insert(out, { text = item.text, index = i })', 'table.insert(out, { text = item.text, index = #out + 1 })', 'claims'),
 ('R7', T, 'if #acItems == 0 then', 'if #acItems == 0 and #extractOutcomes(acBody) == 0 then', 'claims'),
 ('R8', T, '\tfor _, entry in trace.acItems(body) do\n\t\ttable.insert(out, entry.text)\n\tend\n\treturn out\n', '\tlocal _ = out\n\treturn extractOutcomes(body)\n', 'claims'),
 ('R9', T, '\t\t\ttable.insert(findings, `row {cid}, claim: unknown claim {cid}`)\n', '', 'claims'),
 ('R10a', T, 'if spec and not source then', 'if spec then', 'code'),
 ('R10c', T, '\t\tand string.find(path, "/.tracker/", 1, true) == nil\n', '', 'code'),
 ('R10b', T, 'if spec and not source then', 'if not source then', 'code'),
 ('R11', T, '\t\tfor _, c in layer.commits do\n\t\t\tfor _, p in c.files do\n\t\t\t\tfiles[p] = true', '\t\tfor _, c in { layer.commits[1] } do\n\t\t\tfor _, p in c.files do\n\t\t\t\tfiles[p] = true', 'code'),
 ('R12', T, 'local testsOnly = trace.testsOnly(input.layers)', 'local testsOnly = trace.testsOnly(input.layers)\n\tif input.layers == nil then\n\t\tfor _, i in input.issues do\n\t\t\ttestsOnly[i.id] = true\n\t\tend\n\tend', 'code'),
 ('R13', T, 'elseif not isSpecFile(ref.path) then', 'elseif not isSpecFile(ref.path) and not changedSourcesSet[ref.path] then', 'code'),
 ('R14', T, 'elseif not changedFilesSet[ref.path] then', 'elseif false then', 'code'),
 ('R15a', T, 'elseif not own[ref.path] and not inTouched(ref.path, touched, issue.home) then', 'elseif false then', 'code'),
 ('R15c', T, 'local own: { [string]: boolean } = layerFiles[issue.id] or {}', 'local own: { [string]: boolean } = {}\n\t\t\tfor _, fs in layerFiles do\n\t\t\t\tfor k in fs do\n\t\t\t\t\town[k] = true\n\t\t\t\tend\n\t\t\tend', 'code'),
 ('R16own', T, 'elseif not own[ref.path] and not inTouched(ref.path, touched, issue.home) then', 'elseif not inTouched(ref.path, touched, issue.home) then', 'code'),
 ('R15b', T, 'return path == dir or string.sub(path, 1, #dir + 1) == dir .. "/"', 'return string.sub(path, 1, #dir) == dir', 'code'),
 ('R16a', T, 'raftplan.touchedModules(issue.docText)', 'raftplan.touchedModules(issue.capturedText)', 'code'),
 ('R16b', R, '\t\ttable.insert(out, (string.gsub(path, "/+$", "")))\n\tend\n\tif #out == 0 then', '\t\ttable.insert(out, path)\n\tend\n\tif #out == 0 then', 'code'),
 ('R17', T, 'elseif testsOnly[issue.id] and not isNone then', 'elseif testsOnly[issue.id] and isNone then\n\t\t\t-- accepted\n\t\telseif testsOnly[issue.id] then', 'code'),
 ('R18', T, 'elseif testsOnly[issue.id] and not isNone then', 'elseif testsOnly[issue.id] and not isNone and #input.changedSources > 0 then', 'code'),
 ('R19a', T, '\t\t\t\tif isSpecFile(ref.path) then\n\t\t\t\t\t-- a spec file, there or deleted', '\t\t\t\tif isSpecFile(ref.path) and not changedFilesSet[ref.path] then\n\t\t\t\t\t-- a spec file, there or deleted', 'code', [('\t\t\t\telseif not changedSourcesSet[ref.path] then\n\t\t\t\t\ttable.insert(findings, `row {cid}, code: {ref.path} was not changed by this stack`)', '\t\t\t\telseif not changedSourcesSet[ref.path] and not changedFilesSet[ref.path] then\n\t\t\t\t\ttable.insert(findings, `row {cid}, code: {ref.path} was not changed by this stack`)')]),
 ('R19b', T, '\t\t\t\tif isSpecFile(ref.path) then\n\t\t\t\t\t-- a spec file, there or deleted', '\t\t\t\tif false then\n\t\t\t\t\t-- a spec file, there or deleted', 'code'),
 ('R20', M, 'changedFiles = changedFiles,', 'changedFiles = changedSources,', 'land'),
 ('R20b', SEAL, 'local code = if spec then `{spec}:1` else codeRef', 'local code = codeRef', 'land'),
 ('R23', T, 'if err ~= nil and input.filesAtCommit[ref.path] == nil and baseFiles[ref.path] ~= nil then', 'if false then', 'code'),
 ('R23-land', T, 'if err ~= nil and input.filesAtCommit[ref.path] == nil and baseFiles[ref.path] ~= nil then', 'if false then', 'land'),
 ('R24', T, 'if err ~= nil and input.filesAtCommit[ref.path] == nil and baseFiles[ref.path] ~= nil then', 'if baseFiles[ref.path] ~= nil then', 'code'),
 ('R25', M, '\t\t\tlocal text = gitFileTextAt(baseTip, path)\n\t\t\tif text ~= nil then\n\t\t\t\tfilesAtBase[path]', '\t\t\tlocal text = gitFileTextAt(topTip, path)\n\t\t\tif text ~= nil then\n\t\t\t\tfilesAtBase[path]', 'land'),
 ('R26', M, 'local deleted = sh.git({ "diff", "--name-only", "--no-renames", "--diff-filter=D", baseTip, topTip })', 'local deleted = table.concat(diffList, "\\n")', 'land'),
 ('R27', T, 'if under(path, p) or (home ~= "." and home ~= "" and under(path, `{home}/{p}`)) then', 'if under(path, p) then', 'code'),
 ('R28', T, 'if under(path, p) or (home ~= "." and home ~= "" and under(path, `{home}/{p}`)) then', 'if under(path, p) or (home ~= "." and home ~= "" and string.sub(path, 1, #home + 1 + #p) == `{home}/{p}`) then', 'code'),
 ('R29', SEAL, 'if spec == nil and trace.isSpecFile(path) then', 'if spec == nil and trace.isSpecFile(path) and fs.isFile(`{dir}/{path}`) then', 'land'),
 ('R30', T, '\t\t\t\tif isSpecFile(ref.path) then\n\t\t\t\t\t-- a spec file, there or deleted', '\t\t\t\tif err == nil and isSpecFile(ref.path) then\n\t\t\t\t\t-- a spec file, there or deleted', 'code'),
 ('R21', REV, 'a tests-only ticket, whose layer changed a spec file (a `*.spec.luau` outside a `.tracker/` folder) and no source file, cites', 'a tests-only ticket cites', 'docs'),
 ('R22', M, 'local function touchedModules(item: store.Item): { string }?\n\treturn raftplan.touchedModules(fs.readFile(item.doc))\nend\n', OLD_TOUCHED, 'docs'),
]
only = set(sys.argv[1:])
results = []
for m in MUTANTS:
    name, path, old, new, spec = m[:5]
    extra = m[5] if len(m) > 5 else []
    if only and name not in only:
        continue
    full = os.path.join(P, path)
    text = open(full).read()
    edits = [(old, new)] + extra
    ok = True
    for o, n in edits:
        if text.count(o) != 1:
            results.append((name, 'NOT APPLIED', f'{text.count(o)} matches')); ok = False; break
        text = text.replace(o, n, 1)
    if not ok:
        continue
    open(full, 'w').write(text)
    try:
        r = subprocess.run(RUN + [A + spec + '.spec.luau'], capture_output=True, text=True)
        out = r.stdout + r.stderr
    finally:
        subprocess.run(['git', '-C', P, 'checkout', '--', path], check=True)
    failed_lines = [l for l in out.splitlines() if l.startswith('FAIL ') and ' :: ' in l]
    detail = [l.strip() for l in out.splitlines() if l.strip().startswith('/') and 'spec:' in l]
    bad = [d for d in detail if 'attempt to' in d or 'syntax' in d.lower() or 'TypeError' in d]
    verdict = 'killed' if failed_lines and not bad else ('ERROR' if bad else 'SURVIVED')
    results.append((name, verdict, '; '.join(f.split(' :: ')[1][:70] for f in failed_lines[:2]) + (' | ' + bad[0][:150] if bad else '')))
for r in results:
    print('\t'.join(r))
