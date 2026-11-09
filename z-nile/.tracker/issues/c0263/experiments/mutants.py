"""Mutation check for c0263: python3 mutants.py ["<mutant name>" ...]

Each entry replaces one text in a copy of the prototype (proto-c0263-raft), runs the row's spec through ./zn run --time,
and restores the file. A mutant is killed when the run fails."""
import subprocess
import sys

P = '/Users/philipbergen/code/pickman/.worktree/proto-c0263-mut'
Z = P + '/z-nile'
A = 'tests/acceptance/c0263/'
PV, RC, PB, RM, RS = A + 'provenance.spec.luau', A + 'record.spec.luau', A + 'publish.spec.luau', A + 'remap.spec.luau', A + 'remap-shapes.spec.luau'
PLAIN = '(function() local r = sh.run("git", { "merge", "--no-edit", %s }) if not r.ok then sh.run("git", { "merge", "--abort" }) end return r.ok, r.stderr end)()'
PRV, MAIN, PUB, AUD, TRL = 'engine/provenance.luau', 'engine/main.luau', 'engine/publish.luau', 'engine/audit.luau', 'engine/trail.luau'
M = [
    ('isValid accepts any agent:', PRV, 'agent:[%l%d%-]+ effort %w+$") ~= nil\nend\n\n-- the form', 'agent:") ~= nil\nend\n\n-- the form', PV),
    ('modelId keeps dots', PRV, '"[^%w]+", "-")', '"[^%w%.]+", "-")', PV),
    ('none accepted live', PRV, 'local function liveForm(value: string): boolean\n', 'local function liveForm(value: string): boolean\n\tif value == "none" then\n\t\treturn true\n\tend\n', PV),
    ('env beats flag', PRV, '{ flag, env }', '{ env, flag }', PV),
    ('agent hint ignored', PRV, 'if hint.agent then', 'if false then', PV),
    ('hint ignores AI_AGENT', PRV, ' or set("AI_AGENT")', '', PV),
    ('hint ignores CLAUDECODE', PRV, 'set("CLAUDECODE") or ', '', PV),
    ('hint ignores CURSOR_AGENT', PRV, ' or set("CURSOR_AGENT")', '', PV),
    ('hint ignores GROK_SESSION_ID', PRV, ' or set("GROK_SESSION_ID")', '', PV),
    ('hint effort dropped', PRV, 'effort = env.CLAUDE_EFFORT,', 'effort = nil,', PV),
    ('liveActor ignores ZN_ACTOR', MAIN, 'process.env.ZN_ACTOR, hint, name)', 'nil, hint, name)', RC),
    ('liveActor ignores --actor', MAIN, 'provenance.resolve(if flagList then flagList[1] else nil,', 'provenance.resolve(nil,', RC),
    ('liveActor ignores the git name', MAIN, 'process.env.ZN_ACTOR, hint, name)', 'process.env.ZN_ACTOR, hint, nil)', RC),
    ('liveActor ignores the environment hint', MAIN, 'local hint = provenance.hint({', 'local hint = provenance.hint({}) or provenance.hint({', RC),
    ('liveActor ignores CURSOR_AGENT', MAIN, '\t\tCURSOR_AGENT = process.env.CURSOR_AGENT,\n', '', RC),
    ('liveActor ignores GROK_SESSION_ID', MAIN, '\t\tGROK_SESSION_ID = process.env.GROK_SESSION_ID,\n', '', RC),
    ('free event name', PRV, 'return table.find(provenance.EVENTS, event) ~= nil', 'return true', PV),
    ('parser skips non-bar lines', PRV, '\t\tlocal line = lines[n]\n', '\t\tlocal line = lines[n]\n\t\tif string.sub(line, 1, 1) ~= "|" then\n\t\t\tcontinue\n\t\tend\n', PV),
    ('parser takes a fifth cell', PRV, '([^|]*) |$")', '(.*) |$")', PV),
    ('pipe splits row', PRV, 'string.gsub(detail, "|", "/")', 'string.gsub(detail, "|", "|")', PV),
    ('union drops theirs', PRV, 'table.insert(out, t[i])', '', PV),
    ('union ours first', PRV, '\tlocal taken: { [string]: number } = {}', '\tfor i = #b + 1, #o do\n\t\ttable.insert(out, o[i])\n\tend\n\tlocal taken: { [string]: number } = {}', PV),
    ('union doubles shared', PRV, 'if (taken[k] or 0) > 0 then', 'if false then', PV),
    ('union drops the multiset decrement', PRV, 'taken[k] -= 1', '', PV),
    ('union accepts an edited base row', PRV, '\tif badO then', '\tif false then', PV),
    ('appendOnly ignores actor', PRV, 'or m.actor ~= r.actor', '', PV),
    ('appendOnly ignores detail', PRV, 'or m.detail ~= r.detail', '', PV),
    ('appendOnly ignores when', PRV, 'or m.when ~= r.when', '', PV),
    ('appendOnly compares as a set', PRV, '\t\t\tlocal m = n[i]\n\t\t\tif\n\t\t\t\tnot m', '\t\t\tlocal m = n[i]\n\t\t\tfor _, cand in n do\n\t\t\t\tif cand.when == r.when and cand.event == r.event and cand.actor == r.actor and cand.detail == r.detail then\n\t\t\t\t\tm = cand\n\t\t\t\tend\n\t\t\tend\n\t\t\tif\n\t\t\t\tnot m', PV),
    ('extends compares as a set', PRV, '\t\tlocal m = side[i]\n', '\t\tlocal m = side[i]\n\t\tfor _, cand in side do\n\t\t\tif cand.when == r.when and cand.event == r.event and cand.actor == r.actor and cand.detail == r.detail then\n\t\t\t\tm = cand\n\t\t\tend\n\t\tend\n', PV),
    ('publishProblem allows all', PRV, 'if not table.find(allowed, n[i].event) then', 'if false then', PV),
    ('locate takes the first of two', PRV, 'if found then\n\t\t\t\treturn nil,', 'if false then\n\t\t\t\treturn nil,', PV),
    ('isDoc counts record', TRL, ' or name == "provenance.md"', '', PV),
    ('audit ignores header id', PRV, 'if folderId and header ~= folderId then', 'if false then', PV),
    ('audit skips active and done records', AUD, '\t\tif fs.isFile(recFile) then', '\t\tif fs.isFile(recFile) and not string.find(f.path, "/active/", 1, true) and not string.find(f.path, "/done/", 1, true) then', RC),
    ('audit skips rafts', AUD, '\t\tif fs.isFile(recFile) then', '\t\tif fs.isFile(recFile) and not string.find(f.path, "/rafts/", 1, true) then', RC),
    ('validator: active takes any event', PUB, 'then { "unblocked" }\n\t\t\t\t\telse provenance.PUBLISHED', 'then provenance.PUBLISHED\n\t\t\t\t\telse provenance.PUBLISHED', PB),
    ('validator: done takes published events', PUB, 'if string.find(c.path, "/done/", 1, true) then\n\t\t\t\t\treturn fail(', 'if false then\n\t\t\t\t\treturn fail(', PB),
    ('validator: no document beside', PUB, 'if not onOrigin[doc] then\n\t\t\t\t\treturn fail(`{c.path}: no {pid}.md', 'if false then\n\t\t\t\t\treturn fail(`{c.path}: no {pid}.md', PB),
    ('record built from worktree file', MAIN, 'provenance.record(read(rec), id,', 'provenance.record(if fs.isFile(rec) then fs.readFile(rec) else nil, id,', RC),
    ('record accepts any event (command)', MAIN, 'if not table.find(provenance.PUBLISHED, event) then', 'if false then', RC),
    ('record: done item (command)', MAIN, 'if string.find(doc, "/done/", 1, true) then\n\t\t\treturn `record refuses', 'if false then\n\t\t\treturn `record refuses', RC),
    ('record: active takes any event (command)', MAIN, 'elseif string.find(doc, "/active/", 1, true) and event ~= "unblocked" then', 'elseif false then', RC),
    ('record: main checkout allowed', MAIN, '\trefuseInMainCheckout("record")\n', '', RC),
    ('record: offline allowed', MAIN, '\tif not publishing() then\n\t\tfail("record needs an origin remote', '\tif false then\n\t\tfail("record needs an origin remote', RC),
    # settle (pure)
    ('merge: no union (both changed aborts)', PRV, '\tlocal united, why = provenance.union(common, ours, theirs)\n', '\tlocal united, why = nil, "no union"\n', PV),
    ('merge: refusal of a bad union ignored', PRV, '\tlocal united, why = provenance.union(common, ours, theirs)\n\tif not united then\n\t\treturn nil, nil, why\n\tend\n', '\tlocal united = provenance.union(common, ours, theirs) or ours\n', PV),
    ('merge: one-sided record aborts', PRV, '\telseif changedOurs and not changedTheirs then\n\t\treturn take(ours)', '\telseif changedOurs and not changedTheirs then\n\t\treturn nil, nil, "one-sided"', PV),
    ('merge: a deleted record is resurrected', PRV, '\t\tif text == nil then\n\t\t\treturn "remove", nil, nil', '\t\tif text == nil then\n\t\t\treturn "keep", nil, nil', PV),
    ('merge: a record changed on one side and absent on the other is taken as one-sided', PRV, '\tif ours == nil or theirs == nil then\n\t\treturn nil,', '\tif ours == nil or theirs == nil then\n\t\treturn take(ours or theirs)\n\tend\n\tif false then\n\t\treturn nil,', RC),
    ('merge: both sides deleted is an id change', PRV, '\tif ours == nil and theirs == nil then\n\t\treturn "remove", nil, nil -- both sides deleted it\n\tend\n', '', PV),
    # mergeRef
    ('merge: settles across a compaction', MAIN, '\t\t\tif crossing then', '\t\t\tif false then', RC),
    ('merge: examines only unmerged ids', MAIN, 'for _, path in gitLines({ "diff", "--name-only", "--no-renames", base, side }) do', 'for _, path in {} :: { string } do', RC),
    ('merge: stale old path kept', MAIN, 'if path ~= dest and recordIdOf(path) == plan.id then', 'if false then', RC),
    ('merge: stale record unlinked, folder kept', MAIN, 'sh.must("git", { "rm", "-q", "-f", "--ignore-unmatch", "--", path })', 'sh.run("git", { "rm", "-q", "-f", "--cached", "--ignore-unmatch", "--", path })\n\t\t\t\t\t\t\tif fs.isFile(path) then\n\t\t\t\t\t\t\t\tfs.removeFile(path)\n\t\t\t\t\t\t\tend', RC),
    ('merge: ignores locate refusal', MAIN, 'if ownWhy or theirWhy or commonWhy then', 'if false then', RC),
    ('merge: no-document stop removed', MAIN, 'if not folder then', 'if false then', RC),
    ('merge: directoryRenames moves every file', MAIN, '{ "merge", "--no-commit", "--no-edit", ref }', '{ "-c", "merge.directoryRenames=true", "merge", "--no-commit", "--no-edit", ref }', RC),
    ('merge: takes any folder named by the id', MAIN, 'return if rel == "provenance.md" then id else nil', 'return string.match(path, "/([fdcR]%d%d%d%d)/provenance%.md$")', RC),
    ('merge: ignores raft records', MAIN, 'return if rel == "provenance.md" then id else nil', 'return if rel == "provenance.md" and string.sub(id, 1, 1) ~= "R" then id else nil', RC),
    ('land plain merge', MAIN, 'mergeRef(base)', PLAIN % 'base', RC),
    ('merge: a clean merge skips the records', MAIN, 'if #ids > 0 then', 'if #ids > 0 and next(unmerged) ~= nil then', RC),
    ('merge: every conflict kept ours', MAIN, 'if not path or not id then', 'if path and not id then\n\t\t\t\t\tsh.run("git", { "checkout", "--ours", path })\n\t\t\t\t\tsh.must("git", { "add", path })\n\t\t\t\tend\n\t\t\t\tif false then', RC),
    ('merge: record written at the old path', MAIN, 'dest = `{plan.folder}/provenance.md`\n', 'dest = `{plan.folder}/provenance.md`\n\t\t\t\t\tfor _, path in recordPaths(index) do\n\t\t\t\t\t\tif recordIdOf(path) == plan.id then\n\t\t\t\t\t\t\tdest = path\n\t\t\t\t\t\tend\n\t\t\t\t\tend\n', RC),
    ('merge: takes over any merge in progress', MAIN, 'if target == "" or not sh.run("git", { "merge-base", "--is-ancestor", head, target }).ok then', 'if false then', RC),
    ('merge: resumed only when MERGE_HEAD equals ref', MAIN, 'not sh.run("git", { "merge-base", "--is-ancestor", head, target }).ok', 'head ~= target', RC),
    ('merge: aborts a merge it did not start', MAIN, '\t\t\tif ours then\n\t\t\t\tsh.run("git", { "merge", "--abort" })', '\t\t\tif true then\n\t\t\t\tsh.run("git", { "merge", "--abort" })', RC),
    ('merge: writes every settled record', MAIN, 'if not (current.ok and sh.trim(current.stdout) == blob) then', 'if true then', RC),
    ('merge: writes over uncommitted changes', MAIN, 'if dirty(dest :: string) then', 'if false then', RC),
    ('merge: ignores a rebase in progress', MAIN, '\t\tor fs.isDir(`{gitDir}/rebase-merge`)\n\t\tor fs.isDir(`{gitDir}/rebase-apply`)\n', '', RC),
    ('merge: ignores retired records', MAIN, 'if swapped == 1 then', 'if false then', RC),
    ('fold plain merge', MAIN, 'local ok, why, aborted = mergeRef("origin/main")\n\tif not ok then\n\t\tfail(`{what}:', 'local ok, why, aborted = ' + PLAIN % '"origin/main"' + '\n\tif not ok then\n\t\tfail(`{what}:', RC),
    ('sync plain merge', MAIN, 'local ok, why, aborted = mergeRef("origin/main")\n\tif not ok then\n\t\tfail(\n', 'local ok, why, aborted = ' + PLAIN % '"origin/main"' + '\n\tif not ok then\n\t\tfail(\n', RC),
    ('hint ignores ZN_DISPATCH', PRV, ' or set(\n\t\t\t"ZN_DISPATCH"\n\t\t),', ',', PV),
    ('guard ignores a one-sided change', PRV, 'local crossing = (oursCompacted and theirsChanged) or (theirsCompacted and oursChanged)', 'local crossing = (oursCompacted and theirsCompacted) and (oursChanged or theirsChanged)', PV),
    ('merge: same advice for a hand merge', MAIN, 'local way = if ours', 'local way = if true', RC),
    ('merge: dirty ignores untracked paths', MAIN, 'return fs.isFile(path)', 'return false', RC),
    ('merge: ignores a revert in progress', MAIN, '\t\tor inProgress("REVERT_HEAD")\n', '', RC),
    ('merge: finishes a hand merge inside a rebase', MAIN, '\tif\n\t\tinProgress("CHERRY_PICK_HEAD")\n\t\tor inProgress("REVERT_HEAD")\n\t\tor fs.isDir(`{gitDir}/rebase-merge`)\n\t\tor fs.isDir(`{gitDir}/rebase-apply`)\n\tthen', '\tif\n\t\tnot inProgress("MERGE_HEAD")\n\t\tand (inProgress("CHERRY_PICK_HEAD")\n\t\tor inProgress("REVERT_HEAD")\n\t\tor fs.isDir(`{gitDir}/rebase-merge`)\n\t\tor fs.isDir(`{gitDir}/rebase-apply`))\n\tthen', RC),
    ('merge: hides that the hand merge was committed', MAIN, 'finished = "your merge was finished and committed; "', 'finished = ""', RC),
    # remap
    ('remap skips the settling', MAIN, 'local settled = if mtTree then settleRemapRecords(mt.stdout, mtTree, baseTree) else nil', 'local settled = mtTree', RM),
    ('remap settles only conflicted paths', MAIN, 'local ids = changedRecordIds(baseTree, "HEAD", "origin/main")', 'local ids: { string } = {}', RS),
    ('remap drops the base stage', MAIN, 'local plans = planRecords(ids, "HEAD", "origin/main", baseTree, merged)', 'local plans = planRecords(ids, "HEAD", "origin/main", "4b825dc642cb6eb9a060e54bf8d69288fbee4904", merged)', RS),
    ('remap accepts a non-record conflict beside a record', MAIN, '\t\t\tif not id then\n\t\t\t\treturn nil\n\t\t\tend', '\t\t\tif not id then\n\t\t\t\tcontinue\n\t\t\tend', RS),
    # docs
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
