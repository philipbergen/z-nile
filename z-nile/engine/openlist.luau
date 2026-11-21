--!strict
-- The one-round rule. A review is answered once. A refuted finding, a high finding that was not
-- fixed, and a Judged criterion ruled fail go to the human under `## Open to the human` in the
-- item's document. A ruling is `Ruled (user, YYYY-MM-DD):` on that bullet. Older review files
-- still parse elsewhere (metrics, `lessons --uncovered`); this module judges the one review it is given.

local openlist = {}

local RULED = "Ruled %(user, %d%d%d%d%-%d%d%-%d%d%):"

-- The body of `## <heading>`, from the line after the heading to the next `## ` heading.
local function sectionOf(doc: string, heading: string): string?
	local hay = "\n" .. doc
	local mark = "\n## " .. heading
	local s = string.find(hay, mark, 1, true)
	if not s then
		return nil
	end
	local body = s + #mark
	local nxt = string.find(hay, "\n## ", body, true)
	return if nxt then string.sub(hay, body, nxt - 1) else string.sub(hay, body)
end

-- Finding ids in a review file, with the bracketed severity or "unrated".
function openlist.findings(review: string): { { id: string, severity: string } }
	local out = {}
	for foundId, foundRest in string.gmatch("\n" .. review, "\n###%s+(F%d+)([^\n]*)") do
		local id: string = foundId :: string
		local rest: string = foundRest :: string
		local raw = string.match(rest, "^%s*%[(%a+)%]")
		local severity = "unrated"
		if raw ~= nil then
			severity = string.lower(raw :: string)
		end
		table.insert(out, { id = id, severity = severity })
	end
	return out
end

-- Judged criteria the review ruled fail (`- JC1: fail`).
function openlist.judgedFails(review: string): { string }
	local out = {}
	for id in string.gmatch("\n" .. review, "\n%- JC(%d+):%s*fail") do
		table.insert(out, "JC" .. id)
	end
	return out
end

-- The refute line's kind for one finding: fixed, refuted, deferred, other, or nil when unanswered.
function openlist.answerKind(refute: string, id: string): string?
	local line = string.match("\n" .. refute, `\n%-%s+{id}:%s*([^\n]*)`)
	if not line then
		return nil
	end
	if string.find(line, "^fixed") then
		return "fixed"
	end
	if string.find(line, "^refuted") then
		return "refuted"
	end
	if line == "deferred" or string.find(line, "^deferred%s") then
		return "deferred"
	end
	return "other"
end

-- Ids the human must rule on this one review: any refutation, any high that is not fixed, any failed Judged criterion.
function openlist.needsHuman(review: string, refute: string): { string }
	local out = {}
	for _, f in openlist.findings(review) do
		local kind = openlist.answerKind(refute, f.id)
		if kind == "refuted" or (f.severity == "high" and kind ~= "fixed") then
			table.insert(out, f.id)
		end
	end
	for _, id in openlist.judgedFails(review) do
		table.insert(out, id)
	end
	return out
end

-- Bullet ids under `## Open to the human` that have no `Ruled (user, YYYY-MM-DD):` line.
function openlist.pending(doc: string): { string }
	local section = sectionOf(doc, "Open to the human")
	if not section then
		return {}
	end
	local pending = {}
	local current: string? = nil
	local ruled = false
	local function flush()
		if current and not ruled then
			table.insert(pending, current :: string)
		end
		current = nil
		ruled = false
	end
	for line in string.gmatch(section .. "\n", "(.-)\n") do
		local id = string.match(line, "^%- (F%d+):") or string.match(line, "^%- (JC%d+):")
		if id then
			flush()
			current = id
			ruled = string.match(line, RULED) ~= nil
		elseif current and string.match(line, RULED) then
			ruled = true
		end
	end
	flush()
	return pending
end

local GUESSED = "Guessed %(agent, %d%d%d%d%-%d%d%-%d%d%):%s*(.-)%s*$"

-- f0399: the Guessed lines of bullets that have no Ruled line. `issue` is nil when the line names only a guess
-- (the document's own issue). A Guessed line that names no guess gives guess "".
function openlist.guessed(doc: string): { { id: string, issue: string?, guess: string } }
	local section = sectionOf(doc, "Open to the human")
	local out: { { id: string, issue: string?, guess: string } } = {}
	if not section then
		return out
	end
	local unruled: { [string]: boolean } = {}
	for _, id in openlist.pending(doc) do
		unruled[id] = true
	end
	local current: string? = nil
	for line in string.gmatch(section .. "\n", "(.-)\n") do
		local id = string.match(line, "^%- (F%d+):") or string.match(line, "^%- (JC%d+):")
		if id then
			current = id
		end
		local said = string.match(line, GUESSED)
		if current and said and unruled[current :: string] then
			local issue, guess = string.match(said, "^([fdc]%d%d%d%d) (G%d+)$")
			if not issue then
				guess = string.match(said, "^(G%d+)$")
			end
			table.insert(out, { id = current :: string, issue = issue, guess = guess or "" })
		end
	end
	return out
end

-- The words after the colon of bullet `id`'s Guessed line, as written (for a refusal that quotes them).
function openlist.guessedWords(doc: string, id: string): string
	local section = sectionOf(doc, "Open to the human") or ""
	local current: string? = nil
	for line in string.gmatch(section .. "\n", "(.-)\n") do
		current = string.match(line, "^%- (F%d+):") or string.match(line, "^%- (JC%d+):") or current
		local said = string.match(line, GUESSED)
		if current == id and said then
			return said
		end
	end
	return ""
end

-- f0399: bullets with neither a Ruled line nor a Guessed line.
function openlist.waiting(doc: string): { string }
	local answered: { [string]: boolean } = {}
	for _, g in openlist.guessed(doc) do
		answered[g.id] = true
	end
	local out = {}
	for _, id in openlist.pending(doc) do
		if not answered[id] then
			table.insert(out, id)
		end
	end
	return out
end

-- nil when every id that needs the human is ruled in the document. Otherwise the refusal, naming the ids.
function openlist.problem(review: string, refute: string, doc: string): string?
	local need = openlist.needsHuman(review, refute)
	if #need == 0 then
		return nil
	end
	local section = sectionOf(doc, "Open to the human") or ""
	local have: { [string]: boolean } = {}
	for id in string.gmatch("\n" .. section, "\n%- (F%d+):") do
		have[id] = true
	end
	for id in string.gmatch("\n" .. section, "\n%- (JC%d+):") do
		have[id] = true
	end
	local unruled: { [string]: boolean } = {}
	for _, id in openlist.waiting(doc) do
		unruled[id] = true
	end
	local missing = {}
	for _, id in need do
		if not have[id] or unruled[id] then
			table.insert(missing, id)
		end
	end
	if #missing == 0 then
		return nil
	end
	return `open to the human ({table.concat(missing, ", ")}): record each under ## Open to the human with Ruled (user, YYYY-MM-DD):`
end

-- f0421: the one definition of "answered" (moved verbatim from `./zn done`'s reviewProblem, after its approve check). nil
-- when every finding of `review` is answered in `refute` (or ruled under `## Open to the human` in `doc`), the
-- `consequences:` of a fixed answer are given, a deferral names a backlog issue (`isBacklog`) and is of a medium or
-- low finding, and a review with a verdict and no findings has none to answer. Otherwise the refusal `./zn done` gives.
function openlist.unanswered(p: {
	review: string,
	refute: string,
	doc: string,
	reviewName: string,
	refuteName: string,
	isBacklog: (string) -> boolean,
}): string?
	local reviewName, refuteName, raftDoc = p.reviewName, p.refuteName, p.doc
	local review = "\n" .. p.review
	local verdict = string.match(review, "\n[Vv]erdict:%s*(%a+)")
	local humanSection = string.match("\n" .. raftDoc, "\n## Open to the human\n(.-)\n## ")
		or string.match("\n" .. raftDoc, "\n## Open to the human\n(.*)$")
		or ""
	local inHuman: { [string]: boolean } = {}
	for fid in string.gmatch("\n" .. humanSection, "\n%- (F%d+):") do
		inHuman[fid] = true
	end
	local pendingSet: { [string]: boolean } = {}
	for _, fid in openlist.pending(raftDoc) do
		pendingSet[fid] = true
	end

	local refute = "\n" .. p.refute
	local missing = {}
	local invalid = {}
	local findingCount = 0
	for id, rest in string.gmatch(review, "\n###%s+(F%d+)([^\n]*)") do
		findingCount += 1
		local line = string.match(refute, `\n%-%s+{id}:%s*([^\n]*)`)
		if line and string.find(line, "^fixed") then
			if not string.find(line, "consequences:%s*%S", 6) then
				table.insert(
					invalid,
					`{id}: a fixed answer needs "; consequences: <what the fix could break, and how that was checked, or none>"`
				)
			end
			continue
		end
		if line and string.find(line, "^refuted") then
			continue
		end
		if inHuman[id] and not pendingSet[id] then
			continue
		end
		if not line or not (line == "deferred" or string.find(line, "^deferred%s")) then
			if inHuman[id] and pendingSet[id] then
				continue
			end
			table.insert(missing, id)
			continue
		end
		local target = string.match(line, "^deferred%s+([fdc]%d%d%d%d):%s*%S")
		local severity = string.match(rest or "", "^%s*%[(%a+)%]")
		local rating = if severity then string.lower(severity) else "unrated"
		if not target then
			table.insert(invalid, `{id}: deferred needs "<issue id>: <why>"`)
		elseif rating ~= "medium" and rating ~= "low" then
			table.insert(invalid, `{id} is {rating}: only a medium or low finding can be deferred`)
		elseif not p.isBacklog(target) then
			table.insert(invalid, `{id}: {target} is not a backlog issue`)
		end
	end
	if #missing > 0 then
		return `{reviewName} findings not answered in {refuteName}: {table.concat(missing, ", ")}`
	end
	if #invalid > 0 then
		return `{refuteName}: {table.concat(invalid, "; ")}`
	end
	-- one round: a refuted finding, an unclosed high, or a failed Judged criterion waits for the human
	local gap = openlist.problem(review, refute, raftDoc)
	if gap then
		return `{reviewName} {gap}`
	end
	if verdict ~= nil and findingCount == 0 and #openlist.judgedFails(review) == 0 then
		return `{reviewName} Verdict is {verdict}, not approve`
	end
	return nil
end

return openlist
