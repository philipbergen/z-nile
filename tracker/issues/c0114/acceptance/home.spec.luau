--!strict

local fs = require("@lune/fs")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local TOML = 'id = ["pickman", "z-nile"]\n'

local function idOf(out: string): string
	return string.match(out, "([fcdR]%d%d%d%d)") :: string
end

return t.spec("project tabs", function(it)
	it("tab order", function()
		local text = fs.readFile("z-nile/projects.toml")
		local pick = string.find(text, "pickman", 1, true)
		local nile = string.find(text, "z-nile", 1, true)
		t.expect(pick ~= nil and nile ~= nil and (pick :: number) < (nile :: number)).toBe(true)
	end)

	it("project field", function()
		local f = trackerfix.new("c0114-field", { ["z-nile/projects.toml"] = TOML })
		local wt = trackerfix.trOk(f, f.main, { "worktree", "cap-field" })
		local out = trackerfix.trOk(
			f,
			wt,
			{ "new", "issue", "c", "tooling-home", "--desc", "Tooling.", "--project", "z-nile" }
		)
		local id = idOf(out)
		local path = `tracker/issues/{id}/{id}.md`
		local doc = require("@tests/lib/fixture").git(wt, { "show", `origin/main:{path}` })
		t.expect(string.find(doc, "project: z-nile", 1, true) ~= nil).toBe(true)
		t.expect(string.find(doc, "z-nile/tracker/", 1, true) ~= nil).toBe(false)
		local tree = require("@tests/lib/fixture").git(wt, { "ls-tree", "-r", "--name-only", "origin/main" })
		t.expect(string.find(tree, "z-nile/tracker/", 1, true) ~= nil).toBe(false)
	end)

	it("default project", function()
		local f = trackerfix.new("c0114-default")
		local wt = trackerfix.trOk(f, f.main, { "worktree", "cap-default" })
		local out = trackerfix.trOk(f, wt, { "new", "issue", "c", "plain", "--desc", "Plain." })
		local id = idOf(out)
		local doc =
			require("@tests/lib/fixture").git(wt, { "show", `origin/main:tracker/issues/{id}/{id}.md` })
		t.expect(string.find(doc, "project: pickman", 1, true) ~= nil).toBe(true)
	end)

	it("read rules", function()
		local projects = require("@scripts/tracker/projects")
		local dir = ".cache/c0114-read"
		if fs.isDir(dir) then
			fs.removeDir(dir)
		end
		fs.writeDir(dir)
		local ids = projects.read(dir)
		t.expect(ids[1]).toBe("pickman")
		t.expect(ids[2]).toBe(nil)
		fs.writeDir(dir .. "/z-nile")
		fs.writeFile(dir .. "/z-nile/projects.toml", 'id = ["a", "a"]\n')
		t.expect(pcall(projects.read, dir)).toBe(false)
		fs.writeFile(dir .. "/z-nile/projects.toml", "id = []\n")
		t.expect(pcall(projects.read, dir)).toBe(false)
	end)

	it("list filter", function()
		local member = function(id: string, project: string, raft: string): string
			return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {id}\nraft: {raft}\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-01-01\nstatus: prepared-quiet-copper-falcon\nproject: {project}\n---\n\n# {id}\n`
		end
		local raft = function(id: string, issue: string): string
			return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {id}\nsingle: false\nissues: [{issue}]\ndesign: ready\ncreated: 2026-01-01\nstatus: prepared-quiet-copper-falcon\n---\n\n# {id}\n`
		end
		local f = trackerfix.new("c0114-list", {
			["z-nile/projects.toml"] = TOML,
			["tracker/next"] = "issue 3 seed-phrase\nraft 3 seed-phrase\n",
			["tracker/issues/c0001/c0001.md"] = member("c0001", "z-nile", "R0001"),
			["tracker/issues/c0001/check.sh"] = 'check "AC1: ok" true\n',
			["tracker/rafts/R0001/R0001.md"] = raft("R0001", "c0001"),
			["tracker/rafts/R0001/check.sh"] = 'check "AC1: ok" true\n',
			["tracker/issues/c0002/c0002.md"] = member("c0002", "pickman", "R0002"),
			["tracker/issues/c0002/check.sh"] = 'check "AC1: ok" true\n',
			["tracker/rafts/R0002/R0002.md"] = raft("R0002", "c0002"),
			["tracker/rafts/R0002/check.sh"] = 'check "AC1: ok" true\n',
		})
		local wt = trackerfix.trOk(f, f.main, { "worktree", "cap-list" })
		local zn = idOf(
			trackerfix.trOk(
				f,
				wt,
				{ "new", "issue", "c", "tool-tab", "--desc", "Tool.", "--project", "z-nile" }
			)
		)
		local pk = idOf(trackerfix.trOk(f, wt, { "new", "issue", "c", "game-tab", "--desc", "Game." }))
		local listed = trackerfix.trOk(f, wt, { "list", "--project", "z-nile" })
		t.expect(string.find(listed, zn, 1, true) ~= nil).toBe(true)
		t.expect(string.find(listed, pk, 1, true) ~= nil).toBe(false)
		local function starts(id: string): boolean
			for line in string.gmatch(listed .. "\n", "([^\n]*)\n") do
				if string.match(line, `^{id}%s`) then
					return true
				end
			end
			return false
		end
		t.expect(starts("R0001")).toBe(true)
		t.expect(starts("R0002")).toBe(false)
	end)

	it("unknown project", function()
		local f = trackerfix.new("c0114-unknown", { ["z-nile/projects.toml"] = TOML })
		local wt = trackerfix.trOk(f, f.main, { "worktree", "cap-unknown" })
		local tip = require("@tests/lib/fixture").git(f.origin, { "rev-parse", "main" })
		local r =
			trackerfix.tr(f, wt, { "new", "issue", "c", "typo", "--desc", "Typo.", "--project", "z-nil" })
		t.expect(r.ok).toBe(false)
		local said = r.stdout .. r.stderr
		t.expect(string.find(said, "pickman", 1, true) ~= nil).toBe(true)
		t.expect(string.find(said, "z-nile", 1, true) ~= nil).toBe(true)
		t.expect(require("@tests/lib/fixture").git(f.origin, { "rev-parse", "main" })).toBe(tip)
		local listed = trackerfix.tr(f, wt, { "list", "--project", "nope" })
		t.expect(listed.ok).toBe(false)
	end)

	it("emergent project", function()
		local member = table.concat({
			"---",
			"id: c0001",
			"type: chore",
			"title: tool",
			"slug: tool",
			"raft: R0001",
			"depends_on: []",
			"emergent: false",
			"design: ready",
			"created: 2026-01-01",
			"status: active-quiet-copper-falcon",
			"project: z-nile",
			"---",
			"",
			"# c0001",
			"",
		}, "\n")
		local raft = table.concat({
			"---",
			"id: R0001",
			"type: chore",
			"title: tool",
			"slug: tool",
			"single: false",
			"issues: [c0001]",
			"design: ready",
			"created: 2026-01-01",
			"status: active-quiet-copper-falcon",
			"---",
			"",
			"# R0001",
			"",
		}, "\n")
		local f = trackerfix.new("c0114-emergent", {
			["z-nile/projects.toml"] = TOML,
			["tracker/next"] = "issue 2 seed-phrase\nraft 2 seed-phrase\n",
			["tracker/issues/active/c0001/c0001.md"] = member,
			["tracker/issues/active/c0001/check.sh"] = 'check "AC1: ok" true\n',
			["tracker/rafts/active/R0001/R0001.md"] = raft,
			["tracker/rafts/active/R0001/check.sh"] = 'check "AC1: ok" true\n',
		})
		local wt = trackerfix.trOk(f, f.main, { "worktree", "R0001" })
		local tip = require("@tests/lib/fixture").git(f.origin, { "rev-parse", "main" })
		local refused = trackerfix.tr(f, wt, {
			"new",
			"issue",
			"c",
			"other-tab",
			"--desc",
			"Other.",
			"--raft",
			"R0001",
			"--project",
			"pickman",
		})
		t.expect(refused.ok).toBe(false)
		t.expect(require("@tests/lib/fixture").git(f.origin, { "rev-parse", "main" })).toBe(tip)
		local made = trackerfix.trOk(f, wt, {
			"new",
			"issue",
			"c",
			"same-tab",
			"--desc",
			"Same.",
			"--raft",
			"R0001",
		})
		local id = idOf(made)
		local doc = fs.readFile(`{wt}/tracker/issues/active/{id}/{id}.md`)
		t.expect(string.find(doc, "project: z-nile", 1, true) ~= nil).toBe(true)
	end)
end)
