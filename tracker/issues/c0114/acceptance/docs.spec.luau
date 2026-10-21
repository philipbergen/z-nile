--!strict
-- c0114 AC17: the skills, AGENTS.md, SETUP.md and the templates name `./zn` and the moved paths, never the old ones
-- (scripts/tracker.sh is named once, as the forwarder), and they state the project-root rules the engine follows.
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

local SKILLS = ".claude/skills"

local function docs(): { [string]: string }
	local out: { [string]: string } = {
		["AGENTS.md"] = fs.readFile("AGENTS.md"),
		["SETUP.md"] = fs.readFile("SETUP.md"),
	}
	for _, skill in fs.readDir(SKILLS) do
		local dir = `{SKILLS}/{skill}`
		if fs.isFile(`{dir}/SKILL.md`) then
			out[`{dir}/SKILL.md`] = fs.readFile(`{dir}/SKILL.md`)
		end
		if fs.isDir(`{dir}/lessons`) then
			for _, name in fs.readDir(`{dir}/lessons`) do
				out[`{dir}/lessons/{name}`] = fs.readFile(`{dir}/lessons/{name}`)
			end
		end
	end
	for _, rel in { "prompt.md", "issue/doc.md", "issue/check.sh", "raft/doc.md", "raft/check.sh" } do
		out[`z-nile/templates/{rel}`] = fs.readFile(`z-nile/templates/{rel}`)
	end
	return out
end

local function at(text: string, needle: string): number
	local s = string.find(text, needle, 1, true)
	if not s then
		error(`missing: {needle}`)
	end
	return s
end

-- old paths, matched as literal text
local OLD = {
	"scripts/tracker/",
	"scripts/check.sh",
	"scripts/setup.sh",
	"scripts/ci-verify.sh",
	"scripts/affected",
	"scripts/vendor",
	"scripts/lib/ac.sh",
	"scripts/lib/fence.sh",
	"scripts/lib/par.sh",
	"scripts/lib/git-hooks",
	"scripts/lib/replace-file.pl",
	"scripts/lib/sh.luau",
	"scripts/lib/graph.luau",
	"tracker/templates",
	"tracker/next",
}

-- every use of the command name `tracker.sh` (bare, or as scripts/tracker.sh)
local function commandUses(text: string): number
	local n = 0
	local i = 1
	while true do
		local s, e = string.find(text, "tracker.sh", i, true)
		if not s then
			return n
		end
		local before = if s > 1 then string.sub(text, s - 1, s - 1) else ""
		if not string.match(before, "[%w%-_.]") then
			n += 1
		end
		i = (e :: number) + 1
	end
end

return t.spec("c0114 the docs name ./zn and the moved paths", function(it)
	it("no skill, lesson, AGENTS.md, SETUP.md or template names an old path", function()
		local bad: { string } = {}
		for path, text in docs() do
			for _, old in OLD do
				if string.find(text, old, 1, true) then
					table.insert(bad, `{path}: {old}`)
				end
			end
		end
		table.sort(bad)
		t.expect(table.concat(bad, "\n")).toBe("")
	end)

	it(
		"the command is ./zn everywhere; the tracker skill names scripts/tracker.sh once, as the forwarder",
		function()
			local bad: { string } = {}
			for path, text in docs() do
				local n = commandUses(text)
				local allowed = if path == `{SKILLS}/tracker/SKILL.md` then 1 else 0
				if n ~= allowed then
					table.insert(bad, `{path}: {n}`)
				end
			end
			table.sort(bad)
			t.expect(table.concat(bad, "\n")).toBe("")
			local tracker = fs.readFile(`{SKILLS}/tracker/SKILL.md`)
			at(tracker, "The command is `./zn` at the repository root (`scripts/tracker.sh` forwards to it")
		end
	)

	it("new items' check.sh files use the moved helpers and ./zn", function()
		local issue = fs.readFile("z-nile/templates/issue/check.sh")
		at(issue, 'rev-parse --show-toplevel)/z-nile/lib/ac.sh"')
		local raft = fs.readFile("z-nile/templates/raft/check.sh")
		at(raft, 'check "RC0: repo gate passes (full)" z-nile/check.sh --full')
		at(raft, "for dir in $(./zn members {{ID}}); do")
		at(raft, "./zn promote-check {{ID}}")
	end)

	it("the tracker and make-issue skills state the project-root rules", function()
		local tracker = fs.readFile(`{SKILLS}/tracker/SKILL.md`)
		at(
			tracker,
			"`z-nile/projects.toml` lists the projects, each with the root that holds its issues and rafts"
		)
		at(tracker, "A directory it does not list is not a project.")
		at(tracker, "One counter numbers every project, so a bare id is unique across the repository")
		at(tracker, "searches every root")
		at(tracker, "A raft lives in its members' project and never spans two.")
		at(tracker, "`rg --hidden`")
		at(
			tracker,
			"under a root that `origin/main`'s `z-nile/projects.toml` lists (never the working tree's)"
		)
		at(tracker, "never to another root")
		local make = fs.readFile(`{SKILLS}/make-issue/SKILL.md`)
		at(make, "with `--project z-nile` for tooling work")
	end)

	it("the sequestration check covers every project root", function()
		local cmd =
			"-- 'tracker/**/check.sh' 'tracker/**/acceptance/**' '*/.tracker/**/check.sh' '*/.tracker/**/acceptance/**'"
		for _, skill in { "review", "testing", "execute-raft" } do
			at(fs.readFile(`{SKILLS}/{skill}/SKILL.md`), cmd)
		end
	end)
end)
