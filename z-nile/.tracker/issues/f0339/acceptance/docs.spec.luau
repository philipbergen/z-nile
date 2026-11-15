--!strict
-- f0339 AC3: the explainer page's template has the shape explainer.check reads, the usage text lists
-- `explain`, and the skills and the README say who writes the page and what approve does with it. Reads the
-- checkout's own files as text.
local explainer = require("@znile/engine/explainer")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local ROOT = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local TEMPLATE = "z-nile/templates/explainer.html"
local ZERO = string.rep("0", 64)

local function read(rel: string): string
	return fs.readFile(`{ROOT}/{rel}`)
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

-- The first line of `text` that starts with `prefix`.
local function lineOf(text: string, prefix: string): string
	for line in string.gmatch(text, "[^\n]+") do
		if string.sub(line, 1, #prefix) == prefix then
			return line
		end
	end
	error(`no line starts with "{prefix}"`, 2)
end

local function expectHas(text: string, needle: string, where: string)
	if not has(text, needle) then
		error(`{where} does not say "{needle}"`, 2)
	end
end

return t.spec("f0339 the template, the usage and the docs", function(it)
	it("AC3: the template's only problems are its placeholders and its contract", function()
		local text = read(TEMPLATE)
		local problems = explainer.check(TEMPLATE, text, ZERO, {})
		if #problems ~= 1 or not has(problems[1], `placeholder text (class="{explainer.FILL}")`) then
			error(`the template should fail only on its placeholders:\n{table.concat(problems, "\n")}`)
		end
		-- the placeholder contract is not a real one: any real hash refuses it too
		local real = explainer.check(TEMPLATE, text, string.rep("1", 64), {})
		t.expect(#real).toBe(2)
		t.expect(has(table.concat(real, "\n"), "explains contract 000000000000")).toBe(true)
	end)

	it("AC3: the usage text lists explain beside approve", function()
		local main = read("z-nile/engine/main.luau")
		local usage = string.match(main, "local USAGE = %[%[(.-)%]%]") or ""
		expectHas(usage, "\n  explain <issue-id>", "the usage text")
		expectHas(usage, "\n  approve <issue-id> [--check|--publish]", "the usage text")
	end)

	it("AC3: z-design has the designer write the page and check it before design: ready", function()
		local skill = read("z-nile/skills/z-design/SKILL.md")
		expectHas(skill, "explainer.html", "z-design")
		expectHas(skill, TEMPLATE, "z-design")
		expectHas(skill, "`./zn explain <id>`", "z-design")
		expectHas(skill, "`zn-fill`", "z-design")
		-- the check that must pass comes before the issue is marked ready
		local passes = "`./zn explain <id>` must end in `ok`"
		expectHas(skill, passes, "z-design")
		local check = string.find(skill, passes, 1, true) :: number
		local ready = string.find(skill, "set `design: ready` on the issue", 1, true)
		t.expect(ready ~= nil and check < (ready :: number)).toBe(true)
	end)

	it("AC3: zz-rules says approve opens the page and asks y/n, and lists explain", function()
		local rules = read("z-nile/skills/zz-rules/SKILL.md")
		local approve = lineOf(rules, "| approve |")
		expectHas(approve, "explainer.html", "zz-rules' approve row")
		expectHas(approve, "y/n", "zz-rules' approve row")
		expectHas(approve, "warns when the page", "zz-rules' approve row")
		local explain = lineOf(rules, "| explain |")
		expectHas(explain, "`./zn explain <issue-id>`", "zz-rules' explain row")
	end)

	it("AC3: the design reviewer reads the page, and the README says approve shows it", function()
		local review = read("z-nile/skills/zz-review/SKILL.md")
		local design = string.match(review, "\n## Design mode %(from z%-design%)\n(.-)\n## ") or ""
		expectHas(design, "explainer.html", "zz-review's design mode")
		local readme = read("z-nile/README.md")
		local bullet = lineOf(readme, "- A person approves a design with `./zn approve <id>`")
		expectHas(bullet, "explainer page", "the README's approve bullet")
	end)

	it("AC3: a re-approval and the one-time approval say the page comes first", function()
		local execute = read("z-nile/skills/zz-execute/SKILL.md")
		local again = string.match(execute, "[^\n]*`./zn approve <id>` again when the contract changed[^\n]*") or ""
		expectHas(again, "explainer page", "zz-execute's re-approval sentence")
		local ready = read("z-nile/skills/z-ready/SKILL.md")
		local once = string.match(ready, "[^\n]*one%-time step[^\n]*") or ""
		expectHas(once, "explainer page", "z-ready's one-time approval line")
		local engine = read("z-nile/engine/approval.luau")
		expectHas(engine, "approving first needs the issue's explainer page (./zn explain {id})", "ready's no-approval refusal")
	end)
end)
