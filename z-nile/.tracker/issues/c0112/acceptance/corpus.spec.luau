--!strict
-- c0112 AC2: the coverage pass is not vacuous (the reader found reviews of every kind it harvests, and every finding has
-- an entry), and no two lessons share a title or a check question (the merge pass deduplicates by kind). The exact
-- corpus of the day c0112 ran (no review deleted) is check.sh's. Reads the real files, writes nothing.
local lessons = require("@znile/engine/lessons")
local process = require("@lune/process")
local t = require("@tests/lib/t")

-- the repository's files, from its top (this spec runs from z-nile/, c0120)
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function joined(list: { string }): string
	return table.concat(list, "\n")
end

-- the real tree, read once for the cases below
local cached: lessons.Tree? = nil
local function loaded(): lessons.Tree
	if not cached then
		cached = lessons.load(TOP)
	end
	return cached :: lessons.Tree
end

return t.spec("c0112 the review corpus and the lessons stay whole", function(it)
	it("the reader finds design, code and stream reviews, and every finding has an entry", function()
		local tree = loaded()
		local findings, stream, code, design, entries = 0, 0, 0, 0, 0
		for _, item in tree.items do
			for stem, text in item.reviews do
				local n = #lessons.findings(text)
				findings += n
				if string.sub(stem, 1, 14) == "stream-review-" then
					stream += n
				elseif string.sub(stem, 1, 7) == "review-" then
					code += n
				elseif string.sub(stem, 1, 14) == "design-review-" then
					design += n
				end
			end
			if item.harvest then
				local list = lessons.parseHarvest(item.id, item.harvest)
				for _, e in list do
					if not e.note then
						entries += 1
					end
				end
			end
		end
		-- non-vacuity only: a reader that finds nothing, or a kind it skips, would make the lists empty for free
		t.expect(findings >= 100).toBe(true)
		t.expect(design >= 1 and code >= 1 and stream >= 1).toBe(true)
		t.expect(entries >= findings).toBe(true)
	end)

	it("no two lessons share a title or a check question", function()
		local tree = loaded()
		local titles: { [string]: string } = {}
		local checks: { [string]: string } = {}
		local dups: { string } = {}
		for id, text in tree.lessons do
			local l = lessons.parse(id, text)
			if not l then
				table.insert(dups, `{id}: does not parse`)
				continue
			end
			local title = string.lower(l.title)
			local check = string.lower(l.check)
			if titles[title] then
				table.insert(dups, `{id} and {titles[title]} have the title {l.title}`)
			end
			if checks[check] then
				table.insert(dups, `{id} and {checks[check]} ask the same check`)
			end
			titles[title] = id
			checks[check] = id
		end
		table.sort(dups)
		t.expect(joined(dups)).toBe("")
	end)
end)
