--!strict
-- f0423: what waits for the owner's approval. One rule, pure over facts the caller already read: the approval queue
-- (`./zn approve`), and later `work.forRaft`, `./zn done` and the board's count. A fact is five things and the two
-- rework facts (step 3 of f0423 reads them; until then no caller sets them).
local waiting = {}

export type Stage = "draft" | "designed" | "built" -- draft: the design is not ready; built: a layer with commits exists
export type Approval = "none" | "bad" | "holds" | "guesses" | "stale" -- approval.standing, plus none and bad

export type Fact = {
	stage: Stage,
	approval: Approval,
	changed: { string }, -- the contract parts that differ from the last approval row
	guesses: number, -- the count in guesses.md
	lands: boolean, -- the raft was readied with `Lands: approved`
	reworkOpen: boolean, -- a rework entry is still open
	reworkSince: number?, -- N of the newest rework entry W<N> when it is later than the last approval row
}

export type Verdict = { state: "waits" | "clear" | "working", why: string }

-- The first rule that matches decides.
function waiting.of(f: Fact): Verdict
	if f.stage == "draft" then
		return { state = "working", why = "its design is not ready" }
	end
	if f.reworkOpen then
		return { state = "working", why = "a rework is open" }
	end
	if f.approval == "bad" then
		return { state = "waits", why = "approval.md does not parse" }
	end
	if f.reworkSince ~= nil then
		return { state = "waits", why = `reworked since approval (W{f.reworkSince})` }
	end
	if f.approval == "guesses" or f.approval == "stale" then
		local parts = if #f.changed > 0 then table.concat(f.changed, ", ") else "design"
		return { state = "waits", why = `changed: {parts}` }
	end
	if f.approval == "none" and (f.guesses > 0 or f.lands) then
		return { state = "waits", why = `no approval ({f.guesses} guesses)` }
	end
	return { state = "clear", why = "nothing to approve" }
end

-- A raft or a raftless ticket waits if any member waits, else is working if any member is, else is clear.
function waiting.unit(verdicts: { Verdict }): "waits" | "clear" | "working"
	local state: "waits" | "clear" | "working" = "clear"
	for _, v in verdicts do
		if v.state == "waits" then
			return "waits"
		elseif v.state == "working" then
			state = "working"
		end
	end
	return state
end

export type Placed = { id: string, unit: string, layer: number }

-- Ticket ids, the bottom of a stack first: by the band of the ticket's unit (`bands`, depgraph.bands' answer, a
-- unit missing from it is band 0), then by layer within a raft, then by id.
function waiting.order(tickets: { Placed }, bands: { [string]: number }): { string }
	local sorted = table.clone(tickets)
	table.sort(sorted, function(a, b)
		local ba, bb = bands[a.unit] or 0, bands[b.unit] or 0
		if ba ~= bb then
			return ba < bb
		end
		if a.unit ~= b.unit then
			return a.unit < b.unit
		end
		if a.layer ~= b.layer then
			return a.layer < b.layer
		end
		return a.id < b.id
	end)
	local out: { string } = {}
	for _, p in sorted do
		table.insert(out, p.id)
	end
	return out
end

return waiting
