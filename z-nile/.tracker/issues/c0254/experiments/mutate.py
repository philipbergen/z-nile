#!/usr/bin/env python3
# c0254 prep mutation check (revision 1: one mutant per Rules row): one mutant per Rules row, applied to the prototype worktree (proto-c0254), the row's spec file run,
# and the prototype put back with `git checkout`. A mutant counts as killed only when a case FAILs on an assertion (a message
# that starts "expected" or "<file> is missing/still says"), never on a syntax, require or type error.
# Run:  ./zn run --time 3000 -- python3 -I <this file> <proto worktree> <results file>
import re, subprocess, sys, hashlib

PROTO, OUT = sys.argv[1], sys.argv[2]
ONLY = set(sys.argv[3].split(',')) if len(sys.argv) > 3 else None  # optional: rerun only these row ids
Z = PROTO + "/z-nile"
ACC = ".tracker/issues/c0254/acceptance/"

# (row id, file, old text (must occur once), new text, spec, case fragment that must fail)
M = [
 ("R1a","engine/xhost.luau",'\tif after == nil then\n\t\treturn "failed"\n\tend\n','\tif after == nil then\n\t\treturn "lost"\n\tend\n',"pure","AC1: a failed claim that moved nothing"),
 ("R1b","engine/xhost.luau",'if after.state == before.state and after.status == before.status then','if false then',"pure","AC1: a failed claim that moved nothing"),
 ("R1c","engine/xhost.luau",'if after.stamp ~= "" and ((mine ~= "" and after.stamp == mine) or ours) then','if false then',"pure","AC1: a failed claim that moved nothing"),
 ("R1d","engine/xhost.luau",'if after.stamp ~= "" and ((mine ~= "" and after.stamp == mine) or ours) then','if after.stamp ~= "" and (mine ~= "" and after.stamp == mine) then',"pick","AC1: a claim whose commit carries this attempt's token"),
 ("R2a","engine/xhost.luau",'\t\tif seen.state == "backlog" and seen.status == "new" then\n\t\t\treturn "ok"\n\t\tend\n\t\treturn if mine ~= "" and seen.stamp == mine then "ok" else "taken"\n\telseif pick == "raft" then','\t\treturn "ok"\n\telseif pick == "raft" then',"pick","AC1: a draft pick is still ours"),
 ("R2b","engine/xhost.luau",'if seen.state == "backlog" and seen.status == "prepared" then\n\t\t\treturn "ok"\n\t\tend\n\t\treturn if mine','if true then\n\t\t\treturn "ok"\n\t\tend\n\t\treturn if mine',"pick","AC1: a raft pick is still ours"),
 ("R2c","engine/xhost.luau",'if raftedBy == nil or (mine ~= "" and raftedBy.stamp == mine) then','if true then',"pick","AC1: a rafting pick is taken"),
 ("R2d","engine/xhost.luau",'\tif not xhost.isClaim(seen.stamp) then\n\t\treturn true\n\tend\n\treturn seen.stamp == claim','\treturn true',"pick","AC1: a lost pick is left to the takeover"),
 ("R3a","engine/dispatch.luau",'\tif f.worker == true and f.taken ~= nil and f.taken ~= "" then','\tif false then',"pick","AC1: a pick another worker finished meanwhile"),
 ("R3b","engine/dispatch.luau",'if f.worker == true and f.status == "preparing" and not f.owned then','if false then',"pick","AC1: a worker\'s draft or raft that another worker holds"),
 ("R3c","engine/dispatch.luau",'(f.status == "preparing" and (f.worker == true or f.ownClaim))','(f.status == "preparing" and f.worker == true)',"pick","AC1: a plain dispatch of the same facts"),
 ("R3d","engine/dispatch.luau",'\tif f.worker == true and not f.owned then\n\t\tif f.pick == "lost" then','\tif false then\n\t\tif f.pick == "lost" then',"pick","AC1: a worker's draft or raft that another worker holds"),
 ("R3e","engine/dispatch.luau",'\t\tif f.pick == "lost" then\n\t\t\treturn { kind = "step", step = "z-stop", target = f.id }','\t\tif false then\n\t\t\treturn { kind = "step", step = "z-stop", target = f.id }',"pick","AC1: a lost pick is taken over"),
 ("R3f","engine/dispatch.luau",'\n\t\t\tf.worker == true\n\t\t\tand (f.status == "new" or','\n\t\t\t(f.status == "new" or',"pick","AC1: a plain dispatch of the same facts"),
 ("R4","engine/supervise.luau",'tripwire = 5, taken = 6, pushRefused = 7 }\n\nexport type Pick','tripwire = 5, taken = 7, pushRefused = 7 }\n\nexport type Pick',"pure","AC1: the dispatcher and the supervisor share one exit code"),
 ("R5","engine/supervise.luau",'\ttable.insert(args, "--pick")\n\ttable.insert(args, pick.kind)\n','',"pick","AC1: the supervisor passes the pick's kind"),
 ("R6","engine/workloop.luau",'\t\t\ttaken -= 1\n\t\t\tif lastLost == p.id then','\t\t\tif lastLost == p.id then',"pure","AC1: a lost race takes the next pick at once"),
 ("R7","engine/workloop.luau",'\t\t\tif lastLost == p.id then\n\t\t\t\tworld.sleep(world.idleSeconds or supervise.IDLE_SECONDS)\n\t\t\tend\n','',"pure","AC1: the same item lost twice in a row"),
 ("R8","engine/workloop.luau",'\t\tif r ~= "taken" then\n\t\t\tlastLost = ""','\t\tif false then\n\t\t\tlastLost = ""',"pick","AC1: lost, then another item, then lost again"),
 ("R9","engine/workloop.luau",'if result ~= "stopped" and result ~= "stop" then','if false then',"pick","AC1: a raft the previous run held"),
 ("R10","engine/dispatcher.luau",'if not CLAIM_STEPS[step] then\n\t\treturn "failed"\n\tend','if false then\n\t\treturn "failed"\n\tend',"pure","AC1: the dispatcher asks origin/main after a failed claim step"),
 ("R11","engine/dispatcher.luau",'return if by ~= nil and by.stamp ~= mine then "lost" else "failed"','return "failed"',"pick","AC1: a rafting step is lost only when"),
 ("R12","engine/dispatcher.luau",'token ~= nil and attempt ~= nil and token == attempt','false',"pick","AC1: a claim whose commit carries this attempt's token"),
 ("R13","engine/dispatcher.luau",'\telseif verdict == "lost" then\n\t\t\t\t\tprint(','\telseif false then\n\t\t\t\t\tprint(',"chain","AC1: a race lost between the pick and the claim step"),
 ("R14","engine/dispatcher.luau",'\t\t\t\t\tdispatcher.dropLostAttempt(st, ctx, prepDir, prepBranch)\n\t\t\t\t\tsave(st)\n\t\t\t\t\treturn dispatch.EXIT.taken','\t\t\t\t\tdispatcher.dropLostAttempt(st, ctx, prepDir, prepBranch)\n\t\t\t\t\tsave(st)\n\t\t\t\t\treturn dispatch.EXIT.failure',"chain","AC1: a race lost between the pick and the claim step"),
 ("R15","engine/dispatcher.luau",'\t\t\tprocess.exec("git", { "-C", mainRoot, "worktree", "remove", dir })\n','',"chain","AC1: a race lost between the pick and the claim step"),
 ("R16","engine/dispatcher.luau",'\ttable.remove(st.history)\n\tst.step','\tst.step',"pure","AC1: a lost claim leaves no failed step"),
 ("R17","engine/dispatcher.luau",'\tpcall(fs.writeFile, `{dir}/.cache/tracker-stamp-{target}`, stamp)\n','',"pick","AC1: a claim that landed is recorded"),
 ("R18","engine/dispatcher.luau",'\t\tclaimed = if worker.on and st.claim and st.claim.id == id then st.claim.stamp else nil,\n','',"chain","AC4, AC5: the claim step runs as the worker"),
 ("R19","engine/dispatch.luau",'if p.step == "z-design" and p.claimed and p.claimed ~= "" then','if false then',"pick","AC1: a z-design prompt of a worker's run"),
 ("R20","engine/main.luau",'\t\tand tf.status == H.stampMemory(t)\n','\t\tand false\n',"race","AC1: a claim this checkout already holds is an idempotent success"),
 ("R21","engine/main.luau",'if holder then\n\t\t\t\t\t\treturn `{id} is being rafted by {holder} on origin/main (another worker\'s claim): take another issue`','if false then\n\t\t\t\t\t\treturn `{id} is being rafted by {holder} on origin/main (another worker\'s claim): take another issue`',"race","AC1: two hosts rafting one approved issue"),
 ("R22","engine/xhost.luau",'if f.claim == "taken" then\n\t\treturn { action = "refuse", why = xhost.lostText(owner, f.originStamp) }','if false then\n\t\treturn { action = "refuse", why = xhost.lostText(owner, f.originStamp) }',"pure","AC2, AC3: a worker whose claim was taken over"),
 ("R23","engine/xhost.luau",'and f.copy == true\n','and f.copy == false\n',"pick","AC2: a numbered copy that holds no claim"),
 ("R24","engine/xhost.luau",'return `{head}: this checkout\'s work is no longer the claim\'s; stop here (./zn lost lists lost work to pick up)`','return `{head}: continue from the taker\'s push in a new worktree`',"pick","AC2: a lost worker is told c0274's own words"),
 ("R25","engine/main.luau",'if f.claim ~= "taken" and f.claim ~= "ended" then\n\t\treturn\n\tend','do\n\t\treturn\n\tend',"layer","AC2: host A's finish and restack are refused"),
 ("R26","engine/main.luau",'\t\t\t"--refmap=", -- no opportunistic update of refs/remotes/origin/<branch>, the ref finish and restack lease against\n','',"layer","AC2, AC3: host A's next commit stands"),
 ("R27","engine/main.luau",'\treturn rememberedClaim(id)\nend\n\n-- c0254 (Q3, Q5)','\treturn ""\nend\n\n-- c0254 (Q3, Q5)',"race","AC2, AC3: host A\'s next commit stands"),
 ("R28","engine/main.luau",'local f = `.cache/tracker-stamp-{id}`\n\tif fs.isFile(f) then','local f = `.cache/tracker-nothing-{id}`\n\tif fs.isFile(f) then',"layer","AC2, AC3: host A's next commit stands"),
 ("R29","engine/xhost.luau",'if f.originHas and (f.behind == nil or f.behind > 0) then','if f.originHas and (f.behind ~= nil and f.behind > 5) then',"pure","AC2, AC3: nothing is pushed over commits origin has"),
 ("R30","engine/xhost.luau",'\treturn { action = "push-new", why = "the first push of the branch sets its upstream" }','\treturn { action = "push", why = "the first push of the branch sets its upstream" }',"pure","AC3: every commit on a layer or prep branch is pushed"),
 ("R31","engine/xhost.luau",'if kind == "other" then\n\t\tif f.hasUpstream then','if kind == "other" then\n\t\tif true then',"pure","AC3: any other branch keeps today\'s rule"),
 ("R32","engine/xhost.luau",'elseif string.match(branch, "^prep%-[%w%-]+$") then','elseif false then',"pure","AC3: branch kinds"),
 ("R33","engine/main.luau",'for _, a in { "origin", `HEAD:{target}` } do','for _, a in {} do',"race","AC3: the push goes to the branch\'s own name"),
 ("R34","engine/main.luau",'return H.EXIT_PUSH_REFUSED','return 0',"race","AC3: a worker that still holds its claim does not push over commits"),
 ("R35","engine/main.luau",'return H.EXIT_PUSH_FAILED','return 0',"race","AC3: a push that fails exits 8"),
 ("R36","engine/main.luau",'\tif currentRaft() == nil and xhost.branchKind(sh.git({ "branch", "--show-current" })) == "prep" then','\tif false then',"race","AC3: host A's prep commits are pushed one by one"),
 ("R37","engine/main.luau",'\t\t\ttable.insert(args, "-u")\n','',"race","AC3: host A's prep commits are pushed one by one"),
 ("R38","engine/main.luau",'facts.behind = if n.ok then tonumber(sh.trim(n.stdout)) else nil\n\t\telse\n\t\t\tfacts.behind = nil','facts.behind = 0\n\t\telse\n\t\t\tfacts.behind = nil',"race","AC3: a worker that still holds its claim does not push over commits"),
 ("R39","engine/main.luau",'\t\t\tfacts.claim = heartbeat.holds(H.stampMemory(owner), facts.originStamp)','\t\t\tfacts.claim = "held"',"race","AC2, AC3: host A's next commit stands"),
 ("R40","engine/main.luau",'\t\t\tpcall(sh.writeReplacing, ".cache/push-refused", note)\n','',"chain","AC3: a push the session\'s own commit was refused"),
 ("R41","engine/dispatcher.luau",'\t\t\t\tif worker.on and st.worktree and fs.isFile(refusedFile) then','\t\t\t\tif false then',"chain","AC3: a push the session\'s own commit was refused"),
 ("R42","engine/xhost.luau",'if cli == nil or not string.match(cli, "^[%a][%w%-]*$") then','if true then',"pure","AC4: a worker\'s identity is its host, CLI and model"),
 ("R43","engine/costrow.luau",'if row.cli == nil and AUTHORING[row.phase] then','if row.cli == nil then',"spend","AC4: the environment names the CLI only for the authoring phases"),
 ("R44","engine/dispatcher.luau",'\t\t\t\tcli = a.cli,\n\t\t\t\tminutes = if reviewer','\t\t\t\tminutes = if reviewer',"chain","AC4, AC5: the claim step runs as the worker"),
 ("R45","engine/dispatcher.luau",'stepEnv = { ZN_CLI = who.cli, ZN_ATTEMPT = st.attempt :: string }','stepEnv = { ZN_CLI = "unknown", ZN_ATTEMPT = st.attempt :: string }',"chain","AC4, AC5: the claim step runs as the worker"),
 ("R46","engine/buffer.luau",'\tif row.host or row.cli then\n','\tif false then\n',"spend","AC4: a row with a host and a CLI is written"),
 ("R47","engine/buffer.luau",'if raw ~= buffer.HEADER and raw ~= buffer.HEADER_WHO then','if raw ~= buffer.HEADER_WHO then',"spend","AC4: a file with the old header still reads"),
 ("R48","engine/costrow.luau",'row.host = row.host or who.host','row.host = who.host',"spend","AC4: a row that already says its host"),
 ("R49","engine/buffer.luau",'\tif line.cli then\n\t\ttable.insert(cells, cell(line.cli))','\tif false then\n\t\ttable.insert(cells, cell(line.cli))',"spend","AC4: a line a dispatched step wrote carries"),
 ("R50","engine/xhost.luau",'if stamps[h.id] == h.stamp and out[h.id] == nil'.replace('if ','if h and ',1),'if h and out[h.id] == nil',"pure","AC5: the Worker trailer round-trips"),
 ("R51","engine/xhost.luau",'and out[h.id] == nil then','then',"pure","AC5: the Worker trailer round-trips"),
 ("R52","engine/work.luau",'local worker = if r.worker ~= nil and r.worker ~= "" then ` worker {r.worker}` else ""','local worker = ""',"pure","AC5: ./zn work status names the worker"),
 ("R53","engine/main.luau",'\t\t\t\treturn H.withWorkers(`tracker: new raft {chosen} {slug}`, carriers, claim)','\t\t\t\treturn `tracker: new raft {chosen} {slug}`',"race","AC5: the rafting claim names its worker too"),
 ("R54","engine/main.luau",'table.insert(lines, xhost.trailer(id, stampValue, who, attempt))','table.insert(lines, xhost.trailer(id, stampValue, who))',"race","AC5: the claim commit says who made it"),
 ("R55","engine/board.luau",'\t\t\theld = heldOf[i.id],\n','',"race","AC5: the claim commit says who made it"),
 ("R56","engine/heartbeat.luau",'\t\tif held == "held" then\n\t\t\treturn false\n\t\telseif held == "taken" or held == "ended" then\n\t\t\tover = true','\t\tif false then\n\t\t\treturn false\n\t\telseif held == "taken" or held == "ended" then\n\t\t\tover = true',"pick","AC2, AC7: staleMember is c0277's rule"),
 ("R57","engine/main.luau",'remembered ~= ""\n\t\t\t\tand heartbeat.staleMember(','false\n\t\t\t\tand heartbeat.staleMember(',"race","AC7: host A\'s sync marks its worktrees"),
 ("R58","engine/main.luau",'\t\t\tlocal alive = current ~= nil\n','\t\t\tlocal alive = false\n',"race","AC7: a discarded worktree is kept while the taker's claim lives"),
 ("R59","engine/main.luau",'if files or commits > 0 then','if files then',"race","AC7: when the work ends"),
 ("R60","engine/main.luau",'\t\t\t\telseif remove then\n','\t\t\t\telseif false then\n',"race","AC7: when the work ends"),
 ("R61","engine/main.luau",'\t\t\t\tg({ "merge", "--ff-only", "--quiet", `origin/{branch}` })\n','',"race","AC2: host B\'s stale worktree"),
 ("R62","engine/main.luau",'\t\tif g({ "merge-base", "--is-ancestor", mine.stdout, tip }).ok then','\t\tif true then',"race","AC2: a local branch that has diverged"),
 ("R63","README.md",'The push is the lock: a lost race means taking the next raft.','The push is the lock: a lost race means taking the next item.',"docs","AC6: the claim paragraph follows the raft claim"),
 ("R64","README.md",'*exists* (c0254) (the claim itself *exists*)','*exists* (c0254)',"docs","AC6: the done c0264"),
 ("R65","skills/zz-rules/SKILL.md",'`claim` (`./zn status <id> preparing`, in the issue\'s prep worktree; worker mode only, c0254), ','',"docs","AC6: zz-rules says a prep commit is pushed"),
 ("R67","engine/dispatcher.luau",'{if cli\n\t\tthen ` --cli {cli}`\n\t\telse ""}','',"pick","AC4: a code review\'s record line"),
 ("R66","skills/z-design/SKILL.md",'**Commit as you go**','**Commit once**',"docs","AC6: z-design commits as it goes"),
]

def sh(args, cwd, timeout=900):
    return subprocess.run(args, cwd=cwd, capture_output=True, text=True, timeout=timeout)

res = []
for rid, f, old, new, spec, frag in M:
    if ONLY and rid not in ONLY:
        continue
    path = f"{Z}/{f}"
    src = open(path).read()
    n = src.count(old)
    if n != 1:
        res.append(f"{rid}\tNOT APPLIED\t{f}: old text occurs {n} times")
        continue
    mutated = src.replace(old, new, 1)
    open(path, "w").write(mutated)
    h = hashlib.sha256(mutated.encode()).hexdigest()[:12]
    try:
        r = sh(["lune", "run", "tests/run", "--", ACC + spec + ".spec.luau"], Z)
        text = r.stdout + r.stderr
    finally:
        sh(["git", "checkout", "--", f"z-nile/{f}"], PROTO)
    fails = [l for l in text.splitlines() if l.startswith("FAIL") and frag in l]
    detail = ""
    killed = False
    if fails:
        i = text.splitlines().index(fails[0])
        msg = text.splitlines()[i + 1].strip() if i + 1 < len(text.splitlines()) else ""
        detail = msg[:170]
        killed = bool(re.search(r"expected|is missing|still says|lacks", msg)) and not re.search(r"attempt to|Requested module|syntax|TypeError|unexpected symbol", msg)
    res.append(f"{rid}\t{'KILLED' if killed else 'SURVIVED' if not fails else 'NOT-ASSERTION'}\t{f}\tsha256:{h}\t{spec}::{frag}\t{detail}")
open(OUT, "w").write("\n".join(res) + "\n")
print("\n".join(res))
