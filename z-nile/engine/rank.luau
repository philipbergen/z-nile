--!strict
-- The rank of an issue or a raft (c0249): the `rank:` front-matter line, the order it gives, the move that edits it
-- and the pick `./zn next` prints. Pure over texts and facts; main.luau reads origin/main and the checkout and writes.
--
-- The order (one comparator, `rank.less`), best first:
--   1. blocked items, when the caller asks (`list` and the board: they wait on the person; `next` skips them instead);
--   2. lost work, in the order the heartbeat gives (c0265: longest silent first), whatever its rank;
--   3. a set rank before an unset one, then the lower rank;
--   4. the ticket number (a raft before an issue, then the number, then the id), so the order is always stable.
-- `rank.listOrder` is what `./zn list` prints: every blocked item first (rafts, then issues), then lost work, then the rafts
-- and then the issues, each in this order (c0250's shape for the blocked part, which its work-board spec pins).
-- A rank only orders work that is not started: an item that is not in the backlog counts as unset.
local provenance = require("./provenance")
local publish = require("./publish")
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
	moved: boolean?, -- its latest `ranked` row in provenance.md carries `moved=`: a move that renumbered it wrote the rank, a person did not set it
	design: string?, -- front `design:` (the rafting pick needs `ready`)
	approved: boolean?, -- an approval.md sits beside the document on origin/main (the rafting pick)
	ownRank: number?, -- set by rank.stack only: its own rank, while `rank` holds the one the order uses
	ownMoved: boolean?, -- set by rank.stack only: whether its own rank is a moved-written one
}

-- The rank a front-matter value gives: (nil, nil) for none (the line is missing or empty), (n, nil), or (nil, why). The
-- value is a bare whole number: who set it is in the item's provenance.md, never in the line (`rank.movedBy`).
function rank.parse(value: string?): (number?, string?)
	if value == nil or value == "" then
		return nil, nil
	end
	if #value > 6 or not string.match(value, "^[1-9]%d*$") then
		return nil,
			`rank: {value} is not a whole number from 1 to {rank.MAX} (no sign, no leading zero, no fraction); `
				.. "leave it empty or remove the line to unset it"
	end
	return tonumber(value), nil
end

-- Whether a rank was written by a move that renumbered the item rather than set by a person, read from the item's
-- provenance.md (`text`, nil when there is none): its latest `ranked` row carries a `moved=` field (the move writes the
-- row of every item it renumbers with `moved=<the item it moved>`). A person-set rank has a latest `ranked` row with no
-- `moved=`, or no row at all (a hand edit). A raft takes its members' best rank from the person-set ones only, so a move
-- that renumbers items never reorders the rafts (Q5, F2 of the design review). A record that does not parse counts as
-- person-set (the audit refuses it).
function rank.movedBy(text: string?): boolean
	if text == nil or text == "" then
		return false
	end
	local rows = provenance.parse(text)
	if not rows then
		return false
	end
	for i = #rows, 1, -1 do
		if rows[i].event == "ranked" then
			for part in string.gmatch(rows[i].detail, "[^;]+") do
				if string.match(part, "^%s*moved=") then
					return true
				end
			end
			return false
		end
	end
	return false
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

-- The document with its rank set to `value` (a whole number) or removed (nil). Every `rank:` line
-- goes; a set rank is written once, right after `id:` (at the top of the block when there is none): the line every prep
-- branch leaves alone, so a rank published while a prep is open merges without a conflict (`status:` and `design:` are
-- the lines a prep edits, and a line beside them conflicts). Nil when there is no front block.
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
		local at = 1
		for i, line in kept do
			if string.match(line, "^id:") then
				at = i + 1
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

-- (state, id, root) of an item's document path, for the roots a registry lists (origin/main's, for a publish; the
-- working tree's, for a reader): publish.itemPath's reading of `<root>/(issues|rafts)/[active/|done/]<id>/<id>.md`, and a
-- retired raft's (`<root>/rafts/retired/<id>/<id>.md`, which a publish never sees). nil for any other path.
function rank.where(path: string, roots: { string }): (string?, string?, string?)
	local id, rel, root = publish.itemPath(path)
	if id and rel == `{id}.md` and root and table.find(roots, root) then
		local under = string.sub(path, #root + 2)
		local state = if string.find(under, "^issues/active/") or string.find(under, "^rafts/active/")
			then "active"
			elseif string.find(under, "^issues/done/") or string.find(under, "^rafts/done/") then "done"
			else "backlog"
		return state, id, root
	end
	for _, r in roots do
		local escaped = string.gsub(r, "%p", "%%%0")
		local a, b = string.match(path, `^{escaped}/rafts/retired/(R%d%d%d%d)/(R%d%d%d%d)%.md$`)
		if a and a == b then
			return "retired", a, r
		end
	end
	return nil, nil, nil
end

-- The fact of one document: `front` is its front matter as a key -> value table (any reader's). The status word is the
-- effective one (status.effective), or the stored `blocked`. A done item is its id and state alone. `record` is the text
-- of the item's provenance.md, when the caller has read it (it needs it only for an item that has a rank).
function rank.factOf(path: string, front: { [string]: string }, roots: { string }, record: string?): Fact?
	local state, id, root = rank.where(path, roots)
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
		moved = own ~= nil and rank.movedBy(record),
		raft = if (front.raft or "") ~= "" then front.raft else nil,
		members = ids(front.issues),
		dependsOn = ids(front.depends_on),
		root = root,
		design = front.design,
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

-- A raft's rank for ordering: its own, else the best (lowest) rank a person set on one of its members (a rank a move
-- wrote, `moved=` in its provenance.md, does not count: an unrelated move must not reorder the rafts); an issue's is its own.
function rank.effective(f: Fact, byId: { [string]: Fact }): number?
	local own = ranked(f)
	if own ~= nil or f.kind ~= "raft" then
		return own
	end
	local best: number? = nil
	for _, mid in f.members do
		local m = byId[mid]
		local r = if m and not m.moved then ranked(m) else nil
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

export type Pick = { id: string, kind: string, why: string } -- kind: "lost" | "raft" | "rafting" | "draft"

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
--   else the best-ranked approved issue that is in no raft (a worker rafts it: `./zn raft-plan --apply`);
--   else the best-ranked issue whose design a worker may draft.
-- A blocked item, or one whose dependencies are not all done, is skipped and keeps its rank. (A blocked item has the
-- stored status `blocked`, so the status tests below leave it out; only lost work needs the check.)
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
	local approved: { Fact } = {}
	local issues: { Fact } = {}
	for _, f in facts do
		if f.state ~= "backlog" or not free(f) then
			continue
		end
		if f.kind == "raft" and f.status == "prepared" and ctx.claimable(f) then
			table.insert(rafts, f)
		elseif f.kind == "issue" and (f.raft or "") == "" then
			if f.status == "prepared" and f.design == "ready" and f.approved == true then
				table.insert(approved, f)
			elseif f.status == "new" and ctx.mayDraft(f) then
				table.insert(issues, f)
			end
		end
	end
	local nextRaft = rank.order(rafts, { world = facts })[1]
	if nextRaft then
		return { id = nextRaft.id, kind = "raft", why = `rank {shown(rank.effective(nextRaft, byId))}` }, ""
	end
	local nextApproved = rank.order(approved, { world = facts })[1]
	if nextApproved then
		return { id = nextApproved.id, kind = "rafting", why = "approved, in no raft" }, ""
	end
	local nextIssue = rank.order(issues, { world = facts })[1]
	if nextIssue then
		return { id = nextIssue.id, kind = "draft", why = `rank {shown(nextIssue.rank)}` }, ""
	end
	return nil, "no lost work, no claimable raft, no approved issue to raft and no issue to draft"
end

-- What `./zn list` prints, in order: every blocked item (rafts, then issues, each in the stack's order), then lost work
-- (the heartbeat's order, any kind), then the rest: the rafts, then the issues, each in the stack's order. `world` is
-- every fact (a raft's rank reads its members').
function rank.listOrder(facts: { Fact }, lost: { string }?, world: { Fact }?): { Fact }
	local byId = byIdOf(world or facts)
	local blocked: { Fact } = {}
	local rest: { Fact } = {}
	for _, f in facts do
		table.insert(if rank.isBlocked(f.status) then blocked else rest, f)
	end
	local out: { Fact } = {}
	local function kinds(list: { Fact })
		for _, kind in { "raft", "issue" } do
			local ofKind: { Fact } = {}
			for _, f in list do
				if f.kind == kind then
					table.insert(ofKind, f)
				end
			end
			for _, f in rank.order(ofKind, { world = world or facts }) do
				table.insert(out, f)
			end
		end
	end
	kinds(blocked)
	local taken: { [Fact]: boolean } = {}
	local lostList: { string } = lost or {}
	for _, id in lostList do
		local f = byId[id]
		if f and not taken[f] and table.find(rest, f) then
			taken[f] = true
			table.insert(out, f)
		end
	end
	local others: { Fact } = {}
	for _, f in rest do
		if not taken[f] then
			table.insert(others, f)
		end
	end
	kinds(others)
	return out
end

export type Change = { id: string, rank: number?, was: number?, moved: boolean? } -- moved: its `ranked` row carries `moved=`

-- The facts a move can place: the backlog items of the kind, in the order a rank gives them (no lost, no blocked).
function rank.stack(facts: { Fact }, kind: string): { Fact }
	local byId = byIdOf(facts)
	local mine: { Fact } = {}
	for _, f in facts do
		if f.kind == kind and f.state == "backlog" then
			local c = table.clone(f)
			c.ownRank = f.rank
			c.ownMoved = f.moved
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
--   "top"                    the first place
--   "last"                   the end: below the unset items the moved item is unset (it then sorts among them by number,
--                            which the third result says); with every item ranked it goes after the last
--   "before", "after"        next to the item `arg` names (another item of the stack)
--   "set"                    the whole number `arg`
--   "unset"                  no rank
-- The moved item is given a plain rank in a gap (its neighbours' ranks 10 apart, so one move edits one file). Dropped
-- among or after unset items, it is given a rank with the unset items above it in the stack, in steps of 10 after the
-- highest rank there is, and their `ranked` rows carry `moved=` (a person did not set them: a raft's rank ignores them); no
-- rank that exists changes. Only when there is no room between two ranked neighbours are the ranked items renumbered 10, 20,
-- 30 ... from the top, each but the moved one with `moved=` in its row. An empty result changes nothing; asking for the
-- place a moved-written rank already has changes no line but writes a row without `moved=`, which makes it the person's.
function rank.plan(
	stack: { Fact },
	id: string,
	how: string,
	arg: (string | number)?
): ({ Change }?, string?, string?)
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
		if me.ownRank == n and not me.ownMoved then
			return {}, nil
		end
		return { { id = id, rank = n, was = me.ownRank, moved = false } }, nil
	elseif how == "unset" then
		return if me.ownRank == nil then {} else { { id = id, rank = nil, was = me.ownRank } }, nil
	end
	local byId: { [string]: Fact } = {}
	local others: { string } = {}
	local current: { string } = {}
	local anyUnset = false
	for _, f in stack do
		byId[f.id] = f
		table.insert(current, f.id)
		if f.id ~= id then
			table.insert(others, f.id)
			anyUnset = anyUnset or f.rank == nil
		end
	end
	if how == "last" and anyUnset then
		local note = "dropped below the unset items: it sorts among them by number, and nothing is renumbered"
		return if me.ownRank == nil then {} else { { id = id, rank = nil, was = me.ownRank } }, nil, note
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
		-- already there; but asking for the place makes a moved-written rank the person's own
		if me.ownRank ~= nil and me.ownMoved then
			return { { id = id, rank = me.ownRank, was = me.ownRank, moved = false } }, nil
		end
		return {}, nil
	end
	local function rankOf(i: number): number?
		local f = byId[want[i]]
		return if f then f.rank else nil
	end
	local function keeps(changes: { Change }): { Change }?
		local assigned: { [string]: number? } = {}
		for _, c in changes do
			assigned[c.id] = c.rank
		end
		if same(orderIds(stack, assigned), want) then
			return changes
		end
		return nil
	end
	-- the moved item among the unset ones: rank it, and the unset items above it, after the highest rank
	if at > 1 and rankOf(at - 1) == nil then
		local first = at
		for i = 1, at - 1 do
			if rankOf(i) == nil then
				first = i
				break
			end
		end
		local base = 0
		for i = 1, first - 1 do
			base = math.max(base, rankOf(i) or 0)
		end
		if base + (at - first + 1) * rank.GAP > rank.MAX then
			return nil, `{at - first + 1} items do not fit above {rank.MAX}`
		end
		local changes: { Change } = {}
		for i = first, at do
			table.insert(changes, {
				id = want[i],
				rank = base + (i - first + 1) * rank.GAP,
				was = byId[want[i]].ownRank,
				moved = i ~= at,
			})
		end
		local checked = keeps(changes)
		if checked then
			return checked, nil
		end
		return nil, `{id}: the ranks do not give the order asked for (a bug: report it)`
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
		local one = keeps({ { id = id, rank = pick, was = me.ownRank, moved = false } })
		if one then
			return if me.ownRank == pick and not me.ownMoved then {} else one, nil
		end
	end
	-- no room: renumber the ranked items from the top, through the moved item
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
	for i = 1, last do
		local wid = want[i]
		local f = byId[wid]
		if f.ownRank ~= i * rank.GAP or (wid == id and f.ownMoved) then
			table.insert(changes, { id = wid, rank = i * rank.GAP, was = f.ownRank, moved = wid ~= id })
		end
	end
	local checked = keeps(changes)
	if checked then
		return checked, nil
	end
	return nil, `{id}: the renumbering does not give the order asked for (a bug: report it)`
end

return rank
