--!strict
-- The rank of an issue or a raft (c0249): the `rank:` front-matter line, the order it gives, the move that edits it
-- and the pick `./zn next` prints. Pure over texts and facts; main.luau reads origin/main and the checkout and writes.
--
-- The order (one comparator, `rank.before`), best first:
--   1. blocked items, when the caller asks (`list` and the board: they wait on the person; `next` skips them instead);
--   2. lost work, in the order the heartbeat gives (c0265: longest silent first), whatever its rank;
--   3. a set rank before an unset one, then the lower rank;
--   4. the ticket number (a raft before an issue, then the number, then the id), so the order is always stable.
-- A rank only orders work that is not started: an item that is not in the backlog counts as unset.
local statusLib = require("./status")

local rank = {}

rank.MAX = 999999
rank.GAP = 10

export type Fact = {
	id: string,
	kind: string, -- "issue" | "raft"
	state: string, -- "backlog" | "active" | "done" | "retired"
	status: string, -- the effective status word (status.effective), or the stored word `blocked`
	rank: number?, -- its own rank; nil when unset
	raft: string?, -- an issue's raft
	members: { string }, -- a raft's member ids
	dependsOn: { string }, -- an issue's depends_on ids
	root: string, -- the project root that holds it
	ownRank: number?, -- set by rank.stack only: its own rank, while `rank` holds the one the order uses
}

-- The rank a front-matter value gives: (nil, nil) for none (the line is missing or empty), (n, nil), or (nil, why).
function rank.parse(value: string?): (number?, string?)
	if value == nil or value == "" then
		return nil, nil
	end
	if #value > 6 or not string.match(value, "^[1-9]%d*$") then
		return nil,
			`rank: {value} is not a whole number from 1 to {rank.MAX} (no sign, no leading zero, no fraction); leave it empty or remove the line to unset it`
	end
	return tonumber(value), nil
end

-- What is wrong with the rank lines of a document, or nil. The front block is read as store.readFront reads it (the
-- text between the leading `---` fences, one `key: value` per line); a line that says rank in any other shape
-- (indented, spaced before the colon, another case) is a problem too, because the readers would skip it silently.
function rank.problem(text: string): string?
	local block = string.match(text, "^%-%-%-\n(.-)\n%-%-%-")
	if not block then
		return nil
	end
	local lines, value = 0, nil :: string?
	for line in string.gmatch(block, "[^\n]+") do
		local key, v = string.match(line, "^([%w_]+):%s*(.-)%s*$")
		if key == "rank" then
			lines += 1
			value = v
		elseif string.match(line, "^%s*[Rr][Aa][Nn][Kk]%s*:") then
			return `{line}: write the rank as \`rank: <whole number>\` at the start of the line`
		end
	end
	if lines > 1 then
		return `rank: is written {lines} times; keep one line`
	end
	local _, why = rank.parse(value)
	return why
end

-- The document with its rank set to `value` (a whole number) or removed (nil). Every `rank:` line goes; a set rank is
-- written once, just before `status:` (the template's last key) or, without one, last. Nil when there is no front block.
function rank.withRank(text: string, value: number?): string?
	local head, block, rest = string.match(text, "^(%-%-%-\n)(.-\n)(%-%-%-.*)$")
	if not head or not block or not rest then
		return nil
	end
	local kept: { string } = {}
	for line in string.gmatch(block, "([^\n]*)\n") do
		if not string.match(line, "^rank:") then
			table.insert(kept, line)
		end
	end
	if value ~= nil then
		local at = #kept + 1
		for i, line in kept do
			if string.match(line, "^status:") then
				at = i
				break
			end
		end
		table.insert(kept, at, `rank: {value}`)
	end
	local body = table.concat(kept, "\n")
	if #kept > 0 then
		body ..= "\n"
	end
	return head .. body .. rest
end

-- The stored status words that mean "waits on a person" (c0250's `blocked`, plain or stamped).
function rank.isBlocked(status: string?): boolean
	return status ~= nil and (status == "blocked" or string.sub(status, 1, 8) == "blocked-")
end

function rank.number(id: string): number
	return tonumber(string.sub(id, 2)) or 0
end

-- (state, id, root) of an item's document path (`<root>/issues/[active/|done/|retired/]<id>/<id>.md`, rafts alike);
-- nil for any other path.
function rank.where(path: string): (string?, string?, string?)
	for _, k in { { "issues", "[fdc]" }, { "rafts", "R" } } do
		for _, st in
			{ { "active/", "active" }, { "done/", "done" }, { "retired/", "retired" }, { "", "backlog" } }
		do
			local root, id, file =
				string.match(path, `^(.*)/{k[1]}/{st[1]}({k[2]}%d%d%d%d)/({k[2]}%d%d%d%d)%.md$`)
			if root and id and id == file then
				return st[2], id, root
			end
		end
	end
	return nil, nil, nil
end

-- The fact of one document: `front` is its front matter as a key -> value table (any reader's). The status word is the
-- effective one (status.effective), or the stored `blocked`. A done item is its id and state alone.
function rank.factOf(path: string, front: { [string]: string }): Fact?
	local state, id, root = rank.where(path)
	if not state or not id or not root then
		return nil
	end
	local kind = if string.sub(id, 1, 1) == "R" then "raft" else "issue"
	if state == "done" then
		local finished: Fact = {
			id = id,
			kind = kind,
			state = state,
			status = "done",
			rank = nil,
			raft = nil,
			members = {},
			dependsOn = {},
			root = root,
		}
		return finished
	end
	local own = if state == "backlog" then rank.parse(front.rank) else nil
	local word = if rank.isBlocked(front.status)
		then front.status :: string
		else statusLib.effective(front, state)
	local ids = function(value: string?): { string }
		local out: { string } = {}
		for item in string.gmatch(value or "", "[fdcR]%d%d%d%d") do
			table.insert(out, item)
		end
		return out
	end
	return {
		id = id,
		kind = kind,
		state = state,
		status = word,
		rank = own,
		raft = if (front.raft or "") ~= "" then front.raft else nil,
		members = ids(front.issues),
		dependsOn = ids(front.depends_on),
		root = root,
	}
end

local function ranked(f: Fact): number?
	return if f.state == "backlog" then f.rank else nil
end

-- The comparison of two rank values with their ids: a set rank first, the lower first, then raft before issue, the
-- ticket number, the id. Both `rank.before` and the raft facts of `work.luau` use it.
function rank.less(ar: number?, aid: string, br: number?, bid: string): boolean
	if ar ~= br then
		if ar == nil then
			return false
		elseif br == nil then
			return true
		end
		return ar < br
	end
	local ak, bk = string.sub(aid, 1, 1) == "R", string.sub(bid, 1, 1) == "R"
	if ak ~= bk then
		return ak
	end
	local an, bn = rank.number(aid), rank.number(bid)
	if an ~= bn then
		return an < bn
	end
	return aid < bid
end

-- A raft's rank for ordering: its own, else the best (lowest) rank of its members; an issue's is its own. nil: unset.
function rank.effective(f: Fact, byId: { [string]: Fact }): number?
	local own = ranked(f)
	if own ~= nil or f.kind ~= "raft" then
		return own
	end
	local best: number? = nil
	for _, mid in f.members do
		local m = byId[mid]
		local r = if m then ranked(m) else nil
		if r ~= nil and (best == nil or r < best) then
			best = r
		end
	end
	return best
end

export type Options = {
	lost: { string }?, -- lost ids, in the heartbeat's order (c0265 `heartbeat.order`); first come first
	blockedFirst: boolean?,
	world: { Fact }?, -- every fact, when `facts` is a part of them (a raft's rank reads its members')
}

local function byIdOf(facts: { Fact }): { [string]: Fact }
	local out: { [string]: Fact } = {}
	for _, f in facts do
		out[f.id] = f
	end
	return out
end

-- The facts in the stack's order (a new table).
function rank.order(facts: { Fact }, opts: Options?): { Fact }
	local o: Options = opts or {}
	local byId = byIdOf(o.world or facts)
	local lostAt: { [string]: number } = {}
	local lostList: { string } = o.lost or {}
	for i, id in lostList do
		lostAt[id] = lostAt[id] or i
	end
	local out = table.clone(facts)
	table.sort(out, function(a: Fact, b: Fact): boolean
		if o.blockedFirst then
			local ab, bb = rank.isBlocked(a.status), rank.isBlocked(b.status)
			if ab ~= bb then
				return ab
			end
		end
		local al, bl = lostAt[a.id], lostAt[b.id]
		if al ~= bl then
			if al == nil then
				return false
			elseif bl == nil then
				return true
			end
			return al < bl
		end
		return rank.less(rank.effective(a, byId), a.id, rank.effective(b, byId), b.id)
	end)
	return out
end

-- True when every dependency of the item is done: an issue's own `depends_on`, a raft's members' outside the raft.
function rank.depsMet(f: Fact, byId: { [string]: Fact }): boolean
	local own: { [string]: boolean } = {}
	for _, mid in f.members do
		own[mid] = true
	end
	local function done(dep: string): boolean
		local d = byId[dep]
		return d ~= nil and d.state == "done"
	end
	for _, dep in f.dependsOn do
		if not done(dep) then
			return false
		end
	end
	for _, mid in f.members do
		local m = byId[mid]
		local mdeps: { string } = if m then m.dependsOn else {}
		for _, dep in mdeps do
			if not own[dep] and not done(dep) then
				return false
			end
		end
	end
	return true
end

export type Pick = { id: string, kind: string, why: string } -- kind: "lost" | "raft" | "draft"

export type Context = {
	lost: { string }?,
	claimable: (Fact) -> boolean, -- a raft: `./zn ready` would accept it (work.claimable)
	mayDraft: (Fact) -> boolean, -- an issue: a worker may draft its design (c0253 narrows this to a confirmed idea)
	scope: string?, -- a project root; nil or "" is every project
}

local function inScope(f: Fact, scope: string?): boolean
	return scope == nil or scope == "" or f.root == scope
end

local function shown(r: number?): string
	return if r == nil then "unset" else tostring(r)
end

-- The next item to take, or nil and why there is none:
--   lost work first, whatever its rank (the heartbeat's order);
--   else the claimable raft with the best rank;
--   else, only when no raft is claimable, the best-ranked issue whose design a worker may draft.
-- A blocked item, or one whose dependencies are not all done, is skipped and keeps its rank.
function rank.next(facts: { Fact }, ctx: Context): (Pick?, string)
	local byId = byIdOf(facts)
	local function free(f: Fact): boolean
		return inScope(f, ctx.scope) and rank.depsMet(f, byId)
	end
	local lostList: { string } = ctx.lost or {}
	for _, id in lostList do
		local f = byId[id]
		if
			f
			and f.state ~= "done"
			and f.state ~= "retired"
			and inScope(f, ctx.scope)
			and not rank.isBlocked(f.status)
		then
			return { id = id, kind = "lost", why = "its heartbeat is stale" }, ""
		end
	end
	local rafts: { Fact } = {}
	local issues: { Fact } = {}
	for _, f in facts do
		if f.state ~= "backlog" or not free(f) then
			continue
		end
		if f.kind == "raft" and f.status == "prepared" and ctx.claimable(f) then
			table.insert(rafts, f)
		elseif f.kind == "issue" and f.status == "new" and (f.raft or "") == "" and ctx.mayDraft(f) then
			table.insert(issues, f)
		end
	end
	local nextRaft = rank.order(rafts, { world = facts })[1]
	if nextRaft then
		return { id = nextRaft.id, kind = "raft", why = `rank {shown(rank.effective(nextRaft, byId))}` }, ""
	end
	local nextIssue = rank.order(issues, { world = facts })[1]
	if nextIssue then
		return { id = nextIssue.id, kind = "draft", why = `rank {shown(nextIssue.rank)}` }, ""
	end
	return nil, "no lost work, no claimable raft and no issue to draft"
end

export type Change = { id: string, rank: number?, was: number? }

-- The facts a move can place: the backlog items of the kind, in the order a rank gives them (no lost, no blocked).
function rank.stack(facts: { Fact }, kind: string): { Fact }
	local byId = byIdOf(facts)
	local mine: { Fact } = {}
	for _, f in facts do
		if f.kind == kind and f.state == "backlog" then
			local c = table.clone(f)
			c.ownRank = f.rank
			c.rank = rank.effective(f, byId)
			table.insert(mine, c)
		end
	end
	return rank.order(mine)
end

local function orderIds(stack: { Fact }, assigned: { [string]: number? }): { string }
	local copy: { Fact } = {}
	local byId: { [string]: Fact } = {}
	for _, f in stack do
		local c = table.clone(f)
		c.rank = if assigned[f.id] ~= nil then assigned[f.id] else f.rank
		table.insert(copy, c)
		byId[c.id] = c
	end
	local out: { string } = {}
	for _, f in rank.order(copy) do
		table.insert(out, f.id)
	end
	return out
end

local function same(a: { string }, b: { string }): boolean
	if #a ~= #b then
		return false
	end
	for i, id in a do
		if id ~= b[i] then
			return false
		end
	end
	return true
end

-- What a move writes. `stack` is rank.stack(...) of the item's kind, `id` is in it, and `how` is one of:
--   "top", "last"            the first or the last place
--   "before", "after"        next to the item `arg` names (another item of the stack)
--   "set"                    the whole number `arg`
--   "unset"                  no rank
-- The moved item is given a rank in a gap (the neighbours' ranks 10 apart, so one move edits one file); when there is no
-- room, or the item goes among unset ones, the items from the top through the moved one are renumbered 10, 20, 30 ... in
-- one change. Items below stay as they are. An empty result changes nothing.
function rank.plan(stack: { Fact }, id: string, how: string, arg: (string | number)?): ({ Change }?, string?)
	local me: Fact? = nil
	for _, f in stack do
		if f.id == id then
			me = f
		end
	end
	if not me then
		return nil, `{id} is not in the backlog stack of its kind`
	end
	if how == "set" then
		local n = arg :: number
		if n < 1 or n > rank.MAX or n ~= math.floor(n) then
			return nil, `rank {n} is not a whole number from 1 to {rank.MAX}`
		end
		return if me.ownRank == n then {} else { { id = id, rank = n, was = me.ownRank } }, nil
	elseif how == "unset" then
		return if me.ownRank == nil then {} else { { id = id, rank = nil, was = me.ownRank } }, nil
	end
	local others: { string } = {}
	local current: { string } = {}
	for _, f in stack do
		table.insert(current, f.id)
		if f.id ~= id then
			table.insert(others, f.id)
		end
	end
	local at: number
	if how == "top" then
		at = 1
	elseif how == "last" then
		at = #others + 1
	elseif how == "before" or how == "after" then
		local anchor = arg :: string
		if anchor == id then
			return nil, `{id} cannot go {how} itself`
		end
		local i = table.find(others, anchor)
		if not i then
			return nil,
				`{anchor} is not in the backlog stack of {id}'s kind (a rank orders work that is not started, one kind at a time)`
		end
		at = if how == "before" then i else i + 1
	else
		return nil, `unknown move {how}`
	end
	local want = table.clone(others)
	table.insert(want, at, id)
	if same(want, current) then
		return {}, nil
	end
	local byId: { [string]: Fact } = {}
	for _, f in stack do
		byId[f.id] = f
	end
	local function rankOf(i: number): number?
		local f = byId[want[i]]
		return if f then f.rank else nil
	end
	-- one edit, in a gap
	local above, below = if at > 1 then rankOf(at - 1) else nil, rankOf(at + 1)
	local pick: number? = nil
	if at == 1 then
		if below == nil then
			pick = rank.GAP
		elseif below - rank.GAP >= 1 then
			pick = below - rank.GAP
		elseif below >= 2 then
			pick = below // 2
		end
	elseif above ~= nil then
		if below == nil or below - above > rank.GAP then
			pick = above + rank.GAP
		elseif below - above >= 2 then
			pick = (above + below) // 2
		end
	end
	if pick ~= nil and pick >= 1 and pick <= rank.MAX then
		if same(orderIds(stack, { [id] = pick }), want) then
			return if me.ownRank == pick then {} else { { id = id, rank = pick, was = me.ownRank } }, nil
		end
	end
	-- renumber from the top through the moved item, and through the last ranked item below it
	local last = at
	for i, wid in want do
		if byId[wid].rank ~= nil then
			last = math.max(last, i)
		end
	end
	if last * rank.GAP > rank.MAX then
		return nil, `{last} ranked items do not fit below {rank.MAX}`
	end
	local changes: { Change } = {}
	local assigned: { [string]: number? } = {}
	for i = 1, last do
		local wid = want[i]
		assigned[wid] = i * rank.GAP
		if byId[wid].ownRank ~= i * rank.GAP then
			table.insert(changes, { id = wid, rank = i * rank.GAP, was = byId[wid].ownRank })
		end
	end
	if not same(orderIds(stack, assigned), want) then
		return nil, `{id}: the renumbering does not give the order asked for (a bug: report it)`
	end
	return changes, nil
end

return rank
