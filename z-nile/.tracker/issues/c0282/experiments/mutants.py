"""Mutation check for c0282: python3 mutants.py ["<mutant name>" ...]   (no name: every mutant)

Each entry replaces one text in a copy of the prototype (proto-c0282), runs the row's spec through ./zn run --time,
and restores the file. A mutant is killed when the run fails. Prints `killed <name>` or `SURVIVED <name>`, and
`no match <name>` when the text to replace is not in the file (the mutant did not apply)."""
import os
import subprocess
import sys

P = os.environ.get('MUT_P', '/Users/philipbergen/code/pickman/.worktree/proto-c0282-mut')  # a copy of the prototype
Z = P + '/z-nile'
A = 'tests/acceptance/c0282/'
LC, RC, DS, PV = A + 'lifecycle.spec.luau', A + 'record.spec.luau', A + 'dispatch.spec.luau', A + 'provenance.spec.luau'
MAIN, DSP, PRV = 'engine/main.luau', 'engine/dispatcher.luau', 'engine/provenance.luau'
NEWRAFT_PUB = 'lifecycle.append(item.dir, id, "rafted", actor, provenance.raftDetail(chosen, via))'
M = [
    # status new -> unblocked
    ('status new: no row', MAIN, 'if unblocker and not store.isRaftId(t) then', 'if false then', RC),
    ('status new: the raft gets a record', MAIN, 'if unblocker and not store.isRaftId(t) then', 'if unblocker then', RC),
    ('status new: row built from the worktree file', MAIN, 'provenance.record(read(rec), t, "unblocked"', 'provenance.record(if fs.isFile(rec) then fs.readFile(rec) else nil, t, "unblocked"', RC),
    ('status new: flag ignored', MAIN, 'local unblocker = if to == "new" then (lifecycle.who(opts)) else nil', 'local unblocker = if to == "new" then (lifecycle.who(nil)) else nil', RC),
    ('status: every move stamps', MAIN, 'local unblocker = if to == "new" then (lifecycle.who(opts)) else nil', 'local unblocker = (lifecycle.who(opts))', RC),
    ('release stamps', MAIN, 'table.insert(changes, { path = p, content = withFront(text, "status", stamp(to)) })\n\t\tend\n\t\tif #changes == 0 then', 'table.insert(changes, { path = p, content = withFront(text, "status", stamp(to)) })\n\t\t\ttable.insert(changes, { path = (string.gsub(p, "[^/]+$", "provenance.md")), content = provenance.record(read((string.gsub(p, "[^/]+$", "provenance.md"))), id, "unblocked", "human:x", "", "2026-11-09 10:00") :: string })\n\t\tend\n\t\tif #changes == 0 then', RC),
    # rafted
    ('new raft: published path writes no row', MAIN, '\t\t\t\t' + NEWRAFT_PUB + '\n', '', RC),
    ('new raft: the raft gets a record', MAIN, '\t\t\tsh.git({ "commit", "--quiet", "-m", `tracker: {chosen} members` })', '\t\t\tlifecycle.append(store.get(chosen).dir, chosen, "rafted", actor, provenance.raftDetail(chosen, via))\n\t\t\tsh.git({ "commit", "--quiet", "-m", `tracker: {chosen} members` })', RC),
    ('new raft: offline path writes no row', MAIN, '\t\t\tlifecycle.append(m.dir, m.id, "rafted", actor, provenance.raftDetail(id, via))\n', '', LC),
    ('fold: no row', MAIN, '\t\tlifecycle.append(item.dir, id, "rafted", actor, provenance.raftDetail(raftId, via))\n', '', RC),
    ('recombine: no row', MAIN, '\t\tlifecycle.append(item.dir, id, "rafted", actor, provenance.raftDetail(keeperId, via))\n', '', RC),
    ('emergent issue: no row', MAIN, '\t\tif raftId and actor then\n\t\t\tlifecycle.append(dir, id, "rafted", actor, provenance.raftDetail(raftId, via))\n\t\tend\n', '', LC),
    ('unfold deletes the row', MAIN, '\t\tstore.setFront(doc, "raft", "")\n\t\tsh.git({ "add", doc })\n\tend\n\tstore.setFront(raft.doc, "issues", listValue(left))', '\t\tstore.setFront(doc, "raft", "")\n\t\tsh.git({ "add", doc })\n\t\tsh.run("git", { "rm", "-q", "-f", "--ignore-unmatch", "--", store.get(id).dir .. "/provenance.md" })\n\tend\n\tstore.setFront(raft.doc, "issues", listValue(left))', RC),
    ('via always written', PRV, 'return if via then `raft={raft}; via={via}` else `raft={raft}`', 'return `raft={raft}; via={via or "dispatch:x"}`', PV),
    ('via ignored by the commands', MAIN, 'local via, why = provenance.via(process.env.ZN_VIA)', 'local via, why = provenance.via(nil)', RC),
    ('via accepts anything', PRV, 'if string.match(value, "^dispatch:[%l][%l%d%-]*$") then', 'if true then', PV),
    ('new raft: bad actor read after the claim is published', MAIN, '\t\tlocal actor, via = lifecycle.who(opts)\n\t\tfor i = 4, #pos do', '\t\tlocal actor, via = process.env.ZN_ACTOR or "human:x", nil\n\t\tfor i = 4, #pos do', RC),
    ('fold: bad actor read after the claim is published', MAIN, '\tlocal actor, via = lifecycle.who(opts)\n\traftingStart("fold")', '\tlocal actor, via = process.env.ZN_ACTOR or "human:x", nil\n\traftingStart("fold")', RC),
    ('new issue: reads the actor always', MAIN, '\t\tif raftId then\n\t\t\tactor, via = lifecycle.who(opts)\n\t\tend', '\t\tactor, via = lifecycle.who(opts)', RC),
    ('lifecycleWho accepts no git identity', MAIN, 'if not provenance.isLive(actor) then\n\t\tfail("no git identity', 'if false then\n\t\tfail("no git identity', RC),
    # delivered
    ('done: only the first member', MAIN, '\t\tlifecycle.append(item.dir, item.id, "delivered", actor, provenance.raftDetail(raft.id, nil))\n', '\t\tlifecycle.append(item.dir, item.id, "delivered", actor, provenance.raftDetail(raft.id, nil))\n\t\tbreak\n', LC),
    ('done: the raft gets a row', MAIN, '\traft = move(raft, "done")\n\ttable.insert(movedItems, raft)', '\traft = move(raft, "done")\n\tlifecycle.append(raft.dir, raft.id, "delivered", actor, provenance.raftDetail(raft.id, nil))\n\ttable.insert(movedItems, raft)', LC),
    ('done: the row is left unstaged', MAIN, '\t\tlifecycle.append(item.dir, item.id, "delivered", actor, provenance.raftDetail(raft.id, nil))\n', '\t\tfs.writeFile(`{item.dir}/provenance.md`, provenance.record(if fs.isFile(`{item.dir}/provenance.md`) then fs.readFile(`{item.dir}/provenance.md`) else nil, item.id, "delivered", actor, provenance.raftDetail(raft.id, nil), lifecycle.now()) :: string)\n', LC),
    ('done: the worker is stored', MAIN, '\t\tlifecycle.append(item.dir, item.id, "delivered", actor, provenance.raftDetail(raft.id, nil))\n', '\t\tlifecycle.append(item.dir, item.id, "delivered", actor, provenance.raftDetail(raft.id, nil) .. "; worker=claude")\n', LC),
    ('done: bad actor read after the moves', MAIN, '\tlocal actor = lifecycle.who(opts)\n\tfor _, m in store.members(raft.id) do', '\tlocal actor = process.env.ZN_ACTOR or "human:x"\n\tfor _, m in store.members(raft.id) do', LC),
    # dispatcher
    ('attempt keeps the first ZN_ACTOR', DSP, 'env.ZN_ACTOR = provenance.agent(spec.model, spec.effort)', 'env.ZN_ACTOR = env.ZN_ACTOR or provenance.agent(spec.model, spec.effort)', DS),
    ('attempt actor with the dotted model', DSP, 'env.ZN_ACTOR = provenance.agent(spec.model, spec.effort)', 'env.ZN_ACTOR = `agent:{spec.model} effort {spec.effort or "unknown"}`', DS),
    ('attempt actor without the effort', DSP, 'env.ZN_ACTOR = provenance.agent(spec.model, spec.effort)', 'env.ZN_ACTOR = provenance.agent(spec.model, nil)', DS),
    ('script step records no user', DSP, '\t\tstepEnv.ZN_ACTOR = provenance.human(name)\n', '', DS),
    ('script step records no via', DSP, 'local stepEnv: { [string]: string } = { ZN_VIA = `dispatch:{step}` }', 'local stepEnv: { [string]: string } = {}', DS),
    ('script step names another step', DSP, 'ZN_VIA = `dispatch:{step}`', 'ZN_VIA = "dispatch:script"', DS),
    ('docs: lifecycle paragraph removed', 'skills/zz-rules/SKILL.md', '**Lifecycle rows** (c0282;', '**Lifecycle** (c0282;', PV),
    ('gate takes a record without a raft: change', DSP, 'if became == nil or became == "" or became == was then', 'if false then', DS),
    ('gate ignores the row\'s raft', PRV, 'local okDetail = row.detail == `raft={raft}`', 'local okDetail = string.find(row.detail, "^raft=") ~= nil', DS),
    ('gate takes any stored actor', PRV, 'if not provenance.isLive(row.actor) then', 'if false then', DS),
    ('gate takes any via', PRV, 'okDetail = via ~= nil and provenance.via(via) ~= nil', 'okDetail = via ~= nil', DS),
    ('stale refusal names rebase', DSP, 'run ./zn sync in its worktree (it merges main and unites a provenance.md both sides appended), then push', 'rebase it onto main', DS),
    ('fold: record checked after the claim', MAIN, '\t\tlifecycle.check(issue.dir)\n', '', RC),
    ('new raft: record not checked', MAIN, '\t\t\t\tlifecycle.check(member.dir)\n', '', RC),
    ('done: record checked late', MAIN, '\tfor _, m in store.members(raft.id) do\n\t\tlifecycle.check(m.dir)\n\tend\n', '', LC),
    ('done: --actor ignored', MAIN, '\tlocal actor = lifecycle.who(opts)\n\tfor _, m in store.members(raft.id) do', '\tlocal actor = lifecycle.who(nil)\n\tfor _, m in store.members(raft.id) do', LC),
    ('emergent: --actor ignored', MAIN, '\t\t\tactor, via = lifecycle.who(opts)\n', '\t\t\tactor, via = lifecycle.who(nil)\n', LC),
    ('new raft: --actor ignored', MAIN, '\t\tlocal actor, via = lifecycle.who(opts)\n\t\tfor i = 4, #pos do', '\t\tlocal actor, via = lifecycle.who(nil)\n\t\tfor i = 4, #pos do', RC),
    ('offline new raft: --actor ignored', MAIN, '\t\tlocal actor, via = lifecycle.who(opts)\n\t\tfor i = 4, #pos do', '\t\tlocal actor, via = lifecycle.who(nil)\n\t\tfor i = 4, #pos do', LC),
    ('recombine: --actor ignored', MAIN, '\tlocal actor, via = lifecycle.who(opts)\n\tif keeperId == otherId then', '\tlocal actor, via = lifecycle.who(nil)\n\tif keeperId == otherId then', RC),
    ('fold: --actor ignored', MAIN, '\tlocal actor, via = lifecycle.who(opts)\n\traftingStart("fold")', '\tlocal actor, via = lifecycle.who(nil)\n\traftingStart("fold")', RC),
    ('raft-plan drops --actor', MAIN, 'if opts["--actor"] then\n\t\t\t\to["--actor"] = opts["--actor"]', 'if false then\n\t\t\t\to["--actor"] = opts["--actor"]', RC),
    ('hint ignores GROK_SESSION_ID', PRV, '"CURSOR_AGENT", "GROK_SESSION_ID", "ZN_DISPATCH" }\nprovenance.ENV_VARS', '"CURSOR_AGENT", "ZN_DISPATCH" }\nprovenance.ENV_VARS', PV),
    ('ENV_VARS lacks a marker', PRV, 'provenance.ENV_VARS = {\n\t"CLAUDECODE",\n\t"AI_AGENT",\n\t"CURSOR_AGENT",', 'provenance.ENV_VARS = {\n\t"CLAUDECODE",\n\t"AI_AGENT",', PV),
    # the rafting gate
    ('gate accepts every event', DSP, 'provenance.raftedProblem(old, new :: string, pid :: string, became)', 'provenance.publishProblem(old, new :: string, pid :: string, provenance.EVENTS)', DS),
    ('gate reads the record trimmed', DSP, 'local old, new = raw(base), raw(ref)', 'local old, new = show(base, path), show(ref, path)', DS),
    ('gate ignores the old rows', DSP, 'provenance.raftedProblem(old, new :: string, pid :: string, became)', 'provenance.raftedProblem(nil, new :: string, pid :: string, became)', DS),
    ('gate takes a record of an issue that is not in the backlog', DSP, 'elseif life ~= "" then\n\t\t\t\t\treturn `it changes {path}, an issue in {string.sub(life, 1, -2)}/: a rafting PR changes only a backlog issue\'s raft: line`\n\t\t\t\telseif path == `{r}/issues/{pid}/provenance.md` then', 'elseif rel == "provenance.md" then', DS),
    ('gate takes a raft record', DSP, 'if rel == "provenance.md" then\n\t\t\t\t\treturn `it changes {path}: a rafting PR does not write a raft', 'if false then\n\t\t\t\t\treturn `it changes {path}: a rafting PR does not write a raft', DS),
    ('gate takes any file in the issue folder', DSP, 'elseif path == `{r}/issues/{pid}/provenance.md` then', 'elseif string.find(path, `{r}/issues/{pid}/`, 1, true) then', DS),
]

def run(name, path, old, new, spec):
    f = Z + '/' + path
    text = open(f).read()
    if text.count(old) != 1:
        print('no match', name, text.count(old))
        return
    open(f, 'w').write(text.replace(old, new))
    try:
        r = subprocess.run([P + '/zn', 'run', '--time', '900', '--', 'bash', '-c', 'cd ' + Z + ' && lune run tests/run -- ' + spec],
                           capture_output=True, text=True)
        out = r.stdout + r.stderr
        killed = r.returncode != 0
        why = [l for l in out.splitlines() if 'FAIL' in l or 'expected' in l or 'error' in l.lower()][:2]
        print(('killed ' if killed else 'SURVIVED ') + name, '|', ' / '.join(w.strip()[:160] for w in why))
    finally:
        open(f, 'w').write(text)

# `python3 mutants.py slice:A:B` runs mutants A..B-1 (a ./zn run holds a command for at most an hour)
if len(sys.argv) == 2 and sys.argv[1].startswith('slice:'):
    _, a, b = sys.argv[1].split(':')
    for name, path, old, new, spec in M[int(a):int(b)]:
        run(name, path, old, new, spec)
else:
    want = set(sys.argv[1:])
    for name, path, old, new, spec in M:
        if not want or name in want:
            run(name, path, old, new, spec)
