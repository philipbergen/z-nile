--!strict
-- c0114 AC9: the skills, AGENTS.md, SETUP.md and the templates name `./zn` and the moved paths, never the old ones
-- (scripts/tracker.sh is named once, as the forwarder), and they state the project-root rules the engine follows.
local fs = require("@lune/fs")
local projects = require("@znile/engine/projects")
-- c0120 override: the spec runs from z-nile/, its home, after the move
local process = require("@lune/process")
local serde = require("@lune/serde")
local skills = require("@znile/engine/skills")
local t = require("@tests/lib/t")

-- c0184 override: the skills' folders come from the one reader of them, over the registry's projects
local function skillBases(top: string): { string }
	local out: { string } = {}
	for _, folder in skills.folders(projects.load(top)) do
		table.insert(out, folder.path)
	end
	return out
end
-- c0115 override: the skills' real folders, every project's (never through the .claude/skills links); each
-- entry is a repository-relative skill folder ("z-nile/skills/zz-rules")
local function skillDirs(top: string): { string }
	local out = {}
	for _, base in skillBases(top) do
		local names = fs.readDir(`{top}/{base}`)
		table.sort(names)
		for _, name in names do
			table.insert(out, `{base}/{name}`)
		end
	end
	return out
end
-- c0120 override: the spec runs from z-nile/, so every document is read from the checkout's top
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function docs(): { [string]: string }
	-- c0120 override: the spec runs from z-nile/, its home: the checkout's files are read from the top
	local out: { [string]: string } = {
		["AGENTS.md"] = fs.readFile(`{TOP}/AGENTS.md`),
		["SETUP.md"] = fs.readFile(`{TOP}/SETUP.md`),
	}
	for _, dir in skillDirs(TOP) do
		-- c0120 override: the spec runs from z-nile/, its home: the checkout's files are read from the top
		if fs.isFile(`{TOP}/{dir}/SKILL.md`) then
			out[`{dir}/SKILL.md`] = fs.readFile(`{TOP}/{dir}/SKILL.md`)
		end
		-- c0120 override: the spec runs from z-nile/, its home: the checkout's files are read from the top
		if fs.isDir(`{TOP}/{dir}/lessons`) then
			for _, name in fs.readDir(`{TOP}/{dir}/lessons`) do
				out[`{dir}/lessons/{name}`] = fs.readFile(`{TOP}/{dir}/lessons/{name}`)
			end
		end
	end
	for _, rel in { "prompt.md", "issue/doc.md", "issue/check.sh", "raft/doc.md", "raft/check.sh" } do
		-- c0120 override: the spec runs from z-nile/, its home: the checkout's files are read from the top
		out[`z-nile/templates/{rel}`] = fs.readFile(`{TOP}/z-nile/templates/{rel}`)
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
		-- c0120 override: each home has its own scripts/ (pickman/scripts/check.sh, z-nile/scripts/check.sh), so an old
		-- path counts only where no home's folder (or the words "home's", naming one) is in front of it
		-- c0120 override: each home has its own scripts/ (pickman/scripts/check.sh, z-nile/scripts/check.sh), so an old
		local function namesOld(text: string, old: string): boolean
			local i = 1
			while true do
				local s, e = string.find(text, old, i, true)
				if not s then
					return false
				end
				local before = string.sub(text, math.max(1, s - 8), s - 1)
				if
					not (
						string.match(before, "pickman/$")
						or string.match(before, "z%-nile/$")
						or string.match(before, "home's `$")
					)
				then
					return true
				end
				i = (e :: number) + 1
			end
		end
		for path, text in docs() do
			for _, old in OLD do
				-- c0120 override: the spec runs from z-nile/, its home, after the move
				if namesOld(text, old) then
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
				local allowed = if path == `z-nile/skills/zz-rules/SKILL.md` then 1 else 0
				if n ~= allowed then
					table.insert(bad, `{path}: {n}`)
				end
			end
			table.sort(bad)
			t.expect(table.concat(bad, "\n")).toBe("")
			local tracker = fs.readFile(`{TOP}/z-nile/skills/zz-rules/SKILL.md`)
			at(tracker, "The command is `./zn` at the repository root (`scripts/tracker.sh` forwards to it")
		end
	)

	it("new items' check.sh files use the moved helpers and ./zn", function()
		-- c0120 override: the spec runs from z-nile/, its home: the checkout's files are read from the top
		local issue = fs.readFile(`{TOP}/z-nile/templates/issue/check.sh`)
		at(issue, 'rev-parse --show-toplevel)/z-nile/lib/ac.sh"')
		local raft = fs.readFile(`{TOP}/z-nile/templates/raft/check.sh`)
		-- c0120 override: a raft's check.sh runs from its project's home, so it names the gate and ./zn by the root, and
		-- the gate it runs is its project's
		-- c0120 override: a raft's check.sh runs from its project's home, so it names the gate and ./zn by the root, and
		-- c0120 override: the spec runs from z-nile/, its home: the checkout's files are read from the top
		at(
			raft,
			'check "RC0: project gate passes (affected)" "$ZN_ROOT/z-nile/check.sh" --project {{PROJECT}} --affected'
		)
		at(raft, 'for dir in $("$ZN_ROOT/zn" members {{ID}}); do')
		at(raft, '"$ZN_ROOT/zn" promote-check {{ID}}')
	end)

	it("the tracker and make-issue skills state the project-root rules", function()
		local tracker = fs.readFile(`{TOP}/z-nile/skills/zz-rules/SKILL.md`)
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
		local make = fs.readFile(`{TOP}/z-nile/skills/z-ticket/SKILL.md`)
		-- the project: --project's, else the directory's, refused at the root (decided with the user, 2026-10-21)
		at(make, "`./zn new issue <f|d|c> <kebab-slug> --project <name> --desc")
		at(make, "The project is `--project`'s when given, else the one whose folder you run `./zn` in")
		at(
			make,
			"at the checkout's root, or in a folder no project holds, `./zn` refuses and asks for `--project`"
		)
		at(make, "Tooling work (the tracker, the gate, the guards, the skills, CI) is `--project z-nile`")
		-- c0120 override: pickman has its folder now, pickman/; at the root game work still names --project pickman
		-- c0183 override: a game's, the portal's or the library's work is its own project's, pickman one of them
		at(make, "the work of a game, the portal or the arcade library is its project's (`--project pickman`")
		at(tracker, "the directory gives the project unless `--project` names one")
		at(
			tracker,
			"the commands that create an item, and so must choose its project (`new issue`, `new raft`), refuse and ask for `--project`"
		)
		at(
			tracker,
			"read-only ones read every project there (`list` shows them all), because reading needs no project"
		)
		-- every capture line a skill or template gives names its project, or its raft
		-- c0120 override: the documents are read from the checkout's top (this spec runs from z-nile/)
		for _, dir in skillDirs(TOP) do
			local doc = `{dir}/SKILL.md`
			if fs.isFile(`{TOP}/{doc}`) then
				for line in string.gmatch(fs.readFile(`{TOP}/{doc}`), "[^\n]+") do
					for cmd in string.gmatch(line, "`(%./zn new [^`]*)`") do
						if
							not (
								string.find(cmd, "--project", 1, true) or string.find(cmd, "--raft", 1, true)
							)
						then
							error(`{doc}: {cmd} names no project`)
						end
					end
				end
			end
		end
		at(
			fs.readFile(`{TOP}/z-nile/templates/prompt.md`),
			"`./zn new issue … --project <name>`, or `--raft <R-id>`"
		)
	end)

	it(
		"the settings allow ./zn wherever they allowed scripts/tracker.sh, and keep the old entries",
		function()
			-- c0120 override: the spec runs from z-nile/, so the settings are read from the checkout's top
			local settings = serde.decode("json", fs.readFile(`{TOP}/.claude/settings.json`))
			local allow: { string } = settings.permissions.allow
			local old = 0
			for _, entry in allow do
				local rest = string.match(entry, "^Bash%(scripts/tracker%.sh (.*)$")
					or string.match(entry, "^Bash%(tracker%.sh (.*)$")
				if rest then
					old += 1
					if not table.find(allow, "Bash(./zn " .. rest) then
						error(`no ./zn entry beside {entry}`)
					end
				end
			end
			t.expect(old > 0).toBe(true)
			-- the Stop gate is gone; the other hooks still run scripts/hooks/
			t.expect(settings.hooks.Stop).toBe(nil)
			t.expect(settings.hooks.PostToolUse[1].hooks[1].command)
				.toBe('"$CLAUDE_PROJECT_DIR"/scripts/hooks/post-edit.sh')
		end
	)

	it("the sequestration check covers every project root", function()
		local cmd =
			"-- 'tracker/**/check.sh' 'tracker/**/acceptance/**' '*/.tracker/**/check.sh' '*/.tracker/**/acceptance/**'"
		for _, skill in { "zz-review", "zz-test", "zz-execute" } do
			at(fs.readFile(`{TOP}/z-nile/skills/{skill}/SKILL.md`), cmd)
		end
	end)
end)
