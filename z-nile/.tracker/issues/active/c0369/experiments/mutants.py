"""Mutation check for c0369: MUT_WT=<a throwaway copy of the prototype> python3 mutants.py ["<mutant id>" ...]

MUT_WT is required: a worktree or clone of proto-c0369-landed (origin/main after f0399 landed, with this change, no c0283) that holds this issue's specs in
z-nile/.tracker/issues/c0369/acceptance and nothing worth keeping. Each entry replaces one text there, runs the row's
spec and restores the file (also when the run is stopped by a signal). A mutant is killed when the run fails; the
output line says on what. An entry whose text is not found exactly once, or that survives, exits non-zero.
Run it bounded: MUT_WT=... [MUT_SHARD=k/n] ./zn run --time 3500 -- python3 <this file>"""
import os
import signal
import subprocess
import sys

P = os.environ.get('MUT_WT', '')
Z = P + '/z-nile'
A = '.tracker/issues/c0369/acceptance/'
PL, DC = A + 'place.spec.luau', A + 'docs.spec.luau'
AM, AB = A + 'approve-main.spec.luau', A + 'approve-branch.spec.luau'
AR = (AM, AB)  # an engine mutant runs both fixture specs
ARF = A + 'approve-raft.spec.luau'
PLACE, MAIN, APPROVAL = 'engine/approveplace.luau', 'engine/main.luau', 'engine/approval.luau'
RULES, DESIGN, READY = 'skills/zz-rules/SKILL.md', 'skills/z-design/SKILL.md', 'skills/z-ready/SKILL.md'
LAYERGIT, WORK, EXEC = 'engine/layergit.luau', 'engine/work.luau', 'skills/zz-execute/SKILL.md'
LAND = 'tests/acceptance/f0399/land.spec.luau'  # narrowed by this issue's Overrides line
TOOL_AP, TOOL_PUB = 'tests/tooling/approve.spec.luau', 'tests/tooling/approve-publish.spec.luau'
TO_MAIN = 'if not publishOnly and main and main.ready and main.state ~= "holds" then'
M = [
    ("place: a worktree that holds main's own design is taken", PLACE, 'if main and main.ready and main.hash == hash then', 'if false then', PL),
    ('place: a worktree that is only behind main is taken', PLACE, 'return w.base ~= hash and not w.landed', 'return not w.landed', PL),
    ('place: a prep that already merged is taken', PLACE, 'return w.base ~= hash and not w.landed', 'return w.base ~= hash', PL),
    ('place: a draft in a worktree is taken', PLACE, 'if not w.copy.ready or hash == nil then', 'if hash == nil then', PL),
    ("place: main's unapproved design wins over a worktree's own", PLACE, 'if not publishOnly and #waiting > 0 then', 'if not publishOnly and #waiting > 0 and not (main and main.ready) then', PL),
    ('place: the prep wins over the worktree the command runs in', PLACE, 'return if w.here then 3 elseif w.prep then 2', 'return if w.here then 1 elseif w.prep then 2', PL),
    ('place: an approved worktree is approved again', PLACE, 'if mine and w.copy.state ~= "holds" then', 'if mine then', PL),
    ('place: --publish records a new approval in a worktree', PLACE, 'if not publishOnly and #waiting > 0 then', 'if #waiting > 0 then', PL),
    ("place: --publish records a new approval of main's design", PLACE, TO_MAIN, 'if main and main.ready and main.state ~= "holds" then', PL),
    ("place: an approval held for main's design is recorded again", PLACE, 'elseif forMain(main, w) then', 'elseif false then', PL),
    ("place: an approval held for main's approved design is published again", PLACE, '\t\tand main.state ~= "holds"\n', '\t\tand true\n', PL),
    ("place: a record of a design that is nobody's is retried", PLACE, 'elseif mine and w.copy.state == "holds" then', 'elseif w.copy.state == "holds" then', PL),
    ('place: a pushed approval is retried', PLACE, 'table.insert(if w.pushed then pushed else recorded, w)', 'table.insert(recorded, w)', PL),
    ('place: an approved main is approved again', PLACE, TO_MAIN, 'if not publishOnly and main and main.ready then', PL),
    ('place: a draft on main is approved', PLACE, TO_MAIN, 'if not publishOnly and main and main.state ~= "holds" then', PL),
    ('approve: it records in the checkout it runs in', MAIN, '\t\tif target ~= top then\n', '\t\tif false then\n', AR),
    ('approve: nothing is published after recording', MAIN, 'print(`approved {id} {hash} in {where}`)\n\tif hasOrigin() then', 'print(`approved {id} {hash} in {where}`)\n\tif false then', AR),
    ('approve: a draft on main with the same text takes the approval', MAIN, 'if not doc or frontOf(doc).design ~= "ready" then', 'if not doc then', AR),
    ("approve: the command's worktree stays after publishing", MAIN, 'if ran.ok and target == scratch and detached then', 'if false then', AR),
    ("approve: the command's worktree is removed after a failed publish", MAIN, 'if ran.ok and target == scratch and detached then', 'if target == scratch and detached then', AR),
    ('approve: a taken worktree path is reused', MAIN, 'if not detached or not dirty.ok or sh.trim(dirty.stdout) ~= "" then', 'if false then', AR),
    ('approve: a failed push is reported as done', MAIN, '\t\t\tif not pushed.ok then\n\t\t\t\tnotYet(', '\t\t\tif false then\n\t\t\t\tnotYet(', AR),
    ('approve: a failed publish is reported as done', MAIN, '\t\tif not result.ok then\n\t\t\tnotYet(', '\t\tif false then\n\t\t\tnotYet(', AR),
    ('approve: --publish does not look for the record', MAIN, 'places.choose(id, mainCopy, seen, publishOnly)', 'places.choose(id, mainCopy, seen, false)', AR),
    ('approve: a held approval is recorded a second time', MAIN, '\t\t\tif not chosen.record then\n', '\t\t\tif false then\n', AR),
    ('approve: publishing off is ignored', MAIN, '\t\tif not publishing() then\n\t\t\tnotYet(', '\t\tif false then\n\t\t\tnotYet(', AR),
    ('approve: ZN_APPROVE_IN skips the refusals', MAIN, '\tlocal onlyCheck = opts["--check"] ~= nil\n\tif not onlyCheck then', '\tlocal onlyCheck = opts["--check"] ~= nil\n\tif not onlyCheck and (process.env.ZN_APPROVE_IN or "") == "" then', AR),
    ('approve: a placed run records in the main checkout', MAIN, '\t\trefuseInMainCheckout("approve")\n', '\t\tlocal _ = refuseInMainCheckout\n', AR),
    ("approve: the worktree's whole approval.md replaces main's", MAIN, 'return { { path = path, content = contract.render(rows) } }', 'return { { path = path, content = localText } }', AR),
    ('approve: the place is not said', MAIN, '"approving in" else "publishing from"', '"" else ""', AR),
    ('load: the history of main is not read', PLACE, 'w.landed = held(path, (string.gsub(base, "%s+$", "")), id, copy.hash :: string)', 'w.landed = false', AR),
    ('load: the merge-base is not read', PLACE, 'w.base = if at and at.ready then at.hash else nil', 'w.base = nil', AR),
    ("load: a draft at the merge-base counts as main's design", PLACE, 'w.base = if at and at.ready then at.hash else nil', 'w.base = if at then at.hash else nil', AR),
    ('load: a pushed branch is not seen', PLACE, 'w.pushed = theirs ~= nil and theirs == git(path, { "rev-parse", "HEAD" })', 'w.pushed = false', AR),
    ('load: every worktree is read', PLACE, 'if i > 1 and (prep or raft or path == here or path == scratch) and fs.isDir(path) then', 'if i > 1 and fs.isDir(path) then', AR),
    ('load: the prep branch is not looked for', PLACE, 'local prep = slug ~= "" and tree.branch == `prep-{slug}`', 'local prep = false', AR),
    ("place: main's older design is approved behind a pushed prep", PLACE, '\tif #pushed > 0 then\n\t\tlocal name', '\tif false then\n\t\tlocal name', (PL, AB)),
    ('approve: a branch with no remote is pushed', MAIN, 'if name ~= `prep-{item.slug}` and not known.ok then', 'if false then', AB),
    ('approve: a moved branch is force-pushed', MAIN, 'local pushed = sh.run("git", { "push", "-q", "origin", `HEAD:refs/heads/{name}` })', 'local pushed = sh.run("git", { "push", "-q", "--force", "origin", `HEAD:refs/heads/{name}` })', AB),
    ('approve: any ZN_APPROVE_IN skips placement', MAIN, 'process.env.ZN_APPROVE_IN ~= top then', '(process.env.ZN_APPROVE_IN or "") == "" then', AB),
    ('approve: the older-design note is dropped', MAIN, '"; origin/main\'s older design stays unapproved: that pull request replaces it"', '""', AB),
    ('docs: zz-rules forgets the push rule', RULES, 'Only the prep branch, or a branch already on origin, is pushed, and never forced', 'Every branch is pushed', DC),
    ('docs: the approve tooling spec approves through an unanswered terminal', TOOL_AP, 'local again = approve(nil)', 'local again = fixture.exec(wt, "script", { "-q", "/dev/null", "./zn", "approve", ID }, { env = {} })', DC),
    ('load: the raft worktree is not looked for', PLACE, 'local raft = raftName ~= "" and path == `{trees[1].path}/.worktree/{raftName}`', 'local raft = false', ARF),
    ('load: the raft worktree is read for an issue that is not active', PLACE, 'local raftName = if main and main.active and main.raft then main.raft else ""', 'local raftName = if main and main.raft then main.raft else ""', ARF),
    ('load: any worktree named like a raft is read', PLACE, 'local raft = raftName ~= "" and path == `{trees[1].path}/.worktree/{raftName}`', 'local raft = raftName ~= "" and string.match(path, "/%.worktree/R%d+$") ~= nil', ARF),
    ('atRev: an issue in active/ is not seen as active', PLACE, 'string.find(d.dir, "/issues/active/", 1, true) ~= nil', 'false', ARF),
    ('docs: zz-rules forgets the raft worktree', RULES, "its one place is its raft's worktree (`.worktree/<R-id>`)", "its one place is every worktree", DC),
    ('approve: an unparseable approval.md on main blocks the approval', MAIN, '\t\tand not contract.parse(fs.readFile(current))\n', '\t\tand false\n', AM),
    ('approve: a placed run records on no branch', MAIN, 'if process.env.ZN_APPROVE_IN == top and where ~= "a worktree of origin/main" then', 'if false then', ARF),
    ('approve: a layer branch is not pushed', MAIN, 'local layer = stack.parse(name)\n\t\t\tif layer then', 'local layer = stack.parse(name)\n\t\t\tif false then', (AB, ARF)),
    ('approve: an active issue is recorded on a lower layer', MAIN, 'if not topLayer or branch ~= topName then', 'if not topLayer then', ARF),
    ('approve: an active issue is recorded on a dirty tree', MAIN, 'if not status.ok or sh.trim(status.stdout) ~= "" then', 'if false then', ARF),
    ('approve: an active issue is published to origin/main', MAIN, 'if item.state == "active" then\n\t\t\tlocal raftId = store.readFront(item.doc).raft or ""', 'if false then\n\t\t\tlocal raftId = store.readFront(item.doc).raft or ""', ARF),
    ('place: an active issue is placed like a backlog one', PLACE, 'if main and main.active then', 'if false then', (PL, ARF)),
    ('place: an active issue with no raft worktree is recorded on origin/main', PLACE, '\t\tif main.state == "holds" then\n\t\t\treturn { kind = "approved", path = nil, name = "origin/main", record = false }, nil\n\t\tend\n\t\treturn nil,', '\t\tif true then\n\t\t\treturn { kind = "main", path = nil, name = "origin/main", record = true }, nil\n\t\tend\n\t\treturn nil,', PL),
    ('layergit: approval.md is not a post-finish path', LAYERGIT, 'for _, file in { "approval%.md", "guesses%.md" } do', 'for _, file in { "guesses%.md" } do', ARF),
    ('docs: zz-rules forgets the top-layer rule', RULES, "it records only when that worktree is on the raft's top layer with a clean tree", 'it records there', DC),
    ('load: the raft worktree is judged by its checkout, not the top layer', PLACE, 'local copy = if topRef', 'local copy = if false', ARF),
    ('docs: zz-rules still sends the person to a worktree', RULES, '| one command, with a terminal on stdin,', '| in the worktree where the design is, with a terminal on stdin,', DC),
    ('docs: zz-rules forgets the main checkout is never written', RULES, 'the main checkout is never written', 'the main checkout is rarely written', DC),
    ('docs: zz-rules forgets which worktrees are read', RULES, 'No other worktree is read, so a prototype or a copy is approved only by running the command inside it', 'Every worktree is read', DC),
    ('docs: zz-rules forgets the retry', RULES, '`./zn approve <id> --publish` retries it from anywhere', '`./zn approve <id> --publish` retries it', DC),
    ('docs: z-design still says this worktree', DESIGN, 'in a terminal of their own, from anywhere in the checkout: it finds this worktree, records the approval and pushes the branch', 'in a terminal of their own in this worktree', DC),
    ('docs: z-ready still says the prep worktree', READY, 'run by the human in a terminal, from anywhere in the checkout', 'run by the human in the prep worktree', DC),
    ('docs: the changed-contract refusal still names two commands', APPROVAL, 'Run ./zn approve {id} again.`', 'Run ./zn approve {id} again, then ./zn approve {id} --publish.`', DC),
    ('docs: the publish tooling spec carries no explainer page', TOOL_PUB, '[`{ISSUE}/explainer.html`] = page(doc()),', '', DC),
    ('docs: the approve tooling spec types no answer', TOOL_AP, 'local line = `yes y | script -q /dev/null sh -c', 'local line = `script -q /dev/null sh -c', DC),
    ('docs: the publish tooling spec walks two commands', TOOL_PUB, 'published {ID} to origin/main: it counts now', 'published', DC),
    ('docs: ready still names two commands', APPROVAL, 'run ./zn approve {id} in a terminal, from anywhere in the checkout. This is', 'run ./zn approve {id}, then ./zn approve {id} --publish, from the worktree that holds the design. This is', DC),
    ('docs: a refusal tells the person to go into a worktree', PLACE, 'run ./zn worktree {raftName}, then ./zn approve {id}`', 'cd into a worktree of {raftName}, then ./zn approve {id} inside the one you mean`', (DC, PL)),
    # the re-prep on landed f0399 (2026-11-17)
    ('atRev: guesses.md is not hashed', PLACE, '\t\t\t\treadycheck.specs(folder, promoted),\n\t\t\t\tfolder[guesses.FILE]\n', '\t\t\t\treadycheck.specs(folder, promoted)\n', AM),
    ('approve: a pushed active approval is said to wait for a pull request', MAIN, 'if mainCopy and mainCopy.active then', 'if false then', ARF),
    ('approve: --publish is refused for an issue in active/', MAIN, 'print(`{id} is approved in {chosen.name}: it lands with {mainCopy.raft or "its raft"}`)', 'fail(`{id} is active in {mainCopy.raft}: its approval lands with the raft`)', ARF),
    ('approve: the layer push prints the prep line', MAIN, 'print(`It lands with {layer.raft}: pushed to {name}, nothing to publish.`)', 'print(`pushed {name}: the approval counts when its pull request merges`)', (AB, ARF)),
    ('approve: the lower-layer refusal sends the person to cd', MAIN, "its top layer; the raft's worktree is on {onName}`", 'its top layer (cd "$(./zn worktree {raftId})")`', ARF),
    ("docs: work next's wait names the raft's worktree", WORK, 'from anywhere in the checkout ({table.concat(', 'in its worktree ({table.concat(', DC),
    ("docs: done's wait names this worktree", MAIN, 'The person runs ./zn approve <id> in a terminal, from anywhere in the checkout;', 'The person runs ./zn approve <id> in this worktree;', DC),
    ("docs: zz-execute sends the person to the raft's worktree", EXEC, "from anywhere in the checkout (it records in the raft's worktree, on its top layer, and pushes that layer)", "in the raft's worktree, on its top layer", DC),
    ('land: an active issue is published to origin/main (f0399 land.spec, narrowed)', MAIN, 'if item.state == "active" then\n\t\t\tlocal raftId = store.readFront(item.doc).raft or ""', 'if false then\n\t\t\tlocal raftId = store.readFront(item.doc).raft or ""', LAND),
    ("approve: an active issue's retry pushes the checked-out branch", MAIN, 'if onHere.ok then\n\t\t\t\tlocal pushed =', 'if onHere.ok then\n\t\t\t\tpushBranch()\n\t\t\t\tdo\n\t\t\t\t\treturn\n\t\t\t\tend\n\t\t\t\tlocal pushed =', ARF),
]

restore = None  # (path, text) of the file a mutant is in


def put_back(*_):
    if restore:
        open(restore[0], 'w').write(restore[1])


def stopped(signum, _frame):
    put_back()
    sys.exit(128 + signum)


def main() -> int:
    global restore
    if not P or not os.path.isdir(Z):
        print('MUT_WT must name a throwaway copy of the prototype')
        return 2
    dirty = subprocess.run(['git', '-C', P, 'status', '--porcelain'], capture_output=True, text=True, timeout=60)
    if dirty.returncode != 0 or dirty.stdout.strip():
        print('refusing: the prototype copy is dirty or unreadable: ' + P)
        return 2
    for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(sig, stopped)
    wanted = sys.argv[1:]
    # MUT_SHARD=k/n runs every n-th entry from the k-th (1-based), so n copies can run side by side
    shard = os.environ.get('MUT_SHARD', '1/1').split('/')
    k, n = int(shard[0]), int(shard[1])
    bad = 0
    for i, (name, rel, old, new, spec) in enumerate(M):
        if wanted and name not in wanted:
            continue
        if i % n != k - 1:
            continue
        path = os.path.normpath(Z + '/' + rel)
        text = open(path).read()
        if text.count(old) != 1:
            print('NOT APPLIED  ' + name + ' (' + str(text.count(old)) + ' matches)', flush=True)
            bad += 1
            continue
        restore = (path, text)
        open(path, 'w').write(text.replace(old, new))
        try:
            specs = list(spec) if isinstance(spec, tuple) else [spec]
            r = subprocess.run(['lune', 'run', 'tests/run', '--'] + specs, cwd=Z, capture_output=True, text=True, timeout=1500)
            out = r.stdout + r.stderr
        finally:
            put_back()
            restore = None
        if r.returncode == 0:
            print('SURVIVED     ' + name, flush=True)
            bad += 1
            continue
        why = ''
        lines = out.splitlines()
        for i, line in enumerate(lines):
            if line.startswith('FAIL') and ' :: ' in line:
                why = line.split(' :: ', 1)[1] + ' | ' + (lines[i + 1].strip()[-150:] if i + 1 < len(lines) else '')
                break
        print('killed       ' + name + '  <-  ' + (why or out.strip()[-200:]), flush=True)
    return 1 if bad else 0


sys.exit(main())
