--!strict
-- c0115 AC7: a raft's prompt names z-nile's step skills (zz-execute, zz-rules, zz-arch, zz-test, zz-review, in that
-- order) and then every skill of the raft's own project, each from its real folder, never through .claude/skills,
-- and pastes none of them. A z-nile raft gets no project skill, and another project's skills never reach it.
-- The prompt names the project and does not carry a lessons index.
-- Fixture under .cache/c0115-prompt (tests/lib/trackerfix): a pickman raft in tracker/ (the fixtures' layout,
-- tests/lib/engine REGISTRY) and a z-nile raft in z-nile/.tracker, with a pickman skill and lessons on both sides.
local engine = require("@tests/lib/engine")
local fs = require("@lune/fs")
local process = require("@lune/process")
-- the repository's top: this spec runs from z-nile/ (c0120), and the real tree's files are read from there
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local PREPARED = "prepared-quiet-copper-falcon"
local Z = "z-nile/.tracker"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
local INLINED = { "zz-execute", "zz-rules", "zz-arch", "zz-test", "zz-review" }

local function raft(id: string, member: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {string.lower(id)}\nsingle: true\nissues: [{member}]\n`
		.. `design: ready\ncreated: 2026-10-21\nstatus: {PREPARED}\n---\n\n# {id}\n`
end
local function issue(id: string, raftId: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {id}\nraft: {raftId}\ndepends_on: []\nemergent: false\n`
		.. `design: ready\ncreated: 2026-10-21\nstatus: {PREPARED}\n---\n\n# {id}\n`
end
local function lesson(check: string): string
	return `---\ntitle: A lesson\nwhen: build\ntags: [wiring]\ncheck: {check}\nfrom: user 2026-10-21: said so\n---\nBody.\n`
end
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function section(prompt: string, from: string, to: string?): string
	local a = string.find(prompt, from, 1, true)
	if not a then
		error(`no {from} in the prompt`, 2)
	end
	local b = if to then string.find(prompt, to, a :: number, true) else nil
	return string.sub(prompt, a :: number, (b or 0) - 1)
end
-- the skill paths the prompt names, in order, from the Skills section
local function named(prompt: string): { string }
	local out = {}
	for path in string.gmatch(section(prompt, "\n## Skills"), "`([^`]+)`") do
		if string.find(path, "/SKILL.md", 1, true) then
			table.insert(out, path)
		end
	end
	return out
end

local f: trackerfix.Fixture
local function ready(id: string, root: string): string
	local r = trackerfix.tr(f, f.main, { "ready", id })
	if not r.ok then
		error(r.stderr .. r.stdout, 2)
	end
	return fs.readFile(`{f.main}/{root}/rafts/active/{id}/prompt.md`)
end

return t.spec("c0115 a prompt names z-nile's skills and its own project's", function(it)
	it("sets up a pickman raft, a z-nile raft, a pickman skill and lessons in both projects", function()
		f = trackerfix.new("c0115-prompt", {
			[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
			["pickman/.tracker/architecture.md"] = "# map\n",
			["pickman/.tracker/rafts/R0010/R0010.md"] = raft("R0010", "c0010"),
			["pickman/.tracker/rafts/R0010/check.sh"] = CHECK,
			["pickman/.tracker/issues/c0010/c0010.md"] = issue("c0010", "R0010"),
			["pickman/.tracker/issues/c0010/check.sh"] = CHECK,
			[`{Z}/rafts/R0020/R0020.md`] = raft("R0020", "c0020"),
			[`{Z}/rafts/R0020/check.sh`] = CHECK,
			[`{Z}/issues/c0020/c0020.md`] = issue("c0020", "R0020"),
			[`{Z}/issues/c0020/check.sh`] = CHECK,
			["pickman/skills/pickman-play/SKILL.md"] = "---\nname: pickman-play\ndescription: d\n---\n\n# Play: PLAY-RULES\n",
			["pickman/skills/pickman-play/lessons/feel.md"] = lesson("Does the game feel fair?"),
			["z-nile/skills/zz-test/lessons/pin.md"] = lesson("Are the inputs pinned?"),
		})
	end)

	it(
		"the fixture's copied skills carry their lessons (the user's G7), for every folder engine.copy copies",
		function()
			local count = 0
			-- the folders engine.copy copies (z-nile's skills), from its own constant: a project's lessons are not copied
			for _, base in engine.COPIED_SKILLS do
				if fs.isDir(`{TOP}/{base}`) then
					for _, skill in fs.readDir(`{TOP}/{base}`) do
						local dir = `{base}/{skill}/lessons`
						if fs.isDir(`{TOP}/{dir}`) then
							for _, name in fs.readDir(`{TOP}/{dir}`) do
								count += 1
								if not fs.isFile(`{f.main}/{dir}/{name}`) then
									error(`the fixture lacks {dir}/{name}`)
								end
							end
						end
					end
				end
			end
			t.expect(count > 0).toBe(true)
		end
	)

	it(
		"a pickman raft names z-nile's five skills in order, then pickman's, from their real folders",
		function()
			local prompt = ready("R0010", "pickman/.tracker")
			local paths = named(prompt)
			local want = {}
			for _, s in INLINED do
				table.insert(want, `z-nile/skills/{s}/SKILL.md`)
			end
			table.insert(want, "pickman/skills/pickman-play/SKILL.md")
			t.expect(paths).toEqual(want)
			t.expect(has(prompt, "PLAY-RULES")).toBe(false)
			t.expect(has(prompt, "zz-test/pin")).toBe(false)
			t.expect(has(prompt, "pickman-play/feel")).toBe(false)
			t.expect(has(prompt, '<file path=".claude/')).toBe(false)
			t.expect(has(prompt, "This raft is the pickman project's.")).toBe(true)
			t.expect(has(prompt, "Search with `./zn lessons <terms>`")).toBe(true)
			t.expect(has(prompt, "{{")).toBe(false)
		end
	)

	it("a z-nile raft names the same five and no project skill", function()
		local prompt = ready("R0020", Z)
		local want = {}
		for _, s in INLINED do
			table.insert(want, `z-nile/skills/{s}/SKILL.md`)
		end
		t.expect(named(prompt)).toEqual(want)
		t.expect(has(prompt, "PLAY-RULES")).toBe(false)
		t.expect(has(prompt, "pickman-play")).toBe(false)
		t.expect(has(prompt, "zz-test/pin")).toBe(false)
		t.expect(has(prompt, "This raft is the z-nile project's.")).toBe(true)
		t.expect(has(prompt, "{{")).toBe(false)
	end)
end)
