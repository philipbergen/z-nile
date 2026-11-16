--!strict
-- c0252: the checks before a raft's stack (or its green prefix) lands, as one pure function over what the edge read
-- (landread.luau, `./zn land-check`): each failed check is a named problem, and the chain acts on the strictest kind.
-- `./zn done` and the dispatcher both call it, so a manual landing and the dispatcher's agree (one lander, Q5).
-- Pure (zz-arch): texts and numbers in, problems and verdicts out; nothing is read, run or written here.
local escalation = require("./escalation")

local landcheck = {}

-- wait: nothing for a worker to do (CI pending, no check registered yet, GitHub still computing, a read that failed, a
--   stack that changes the gate that would judge it): the chain stops at the gate (exit 4) and a later run looks again.
-- redo: a worker can fix it (a layer not complete, a review not answered, a stale trace, a red check, a head that is not
--   the tip): the chain runs the worker again, and after `cap` repeats of the same failure the raft blocks.
-- block: only a person can decide (an unruled high finding, approval drift, a closed pull request): escalate at once.
-- Anything else is read as a wait: the unguarded action (land) follows only an explicit "no problem" (zz-arch rule 7).
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
	codePaths: { string }, -- paths the bind changes that are not tracker state (landread.codePaths: trackerstate's rule)
	gameRoots: { string }, -- project homes whose game code needs the cicd publish (zz-rules Merging 3)
	cicd: boolean, -- ~/.config/pickman/cicd.toml exists
	unreadable: { Unreadable }, -- reads that failed (git, the registry): each is a wait, never a pass
	gate: { red: string?, wait: string? }?, -- the clean-clone full gate and cicd run before the landing (`land-gate`)
}
export type Unreadable = { code: string, text: string }

-- Paths whose change makes a stack its own judge: the gate's driver, the selector and the runner. The landing runs
-- these from the stack's own tree (the merged tree is what is gated), so a stack that changes them is a person's to land.
landcheck.SELF_GATING = {
	"zn",
	"z-nile/check.sh",
	"z-nile/affected.luau",
	"z-nile/specs.luau",
	"z-nile/tests/run.luau",
	"z-nile/lib/",
}

local function problem(code: string, kind: Kind, text: string, reason: string, layer: string?): Problem
	return { code = code, kind = kind, text = text, reason = reason, layer = layer }
end

-- Whether any of the bind's code paths (landread.codePaths: not tracker state) is inside a game home.
function landcheck.touchesGame(codePaths: { string }, gameRoots: { string }): boolean
	for _, p in codePaths do
		for _, root in gameRoots do
			if string.sub(p, 1, #root + 1) == root .. "/" then
				return true
			end
		end
	end
	return false
end

-- The first code path that is part of the gate's own driver, or nil.
function landcheck.selfGating(codePaths: { string }): string?
	for _, p in codePaths do
		for _, g in landcheck.SELF_GATING do
			if p == g or (string.sub(g, -1) == "/" and string.sub(p, 1, #g) == g) then
				return p
			end
		end
	end
	return nil
end

local FAILED = {
	FAILURE = true,
	ERROR = true,
	CANCELLED = true,
	TIMED_OUT = true,
	ACTION_REQUIRED = true,
	STARTUP_FAILURE = true,
}
local PASSED = { SUCCESS = true, NEUTRAL = true, SKIPPED = true }

-- "Green" on the top layer's head: no failed and no running check, SUCCESS, NEUTRAL and SKIPPED passing (a draft
-- layer's `deploy` workflow is skipped). A state this list does not know is running, never passed. Returns the failed
-- check names and the pending ones.
function landcheck.checks(checks: { Check }): ({ string }, { string })
	local failed: { string } = {}
	local pending: { string } = {}
	for _, c in checks do
		if PASSED[c.state] then
			continue
		elseif FAILED[c.state] then
			table.insert(failed, c.name)
		else
			table.insert(pending, c.name)
		end
	end
	return failed, pending
end

-- The problems of the clean-clone full gate and the cicd run (`./zn land-gate`), which the dispatcher remembers per tip:
-- a red run is a redo like any red check, a lease held or a publish failure is a wait.
function landcheck.gateProblems(gate: { red: string?, wait: string? }?): { Problem }
	local out: { Problem } = {}
	if gate and gate.red then
		table.insert(out, problem("full-gate-red", "redo", gate.red, "red-gate", nil))
	end
	if gate and gate.wait then
		table.insert(out, problem("full-gate-wait", "wait", gate.wait, "red-gate", nil))
	end
	return out
end

-- Every failed check of the landing, in the order a person reads them. Nothing here reads the world: an input that
-- could not be read is a problem the edge already named (fail closed).
function landcheck.problems(i: Input): { Problem }
	local out: { Problem } = {}
	local function add(p: Problem)
		table.insert(out, p)
	end
	for _, u in i.unreadable do
		add(problem(u.code, "wait", u.text, "red-gate", nil))
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
	local own = landcheck.selfGating(i.codePaths)
	if own then
		add(
			problem(
				"self-gating",
				"wait",
				`the stack changes {own}, part of the gate that would judge it: a person lands it (./zn done {i.raft})`,
				"needs-decision",
				nil
			)
		)
	end
	if landcheck.touchesGame(i.codePaths, i.gameRoots) and not i.cicd then
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
	for _, p in landcheck.gateProblems(i.gate) do
		add(p)
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
	elseif pr.state == "CLOSED" or pr.state == "MERGED" then
		add(
			problem(
				"pr-closed",
				"block",
				`the pull request of {i.topIssue} is {string.lower(pr.state)}, not open`,
				"needs-decision",
				i.topIssue
			)
		)
	elseif pr.state ~= "OPEN" then
		add(
			problem(
				"pr-state-unknown",
				"wait",
				`the pull request of {i.topIssue} reports the state "{pr.state}", which is not OPEN: nothing is landed on it`,
				"red-gate",
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
		if #pr.checks == 0 then
			add(
				problem(
					"ci-none",
					"wait",
					`no check is registered on {i.topIssue}'s head yet: an empty rollup is not a green one`,
					"red-gate",
					i.topIssue
				)
			)
		end
		local failed, pending = landcheck.checks(pr.checks)
		if #failed > 0 then
			add(
				problem(
					"ci-failed",
					"redo",
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
		-- a draft layer's mergeable is UNKNOWN for as long as it is a draft (done's merge onto main judges conflicts)
		if not pr.draft then
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
			elseif pr.mergeable ~= "MERGEABLE" then
				add(
					problem(
						"pr-mergeable-unknown",
						"wait",
						`GitHub has not said whether the pull request of {i.topIssue} merges ("{pr.mergeable}"): it is still computing it`,
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

local KINDS = { wait = true, redo = true, block = true }

-- What the chain does: land only when nothing failed; block at once on a block problem; run the worker again on a redo
-- problem until `cap` repeats of the same failure are spent, then block; otherwise wait. A kind this module does not
-- know is a wait. A redo outranks a wait (waiting on CI for a stack the worker must change is pointless), and a wait
-- never blocks.
function landcheck.classify(ps: { Problem }, tries: number, cap: number): Verdict
	if #ps == 0 then
		return { action = "land", problems = ps }
	end
	local firstBlock: Problem? = nil
	local firstRedo: Problem? = nil
	for _, p in ps do
		if p.kind == "block" and not firstBlock then
			firstBlock = p
		elseif p.kind == "redo" and not firstRedo then
			firstRedo = p
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
	return { action = "wait", problems = ps }
end

-- Whether a problem row (from `./zn land-check`) names a kind this module knows; the dispatcher turns any other row
-- into a wait.
function landcheck.knownKind(kind: any): boolean
	return type(kind) == "string" and KINDS[kind] == true
end

-- The failure a rerun is a repeat of: the codes and the top layer's tip. A worker that changes either has made progress
-- (a layer built, a trace redone), so its next failure is a new one and the count starts again.
function landcheck.signature(ps: { Problem }, topTip: string): string
	local codes: { string } = {}
	for _, p in ps do
		table.insert(codes, p.code)
	end
	table.sort(codes)
	return `{table.concat(codes, ",")}@{topTip}`
end

-- The repeats counted against `cap`: `spent` when the failure is the one the last rerun was for, else none.
function landcheck.repeats(prevSignature: string?, spent: number, signature: string): number
	return if prevSignature == signature then spent else 0
end

-- One line per problem, for a refusal or a stop.
function landcheck.lines(ps: { Problem }): { string }
	local out: { string } = {}
	for _, p in ps do
		table.insert(out, `{p.code} ({p.kind}): {p.text}`)
	end
	return out
end

-- The option a filed note recommends. Only a person's own ruling is `approve`; every other note recommends `retry`:
-- `amend-design` takes the Layer out of the raft and back to draft, the most expensive answer, and the dispatcher never
-- recommends it, and `abort` is the person's alone.
landcheck.RECOMMEND = { ["open-high"] = "approve", ["approval-drift"] = "approve" } :: { [string]: string }
function landcheck.recommended(ps: { Problem }): string
	for _, p in ps do
		local r = landcheck.RECOMMEND[p.code]
		if r then
			return r
		end
	end
	return "retry"
end

-- The escalation.md body the dispatcher files when a landing is blocked: the four sections escalation.parse requires
-- and exactly one recommended option.
function landcheck.escalation(ps: { Problem }, raft: string, layer: string?, tries: number): string
	local lines: { string } = {}
	local capped = false
	for _, p in ps do
		table.insert(lines, `- {p.code}: {p.text}`)
		if p.kind == "redo" then
			capped = true
		end
	end
	local recommend = landcheck.recommended(ps)
	local function option(decision: string, text: string): string
		return `- {decision}: {text}{if decision == recommend then " (recommended)" else ""}`
	end
	local body = {
		"## Question",
		`The dispatcher would not land {raft}{if layer then ` (layer {layer})` else ""}: {if capped
			then `the same check failed after {tries} repeat(s) of the worker`
			else "a check can only be decided by a person"}. What should it do?`,
		"",
		"## What was tried",
		`The dispatcher ran landcheck over {raft}'s published layers, their pull request and the tracker state. {if capped
			then `It ran the worker again {tries} time(s) for that failure and it stayed.`
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

-- The bind in a first-parent walk of `main` from its tip down to the guard's mark: `chain` lists the commits newest
-- first with their parents ({ sha, p1, p2? }). Exactly one commit whose second parent is `topTip` is the bind; nothing
-- else counts. Returns its index in `chain` and nil, or nil and why.
function landcheck.findBind(chain: { { string } }, topTip: string): (number?, string?)
	local found: number? = nil
	for idx, c in chain do
		if c[3] ~= nil and c[3] == topTip and topTip ~= "" then
			if found then
				return nil, "two merges of the layer tip are on main since the mark"
			end
			found = idx
		end
	end
	if not found then
		return nil, `no merge of {topTip} is on main's first-parent line since the guard's mark`
	end
	return found, nil
end

-- The block request a dispatched `./zn block` leaves for the dispatcher (G1): one `key: value` line each. `tip` is the
-- Layer's published tip, from which the dispatcher restores the note and the open findings when it files the block.
function landcheck.requestText(id: string, reason: string, layer: string?, tip: string?): string
	return `item: {id}\nreason: {reason}\nlayer: {layer or ""}\ntip: {tip or ""}\n`
end

export type Request = { item: string, reason: string, layer: string?, tip: string? }
function landcheck.parseRequest(text: string): Request?
	local item = string.match(text, "^item: ([^\n]+)\n")
	local reason = string.match(text, "\nreason: ([^\n]+)\n")
	local layer = string.match(text, "\nlayer: ([^\n]*)\n")
	local tip = string.match(text, "\ntip: ([^\n]*)\n")
	if not item or not reason or not table.find(escalation.REASONS, reason) then
		return nil
	end
	return {
		item = item,
		reason = reason,
		layer = if layer and layer ~= "" then layer else nil,
		tip = if tip and tip ~= "" then tip else nil,
	}
end

return landcheck
