--!strict
-- c0301: every text that restates the trace's claim and code-cell rules says the new ones, and the Touched modules
-- section has one reader. Reads the files; writes nothing.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function read(rel: string): string
	return fs.readFile(`{TOP}/{rel}`)
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

local function oneLine(text: string): string
	return (string.gsub(text, "%s+", " "))
end

return t.spec("c0301: the restated trace rules and the one Touched modules reader", function(it)
	it("AC4: zz-rules, zz-review and the trace contract state the None. and tests-only rules", function()
		local rules = oneLine(read("z-nile/skills/zz-rules/SKILL.md"))
		t.expect(has(rules, 'a `### Judged` or `### Observed` subsection whose whole body is "None." is no claim and keeps its number, so no other claim\'s number moves'))
			.toBe(true)
		t.expect(has(rules, "a tests-only ticket, one whose layer changed a spec file (a `*.spec.luau` outside a `.tracker/` folder) and no source file, cites a spec file the stack changed that its own layer changed or its Touched modules name (as written or under the ticket's home), or one the stack deleted, at its line on main, and a spec file is never the code of any other ticket"))
			.toBe(true)

		local review = oneLine(read("z-nile/skills/zz-review/SKILL.md"))
		t.expect(has(review, "a tests-only ticket, whose layer changed a spec file (a `*.spec.luau` outside a `.tracker/` folder) and no source file, cites `<spec-file>:<line>` of a spec the stack changed that its own layer changed or its Touched modules name, as written or under the ticket's home, or of one the stack deleted, at its line on main"))
			.toBe(true)
		t.expect(has(review, 'An empty `### Judged` or `### Observed` ("None.") has no row.')).toBe(true)

		local contract = oneLine((string.gsub(read("z-nile/engine/trace.luau"), "\n%-%-", "\n")))
		t.expect(has(contract, 'subsection whose whole body is "None." (any case, with or without the period or parentheses) is no claim; it keeps its number, so no other claim\'s number moves (c0301)'))
			.toBe(true)
		t.expect(has(contract, "A tests-only ticket (its layer changed at least one `.spec.luau` file outside a `.tracker/` folder and no source file) cites in `code` a spec file the stack changed that its own layer changed or its `### Touched modules` name (as written or under the ticket's home), a spec the stack deleted at a line it had on main, or `none` when the stack changed no source file. Any other ticket's `code` cell never cites a spec file (c0301)."))
			.toBe(true)
	end)

	it("AC4: the Touched modules section is read by raftplan.touchedModules alone", function()
		local main = read("z-nile/engine/main.luau")
		t.expect(has(main, "raftplan.touchedModules(fs.readFile(item.doc))")).toBe(true)
		t.expect(has(main, "### Touched modules\\n(.-)")).toBe(false)
		local tr = read("z-nile/engine/trace.luau")
		t.expect(has(tr, "raftplan.touchedModules(issue.docText)")).toBe(true)
		t.expect(has(tr, "Touched modules\\n")).toBe(false)
	end)
end)
