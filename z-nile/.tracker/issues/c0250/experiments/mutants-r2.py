import subprocess, sys, os, time
W='/Users/philipbergen/code/pickman/.worktree/proto-c0250-r2'
Z=W+'/z-nile'
A='.tracker/issues/c0250/acceptance/'
OUT='/private/tmp/claude-501/-Users-philipbergen-code-pickman/d810cee1-2a54-48c7-85af-0839e7c5c119/scratchpad/mut250/results2.txt'
def rd(p): return open(p).read()
db=rd(Z+'/'+A+'dispatch-block.spec.luau').replace('[roles.design-challenge]','[roles.raft]\nmodel = "claude-opus-5-5"\ncli = "claude"\nruntime = "claude-cli"\nrank = 3\nmax_tokens = 5000\neffort = "high"\nfallbacks = []\n\n[roles.design-challenge]',1)
open(Z+'/'+A+'zmut-db.spec.luau','w').write(db)
br=rd(Z+'/'+A+'block-resolve.spec.luau').replace('znOk(dir, { "block", raft, reason })','znOk(dir, { "block", raft, reason, "--layer", layerIssue })',1)
open(Z+'/'+A+'zmut-br.spec.luau','w').write(br)
D='z-nile/engine/dispatcher.luau'; M='z-nile/engine/main.luau'; DP='z-nile/engine/dispatch.luau'
mutants=[
('1 retry --answer lets blocked through',D,'			if blockedItem then\n				return refuse(','			if blockedItem and not answer then\n				return refuse(','zmut-db'),
('2 old rule: questions.md on an item fails',D,'	elseif not (zAsked and #zMade > 0) then','	elseif not nested and id ~= "" and id ~= "new" and fs.isFile(`{stateDir}/questions.md`) then\n		exProblem = "old rule: questions.md on an item"\n	elseif not (zAsked and #zMade > 0) then','zmut-db'),
('3 resolution copy skipped',D,'	local note, sha, holder = uncarried(ctx, st, id)\n	if not note then\n		return nil, false\n	end','	local note, sha, holder = uncarried(ctx, st, id)\n	if true then\n		return nil, false\n	end','zmut-db'),
('4 questions.md left waiting after a block',D,'if not why and (fs.isFile(qf) or isLink(qf)) then','if false then','zmut-db'),
('5 nested stop drops c0256 words',D,'`this step needs the user, and only the step that started it can ask:','`this step needs the user:','zmut-db'),
('7 copy only when exchange ends in note question',D,'	if not ours then\n		local resumes','	if false then\n		local resumes','zmut-db'),
('8 one-step on blocked item starts nothing',D,'			local o, holder = blocker(ctx, id)\n			if o then\n				local reason','			local o, holder = blocker(ctx, id)\n			if false and o then\n				local reason','zmut-db'),
('9 carry only in chain and retry',D,'	if id ~= "" and id ~= "new" then\n		local carryWhy','	if id ~= "" and id ~= "new" and st.mode == "chain" then\n		local carryWhy','zmut-db'),
('10 waiting c0256 question blocks the carry',D,'	local note, sha, holder = uncarried(ctx, st, id)\n	if not note then\n		return nil, false\n	end','	local note, sha, holder = uncarried(ctx, st, id)\n	if not note or fs.isFile(`{st.dir}/questions.md`) then\n		return nil, false\n	end','zmut-db'),
('13 resumeStep gives z-ready for a raft',DP,'	if f.kind == "raft" then\n		return "z-run"','	if f.kind == "raft" then\n		return "z-ready"','zmut-db'),
('14 blockCommand names the issue',DP,'		return `./zn block {raft} {reason} --layer {id}`','		return `./zn block {id} {reason}`','zmut-db'),
('15 re-run prompt from history',D,'local exLastStep = if st.rerunCarried','local exLastStep = if false','zmut-db'),
('16 facts read the issue only',D,'	if store.isIssueId(id) and not (o and o.state == "done") then\n		local r = ctx.listedBy(id)\n		if r and r.status == "blocked" then','	if false then\n		local r = ctx.listedBy(id)\n		if r and r.status == "blocked" then','zmut-db'),
('18 superseded uses WITHDRAWN words',D,'exchangeAdd(st, "answer", escalation.SUPERSEDED)','exchangeAdd(st, "answer", exchange.WITHDRAWN)','zmut-db'),
('22 raft note carried twice',D,'				if st.carried ~= sha then','				if st.carried ~= sha or c ~= o then','zmut-db'),
('12 lowest member taken as Layer',M,'		elseif #candidates >= 2 then','		elseif false then','zmut-br'),
('19 refusal exits 2',M,'	stdio.ewrite(msg .. "\\n")\n	return process.exit(1)','	stdio.ewrite(msg .. "\\n")\n	return process.exit(2)','zmut-br'),
('20 Layer written for a draft raft',M,'		layer = layer,\n		actor = actor,','		layer = layer or id,\n		actor = actor,','zmut-br'),
('21 Layer from current branch',M,'		else\n			layer = candidates[1]\n		end','		else\n			local cur = stack.parse(sh.git({ "branch", "--show-current" }))\n			layer = if cur and table.find(candidates, cur.issue) then cur.issue else candidates[1]\n		end','zmut-br'),
('11 raft questions.md no longer stops',"z-nile/engine/work.luau",'	if r.blocked ~= nil or r.questions then\n		return false\n	end','	if r.blocked ~= nil then\n		return false\n	end','work-board'),
('17 workread never fills blocked',"z-nile/engine/workread.luau",'blocked = if statusLib.effective(front, at.state) == "blocked" then (front.blocked or "") else nil,','blocked = nil,','work-board'),
('6 review-exhausted names a round count',"z-nile/skills/zz-rules/SKILL.md",'A finding still open when no further review round may run is a block with reason `review-exhausted`','After the one review round, a finding still open when no further review round may run is a block with reason `review-exhausted`','docs'),
]
only=sys.argv[1:]
specs={'zmut-db':A+'zmut-db.spec.luau','zmut-br':A+'zmut-br.spec.luau','work-board':A+'work-board.spec.luau','docs':A+'docs.spec.luau'}
log=open(OUT,'a')
try:
  for name,f,old,new,spec in mutants:
    if only and name.split()[0] not in only: continue
    p=W+'/'+f
    src=rd(p)
    if src.count(old)!=1:
        log.write(f'## {name}: ANCHOR count={src.count(old)} (not applied)\n'); log.flush(); continue
    open(p,'w').write(src.replace(old,new))
    t0=time.time()
    try:
        r=subprocess.run(['../zn','run','--time','900','--','lune','run','tests/run','--',specs[spec]],cwd=Z,capture_output=True,text=True,timeout=1000)
        out=r.stdout+r.stderr
    finally:
        open(p,'w').write(src)
    lines=[l[:330] for l in out.splitlines() if l.startswith('FAIL') or 'passed' in l or 'rror' in l[:80]]
    log.write(f'## {name} [{spec}] {int(time.time()-t0)}s\n'+'\n'.join(lines[:8])+'\n'); log.flush()
finally:
  for s in ('zmut-db','zmut-br'):
    try: os.remove(Z+'/'+A+s+'.spec.luau')
    except: pass
  log.write('## done\n'); log.close()
