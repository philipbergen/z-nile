--!strict
-- Skill lessons (c0111): one Markdown file per lesson under <skills folder>/<skill>/lessons/<slug>.md (z-nile/skills or
-- <project>/skills, c0115; .claude/skills in a tree from before c0115), and a
-- harvest.md ledger in each reviewed item's folder mapping every review finding to the lessons it taught, or
-- marking it one-off. Everything here is pure over texts except `load`, which only reads.
local fs = require("@lune/fs")
local projects = require("./projects")
local skillsLib = require("./skills")

local stats = require("./stats")

local lessons = {}

export type When = "design" | "build" | "both"
export type Lesson = {
	id: string,
	skill: string,
	slug: string,
	title: string,
	when: When,
	tags: { string },
	check: string,
	from: string?,
	body: string,
}
-- a review entry names a finding (review, finding); a note entry (`- note <text>: <ids>`) is a source that is not a
-- review finding: review is "note", finding is "", and note holds the text
export type Entry = {
	item: string,
	review: string,
	finding: string,
	lessons: { string },
	oneOff: string?,
	note: string?,
	-- c0136: the step that erred (a skill, or "none") and the earlier step that should have prevented it, from the
	-- `(erred <skill>[, upstream <skill>])` group before the colon; nil on an entry written without one
	erred: string?,
	upstream: string?,
}
-- one reviewed item: review stem -> text (design-review-NNN, review-NNN), and its harvest.md text if any
export type Item = { id: string, reviews: { [string]: string }, harvest: string? }
export type Tree = {
	lessons: { [string]: string },
	found: { [string]: boolean }, -- every item folder seen, reviewed or not
	skills: { [string]: boolean },
	-- c0115: each skill's real folder ("z-nile/skills/zz-test") and the project it belongs to; nil in hand-built trees
	folders: { [string]: string }?,
	owners: { [string]: string }?,
	items: { Item },
	problems: { string },
}
export type Query =
	{ skills: { string }?, when: ("design" | "build")?, tags: { string }?, words: { string }? }

-- c0136 (c0140): the steps that happen in design. A mistake one of them made, or should have caught, is a lesson design
-- reads: a harvest line naming one refuses a lesson that is `when: build`.
lessons.DESIGN_STEPS = { "z-idea", "z-ticket", "z-design", "z-raft" }

local KEBAB = "^[a-z0-9]+%-?[a-z0-9%-]*$"
local KEYS = { title = true, when = true, tags = true, check = true, from = true }
local WHEN = { design = true, build = true, both = true }

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end

local function kebab(s: string): boolean
	return string.match(s, KEBAB) ~= nil and string.sub(s, -1) ~= "-" and string.find(s, "--", 1, true) == nil
end

-- c0136: the one rule for a pair of steps, spelled as a harvest group or as a review's two lines. `upstream` is nil
-- when none. Returns the problem, or nil. A skill is lowercase kebab; `none` is only an `erred` with no upstream.
local function validSteps(erred: string, upstream: string?): string?
	if erred ~= "none" and not kebab(erred) then
		return "erred is a skill name or none"
	end
	if upstream ~= nil and (upstream == "none" or not kebab(upstream)) then
		return "upstream is a skill name, or left out for none"
	end
	if erred == "none" and upstream ~= nil then
		return "erred none has no upstream"
	end
	if upstream == erred then
		return "upstream is the same step as erred"
	end
	return nil
end

function lessons.parse(id: string, text: string): (Lesson?, string?)
	local skill, slug = string.match(id, "^([^/]+)/([^/]+)$")
	if not skill or not slug then
		return nil, `{id}: an id is <skill>/<slug>`
	end
	if not kebab(slug) then
		return nil, `{id}: the slug must be lowercase kebab`
	end
	local front, body = string.match(text, "^%-%-%-\n(.-)\n%-%-%-\n?(.*)$")
	if not front or not body then
		return nil, `{id}: no frontmatter`
	end
	local f: { [string]: string } = {}
	for line in string.gmatch(front, "[^\n]+") do
		local k, v = string.match(line, "^([%w_%-]+):(.*)$")
		if not k or not v then
			return nil, `{id}: a frontmatter line is not key: value: {line}`
		end
		if not KEYS[k] then
			return nil, `{id}: unknown key {k}`
		end
		if f[k] ~= nil then
			return nil, `{id}: {k} is repeated`
		end
		f[k] = trim(v)
	end
	if not f.title or f.title == "" then
		return nil, `{id}: title is required`
	end
	if not f.when or not WHEN[f.when] then
		return nil, `{id}: when must be design, build or both`
	end
	local list = f.tags and string.match(f.tags, "^%[(.*)%]$")
	if not list then
		return nil, `{id}: tags must be a [a, b] list`
	end
	local tags = {}
	for tag in string.gmatch(list, "[^,]+") do
		local tg = trim(tag)
		if not kebab(tg) then
			return nil, `{id}: tags must be lowercase kebab: {tg}`
		end
		if table.find(tags, tg) then
			return nil, `{id}: tag {tg} is repeated`
		end
		table.insert(tags, tg)
	end
	if #tags == 0 then
		return nil, `{id}: tags needs at least one tag`
	end
	if not f.check or not string.match(f.check, "%?$") then
		return nil, `{id}: check must be one line ending in ?`
	end
	if trim(body) == "" then
		return nil, `{id}: the body is empty`
	end
	local from = if f.from and f.from ~= "" then f.from else nil
	return {
		id = id,
		skill = skill,
		slug = slug,
		title = f.title,
		when = f.when :: When,
		tags = tags,
		check = f.check,
		from = from,
		body = body,
	},
		nil
end

function lessons.findings(review: string): { string }
	local out = {}
	-- the pattern tracker.sh done reads (reviewProblem)
	for id in string.gmatch("\n" .. review, "\n###%s+(F%d+)") do
		table.insert(out, id)
	end
	return out
end

local function isStem(stem: string): boolean
	return string.match(stem, "^design%-review%-%d%d%d$") ~= nil
		or string.match(stem, "^review%-%d%d%d$") ~= nil
		or string.match(stem, "^final%-review%-%d%d%d$") ~= nil
		or string.match(stem, "^stream%-review%-[fdc]%d%d%d%d%-%d%d%d$") ~= nil -- c0136
		or string.match(stem, "^focused%-review%-%d%d%d$") ~= nil -- c0136
end

-- c0136: a step named in a record that is never edited (a review file, a ledger) is read through the rename table, so a
-- skill that is renamed later (skills.RENAMED, c0115) keeps its old records valid.
local function canon(name: string, skills: { [string]: boolean }?): string
	if skills and skills[name] then
		return name -- a skill that exists under that name is never mapped away
	end
	local renamed = skillsLib.RENAMED[name] or name
	return skillsLib.MOVED[renamed] or renamed -- a skill renamed twice reads as its latest name (c0436)
end

-- c0436: a skill's name with an alias read as the skill it became (z-ticket as z-idea): two records name one step when
-- they spell it either way. Pure.
local function same(a: string?, b: string?): boolean
	if a == nil or b == nil then
		return a == b
	end
	return (skillsLib.MOVED[a] or a) == (skillsLib.MOVED[b] or b)
end

-- c0136: a note about a finding starts with its head, `<stem> F<n> <text>`: returns the stem, the finding and the rest.
-- The one reader for the waiver note and for the phase of a note.
function lessons.noteHead(text: string): (string?, string?, string)
	local stem, finding, rest = string.match(text, "^(%S+) (F%d+)%s*(.*)$")
	if stem and finding and isStem(stem) then
		return stem, finding, rest or ""
	end
	return nil, nil, text
end

-- c0136: the phase a focused review's heading names, `(focused mode, design)` or `(focused mode, build)`, exactly those
-- words; `none` for any other heading (a missing word, `Design`, `both`): an unreadable phase is never read as build.
local function headingPhase(text: string): string
	local word = string.match(string.match(text, "^[^\n]*") or "", "%(focused mode, (%a+)%)")
	return if word == "design" or word == "build" then word else "none"
end

-- c0136: the phase a review looked at, which decides whether its findings are design's: a design round (an issue's, or
-- z-raft's coherence round) is `design`; a focused review says so in its heading; every other review is `build`.
function lessons.reviewPhase(stem: string, text: string): string
	if string.match(stem, "^design%-review%-") then
		return "design"
	end
	if string.match(stem, "^focused%-review%-") then
		return headingPhase(text)
	end
	return "build"
end

-- c0136: what a reviewer wrote under each finding: `Erred: <skill|none>` (the step that made the mistake) and
-- `Upstream: <skill|none>` (an earlier step that should have prevented or caught it). Returns the finding id -> steps
-- (`upstream` is nil for `none`), and the problems of a file that uses the lines: a repeated or malformed line, or a
-- finding missing one of the two once any finding has either. A file with neither line anywhere (written before
-- c0136) has no steps and no problems.
export type FindingSteps = { erred: string, upstream: string? }
-- The fence a line opens or closes: its character and length, when it has up to three spaces then three or more
-- backticks or tildes (CommonMark); nil otherwise.
local function fenceOf(line: string): (string?, number)
	local indent, run = string.match(line, "^( *)([`~]+)")
	if indent == nil or run == nil or #indent > 3 or #run < 3 then
		return nil, 0
	end
	local c = string.sub(run, 1, 1)
	if string.find(run, if c == "`" then "~" else "`", 1, true) then
		return nil, 0 -- a run that mixes both characters is not a fence
	end
	return c, #run
end

-- One pass over a review: the Erred and Upstream value of each finding, the findings in order (every `### F<n>`
-- heading, as `lessons.findings` and `done` read them, a fenced one included), and the problems of the lines. With
-- `fences` a line inside a fenced code block is not read; it returns whether a fence was still open at the end.
local function scanSteps(review: string, fences: boolean)
	local erred: { [string]: string } = {}
	local upstream: { [string]: string } = {}
	local order: { string } = {}
	local problems: { string } = {}
	local bad: { [string]: boolean } = {}
	local current: string? = nil
	local fence: string? = nil
	local fenceLen = 0
	for line in string.gmatch(review .. "\n", "([^\n]*)\n") do
		local id = string.match(line, "^###%s+(F%d+)")
		if id then
			current = id
			table.insert(order, id)
			continue
		end
		if fences then
			local c, n = fenceOf(line)
			if fence == nil and c ~= nil then
				fence, fenceLen = c, n
				continue
			elseif fence ~= nil and c == fence and n >= fenceLen and string.match(line, "^ *[`~]+%s*$") then
				fence = nil
				continue
			end
			if fence ~= nil then
				continue
			end
		end
		if string.sub(line, 1, 3) == "## " then
			current = nil -- a section after the findings (Judged criteria) is no finding's
			continue
		end
		local key, value = string.match(line, "^(%a+):%s*(.-)%s*$")
		if current and (key == "Erred" or key == "Upstream") then
			local into = if key == "Erred" then erred else upstream
			if into[current] ~= nil then
				table.insert(problems, `{current}: {key}: is repeated`)
				bad[current] = true
			elseif value == nil or not kebab(value) then
				table.insert(problems, `{current}: {key}: needs a skill name or none`)
				bad[current] = true
			else
				into[current] = value
			end
		end
	end
	return erred, upstream, order, problems, bad, fence ~= nil
end

function lessons.findingSteps(
	review: string,
	skills: { [string]: boolean }?
): ({ [string]: FindingSteps }, { string })
	local erred, upstream, order, problems, bad, open = scanSteps(review, true)
	if open then
		-- a fence that is never closed would hide every line after it as quoted: read the file with no fences at all, so a
		-- slip shows as a problem and not as a review that has no lines
		erred, upstream, order, problems, bad = scanSteps(review, false)
	end
	local out: { [string]: FindingSteps } = {}
	local used = next(erred) ~= nil or next(upstream) ~= nil
	for _, id in order do
		if bad[id] then
			continue
		end
		local e, up = erred[id], upstream[id]
		if e and up then
			local u: string? = if up == "none" then nil else up
			local problem = validSteps(e, u)
			if problem then
				table.insert(problems, `{id}: Erred: {e}, Upstream: {up}: {problem}`)
				continue
			end
			if skills then
				local unknown = false
				if e ~= "none" and not skills[canon(e, skills)] then
					table.insert(problems, `{id}: Erred: no skill {e}`)
					unknown = true
				end
				if u ~= nil and not skills[canon(u, skills)] then
					table.insert(problems, `{id}: Upstream: no skill {u}`)
					unknown = true
				end
				if unknown then
					continue
				end
			end
			out[id] = { erred = canon(e, skills), upstream = if u then canon(u, skills) else nil }
		elseif used then
			table.insert(problems, `{id}: write both Erred: and Upstream: (none when no step applies)`)
		end
	end
	return out, problems
end

-- c0136: what a reviewer or a lead checks on a NEW review before it is handed back or committed (`--check-review`):
-- the problems of its step lines, a file that has findings and no lines at all (a new review gives every finding
-- both), and a focused heading with no readable phase (judged from the text, whatever the file is called). A file
-- with no finding (an approving round) passes. Old reviews are never run through it.
function lessons.checkNewReview(stem: string, text: string, skills: { [string]: boolean }?): { string }
	local steps, problems = lessons.findingSteps(text, skills)
	local out = table.clone(problems)
	local findings = lessons.findings(text)
	if #findings > 0 and next(steps) == nil and #problems == 0 then
		table.insert(
			out,
			"no step lines: a new review gives every finding Erred: and Upstream: at the start of a line, unbolded (zz-review)"
		)
	end
	local first = string.match(text, "^[^\n]*") or ""
	if
		(string.match(stem, "^focused%-review%-") or string.find(first, "(focused mode", 1, true))
		and headingPhase(text) == "none"
	then
		table.insert(out, "the heading must say (focused mode, design) or (focused mode, build)")
	end
	return out
end

-- the step group as an entry or a message spells it
local function stepsText(erred: string, upstream: string?): string
	return if upstream then `erred {erred}, upstream {upstream}` else `erred {erred}`
end

local function twice(ids: { string }): string?
	for i, id in ids do
		if table.find(ids, id, i + 1) then
			return id
		end
	end
	return nil
end

-- c0136: the step group `(erred <skill>)` or `(erred <skill>, upstream <skill>)`, given its text between the
-- parentheses. A skill is lowercase kebab; erred alone may be `none` (no step erred). Returns erred, upstream, or a problem.
local function parseSteps(inner: string): (string?, string?, string?)
	local erred, upstream = string.match(inner, "^erred ([^%s,]+), upstream ([^%s,]+)$")
	if not erred then
		erred = string.match(inner, "^erred ([^%s,]+)$")
	end
	if not erred then
		return nil, nil, "the step group is (erred <skill>) or (erred <skill>, upstream <skill>)"
	end
	local problem = validSteps(erred, upstream)
	if problem then
		return nil, nil, problem
	end
	return erred, upstream, nil
end

function lessons.parseHarvest(item: string, text: string): ({ Entry }, { string })
	local entries: { Entry } = {}
	local problems: { string } = {}
	local seen: { [string]: boolean } = {}
	for line in string.gmatch(text, "[^\n]+") do
		if string.sub(line, 1, 2) ~= "- " then
			continue
		end
		local noteText, ids = string.match(line, "^%- note (.*): ([^:]*)$")
		if noteText then
			local note = trim(noteText)
			local entry: Entry = { item = item, review = "note", finding = "", lessons = {}, note = note }
			-- c0136: a trailing `(erred …)` group belongs to the entry, not to the note's text
			local base, inner = string.match(note, "^(.-)%s*%((erred [^()]*)%)$")
			local stepProblem: string? = nil
			if base and inner then
				note = trim(base)
				entry.note = note
				entry.erred, entry.upstream, stepProblem = parseSteps(inner)
			end
			for id in string.gmatch(ids :: string, "[^,]+") do
				table.insert(entry.lessons, trim(id))
			end
			if stepProblem then
				table.insert(problems, `{item}/harvest.md: note {note}: {stepProblem}`)
			elseif note == "" then
				table.insert(problems, `{item}/harvest.md: note: a note needs its text`)
			elseif #entry.lessons == 0 or table.find(entry.lessons, "") then
				table.insert(problems, `{item}/harvest.md: note {note}: the target must be lesson ids`)
			elseif entry.erred == "none" then
				table.insert(problems, `{item}/harvest.md: note {note}: erred none names no lesson`)
			else
				local ok = true
				for _, lid in entry.lessons do
					ok = ok and string.match(lid, "^[%w%-]+/[a-z0-9%-]+$") ~= nil
				end
				local dup = twice(entry.lessons)
				if dup then
					table.insert(problems, `{item}/harvest.md: note {note}: lesson {dup} is named twice`)
				elseif ok then
					table.insert(entries, entry)
				else
					table.insert(problems, `{item}/harvest.md: note {note}: the target must be lesson ids`)
				end
			end
			continue
		end
		local stem, finding, rest = string.match(line, "^%- (%S+) (F%d+)(.*)$")
		-- c0136: `: target`, or ` (erred …): target`
		local inner, target = string.match(rest or "", "^%s*%(([^()]*)%)%s*:%s*(.-)%s*$")
		if not inner then
			target = string.match(rest or "", "^:%s*(.-)%s*$")
		end
		if not stem or not finding or not target or not isStem(stem) then
			table.insert(problems, `{item}/harvest.md: not an entry: {line}`)
			continue
		end
		local key = `{stem} {finding}`
		local entry: Entry = { item = item, review = stem, finding = finding, lessons = {}, oneOff = nil }
		if inner then
			local stepProblem: string?
			entry.erred, entry.upstream, stepProblem = parseSteps(inner)
			if stepProblem then
				table.insert(problems, `{item}/harvest.md: {key}: {stepProblem}: ({inner})`)
				continue
			end
		end
		local reason = string.match(target, "^one%-off:%s*(.*)$")
		if reason then
			if trim(reason) == "" then
				table.insert(problems, `{item}/harvest.md: {key}: a one-off needs a reason`)
				continue
			end
			entry.oneOff = trim(reason)
		else
			local ok = target ~= ""
			for id in string.gmatch(target, "[^,]+") do
				local lid = trim(id)
				if not string.match(lid, "^[%w%-]+/[a-z0-9%-]+$") then
					ok = false
					break
				end
				table.insert(entry.lessons, lid)
			end
			if not ok then
				table.insert(
					problems,
					`{item}/harvest.md: {key}: the target is neither lesson ids nor one-off: {target}`
				)
				continue
			end
		end
		local dup = twice(entry.lessons)
		if dup then
			table.insert(problems, `{item}/harvest.md: {key}: lesson {dup} is named twice`)
			continue
		end
		if entry.erred == "none" and #entry.lessons > 0 then
			table.insert(problems, `{item}/harvest.md: {key}: erred none names no lesson`)
			continue
		end
		if seen[key] then
			table.insert(problems, `{item}/harvest.md: {key}: a second entry for the same finding`)
			continue
		end
		seen[key] = true
		table.insert(entries, entry)
	end
	return entries, problems
end

local function num(finding: string): number
	return tonumber(string.sub(finding, 2)) :: number
end

local function stems(item: Item): { string }
	local out = {}
	for stem in item.reviews do
		table.insert(out, stem)
	end
	table.sort(out)
	return out
end

local function byId(items: { Item }): { Item }
	local out = table.clone(items)
	table.sort(out, function(a, b)
		return a.id < b.id
	end)
	return out
end

local function entriesOf(item: Item): { Entry }
	if not item.harvest then
		return {}
	end
	local e = lessons.parseHarvest(item.id, item.harvest)
	return e
end

function lessons.sources(items: { Item }): { [string]: { string } }
	local out: { [string]: { string } } = {}
	for _, item in byId(items) do
		-- review entries in review and finding order, then notes in file order
		local reviews: { Entry }, notes: { Entry } = {}, {}
		for _, e in entriesOf(item) do
			table.insert(if e.note then notes else reviews, e)
		end
		table.sort(reviews, function(a, b)
			if a.review ~= b.review then
				return a.review < b.review
			end
			return num(a.finding) < num(b.finding)
		end)
		for _, list in { reviews, notes } do
			for _, e in list do
				for _, id in e.lessons do
					-- c0436: an old record names a moved skill's lesson by its old id: it is a source of both
					local source = if e.note
						then `{e.item} note {e.note}`
						else `{e.item} {e.review} {e.finding}`
					for _, lid in { id, skillsLib.movedId(id) } do
						out[lid] = out[lid] or {}
						if not table.find(out[lid], source) then
							table.insert(out[lid], source)
						end
					end
				end
			end
		end
	end
	return out
end

function lessons.uncovered(items: { Item }): { string }
	local out = {}
	for _, item in byId(items) do
		local named: { [string]: boolean } = {}
		for _, e in entriesOf(item) do
			named[`{e.review} {e.finding}`] = true
		end
		for _, stem in stems(item) do
			local fs_ = lessons.findings(item.reviews[stem])
			table.sort(fs_, function(a, b)
				return num(a) < num(b)
			end)
			for _, f in fs_ do
				if not named[`{stem} {f}`] then
					table.insert(out, `{item.id} {stem} {f}`)
				end
			end
		end
	end
	return out
end

-- c0136: the harvest entries that name no step: `<item> <review> <finding>` for a review entry, `<item> note <text>`
-- for a note. A finding with no entry at all is `uncovered`'s, not listed here.
function lessons.unattributed(items: { Item }): { string }
	local out = {}
	for _, item in byId(items) do
		for _, e in entriesOf(item) do
			if e.erred == nil then
				table.insert(
					out,
					if e.note then `{item.id} note {e.note}` else `{item.id} {e.review} {e.finding}`
				)
			end
		end
	end
	return out
end

-- findings per lesson tag: every review entry (not a note, not one-off) that names a lesson carrying the tag counts
-- once for that tag, however many of its lessons carry it; `items` counts the distinct items those findings are in.
-- Most findings first, then tag order. A lesson id that `all` does not hold adds nothing.
export type TagCount = { tag: string, findings: number, items: number }
function lessons.tagCounts(all: { Lesson }, items: { Item }): { TagCount }
	local tagsOf: { [string]: { string } } = {}
	for _, l in all do
		tagsOf[l.id] = l.tags
	end
	local findings: { [string]: number } = {}
	local seen: { [string]: { [string]: boolean } } = {}
	for _, item in byId(items) do
		for _, e in entriesOf(item) do
			if e.note then
				continue
			end
			local hit: { [string]: boolean } = {}
			for _, lid in e.lessons do
				local tags: { string } = tagsOf[lid] or {}
				for _, tag in tags do
					hit[tag] = true
				end
			end
			for tag in hit do
				findings[tag] = (findings[tag] or 0) + 1
				seen[tag] = seen[tag] or {}
				seen[tag][item.id] = true
			end
		end
	end
	local out: { TagCount } = {}
	for tag, n in findings do
		local k = 0
		for _ in seen[tag] do
			k += 1
		end
		table.insert(out, { tag = tag, findings = n, items = k })
	end
	table.sort(out, function(a, b)
		if a.findings ~= b.findings then
			return a.findings > b.findings
		end
		return a.tag < b.tag
	end)
	return out
end

-- The day number (days since 1970-01-01) of a `YYYY-MM-DD` date, or nil when it is not one. The arithmetic is
-- stats.day's (one reader per format); this adds the range check.
function lessons.day(date: string): number?
	local y, m, d = string.match(date, "^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
	if not y then
		return nil
	end
	local month, dd = tonumber(m) or 0, tonumber(d) or 0
	if month < 1 or month > 12 or dd < 1 or dd > 31 then
		return nil
	end
	return stats.day(date)
end

-- design review rounds before and after lessons existed. `start` is a raft's `created:` day (`lessons.day`); `cutoff`
-- the day the lessons module was first added (scripts/tracker/lessons.luau, before c0114 moved it). A raft whose start is at
-- or after the cutoff is "after"; with no cutoff every dated raft is "before"; a raft with no start counts nowhere.
export type RaftRounds = { id: string, rounds: number, start: number? }
export type Split = { rafts: number, rounds: number, mean: number }
function lessons.roundsSplit(rafts: { RaftRounds }, cutoff: number?): { before: Split, after: Split }
	local before: Split = { rafts = 0, rounds = 0, mean = 0 }
	local after: Split = { rafts = 0, rounds = 0, mean = 0 }
	for _, r in rafts do
		if r.start == nil or r.rounds == 0 then
			continue
		end
		local side = if cutoff ~= nil and (r.start :: number) >= cutoff then after else before
		side.rafts += 1
		side.rounds += r.rounds
	end
	for _, side in { before, after } do
		side.mean = if side.rafts > 0 then side.rounds / side.rafts else 0
	end
	return { before = before, after = after }
end

function lessons.check(tree: Tree): { string }
	local problems: { string } = table.clone(tree.problems)
	local seen: { [string]: boolean } = {}
	local function add(p: string)
		if not seen[p] then
			seen[p] = true
			table.insert(problems, p)
		end
	end
	for _, p in tree.problems do
		seen[p] = true
	end
	local sources = lessons.sources(tree.items)
	for id, text in tree.lessons do
		local l, err = lessons.parse(id, text)
		if not l then
			add(err :: string)
			continue
		end
		if not tree.skills[l.skill] then
			add(`{id}: no skill {l.skill} (no {l.skill}/SKILL.md in any skills folder)`)
		end
		if not sources[id] and not l.from then
			add(`{id}: no source: no harvest entry names it and it has no from`)
		end
	end
	for _, item in tree.items do
		-- c0136: the problems of each review's step lines, per finding
		local stepProblems: { [string]: { [string]: boolean } } = {}
		local lineProblems: { { stem: string, finding: string, text: string } } = {}
		-- each review's step lines are read once per item (R0068 review-001 F3); the tables are only read below
		local boundSteps: { [string]: { [string]: FindingSteps } } = {}
		for stem, text in item.reviews do
			stepProblems[stem] = {}
			local bound, bad = lessons.findingSteps(text, tree.skills)
			boundSteps[stem] = bound
			for _, p in bad do
				local finding = string.match(p, "^(F%d+):") or ""
				stepProblems[stem][finding] = true
				table.insert(lineProblems, { stem = stem, finding = finding, text = p })
			end
		end
		local entries: { Entry } = {}
		if item.harvest then
			local bad: { string }
			entries, bad = lessons.parseHarvest(item.id, item.harvest)
			for _, p in bad do
				add(p)
			end
		end
		-- a focused review whose heading names no readable phase is a problem; a committed one is never edited, so a note
		-- `- note focused-review-NNN phase <design|build> (erred zz-review): <lessons>` supplies the phase and clears it
		local phaseOf: { [string]: string } = {}
		for stem, text in item.reviews do
			phaseOf[stem] = lessons.reviewPhase(stem, text)
		end
		for _, e in entries do
			local stem, word = string.match(e.note or "", "^(%S+) phase (%a+)$")
			if e.note and stem and word then
				local who = `{item.id}/harvest.md: note {e.note}`
				if not string.match(stem, "^focused%-review%-%d%d%d$") then
					add(`{who}: a phase note names a focused review`)
				elseif e.erred ~= "zz-review" then
					add(`{who}: a phase note is (erred zz-review)`)
				elseif word ~= "design" and word ~= "build" then
					add(`{who}: the phase is design or build`)
				elseif not item.reviews[stem] then
					add(`{who}: no {stem}.md in {item.id}`)
				elseif phaseOf[stem] ~= "none" then
					add(`{who}: {stem}.md already names its phase`)
				else
					phaseOf[stem] = word
				end
			end
		end
		for stem, phase in phaseOf do
			if phase == "none" then
				add(
					`{item.id}/{stem}.md: the heading must say (focused mode, design) or (focused mode, build)`
				)
			end
		end
		-- a review committed with step lines that cannot be read is never edited: a note
		-- `- note <stem> F<n> step lines invalid (erred zz-review): <lessons>` waives that finding's problems, and only a
		-- finding that has one
		local waived: { [string]: boolean } = {}
		for _, e in entries do
			local stem, finding, rest = lessons.noteHead(e.note or "")
			if
				e.note
				and stem
				and finding
				and string.sub(rest, 1, #"step lines invalid") == "step lines invalid"
			then
				local who = `{item.id}/harvest.md: note {e.note}`
				if e.erred ~= "zz-review" then
					add(`{who}: a waiver note is (erred zz-review)`)
				elseif not item.reviews[stem] then
					add(`{who}: no {stem}.md in {item.id}`)
				elseif not stepProblems[stem][finding] then
					add(`{who}: {stem}.md {finding} has no step-line problem to waive`)
				else
					waived[`{stem} {finding}`] = true
				end
			end
		end
		for _, lp in lineProblems do
			if not waived[`{lp.stem} {lp.finding}`] then
				add(`{item.id}/{lp.stem}.md {lp.text}`)
			end
		end
		-- c0136: whether a finding is design's is a fact about the finding, computed once and applied to its entry and
		-- to every note headed for it: its review is a design round (or unreadable), or the step lines that bind or the
		-- group of its entry name a design step
		local findingDesign: { [string]: boolean } = {}
		local function isDesignStep(name: string?): boolean
			return name ~= nil and table.find(lessons.DESIGN_STEPS, canon(name, tree.skills)) ~= nil
		end
		for stem in item.reviews do
			for finding, bound in boundSteps[stem] do
				if isDesignStep(bound.erred) or isDesignStep(bound.upstream) then
					findingDesign[`{stem} {finding}`] = true
				end
			end
		end
		for _, e in entries do
			if not e.note and (isDesignStep(e.erred) or isDesignStep(e.upstream)) then
				findingDesign[`{e.review} {e.finding}`] = true
			end
		end
		for _, e in entries do
			-- c0136: the named steps are skills, and a lesson is filed under one of them
			local who = if e.note
				then `{item.id}/harvest.md: note {e.note}`
				else `{item.id}/harvest.md: {e.review} {e.finding}`
			-- a note about a finding must name a review of this item and a finding that review has, as an entry must
			local noteStem, noteFinding, noteRest = lessons.noteHead(e.note or "")
			if
				e.note
				and noteStem
				and noteFinding
				and string.sub(noteRest, 1, #"step lines invalid") ~= "step lines invalid"
			then
				local review = item.reviews[noteStem]
				if not review then
					add(`{who}: no {noteStem}.md in {item.id}`)
				elseif not table.find(lessons.findings(review), noteFinding) then
					add(`{who}: {noteStem}.md has no {noteFinding}`)
				end
			end
			-- an attempt at a head that does not read (a typo'd stem, a lowercase f1, a comma) is a message, never an
			-- unjudged note; legacy notes (no group) are not judged
			if e.note and e.erred ~= nil and noteStem == nil then
				local words = string.split(e.note, " ")
				local phaseNote = string.match(e.note, "^%S+ phase %a+$") ~= nil
				local tries = words[1] ~= nil and string.find(words[1], "review-", 1, true) ~= nil
				for i = 1, #words do
					tries = tries or string.match(words[i], "^[Ff]%d+%p*$") ~= nil
				end
				if tries and not phaseNote then
					add(`{who}: a note about a finding starts <stem> F<n>, such as design-review-001 F1`)
				end
			end
			local erred = e.erred
			if erred ~= nil then
				local steps = stepsText(erred, e.upstream)
				local both: { string } = if e.upstream then { erred, e.upstream } else { erred }
				for _, step in both do
					if step ~= "none" and not tree.skills[canon(step, tree.skills)] then
						add(`{who}: no skill {step} (no {step}/SKILL.md in any skills folder)`)
					end
				end
				local up = e.upstream
				local erredNow = canon(erred, tree.skills)
				local upNow = if up then canon(up, tree.skills) else nil
				-- a mistake design made or should have caught: it names a design step, or it answers a finding of a
				-- design-phase review (a design round, or a focused review that says design), as an entry or as a note
				-- headed `<stem> F<n>`, unless it is the reviewer's own mistake
				local designStep = table.find(lessons.DESIGN_STEPS, erredNow) ~= nil
					or (upNow ~= nil and table.find(lessons.DESIGN_STEPS, upNow) ~= nil)
				local headStem: string? = if e.note then noteStem else e.review
				local headFinding: string? = if e.note then noteFinding else e.finding
				-- an unreadable phase counts as design: it is never read as the unguarded answer
				local headPhase = if headStem then phaseOf[headStem] else nil
				local designKey = if headStem and headFinding then `{headStem} {headFinding}` else nil
				local designFinding = designKey ~= nil and findingDesign[designKey] == true
				local designReview = headPhase ~= nil
					and (headPhase ~= "build" or designFinding)
					and erred ~= "none"
				local why = if designStep
					then "the line names a design step"
					elseif headPhase ~= "build" then "it answers a design review finding"
					else "it answers a finding whose lines or entry name a design step"
				for _, rawLid in e.lessons do
					local lid = skillsLib.movedId(rawLid) -- c0436: an old record names the moved skill
					local skill = string.match(lid, "^([^/]+)/")
					if not same(skill, erredNow) and not same(skill, upNow) then
						add(
							`{who}: lesson {lid} is filed under {skill}, which the line does not name ({steps})`
						)
					end
					local text = tree.lessons[rawLid] or tree.lessons[lid]
					local parsed = if text then lessons.parse(lid, text) else nil
					-- the reviewer's own mistake is a reviewer lesson, which a reviewer reads whatever its `when:`: exempt only
					-- when the lesson is filed under zz-review (a lesson filed under the upstream skill reaches design)
					local ownMistake = erredNow == "zz-review" and skill == "zz-review"
					if
						(designStep or (designReview and not ownMistake))
						and parsed
						and parsed.when == "build"
					then
						add(
							`{who}: lesson {lid} is when: build, but {why} ({steps}): a mistake design made or should have caught reaches design (when: design or both)`
						)
					end
				end
			end
			if e.note then
				for _, lid in e.lessons do
					if not (tree.lessons[lid] or tree.lessons[skillsLib.movedId(lid)]) then
						add(`{who}: no lesson {lid}`)
					end
				end
				continue
			end
			local key = who
			local review = item.reviews[e.review]
			if not review then
				add(`{key}: no {e.review}.md in {item.id}`)
				continue
			end
			if not table.find(lessons.findings(review), e.finding) then
				add(`{key}: {e.review}.md has no {e.finding}`)
			end
			-- c0136: the reviewer's attribution is the entry's, when the review gives one
			local said = (boundSteps[e.review] or {})[e.finding]
			if said and erred == nil then
				add(
					`{key}: {e.review}.md {e.finding} gives Erred: {said.erred}, Upstream: {said.upstream or "none"}: the entry copies them as its (erred …) group`
				)
			end
			if said and erred ~= nil then
				local entryUp = if e.upstream then canon(e.upstream, tree.skills) else nil
				if not same(canon(erred, tree.skills), said.erred) or not same(entryUp, said.upstream) then
					local was = `Erred: {said.erred}, Upstream: {said.upstream or "none"}`
					add(
						`{key}: the line says ({stepsText(erred, e.upstream)}) but {e.review}.md {e.finding} says {was}`
					)
				end
			end
			for _, lid in e.lessons do
				if not (tree.lessons[lid] or tree.lessons[skillsLib.movedId(lid)]) then
					add(`{key}: no lesson {lid}`)
				end
			end
		end
	end
	table.sort(problems)
	return problems
end

local function count(l: Lesson, sources: { [string]: { string } }): number
	return #(sources[l.id] or {}) + (if l.from then 1 else 0)
end

function lessons.select(all: { Lesson }, sources: { [string]: { string } }, q: Query): { Lesson }
	local out = {}
	for _, l in all do
		if q.skills and #q.skills > 0 and not table.find(q.skills, l.skill) then
			continue
		end
		if q.when and l.when ~= "both" and l.when ~= q.when then
			continue
		end
		local keep = true
		local wanted: { string } = q.tags or {}
		for _, tag in wanted do
			if not table.find(l.tags, tag) then
				keep = false
			end
		end
		local hay =
			string.lower(table.concat({ l.id, l.title, table.concat(l.tags, " "), l.check, l.body }, "\n"))
		local words: { string } = q.words or {}
		for _, w in words do
			local isId = false
			for _, other in all do
				isId = isId or other.id == w
			end
			if (isId and w ~= l.id) or (not isId and not string.find(hay, string.lower(w), 1, true)) then
				keep = false
			end
		end
		if keep then
			table.insert(out, l)
		end
	end
	table.sort(out, function(a, b)
		local ca, cb = count(a, sources), count(b, sources)
		if ca ~= cb then
			return ca > cb
		end
		return a.id < b.id
	end)
	return out
end

function lessons.index(chosen: { Lesson }, sources: { [string]: { string } }): string
	if #chosen == 0 then
		return "(none)\n"
	end
	local out = {}
	for _, l in chosen do
		local n = count(l, sources)
		table.insert(out, `- {l.id} ({l.when}, {n} {if n == 1 then "source" else "sources"}): {l.check}\n`)
	end
	return table.concat(out)
end

local ITEM = "^[fdcR]%d%d%d%d$"

local function dirs(path: string): { string }
	if not fs.isDir(path) then
		return {}
	end
	local out = {}
	for _, name in fs.readDir(path) do
		if fs.isDir(`{path}/{name}`) then
			table.insert(out, name)
		end
	end
	table.sort(out)
	return out
end

-- Where a tree from before c0115 keeps its skills (and a hand-built tree with no folders is read as).
lessons.LEGACY_SKILLS = ".claude/skills"

-- A skill's real folder in a loaded tree ("z-nile/skills/zz-test"), or its legacy place.
function lessons.folderOf(tree: Tree, skill: string): string
	return (tree.folders and tree.folders[skill]) or `{lessons.LEGACY_SKILLS}/{skill}`
end

function lessons.load(root: string): Tree
	local folders: { [string]: string } = {}
	local owners: { [string]: string } = {}
	local tree: Tree = {
		lessons = {},
		found = {},
		skills = {},
		folders = folders,
		owners = owners,
		items = {},
		problems = {},
	}
	-- c0115: the real skill folders, z-nile's and every project's (skills.folders); a tree that has none of them
	-- predates c0115 and keeps its skills in .claude/skills
	local ok, reg = pcall(projects.load, root)
	if not ok then
		error(`lessons: {reg}`, 0) -- a missing or bad registry refuses: never guess the roots or the skills folders (c0114)
	end
	local registry: projects.Registry = reg :: projects.Registry
	local bases: { { path: string, project: string } } = {}
	for _, f in skillsLib.folders(registry) do
		if fs.isDir(`{root}/{f.path}`) then
			table.insert(bases, { path = f.path, project = f.project })
		end
	end
	if #bases == 0 then
		bases = { { path = lessons.LEGACY_SKILLS, project = "" } }
	end
	for _, b in bases do
		for _, skill in dirs(`{root}/{b.path}`) do
			local rel = `{b.path}/{skill}`
			if folders[skill] then
				table.insert(tree.problems, `skill {skill} is in two folders: {folders[skill]} and {rel}`)
				continue
			end
			if fs.isFile(`{root}/{rel}/SKILL.md`) then
				tree.skills[skill] = true
			end
			folders[skill] = rel
			if b.project ~= "" then
				owners[skill] = b.project
			end
			local folder = `{root}/{rel}/lessons`
			if fs.isDir(folder) then
				local names = fs.readDir(folder)
				table.sort(names)
				for _, name in names do
					local slug = string.match(name, "^(.+)%.md$")
					if string.sub(name, 1, 1) == "." then
						continue -- hidden files (.DS_Store, editor swap files) are never lessons
					elseif slug and fs.isFile(`{folder}/{name}`) then
						tree.lessons[`{skill}/{slug}`] = fs.readFile(`{folder}/{name}`)
					else
						table.insert(tree.problems, `{rel}/lessons/{name}: not a lesson file`)
					end
				end
			end
		end
	end
	-- items under every project root of the checkout (c0114): z-nile's rafts hold the harvests
	local roots: { string } = projects.roots(registry)
	for _, top in roots do
		for _, kind in { "issues", "rafts" } do
			-- c0116: a retired raft (rafts/retired/<R-id>) keeps its reviews and harvest.md, which stay sources
			for _, state in { "", "/active", "/done", "/retired" } do
				local parent = `{root}/{top}/{kind}{state}`
				for _, id in dirs(parent) do
					if not string.match(id, ITEM) then
						continue
					end
					tree.found[id] = true
					local item: Item = { id = id, reviews = {}, harvest = nil }
					local any = false
					for _, name in fs.readDir(`{parent}/{id}`) do
						local stem = string.match(name, "^(.+)%.md$")
						local path = `{parent}/{id}/{name}`
						if stem and isStem(stem) and fs.isFile(path) then
							item.reviews[stem] = fs.readFile(path)
							any = true
						elseif name == "harvest.md" and fs.isFile(path) then
							item.harvest = fs.readFile(path)
							any = true
						end
					end
					if any then
						table.insert(tree.items, item)
					end
				end
			end
		end
	end
	table.sort(tree.items, function(a, b)
		return a.id < b.id
	end)
	return tree
end

-- c0115: the old lesson ids in one harvest.md line. Every byte of a ledger takes one of two rules. The id list of
-- an entry parseHarvest (the format's one reader) returns takes the id rule: every id of an old skill counts, known or
-- not. Everything else is prose and takes skills.oldLessonIds' prose rule (only a token whose renamed lesson exists):
-- the rest of an entry's line (its review and finding, a note's text, a one-off's reason), and every line parseHarvest
-- skips (headings, paragraphs, indented sub-bullets, blank or odd lines) or refuses (`lessons --check` still fails on
-- those). Returns the line with every known old id renamed, the count, every old id found ("old/slug"), and the
-- parsed ids with no renamed lesson.
local function ledgerLine(
	line: string,
	existing: { [string]: boolean }
): (string, number, { string }, { string })
	local found: { string } = {}
	local unknown: { string } = {}
	local function prose(text: string): (string, number)
		for _, hit in skillsLib.oldLessonIds(text, existing) do
			table.insert(found, `{hit.old}/{hit.slug}`)
		end
		local renamed, n = skillsLib.renameLessonIds(text, existing)
		-- c0136: the skill names of a step group are renamed too (the table keeps old records valid; this keeps the
		-- ledger itself current)
		local renames = 0
		local out = string.gsub(renamed, "%((erred [^()]*)%)", function(inner: string): string
			local fixed = inner
			for _, key in { "erred", "upstream" } do
				fixed = string.gsub(fixed, `{key} ([%w%-]+)`, function(name: string): string
					local new = skillsLib.RENAMED[name]
					if new then
						renames += 1
						table.insert(found, `{name}/(step)`)
						return `{key} {new}`
					end
					return `{key} {name}`
				end)
			end
			return `({fixed})`
		end)
		return out, n + renames
	end
	local entry = lessons.parseHarvest("x", line)[1]
	local head, ids
	if entry and entry.note then
		head, ids = string.match(line, "^(%- note .*: )([^:]*)$")
	elseif entry and not entry.oneOff then
		head, ids = string.match(line, "^(%- %S+ F%d+[^:]*:%s*)(.*)$")
	end
	if not entry or entry.oneOff or not head or not ids then
		-- no id list on this line: all of it is prose
		local out, n = prose(line)
		return out, n, found, unknown
	end
	local out, n = prose(head :: string)
	local renamed: { [string]: string } = {}
	for _, id in entry.lessons do
		local old, slug = string.match(id, "^([^/]+)/(.+)$")
		local new = old and skillsLib.RENAMED[old]
		if new then
			table.insert(found, id)
			if existing[`{new}/{slug}`] then
				renamed[id] = `{new}/{slug}`
			else
				table.insert(unknown, id)
			end
		end
	end
	-- each id renamed in place: the list's separators and spaces stay byte for byte
	local list = string.gsub(ids :: string, "[^,]+", function(chunk: string): string
		local left, core, right = string.match(chunk, "^(%s*)(.-)(%s*)$")
		local new = core and renamed[core]
		if new then
			n += 1
			return `{left}{new}{right}`
		end
		return chunk
	end)
	return out .. list, n, found, unknown
end

-- Every old lesson id in a harvest.md's text ("old/slug"), and the parsed ones with no renamed lesson.
function lessons.ledgerOldIds(text: string, existing: { [string]: boolean }): ({ string }, { string })
	local found: { string } = {}
	local unknown: { string } = {}
	for line in string.gmatch(text, "[^\n]+") do
		local _, _, f, u = ledgerLine(line, existing)
		table.move(f, 1, #f, #found + 1, found)
		table.move(u, 1, #u, #unknown + 1, unknown)
	end
	return found, unknown
end

-- A harvest.md's text with every known old id renamed (ids and prose alike), the count, and the unknown parsed ids.
function lessons.renameLedger(text: string, existing: { [string]: boolean }): (string, number, { string })
	local out: { string } = {}
	local unknown: { string } = {}
	local n = 0
	for line in string.gmatch(text .. (if string.sub(text, -1) == "\n" then "" else "\n"), "([^\n]*)\n") do
		local l, m, _, u = ledgerLine(line, existing)
		table.insert(out, l)
		n += m
		table.move(u, 1, #u, #unknown + 1, unknown)
	end
	local joined = table.concat(out, "\n")
	if string.sub(text, -1) == "\n" then
		joined ..= "\n"
	end
	return joined, n, unknown
end

return lessons
