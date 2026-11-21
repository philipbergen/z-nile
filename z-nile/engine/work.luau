--!strict
-- What one worker does next. Pure over tracker facts the edge has already read. The skill carries none of
-- this order: `./zn work next` prints one line, and the worker does that one thing.
--
-- dispatch.next is a different decision and must stay one. It chooses the pipeline step from the
-- dispatcher's facts (the pull request, the last step's outcome, a tripwire, another terminal's claim).
-- An active raft stays on z-run until its run pull request leaves draft, and then stops for a human to
-- merge. It does not read layers. This function chooses the one action inside that z-run (implement,
-- finish, restack, review, trace, final-review, done) from the layer facts. It does not read the pull
-- request. One function for both would hide either the merge gate or which layer action the session does.
-- The shared facts agree: questions stop both, a done raft stops both, and a prepared backlog raft is
-- `ready` here and `z-ready` there. A spec fails when those diverge, or when an active raft's action
-- becomes the pipeline step (or the pipeline step becomes a layer action).
--
-- Left for later tickets, on purpose:
--   c0249: work.rankKey is the id. Rank replaces that key, and lost work is not taken first.
--   c0265: nothing beats while a raft is held. An unnamed session does not resume one, and does not take it over.
--   c0254: the holder is the author of the ready commit, not a worker identity, and two checkouts can be
--     told to build the same active raft if both name it.
--   A person who names no raft keeps taking the next claimable one. The folder ./zn was run from
--   is that project's tracker root (Input.scope); the checkout root, and any folder no project
--   holds, leaves scope empty and the next raft is any project's. Naming a raft ignores scope.
--   A named raft ends the session.
--   A supervisor that starts a fresh session is a later ticket. The skill counts releases in a row
--   and passes `released`; a stop commit does not name the session, so git cannot.
local work = {}

export type LayerFact = {
	position: number,
	issue: string,
	name: string,
	commits: number,
	onlyStart: boolean, -- the layer's only commit is `tracker: start`
	finished: boolean,
	-- c0248, both optional so a layer read without them behaves as before:
	landed: boolean?, -- its issue is in done/ on origin/main: an earlier bind landed it
	reviewReason: string?, -- a raft with `layers: reviewed`: "" when the layer is complete, else why not; nil: not read
	-- c0262: the ticket's final review (finalview.state): none, on-course, review-again, redo-design, redo-layer, blocked,
	-- invalid; read only for a finished layer whose ticket carries `final: ticket`. nil: not read (an unmarked ticket, or
	-- a fact built without it), and the layer is not held up by a review nobody asked for.
	finalState: string?,
}

export type RaftFact = {
	id: string,
	title: string,
	where: string, -- backlog, active, done
	status: string,
	designReady: boolean,
	depsMet: boolean,
	questions: boolean,
	blocked: string?, -- the reason, when the raft is blocked on origin/main (c0250): a human resolves it
	issues: { string },
	layers: { LayerFact },
	holder: string,
	since: string,
	stacked: boolean,
	codeReview: string, -- none, open, resolved
	finalReview: string, -- none, open, approved
	trace: boolean,
	traceOk: boolean,
	-- c0248: the raft carries `layers: reviewed`: each layer is reviewed in its own issue folder before the next
	-- starts (no raft-level code review), and each landing has its own trace (`traceName`) and final review
	marked: boolean?,
	traceName: string?, -- this landing's trace file (`trace-NNN.md`); nil: `trace.md`
	block: string?, -- "" when ready would accept. A reason when the reader has judged and ready would refuse.
	root: string, -- the project's tracker root, "pickman/.tracker". "" when the reader has not placed it.
	-- f0399, all optional so a raft read without them behaves as before:
	lands: boolean?, -- the raft document has `lands: approved`: done asks every member for an approval that holds
	on: string?, -- the raft it is built on (`on: R0100`)
	onLanded: boolean?, -- that raft is done
	unapproved: { string }?, -- "<id> (<why>)" per member whose approval does not hold; read once the final review is approved
	outside: { string }?, -- depends_on ids of its members that are not members
	blockOn: string?, -- as `block`, judged with the members of the one raft it could be built on taken as done
}

-- An issue as the unnamed session sees it (f0399). Only issues not in done/ are listed, so a dependency that is
-- not in the list has landed.
export type IssueFact = {
	id: string,
	root: string,
	status: string, -- effective: new, preparing, prepared, active, closed
	raft: string, -- "" when it is in none
	designReady: boolean,
	sized: boolean,
	deps: { string },
	draftBlock: string, -- "" when z-design's claim gate accepts it, else its reason
	added: boolean?, -- a c0394 added issue (`waits:`): never picked here
	mine: boolean?, -- preparing, and its prep worktree is in this checkout
}

-- Who carries an item now: the session that last asked `work next` for it, and how long ago (seconds).
export type Carrier = { session: string, age: number }

export type Input = {
	asked: string?,
	held: string?,
	author: string?, -- "Name <email>" of this checkout, the ready commit's author form
	released: number?, -- how many rafts this session has released in a row. The skill carries it.
	scope: string?, -- a project's tracker root. Nil or "" is every project (the checkout root).
	rafts: { RaftFact },
	issues: { IssueFact }?, -- f0399. Nil: the picks are the rafts' only.
	session: string?, -- this session's id. Nil or "" when it cannot be named: nothing held is resumed.
	carriers: { [string]: Carrier }?, -- by raft or issue id
}

-- A carrier that has not asked for this long is taken as gone (until c0265's heartbeat replaces this).
work.STALE = 6 * 3600

-- May this session resume a held item nobody named? Only a session that can be named, and only when no other
-- live session carries the item.
function work.free(id: string, input: Input): boolean
	if not input.session or input.session == "" then
		return false
	end
	local c = (input.carriers or {})[id]
	return c == nil or c.session == input.session or c.age > work.STALE
end

-- Two blocked releases in a row stop an unnamed session. The only place that number lives.
work.BLOCKED_IN_A_ROW = 2

function work.blockedWhy(): string
	return `{work.BLOCKED_IN_A_ROW} rafts in a row were released as blocked. Stop. This is more likely the worker or the tool than the rafts.`
end

-- c0249 replaces this key with a rank. Lowest key is first. Today the key is the id.
function work.rankKey(r: RaftFact): string
	return r.id
end

export type Decision = {
	raft: string,
	layer: string,
	ticket: string,
	action: string,
	why: string,
}

local function blank(action: string, why: string, raft: string?): Decision
	return { raft = raft or "", layer = "", ticket = "", action = action, why = why }
end

local function find(rafts: { RaftFact }, id: string): RaftFact?
	for _, r in rafts do
		if r.id == id then
			return r
		end
	end
	return nil
end

function work.claimable(r: RaftFact): boolean
	if r.blocked ~= nil or r.questions then
		return false
	end
	if r.block ~= nil then
		return r.block == ""
	end
	return r.where == "backlog" and r.status == "prepared" and r.designReady and r.depsMet and not r.questions
end

-- The rafts an unnamed session may see. A scope is one project's tracker root; nil or "" is every project.
function work.kept(rafts: { RaftFact }, scope: string?): { RaftFact }
	if not scope or scope == "" then
		return rafts
	end
	local out: { RaftFact } = {}
	for _, r in rafts do
		if r.root == scope then
			table.insert(out, r)
		end
	end
	return out
end

-- The folder name of a tracker root ("pickman" from "pickman/.tracker"), or "".
function work.scopeName(scope: string?): string
	if not scope or scope == "" then
		return ""
	end
	return string.match(scope, "^([^/]+)/") or scope
end

-- The next raft an unnamed session may take. One function. Lowest work.rankKey, which is the id until c0249.
function work.nextClaimable(rafts: { RaftFact }): RaftFact?
	local best: RaftFact? = nil
	for _, r in rafts do
		if work.claimable(r) and (not best or work.rankKey(r) < work.rankKey(best :: RaftFact)) then
			best = r
		end
	end
	return best
end

-- The first reason this raft is not offered. Nil when it is offered, or when it is already done.
function work.oneReason(r: RaftFact): string?
	if work.claimable(r) or r.where == "done" then
		return nil
	end
	if r.blocked ~= nil then
		return `is blocked ({r.blocked}): a human resolves it with ./zn resolve`
	end
	if r.block ~= nil and r.block ~= "" then
		return r.block
	end
	if r.where == "active" then
		if work.forRaft(r).action == "wait" and r.unapproved and #(r.unapproved :: { string }) > 0 then
			return `waits for approval: {table.concat(r.unapproved :: { string }, ", ")}`
		end
		return "is held"
	end
	if r.where == "backlog" then
		if r.blocked ~= nil then
			return `is blocked ({r.blocked}): a human resolves it with ./zn resolve`
		elseif r.questions then
			return "needs a human (questions.md)"
		elseif r.status ~= "prepared" or not r.designReady then
			return `is {r.status}, design not ready`
		elseif not r.depsMet then
			return "has a dependency that is not done"
		end
	end
	return `is {r.where}`
end

function work.skipped(rafts: { RaftFact }): { string }
	local lines: { string } = {}
	for _, r in rafts do
		local why = work.oneReason(r)
		if why then
			table.insert(lines, `{r.id}: {why}`)
		end
	end
	table.sort(lines)
	return lines
end

function work.whyNone(rafts: { RaftFact }): string
	local lines = work.skipped(rafts)
	if #lines == 0 then
		return "no claimable raft"
	end
	return table.concat(lines, "; ")
end

local function of(r: RaftFact, action: string, why: string, ticket: string, layer: LayerFact?): Decision
	return {
		raft = r.id,
		layer = if layer then `{layer.position} {layer.issue}` else "",
		ticket = ticket,
		action = action,
		why = why,
	}
end

local function layerAt(r: RaftFact, position: number, issue: string): LayerFact?
	for _, layer in r.layers do
		if layer.position == position and layer.issue == issue then
			return layer
		end
	end
	return nil
end

-- c0262: what a finished layer needs before its ticket is complete, by the ticket's final review state. A raft readied
-- with `layers: reviewed` lands the complete layers below a redesign or a block first (`done --through`); any other raft
-- lands whole (c0248 outcome 9: done refuses --through on it), so it is never told to.
function work.finalStep(r: RaftFact, issue: string, layer: LayerFact, state: string): Decision
	local below = layerAt(r, layer.position - 1, r.issues[layer.position - 1] or "")
	local belowComplete = below ~= nil
		and not below.landed
		and (below.finalState == nil or below.finalState == "on-course")
		and (below.reviewReason == nil or below.reviewReason == "")
	local landFirst = if r.marked
			and below ~= nil
			and belowComplete
		then `The layers below are complete: first land them with ./zn done {r.id} --through {below.issue}. `
		elseif r.marked then ""
		else `{r.id} has no layers: reviewed, so it lands whole: nothing lands before this. `
	local harvest =
		`Harvest each finding of that review into {issue}'s harvest.md (a lesson, or one-off: <reason>) first. `
	local function block(reason: string, question: string): string
		return `{landFirst}Write escalation.md in {r.id}'s folder: ## Question ({question}), ## What was tried, ## Open findings or error (its first line names the latest final-review-NNN.md, the one ./zn final {issue} names, then that review's findings verbatim) and ## Options (bullets that start with amend-design, retry, approve or abort; exactly one ends (recommended)). Then run ./zn block {r.id} {reason} --layer {issue} in {r.id}'s worktree, tell the person, and run ./zn work next again. Under ./zn dispatch do not run ./zn done. Do not review it again: the human resolves it with ./zn resolve, which leaves {r.id} prepared; it is readied again (z-ready; after an approve the person first re-approves the ticket with ./zn approve), then ./zn work next goes on.`
	end
	if state == "redo-design" then
		return of(
			r,
			"redesign",
			`{landFirst}{harvest}The final review of {issue} (final-review-NNN.md in its folder) found the design missed the ask. The ticket goes back to z-design: from the main checkout run ./zn stop {r.id}, ./zn unfold {r.id} {issue}, re-prep {issue} with z-design (copy its final-review-NNN.md files into its folder and read their gaps first), then z-raft and z-ready it again. Ask again.`,
			issue,
			layer
		)
	elseif state == "redo-layer" then
		return of(
			r,
			"rebuild",
			`{harvest}The final review of {issue} (final-review-NNN.md in its folder) found the implementation missed the design. Rebuild {layer.name} against those gaps until ./zn check {issue} is green, run ./zn finish {issue}, then ask again. The review runs again; a second off-course verdict blocks the ticket.`,
			issue,
			layer
		)
	elseif state == "blocked" then
		return of(
			r,
			"blocked",
			`{harvest}{issue} was off course twice: no further review round may run, so it is blocked for the human (review-exhausted). {block(
				"review-exhausted",
				`whether {issue} delivers its ask despite both verdicts`
			)}`,
			issue,
			layer
		)
	elseif state == "invalid" then
		return of(
			r,
			"blocked",
			`A final review of {issue} cannot be read, or judged a view an off-course review had judged (./zn final {issue} says why). Do not guess a verdict. {block(
				"needs-decision",
				`what to do with {issue}'s unreadable review`
			)}`,
			issue,
			layer
		)
	end
	return of(
		r,
		"final-review-ticket",
		`Run the final review of {issue} (zz-review, final mode, on the ticket): ./zn dispatch zz-review {issue} --mode final. An agent never starts the reviewer itself (a subagent or CLI it starts carries this checkout's instructions); a person may instead start a CLI of their own in the folder ./zn final {issue} --view prints. Commit final-review-NNN.md in {issue}'s folder on {layer.name} (./zn commit --phase code-review), then ask again. The next layer starts after an on-course verdict.`,
		issue,
		layer
	)
end

-- The one next action for a raft this session already holds, or was named.
function work.forRaft(r: RaftFact): Decision
	if r.where == "done" then
		return of(
			r,
			"end",
			`{r.id} landed. Stop. Tell the person to start a fresh session (or /clear) and run z-work again.`,
			"",
			nil
		)
	end
	if r.blocked ~= nil then
		return of(
			r,
			"end",
			`{r.id} is blocked: start a fresh session. It needs a human ({r.blocked}): ./zn resolve {r.id} <decision>. Stop. Tell the person to start a fresh session (or /clear) and run z-work again.`,
			"",
			nil
		)
	end
	if r.questions and r.where == "backlog" then
		return of(
			r,
			"end",
			`{r.id} was released and needs a human (questions.md). Stop. Tell the person to start a fresh session (or /clear) and run z-work again.`,
			"",
			nil
		)
	end
	if r.questions and r.where == "active" then
		return of(
			r,
			"release",
			`questions.md is in {r.id}. From the main checkout run ./zn stop {r.id}, tell the person, then ask again.`,
			"",
			nil
		)
	end
	if r.where == "backlog" then
		if work.claimable(r) then
			return of(
				r,
				"ready",
				`{r.id} is prepared and ready would accept it. From the main checkout run ./zn ready {r.id}, then ask again.`,
				"",
				nil
			)
		end
		local why = if r.block ~= nil and r.block ~= ""
			then r.block
			elseif not r.designReady then `{r.id} is not design: ready`
			elseif r.status ~= "prepared" then `{r.id} is {r.status}, not prepared`
			else `{r.id} has a dependency that is not done`
		return of(r, "none", why, "", nil)
	end
	if r.where ~= "active" then
		return of(r, "none", `{r.id} is {r.where}: nothing to run`, "", nil)
	end
	if #r.issues == 0 then
		return of(r, "none", `{r.id} has no issues`, "", nil)
	end
	for i, issue in r.issues do
		local layer = layerAt(r, i, issue)
		if layer and layer.landed then
			continue
		end
		if not layer then
			return of(
				r,
				"implement",
				`{issue} has no layer yet. Run ./zn start {r.id} and ask again.`,
				issue,
				nil
			)
		end
		if not layer.finished then
			if layer.onlyStart or layer.commits == 0 then
				return of(
					r,
					"implement",
					`Build {issue} on {layer.name} until ./zn check {issue} is green, then ask again. Do not run ./zn finish yet.`,
					issue,
					layer
				)
			end
			return of(
				r,
				"finish",
				`Run ./zn finish {issue}. If the check is red, fix the code and run finish again. The same check failing after a real second attempt is blocked: land the green layers below with ./zn done {r.id} --through <issue>, write escalation.md in {r.id}'s folder, run ./zn block {r.id} <reason> in this worktree, tell the person, and ask again.`,
				issue,
				layer
			)
		end
		-- c0248: a layer is complete (finished, green and reviewed in its issue's folder) before the next one starts
		if layer.reviewReason ~= nil and layer.reviewReason ~= "" then
			return of(
				r,
				"review",
				`Review {issue}'s layer: run its code review (zz-review, code mode; the review is in {issue}'s folder; zz-execute Phase 4), or answer the open one, until it is complete, then ask again. Now: {layer.reviewReason}`,
				issue,
				layer
			)
		end
		-- c0262: a layer is complete only after its ticket's final review is on course, and the next layer
		-- starts after that.
		-- (c0248's review step above comes first: the ticket's final review is the last review)
		local state = layer.finalState
		if state ~= nil and state ~= "on-course" then
			return work.finalStep(r, issue, layer, state)
		end
	end
	if not r.stacked then
		return of(r, "restack", `Run ./zn restack {r.id}, then ask again.`, "", nil)
	end
	if not r.marked and r.codeReview == "none" then
		return of(
			r,
			"review",
			"Run the code review once (zz-review, code mode; zz-execute Phase 4). Commit the review file, then ask again.",
			"",
			nil
		)
	end
	if not r.marked and r.codeReview ~= "resolved" then
		return of(
			r,
			"review",
			"Answer the open code review (zz-execute Phase 4) until its verdict is approve, then ask again. Do not guess a ruling under ./zn dispatch; otherwise answer an open ruling with a recorded guess (./zn guess).",
			"",
			nil
		)
	end
	if not r.trace then
		return of(
			r,
			"trace",
			`Append and commit the final Verification log entries (zz-execute Phase 5 step 1), then run ./zn trace {r.id} and commit that skeleton as {r.traceName or "trace.md"} in {r.id}'s folder, then ask again.`,
			"",
			nil
		)
	end
	if r.finalReview ~= "approved" then
		return of(
			r,
			"final-review",
			`Run the final review (zz-execute Phase 5). It fills {r.traceName or "trace.md"} and writes final-review-NNN.md. Then ask again.`,
			"",
			nil
		)
	end
	if not r.traceOk then
		return of(
			r,
			"trace",
			`./zn trace {r.id} --check does not pass. Fix {r.traceName or "trace.md"}, then ask again.`,
			"",
			nil
		)
	end
	if r.unapproved and #(r.unapproved :: { string }) > 0 then
		local ids: { string } = {}
		for _, line in r.unapproved :: { string } do
			table.insert(ids, (string.match(line, "^(%S+)") or line) :: string)
		end
		return of(
			r,
			"wait",
			`{r.id} waits for the person: ./zn approve {table.concat(ids, ", ")} from anywhere in the checkout ({table.concat(
				r.unapproved :: { string },
				", "
			)}); ./zn guesses {r.id} lists what to review. Tell the person, then ask again with no raft.`,
			"",
			nil
		)
	end
	if r.on and r.on ~= "" and not r.onLanded then
		return of(
			r,
			"wait",
			`{r.id} is built on {r.on :: string}, which has not landed. Tell the person, then ask again with no raft.`,
			"",
			nil
		)
	end
	return of(r, "done", `Run ./zn done {r.id}. It lands the stack. Then ask again.`, "", nil)
end

-- f0399 -------------------------------------------------------------------------------------------------------

local function issueOf(issues: { IssueFact }, id: string): IssueFact?
	for _, i in issues do
		if i.id == id then
			return i
		end
	end
	return nil
end

-- The depends_on ids that have not landed: an id in the list (the list holds no done issue).
function work.unmet(deps: { string }, issues: { IssueFact }): { string }
	local out: { string } = {}
	for _, d in deps do
		if issueOf(issues, d) then
			table.insert(out, d)
		end
	end
	return out
end

local function allDesigned(ids: { string }, issues: { IssueFact }): string?
	for _, d in ids do
		local dep = issueOf(issues, d)
		if dep and not dep.designReady then
			return d
		end
	end
	return nil
end

local function everyLayerFinished(r: RaftFact): boolean
	if r.where ~= "active" or #r.issues == 0 then
		return false
	end
	for i, issue in r.issues do
		local layer = layerAt(r, i, issue)
		if not layer or not layer.finished then
			return false
		end
	end
	return true
end

-- The one unlanded raft `r` could be built on: active, every layer finished, holding every unmet outside
-- dependency. Nil and the first reason otherwise.
function work.baseFor(r: RaftFact, rafts: { RaftFact }, issues: { IssueFact }): (string?, string?)
	local unmet = work.unmet(r.outside or {}, issues)
	if #unmet == 0 then
		return nil, "has no unmet dependency"
	end
	local base: RaftFact? = nil
	for _, d in unmet do
		local holder: RaftFact? = nil
		for _, other in rafts do
			if other.where == "active" and table.find(other.issues, d) then
				holder = other
			end
		end
		if not holder then
			return nil, `depends on {d}, which is in no active raft with every layer finished`
		end
		if base and (base :: RaftFact).id ~= (holder :: RaftFact).id then
			return nil,
				`depends on {(base :: RaftFact).id} and {(holder :: RaftFact).id}: a raft is built on one raft`
		end
		base = holder
	end
	if not everyLayerFinished(base :: RaftFact) then
		return nil, `depends on {unmet[1]}, which is in no active raft with every layer finished`
	end
	return (base :: RaftFact).id, nil
end

local function readyOn(r: RaftFact): boolean
	if r.where ~= "backlog" or work.claimable(r) or r.blocked ~= nil then
		return false
	end
	if r.blockOn ~= nil then
		return r.blockOn == ""
	end
	return r.status == "prepared" and r.designReady and not r.questions
end

-- A backlog raft `ready` refuses for something a worker can repair: not a dependency, not questions.md, and not an
-- approved contract that changed (the person approves again).
function work.fixable(r: RaftFact): boolean
	return r.where == "backlog"
		and r.blocked == nil
		and r.status == "prepared"
		and not r.questions
		and r.depsMet
		and r.block ~= nil
		and r.block ~= ""
		and string.find(r.block :: string, "changed since approval", 1, true) == nil
end

-- Why a backlog issue in no raft is not picked, or nil when it is a pick. `tier` 1 asks for nothing unmet.
local function issuePick(
	i: IssueFact,
	issues: { IssueFact },
	tier: number,
	free: boolean?
): (string?, string?)
	if i.raft ~= "" or i.added or i.status == "closed" or i.status == "active" then
		return nil, nil -- not this function's: a raft's member, an added issue, closed
	end
	local action: string
	if i.status == "preparing" then
		if not (i.mine and free) then
			return nil, "is being designed (preparing): name it to resume"
		end
		action = "resume"
	elseif i.status == "prepared" and i.designReady then
		action = if i.sized then "rafting" else "fix"
	elseif i.status == "new" then
		if i.draftBlock ~= "" then
			return nil, `its idea needs the person ({i.draftBlock})`
		end
		action = "draft"
	else
		return nil, `is {i.status}`
	end
	local unmet = work.unmet(i.deps, issues)
	for _, d in unmet do
		local dep = issueOf(issues, d)
		if dep and dep.status == "closed" then
			return nil, `depends on {d}, which is closed (won't do): its depends_on needs the person`
		end
	end
	if #unmet > 0 then
		local raw = allDesigned(unmet, issues)
		if raw then
			return nil, `depends on {raw}, which is not designed`
		end
		if tier == 1 then
			return nil, nil -- a tier 2 pick
		end
	elseif tier == 2 then
		return nil, nil
	end
	return action, nil
end

local function issueDecision(i: IssueFact, action: string, issues: { IssueFact }): Decision
	local unmet = work.unmet(i.deps, issues)
	local tail = if #unmet > 0
		then ` It depends on {table.concat(unmet, ", ")}, not landed: design from their documents, and run prototypes on their layer branches where they have one.`
		else ""
	if action == "resume" then
		return {
			raft = "",
			layer = "",
			ticket = i.id,
			action = "draft",
			why = `{i.id} is being designed and its prep worktree is here: resume it (z-design, guess mode), then ask again.{tail}`,
		}
	end
	if action == "fix" then
		return {
			raft = "",
			layer = "",
			ticket = i.id,
			action = "fix",
			why = `{i.id} is prepared with no size:, so z-raft cannot place it. Record z-design's estimate of changed lines as size: by a tracker pull request, merge it when it is green, then ask again.`,
		}
	end
	local why = if action == "draft"
		then `Design {i.id} in guess mode (z-design): ./zn status {i.id} preparing in a prep worktree, record every open choice with ./zn guess, merge the prep pull request when it is green, then ask again.{tail}`
		else `{i.id} is prepared and in no raft. Run z-raft with no argument in guess mode (./zn raft-plan --apply), merge the rafting pull request when it is green, then ask again.`
	return { raft = "", layer = "", ticket = i.id, action = action, why = why }
end

-- One line per backlog issue in no raft that is not picked.
-- `all` is every issue (a dependency may be another project's); it defaults to `issues`.
function work.skippedIssues(issues: { IssueFact }, all: { IssueFact }?, input: Input?): { string }
	local lines: { string } = {}
	for _, i in issues do
		local a1, why = issuePick(i, all or issues, 1, input ~= nil and work.free(i.id, input))
		if not a1 and why then
			table.insert(lines, `{i.id}: {why}`)
		end
	end
	table.sort(lines)
	return lines
end

local function keptIssues(issues: { IssueFact }?, scope: string?): { IssueFact }
	local out: { IssueFact } = {}
	for _, i in (issues or {}) :: { IssueFact } do
		if not scope or scope == "" or i.root == scope then
			table.insert(out, i)
		end
	end
	table.sort(out, function(a, b)
		return a.id < b.id
	end)
	return out
end

local function lowestIssue(
	issues: { IssueFact },
	all: { IssueFact },
	tier: number,
	action: string,
	input: Input
): IssueFact?
	for _, i in issues do -- sorted by id
		if issuePick(i, all, tier, work.free(i.id, input)) == action then
			return i
		end
	end
	return nil
end

-- The action for an issue that was named.
function work.forIssue(i: IssueFact, input: Input): Decision
	if i.raft ~= "" then
		local r = find(input.rafts, i.raft)
		if r then
			return work.forRaft(r)
		end
		return blank("none", `{i.id} is in {i.raft}, which is not in the tracker`, "")
	end
	local all = input.issues or {}
	if i.status == "preparing" then
		return {
			raft = "",
			layer = "",
			ticket = i.id,
			action = "draft",
			why = `{i.id} is being designed: resume its prep worktree (z-design, guess mode), then ask again.`,
		}
	end
	local action, why = issuePick(i, all, 1, true)
	if not action and not why then
		action, why = issuePick(i, all, 2, true)
	end
	if action then
		return issueDecision(i, action, all)
	end
	return { raft = "", layer = "", ticket = i.id, action = "none", why = why or `{i.id} is {i.status}` }
end

function work.heldBy(input: Input): { string }
	local out: { string } = {}
	local author = input.author or ""
	if author == "" then
		return out
	end
	for _, r in work.kept(input.rafts, input.scope) do
		if r.where == "active" and r.holder == author then
			table.insert(out, r.id)
		end
	end
	table.sort(out)
	return out
end

function work.decide(input: Input): Decision
	if input.asked and input.asked ~= "" then
		local r = find(input.rafts, input.asked)
		local named = issueOf(input.issues or {}, input.asked :: string)
		if not r and named then
			return work.forIssue(named, input)
		end
		if not r then
			return blank("none", `{input.asked} is not in the tracker`, input.asked)
		end
		return work.forRaft(r)
	end
	if (input.released or 0) >= work.BLOCKED_IN_A_ROW then
		return blank("none", work.blockedWhy(), "")
	end
	-- An unnamed session does not resume the raft this checkout is in, and does not resume one this
	-- person already holds. Naming the raft is the resume.
	local visible = work.kept(input.rafts, input.scope)
	local holds = work.heldBy(input)
	local prefix = if #holds > 0 then `you hold {table.concat(holds, ", ")}: name one to resume it. ` else ""
	local all = input.issues or {}
	local issues = keptIssues(input.issues, input.scope)
	local function with(d: Decision): Decision
		d.why = prefix .. d.why
		return d
	end
	-- f0399, tier 1 (nothing unmet), furthest along first: a raft this author holds and no live session carries,
	-- one that only has to land before one still being built,
	local RESUMED: { [string]: boolean } = {
		implement = true,
		finish = true,
		restack = true,
		review = true,
		trace = true,
		["final-review"] = true,
	}
	-- A held raft built on a raft that has not landed has something unmet: it is resumed in tier 2 (final
	-- review 001 F2), so the tier always wins.
	local function held(tier: number): Decision?
		for _, wanted in { "done", "build" } do
			local mine: RaftFact? = nil
			for _, r in visible do
				if
					r.where == "active"
					and r.holder ~= ""
					and r.holder == (input.author or "")
					and work.free(r.id, input)
					and (r.on ~= nil and r.on ~= "" and not r.onLanded) == (tier == 2)
				then
					local action = work.forRaft(r).action
					local fits = if wanted == "done" then action == "done" else RESUMED[action] == true
					if fits and (not mine or work.rankKey(r) < work.rankKey(mine :: RaftFact)) then
						mine = r
					end
				end
			end
			if mine then
				local d = work.forRaft(mine :: RaftFact)
				-- the other rafts this author holds are still named, as on every unnamed pick. A resume's line
				-- still starts with "Resuming".
				local others: { string } = {}
				for _, id in holds do
					if id ~= (mine :: RaftFact).id then
						table.insert(others, id)
					end
				end
				local note = if #others > 0
					then `you hold {table.concat(others, ", ")}: name one to resume it. `
					else ""
				if wanted == "build" then
					d.why = `Resuming {(mine :: RaftFact).id}: you hold it and no live session carries it. `
						.. note
						.. d.why
				else
					d.why = note .. d.why
				end
				return d
			end
		end
		return nil
	end
	local mineFirst = held(1)
	if mineFirst then
		return mineFirst
	end
	-- a raft to ready, a raft ready refuses for something the worker can repair,
	local nextRaft = work.nextClaimable(visible)
	if nextRaft then
		return with(work.forRaft(nextRaft))
	end
	local broken: RaftFact? = nil
	for _, r in visible do
		if
			input.issues ~= nil
			and work.fixable(r)
			and (not broken or work.rankKey(r) < work.rankKey(broken :: RaftFact))
		then
			broken = r
		end
	end
	if broken then
		local r = broken :: RaftFact
		return with({
			raft = r.id,
			layer = "",
			ticket = "",
			action = "fix",
			why = `ready refuses {r.id}: {r.block :: string}. Repair it in guess mode (z-raft: a new coherence round, ./zn unfold and fold again, or the member's z-design), merge the pull request when it is green, then ask again.`,
		})
	end
	-- a prepared issue to raft, one to size, a design of this checkout to resume, an issue to design;
	for _, action in { "rafting", "fix", "resume", "draft" } do
		local pick = lowestIssue(issues, all, 1, action, input)
		if pick then
			return with(issueDecision(pick, action, all))
		end
	end
	-- tier 2 (something unmet), only now: a held raft built on an unlanded one, a raft to build on the raft
	-- it depends on,
	local mineOn = held(2)
	if mineOn then
		return mineOn
	end
	local onRaft: RaftFact? = nil
	local onBase = ""
	for _, r in visible do
		if readyOn(r) and (not onRaft or work.rankKey(r) < work.rankKey(onRaft :: RaftFact)) then
			local base = work.baseFor(r, input.rafts, all)
			if base then
				onRaft = r
				onBase = base
			end
		end
	end
	if onRaft then
		local r = onRaft :: RaftFact
		return with({
			raft = r.id,
			layer = "",
			ticket = "",
			action = "ready",
			why = `{r.id} is prepared and depends on {onBase}, whose layers are finished. From the main checkout run ./zn ready {r.id} --on {onBase}, then ask again.`,
		})
	end
	for _, action in { "rafting", "fix", "resume", "draft" } do
		local pick = lowestIssue(issues, all, 2, action, input)
		if pick then
			return with(issueDecision(pick, action, all))
		end
	end
	local reasons = work.whyNone(visible)
	local more = work.skippedIssues(issues, all, input)
	if #more > 0 then
		reasons = if reasons == "no claimable raft"
			then table.concat(more, "; ")
			else reasons .. "; " .. table.concat(more, "; ")
	end
	return blank("none", prefix .. reasons, "")
end

function work.report(input: Input, d: Decision): string
	local unnamed = not input.asked or input.asked == ""
	if not unnamed or (d.action ~= "none" and d.action ~= "ready") then
		return work.say(d)
	end
	if d.action == "none" and string.find(d.why, "in a row", 1, true) then
		return work.say(d)
	end
	local holds = work.heldBy(input)
	local name = work.scopeName(input.scope)
	local place = if name == "" then "" else ` in {name}`
	local head = if d.action == "none"
		then `nothing to do - {if #holds > 0
			then `you hold {table.concat(holds, ", ")}: name one to resume it. `
			else ""}no claimable raft{place}`
		else work.say(d)
	local lines = { head }
	for _, skipped in work.skipped(work.kept(input.rafts, input.scope)) do
		table.insert(lines, skipped)
	end
	for _, skipped in work.skippedIssues(keptIssues(input.issues, input.scope), input.issues, input) do
		table.insert(lines, skipped)
	end
	return table.concat(lines, "\n")
end

-- `./zn work queue`: one line per raft, then per backlog issue in no raft, that the next action will not take.
function work.queue(input: Input): { string }
	local lines = work.skipped(work.kept(input.rafts, input.scope))
	for _, skipped in work.skippedIssues(keptIssues(input.issues, input.scope), input.issues, input) do
		table.insert(lines, skipped)
	end
	return lines
end

function work.say(d: Decision): string
	local why = (string.gsub(d.why, "\n", " "))
	if d.raft == "" and d.ticket ~= "" then
		return `{d.ticket}: {d.action} - {why}`
	end
	if d.action == "none" and d.raft == "" then
		return `nothing to do - {why}`
	end
	local where = if d.raft ~= "" then d.raft else "nothing"
	if d.layer ~= "" then
		where ..= ` layer {d.layer}`
	end
	local ticket = if d.ticket ~= "" then ` {d.ticket}` else ""
	return `{where}: {d.action}{ticket} - {why}`
end

function work.status(rafts: { RaftFact }): { string }
	local rows: { RaftFact } = {}
	for _, r in rafts do
		if r.where == "active" then
			table.insert(rows, r)
		end
	end
	table.sort(rows, function(a, b)
		return a.id < b.id
	end)
	local out: { string } = {}
	for _, r in rows do
		local top: LayerFact? = nil
		for _, layer in r.layers do
			if not top or layer.position > (top :: LayerFact).position then
				top = layer
			end
		end
		local place = if top
			then `layer {(top :: LayerFact).position} {(top :: LayerFact).issue}`
			else "claimed"
		local who = if r.holder ~= "" then r.holder else "unknown"
		local since = if r.since ~= "" then r.since else "unknown"
		local waits = ""
		if work.forRaft(r).action == "wait" and r.unapproved and #(r.unapproved :: { string }) > 0 then
			local ids: { string } = {}
			for _, line in r.unapproved :: { string } do
				table.insert(ids, string.match(line, "^(%S+)") or line)
			end
			waits = ` waits for approval: {table.concat(ids, ", ")}`
		end
		table.insert(out, `{r.id} {place} holder {who} since {since}{waits}`)
	end
	return out
end

return work
