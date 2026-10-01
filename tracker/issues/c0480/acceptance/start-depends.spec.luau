--!strict
-- c0480: `tracker.sh start` refuses a raft whose member issue depends on an item outside the raft that is not done.
-- Driven for real in a throwaway clone (no remote, so start skips push and gh), like the lifecycle spec.
local clone = require("@tests/lib/clone")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local dir = `{root}/.cache/c0480-start-depends`

local function run(cmd: string, args: { string }): Result
	return process.exec(cmd, args, { cwd = dir })
end

local function must(r: Result, what: string): string
	if not r.ok then
		error(`{what} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return (string.gsub(r.stdout, "%s+$", ""))
end

local function tr(args: { string }): Result
	return run("bash", { "scripts/tracker.sh", table.unpack(args) })
end

local function git(args: { string }): string
	return must(run("git", args), "git " .. table.concat(args, " "))
end

local function edit(path: string, from: string, to: string)
	local text, n = string.gsub(fs.readFile(`{dir}/{path}`), from, to)
	assert(n > 0, `pattern {from} not found in {path}`)
	fs.writeFile(`{dir}/{path}`, text)
end

local function has(text: string, token: string): boolean
	return string.find(text, token, 1, true) ~= nil
end

local branch0 = ""

return t.spec("c0480 start checks depends_on", function(it)
	it("sets up a sandbox with five rafts covering each kind of dependency", function()
		if fs.isDir(dir) then
			fs.removeDir(dir)
		end
		clone.isolated(root, dir)
		git({ "remote", "remove", "origin" })
		-- overlay the working tree's tooling so uncommitted tracker changes are what gets tested
		local listed = process.exec(
			"git",
			{ "ls-files", "-co", "--exclude-standard", "scripts", "tracker/templates" },
			{ cwd = root }
		)
		for path in string.gmatch(listed.stdout, "[^\n]+") do
			if fs.isFile(`{root}/{path}`) then
				local parent = string.match(path, "^(.*)/[^/]+$")
				if parent then
					fs.writeDir(`{dir}/{parent}`)
				end
				fs.writeFile(`{dir}/{path}`, fs.readFile(`{root}/{path}`))
			end
		end
		git({ "config", "user.name", "e2e" })
		git({ "config", "user.email", "e2e@example.invalid" })
		for _, kind in { "issues", "rafts" } do
			for _, state in { "", "active/", "done/" } do
				local base = `{dir}/tracker/{kind}/{state}`
				for _, name in fs.readDir(base) do
					if string.match(name, "^[fdcR]%d%d%d%d$") then
						fs.removeDir(base .. name)
					end
				end
			end
		end
		for _, slug in { "base", "needs-base", "pair-a", "pair-b", "ghost", "late-a", "late-b" } do
			must(tr({ "new", "issue", "f", slug }), "new issue " .. slug)
		end
		-- f0010 base; f0020 needs it; f0040 needs its raft-mate f0030; f0050 needs a missing id; f0070 (second member) needs its raft-mate f0060 and then f0010
		edit("tracker/issues/f0020/f0020.md", "depends_on: %[%]", "depends_on: [f0010]")
		edit("tracker/issues/f0040/f0040.md", "depends_on: %[%]", "depends_on: [f0030]")
		edit("tracker/issues/f0050/f0050.md", "depends_on: %[%]", "depends_on: [f9999]")
		edit("tracker/issues/f0070/f0070.md", "depends_on: %[%]", "depends_on: [f0060, f0010]")
		must(tr({ "new", "raft", "feature", "base", "f0010" }), "raft base")
		must(tr({ "new", "raft", "feature", "needs-base", "f0020" }), "raft needs-base")
		must(tr({ "new", "raft", "feature", "pair", "f0030", "f0040" }), "raft pair")
		must(tr({ "new", "raft", "feature", "ghost", "f0050" }), "raft ghost")
		must(tr({ "new", "raft", "feature", "late", "f0060", "f0070" }), "raft late")
		for _, doc in
			{
				"tracker/issues/f0010/f0010.md",
				"tracker/issues/f0020/f0020.md",
				"tracker/issues/f0030/f0030.md",
				"tracker/issues/f0040/f0040.md",
				"tracker/issues/f0050/f0050.md",
				"tracker/issues/f0060/f0060.md",
				"tracker/issues/f0070/f0070.md",
				"tracker/rafts/R0010/R0010.md",
				"tracker/rafts/R0020/R0020.md",
				"tracker/rafts/R0030/R0030.md",
				"tracker/rafts/R0040/R0040.md",
				"tracker/rafts/R0050/R0050.md",
			}
		do
			edit(doc, "design: draft", "design: ready")
		end
		git({ "add", "-A" })
		git({ "commit", "-qm", "prep ready" })
		branch0 = git({ "branch", "--show-current" })
	end)

	it("refuses an issue that depends on an id that does not exist, naming both", function()
		local r = tr({ "start", "R0040" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "f0050")).toBe(true)
		t.expect(has(r.stderr, "f9999")).toBe(true)
		t.expect(has(r.stderr, "unknown")).toBe(true)
		t.expect(has(r.stderr, "origin/main")).toBe(true)
		t.expect(has(r.stderr, "never edit depends_on")).toBe(true)
	end)

	it("refuses an issue that depends on a backlog item outside the raft, naming both", function()
		local r = tr({ "start", "R0020" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "f0020")).toBe(true)
		t.expect(has(r.stderr, "f0010")).toBe(true)
		t.expect(has(r.stderr, "backlog")).toBe(true)
		t.expect(has(r.stderr, "origin/main")).toBe(true)
	end)

	it("checks every member and every dependency in its list", function()
		local r = tr({ "start", "R0050" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "f0070")).toBe(true)
		t.expect(has(r.stderr, "f0010")).toBe(true)
	end)

	it("a refusal changes nothing: same branch, raft still in the backlog, tree clean", function()
		t.expect(git({ "branch", "--show-current" })).toBe(branch0)
		t.expect(fs.isDir(`{dir}/tracker/rafts/R0020`)).toBe(true)
		t.expect(fs.isDir(`{dir}/tracker/rafts/active/R0020`)).toBe(false)
		t.expect(fs.isDir(`{dir}/tracker/issues/f0020`)).toBe(true)
		t.expect(git({ "status", "--porcelain" })).toBe("")
	end)

	it("still refuses while the dependency is only active, and says so", function()
		must(tr({ "start", "R0010" }), "start R0010")
		local r = tr({ "start", "R0020" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "f0010")).toBe(true)
		t.expect(has(r.stderr, "active")).toBe(true)
		t.expect(has(r.stderr, "origin/main")).toBe(true)
	end)

	it("starts the raft once the dependency is done", function()
		git({ "mv", "tracker/issues/active/f0010", "tracker/issues/done/f0010" })
		git({ "mv", "tracker/rafts/active/R0010", "tracker/rafts/done/R0010" })
		git({ "commit", "-qm", "R0010 done" })
		must(tr({ "start", "R0020" }), "start R0020")
		t.expect(fs.isDir(`{dir}/tracker/rafts/active/R0020`)).toBe(true)
		t.expect(fs.isDir(`{dir}/tracker/issues/active/f0020`)).toBe(true)
	end)

	it("a dependency on a raft-mate is fine", function()
		must(tr({ "start", "R0030" }), "start R0030")
		t.expect(fs.isDir(`{dir}/tracker/issues/active/f0040`)).toBe(true)
	end)

	it("the tracker skill's start row says start refuses unfinished dependencies", function()
		local row = ""
		for line in string.gmatch(fs.readFile(`{root}/.claude/skills/tracker/SKILL.md`), "[^\n]+") do
			if string.sub(line, 1, 10) == "| start | " then
				row = line
			end
		end
		t.expect(row ~= "").toBe(true)
		for _, token in { "depends_on", "done", "origin/main", "never edit", "stop" } do
			t.expect(has(row, token)).toBe(true)
		end
	end)
end)
