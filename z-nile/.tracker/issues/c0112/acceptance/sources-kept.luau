--!strict
-- c0112 AC3 and the conflict check: no lesson and no source is lost.
--   lune run sources-kept.luau -- [--merges] <base tree> <current tree>
-- Both trees are checkouts (for AC3 the base is `git archive <merge base>` in a temporary folder; the validator in
-- experiments/ and the merge pass run this file too; after `done` it lives in tests/acceptance/c0112/ and the zz-rules
-- sentence for a harvest.md conflict runs it against each merge parent). Every lesson the base has must exist in the
-- current tree, and every source it had must still be one, compared exactly, as sets:
--   - a finding source `<item> <review> <finding>`: by the same key, or as a note of that item headed `<review>
--     <finding>` (the head as a whole word: a note headed F12 does not stand in for F1), which is where c0136 lets a
--     third lesson of a finding go;
--   - a note source `<item> note <text>`: by the same text, or by `reword(text)` below, as a note source of the same
--     lesson in the same item.
-- Without `--merges` (AC3, which check.sh runs without options and the branch cannot change) a lesson gone from the
-- current tree is a loss, because c0112 never renames a lesson. With `--merges` a gone lesson is kept when at least one
-- current lesson of the same skill holds every source the base gave it (c0181's lesson-merge deletes the `from` lesson
-- and keeps its sources in `into`); every holder is named. A source held only in another skill, or by no lesson, is a
-- loss. The invariant is over sources, not lesson ids.
local lessons = require("@znile/engine/lessons")
local process = require("@lune/process")

-- c0136's near-head rule refuses a grouped note that has a word shaped like a finding (`F1,`) or a first word with
-- `review-` (`design-review-004,`), so the backfill rewords such a note, and this is the only rewording AC3 allows: each
-- finding-shaped word becomes `finding <n>` (its punctuation kept), and a first word containing `review-` has its hyphens
-- turned into spaces. A rule over the input, not a list of today's notes: main keeps adding notes until `done`.
local function reword(text: string): string
	local words = string.split(text, " ")
	for i, w in words do
		local n, punct = string.match(w, "^[Ff](%d%d?%d?)(%p*)$")
		if n then
			words[i] = `finding {n}{punct}`
		elseif i == 1 and string.find(w, "review-", 1, true) then
			words[i] = (string.gsub(w, "%-", " "))
		end
	end
	return table.concat(words, " ")
end

local args: { string } = {}
local merges = false
for _, a in process.args do
	if a == "--merges" then
		merges = true
	elseif a ~= "--" then
		table.insert(args, a)
	end
end
local baseDir, curDir = args[1], args[2]
if not baseDir or not curDir then
	print("usage: sources-kept [--merges] <base tree> <current tree>")
	process.exit(2)
end

local function sourcesOf(dir: string): ({ [string]: { string } }, { [string]: boolean })
	local tree = lessons.load(dir)
	local have: { [string]: boolean } = {}
	for id in tree.lessons do
		have[id] = true
	end
	return lessons.sources(tree.items), have
end

local baseSources, baseLessons = sourcesOf(baseDir :: string)
local curSources, curLessons = sourcesOf(curDir :: string)

local function noteItem(label: string): string?
	return string.match(label, "^(%S+) note ")
end

-- the sources of base lesson `id` that `into` (a current lesson) does not hold, as messages
local function lostOf(id: string, into: string): { string }
	local lost: { string } = {}
	local now: { [string]: boolean } = {}
	local curList: { string } = curSources[into] or {}
	for _, s in curList do
		now[s] = true
	end
	local baseList: { string } = baseSources[id] or {}
	for _, s in baseList do
		if now[s] then
			continue
		end
		local item = noteItem(s)
		if item then
			-- a note source: exact, or reworded by reword() as a note source of the lesson in this item
			if now[`{item} note {reword(string.sub(s, #item + 7))}`] ~= true then
				table.insert(lost, `lesson {id} lost the note source: {s}`)
			end
			continue
		end
		local head, stem, finding = string.match(s, "^(%S+) (%S+) (F%d+)$")
		local movedToNote = false
		if head then
			local prefix = `{head} note {stem} {finding}`
			for have in now do
				if have == prefix or string.sub(have, 1, #prefix + 1) == prefix .. " " then
					movedToNote = true
				end
			end
		end
		if not movedToNote then
			table.insert(lost, `lesson {id} lost the source: {s}`)
		end
	end
	return lost
end

local problems: { string } = {}
local notes: { string } = {}
local seen = 0
for id in baseLessons do
	seen += 1
	if curLessons[id] then
		for _, p in lostOf(id, id) do
			table.insert(problems, p)
		end
		continue
	end
	if not merges then
		table.insert(problems, `lesson {id} is gone`)
		continue
	end
	local skill = string.match(id, "^([^/]+)/") :: string
	local survivors: { string } = {}
	for cur in curLessons do
		if string.sub(cur, 1, #skill + 1) == skill .. "/" and #lostOf(id, cur) == 0 then
			table.insert(survivors, cur)
		end
	end
	if #survivors >= 1 then
		table.sort(survivors)
		table.insert(notes, `lesson {id} merged into {table.concat(survivors, ", ")}`)
	else
		table.insert(problems, `lesson {id} is gone, and no lesson of {skill} holds all its sources`)
	end
end
if seen < 100 then
	table.insert(problems, `the base tree has only {seen} lessons`)
end
table.sort(problems)
table.sort(notes)
if #notes > 0 then
	print(table.concat(notes, "\n"))
end
if #problems > 0 then
	print(table.concat(problems, "\n"))
	process.exit(1)
end
print(`{seen} lessons, every source kept`)
