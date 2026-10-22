--!strict
-- c0880: `tracker.sh audit`, `list` on a tree with a duplicate id, and `renumber <item directory>` to separate the
-- copies. A fixture repository without an origin under .cache/c0880-cli.
local engine = require("@tests/lib/engine")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end
local root = trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)
-- c0120 override: fixtures live under the spec's home's .cache (the jail refuses the checkout top's)
local here = trim(process.exec("pwd", { "-P" }).stdout)
local base = `{here}/.cache/c0880-cli`
local repo = `{base}/repo`

local function git(args: { string }): string
	return fixture.git(repo, args)
end
local function tr(args: { string }): Result
	return fixture.exec(repo, "bash", { "scripts/tracker.sh", table.unpack(args) })
end
local function has(text: string?, needle: string): boolean
	return text ~= nil and string.find(text, needle, 1, true) ~= nil
end
-- the number of output lines that list `id` (its first column)
local function rows(text: string, id: string): number
	local n = 0
	for line in string.gmatch(text, "[^\n]+") do
		if string.match(line, "^(%S+)") == id then
			n += 1
		end
	end
	return n
end
local function write(path: string, text: string)
	fs.writeDir(string.match(path, "^(.*)/[^/]+$") :: string)
	fs.writeFile(path, text)
end
local function doc(id: string, body: string): string
	return `---\nid: {id}\ntype: chore\ntitle: T {id}\nslug: s\nraft: \ndepends_on: []\ndesign: draft\n---\n\n# {id}: T\n\n{body}\n`
end
local C10 = doc("c0010", "The one in the backlog.")
local DONE10 = doc("c0010", "The emergent one that was filed in done.")
local C20 = doc("c0020", "Waits for c0010.")

return t.spec("c0880 audit, list and renumber by directory", function(it)
	it("sets up a tracker repository", function()
		-- c0120 override: pickman's items live in pickman/.tracker (engine.REGISTRY's layout)
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(repo)
		process.exec("git", { "init", "-q", "-b", "main", repo }) -- raw: init to a named path
		git({ "config", "user.name", "cli" })
		git({ "config", "user.email", "cli@example.invalid" })
		for _, p in { ".luaurc" } do
			process.exec("cp", { "-R", `{root}/{p}`, `{repo}/{p}` })
		end
		fs.writeDir(`{repo}/tracker`)
		engine.copy(root, repo) -- c0114 override: ./zn, scripts/ and z-nile/ (the engine, the gate, the templates)
		write(`{repo}/z-nile/next`, "issue 21 a-b-c\nraft 11 a-b-c\n")
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		write(`{repo}/pickman/.tracker/issues/c0010/c0010.md`, C10)
		write(`{repo}/pickman/.tracker/issues/c0020/c0020.md`, C20)
		write(
			-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
			`{repo}/pickman/.tracker/rafts/R0010/R0010.md`,
			"---\nid: R0010\ntype: chore\ntitle: Raft\nslug: raft\nissues: []\ndesign: draft\n---\n\n# R0010\n"
		)
		git({ "add", "-A" })
		git({ "commit", "-q", "-m", "seed" })
		-- origin/main without a remote: renumber reads its ids, and nothing is published
		git({ "update-ref", "refs/remotes/origin/main", "HEAD" })
	end)

	it("audit passes a sound tree and says so", function()
		local r = tr({ "audit" })
		t.expect(r.ok).toBe(true)
		t.expect(has(r.stdout, "0 errors")).toBe(true)
	end)

	it("audit fails on a duplicate and names every copy", function()
		-- c0120 override: pickman's items live in pickman/.tracker (engine.REGISTRY's layout)
		write(`{repo}/pickman/.tracker/issues/done/c0010/c0010.md`, DONE10)
		write(`{repo}/pickman/.tracker/issues/c0030/check.sh`, "#!/usr/bin/env bash\n") -- and a folder with no document
		local r = tr({ "audit" })
		t.expect(r.ok).toBe(false)
		t.expect(r.code).toBe(1)
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		t.expect(has(r.stdout, "error duplicate pickman/.tracker/issues/c0010")).toBe(true)
		t.expect(has(r.stdout, "error duplicate pickman/.tracker/issues/done/c0010")).toBe(true)
		t.expect(has(r.stdout, "error no-document pickman/.tracker/issues/c0030")).toBe(true)
		t.expect(has(r.stdout, "3 errors")).toBe(true)
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		fs.removeDir(`{repo}/pickman/.tracker/issues/c0030`)
	end)

	it("list prints every item it can, both copies included, then fails naming the duplicate", function()
		-- c0120 override: pickman's items live in pickman/.tracker (engine.REGISTRY's layout)
		local r = tr({ "list" })
		t.expect(r.ok).toBe(false)
		t.expect(r.code).toBe(1)
		t.expect(has(r.stdout, "R0010")).toBe(true)
		t.expect(has(r.stdout, "c0020")).toBe(true)
		t.expect(rows(r.stdout, "c0010")).toBe(2)
		t.expect(has(r.stderr, "duplicate")).toBe(true)
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		t.expect(has(r.stderr, "pickman/.tracker/issues/done/c0010")).toBe(true)
		-- a state filter still prints what it can
		local done = tr({ "list", "done" })
		t.expect(done.ok).toBe(false)
		t.expect(rows(done.stdout, "c0010")).toBe(1)
	end)

	it("renumber refuses a path that is not an item directory", function()
		-- c0120 override: pickman's items live in pickman/.tracker (engine.REGISTRY's layout)
		for _, bad in
			{
				"pickman/.tracker/issues",
				"pickman/.tracker/issues/done/c0099",
				"src/c0010",
				-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
				"pickman/.tracker/issues/done/c0010/c0010.md",
			}
		do
			local r = tr({ "renumber", bad })
			t.expect(r.ok).toBe(false)
		end
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		t.expect(fs.isDir(`{repo}/pickman/.tracker/issues/done/c0010`)).toBe(true)
	end)

	it("renumber refuses a done copy and names the other one: its specs are promoted under its id", function()
		-- c0120 override: pickman's items live in pickman/.tracker (engine.REGISTRY's layout)
		local r = tr({ "renumber", "pickman/.tracker/issues/done/c0010" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "pickman/.tracker/issues/c0010")).toBe(true)
		t.expect(fs.readFile(`{repo}/pickman/.tracker/issues/done/c0010/c0010.md`)).toBe(DONE10)
	end)

	it("renumber <directory> moves only that copy and rewrites ids only inside it", function()
		-- c0120 override: pickman's items live in pickman/.tracker (engine.REGISTRY's layout)
		local r = tr({ "renumber", "pickman/.tracker/issues/c0010" })
		if not r.ok then
			error(r.stderr .. r.stdout)
		end
		t.expect(has(r.stdout, "c0010 -> c0021")).toBe(true)
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		local moved = fs.readFile(`{repo}/pickman/.tracker/issues/c0021/c0021.md`)
		t.expect(has(moved, "id: c0021")).toBe(true)
		t.expect(has(moved, "# c0021: T")).toBe(true)
		t.expect(has(moved, "The one in the backlog.")).toBe(true)
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		t.expect(fs.isDir(`{repo}/pickman/.tracker/issues/c0010`)).toBe(false)
		-- the other copy, and every reference elsewhere, still mean the done c0010
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		t.expect(fs.readFile(`{repo}/pickman/.tracker/issues/done/c0010/c0010.md`)).toBe(DONE10)
		t.expect(fs.readFile(`{repo}/pickman/.tracker/issues/c0020/c0020.md`)).toBe(C20)
		t.expect(tr({ "list" }).ok).toBe(true)
		t.expect(tr({ "audit" }).ok).toBe(true)
	end)

	it("renumber <directory> <new> uses the number given", function()
		-- c0120 override: pickman's items live in pickman/.tracker (engine.REGISTRY's layout)
		local r = tr({ "renumber", "pickman/.tracker/issues/c0021", "c0500" })
		t.expect(r.ok).toBe(true)
		t.expect(fs.isFile(`{repo}/pickman/.tracker/issues/c0500/c0500.md`)).toBe(true)
		t.expect(tr({ "renumber", "pickman/.tracker/issues/c0500", "f0600" }).ok).toBe(false) -- prefix kept
		t.expect(tr({ "renumber", "pickman/.tracker/issues/c0500", "c0020" }).ok).toBe(false) -- taken
	end)

	it("the tracker skill documents audit and renumbering a duplicate's copy", function()
		local skill = fs.readFile(`{root}/.claude/skills/tracker/SKILL.md`)
		local other = string.match(skill, "## Other commands\n(.-)\n## ") :: string
		t.expect(has(other, "./zn audit")).toBe(true)
		local readOnly = string.match(skill, "the read%-only tracker commands ([^\n]+)") :: string
		t.expect(has(readOnly, "`audit`")).toBe(true)
		local dup = string.match(skill, "\n%- %*%*Duplicate ids%*%*([^\n]+)") :: string
		t.expect(dup ~= nil).toBe(true)
		t.expect(has(dup, "./zn audit")).toBe(true)
		t.expect(has(dup, "./zn renumber <directory>")).toBe(true)
		t.expect(has(dup, "not in `done/`")).toBe(true)
	end)

	it("cleans up", function()
		fs.removeDir(base)
	end)
end)
