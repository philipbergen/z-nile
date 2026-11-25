--!strict
-- f0450: which defects count as rework. A defect counts when it shipped: some ticket or raft it fixes (`fixes:`)
-- was already done on or before the day the defect was captured (`created:`). One that records nothing it fixes
-- counts too, and is listed until someone records it. Pure over the facts passed in; `./zn metrics` reads them.
local store = require("./store")

local rework = {}

export type Defect = { id: string, created: string?, fixes: { string }, ruled: boolean? }
export type Class = "shipped" | "open" | "unrecorded" | "ruled"
export type Verdict = { id: string, class: Class, fixes: { string } }
export type Row = { id: string, type: string, added: number, minutes: number }

-- The ids a defect's frontmatter names under `fixes:` (issues and rafts), in order.
function rework.fixesOf(front: { [string]: string }): { string }
	return store.idList(front.fixes)
end

-- The owner's ruling that a defect did not ship: `shipped: no` is honoured only when the document also holds a line
-- that names the key, `Ruled (user, YYYY-MM-DD), shipped: no: "<words>"`, outside a fenced code block, so a key typed
-- alone, or a ruling about something else, changes nothing (and `./zn audit` says so). The line is a quotation:
-- nothing here can tell the owner's words from an agent's, review of the pull request that adds it is the guard.
function rework.isRuled(front: { [string]: string }, text: string): boolean
	if front.shipped ~= "no" then
		return false
	end
	local fenced = false
	for line in string.gmatch(text, "[^\n]+") do
		if string.match(line, "^%s*```") then
			fenced = not fenced
		elseif
			not fenced
			and string.match(line, '^%s*[-*]?%s*Ruled %(user, %d%d%d%d%-%d%d%-%d%d%), shipped: no: ".+"')
		then
			return true
		end
	end
	return false
end

function rework.keyIgnored(front: { [string]: string }, text: string): boolean
	return front.shipped ~= nil and not rework.isRuled(front, text)
end

-- `doneDay` nil: no readable history, so no defect that names a fix can be judged and each counts.
function rework.classify(defects: { Defect }, doneDay: { [string]: string }?): { Verdict }
	local out: { Verdict } = {}
	for _, d in defects do
		local class: Class = "open"
		if d.ruled then
			class = "ruled"
		elseif #d.fixes == 0 then
			class = "unrecorded"
		elseif doneDay == nil or d.created == nil then
			class = "shipped"
		else
			for _, id in d.fixes do
				local day = doneDay[id]
				if day ~= nil and day <= d.created then
					class = "shipped"
					break
				end
			end
		end
		table.insert(out, { id = d.id, class = class, fixes = d.fixes })
	end
	return out
end

local function share(part: number, whole: number, flag: boolean): string
	if whole == 0 then
		return "n/a"
	end
	local p = 100 * part / whole
	return string.format("%.1f%%%s", p, if flag and p > 20 then " (OVER 20% TARGET)" else "")
end

-- The rework lines of `./zn metrics`, for the done (and with --include-active, active) issues in `rows`.
function rework.lines(rows: { Row }, verdicts: { Verdict }, historyKnown: boolean): { string }
	local classOf: { [string]: Verdict } = {}
	for _, v in verdicts do
		classOf[v.id] = v
	end
	local feature = { added = 0, minutes = 0, count = 0 }
	local all = { added = 0, minutes = 0, count = 0 }
	local shipped = { added = 0, minutes = 0, count = 0 }
	local open: { string } = {}
	local ruled: { string } = {}
	local unrecorded: { string } = {}
	for _, r in rows do
		if r.type == "feature" then
			feature.added += r.added
			feature.minutes += r.minutes
			feature.count += 1
		elseif r.type == "defect" then
			all.added += r.added
			all.minutes += r.minutes
			all.count += 1
			local v = classOf[r.id]
			local class: Class = if v then v.class else "unrecorded"
			if class == "ruled" then
				table.insert(ruled, r.id)
			elseif class == "open" then
				table.insert(open, `{r.id} (fixes {table.concat(if v then v.fixes else {}, ", ")})`)
			else
				shipped.added += r.added
				shipped.minutes += r.minutes
				shipped.count += 1
				if class == "unrecorded" then
					table.insert(unrecorded, r.id)
				end
			end
		end
	end
	table.sort(open)
	table.sort(unrecorded)
	table.sort(ruled)
	local function listed(items: { string }): string
		return if #items == 0 then "0" else `{#items}: {table.concat(items, ", ")}`
	end
	local out = {
		"Rework = shipped defects / (shipped defects + features). Target: under 20%.",
		"Rework counts every phase, capture to deliver. A defect counts when what it fixes (fixes:) was done when it was captured.",
		`  by lines added:  {share(shipped.added, shipped.added + feature.added, true)}`,
		`  by issues:       {share(shipped.count, shipped.count + feature.count, true)}`,
		`  by agent time:   {share(shipped.minutes, shipped.minutes + feature.minutes, true)}`,
		`  all defects, shipped or not (the figure before f0450): by lines added {share(
			all.added,
			all.added + feature.added,
			false
		)}, by issues {share(all.count, all.count + feature.count, false)}, by agent time {share(
			all.minutes,
			all.minutes + feature.minutes,
			false
		)}`,
		`  defects not counted, the work they fix was still open when they were captured: {listed(open)}`,
		`  defects not counted by the owner's ruling (shipped: no): {listed(ruled)}`,
		`  defects with no fixed ticket recorded: {listed(unrecorded)}{if #unrecorded > 0
			then " (counted as shipped until someone records what each fixes)"
			else ""}`,
	}
	if not historyKnown then
		table.insert(
			out,
			"  no readable git history here: the day each fixed ticket was done is unknown, so every defect that names a fix counts."
		)
	end
	return out
end

return rework
