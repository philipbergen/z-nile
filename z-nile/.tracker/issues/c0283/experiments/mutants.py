"""Mutation check for c0283: python3 mutants.py ["<mutant name>" ...]

Each entry replaces one text in a copy of the prototype (proto-c0283, worktree proto-c0283-mut), runs the row's spec
through ./zn run --time, and restores the file. A mutant is killed when the run fails on an assertion."""
import subprocess
import sys

import os
P = os.environ.get('MUT_WT', '/Users/philipbergen/code/pickman/.worktree/proto-c0283-mut')
Z = P + '/z-nile'
A = 'tests/acceptance/c0283/'
AP, AR, FZ, DP, DC = A + 'approval.spec.luau', A + 'approve.spec.luau', A + 'freeze.spec.luau', A + 'dispatch.spec.luau', A + 'docs.spec.luau'
PRV, MAIN, DSP = 'engine/provenance.luau', 'engine/main.luau', 'engine/dispatch.luau'
M = [
    # the pure rules
    ('approval takes the first row', PRV, '\t\tif r.event == "approved" then\n\t\t\tnewest = r', '\t\tif r.event == "approved" and not newest then\n\t\t\tnewest = r', AP),
    ('approval matches any row', PRV, '\tif covered == hash then\n\t\treturn "current", covered', '\tfor _, r in rows do\n\t\tif r.event == "approved" and string.find(r.detail, hash, 1, true) then\n\t\t\treturn "current", hash\n\t\tend\n\tend\n\tif covered == hash then\n\t\treturn "current", covered', AP),
    ('a bare approved row approves', PRV, 'if covered == hash then', 'if covered == hash or covered == nil then', AP),
    ('exemptParse skips a bad line', PRV, 'return nil, `line {n} is not "<id> <12 hex>": {line}`', 'continue', AP),
    ('exemptParse accepts a repeated id', PRV, 'if out[id :: string] then', 'if false then', AP),
    ('no list enforces', PRV, '\tif exempt == nil then\n\t\treturn nil\n\tend', '\tif exempt == nil then\n\t\texempt = {}\n\tend', AP),
    ('a listed id passes after a redesign', PRV, '\tif listed == hash then\n\t\treturn nil\n\tend', '\tif listed then\n\t\treturn nil\n\tend', AP),
    ('an unapproved unlisted issue passes', PRV, '\treturn `{id} is prepared without an approval and is not on the frozen list: ./zn approve {id}`', '\treturn nil', AP),
    ('a stale approval passes the door', PRV, '\tif state == "stale" then\n\t\treturn `{id}\'s approval no longer', '\tif false then\n\t\treturn `{id}\'s approval no longer', AP),
    # approve
    ('approve: the commit is the agent\'s', MAIN, 'sh.must("git", { "commit", "-q", "-m", `tracker: approve {id}` })', 'sh.must("git", { "commit", "-q", "--author", "Agent <agent@example.invalid>", "-m", `tracker: approve {id}` })', AR),
    ('approve: no hash recorded', MAIN, '`design={hash}`', '"design="', AR),
    ('approve: changes outside the folder allowed', MAIN, 'if string.sub(path, 1, #folder + 1) ~= folder .. "/" then', 'if false then', AR),
    ('approve: agent session passes', MAIN, 'if provenance.hint(sessionEnv()).agent then\n\t\tlocal here', 'if false then\n\t\tlocal here', AR),
    ('approve: a dispatched step passes', MAIN, '\t\tZN_DISPATCH = process.env.ZN_DISPATCH,\n\t\tCLAUDE_EFFORT', '\t\tCLAUDE_EFFORT', AR),
    ('approve: a human-claiming ZN_ACTOR passes an agent session', MAIN, 'if provenance.hint(sessionEnv()).agent then\n\t\tlocal here', 'if provenance.hint(sessionEnv()).agent and not string.find(process.env.ZN_ACTOR or "", "^human:") then\n\t\tlocal here', AR),
    ('approve: the main checkout message comes first', MAIN, '\tif provenance.hint(sessionEnv()).agent then\n\t\tlocal here', '\trefuseInMainCheckout("approve")\n\tif provenance.hint(sessionEnv()).agent then\n\t\tlocal here', AR),
    ('approve: the actor is ZN_ACTOR', MAIN, 'local human = provenance.human(name :: string)', 'local human = if (process.env.ZN_ACTOR or "") ~= "" then process.env.ZN_ACTOR :: string else provenance.human(name :: string)', AR),
    ('approve: no identity allowed', MAIN, 'if not name or name == "" then\n\t\tfail(\n\t\t\t"approve needs', 'if false then\n\t\tfail(\n\t\t\t"approve needs', AR),
    ('approve: an unclaimed issue allowed', MAIN, 'if st ~= "preparing" then\n\t\tfail(\n\t\t\t`{id} is {st} on origin/main: approve takes', 'if false then\n\t\tfail(\n\t\t\t`{id} is {st} on origin/main: approve takes', AR),
    ('approve: a draft design allowed', MAIN, 'if store.readFront(issue.doc).design ~= "ready" then\n\t\tfail(`{id} is not design: ready here', 'if false then\n\t\tfail(`{id} is not design: ready here', AR),
    ('approve: main checkout allowed', MAIN, 'refuseInMainCheckout("approve")\n', '', AR),
    # status prepared
    ('prepared: no approval needed', MAIN, 'if store.isIssueId(t) then\n\t\t\t\t\tlocal rec = localItem.dir', 'if false then\n\t\t\t\t\tlocal rec = localItem.dir', AR),
    ('prepared: only an issue named alone is checked', MAIN, 'if store.isIssueId(t) then\n\t\t\t\t\tlocal rec = localItem.dir', 'if t == id and store.isIssueId(t) then\n\t\t\t\t\tlocal rec = localItem.dir', AR),
    ('prepared: a stale approval passes', MAIN, 'elseif state == "stale" then\n\t\t\t\t\t\treturn `{t} was redesigned since its approval', 'elseif false then\n\t\t\t\t\t\treturn `{t} was redesigned since its approval', AR),
    ('prepared: the hash omits check.sh', MAIN, 'local hash = raftplan.recordHash(t, gitFolderFiles(localItem.dir))\n\t\t\t\t\tlocal state, covered', 'local only: { [string]: string } = {}\n\t\t\t\t\tfor rel, text in gitFolderFiles(localItem.dir) do\n\t\t\t\t\t\tif rel ~= "check.sh" then\n\t\t\t\t\t\t\tonly[rel] = text\n\t\t\t\t\t\tend\n\t\t\t\t\tend\n\t\t\t\t\tlocal hash = raftplan.recordHash(t, only)\n\t\t\t\t\tlocal state, covered', AR),
    ('prepared: a dispatched step passes', MAIN, 'if (process.env.ZN_DISPATCH or "") ~= "" then\n\t\t\t\t\t\treturn `{t}: a dispatched', 'if false then\n\t\t\t\t\t\treturn `{t}: a dispatched', AR),
    ('prepared: the approval check comes before design ready', MAIN, 'if store.readFront(localItem.doc).design ~= "ready" then\n\t\t\t\t\treturn `{t} is not design: ready: set it (z-design) before status {id} prepared`\n\t\t\t\tend\n\t\t\t\t-- c0283', 'if false then\n\t\t\t\t\treturn `{t} is not design: ready: set it (z-design) before status {id} prepared`\n\t\t\t\tend\n\t\t\t\t-- c0283', AR),
    # doors
    ('new raft: no approval check', MAIN, '\t\t\t\t\tif st == "prepared" then\n\t\t\t\t\t\tlocal fault = approvalFault(', '\t\t\t\t\tif false then\n\t\t\t\t\t\tlocal fault = approvalFault(', AR),
    ('ready: no approval check', MAIN, '\t\t\t\t-- c0283: every member needs a current approval, or the frozen list at its design\n\t\t\t\tfor _, m in members do', '\t\t\t\t-- c0283: every member needs a current approval, or the frozen list at its design\n\t\t\t\tfor _, m in {} :: { store.Item } do', AR),
    ('raft-plan: plans the unapproved', MAIN, '\t\t\tif fault then\n\t\t\t\ttable.insert(unapproved, { id = it.id, reason = fault })\n\t\t\t\tcontinue\n\t\t\tend', '\t\t\tif fault then\n\t\t\t\ttable.insert(unapproved, { id = it.id, reason = fault })\n\t\t\tend', AR),
    ('raft-plan: skip as a command', MAIN, 'print(`skip {un.id}: {un.reason}`)', 'print(`./zn fold {un.id}`)', AR),
    ('audit: no unapproved error', MAIN, '\tif exemptText then\n\t\tfor _, it in store.all("issue") do', '\tif false then\n\t\tfor _, it in store.all("issue") do', AR),
    ('audit: the list read from the working tree', MAIN, '\tlocal exemptText = originText(EXEMPT)\n\tif exemptText then', '\tlocal exemptText = if fs.isFile(EXEMPT) then fs.readFile(EXEMPT) else nil\n\tif exemptText then', FZ),
    ('audit: an unlisted issue with no record passes', PRV, '\treturn `{id} is prepared without an approval and is not on the frozen list: ./zn approve {id}`', '\treturn nil', FZ),
    # freeze
    ('freeze: lists drafts', MAIN, '(it.state == "backlog" and st == "prepared")', '(it.state == "backlog")', FZ),
    ('freeze: lists done issues', MAIN, 'or (it.state == "active" and store.readFront(it.doc).design == "ready")\n\t\t', 'or it.state ~= "backlog"\n\t\t', FZ),
    ('freeze: skips the active', MAIN, 'or (it.state == "active" and store.readFront(it.doc).design == "ready")\n\t\t', '\n\t\t', FZ),
    ('freeze: overwrites a frozen list', MAIN, '\tif sh.run("git", { "cat-file", "-e", `origin/main:{EXEMPT}` }).ok then', '\tif false then', FZ),
    ('freeze: runs in the main checkout', MAIN, 'refuseInMainCheckout("provenance freeze")\n', '', FZ),
    # the dispatcher
    ('prep gate merges when auto_merge names it', DSP, '\t\tand name ~= "prep"\n', '', DP),
    ('prep reason replaced by one message', DSP, 'elseif\n\t\t\tnot table.find(f.autoMerge, name)\n\t\tthen `the {name} PR #{pr.number} waits for a merge', 'elseif\n\t\t\tfalse\n\t\tthen `the {name} PR #{pr.number} waits for a merge', DP),
    ('prep stop lacks the approve suffix', DSP, '\tif name == "prep" then\n\t\twhy ..=', '\tif false then\n\t\twhy ..=', DP),
    ('prep fallthrough keeps the old text', DSP, '\t\telseif name == "prep" then `the prep PR #{pr.number} waits for the user\'s approval and merge`\n', '', DP),
    ('fold: no approval check', MAIN, '\t\t\tlocal fault = approvalFault(\n\t\t\t\tid,\n\t\t\t\ttreeFolderFiles(paths, read, string.sub(p, 1, #p - #id - 4)),\n\t\t\t\texemptTextOnBase(read)\n\t\t\t)\n\t\t\tif fault then\n\t\t\t\treturn fault\n\t\t\tend', '', AR),
    ('fold: the list read from the working tree', MAIN, '\t\t\t\ttreeFolderFiles(paths, read, string.sub(p, 1, #p - #id - 4)),\n\t\t\t\texemptTextOnBase(read)', '\t\t\t\ttreeFolderFiles(paths, read, string.sub(p, 1, #p - #id - 4)),\n\t\t\t\t(if fs.isFile(EXEMPT) then fs.readFile(EXEMPT) else nil)', AR),
    ('new raft: the list read from the working tree', MAIN, '#path - #id - 4)),\n\t\t\t\t\t\t\texemptTextOnBase(read)', '#path - #id - 4)),\n\t\t\t\t\t\t\t(if fs.isFile(EXEMPT) then fs.readFile(EXEMPT) else nil)', AR),
    ('raft-plan: the list read from the working tree', MAIN, 'local unapproved: { { id: string, reason: string } } = {}\n\tlocal exemptText = exemptTextOnBase()', 'local unapproved: { { id: string, reason: string } } = {}\n\tlocal exemptText = if fs.isFile(EXEMPT) then fs.readFile(EXEMPT) else nil', AR),
    ('approve: --said dropped', MAIN, '\t\tdetail ..= `; said="{words}"`', '', AR),
    ('approve: unknown option allowed', MAIN, 'if k ~= "--said" then', 'if false then', AR),
    ('approve: hashes the index only', MAIN, 'local hash = raftplan.recordHash(id, gitFolderFiles(issue.dir))', 'local hash = raftplan.recordHash(id, gitFolderFiles(issue.dir, true))', AR),
    ('prepared: an uncommitted row passes', MAIN, 'if not tracked or not sh.run("git", { "diff", "--quiet", "HEAD", "--", rec }).ok then', 'if false then', AR),
    ('prepared: the refusal prints the hash a row needs', MAIN, '(it covered {covered})', '({covered} -> {hash})', AR),
    ('fixture.exec keeps the session markers (killed from an agent session only)', 'tests/lib/fixture.luau', '\t\tscrubbed[name] = ""', '\t\tscrubbed[name] = nil :: any', AR),
    ('fixtures keep the real list', 'tests/lib/engine.luau', '\t["provenance-exempt.txt"] = true,\n', '', FZ),
    ('list gone: not in force', MAIN, '\t\treturn ""\n\tend\n\treturn nil\nend', '\t\treturn nil\n\tend\n\treturn nil\nend', FZ),
    ('audit: a deleted list is silent', MAIN, 'if exemptText == "" and originText(EXEMPT) == nil then', 'if false then', FZ),
    ('an unparseable list passes the door', MAIN, "return `{id}: origin/main's {EXEMPT} does not parse: {why}`", 'return nil', FZ),
    ('freeze --check: ignores an extra entry', MAIN, 'if want[id] == nil then', 'if false then', FZ),
    ('freeze --check: ignores a wrong hash', MAIN, 'elseif (listed :: { [string]: string })[id] ~= hash then', 'elseif false then', FZ),
    ('freeze --check: ignores a missing entry', MAIN, 'if (listed :: { [string]: string })[id] == nil then', 'if false then', FZ),
    ('docs: the old dispatcher sentence stays', 'skills/z-design/SKILL.md', 'the dispatcher stops at the prep gate for the user, who approves the design and merges the PR (zz-rules, Design approval).', 'the dispatcher passes the gate (the user started it).', DC),
    ('docs: Landing lacks the merge-first rule', 'skills/zz-rules/SKILL.md', 'Before merging a prep PR, merge `origin/main`, rerun', 'Before merging a prep PR, rerun', DC),
    # the texts
    ('docs: zz-rules loses the agent-session refusal', 'skills/zz-rules/SKILL.md', '**It is refused in any agent session**', 'It is refused', DC),
    ('docs: z-design lets the reviewer approve', 'skills/z-design/SKILL.md', '**The design is approved by a human, never by you or the reviewer**', 'The design is approved by the reviewer', DC),
    ('docs: .models.toml still merges prep', '../.models.toml', 'auto_merge = ["raft"]', 'auto_merge = ["prep", "raft"]', DC),
    ('docs: usage lacks approve', MAIN, '  approve <id>  ', '  aprove <id>  ', DC),
    ('docs: AGENTS.md lets an agent try', '../AGENTS.md', 'Tell the user to run it; never try to', 'Run it yourself', DC),
]

def run(name, f, old, new, spec):
    path = f'{Z}/{f}'
    text = open(path).read()
    if text.count(old) != 1:
        return f'{name}: MUTANT DOES NOT APPLY ({text.count(old)} matches)'
    open(path, 'w').write(text.replace(old, new, 1))
    try:
        r = subprocess.run(['./zn', 'run', '--time', '900', '--', 'bash', '-c', f'cd z-nile && lune run tests/run -- {spec}'],
                           cwd=P, capture_output=True, text=True)
    finally:
        open(path, 'w').write(text)
    out = r.stdout + r.stderr
    last = [l for l in out.splitlines() if 'passed' in l][-1:] or ['(no result line)']
    killed = r.returncode != 0
    why = [l for l in out.splitlines() if l.startswith('     ')][:1]
    return f'{name}: {"KILLED" if killed else "SURVIVED"} {last[0]} {why[0][-170:] if why else ""}'

if __name__ == '__main__':
    args = sys.argv[1:]
    part = None
    if args and args[0].startswith('--part='):
        k, n = args[0][len('--part='):].split('/')
        part = (int(k), int(n))
        args = args[1:]
    for i, (name, f, old, new, spec) in enumerate(M):
        if args and name not in args:
            continue
        if part and i % part[1] != part[0] - 1:
            continue
        print(run(name, f, old, new, spec), flush=True)
