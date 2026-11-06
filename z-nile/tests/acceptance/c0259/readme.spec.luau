--!strict
-- c0259: z-nile/README.md labels every claim with what exists, keeps what it said before, and draws the workflow.
-- Shape rules only: the exact vocabulary, the truth of each row and the changed lines are check.sh's (sequestered, not
-- promoted), so the README can grow rows without turning this spec red. Reads the checkout's own README as text.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local ROOT = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local README = fs.readFile(`{ROOT}/z-nile/README.md`)

local function has(text: string, part: string): boolean
	return string.find(text, part, 1, true) ~= nil
end

-- The text of "## How it should work", up to the next "## " heading.
local function workflow(): string
	local from = string.find(README, "\n## How it should work\n", 1, true)
	if from == nil then
		error("README has no '## How it should work'", 0)
	end
	local rest = string.sub(README, from + 1)
	local to = string.find(rest, "\n## ", 4, true)
	return if to then string.sub(rest, 1, to) else rest
end

local STATES = { exists = true, designed = true, captured = true }

return t.spec("c0259 the README labels the target workflow", function(it)
	it(
		"AC1: the workflow section comes before The five parts, and every sub-section carries a state label",
		function()
			local at = string.find(README, "\n## How it should work\n", 1, true)
			local parts = string.find(README, "\n## The five parts\n", 1, true)
			t.expect(at ~= nil and parts ~= nil and (at :: number) < (parts :: number)).toBe(true)
			local subs: { { title: string, body: string } } = {}
			for line in string.gmatch(workflow(), "[^\n]*") do
				local title = string.match(line, "^### (.+)$")
				if title then
					table.insert(subs, { title = title, body = "" })
				elseif #subs > 0 then
					subs[#subs].body ..= line .. "\n"
				end
			end
			local count = #subs
			for _, sub in subs do
				local labelled = string.match(sub.body, "%*exists%*") ~= nil
					or string.match(sub.body, "%*designed%*") ~= nil
					or string.match(sub.body, "%*captured%*") ~= nil
					or sub.title == "Roadmap"
				if not labelled then
					error(`sub-section "{sub.title}" has no state label`, 0)
				end
			end
			t.expect(count >= 5).toBe(true)
		end
	)

	it("AC2: the legend defines exactly three states and no other state word is used", function()
		local w = workflow()
		local legend = string.match(w, "\nStatus labels[^\n]*") or ""
		local defined = 0
		for word in string.gmatch(legend, "%*%*(%a+)%*%*") do
			t.expect(STATES[word] == true).toBe(true)
			defined += 1
		end
		t.expect(defined).toBe(3)
		local plain = string.gsub(w, "%*%*", "")
		for word in string.gmatch(plain, "%*(%a+)%*") do
			if STATES[word] ~= true then
				error(`undefined state word *{word}*`, 0)
			end
		end
	end)

	it(
		"AC3: the roadmap is a table whose every row ends in a defined state, one row being the stacked PR set",
		function()
			local road = string.match(workflow(), "### Roadmap\n(.-)\n### ") or ""
			local rows, stacked = 0, false
			for line in string.gmatch(road, "[^\n]+") do
				if string.sub(line, 1, 1) == "|" and not has(line, "---") and not has(line, "| piece |") then
					rows += 1
					local state = string.match(line, "| (%a+) |$")
					t.expect(state ~= nil and STATES[state :: string] == true).toBe(true)
					if has(line, "stacked PR set") then
						stacked = true
					end
				end
			end
			t.expect(rows >= 8).toBe(true)
			t.expect(stacked).toBe(true)
		end
	)

	it("AC4: the diagram fences are balanced and the workflow diagram shows both ends", function()
		local fences = 0
		for _ in string.gmatch(README, "\n```") do
			fences += 1
		end
		t.expect(fences % 2).toBe(0)
		local diagram = string.match(workflow(), "```mermaid\n(.-)\n```") or ""
		t.expect(has(diagram, "engineer end")).toBe(true)
		t.expect(has(diagram, "worker end")).toBe(true)
	end)

	it("AC5: what the README said before is still there", function()
		for _, w in
			{
				"## The five parts",
				"## Skills",
				"## A project's home",
				"## Design checklists",
				"## The flow",
				"## Where the work lives",
				"stateDiagram-v2",
				"`./zn board`",
				"`z-ticket`",
				"`z-stop`",
				"`pickman-arch`, `pickman-test`",
			}
		do
			t.expect(has(README, w)).toBe(true)
		end
	end)
end)
