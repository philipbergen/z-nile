--!strict
-- f0399 AC15: the skills, AGENTS.md and the README carry the guess-mode rules of the Design's section 7, and the
-- dispatcher's "Headless" section is untouched. Reads the real files; writes nothing.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

-- specs run from their project's home (z-nile/); the repository's files are read from the checkout's top
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function read(path: string): string
	return fs.readFile(`{TOP}/{path}`)
end

local function skill(name: string): string
	return read(`z-nile/skills/{name}/SKILL.md`)
end

local function has(text: string, part: string): boolean
	return string.find(text, part, 1, true) ~= nil
end

local function at(text: string, part: string): number
	return string.find(text, part, 1, true) or error(`missing: {part}`, 2)
end

-- the text of the `## <heading>` section, up to the next `## ` heading
local function section(text: string, heading: string): string
	local mark = `\n## {heading}\n`
	local start = string.find(text, mark, 1, true) or error(`no "## {heading}" section`, 2)
	local nxt = string.find(text, "\n## ", start + #mark, true)
	return if nxt then string.sub(text, start, nxt - 1) else string.sub(text, start)
end

local HEADLESS = "Headless (under `./zn dispatch`)"

return t.spec("f0399: the skills say guess mode", function(it)
	it("z-work has Guess mode, the new actions, and no rule against guessing a human decision", function()
		local w = skill("z-work")
		local g = section(w, "Guess mode")
		t.expect(has(g, "`./zn guess <issue-id> --step design|raft|build`")).toBe(true)
		t.expect(has(g, "at the moment you make the choice")).toBe(true)
		t.expect(has(g, "Never guess under `./zn dispatch`")).toBe(true)
		t.expect(has(g, "never guess an idea's open line")).toBe(true)
		t.expect(has(g, "never guess a choice that would drop or shrink a captured outcome")).toBe(true)
		t.expect(has(g, "Nothing unapproved lands")).toBe(true)
		t.expect(has(g, "`./zn guesses <R-id>`")).toBe(true)
		for _, action in { "`draft`", "`rafting`", "`fix`", "`wait`" } do
			t.expect(has(w, action)).toBe(true)
		end
		t.expect(has(w, "`./zn work next <issue-id>`")).toBe(true)
		t.expect(has(w, "Never guess a human decision")).toBe(false)
		t.expect(has(w, "A `wait` is not a release")).toBe(true)
		t.expect(at(w, "\n## Guess mode\n") < at(w, "\n## Lessons\n")).toBe(true)
	end)

	it("z-design and z-raft have Guess mode before Headless", function()
		local d = skill("z-design")
		t.expect(at(d, "\n## Guess mode\n") < at(d, `\n## {HEADLESS}\n`)).toBe(true)
		local dg = section(d, "Guess mode")
		t.expect(has(dg, "`./zn guess <id> --step design`")).toBe(true)
		t.expect(has(dg, "**Guess (prep) G<n>**")).toBe(true)
		t.expect(has(dg, "`Guessed (agent, YYYY-MM-DD): G<n>`")).toBe(true)
		t.expect(has(dg, "do not stop for `./zn approve`")).toBe(true)
		t.expect(has(dg, "merge your own green prep pull request")).toBe(true)
		t.expect(has(dg, "give the claim back (`./zn status <id> new`)")).toBe(true)
		local r = skill("z-raft")
		t.expect(at(r, "\n## Guess mode\n") < at(r, `\n## {HEADLESS}\n`)).toBe(true)
		local rg = section(r, "Guess mode")
		t.expect(has(rg, "`./zn guess <member> --step raft`")).toBe(true)
		t.expect(has(rg, "`Guessed (agent, YYYY-MM-DD): <member> G<n>`")).toBe(true)
		t.expect(has(rg, "merge your own green rafting pull request")).toBe(true)
		t.expect(has(r, "goes into the raft of what it depends on")).toBe(true)
	end)

	it("z-ready, zz-execute and zz-review say where approval is asked and that guesses are read", function()
		local y = skill("z-ready")
		t.expect(has(y, "An approval is not needed to ready a raft: `./zn done` asks for it")).toBe(true)
		t.expect(has(y, "under `./zn dispatch`, `ready` still asks")).toBe(true)
		t.expect(has(y, "asks for that one-time step and stops")).toBe(false)
		t.expect(has(y, "`./zn ready <R-id> --on <R-id>`")).toBe(true)
		local e = skill("zz-execute")
		t.expect(has(e, "`./zn guess <id> --step build`")).toBe(true)
		t.expect(has(e, "Waiting for approval: <id> (<n> guesses; <changed parts>) | none")).toBe(true)
		t.expect(has(e, "in the raft's worktree, on its top layer")).toBe(true)
		t.expect(has(e, "In guess mode every deviation is also recorded with `./zn guess <id> --step build`"))
			.toBe(true)
		local v = skill("zz-review")
		t.expect(has(v, "`guesses.md`")).toBe(true)
		t.expect(has(v, "a guess with no evidence")).toBe(true)
		t.expect(has(v, "a judgement call in the diff that has no guess")).toBe(true)
	end)

	it(
		"zz-rules lists guess and guesses, the ready commit's trailers and where approval is checked",
		function()
			local z = skill("zz-rules")
			t.expect(has(z, "| guess | `./zn guess <issue-id> --step design\\|raft\\|build")).toBe(true)
			t.expect(has(z, "| guesses | `./zn guesses <issue-id\\|R-id> [--check]`")).toBe(true)
			t.expect(has(z, "`Lands: approved`")).toBe(true)
			t.expect(has(z, "`On: <R-id>`")).toBe(true)
			t.expect(has(z, "`<R-id>/base`")).toBe(true)
			t.expect(has(z, "`guesses.md`")).toBe(true)
			t.expect(has(z, "Refuses a member with no approval, or whose contract hash no longer matches"))
				.toBe(false)
			t.expect(has(z, "`--on <R-id>`")).toBe(true)
		end
	)

	it("AGENTS.md and the README say the worker designs and rafts on recorded guesses", function()
		for _, path in { "AGENTS.md", "z-nile/README.md" } do
			local text = read(path)
			t.expect(has(text, "on recorded guesses")).toBe(true)
			t.expect(has(text, "nothing unapproved lands")).toBe(true)
		end
	end)

	it("the four Headless sections are identical and still forbid guessing a ruling", function()
		local first = section(skill("z-idea"), HEADLESS)
		t.expect(has(first, "Never decide what you would ask the user, and never guess a ruling.")).toBe(true)
		for _, name in { "z-design", "z-raft", "z-code" } do
			t.expect(section(skill(name), HEADLESS)).toBe(first)
		end
	end)
end)
