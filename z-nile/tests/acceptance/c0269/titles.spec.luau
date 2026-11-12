--!strict
-- c0269 AC2: no spec file under z-nile/tests repeats the old gate rule of `done` in a title, a
-- comment or a string, also wrapped across comment lines (a phrase built by concatenation is out of reach: this spec builds
-- its own that way). The exact new texts are check.sh's (AC1), not a promoted case: a later reword that keeps the rule
-- must not turn the gate red. Read from the
-- checkout's top. The stale phrases are built by concatenation so this file does not match itself once promoted.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function read(rel: string): string
	return fs.readFile(`{root}/{rel}`)
end
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

-- the old rule, in the words the stale places used, matched on a normalised text: lower case, backticks removed, runs
-- of spaces folded (so `done` runs, Done runs and a double space are found too)
local STALE = {
	"done runs the " .. "full gate",
	"done skips the " .. "full gate",
	"the gate decision: " .. "full",
}

local function normal(text: string): string
	local lowered = string.lower(text)
	local plain = string.gsub(lowered, "[`]", "")
	local joined = string.gsub(plain, "%-%-+", " ") -- comment markers: a rule wrapped across two comment lines
	return (string.gsub(joined, "%s+", " "))
end

-- every stale phrase a text holds (pure)
local function stale(text: string): { string }
	local found: { string } = {}
	local flat = normal(text)
	for _, phrase in STALE do
		if has(flat, phrase) then
			table.insert(found, phrase)
		end
	end
	return found
end

-- every .spec.luau under a folder, hidden folders skipped
local function specs(dir: string, out: { string })
	for _, name in fs.readDir(`{root}/{dir}`) do
		if string.sub(name, 1, 1) ~= "." then
			local rel = `{dir}/{name}`
			if fs.isDir(`{root}/{rel}`) then
				specs(rel, out)
			elseif string.match(name, "%.spec%.luau$") then
				table.insert(out, rel)
			end
		end
	end
end

return t.spec("c0269 done gate spec names", function(it)
	it("AC2: the scan finds the old rule in a title, a comment and a string", function()
		local planted = {
			['it("done runs the ' .. 'full gate on the tree", function()'] = "title",
			["-- so done skips the " .. "full gate here"] = "comment",
			['local s = "the gate decision: ' .. 'full, unless"'] = "string",
			["--[[ `tracker.sh done` runs the " .. "full gate ]]"] = "block comment",
			["-- `done` runs the " .. "full gate"] = "backtick form",
			["-- Done skips the " .. "full gate"] = "capitalised form",
			["-- done  runs the " .. "full\tgate"] = "spaced form",
			["-- done runs the\n-- " .. "full gate"] = "wrapped comment",
		}
		for text, form in planted do
			if #stale(text) == 0 then
				error(`the scan misses the old rule in a {form}`)
			end
		end
		t.expect(#stale("done runs the affected gate")).toBe(0)
		t.expect(#stale("the merge's full gate")).toBe(0) -- the rule that still holds
	end)

	it("AC2: no spec file under z-nile/tests repeats the old rule", function()
		local files: { string } = {}
		specs("z-nile/tests", files)
		t.expect(#files > 100).toBe(true) -- the walk found the suite, not nothing
		local bad: { string } = {}
		for _, rel in files do
			local found = stale(read(rel))
			if #found > 0 then
				table.insert(bad, `{rel}: {table.concat(found, " | ")}`)
			end
		end
		if #bad > 0 then
			error(`stale gate wording in: {table.concat(bad, "; ")}`)
		end
	end)

	it("AC2: inputs.tsv declares what this spec reads", function()
		local tsv = read("z-nile/tests/inputs.tsv")
		t.expect(has(tsv, "tests/acceptance/c0269/titles.spec.luau\tz-nile/tests/\n")).toBe(true)
	end)
end)
