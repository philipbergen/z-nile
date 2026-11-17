#!/usr/bin/env python3
# The mutants of c0252's Rules table: `python3 -I mutate.py <id>` applies one to the checkout it is run in (exactly one
# occurrence of the old text, or the second when `occ` says so); `--check` verifies every old text is found.
import sys
E='z-nile/engine/'
LC=E+'landcheck.luau'
M={
 'M01':(LC,'''add(
				problem(
					"ci-failed",
					"redo",''','''add(
				problem(
					"ci-failed",
					"block",''',1),
 'M02':(LC,'if PASSED[c.state] then','if PASSED[c.state] or c.state == "" then',1),
 'M03':(LC,'local PASSED = { SUCCESS = true, NEUTRAL = true, SKIPPED = true }','local PASSED = { SUCCESS = true, NEUTRAL = true }',1),
 'M04':(LC,'elseif pr.head ~= i.topTip then','elseif false then',1),
 'M05':(LC,'elseif pr.state == "CLOSED" or pr.state == "MERGED" then','elseif false then',1),
 'M06':(E+'landread.luau','if trackerstate.judge({ e }, roots, false) ~= nil then','if true then',1),
 'M07':(LC,'if landcheck.touchesGame(i.codePaths, i.gameRoots) and not i.cicd then','if false then',1),
 'M08':(LC,'function landcheck.selfGating(codePaths: { string }): string?\n','function landcheck.selfGating(codePaths: { string }): string?\n\tif true then\n\t\treturn nil\n\tend\n',1),
 'M09':(LC,'if firstBlock then','if false then',1),
 'M10':(LC,'if tries >= cap then','if tries > cap then',1),
 'M11':(LC,'return { action = "wait", problems = ps }','return { action = "land", problems = ps }',1),
 'M12':(LC,'return type(kind) == "string" and KINDS[kind] == true','return true',1),
 'M13':(LC,'return if prevSignature == signature then spent else 0','return spent',1),
 'M14':(LC,'\treturn "retry"\nend','\treturn "amend-design"\nend',1),
 'M15':(LC,'return `- {decision}: {text}{if decision == recommend then " (recommended)" else ""}`','return `- {decision}: {text} (recommended)`',1),
 'M16':(LC,'''			if found then
				return nil, "two merges of the layer tip are on main since the mark"
			end''','''			if false then
				return nil, "two merges of the layer tip are on main since the mark"
			end''',1),
 'M17':(LC,'if #pr.checks == 0 then','if false then',1),
 'M18':(LC,'elseif pr.mergeable ~= "MERGEABLE" then','elseif false then',1),
 'M19':(LC,'if not pr.draft then','if true then',1),
 'M20':(LC,'elseif pr.state ~= "OPEN" then','elseif false then',1),
 'M21':(LC,'for _, u in i.unreadable do','for _, u in {} do',1),
 'M22':(LC,'table.insert(out, problem("full-gate-red", "redo", gate.red, "red-gate", nil))','table.insert(out, problem("full-gate-red", "wait", gate.red, "red-gate", nil))',1),
 'M23':(LC,'''			problem(
				"pr-unreadable",
				"wait",''','''			problem(
				"pr-unreadable",
				"redo",''',1),
 'M24':(LC,'\tSTARTUP_FAILURE = true,\n','',1),
 'M25':(LC,'''		else
			table.insert(pending, c.name)
		end''','''		end''',1),
 'M26':(LC,'''				"open-high",
				"block",''','''				"open-high",
				"redo",''',1),
 'M27':(E+'landread.luau','if type(pr.headRefOid) ~= "string" or pr.headRefOid == "" then','if false then',1),
 'M28':(E+'landread.luau','mergeable = tostring(pr.mergeable or "UNKNOWN"),','mergeable = tostring(pr.mergeable or "MERGEABLE"),',1),
 'M29':(E+'dispatch.luau','if not table.find(f.autoMerge, "run") then','if false then',2),
 'M30':(E+'dispatch.luau','\t\t\t\tredo = true,\n','\t\t\t\tredo = false,\n',1),
 'M31':(E+'dispatch.luau','if l and l.action == "land" and l.through then','if false then',1),
 'M32':(E+'dispatch.luau','if l and l.action == "land" and l.through then','if l and l.action ~= "block" and l.through then',1),
 'M33':(E+'dispatch.luau','if l and l.action == "wait" then','if false then',1),
 'M34':(E+'dispatch.luau','if f.layered ~= true and f.pr and f.pr.state == "OPEN" and not f.pr.draft then','if false then',1),
 'M35':(E+'dispatch.luau','if f.layered ~= true and f.pr and f.pr.state == "OPEN" and not f.pr.draft then','if f.pr and f.pr.state == "OPEN" and not f.pr.draft then',1),
 'M36':(E+'models.luau','models.GATES = { "prep", "raft", "run" }','models.GATES = { "prep", "raft" }',1),
 'M37':(E+'models.luau','models.MERGE_RETRIES = 2','models.MERGE_RETRIES = 3',1),
 'M38':(E+'models.luau','or not table.find(models.GATES, g) then','or false then',1),
 'M39':(E+'dispatch.luau','["z-land"] = { kind = "script", argv = { "done", "{id}" }, where = "run" }','["z-land"] = { kind = "script", argv = { "done", "{id}" }, where = "worktree" }',1),
 'M40':(E+'dispatch.luau','["z-gate"] = { kind = "script", argv = { "land-gate", "{id}" }, where = "run" }','["z-gate"] = { kind = "script", argv = { "land-gate", "{id}" }, where = "worktree" }',1),
 'M41':(E+'dispatch.luau','if p.rerun and #p.rerun > 0 then','if false then',1),
 'M42':(E+'models.luau','models.MERGE_RERUN_CAP = 10','models.MERGE_RERUN_CAP = 11',1),
 'M43':(E+'main.luau','if (process.env.ZN_DISPATCH or "") ~= "" or (process.env.ZN_HEADLESS or "") ~= "" then','if (process.env.ZN_DISPATCH or "") ~= "" then',1),
 'M44':(E+'main.luau','if not own[p.code] and (github or not pullRequest) then','if false then',1),
 'M45':(E+'main.luau','''	if #problems > 0 then
		process.exit(1)
	end
end''','''	if false then
		process.exit(1)
	end
end''',1),
 'M46':(E+'main.luau','\t\tthrough = prev\n','\t\tthrough = nil\n',1),
 'M47':(E+'main.luau','if #layergit.layersOf(raft.id) == 0 then','if false then',1),
 'M48':(E+'main.luau','fs.writeFile(`{stateDir}/block-note.md`, noteText)\n','',1),
 'M49':(E+'main.luau','''	if isRaft and runFrom == "active" and (process.env.ZN_DISPATCH or "") ~= "" then''','''	if false then''',1),
 'M50':(E+'dispatcher.luau','guard.mark = fresh\n\treturn nil\nend\n\n-- The state file note','return nil\nend\n\n-- The state file note',1),
 'M51':(E+'dispatcher.luau','local after = vet(bind[1], fresh :: string)','local after = nil',1),
 'M52':(E+'dispatcher.luau','local at, why = landcheck.findBind(chain, tip or "")','local at, why = 1, nil',1),
 'M53':(E+'dispatcher.luau','''		r = process.exec(`{ctx.mainRoot()}/zn`, withDir, {''','''		r = process.exec(`{dir}/zn`, args, {''',1),
 'M54':(E+'dispatcher.luau','local _, out, err = znBase(ctx.mainRoot(), wt, args, true)','local _, out, err = zn(wt, args, true)',1),
 'M55':(LC,'''landcheck.SELF_GATING = {
	"zn",
	"z-nile/check.sh",''','''landcheck.SELF_GATING = {
	"znz",
	"z-nile/check.shz",''',1),
 'M56':(E+'main.luau','if not landcheck.touchesGame(input.codePaths, input.gameRoots) then','if true then',1),
 'M57':(E+'dispatcher.luau','if st.gateOk ~= action.tip then','if false then',1),
 'M58':(E+'main.luau','if string.find(said, "lease", 1, true) or string.find(said, "publish", 1, true) then','if false then',1),
 'M59':(E+'dispatcher.luau','if gateCode == 0 then','if gateCode >= 0 then',1),
 'M60':(E+'dispatcher.luau','local spent = landcheck.repeats(st.landSig, st.landTries or 0, sig)','local spent = st.landTries or 0',1),
 'M61':(E+'dispatcher.luau','if req.tip then','if false then',1),
 'M62':(E+'dispatcher.luau','if fs.isFile(kept) then','if false then',1),
 'M63':(E+'dispatcher.luau','''		layered = false
		for line in string.gmatch''','''		layered = true
		for line in string.gmatch''',1),
 'M64':(E+'main.luau','''	if onto == nil or tip == nil or onto ~= layergit.mainTip() then
		return onto
	end''','''	if true then
		return onto
	end''',1),
 'M65':(E+'dispatcher.luau','local function noAnswer(text: string)','local function noAnswer0(text: string)',0),
 'M66':('zn','if [[ -n $against && "$(git -C "$here" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" != "$(git -C "$top" rev-parse --path-format=absolute --git-common-dir)" ]]; then','if false; then',1),
 'M67':('z-nile/README.md','once a person has approved its design','once its design is approved',1),
 'M68':('z-nile/README.md','| the dispatcher lands a green stack | c0252 | exists |','| the dispatcher lands a green stack | c0252 | captured |',1),
 'M69':('z-nile/skills/zz-rules/SKILL.md',"with the base's engine (the main checkout's, run as `./zn -C <worktree> …`, never the stack's own `zn`)","with the main checkout's engine",1),
 'M70':('z-nile/skills/z-run/SKILL.md','Never run `./zn done`: it is refused here, and when your work is done you stop','Never run `./zn done`: it is refused here, and when your work is done you stop (z-run only)',1),
 'M71':(E+'dispatcher.luau','local verdict = landcheck.classify(ps, spent, cap)','local verdict = landcheck.classify(ps, 0, cap)',1),
 'M73':(E+'dispatch.luau','\t\tand f.blockRequest == nil\n','',1),
 'M72':(E+'dispatcher.luau','if not okj or type(j) ~= "table" then\n\t\treturn noAnswer(out .. err)','if not okj or type(j) ~= "table" then\n\t\treturn true, nil, req',1),
 'M90':(LC,'''				frontier.CODE,
				"review",''','''				frontier.CODE,
				"redo",''',1),
 'M91':(LC,'if not i.frontier.met then','if false then',1),
 'M92':(LC,'''	if firstReview then
		return { action = "review", problems = ps }
	end''','''	if false then
		return { action = "review", problems = ps }
	end''',1),
 'M93':(LC,'''	if firstRedo then
		if tries >= cap then''','''	if firstReview then
		return { action = "review", problems = ps }
	end
	if firstRedo then
		if tries >= cap then''',1),
 'M94':(LC,'if p.kind == "block" and not firstBlock then','if (p.kind == "block" or p.kind == "review") and not firstBlock then',1),
 'M95':(LC,'''	if not ran then
		return ps
	end''','''	if true then
		return ps
	end''',1),
 'M96':(LC,'''				reason = "needs-decision",
				layer = p.layer,''','''				reason = "review-exhausted",
				layer = p.layer,''',1),
 'M97':(E+'dispatch.luau','''local function reviewAction(f: Facts, l: LandFacts): Action
	if not table.find(f.autoMerge, "run") then''','''local function reviewAction(f: Facts, l: LandFacts): Action
	if false then''',1),
 'M98':(E+'dispatch.luau','if l and l.action == "review" then','if false then',1),
 'M99':(E+'dispatch.luau','elseif l.action == "review" then','elseif false then',1),
 'M100':(E+'dispatcher.luau','ps = landcheck.afterRound(ps, tip == fr.from or tip == fr.after)','ps = ps',1),
 'M101':(E+'dispatcher.luau','st.frontierRan = { through = action.through or "", from = action.tip or "" }','st.frontierRan = nil',1),
 'M102':(E+'dispatcher.luau','if ended == "waiting" or st.outcome == "waiting" then','if false then',1),
 'M103':(E+'dispatcher.luau','''			if action.through then
				ro["--through"] = { action.through :: string }''','''			if false then
				ro["--through"] = { action.through :: string }''',1),
 'M104':(E+'dispatcher.luau','local committed = dispatcher.scriptStep(ctx, st, "z-commit", id, commitArgs)','local committed = "ok"',1),
 'M105':(E+'main.luau','''	local floor =
		require("./reviewfiles").frontierVerdict(floorDirs, models.frontier(models.walk(".", raft.dir)))''','''	local floor = { met = true, listed = {} }''',1),
 'M106':(E+'main.luau','''		if table.find(bindIds, m.id) then
			table.insert(floorDirs, m.dir)''','''		if true then
			table.insert(floorDirs, m.dir)''',1),
}
def main():
    mid=sys.argv[1]
    if mid=='--check':
        bad=0
        for k,(f,old,new,occ) in M.items():
            if occ==0: continue
            n=open(f).read().count(old)
            if (occ==1 and n!=1) or (occ>1 and n<occ):
                print('BAD',k,f,n); bad+=1
        print('checked',len(M),'bad',bad); return 1 if bad else 0
    if mid not in M: print('no',mid); return 2
    f,old,new,occ=M[mid]
    if occ==0: print('skip'); return 3
    s=open(f).read()
    if occ==1:
        assert s.count(old)==1,(mid,s.count(old))
        s=s.replace(old,new,1)
    else:
        idx=-1
        for _ in range(occ): idx=s.find(old,idx+1)
        assert idx>=0,(mid,)
        s=s[:idx]+new+s[idx+len(old):]
    open(f,'w').write(s)
    print('applied',mid,f)
    return 0
sys.exit(main())
