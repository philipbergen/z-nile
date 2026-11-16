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
	for _, id in openlist.pending(doc) do
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

return openlist
