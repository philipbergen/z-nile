--!strict
-- c0257 AC12 (G1, ruled): the home rule checks an app home for what an app home has: check.sh with the gate's exact
-- line and executable, its root's issues/ and rafts/, and its two skills; nothing of a Luau home. Fixtures under
-- .cache/c0257-home (this home's .cache); the real tree is read from its top.
local fs = require("@lune/fs")
local home = require("@tests/lib/home")
local process = require("@lune/process")
local projects = require("@znile/engine/projects")
local skills = require("@znile/engine/skills")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local HERE = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local BASE = `{HERE}/.cache/c0257-home`
local REGISTRY = '[[project]]\nname = "z-nile"\nroot = "z-nile/.tracker"\n\n'
	.. '[[project]]\nname = "board"\nroot = "board/.tracker"\nkind = "app"\n'
local CHECK = '#!/usr/bin/env bash\nexec bash "$(dirname "$0")/../z-nile/check.sh" --project board "$@"\n'

local function put(rel: string, text: string)
	local path = `{BASE}/{rel}`
	fs.writeDir(string.match(path, "^(.*)/[^/]+$") :: string)
	fs.writeFile(path, text)
end
local function complete()
	if fs.isDir(BASE) then
		fs.removeDir(BASE)
	end
	put("stylua.toml", 'indent_type = "Tabs"\n')
	put("selene.toml", 'std = "roblox"\n')
	put("board/check.sh", CHECK)
	process.exec("chmod", { "+x", `{BASE}/board/check.sh` })
	put("board/.tracker/issues/.gitkeep", "")
	put("board/.tracker/rafts/.gitkeep", "")
	put("board/skills/board-arch/SKILL.md", "---\nname: board-arch\n---\n")
	put("board/skills/board-test/SKILL.md", "---\nname: board-test\n---\n")
	put("board/app/tests/x.test.mjs", "")
end
local function run(): (string, { string })
	local reg, err = projects.parse(REGISTRY)
	t.expect(err).toBe(nil)
	local found, checked = home.problems(BASE, reg :: projects.Registry)
	return table.concat(found, "\n"), checked
end

return t.spec("c0257 AC12: the home rule for an app home", function(it)
	it("AC12: a complete app home has no problems, with no .luaurc, src/, tests/ or project file", function()
		complete()
		local found, checked = run()
		t.expect(found).toBe("")
		t.expect(checked).toEqual({ "board" })
	end)

	it("AC12: each missing piece is named", function()
		for _, rel in
			{
				"board/check.sh",
				"board/.tracker/issues",
				"board/.tracker/rafts",
				"board/skills/board-arch/SKILL.md",
				"board/skills/board-test/SKILL.md",
			}
		do
			complete()
			local path = `{BASE}/{rel}`
			if fs.isDir(path) then
				fs.removeDir(path)
			else
				fs.removeFile(path)
			end
			local found = run()
			local short = string.gsub(rel, "^board/", "")
			t.expect(string.find(found, short, 1, true) ~= nil).toBe(true)
		end
	end)

	it("AC12: a check.sh with another line, or not executable, is reported", function()
		complete()
		put("board/check.sh", "#!/usr/bin/env bash\necho ok\n")
		process.exec("chmod", { "+x", `{BASE}/board/check.sh` })
		t.expect(string.find((run()), "check.sh", 1, true) ~= nil).toBe(true)
		complete()
		process.exec("chmod", { "-x", `{BASE}/board/check.sh` })
		t.expect(string.find((run()), "check.sh", 1, true) ~= nil).toBe(true)
	end)

	it(
		"AC12: a project whose name starts z- names its skills <project>-...; z and zz still may not",
		function()
			local function entry(name: string): skills.Entry
				return { name = name, text = `---\nname: {name}\ndescription: x\n---\n` }
			end
			local function names(project: string, list: { string }): ({ string }, string)
				local found = {
					{
						folder = { project = project, path = `{project}/skills` },
						entries = {} :: { skills.Entry },
					},
				}
				for _, n in list do
					table.insert(found[1].entries, entry(n))
				end
				local plan, problems = skills.plan(found)
				local out: { string } = {}
				for _, sk in plan do
					table.insert(out, sk.name)
				end
				table.sort(out)
				return out, table.concat(problems, "\n")
			end
			local ok, none = names("z-nile-omarchy", { "z-nile-omarchy-arch", "z-nile-omarchy-test" })
			t.expect(ok).toEqual({ "z-nile-omarchy-arch", "z-nile-omarchy-test" })
			t.expect(none).toBe("")
			local _, taken = names("z-nile-omarchy", { "z-play" })
			t.expect(string.find(taken, "z-nile-omarchy/skills/z-play", 1, true) ~= nil).toBe(true)
			local zz, zzProblems = names("zz", { "zz-play" })
			t.expect(zz).toEqual({})
			t.expect(string.find(zzProblems, "the z- and zz- prefixes are z-nile's", 1, true) ~= nil)
				.toBe(true)
		end
	)

	it("AC12: the real tree's app home holds", function()
		local reg = projects.load(TOP)
		local found, checked = home.problems(TOP, reg)
		t.expect(table.concat(found, "\n")).toBe("")
		t.expect(table.find(checked, "z-nile-omarchy") ~= nil).toBe(true)
	end)
end)
