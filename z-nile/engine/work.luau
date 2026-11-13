--!strict
-- What one worker does next. Pure over tracker facts the edge has already read. The skill carries none of
-- this order: `./zn work next` prints one line, and the worker does that one thing.
--
-- Left for later tickets, on purpose:
--   c0249: a claimable raft is the lowest id, not a rank, and lost work is not taken first.
--   c0250: questions.md is the only block signal. There is no blocked status and no resolve command.
--   c0265: nothing beats while a raft is held.
--   c0254: the holder is the author of the ready commit, not a worker identity, and two checkouts can be
--     told to build the same active raft if both name it.
--   a headless `./zn work` loop is not this function. A session ends when its raft lands or is released.
local work = {}

export type LayerFact = {
	position: number,
	issue: string,
	name: string,
	commits: number,
	onlyStart: boolean, -- the layer's only commit is `tracker: start`
	finished: boolean,
}

export type RaftFact = {
	id: string,
	title: string,
	where: string, -- backlog, active, done
	status: string,
	designReady: boolean,
	depsMet: boolean,
	questions: boolean,
	issues: { string },
	layers: { LayerFact },
	holder: string,
	since: string,
	stacked: boolean,
	codeReview: string, -- none, open, resolved
	finalReview: string, -- none, open, approved
	trace: boolean,
	traceOk: boolean,
}

export type Input = {
	asked: string?,
	held: string?,
	rafts: { RaftFact },
}

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
	return r.where == "backlog" and r.status == "prepared" and r.designReady and r.depsMet and not r.questions
end

-- The next raft a fresh session may take. Lowest id. Rank is c0249's.
function work.nextClaimable(rafts: { RaftFact }): RaftFact?
	local best: RaftFact? = nil
	for _, r in rafts do
		if work.claimable(r) and (not best or r.id < (best :: RaftFact).id) then
			best = r
		end
	end
	return best
end

function work.whyNone(rafts: { RaftFact }): string
	local bits: { string } = {}
	for _, r in rafts do
		if r.where == "active" then
			table.insert(bits, `{r.id} is held`)
		elseif r.where == "backlog" then
			if r.questions then
				table.insert(bits, `{r.id} needs a human (questions.md)`)
			elseif r.status ~= "prepared" or not r.designReady then
				table.insert(bits, `{r.id} is {r.status}, design not ready`)
			elseif not r.depsMet then
				table.insert(bits, `{r.id} has a dependency that is not done`)
			end
		end
	end
	if #bits == 0 then
		return "no prepared raft is claimable"
	end
	table.sort(bits)
	return table.concat(bits, "; ")
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
				`{r.id} is prepared and its dependencies are done. From the main checkout run ./zn ready {r.id}, then ask again.`,
				"",
				nil
			)
		end
		local why = if not r.designReady
			then `{r.id} is not design: ready`
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
				`Run ./zn finish {issue}. If the check is red, fix the code and run finish again. The same check failing after a real second attempt is blocked: write questions.md, commit it, ./zn stop {r.id}, and ask again.`,
				issue,
				layer
			)
		end
	end
	if not r.stacked then
		return of(r, "restack", `Run ./zn restack {r.id}, then ask again.`, "", nil)
	end
	if r.codeReview == "none" then
		return of(
			r,
			"review",
			"Run the code review once (zz-review, code mode; zz-execute Phase 4). Commit the review file, then ask again.",
			"",
			nil
		)
	end
	if r.codeReview ~= "resolved" then
		return of(
			r,
			"review",
			"Answer the open code review (zz-execute Phase 4) until its verdict is approve, then ask again. Do not guess a ruling.",
			"",
			nil
		)
	end
	if not r.trace then
		return of(
			r,
			"trace",
			`Run ./zn trace {r.id} and commit that skeleton as trace.md in {r.id}'s folder, then ask again.`,
			"",
			nil
		)
	end
	if r.finalReview ~= "approved" then
		return of(
			r,
			"final-review",
			"Run the final review (zz-execute Phase 5). It fills trace.md and writes final-review-NNN.md. Then ask again.",
			"",
			nil
		)
	end
	if not r.traceOk then
		return of(
			r,
			"trace",
			`./zn trace {r.id} --check does not pass. Fix trace.md, then ask again.`,
			"",
			nil
		)
	end
	return of(r, "done", `Run ./zn done {r.id}. It lands the stack. Then ask again.`, "", nil)
end

function work.decide(input: Input): Decision
	if input.asked and input.asked ~= "" then
		local r = find(input.rafts, input.asked)
		if not r then
			return blank("none", `{input.asked} is not in the tracker`, input.asked)
		end
		return work.forRaft(r)
	end
	if input.held and input.held ~= "" then
		local h = find(input.rafts, input.held)
		if h and (h.where == "active" or h.where == "done" or h.questions) then
			return work.forRaft(h)
		end
	end
	local nextRaft = work.nextClaimable(input.rafts)
	if not nextRaft then
		return blank("none", work.whyNone(input.rafts), "")
	end
	return work.forRaft(nextRaft)
end

function work.say(d: Decision): string
	local why = (string.gsub(d.why, "\n", " "))
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
		table.insert(out, `{r.id} {place} holder {who} since {since}`)
	end
	return out
end

return work
