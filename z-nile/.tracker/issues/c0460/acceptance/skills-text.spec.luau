--!strict
-- c0460: the skills and the issue template say the new rules. Reads the files as text from the checkout's top;
-- requires only @tests/lib/* and @lune/*.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function has(text: string, phrase: string): boolean
	return string.find(text, phrase, 1, true) ~= nil
end

-- The text from `## <heading>` (or `### `) up to the next heading of the same or higher level.
local function part(text: string, heading: string): string
	local from = string.find(text, "\n" .. heading .. "\n", 1, true)
	if not from then
		return ""
	end
	local level = #(string.match(heading, "^#+") :: string)
	local tail = string.sub(text, from + 1)
	local rest = string.sub(tail, #heading + 2)
	local stop = string.find(rest, "\n" .. string.rep("#", level) .. " ", 1, true)
		or string.find(rest, "\n" .. string.rep("#", math.max(level - 1, 1)) .. " ", 1, true)
	return if stop then string.sub(tail, 1, #heading + 1 + stop) else tail
end

local DESIGN = fs.readFile(`{TOP}/z-nile/skills/z-design/SKILL.md`)
local EXECUTE = fs.readFile(`{TOP}/z-nile/skills/zz-execute/SKILL.md`)
local REVIEW = fs.readFile(`{TOP}/z-nile/skills/zz-review/SKILL.md`)
local TEMPLATE = fs.readFile(`{TOP}/z-nile/templates/issue/doc.md`)

-- The part that starts at the first `## <prefix>` heading (the heading text may change, as c0458's rename of Code
-- mode may), non-empty or the case fails loudly.
local function byPrefix(text: string, prefix: string): string
	local from = string.find(text, "\n" .. prefix, 1, true)
	t.expect(from ~= nil).toBe(true)
	local rest = string.sub(text, (from :: number) + 1)
	local stop = string.find(rest, "\n## ", 4, true)
	return if stop then string.sub(rest, 1, stop) else rest
end

-- A numbered step of z-design ("3." ... "5.") from its line to the next numbered `## ` section.
local function step(n: number): string
	return byPrefix(DESIGN, `## {n}.`)
end

return t.spec("mutants skills and template (c0460)", function(it)
	it("the template's Test plan ends with the Mutants line and has no Rules and mutants heading", function()
		local plan = part(TEMPLATE, "## Test plan")
		t.expect(plan ~= "").toBe(true)
		t.expect(has(plan, "Mutants: mutants.md")).toBe(true)
		t.expect(has(TEMPLATE, "### Rules and mutants")).toBe(false)
		t.expect(has(plan, "| rule |")).toBe(false)
	end)

	it("z-design step 3 asks for the line and the replacement of an earlier ticket's empty table", function()
		local s3 = step(3)
		t.expect(has(s3, "Mutants: mutants.md")).toBe(true)
		t.expect(has(s3, "replace its `### Rules and mutants` subsection")).toBe(true)
		t.expect(has(s3, "| rule | spec :: case | mutant it kills | checked |")).toBe(false)
	end)

	it("z-design no longer asks for rows or a mutation check anywhere", function()
		t.expect(has(DESIGN, "**Mutation check**")).toBe(false)
		t.expect(has(DESIGN, "Add their Rules and mutants rows")).toBe(false)
		t.expect(has(DESIGN, "fill the table from the mutation check")).toBe(false)
		t.expect(has(DESIGN, "no mutation check")).toBe(false)
	end)

	it("z-design step 4 limits acceptance requires and says how they reach z-nile", function()
		local s4 = step(4)
		t.expect(has(s4, "@tests/lib/*")).toBe(true)
		t.expect(has(s4, "@lune/*")).toBe(true)
		t.expect(has(s4, "only through `./zn` or `lune run`")).toBe(true)
		t.expect(has(s4, "lune run")).toBe(true)
	end)

	it(
		"zz-execute Phase 2 has the mutants.md step: killed, survived, tests/ never acceptance/, restore not stash",
		function()
			local phase = byPrefix(EXECUTE, "## Phase 2")
			t.expect(has(phase, "mutants.md")).toBe(true)
			t.expect(has(phase, "killed")).toBe(true)
			t.expect(has(phase, "survived")).toBe(true)
			t.expect(has(phase, "never in the sequestered `acceptance/` folder")).toBe(true)
			t.expect(has(phase, "commit the layer")).toBe(true)
			t.expect(has(phase, "git restore")).toBe(true)
			t.expect(has(phase, "never `git stash`")).toBe(true)
			t.expect(has(phase, "git status --porcelain")).toBe(true)
		end
	)

	it("zz-review design item 0 audits rows only when present and names the neither case", function()
		local design = byPrefix(REVIEW, "## Design mode")
		t.expect(has(design, "at least one row")).toBe(true)
		t.expect(has(design, "mutants.md")).toBe(true)
		t.expect(has(design, "neither the `Mutants: mutants.md` line nor a table with rows")).toBe(true)
	end)

	it("zz-review audits mutants.md in the checks of a built layer and never as Rules and mutants", function()
		local code = byPrefix(REVIEW, "## Code mode")
		local final = byPrefix(REVIEW, "## Final mode")
		t.expect(has(code .. final, "mutants.md")).toBe(true)
		t.expect(has(code, "Rules and mutants")).toBe(false)
		t.expect(has(code, "**Mutants**")).toBe(true) -- the bold name c0458's check list prints
	end)
end)
