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

local KEBAB = "^[a-z0-9]+%-?[a-z0-9%-]*$"
local KEYS = { title = true, when = true, tags = true, check = true, from = true }
local WHEN = { design = true, build = true, both = true }

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end

local function kebab(s: string): boolean
	return string.match(s, KEBAB) ~= nil and string.sub(s, -1) ~= "-" and string.find(s, "--", 1, true) == nil
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

local function twice(ids: { string }): string?
	for i, id in ids do
		if table.find(ids, id, i + 1) then
			return id
		end
	end
	return nil
end

local function isStem(stem: string): boolean
	return string.match(stem, "^design%-review%-%d%d%d$") ~= nil
		or string.match(stem, "^review%-%d%d%d$") ~= nil
		or string.match(stem, "^final%-review%-%d%d%d$") ~= nil
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
			for id in string.gmatch(ids :: string, "[^,]+") do
				table.insert(entry.lessons, trim(id))
			end
			if note == "" then
				table.insert(problems, `{item}/harvest.md: note: a note needs its text`)
			elseif #entry.lessons == 0 or table.find(entry.lessons, "") then
				table.insert(problems, `{item}/harvest.md: note {note}: the target must be lesson ids`)
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
		local stem, finding, target = string.match(line, "^%- (%S+) (F%d+):%s*(.-)%s*$")
		if not stem or not finding or not target or not isStem(stem) then
			table.insert(problems, `{item}/harvest.md: not an entry: {line}`)
			continue
		end
		local key = `{stem} {finding}`
		local entry: Entry = { item = item, review = stem, finding = finding, lessons = {}, oneOff = nil }
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
				for _, lid in e.lessons do
					out[lid] = out[lid] or {}
					table.insert(
						out[lid],
						if e.note then `{e.item} note {e.note}` else `{e.item} {e.review} {e.finding}`
					)
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
		if not item.harvest then
			continue
		end
		local entries, bad = lessons.parseHarvest(item.id, item.harvest)
		for _, p in bad do
			add(p)
		end
		for _, e in entries do
			if e.note then
				for _, lid in e.lessons do
					if not tree.lessons[lid] then
						add(`{item.id}/harvest.md: note {e.note}: no lesson {lid}`)
					end
				end
				continue
			end
			local key = `{item.id}/harvest.md: {e.review} {e.finding}`
			local review = item.reviews[e.review]
			if not review then
				add(`{key}: no {e.review}.md in {item.id}`)
				continue
			end
			if not table.find(lessons.findings(review), e.finding) then
				add(`{key}: {e.review}.md has no {e.finding}`)
			end
			for _, lid in e.lessons do
				if not tree.lessons[lid] then
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
		return skillsLib.renameLessonIds(text, existing)
	end
	local entry = lessons.parseHarvest("x", line)[1]
	local head, ids
	if entry and entry.note then
		head, ids = string.match(line, "^(%- note .*: )([^:]*)$")
	elseif entry and not entry.oneOff then
		head, ids = string.match(line, "^(%- %S+ F%d+:%s*)(.*)$")
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
