--!strict
-- c0264: z-nile/README.md states what z-nile is for (## Intent) and describes the worker model in How it should work.
-- Shape rules only: the exact vocabulary, the truth of each label and the changed lines are check.sh's (sequestered,
-- not promoted), so later features can relabel and grow the section without turning this spec red. Reads the
-- checkout's own README as text.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local ROOT = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local README = fs.readFile(`{ROOT}/z-nile/README.md`)

local function has(text: string, part: string): boolean
	return string.find(text, part, 1, true) ~= nil
end

-- The text of a "## <title>" section, up to the next "## " heading.
local function section(title: string): string
	local from = string.find(README, `\n## {title}\n`, 1, true)
	if from == nil then
		error(`README has no '## {title}'`, 0)
	end
	local rest = string.sub(README, from + 1)
	local to = string.find(rest, "\n## ", 4, true)
	return if to then string.sub(rest, 1, to) else rest
end

-- The body of a "### <title>" sub-section of How it should work, up to the next "###" or "##" heading.
local function sub(title: string): string
	local w = section("How it should work")
	local from = string.find(w, `\n### {title}\n`, 1, true)
	if from == nil then
		error(`How it should work has no '### {title}'`, 0)
	end
	local rest = string.sub(w, from + 1)
	local to = string.find(rest, "\n##", 4, true)
	return if to then string.sub(rest, 1, to) else rest
end

local function lower(text: string): string
	return string.lower(text)
end

return t.spec("c0264 the README states z-nile's intent", function(it)
	it("AC1: ## Intent comes after the opening picture and before How it should work", function()
		local picture = string.find(README, "```mermaid", 1, true)
		local intent = string.find(README, "\n## Intent\n", 1, true)
		local how = string.find(README, "\n## How it should work\n", 1, true)
		t.expect(picture ~= nil and intent ~= nil and how ~= nil).toBe(true)
		t.expect((picture :: number) < (intent :: number) and (intent :: number) < (how :: number)).toBe(true)
	end)

	it("AC2: the intent names the two human stages, the worker, the full-force review, the economy and the names", function()
		local i = lower(section("Intent"))
		for _, w in { "idea", "design", "`z-work`", "merge", "full-force", "sharp", "cheap", "wait", "approved" } do
			if not has(i, w) then
				error(`## Intent lacks: {w}`, 0)
			end
		end
	end)

	it("AC3: the intent claims nothing as built: it carries no state label", function()
		local i = section("Intent")
		for _, w in { "*exists*", "*designed*", "*captured*" } do
			t.expect(has(i, w)).toBe(false)
		end
	end)

	it("AC4: the new sub-sections exist, each labelled with its issue", function()
		for _, pair in
			{
				{ "The idea stage", "c0260" },
				{ "The worker", "c0253" },
				{ "Model tiers", "c0261" },
				{ "The full-force review", "c0262" },
				{ "Provenance", "c0263" },
			}
		do
			local body = sub(pair[1])
			local labelled = string.match(body, "%*%a+%* %(" .. pair[2] .. "%)") ~= nil
			if not labelled then
				error(`'### {pair[1]}' carries no label naming {pair[2]}`, 0)
			end
		end
	end)

	it("AC5: a worker clears its context and takes the next raft whenever a raft ends, merged or blocked", function()
		local w = lower(sub("The worker"))
		t.expect(has(w, "clears its context and picks up the next raft whenever a raft ends")).toBe(true)
		t.expect(has(w, "merged")).toBe(true)
		t.expect(has(w, "blocked")).toBe(true)
	end)
end)
