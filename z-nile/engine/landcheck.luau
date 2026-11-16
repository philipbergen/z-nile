--!strict
-- c0252: the checks before a raft's stack (or its green prefix) lands, as one pure function over what the edge read
-- (landread.luau, `./zn land-check`): each failed check is a named problem, and the chain acts on the strictest kind.
-- `./zn done` and the dispatcher both call it, so a manual landing and the dispatcher's agree (one lander, Q5).
-- Pure (zz-arch): texts and numbers in, problems and verdicts out; nothing is read, run or written here.
local escalation = require("./escalation")

local landcheck = {}

-- wait: nothing for a worker to do (CI pending, GitHub still computing, an unreadable pull request): the chain stops
--   at the gate (exit 4) and a later run looks again.
-- redo: a worker can fix it (a layer not complete, a review not answered, a stale trace, main moved): the chain runs
--   the worker again, and after `cap` tries the problem blocks.
-- block: only a person can decide (CI failed on the head, an unruled high finding, approval drift): escalate at once.
export type Kind = "wait" | "redo" | "block"
export type Problem = {
	code: string,
	kind: Kind,
	text: string,
	reason: string, -- the escalation reason it files under when it blocks (escalation.REASONS)
	layer: string?, -- the issue the problem is about, when one
}
export type Check = { name: string, state: string } -- state: gh's conclusion or state, upper case ("" while running)
export type Pr = {
	state: string, -- OPEN, MERGED or CLOSED
	draft: boolean,
	head: string, -- the head commit gh reports
	mergeable: string, -- MERGEABLE, CONFLICTING or UNKNOWN
	checks: { Check },
}
export type Layer = { issue: string, incomplete: string? } -- `incomplete`: layergit.completeReason's text
export type Input = {
	raft: string,
	layers: { Layer }, -- the layers this landing binds, bottom first
	through: string?, -- the layer a prefix landing stops at (nil: the whole stack)
	topIssue: string, -- the last layer bound
	topTip: string, -- the published tip of that layer: what the bind lands
	pr: Pr?, -- the top layer's pull request; nil when gh could not read it
	prError: string?, -- why `pr` is nil
	reviewProblem: string?, -- main.luau's reviewProblem: the final review is not answered
	openHigh: { string }, -- ids of high findings with no ruling under `## Open to the human`
	traceProblems: { string }, -- `./zn trace --check`'s lines
	approvalDrift: string?, -- approval.refusal's text
	verdictMissing: boolean,
	codeMoved: { string }, -- paths main gained since the stack's base that are not tracker state (c0152)
	changedPaths: { string }, -- paths the bind changes
	gameRoots: { string }, -- project homes whose game code needs the cicd publish (zz-rules Merging 3)
	cicd: boolean, -- ~/.config/pickman/cicd.toml exists
}

local function problem(code: string, kind: Kind, text: string, reason: string, layer: string?): Problem
	return { code = code, kind = kind, text = text, reason = reason, layer = layer }
end

-- Whether a path is tracker state (an item's folder under a `.tracker/`), which main may gain during a run (c0152).
function landcheck.isTracker(path: string): boolean
	return string.match(path, "^%.tracker/") ~= nil or string.match(path, "^[^/]+/%.tracker/") ~= nil
end

-- Of the paths main gained, those that are code: not tracker state.
function landcheck.codeOf(paths: { string }): { string }
	local out: { string } = {}
	for _, p in paths do
		if p ~= "" and not landcheck.isTracker(p) then
			table.insert(out, p)
		end
	end
	return out
end

-- Whether any changed path is inside a game home that is not just its tracker (zz-rules Merging: game stacks need the
-- clean-clone full gate and the cicd publish).
function landcheck.touchesGame(paths: { string }, gameRoots: { string }): boolean
	for _, p in paths do
		for _, root in gameRoots do
			if string.sub(p, 1, #root + 1) == root .. "/" and not landcheck.isTracker(p) then
				return true
			end
		end
	end
	return false
end

-- "Green" on the top layer's head: no failed or pending check, a SKIPPED one counted as green (the deploy workflow
-- skips a draft). Returns the failed check names and the pending ones.
function landcheck.checks(checks: { Check }): ({ string }, { string })
	local failed: { string } = {}
	local pending: { string } = {}
	for _, c in checks do
		local s = c.state
		if s == "SUCCESS" or s == "NEUTRAL" or s == "SKIPPED" then
			continue
		elseif
			s == "FAILURE"
			or s == "ERROR"
			or s == "CANCELLED"
			or s == "TIMED_OUT"
			or s == "ACTION_REQUIRED"
		then
			table.insert(failed, c.name)
		else
			table.insert(pending, c.name)
		end
	end
	return failed, pending
end

-- Every failed check of the landing, in the order a person reads them. Nothing here reads the world: an input that
-- could not be read is a problem the edge already named (fail closed).
function landcheck.problems(i: Input): { Problem }
	local out: { Problem } = {}
	local function add(p: Problem)
		table.insert(out, p)
	end
	for _, l in i.layers do
		if l.incomplete then
			add(problem("layer-incomplete", "redo", `{l.issue}: {l.incomplete}`, "design-gap", l.issue))
		end
	end
	if i.verdictMissing then
		add(
			problem(
				"no-verdict",
				"redo",
				`{i.raft} has no Verdict line in its final review`,
				"review-exhausted",
				nil
			)
		)
	end
	if #i.openHigh > 0 then
		add(
			problem(
				"open-high",
				"block",
				`unruled high finding(s) under ## Open to the human: {table.concat(i.openHigh, ", ")}`,
				"review-exhausted",
				nil
			)
		)
	elseif i.reviewProblem then
		add(problem("review-open", "redo", i.reviewProblem, "review-exhausted", nil))
	end
	for _, line in i.traceProblems do
		add(problem("trace-stale", "redo", line, "review-exhausted", nil))
	end
	if i.approvalDrift then
		add(problem("approval-drift", "block", i.approvalDrift, "needs-decision", nil))
	end
	if #i.codeMoved > 0 then
		add(
			problem(
				"main-moved",
				"redo",
				`main gained code since the stack's base ({table.concat(i.codeMoved, ", ")}): ./zn restack {i.raft}, then the gate runs on the merged tree`,
				"red-gate",
				nil
			)
		)
	end
	if landcheck.touchesGame(i.changedPaths, i.gameRoots) and not i.cicd then
		add(
			problem(
				"cicd-missing",
				"wait",
				"the stack changes a game and ~/.config/pickman/cicd.toml is missing: the cicd publish cannot run on this machine",
				"needs-decision",
				nil
			)
		)
	end
	local pr = i.pr
	if not pr then
		add(
			problem(
				"pr-unreadable",
				"wait",
				`the pull request of {i.topIssue} could not be read ({i.prError or "gh gave nothing"}): nothing is landed on a state that was not read`,
				"red-gate",
				i.topIssue
			)
		)
	else
		if pr.state == "CLOSED" or pr.state == "MERGED" then
			add(
				problem(
					"pr-closed",
					"block",
					`the pull request of {i.topIssue} is {string.lower(pr.state)}, not open`,
					"needs-decision",
					i.topIssue
				)
			)
		elseif pr.head ~= i.topTip then
			add(
				problem(
					"pr-head-moved",
					"redo",
					`the pull request head {pr.head} is not the layer tip {i.topTip}: publish the layer ({i.topIssue}) and let CI look at it`,
					"red-gate",
					i.topIssue
				)
			)
		else
			local failed, pending = landcheck.checks(pr.checks)
			if #failed > 0 then
				add(
					problem(
						"ci-failed",
						"block",
						`CI failed on {i.topIssue}'s head {pr.head}: {table.concat(failed, ", ")}`,
						"red-gate",
						i.topIssue
					)
				)
			end
			if #pending > 0 then
				add(
					problem(
						"ci-pending",
						"wait",
						`CI is still running on {i.topIssue}'s head: {table.concat(pending, ", ")}`,
						"red-gate",
						i.topIssue
					)
				)
			end
			if pr.mergeable == "CONFLICTING" then
				add(
					problem(
						"pr-conflicting",
						"redo",
						`the pull request of {i.topIssue} conflicts with its base: ./zn restack {i.raft}`,
						"red-gate",
						i.topIssue
					)
				)
			end
		end
	end
	return out
end

export type Verdict = {
	action: "land" | "wait" | "redo" | "block",
	problems: { Problem },
	reason: string?, -- block: the escalation reason
	layer: string?, -- block: the Layer
}

-- What the chain does: land when nothing failed; block at once on a block problem; run the worker again on a redo
-- problem until `cap` tries are spent, then block; otherwise wait. A redo outranks a wait (waiting on CI for a stack
-- the worker must change is pointless), and a wait never blocks.
function landcheck.classify(ps: { Problem }, tries: number, cap: number): Verdict
	if #ps == 0 then
		return { action = "land", problems = ps }
	end
	local firstBlock: Problem? = nil
	local firstRedo: Problem? = nil
	local anyWait = false
	for _, p in ps do
		if p.kind == "block" and not firstBlock then
			firstBlock = p
		elseif p.kind == "redo" and not firstRedo then
			firstRedo = p
		elseif p.kind == "wait" then
			anyWait = true
		end
	end
	if firstBlock then
		return { action = "block", problems = ps, reason = firstBlock.reason, layer = firstBlock.layer }
	end
	if firstRedo then
		if tries >= cap then
			return { action = "block", problems = ps, reason = firstRedo.reason, layer = firstRedo.layer }
		end
		return { action = "redo", problems = ps }
	end
	return { action = if anyWait then "wait" else "land", problems = ps }
end

-- One line per problem, for a refusal or a stop.
function landcheck.lines(ps: { Problem }): { string }
	local out: { string } = {}
	for _, p in ps do
		table.insert(out, `{p.code} ({p.kind}): {p.text}`)
	end
	return out
end

-- The escalation.md body the dispatcher files when a landing is blocked: the four sections escalation.parse requires
-- and exactly one recommended option. A capped redo recommends `retry`; a red CI or a ruled-out item `amend-design`
-- or `approve`; the dispatcher never rules for the person.
function landcheck.escalation(ps: { Problem }, raft: string, layer: string?, tries: number): string
	local lines: { string } = {}
	local capped = false
	local needsRuling = false
	for _, p in ps do
		table.insert(lines, `- {p.code}: {p.text}`)
		if p.kind == "redo" then
			capped = true
		elseif p.code == "open-high" or p.code == "approval-drift" then
			needsRuling = true
		end
	end
	local recommend = if needsRuling then "approve" elseif capped then "retry" else "amend-design"
	local function option(decision: string, text: string): string
		return `- {decision}: {text}{if decision == recommend then " (recommended)" else ""}`
	end
	local body = {
		"## Question",
		`The dispatcher would not land {raft}{if layer then ` (layer {layer})` else ""}: {if capped
			then `the same check failed after {tries} tries of the worker`
			else "a check can only be decided by a person"}. What should it do?`,
		"",
		"## What was tried",
		`The dispatcher ran landcheck over {raft}'s published layers, their pull request and the tracker state. {if capped
			then `It ran the worker again {tries} time(s) and the problem stayed.`
			else "It stopped at the first problem that is not a worker's to fix."}`,
		"",
		"## Open findings or error",
		table.concat(lines, "\n"),
		"",
		"## Options",
		option("retry", "run the worker again for another round of fixes"),
		option("amend-design", "the design has to change to make the check pass"),
		option("approve", "accept the finding as it stands (a person rules on it)"),
		option("abort", "stop the raft"),
		"",
	}
	return table.concat(body, "\n")
end

-- Whether a main commit is the dispatcher's own bind of `topTip`: a merge whose second parent is that tip. The first
-- parent is vetted against the guard's mark by the caller (tracker state and pull request merges only).
function landcheck.ownBind(parents: { string }, topTip: string): boolean
	return #parents == 2 and topTip ~= "" and parents[2] == topTip
end

-- The block request a dispatched `./zn block` leaves for the dispatcher (G1): one `key: value` line each.
function landcheck.requestText(id: string, reason: string, layer: string?): string
	return `item: {id}\nreason: {reason}\nlayer: {layer or ""}\n`
end

export type Request = { item: string, reason: string, layer: string? }
function landcheck.parseRequest(text: string): Request?
	local item = string.match(text, "^item: ([^\n]+)\n")
	local reason = string.match(text, "\nreason: ([^\n]+)\n")
	local layer = string.match(text, "\nlayer: ([^\n]*)\n")
	if not item or not reason or not table.find(escalation.REASONS, reason) then
		return nil
	end
	return { item = item, reason = reason, layer = if layer and layer ~= "" then layer else nil }
end

return landcheck
