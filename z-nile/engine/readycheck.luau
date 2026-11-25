--!strict
-- Whether `./zn ready` would accept a raft. Pure: texts in, the first refusal or nil. No push, no move.
-- `readycheck.reason` is every check `./zn ready` makes before the carried move, but for the grouping record. `./zn work next`
-- refuses a raft when this is not nil, and does not push. Rank is not this function.
--
-- The grouping record is not part of `reason`. `./zn ready` judges it (`readycheck.record`) first, for a prepared
-- backlog raft, on origin/main's tree just pulled, then again inside the carried move's validator, on the tree being
-- published, so an ignored file on disk (acceptance/.DS_Store) never changes a member's hash. `./zn work next` calls
-- `record` itself (workread.blockFor), on origin/main's tracked files, before `reason`. Both name a redesigned member
-- ahead of its stale approval. A raft proceeds only when `record` and `reason` are both nil.

local approval = require("./approval")
local contract = require("./contract")
local easy = require("./easy")
local guesses = require("./guesses")
local openlist = require("./openlist")
local raftplan = require("./raftplan")
local rounds = require("./rounds")
local statusLib = require("./status")
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
	questions: boolean,
	listed: { string },
	members: { Member },
	files: { [string]: string },
	loaded: boolean,
	requireApproval: boolean?, -- f0399: under ./zn dispatch every member needs an approval that holds
	light: boolean?, -- c0435: the raft is the light path's single raft: an easy member may have no design review
	onMembers: { string }?, -- f0399: the members of the raft this one is built on (--on), taken as done
}

-- f0399: a Guessed line under "Open to the human" must name a guess that is recorded. `own` is the issue a line
-- naming only a guess means (the document's issue, or a raft's first member); `textOf` gives an issue's guesses.md.
function readycheck.guessedProblem(id: string, doc: string, own: string, textOf: (string) -> string?): string?
	for _, g in openlist.guessed(doc) do
		local issue = g.issue or own
		if g.guess == "" or not guesses.has(textOf(issue), g.guess) then
			local named = if g.guess == "" then openlist.guessedWords(doc, g.id) else `{issue} {g.guess}`
			return `{id}: {g.id}'s Guessed line names {named}, which is not in {issue}'s guesses.md`
		end
	end
	return nil
end

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
	return openlist.problem(review, files[`design-refute-{num}.md`] or "", doc, `design-review-{num}.md`)
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
	if #members > 1 and not raftplan.reviewCovers(reviewFiles, map) then
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
	if not (r.where == "backlog" and r.status == "prepared") then
		return `{r.id} is {r.status} in {r.dir} on origin/main: only a prepared raft is readied`, true
	end
	if r.questions then
		return `{r.id} has questions.md: a human has to answer before it can be readied`, true
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
	local onBase: { [string]: boolean } = {}
	for _, id in r.onMembers or {} :: { string } do
		onBase[id] = true
	end
	for _, m in r.members do
		for _, dep in m.deps do
			if not isMember[dep.id] and not onBase[dep.id] and dep.state ~= "done" then
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
		local _, levelBad = easy.raised(easy.reviewTexts(m.files))
		if levelBad then
			return `{m.id}: {levelBad}: fix the review's Level line before it is readied`, true
		end
		-- c0435: an easy ticket skips its design review only on the light path (where the final review stands in)
		local front = (string.match(m.doc, "^%-%-%-\n(.-)\n%-%-%-") or "") .. "\n"
		local risk = string.match("\n" .. front, "\nrisk:[ ]*([^\n]-)[ ]*\n")
		if r.light ~= true and rounds.level(risk) == "easy" and not easy.hasDesignReview(m.files) then
			return `{m.id} is easy with no design review, and it does not take the light path: it takes the full design path (z-design, a design review) before it is readied`,
				true
		end
		local guessText = m.files[guesses.FILE]
		if guessText then
			local _, problem = guesses.parse(guessText)
			if problem then
				return `{m.id}: {guesses.FILE}: {problem}`, true
			end
		end
		-- c0161, "Check at next read": a member whose newest design round quotes a record must still match it. A member
		-- none of whose rounds quotes one predates the rule and is exempt. `./zn ready` and `./zn work next` share this.
		local stale = statusLib.preparedReadProblem(m.files, raftplan.designRecord(m.id, m.files))
		if stale then
			return `{m.id} {stale}`, true
		end
		local parts, err = contract.build(m.doc, m.files["check.sh"] or "", m.specs, guessText)
		if not parts then
			return `{m.id}: {err}`, true
		end
		-- f0399: outside the dispatcher no approval is asked for here (done asks), and a guess recorded since an
		-- approval is let through; an approved contract edited in any other part goes back to the person first.
		if r.requireApproval then
			local changed = approval.reasonOf(m.id, m.approvalFile, parts, m.approval, true)
			if changed then
				return changed, true
			end
		elseif m.approval then
			if approval.standing(m.approval, parts) == "stale" then
				return approval.reasonOf(m.id, m.approvalFile, parts, m.approval, true), true
			end
		end
	end
	local first = if r.members[1] then r.members[1].id else ""
	local byId: { [string]: Member } = {}
	for _, m in r.members do
		byId[m.id] = m
	end
	local bad = readycheck.guessedProblem(r.id, r.doc, first, function(id: string): string?
		return if byId[id] then byId[id].files[guesses.FILE] else nil
	end)
	if bad then
		return bad, true
	end
	for _, m in r.members do
		local memberBad = readycheck.guessedProblem(m.id, m.doc, m.id, function(id: string): string?
			return if byId[id] then byId[id].files[guesses.FILE] else nil
		end)
		if memberBad then
			return memberBad, true
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
