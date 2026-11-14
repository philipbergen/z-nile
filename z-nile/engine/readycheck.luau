--!strict
-- Whether `./zn ready` would accept a raft. Pure: texts in, the first refusal or nil. No push, no move.
-- `readycheck.reason` is every check `./zn ready` makes before the carried move. `./zn work next`
-- refuses a raft when this is not nil, and does not push. Rank is not this function.
--
-- The grouping record is not part of `reason`. `./zn ready` judges it inside the carried move's
-- validator, on the tree being published (`readycheck.record`), so an ignored file on disk
-- (acceptance/.DS_Store) never changes a member's hash. `./zn work next` calls `record` itself, on
-- origin/main's tracked files, which is that tree when nothing else has landed. A raft proceeds only
-- when `reason` and `record` are both nil.

local approval = require("./approval")
local contract = require("./contract")
local openlist = require("./openlist")
local raftplan = require("./raftplan")
local store = require("./store")

local readycheck = {}

export type Dep = { id: string, state: string }

export type Member = {
	id: string,
	design: string,
	doc: string,
	deps: { Dep },
	files: { [string]: string },
	specs: { [string]: string },
	approval: string?,
	approvalFile: string,
}

export type Raft = {
	id: string,
	where: string,
	status: string,
	dir: string,
	design: string,
	doc: string,
	grouped: string?,
	listed: { string },
	members: { Member },
	files: { [string]: string },
	loaded: boolean,
}

local function hasCheckLine(text: string): boolean
	for line in string.gmatch(text, "[^\n]+") do
		if string.match(line, '^%s*check "') then
			return true
		end
	end
	return false
end

local function openProblem(files: { [string]: string }, doc: string): string?
	local best = 0
	for name in files do
		local found = string.match(name, "^design%-review%-(%d+)%.md$")
		local n = if found then tonumber(found) else nil
		if n and n > best then
			best = n
		end
	end
	if best == 0 then
		return nil
	end
	local num = string.format("%03d", best)
	local review = files[`design-review-{num}.md`]
	if not review then
		return nil
	end
	return openlist.problem(review, files[`design-refute-{num}.md`] or "", doc)
end

local function regrouped(map: { [string]: string }, now: { [string]: string? }): { string }
	local out: { string } = {}
	for id, recorded in map do
		local h = now[id]
		if h and h ~= recorded then
			table.insert(out, `{id} ({recorded} → {h})`)
		end
	end
	table.sort(out)
	return out
end

local function reviewCovers(files: { [string]: string }, map: { [string]: string }): boolean
	if next(map) == nil then
		return true
	end
	for name, text in files do
		if string.match(name, "^design%-review%-%d+%.md$") then
			for quoted in string.gmatch("\n" .. text, "\nGrouped: (%[[^\n]*%])") do
				local q = raftplan.parseGrouped(quoted)
				local all = true
				for id, h in map do
					if q[id] ~= h then
						all = false
					end
				end
				if all then
					return true
				end
			end
		end
	end
	return false
end

-- The grouping record and, when the raft has more than one member, the coherence review that quotes it.
function readycheck.record(
	id: string,
	grouped: string?,
	members: { Member },
	reviewFiles: { [string]: string }
): string?
	local map, problem = raftplan.parseGrouped(grouped)
	if problem then
		return `{id}: {problem}`
	end
	local now: { [string]: string? } = {}
	for _, m in members do
		now[m.id] = raftplan.recordHash(m.id, m.files)
	end
	local redesigned = regrouped(map, now)
	if #redesigned > 0 then
		return `{id}: {table.concat(redesigned, ", ")} changed on origin/main since {id} grouped it: z-raft drops it (./zn unfold {id} <id>) or folds it again with a new coherence review`
	end
	if #members > 1 and not reviewCovers(reviewFiles, map) then
		return `{id}'s coherence review predates its record: run a new raft-mode round (z-raft, zz-review); never edit a review that is already written`
	end
	return nil
end

local function disagree(r: Raft): string?
	local listed: { [string]: boolean } = {}
	for _, id in r.listed do
		listed[id] = true
	end
	local unlisted: { string } = {}
	for _, m in r.members do
		if not listed[m.id] then
			table.insert(unlisted, m.id)
		end
		listed[m.id] = nil
	end
	local missing: { string } = {}
	for id in listed do
		table.insert(missing, id)
	end
	table.sort(unlisted)
	table.sort(missing)
	if #unlisted == 0 and #missing == 0 then
		return nil
	end
	return `{r.id}'s issues: list and its members' raft: fields disagree (raft: {r.id} but not listed: {table.concat(
		unlisted,
		", "
	)}; listed without raft: {r.id}: {table.concat(missing, ", ")}); fix the documents (z-design) and ready again`
end

local function designAndCheck(id: string, design: string, doc: string, files: { [string]: string }): string?
	if design ~= "ready" then
		return `{id} is not design: ready (run z-design first)`
	end
	local gap = openProblem(files, doc)
	if gap then
		return `{id}: {gap}`
	end
	local check = files["check.sh"]
	if not check or not hasCheckLine(check) then
		return `{id} has no check: its check.sh needs at least one line starting check "..."`
	end
	return nil
end

-- The first reason `./zn ready` would refuse, or nil when it would accept. The second value is false
-- when the documents already pass and the design files have not been loaded yet: the caller loads them
-- and calls again. A refusal is complete either way.
function readycheck.reason(r: Raft): (string?, boolean)
	if r.status == "blocked" then
		return `{r.id} is blocked: ./zn resolve {r.id} <decision> first`, true
	end
	if not (r.where == "backlog" and r.status == "prepared") then
		return `{r.id} is {r.status} in {r.dir} on origin/main: only a prepared raft is readied`, true
	end
	if #r.members == 0 then
		return `{r.id} has no member issues`, true
	end
	local mismatch = disagree(r)
	if mismatch then
		return mismatch, true
	end
	if r.design ~= "ready" then
		return `{r.id} is not design: ready (run z-design first)`, true
	end
	for _, m in r.members do
		if m.design ~= "ready" then
			return `{m.id} is not design: ready (run z-design first)`, true
		end
	end
	local isMember: { [string]: boolean } = {}
	for _, m in r.members do
		isMember[m.id] = true
	end
	for _, m in r.members do
		for _, dep in m.deps do
			if not isMember[dep.id] and dep.state ~= "done" then
				return `{m.id} depends on {dep.id}, which is {dep.state} on origin/main: it must be done first`,
					true
			end
		end
	end
	if not r.loaded then
		return nil, false
	end
	local gap = designAndCheck(r.id, r.design, r.doc, r.files)
	if gap then
		return gap, true
	end
	for _, m in r.members do
		local memberGap = designAndCheck(m.id, m.design, m.doc, m.files)
		if memberGap then
			return memberGap, true
		end
		local parts, err = contract.build(m.doc, m.files["check.sh"] or "", m.specs)
		if not parts then
			return `{m.id}: {err}`, true
		end
		local changed = approval.reasonOf(m.id, m.approvalFile, parts, m.approval, true)
		if changed then
			return changed, true
		end
	end
	return nil, true
end

-- The specs the contract hashes: acceptance/ when it holds any spec, otherwise the promoted set the
-- caller already read. Same choice as approval.collect.
function readycheck.specs(files: { [string]: string }, promoted: { [string]: string }): { [string]: string }
	local specs: { [string]: string } = {}
	local any = false
	for rel, text in files do
		local rest = string.match(rel, "^acceptance/(.+%.spec%.luau)$")
		if rest then
			specs[rest] = text
			any = true
		end
	end
	if any then
		return specs
	end
	return promoted
end

function readycheck.deps(value: string?, stateOf: (string) -> string): { Dep }
	local out: { Dep } = {}
	for _, id in store.idList(value) do
		table.insert(out, { id = id, state = stateOf(id) })
	end
	return out
end

return readycheck
