--!strict
-- c0114 AC3: every command works across the project roots of z-nile/projects.toml, reading origin/main's registry
-- for what it publishes. Driven through ./zn in a tracker fixture under .cache/c0114-roots (tests/lib/trackerfix): a
-- bare origin, a main checkout and a second terminal that pushes straight to origin's main.
local claims = require("@znile/engine/claims")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local PREPARED = "prepared-quiet-copper-falcon"
local Z = "z-nile/.tracker"

local function doc(id: string, raft: string, design: string, status: string): string
	local extra = if string.sub(id, 1, 1) == "R" then "single: true\nissues: [c0030]\n" else `raft: {raft}\n`
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {id}\n{extra}depends_on: []\nemergent: false\ndesign: {design}\ncreated: 2026-10-20\nstatus: {status}\n---\n\n# {id}\n`
end

-- c0030's check.sh names its own folder: ready and stop must move that path with it, under z-nile's root
local OWN = `source "$(git -C "$(dirname "$\{BASH_SOURCE[0]\}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"\n`
	.. `check "AC1: own folder" test -d "{Z}/issues/c0030"\nfinish\n`
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'

local f: trackerfix.Fixture

local function onOrigin(path: string): boolean
	return fixture.exec(f.origin, "git", { "cat-file", "-e", `main:{path}` }).ok
end
local function originText(path: string): string
	return fixture.git(f.origin, { "show", `main:{path}` })
end
local function tip(): string
	return fixture.git(f.origin, { "rev-parse", "main" })
end
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
-- a command in a worktree of the main checkout (new, status and friends refuse the main checkout itself)
local wt = ""
local function zn(args: { string }): fixture.Result
	return trackerfix.tr(f, wt, args)
end
local function refused(args: { string }, needle: string)
	local before = tip()
	local r = zn(args)
	t.expect(r.ok).toBe(false)
	if not has(r.stderr, needle) then
		error(`{table.concat(args, " ")}: stderr lacks "{needle}": {r.stderr}`)
	end
	t.expect(tip()).toBe(before)
end

return t.spec("c0114 commands across project roots", function(it)
	it("sets up items in both roots and a shared counter", function()
		local seed: { [string]: string } = {
			[".gitignore"] = fs.readFile(".gitignore"), -- ignores every root's prompt.md
			["tracker/architecture.md"] = fs.readFile("tracker/architecture.md"),
			["z-nile/next"] = "issue 41 a-b-c\nraft 11 a-b-c\n",
			["tracker/issues/f0010/f0010.md"] = doc("f0010", "", "draft", "new-a-b-c"),
			[`{Z}/issues/c0020/c0020.md`] = doc("c0020", "", "draft", "new-a-b-c"),
			[`{Z}/issues/c0021/c0021.md`] = doc("c0021", "", "draft", "new-a-b-c"),
			[`{Z}/issues/c0030/c0030.md`] = doc("c0030", "R0010", "ready", PREPARED),
			[`{Z}/issues/c0030/check.sh`] = OWN,
			[`{Z}/rafts/R0010/R0010.md`] = doc("R0010", "", "ready", PREPARED),
			[`{Z}/rafts/R0010/check.sh`] = CHECK,
		}
		for _, s in { "execute-raft", "tracker", "architecture", "testing", "review" } do
			seed[`.claude/skills/{s}/SKILL.md`] = fs.readFile(`.claude/skills/{s}/SKILL.md`)
		end
		f = trackerfix.new("c0114-roots", seed)
		wt = trackerfix.trOk(f, f.main, { "worktree", "work" })
	end)

	it("find, list, members and status see every root", function()
		t.expect(trackerfix.trOk(f, f.main, { "find", "c0020" })).toBe(`{Z}/issues/c0020`)
		t.expect(trackerfix.trOk(f, f.main, { "find", "f0010" })).toBe("tracker/issues/f0010")
		t.expect(trackerfix.trOk(f, f.main, { "members", "R0010" })).toBe(`{Z}/issues/c0030`)
		local listed = trackerfix.trOk(f, f.main, { "list" })
		for _, id in { "R0010", "f0010", "c0020", "c0030" } do
			t.expect(has(listed, id)).toBe(true)
		end
		local status = trackerfix.trOk(f, f.main, { "status" })
		t.expect(has(status, "c0020 new")).toBe(true)
		t.expect(has(status, "f0010 new")).toBe(true)
		t.expect(trackerfix.trOk(f, f.main, { "status", "c0030" })).toBe("prepared")
	end)

	it(
		"new issue files in the first project unless --project names another, from one shared counter",
		function()
			local a = trackerfix.trOk(f, wt, { "new", "issue", "f", "game-thing" })
			t.expect(a).toBe("tracker/issues/f0041/f0041.md")
			local b = trackerfix.trOk(f, wt, { "new", "issue", "c", "tool-thing", "--project", "z-nile" })
			t.expect(b).toBe(`{Z}/issues/c0042/c0042.md`)
			t.expect(onOrigin(`{Z}/issues/c0042/c0042.md`)).toBe(true)
			t.expect(onOrigin(`{Z}/issues/c0042/check.sh`)).toBe(true)
			local c = trackerfix.trOk(f, wt, { "new", "issue", "c", "game-chore" })
			t.expect(c).toBe("tracker/issues/c0043/c0043.md")
			-- one counter: three issues in two projects took 41, 42 and 43, and origin's counter says 44 next
			t.expect(string.match(originText("z-nile/next"), "^issue 44 %S+\nraft 11 %S+$") ~= nil).toBe(true)
			t.expect(onOrigin("tracker/next")).toBe(false) -- the fixture has no tombstone, and nothing writes one
			refused({ "new", "issue", "c", "nowhere", "--project", "nope" }, "--project nope: not a project")
		end
	)

	it("new raft lives in its members' project and never spans two", function()
		local r = trackerfix.trOk(f, wt, { "new", "raft", "chore", "tools", "c0020", "--single" })
		t.expect(r).toBe(`{Z}/rafts/R0011/R0011.md`)
		t.expect(onOrigin(`{Z}/rafts/R0011/R0011.md`)).toBe(true)
		t.expect(has(originText(`{Z}/issues/c0020/c0020.md`), "status: preparing-")).toBe(true)
		refused({ "new", "raft", "chore", "mixed", "c0021", "c0043" }, "a raft holds issues of one project")
		-- offline (PICKMAN_PUBLISH=0) the same rule holds, from the local items
		fixture.git(wt, { "fetch", "-q", "origin" })
		fixture.git(wt, { "merge", "-q", "origin/main" })
		local before = tip()
		local offline = trackerfix.tr(
			f,
			wt,
			{ "new", "raft", "chore", "mixed", "c0021", "c0043" },
			{ PICKMAN_PUBLISH = "0" }
		)
		t.expect(offline.ok).toBe(false)
		t.expect(has(offline.stderr, "a raft holds issues of one project")).toBe(true)
		t.expect(fs.isDir(`{wt}/tracker/rafts/R0012`) or fs.isDir(`{wt}/{Z}/rafts/R0012`)).toBe(false)
		t.expect(tip()).toBe(before)
	end)

	it("status moves an item in z-nile's root on origin/main", function()
		trackerfix.trOk(f, wt, { "status", "c0021", "preparing" })
		t.expect(has(originText(`{Z}/issues/c0021/c0021.md`), "status: preparing-")).toBe(true)
		trackerfix.trOk(f, wt, { "status", "c0021", "new" })
	end)

	it("a root that only the working tree's registry lists is never published to", function()
		fixture.git(wt, { "fetch", "-q", "origin" })
		fixture.git(wt, { "merge", "-q", "origin/main" })
		local reg = fs.readFile(`{wt}/z-nile/projects.toml`)
		fs.writeFile(
			`{wt}/z-nile/projects.toml`,
			reg .. '\n[[project]]\nname = "evil"\nroot = "evil/.tracker"\n'
		)
		fs.writeDir(`{wt}/evil/.tracker/issues/c0090`)
		fs.writeFile(`{wt}/evil/.tracker/issues/c0090/c0090.md`, doc("c0090", "", "draft", "new-a-b-c"))
		fixture.git(wt, { "add", "-A" })
		fixture.git(wt, { "commit", "-q", "-m", "a root of its own" })
		refused(
			{ "new", "issue", "c", "evil-thing", "--project", "evil" },
			"not a project root in origin/main"
		)
		refused({ "status", "c0090", "preparing" }, "c0090 is not on origin/main")
		t.expect(onOrigin("evil/.tracker/issues/c0090/c0090.md")).toBe(false)
		fixture.git(wt, { "reset", "-q", "--hard", "HEAD~1" })
	end)

	it(
		"one id in two roots is a duplicate: find refuses it, audit names both, renumber takes one copy",
		function()
			trackerfix.elsewhere(
				f,
				{ ["tracker/issues/c0021/c0021.md"] = doc("c0021", "", "draft", "new-d-e-f") },
				"copy"
			)
			fixture.git(f.main, { "pull", "-q", "origin", "main" })
			local found = trackerfix.tr(f, f.main, { "find", "c0021" })
			t.expect(found.ok).toBe(false)
			t.expect(has(found.stderr, "duplicate id c0021")).toBe(true)
			local audited = trackerfix.tr(f, f.main, { "audit" })
			t.expect(audited.ok).toBe(false)
			t.expect(has(audited.stdout, "error duplicate tracker/issues/c0021")).toBe(true)
			t.expect(has(audited.stdout, `error duplicate {Z}/issues/c0021`)).toBe(true)
			-- the copy under z-nile's root, named by its folder, takes the next number from the shared counter
			fixture.git(wt, { "fetch", "-q", "origin" })
			fixture.git(wt, { "merge", "-q", "origin/main" })
			local r = trackerfix.tr(f, wt, { "renumber", `{Z}/issues/c0021` })
			if not r.ok then
				error(r.stderr .. r.stdout)
			end
			t.expect(has(r.stdout, "c0021 -> c0044")).toBe(true)
			t.expect(fs.isFile(`{wt}/{Z}/issues/c0044/c0044.md`)).toBe(true)
			t.expect(trackerfix.trOk(f, wt, { "find", "c0021" })).toBe("tracker/issues/c0021")
			fixture.git(wt, { "reset", "-q", "--hard", "origin/main" })
			fixture.git(f.other, { "pull", "-q", "origin", "main" })
			fixture.git(f.other, { "rm", "-q", "-r", "tracker/issues/c0021" })
			fixture.git(f.other, { "commit", "-q", "-m", "drop the copy" })
			fixture.git(f.other, { "push", "-q", "origin", "HEAD:main" })
			fixture.git(f.main, { "pull", "-q", "origin", "main" })
			t.expect(trackerfix.trOk(f, f.main, { "find", "c0021" })).toBe(`{Z}/issues/c0021`)
		end
	)

	it("a capture of a z-nile draft issue lands without a pull request", function()
		local cap = trackerfix.trOk(f, f.main, { "worktree", "capture-z" })
		fixture.git(cap, { "config", "user.name", "c0114-roots" })
		fixture.git(cap, { "config", "user.email", "c0114-roots@example.invalid" })
		local path = `{Z}/issues/c0021/c0021.md`
		fs.writeFile(`{cap}/{path}`, fs.readFile(`{cap}/{path}`) .. "\nMore about it.\n")
		fixture.git(cap, { "add", "-A" })
		fixture.git(cap, { "commit", "-q", "-m", "tracker: new c0021 more" })
		local r = trackerfix.tr(f, cap, { "land" }, { PICKMAN_LAND_GATE = "true" })
		if not r.ok then
			error(r.stderr .. r.stdout)
		end
		t.expect(has(originText(path), "More about it.")).toBe(true)
	end)

	it("spend counts code lines, never the documents under any project root", function()
		fs.writeFile(`{wt}/{Z}/issues/c0021/notes.md`, "one\ntwo\n")
		fs.writeFile(`{wt}/tracker/issues/f0010/notes.md`, "one\n")
		fs.writeDir(`{wt}/src`)
		fs.writeFile(`{wt}/src/x.luau`, "--!strict\nreturn 1\n")
		fixture.git(wt, { "add", "-A" })
		local call = "req" .. "uire" -- keeps literal require text out of this file (graph scanner)
		fs.writeDir(`{wt}/.cache`)
		fs.writeFile(
			`{wt}/.cache/probe.luau`,
			`local spend = {call}("../z-nile/engine/spend")\nfor _, s in spend.stagedStats() do print(s.path) end\n`
		)
		local r = fixture.exec(wt, "lune", { "run", ".cache/probe" })
		if not r.ok then
			error(r.stderr)
		end
		t.expect(r.stdout).toBe("src/x.luau\n")
		fixture.git(wt, { "reset", "-q", "--hard", "HEAD" })
		fixture.git(wt, { "clean", "-qfd", "src" })
	end)

	it("ready moves a z-nile raft to its own active/, check.sh paths and the prompt included", function()
		fixture.git(f.main, { "pull", "-q", "origin", "main" })
		local before = originText(`{Z}/issues/c0030/check.sh`)
		local r = trackerfix.tr(f, f.main, { "ready", "R0010" })
		if not r.ok then
			error(r.stderr .. r.stdout)
		end
		t.expect(onOrigin(`{Z}/rafts/active/R0010/R0010.md`)).toBe(true)
		t.expect(onOrigin(`{Z}/issues/active/c0030/c0030.md`)).toBe(true)
		t.expect(onOrigin(`{Z}/rafts/R0010/R0010.md`)).toBe(false)
		-- the own path follows the move inside z-nile's root, never doubled (`z-nile/.z-nile/...`)
		local moved = originText(`{Z}/issues/active/c0030/check.sh`)
		t.expect(moved).toBe((string.gsub(before, "%.tracker/issues/c0030", ".tracker/issues/active/c0030")))
		t.expect(has(moved, "z-nile/.z-nile")).toBe(false)
		local prompt = `{f.main}/{Z}/rafts/active/R0010/prompt.md`
		t.expect(fs.isFile(prompt)).toBe(true)
		t.expect(fixture.exec(f.main, "git", { "check-ignore", "-q", `{Z}/rafts/active/R0010/prompt.md` }).ok)
			.toBe(true)
		t.expect(fixture.git(f.main, { "status", "--porcelain" })).toBe("")
		t.expect(
			has(
				trackerfix.trOk(f, f.main, { "prompt", "R0010", "--path" }),
				`{Z}/rafts/active/R0010/prompt.md`
			)
		)
			.toBe(true)
		-- the claim stamp is under z-nile's root on origin: a claim check that reads every root sees it
		local stamp =
			string.match(originText(`{Z}/rafts/active/R0010/R0010.md`), "\nstatus: (active%-[%a%-]+)\n")
		t.expect(stamp ~= nil).toBe(true)
		t.expect((claims.taken(f.main, stamp :: string, "origin/main", { "tracker", Z }))).toBe(true)
		t.expect((claims.taken(f.main, stamp :: string, "origin/main", { "tracker" }))).toBe(false)
		-- an emergent issue, made on the raft's branch in its worktree, is filed beside its raft in z-nile's root
		local rwt = trackerfix.trOk(f, f.main, { "worktree", "R0010" })
		trackerfix.trOk(f, rwt, { "start", "R0010" })
		local made = trackerfix.trOk(f, rwt, { "new", "issue", "c", "found-late", "--raft", "R0010" })
		local eid = string.match(made, "^z%-nile/%.tracker/issues/active/(c%d%d%d%d)/c%d%d%d%d%.md$")
		t.expect(eid ~= nil).toBe(true)
		t.expect(trackerfix.trOk(f, rwt, { "find", eid :: string })).toBe(`{Z}/issues/active/{eid}`)
		-- and naming another project for it is refused, with nothing reserved on origin
		local tipBefore = tip()
		local other = trackerfix.tr(
			f,
			rwt,
			{ "new", "issue", "c", "elsewhere", "--raft", "R0010", "--project", "pickman" }
		)
		t.expect(other.ok).toBe(false)
		t.expect(has(other.stderr, "an emergent issue is made in its raft's project")).toBe(true)
		t.expect(tip()).toBe(tipBefore)
		-- and stop moves both back, restores check.sh byte for byte, and removes the prompt
		local s = trackerfix.tr(f, f.main, { "stop", "R0010" })
		if not s.ok then
			error(s.stderr .. s.stdout)
		end
		t.expect(onOrigin(`{Z}/rafts/R0010/R0010.md`)).toBe(true)
		t.expect(originText(`{Z}/issues/c0030/check.sh`)).toBe(before)
		t.expect(fs.isFile(prompt)).toBe(false)
		t.expect(fs.isDir(`{f.main}/{Z}/rafts/active/R0010`)).toBe(false)
	end)

	it("a pull that moves a z-nile raft out of active/ sweeps the prompt it left behind", function()
		trackerfix.trOk(f, f.main, { "ready", "R0010" })
		local prompt = `{f.main}/{Z}/rafts/active/R0010/prompt.md`
		t.expect(fs.isFile(prompt)).toBe(true)
		-- another terminal gives it back by hand (a git move, as a merge from a branch would)
		fixture.git(f.other, { "pull", "-q", "origin", "main" })
		fixture.git(f.other, { "mv", `{Z}/rafts/active/R0010`, `{Z}/rafts/R0010` })
		fixture.git(f.other, { "mv", `{Z}/issues/active/c0030`, `{Z}/issues/c0030` })
		fixture.git(f.other, { "commit", "-q", "-m", "give it back" })
		fixture.git(f.other, { "push", "-q", "origin", "HEAD:main" })
		trackerfix.trOk(f, f.main, { "sync" })
		t.expect(fs.isFile(prompt)).toBe(false)
		t.expect(trackerfix.trOk(f, f.main, { "find", "R0010" })).toBe(`{Z}/rafts/R0010`)
	end)

	it("worktree-prune removes the worktree of a raft that is done in z-nile's root", function()
		local path = trackerfix.trOk(f, f.main, { "worktree", "R0011" })
		t.expect(fs.isDir(path)).toBe(true)
		fixture.git(f.other, { "pull", "-q", "origin", "main" })
		fixture.git(f.other, { "mv", `{Z}/rafts/R0011`, `{Z}/rafts/done/R0011` })
		fixture.git(f.other, { "commit", "-q", "-m", "R0011 done" })
		fixture.git(f.other, { "push", "-q", "origin", "HEAD:main" })
		local r = trackerfix.tr(f, f.main, { "worktree-prune" })
		if not r.ok then
			error(r.stderr .. r.stdout)
		end
		t.expect(has(r.stdout, `removed {path}`)).toBe(true)
		t.expect(fs.isDir(path)).toBe(false)
	end)
	it("audit reports a registry that does not parse, and a tracker/next that parses as a counter", function()
		local reg = fs.readFile(`{f.main}/z-nile/projects.toml`)
		fs.writeFile(`{f.main}/z-nile/projects.toml`, "[[project]\n")
		local bad = trackerfix.tr(f, f.main, { "audit" })
		fs.writeFile(`{f.main}/z-nile/projects.toml`, reg)
		t.expect(bad.ok).toBe(false)
		t.expect(has(bad.stdout, "error registry z-nile/projects.toml")).toBe(true)
		fs.writeFile(`{f.main}/tracker/next`, "issue 9 a-b-c\nraft 9 a-b-c\n")
		local old = trackerfix.tr(f, f.main, { "audit" })
		fs.removeFile(`{f.main}/tracker/next`)
		t.expect(old.ok).toBe(false)
		t.expect(has(old.stdout, "error old-counter tracker/next")).toBe(true)
		-- the tombstone itself is fine
		fs.writeFile(`{f.main}/tracker/next`, fs.readFile("tracker/next"))
		local tomb = trackerfix.tr(f, f.main, { "audit" })
		fs.removeFile(`{f.main}/tracker/next`)
		t.expect(has(tomb.stdout, "old-counter")).toBe(false)
	end)
end)
