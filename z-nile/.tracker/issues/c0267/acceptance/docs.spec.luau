--!strict
-- c0267 AC9: the README's picture and dispatcher line, zz-rules' chain rule and z-design's headless section say the
-- chain's design step is a draft a person approves, and where the chain waits for it. Reads the repository's files.
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

local function read(path: string): string
	for _, p in { path, `../{path}` } do
		if fs.isFile(p) then
			return fs.readFile(p)
		end
	end
	error(`cannot read {path}`)
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

local function at(text: string, needle: string, where: string)
	if not has(text, needle) then
		error(`{where} does not say: {needle}`, 2)
	end
end

-- the text from `heading` to the next heading of the same or a higher level
local function section(text: string, heading: string): string
	local a = string.find(text, "\n" .. heading .. "\n", 1, true)
	if not a then
		error(`no section {heading}`, 2)
	end
	local level = string.match(heading, "^(#+)") or "##"
	local rest = string.sub(text, (a :: number) + #heading + 2)
	local stop = #rest + 1
	for i = 1, #level do
		local found = string.find(rest, "\n" .. string.rep("#", i) .. " ", 1, true)
		if found and found < stop then
			stop = found
		end
	end
	return string.sub(rest, 1, stop - 1)
end

-- the bullet that starts with `start`, up to the next bullet or the end of the section
local function bullet(text: string, start: string): string
	local a = string.find(text, start, 1, true)
	if not a then
		error(`no bullet {start}`, 2)
	end
	local rest = string.sub(text, a :: number)
	local stop = string.find(rest, "\n- ", 2, true) or (#rest + 1)
	return string.sub(rest, 1, stop - 1)
end

return t.spec("c0267: the documents say the design step is a draft a person approves", function(it)
	it("AC9: the README's picture labels the dispatcher's edge with the approval", function()
		local readme = read("z-nile/README.md")
		local fence = string.find(readme, "```mermaid\n", 1, true) or 0
		local close = string.find(readme, "\n```", fence + 1, true) or 0
		local picture = string.sub(readme, fence, close)
		at(
			picture,
			'dispatcher -->|"runs a skill on an item; a drafted design waits for ./zn approve"| skills',
			"the README picture"
		)
	end)

	it("AC9: the README's dispatcher line says where the chain waits, and that it is no failure", function()
		local part = section(read("z-nile/README.md"), "## The five parts")
		local line = bullet(part, "- **The dispatcher.**")
		at(line, "Its `design` step drafts a design that a person approves", "the README's dispatcher line")
		at(
			line,
			"it stops (exit 3, waiting for the person, not a failure) before it readies a raft any of whose issues has no approval on `origin/main` that matches its contract",
			"the README's dispatcher line"
		)
		at(line, "`./zn approve <id> --publish`", "the README's dispatcher line")
		at(line, "then `./zn dispatch <R-id>` goes on", "the README's dispatcher line")
	end)

	it("AC9: zz-rules' chain rule readies a raft only once its approvals match", function()
		local rules = read("z-nile/skills/zz-rules/SKILL.md")
		local chain = bullet(section(rules, "## Dispatch"), "- **The chain.**")
		at(
			chain,
			"a prepared raft gets `z-ready` once every issue in it has an approval on `origin/main` that matches its contract",
			"zz-rules' chain rule"
		)
		at(
			chain,
			"until then the chain stops (exit 3, waiting for the person, not a failure)",
			"zz-rules' chain rule"
		)
		at(chain, "`workread.unapproved`", "zz-rules' chain rule")
		-- what it kept: the gates, the run gate, the questions stop
		at(chain, "always a human's", "zz-rules' chain rule")
		at(chain, "`./zn lessons --uncovered <id>`", "zz-rules' chain rule")
	end)

	it("AC9: z-design's step 5 says the design is not held for the approval under the dispatcher", function()
		local skill = read("z-nile/skills/z-design/SKILL.md")
		local review = section(skill, "## 5. Adversarial design review (required)")
		local line =
			"Under the dispatcher you do not ask: the chain merges the prep and rafts the issue, and stops before the raft is readied until a person has approved it"
		at(review, "Do not run it yourself. " .. line, "z-design step 5")
		-- the headless section stays the one every model step's skill shares (c0117 docs)
		t.expect(has(section(skill, "## Headless (under `./zn dispatch`)"), line)).toBe(false)
	end)
	it(
		"AC9: z-ready and zz-rules' ready row describe an approval the dispatched path asks for, not a one-time step",
		function()
			local ready = read("z-nile/skills/z-ready/SKILL.md")
			at(
				ready,
				"A design the dispatcher drafted, merged and rafted has none until a person approves it: `./zn ready` refuses it, and the chain waits for it before `z-ready`",
				"z-ready step 2"
			)
			-- the legacy sentence stays beside it: an item prepared before approval (f0339's docs spec finds this line by it)
			at(ready, "An item prepared before approval has none either", "z-ready step 2")
			local rules = read("z-nile/skills/zz-rules/SKILL.md")
			t.expect(has(rules, "told to take that one-time step")).toBe(false)
			at(
				rules,
				"the refusal names `./zn approve <id>`, then `./zn approve <id> --publish`, in a worktree on `origin/main`",
				"zz-rules' ready row"
			)
		end
	)
end)
