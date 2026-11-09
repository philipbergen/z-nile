import subprocess, sys

P = '/Users/philipbergen/code/pickman/.worktree/proto-c0263-mut'
Z = P + '/z-nile'
PV = 'tests/acceptance/c0263/provenance.spec.luau'
RC = 'tests/acceptance/c0263/record.spec.luau'
PB = 'tests/acceptance/c0263/publish.spec.luau'
RM = 'tests/acceptance/c0263/remap.spec.luau'
PLAIN = '(function() local r = sh.run("git", { "merge", "--no-edit", %s }) if not r.ok then sh.run("git", { "merge", "--abort" }) end return r.ok, r.stderr end)()'
M = [
    ('isValid accepts any agent:', 'engine/provenance.luau', 'agent:[%l%d%-]+ effort %w+$") ~= nil\nend\n\n-- the form', 'agent:") ~= nil\nend\n\n-- the form', PV),
    ('modelId keeps dots', 'engine/provenance.luau', '"[^%w]+", "-")', '"[^%w%.]+", "-")', PV),
    ('none accepted live', 'engine/provenance.luau', 'local function liveForm(value: string): boolean\n', 'local function liveForm(value: string): boolean\n\tif value == "none" then\n\t\treturn true\n\tend\n', PV),
    ('env beats flag', 'engine/provenance.luau', '{ flag, env }', '{ env, flag }', PV),
    ('agent hint ignored', 'engine/provenance.luau', 'if hint.agent then', 'if false then', PV),
    ('hint ignores ZN_DISPATCH', 'engine/provenance.luau', ' or set("ZN_DISPATCH")', '', PV),
    ('hint ignores AI_AGENT', 'engine/provenance.luau', ' or set("AI_AGENT")', '', PV),
    ('hint ignores CLAUDECODE', 'engine/provenance.luau', 'set("CLAUDECODE") or ', '', PV),
    ('hint effort dropped', 'engine/provenance.luau', 'effort = env.CLAUDE_EFFORT,', 'effort = nil,', PV),
    ('liveActor ignores ZN_ACTOR', 'engine/main.luau', 'process.env.ZN_ACTOR, hint, name)', 'nil, hint, name)', RC),
    ('liveActor ignores --actor', 'engine/main.luau', 'provenance.resolve(if flagList then flagList[1] else nil,', 'provenance.resolve(nil,', RC),
    ('liveActor ignores the git name', 'engine/main.luau', 'process.env.ZN_ACTOR, hint, name)', 'process.env.ZN_ACTOR, hint, nil)', RC),
    ('liveActor ignores the environment hint', 'engine/main.luau', 'local hint = provenance.hint({', 'local hint = provenance.hint({}) or provenance.hint({', RC),
    ('free event name', 'engine/provenance.luau', 'return table.find(provenance.EVENTS, event) ~= nil', 'return true', PV),
    ('parser skips non-bar lines', 'engine/provenance.luau', '\t\tlocal line = lines[n]\n', '\t\tlocal line = lines[n]\n\t\tif string.sub(line, 1, 1) ~= "|" then\n\t\t\tcontinue\n\t\tend\n', PV),
    ('parser takes a fifth cell', 'engine/provenance.luau', '([^|]*) |$")', '(.*) |$")', PV),
    ('pipe splits row', 'engine/provenance.luau', 'string.gsub(detail, "|", "/")', 'string.gsub(detail, "|", "|")', PV),
    ('union drops theirs', 'engine/provenance.luau', 'table.insert(out, t[i])', '', PV),
    ('union ours first', 'engine/provenance.luau', '\tlocal taken: { [string]: number } = {}', '\tfor i = #b + 1, #o do\n\t\ttable.insert(out, o[i])\n\tend\n\tlocal taken: { [string]: number } = {}', PV),
    ('union doubles shared', 'engine/provenance.luau', 'if (taken[k] or 0) > 0 then', 'if false then', PV),
    ('union accepts an edited base row', 'engine/provenance.luau', '\tif badO then', '\tif false then', PV),
    ('appendOnly ignores actor', 'engine/provenance.luau', 'or m.actor ~= r.actor', '', PV),
    ('appendOnly ignores detail', 'engine/provenance.luau', 'or m.detail ~= r.detail', '', PV),
    ('appendOnly ignores when', 'engine/provenance.luau', 'or m.when ~= r.when', '', PV),
    ('publishProblem allows all', 'engine/provenance.luau', 'if not table.find(allowed, n[i].event) then', 'if false then', PV),
    ('isDoc counts record', 'engine/trail.luau', ' or name == "provenance.md"', '', PV),
    ('audit ignores header id', 'engine/provenance.luau', 'if folderId and header ~= folderId then', 'if false then', PV),
    ('audit skips active and done records', 'engine/audit.luau', '\t\tif fs.isFile(recFile) then', '\t\tif fs.isFile(recFile) and not string.find(f.path, "/active/", 1, true) and not string.find(f.path, "/done/", 1, true) then', RC),
    ('audit skips rafts', 'engine/audit.luau', '\t\tif fs.isFile(recFile) then', '\t\tif fs.isFile(recFile) and not string.find(f.path, "/rafts/", 1, true) then', RC),
    ('validator: active takes any event', 'engine/publish.luau', 'then { "unblocked" }\n\t\t\t\t\telse provenance.PUBLISHED', 'then provenance.PUBLISHED\n\t\t\t\t\telse provenance.PUBLISHED', PB),
    ('validator: done takes published events', 'engine/publish.luau', 'if string.find(c.path, "/done/", 1, true) then\n\t\t\t\t\treturn fail(', 'if false then\n\t\t\t\t\treturn fail(', PB),
    ('validator: no document beside', 'engine/publish.luau', 'if not onOrigin[doc] then\n\t\t\t\t\treturn fail(`{c.path}: no {pid}.md', 'if false then\n\t\t\t\t\treturn fail(`{c.path}: no {pid}.md', PB),
    ('record built from worktree file', 'engine/main.luau', 'provenance.record(read(rec), id,', 'provenance.record(if fs.isFile(rec) then fs.readFile(rec) else nil, id,', RC),
    ('record accepts any event (command)', 'engine/main.luau', 'if not table.find(provenance.PUBLISHED, event) then', 'if false then', RC),
    ('record: done item (command)', 'engine/main.luau', 'if string.find(doc, "/done/", 1, true) then\n\t\t\treturn `record refuses', 'if false then\n\t\t\treturn `record refuses', RC),
    ('record: active takes any event (command)', 'engine/main.luau', 'elseif string.find(doc, "/active/", 1, true) and event ~= "unblocked" then', 'elseif false then', RC),
    ('record: main checkout allowed', 'engine/main.luau', '\trefuseInMainCheckout("record")\n', '', RC),
    ('record: offline allowed', 'engine/main.luau', '\tif not publishing() then\n\t\tfail("record needs an origin remote', '\tif false then\n\t\tfail("record needs an origin remote', RC),
    ('land plain merge', 'engine/main.luau', 'mergeRef(base)', PLAIN % 'base', RC),
    ('fold plain merge', 'engine/main.luau', 'local ok, why = mergeRef("origin/main")\n\tif not ok then\n\t\tfail(`{what}:', 'local ok, why = ' + PLAIN % '"origin/main"' + '\n\tif not ok then\n\t\tfail(`{what}:', RC),
    ('sync plain merge', 'engine/main.luau', 'local ok, why = mergeRef("origin/main")\n\tif not ok then\n\t\tfail(\n', 'local ok, why = ' + PLAIN % '"origin/main"' + '\n\tif not ok then\n\t\tfail(\n', RC),
    ('appendOnly compares as a set', 'engine/provenance.luau', '\t\t\tlocal m = n[i]\n\t\t\tif\n\t\t\t\tnot m', '\t\t\tlocal m = n[i]\n\t\t\tfor _, cand in n do\n\t\t\t\tif cand.when == r.when and cand.event == r.event and cand.actor == r.actor and cand.detail == r.detail then\n\t\t\t\t\tm = cand\n\t\t\t\tend\n\t\t\tend\n\t\t\tif\n\t\t\t\tnot m', PV),
    ('extends compares as a set', 'engine/provenance.luau', '\t\tlocal m = side[i]\n', '\t\tlocal m = side[i]\n\t\tfor _, cand in side do\n\t\t\tif cand.when == r.when and cand.event == r.event and cand.actor == r.actor and cand.detail == r.detail then\n\t\t\t\tm = cand\n\t\t\tend\n\t\tend\n', PV),
    ('union drops the multiset decrement', 'engine/provenance.luau', 'taken[k] -= 1', '', PV),
    ('locate takes the first of two', 'engine/provenance.luau', 'if found then\n\t\t\t\treturn nil,', 'if false then\n\t\t\t\treturn nil,', PV),
    ('hint ignores CURSOR_AGENT', 'engine/provenance.luau', ' or set("CURSOR_AGENT")', '', PV),
    ('hint ignores GROK_SESSION_ID', 'engine/provenance.luau', ' or set("GROK_SESSION_ID")', '', PV),
    ('liveActor ignores CURSOR_AGENT', 'engine/main.luau', '\t\tCURSOR_AGENT = process.env.CURSOR_AGENT,\n', '', RC),
    ('liveActor ignores GROK_SESSION_ID', 'engine/main.luau', '\t\tGROK_SESSION_ID = process.env.GROK_SESSION_ID,\n', '', RC),
    ('merge: no union (both changed aborts)', 'engine/provenance.luau', '\tlocal united, why = provenance.union(common, ours, theirs)\n', '\tlocal united, why = nil, "no union"\n', PV),
    ('merge: refusal of a bad union ignored', 'engine/provenance.luau', '\tlocal united, why = provenance.union(common, ours, theirs)\n\tif not united then\n\t\treturn nil, nil, why\n\tend\n', '\tlocal united = provenance.union(common, ours, theirs) or ours\n', PV),
    ('merge: one-sided record aborts', 'engine/provenance.luau', '\telseif changedOurs and not changedTheirs then\n\t\treturn take(ours)', '\telseif changedOurs and not changedTheirs then\n\t\treturn nil, nil, "one-sided"', PV),
    ('merge: a deleted record is resurrected', 'engine/provenance.luau', '\t\tif text == nil then\n\t\t\treturn "remove", nil, nil', '\t\tif text == nil then\n\t\t\treturn "keep", nil, nil', PV),
    ('merge: a record changed on one side and absent on the other is taken as one-sided', 'engine/provenance.luau', '\tif ours == nil or theirs == nil then\n\t\treturn nil,', '\tif ours == nil or theirs == nil then\n\t\treturn take(ours or theirs)\n\tend\n\tif false then\n\t\treturn nil,', RC),
    ('merge: examines only unmerged ids', 'engine/main.luau', '\t\t\t\tnote(path)\n', '', RC),
    ('merge: a clean merge skips the records', 'engine/main.luau', '\t\tif #ids > 0 then\n', '\t\tif #ids > 0 and unmerged then\n', RC),
    ('merge: every conflict kept ours', 'engine/main.luau', '\t\t\tif not path or not note(path) then\n\t\t\t\treturn false, detail -- a conflict outside the records\n\t\t\tend', '\t\t\tif path and not note(path) then\n\t\t\t\tsh.run("git", { "checkout", "--ours", path })\n\t\t\t\tsh.must("git", { "add", path })\n\t\t\tend', RC),
    ('merge: stale old path kept', 'engine/main.luau', 'if path ~= target and string.match(path, `/{id}/provenance%.md$`) then', 'if false then', RC),
    ('merge: stale record unlinked, folder kept', 'engine/main.luau', 'sh.must("git", { "rm", "-q", "-f", "--ignore-unmatch", "--", path })', 'sh.run("git", { "rm", "-q", "-f", "--cached", "--ignore-unmatch", "--", path })\n\t\t\t\t\t\t\tif fs.isFile(path) then\n\t\t\t\t\t\t\t\tfs.removeFile(path)\n\t\t\t\t\t\t\tend', RC),
    ('merge: record written at the old path', 'engine/main.luau', 'target = `{folder}/provenance.md`', 'target = (provenance.locate(trees["HEAD"], id)) or `{folder}/provenance.md`', RC),
    ('merge: ignores locate refusal', 'engine/main.luau', 'if ownWhy or theirWhy or commonWhy then', 'if false then', RC),
    ('merge: no-document stop removed', 'engine/main.luau', '\t\t\t\t\tif not folder then\n', '\t\t\t\t\tif false then\n', RC),
    ('merge: directoryRenames moves every file', 'engine/main.luau', '{ "merge", "--no-commit", "--no-edit", ref }', '{ "-c", "merge.directoryRenames=true", "merge", "--no-commit", "--no-edit", ref }', RC),
    ('remap skips the union', 'engine/main.luau', 'local united = if tree then uniteRemapRecords(mt.stdout, tree) else nil', 'local united = nil', RM),
    ('docs: zz-execute step 2 reverted', 'skills/zz-execute/SKILL.md', 'run `./zn sync` (it fetches and merges `origin/main`, and unites a `provenance.md` both sides appended) to bring `origin/main` into the branch now', '`git fetch origin main` and merge it into the branch now', PV),
]
only = sys.argv[1:]
for name, f, old, new, spec in M:
    if only and name not in only:
        continue
    path = f'{Z}/{f}'
    s = open(path).read()
    if old not in s:
        print('NOAPPLY', name, flush=True)
        continue
    open(path, 'w').write(s.replace(old, new, 1))
    try:
        r = subprocess.run(['/Users/philipbergen/code/pickman/zn', 'run', '--time', '900', '--', 'lune', 'run', 'tests/run', '--', spec], cwd=Z, capture_output=True, text=True)
        out = r.stdout + r.stderr
        last = [l for l in out.split('\n') if 'passed' in l and 'failed' in l]
        fails = [l for l in out.split('\n') if l.startswith('FAIL')]
        print(('KILLED' if r.returncode != 0 else 'SURVIVED'), name, '|', last[-1] if last else '', '|', (fails[0][:160] if fails else ''), flush=True)
    finally:
        open(path, 'w').write(s)
