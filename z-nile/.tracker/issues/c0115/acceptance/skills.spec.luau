--!strict
-- c0115 AC1: z-nile's skills live in z-nile/skills/<name>/, a project's in <project>/skills/<name>/, and
-- .claude/skills/<name> is a committed relative link to each (../../<folder>/<name>). `./zn skills` writes the links
-- and removes every other link there; `--check` writes nothing and names each missing, extra, wrong or non-link
-- entry and each tracked non-link. Both refuse a folder without SKILL.md, a name: that differs from its folder, a
-- name two folders share, a z-nile skill outside z-/zz-, and a project skill that is not <project>-…. Pure cases
-- through @znile/engine/skills; the command in a fixture under .cache/c0115-skills (tests/lib/trackerfix).
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local projects = require("@znile/engine/projects")
local skills = require("@znile/engine/skills")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local function doc(name: string): string
	return `---\nname: {name}\ndescription: d\n---\n\n# {name}\n`
end
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local ZN: skills.Folder = { project = "z-nile", path = "z-nile/skills" }
local PM: skills.Folder = { project = "pickman", path = "pickman/skills" }
local function entry(name: string, front: string?): skills.Entry
	return { name = name, text = doc(front or name) }
end
local function plan(found: { skills.Found }): ({ string }, { string })
	local list, problems = skills.plan(found)
	local names = {}
	for _, s in list do
		table.insert(names, `{s.name}={s.dir}`)
	end
	return names, problems
end
local function one(problems: { string }, needle: string)
	local joined = table.concat(problems, "\n")
	if not has(joined, needle) then
		error(`no problem names {needle}: {joined}`, 2)
	end
end

local f: trackerfix.Fixture
local wt = ""
local function zn(args: { string }): fixture.Result
	return trackerfix.tr(f, wt, args)
end
local function readlink(path: string): string?
	local r = process.exec("readlink", { path })
	return if r.ok then (string.gsub(r.stdout, "\n$", "")) else nil
end

return t.spec("c0115 the skill folders and their links", function(it)
	it(
		"every project's folder is <home>/skills, z-nile's first, even in a registry without z-nile",
		function()
			local reg = projects.parse(
				'retired = []\n\n[[project]]\nname = "pickman"\nroot = "pickman/.tracker"\n\n'
					.. '[[project]]\nname = "z-nile"\nroot = "z-nile/.tracker"\n'
			)
			local paths = {}
			for _, folder in skills.folders(reg :: projects.Registry) do
				table.insert(paths, `{folder.project}:{folder.path}`)
			end
			t.expect(paths).toEqual({ "z-nile:z-nile/skills", "pickman:pickman/skills" })
			local solo =
				projects.parse('retired = []\n\n[[project]]\nname = "pickman"\nroot = "pickman/.tracker"\n')
			local only = {}
			for _, folder in skills.folders(solo :: projects.Registry) do
				table.insert(only, folder.path)
			end
			t.expect(only).toEqual({ "z-nile/skills", "pickman/skills" })
		end
	)

	it("plans one skill per folder entry, sorted by name, with its real folder", function()
		local names, problems = plan({
			{ folder = ZN, entries = { entry("zz-test"), entry("z-run") } },
			{ folder = PM, entries = { entry("pickman-arch") } },
		})
		t.expect(problems).toEqual({})
		t.expect(names).toEqual({
			"pickman-arch=pickman/skills/pickman-arch",
			"z-run=z-nile/skills/z-run",
			"zz-test=z-nile/skills/zz-test",
		})
	end)

	it("refuses a folder with no SKILL.md and a name: that is not its folder's", function()
		local names, problems = plan({
			{
				folder = ZN,
				entries = { { name = "z-empty", text = nil }, entry("zz-a", "zz-b"), entry("zz-ok") },
			},
		})
		t.expect(names).toEqual({ "zz-ok=z-nile/skills/zz-ok" })
		one(problems, "z-nile/skills/z-empty: no SKILL.md")
		one(problems, "z-nile/skills/zz-a/SKILL.md")
		one(problems, "zz-b")
	end)

	it("keeps z- and zz- for z-nile, and <project>- for a project's skills", function()
		local names, problems = plan({
			{ folder = ZN, entries = { entry("helper") } },
			{
				folder = PM,
				entries = { entry("zz-arch"), entry("z-play"), entry("arch"), entry("pickman-test") },
			},
		})
		t.expect(names).toEqual({ "pickman-test=pickman/skills/pickman-test" })
		t.expect(#problems).toBe(4)
		one(problems, "z-nile/skills/helper")
		one(problems, "pickman/skills/zz-arch")
		one(problems, "pickman/skills/z-play")
		one(problems, "pickman/skills/arch")
		-- a project named zz (or z) meets its own prefix rule, and still may not take z-nile's prefixes
		local zz, zzProblems =
			plan({ { folder = { project = "zz", path = "zz/skills" }, entries = { entry("zz-play") } } })
		t.expect(zz).toEqual({})
		one(zzProblems, "the z- and zz- prefixes are z-nile's")
	end)

	it("refuses a name two folders share, naming both", function()
		local names, problems = plan({
			{ folder = ZN, entries = { entry("zz-x") } },
			{ folder = { project = "z-nile", path = "elsewhere/skills" }, entries = { entry("zz-x") } },
		})
		t.expect(names).toEqual({ "zz-x=z-nile/skills/zz-x" })
		one(problems, "z-nile/skills/zz-x")
		one(problems, "elsewhere/skills/zz-x")
	end)

	it(
		"diff names a missing, an extra, a wrong, an absolute and a non-link entry, and nothing when exact",
		function()
			local list = skills.plan({
				{ folder = ZN, entries = { entry("z-a"), entry("z-b"), entry("z-c"), entry("z-d") } },
			})
			t.expect(skills.target(list[1])).toBe("../../z-nile/skills/z-a")
			local wrong = skills.diff(list, {
				["z-b"] = "../../pickman/skills/z-b",
				["z-c"] = "/abs/z-nile/skills/z-c",
				["z-d"] = false,
				stray = "../../z-nile/skills/stray",
			})
			t.expect(#wrong).toBe(5)
			one(wrong, ".claude/skills/z-a: missing")
			one(wrong, ".claude/skills/z-b: links to ../../pickman/skills/z-b")
			one(wrong, ".claude/skills/z-c: links to /abs/")
			one(wrong, ".claude/skills/z-d: not a link")
			one(wrong, ".claude/skills/stray")
			local exact = skills.diff(list, {
				["z-a"] = "../../z-nile/skills/z-a",
				["z-b"] = "../../z-nile/skills/z-b",
				["z-c"] = "../../z-nile/skills/z-c",
				["z-d"] = "../../z-nile/skills/z-d",
			})
			t.expect(exact).toEqual({})
		end
	)

	it("sets up a fixture with z-nile's skills, a project skill and a worktree", function()
		f = trackerfix.new("c0115-skills", {
			["pickman/skills/pickman-play/SKILL.md"] = doc("pickman-play"),
		})
		wt = `{f.base}/wt`
		fixture.git(f.main, { "worktree", "add", "-q", "-b", "skills-work", wt, "main" })
	end)

	it("--check names every missing link and exits 1 before any link exists", function()
		local r = zn({ "skills", "--check" })
		t.expect(r.code).toBe(1)
		t.expect(has(r.stderr, ".claude/skills/pickman-play: missing")).toBe(true)
		t.expect(has(r.stderr, ".claude/skills/z-run: missing")).toBe(true)
		t.expect(fs.isDir(`{wt}/.claude/skills`)).toBe(false)
	end)

	it("skills writes one relative link per skill, and --check then passes", function()
		local r = zn({ "skills" })
		if not r.ok then
			error(r.stderr .. r.stdout)
		end
		t.expect(readlink(`{wt}/.claude/skills/z-run`)).toBe("../../z-nile/skills/z-run")
		t.expect(readlink(`{wt}/.claude/skills/pickman-play`)).toBe("../../pickman/skills/pickman-play")
		t.expect(fs.isFile(`{wt}/.claude/skills/z-run/SKILL.md`)).toBe(true)
		local count = 0
		for _ in fs.readDir(`{wt}/z-nile/skills`) do
			count += 1
		end
		t.expect(#fs.readDir(`{wt}/.claude/skills`)).toBe(count + 1)
		local c = zn({ "skills", "--check" })
		t.expect(c.code).toBe(0)
		t.expect(has(c.stdout, "ok")).toBe(true)
	end)

	it(
		"skills replaces a wrong or absolute link and removes an extra one; a second run changes nothing",
		function()
			process.exec("rm", { "-f", `{wt}/.claude/skills/z-run`, `{wt}/.claude/skills/zz-test` })
			process.exec("ln", { "-s", "../../pickman/skills/pickman-play", `{wt}/.claude/skills/z-run` })
			process.exec("ln", { "-s", `{wt}/z-nile/skills/zz-test`, `{wt}/.claude/skills/zz-test` })
			process.exec("ln", { "-s", "../../z-nile/skills/gone", `{wt}/.claude/skills/gone` })
			local c = zn({ "skills", "--check" })
			t.expect(c.code).toBe(1)
			t.expect(has(c.stderr, ".claude/skills/z-run: links to ../../pickman/skills/pickman-play"))
				.toBe(true)
			t.expect(has(c.stderr, ".claude/skills/zz-test: links to /")).toBe(true)
			t.expect(has(c.stderr, ".claude/skills/gone")).toBe(true)
			t.expect(zn({ "skills" }).ok).toBe(true)
			t.expect(readlink(`{wt}/.claude/skills/z-run`)).toBe("../../z-nile/skills/z-run")
			t.expect(readlink(`{wt}/.claude/skills/zz-test`)).toBe("../../z-nile/skills/zz-test")
			t.expect(readlink(`{wt}/.claude/skills/gone`)).toBe(nil)
			t.expect(fs.isDir(`{wt}/.claude/skills/gone`)).toBe(false)
			local again = zn({ "skills" })
			t.expect(again.ok).toBe(true)
			t.expect(has(again.stdout, "linked ")).toBe(false)
			t.expect(has(again.stdout, "removed ")).toBe(false)
		end
	)

	it("a real directory in .claude/skills fails --check and is never removed by skills", function()
		fs.writeDir(`{wt}/.claude/skills/z-real`)
		fs.writeFile(`{wt}/.claude/skills/z-real/SKILL.md`, doc("z-real"))
		local c = zn({ "skills", "--check" })
		t.expect(c.code).toBe(1)
		t.expect(has(c.stderr, ".claude/skills/z-real: not a link")).toBe(true)
		local w = zn({ "skills" })
		t.expect(w.code).toBe(1)
		t.expect(has(w.stderr, ".claude/skills/z-real: not a link")).toBe(true)
		t.expect(fs.isFile(`{wt}/.claude/skills/z-real/SKILL.md`)).toBe(true)
		fs.removeDir(`{wt}/.claude/skills/z-real`)
	end)

	it(
		"a committed real folder under .claude/skills fails --check even when the working tree has the link",
		function()
			fixture.git(wt, { "add", "-A" })
			fixture.git(wt, { "commit", "-q", "-m", "links" })
			t.expect(zn({ "skills", "--check" }).code).toBe(0)
			local ls = fixture.git(wt, { "ls-files", "-s", "--", ".claude/skills/z-run" })
			t.expect(string.sub(ls, 1, 6)).toBe("120000")
			-- a branch that committed the skill as a real folder, then put the link back without committing
			process.exec("rm", { "-f", `{wt}/.claude/skills/z-run` })
			fs.writeDir(`{wt}/.claude/skills/z-run`)
			fs.writeFile(`{wt}/.claude/skills/z-run/SKILL.md`, doc("z-run"))
			fixture.git(wt, { "add", "-A" })
			fixture.git(wt, { "commit", "-q", "-m", "a real folder" })
			fs.removeDir(`{wt}/.claude/skills/z-run`)
			process.exec("ln", { "-s", "../../z-nile/skills/z-run", `{wt}/.claude/skills/z-run` })
			local c = zn({ "skills", "--check" })
			t.expect(c.code).toBe(1)
			t.expect(has(c.stderr, ".claude/skills/z-run/SKILL.md: tracked as a file")).toBe(true)
		end
	)

	it("skills refuses a plan problem and writes nothing", function()
		fs.writeDir(`{wt}/pickman/skills/play`)
		fs.writeFile(`{wt}/pickman/skills/play/SKILL.md`, doc("play"))
		process.exec("rm", { "-f", `{wt}/.claude/skills/z-ticket` })
		local w = zn({ "skills" })
		t.expect(w.code).toBe(1)
		t.expect(has(w.stderr, "pickman/skills/play")).toBe(true)
		t.expect(readlink(`{wt}/.claude/skills/z-ticket`)).toBe(nil)
		t.expect(zn({ "skills", "--check" }).code).toBe(1)
		fs.removeDir(`{wt}/pickman/skills/play`)
	end)

	it("skills without --check refuses in the main checkout; --check runs there", function()
		local w = trackerfix.tr(f, f.main, { "skills" })
		t.expect(w.code).toBe(1)
		t.expect(has(w.stderr, "inside a worktree")).toBe(true)
		local c = trackerfix.tr(f, f.main, { "skills", "--check" })
		t.expect(c.code).toBe(1) -- the main checkout has no links: --check reads and reports
		t.expect(has(c.stderr, "missing")).toBe(true)
		t.expect(fs.isDir(`{f.main}/.claude/skills`)).toBe(false)
	end)
	it(
		"a .claude/skills that links outside the repository is refused, and nothing outside it changes",
		function()
			local outside = `{f.base}/outside-skills`
			fs.writeDir(outside)
			process.exec("ln", { "-s", "../nowhere", `{outside}/someone-elses-skill` })
			process.exec("rm", { "-r", `{wt}/.claude/skills` }) -- links only: rm -r never follows them
			process.exec("ln", { "-s", outside, `{wt}/.claude/skills` })
			local w = zn({ "skills" })
			t.expect(w.code).toBe(1)
			t.expect(has(w.stderr, ".claude/skills: a link")).toBe(true)
			t.expect(readlink(`{outside}/someone-elses-skill`)).toBe("../nowhere")
			t.expect(readlink(`{outside}/z-run`)).toBe(nil)
			local c = zn({ "skills", "--check" })
			t.expect(c.code).toBe(1)
			t.expect(has(c.stderr, ".claude/skills: a link")).toBe(true)
			t.expect(readlink(`{outside}/someone-elses-skill`)).toBe("../nowhere")
		end
	)

	it("--check fails on a committed .claude/skills link, whatever it points at", function()
		fixture.git(wt, { "add", "-A" })
		fixture.git(wt, { "commit", "-q", "-m", "a linked skills folder" })
		local ls = fixture.git(wt, { "ls-files", "-s", "--", ".claude/skills" })
		t.expect(string.sub(ls, 1, 6)).toBe("120000")
		local c = zn({ "skills", "--check" })
		t.expect(c.code).toBe(1)
		t.expect(has(c.stderr, ".claude/skills: tracked itself")).toBe(true)
	end)

	it("a .claude that is a link is refused too", function()
		local outside = `{f.base}/outside-claude`
		process.exec("mv", { `{wt}/.claude`, outside })
		process.exec("ln", { "-s", outside, `{wt}/.claude` })
		local w = zn({ "skills" })
		t.expect(w.code).toBe(1)
		t.expect(has(w.stderr, ".claude: a link")).toBe(true)
		t.expect(readlink(`{f.base}/outside-skills/someone-elses-skill`)).toBe("../nowhere")
	end)

	it("a missing registry refuses, writing nothing and never guessing the folders (c0114)", function()
		process.exec("rm", { "-f", `{wt}/.claude` })
		fs.removeFile(`{wt}/z-nile/projects.toml`)
		for _, args in { { "skills", "--check" }, { "skills" } } do
			local r = zn(args)
			t.expect(r.ok).toBe(false)
			t.expect(has(r.stderr, "projects.toml")).toBe(true)
		end
		t.expect(fs.isDir(`{wt}/.claude`) or fs.isFile(`{wt}/.claude`)).toBe(false)
	end)
end)
