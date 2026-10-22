--!strict
-- c0740: `tracker.sh stop` gives back a readied (or started) raft: it moves the raft and its members back out of
-- active/ on origin/main with their check.sh paths rewritten back, removes prompt.md and leaves the branch and PR.
-- Fixture under .cache/c0740-stop: a seed with this tree's tooling and skills, a bare origin, a main clone (the main
-- checkout) and worktrees made by `tracker.sh worktree`. Cases share the fixture and run in order.
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
-- c0120 override: the fixture lives under the home's .cache (specs run from z-nile/, and the jail refuses the top's)
local here = trim(process.exec("pwd", { "-P" }).stdout)
local base = `{here}/.cache/c0740-stop`
local seed, origin, main = `{base}/seed`, `{base}/origin.git`, `{base}/main`
local bin = `{base}/bin`

local function env(extra: { [string]: string }?): { [string]: string }
	local out = {
		PATH = `{bin}:{process.env.PATH or ""}`,
	}
	if extra then
		for k, v in extra do
			out[k] = v
		end
	end
	return out
end
local function run(cwd: string, cmd: string, args: { string }, extra: { [string]: string }?): Result
	return fixture.exec(cwd, cmd, args, { env = env(extra) }) -- R0210: git and tracker.sh in a fixture only through the helper
end
local function git(cwd: string, args: { string }): string
	local r = run(cwd, "git", args)
	if not r.ok then
		error(`git {table.concat(args, " ")} failed: {r.stderr}{r.stdout}`, 2)
	end
	return trim(r.stdout)
end
local function tr(cwd: string, args: { string }, extra: { [string]: string }?): Result
	return run(cwd, "bash", { "scripts/tracker.sh", table.unpack(args) }, extra)
end
local function trOk(cwd: string, args: { string }): string
	local r = tr(cwd, args)
	if not r.ok then
		error(`tracker.sh {table.concat(args, " ")} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return trim(r.stdout)
end
local function has(text: string?, needle: string): boolean
	return text ~= nil and string.find(text, needle, 1, true) ~= nil
end
local function onOrigin(path: string): string?
	local r = run(origin, "git", { "show", `main:{path}` })
	return if r.ok then r.stdout else nil
end
local function tip(): string
	return git(origin, { "rev-parse", "main" })
end
local function write(dir: string, path: string, text: string, exec: boolean?)
	local full = `{dir}/{path}`
	fs.writeDir(string.match(full, "^(.*)/[^/]+$") :: string)
	fs.writeFile(full, text)
	if exec then
		process.exec("chmod", { "+x", full })
	end
end

local PREPARED = "prepared-quiet-copper-falcon"
local function issueDoc(
	id: string,
	title: string,
	raft: string,
	deps: string,
	design: string,
	status: string
): string
	return `---\nid: {id}\ntype: chore\ntitle: {title}\nslug: {string.lower(title)}\nraft: {raft}\ndepends_on: [{deps}]\nemergent: false\ndesign: {design}\ncreated: 2026-10-03\nstatus: {status}\n---\n\n# {id}: {title}\n\n## Problem\nMarker {title}.\n`
end
local function raftDoc(
	id: string,
	title: string,
	slug: string,
	issues: string,
	design: string,
	status: string
): string
	return `---\nid: {id}\ntype: chore\ntitle: {title}\nslug: {slug}\nsingle: false\nissues: [{issues}]\ndesign: {design}\ncreated: 2026-10-03\nstatus: {status}\n---\n\n# {id}: {title}\n\n## Theme\nMarker {title}.\n`
end
local HEAD =
	'#!/usr/bin/env bash\nsource "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
-- check.sh texts with literal backlog paths; {S} is the state segment ("" or "active/" or "done/")
local function c0010Check(s: string): string
	return HEAD
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		.. `check "AC1: spec" test -f pickman/.tracker/issues/{s}c0010/acceptance/a.spec.luau\n`
		.. `check "AC2: sibling" test -f pickman/.tracker/issues/{s}c0020/c0020.md\n`
		.. "# untouched: pickman/.tracker/issues/c0090/c0090.md pickman/.tracker/issues/c00100\nfinish\n"
end
local function r0010Check(s: string): string
	return HEAD
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		.. `check "RC1: member" bash pickman/.tracker/issues/{s}c0010/check.sh\n# raft: pickman/.tracker/rafts/{s}R0010\nfinish\n`
end
local function simpleCheck(id: string, kind: string, s: string): string
	-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
	return HEAD .. `check "AC1: ok" test -n "pickman/.tracker/{kind}/{s}{id}/check.sh"\nfinish\n`
end
local SPEC = "-- c0010 acceptance marker\nreturn nil\n"

local wt = "" -- R0010's worktree
local cap = "" -- a named worktree
local seeded: { [string]: string } = {} -- every R0010/c0010/c0020 file on origin before the first ready

local function snapshot(): { [string]: string }
	local out: { [string]: string } = {}
	-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
	for _, p in
		string.split(git(origin, { "ls-tree", "-r", "--name-only", "main", "pickman/.tracker/" }), "\n")
	do
		local plain = (string.gsub(p, "^pickman/%.tracker/(%a+)/active/", "pickman/.tracker/%1/"))
		if
			-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
			string.match(plain, "^pickman/%.tracker/rafts/R0010/")
			or string.match(plain, "^pickman/%.tracker/issues/c0010/")
			or string.match(plain, "^pickman/%.tracker/issues/c0020/")
		then
			out[p] = onOrigin(p) :: string
		end
	end
	return out
end
local function withoutStatus(text: string): string
	return (string.gsub(text, "\nstatus: [^\n]*", "\nstatus: X"))
end

return t.spec("tracker stop", function(it)
	it("sets up an origin with two prepared rafts and a main checkout", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(seed)
		fs.writeDir(bin)
		write(bin, "gh", "#!/bin/sh\necho gh is not available in this fixture >&2\nexit 1\n", true)
		write(bin, "pbcopy", "#!/bin/sh\ncat > /dev/null\n", true) -- never the real clipboard
		process.exec("git", { "init", "-q", "-b", "main", seed }) -- raw: init to a named path
		git(seed, { "config", "user.name", "t" })
		git(seed, { "config", "user.email", "t@example.invalid" })
		for _, p in { ".claude", ".luaurc", ".gitignore" } do
			process.exec("cp", { "-R", `{root}/{p}`, `{seed}/{p}` })
		end
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		fs.writeDir(`{seed}/pickman/.tracker`)
		engine.copy(root, seed) -- c0114 override: ./zn, scripts/ and z-nile/ (the engine, the gate, the templates)
		-- c0120 override: the repository's architecture document is pickman's, at pickman/.tracker/
		process.exec(
			"cp",
			{ `{root}/pickman/.tracker/architecture.md`, `{seed}/pickman/.tracker/architecture.md` }
		)
		for _, d in { "issues/active", "issues/done", "rafts/active", "rafts/done" } do
			-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
			write(seed, `pickman/.tracker/{d}/.gitkeep`, "")
		end
		write(
			seed,
			-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
			"pickman/.tracker/rafts/R0010/R0010.md",
			raftDoc("R0010", "Readied", "readied", "c0010, c0020", "ready", PREPARED)
		)
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		write(seed, "pickman/.tracker/rafts/R0010/check.sh", r0010Check(""), true)
		write(
			seed,
			-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
			"pickman/.tracker/issues/c0010/c0010.md",
			issueDoc("c0010", "Alpha", "R0010", "", "ready", PREPARED)
		)
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		write(seed, "pickman/.tracker/issues/c0010/check.sh", c0010Check(""), true)
		write(seed, "pickman/.tracker/issues/c0010/acceptance/a.spec.luau", SPEC)
		write(seed, "pickman/.tracker/issues/c0010/experiments/E1.sh", "#!/bin/sh\necho e1\n", true)
		write(
			seed,
			-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
			"pickman/.tracker/issues/c0020/c0020.md",
			issueDoc("c0020", "Beta", "R0010", "", "ready", PREPARED)
		)
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		write(seed, "pickman/.tracker/issues/c0020/check.sh", simpleCheck("c0020", "issues", ""), true)
		write(
			seed,
			-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
			"pickman/.tracker/rafts/R0030/R0030.md",
			raftDoc("R0030", "Legacy", "legacy", "c0030", "ready", PREPARED)
		)
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		write(seed, "pickman/.tracker/rafts/R0030/check.sh", simpleCheck("R0030", "rafts", ""), true)
		write(
			seed,
			-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
			"pickman/.tracker/issues/c0030/c0030.md",
			issueDoc("c0030", "Gamma", "R0030", "", "ready", PREPARED)
		)
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		write(seed, "pickman/.tracker/issues/c0030/check.sh", simpleCheck("c0030", "issues", ""), true)
		git(seed, { "add", "-A" })
		git(seed, { "commit", "-q", "-m", "seed" })
		process.exec("git", { "clone", "-q", "--bare", seed, origin }) -- raw: clone to a named path
		process.exec("git", { "clone", "-q", origin, main })
		git(main, { "config", "user.name", "t" })
		git(main, { "config", "user.email", "t@example.invalid" })
		cap = trOk(main, { "worktree", "cap-a" })
		seeded = snapshot()
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		t.expect(seeded["pickman/.tracker/issues/c0010/experiments/E1.sh"] ~= nil).toBe(true)
	end)

	it("stop refuses outside the main checkout and for a raft that is not readied", function()
		local before = tip()
		local notReadied = tr(main, { "stop", "R0010" })
		t.expect(notReadied.ok).toBe(false)
		t.expect(has(notReadied.stderr, "R0010")).toBe(true)
		trOk(main, { "ready", "R0010" })
		local readied = tip()
		t.expect(readied ~= before).toBe(true)
		local r = tr(cap, { "stop", "R0010" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "main checkout")).toBe(true)
		t.expect(tip()).toBe(readied)
	end)

	it(
		"stop moves a readied raft back out of active/ on origin/main in one commit, stamped prepared",
		function()
			local before = tip()
			trOk(main, { "stop", "R0010" })
			t.expect(git(origin, { "rev-list", "--count", `{before}..main` })).toBe("1")
			-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
			t.expect(git(origin, { "ls-tree", "main", "pickman/.tracker/rafts/active/R0010" })).toBe("")
			t.expect(git(origin, { "ls-tree", "main", "pickman/.tracker/issues/active/c0010" })).toBe("")
			for _, doc in
				{
					-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
					"pickman/.tracker/rafts/R0010/R0010.md",
					"pickman/.tracker/issues/c0010/c0010.md",
					"pickman/.tracker/issues/c0020/c0020.md",
				}
			do
				t.expect(string.match(onOrigin(doc) or "", "\nstatus: prepared%-%a+%-%a+%-%a+\n") ~= nil)
					.toBe(true)
			end
			t.expect(trOk(main, { "status", "R0010" })).toBe("prepared")
			t.expect(
				-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
				string.sub(
					git(origin, { "ls-tree", "main", "pickman/.tracker/issues/c0010/experiments/E1.sh" }),
					1,
					6
				)
			).toBe("100755")
		end
	)

	it("a ready and stop round trip restores every check.sh and file byte for byte", function()
		local now = snapshot()
		local n = 0
		for p, text in seeded do
			n += 1
			t.expect(now[p] ~= nil).toBe(true)
			if string.match(p, "%.md$") then
				t.expect(withoutStatus(now[p])).toBe(withoutStatus(text))
			else
				t.expect(now[p]).toBe(text)
			end
		end
		local m = 0
		for _ in now do
			m += 1
		end
		t.expect(m).toBe(n)
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		t.expect(now["pickman/.tracker/issues/c0010/check.sh"]).toBe(c0010Check(""))
		t.expect(now["pickman/.tracker/rafts/R0010/check.sh"]).toBe(r0010Check(""))
	end)

	it(
		"stop removes prompt.md and the empty active directory, and leaves the main checkout clean and current",
		function()
			-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
			t.expect(fs.isFile(`{main}/pickman/.tracker/rafts/active/R0010/prompt.md`)).toBe(false)
			t.expect(fs.isDir(`{main}/pickman/.tracker/rafts/active/R0010`)).toBe(false)
			t.expect(fs.isFile(`{main}/pickman/.tracker/rafts/active/.gitkeep`)).toBe(true)
			t.expect(git(main, { "rev-parse", "HEAD" })).toBe(tip())
			t.expect(git(main, { "status", "--porcelain" })).toBe("")
			-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
			t.expect(git(main, { "status", "--porcelain", "--ignored", "--", "pickman/.tracker" })).toBe("")
		end
	)

	it("stop of a started raft leaves its branch on origin and names it", function()
		trOk(main, { "ready", "R0010" })
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		t.expect(fs.isFile(`{main}/pickman/.tracker/rafts/active/R0010/prompt.md`)).toBe(true)
		wt = trOk(main, { "worktree", "R0010" })
		trOk(wt, { "start", "R0010" })
		local head = git(wt, { "rev-parse", "HEAD" })
		local out = trOk(main, { "stop", "R0010" })
		t.expect(has(out, "R0010-readied")).toBe(true)
		t.expect(git(origin, { "rev-parse", "R0010-readied" })).toBe(head)
		t.expect(trOk(main, { "status", "R0010" })).toBe("prepared")
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		t.expect(fs.isDir(`{main}/pickman/.tracker/rafts/active/R0010`)).toBe(false)
	end)

	it("a stopped raft can be readied again", function()
		trOk(main, { "ready", "R0010" })
		t.expect(trOk(main, { "status", "R0010" })).toBe("active")
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		t.expect(fs.isFile(`{main}/pickman/.tracker/rafts/active/R0010/prompt.md`)).toBe(true)
		t.expect(onOrigin("pickman/.tracker/issues/active/c0010/check.sh")).toBe(c0010Check("active/"))
	end)

	it("status refuses to move a readied item and names stop", function()
		local before = tip()
		trOk(cap, { "sync" })
		for _, id in { "R0010", "c0020" } do
			for _, to in { "prepared", "preparing", "new" } do
				local r = tr(cap, { "status", id, to })
				t.expect(r.ok).toBe(false)
				t.expect(has(r.stderr, "stop")).toBe(true)
			end
		end
		t.expect(tip()).toBe(before)
	end)

	it("stop refuses a raft with a member already in done/", function()
		-- a broken state, made by hand: c0020 finished while its raft is still readied
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		git(main, { "mv", "pickman/.tracker/issues/active/c0020", "pickman/.tracker/issues/done/c0020" })
		git(main, { "commit", "-q", "-m", "c0020 done by hand" })
		git(main, { "push", "-q", "origin", "HEAD:main" })
		local before = tip()
		local r = tr(main, { "stop", "R0010" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "c0020")).toBe(true)
		t.expect(tip()).toBe(before)
		git(main, { "revert", "--no-edit", "HEAD" })
		git(main, { "push", "-q", "origin", "HEAD:main" })
	end)

	it("stop gives back a raft claimed by the legacy start, without moving it", function()
		local legacy = trOk(main, { "worktree", "R0030" })
		trOk(legacy, { "start", "R0030" }) -- a backlog raft: claimed on origin/main, moved on its branch only
		t.expect(trOk(main, { "status", "R0030" })).toBe("active")
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		t.expect(onOrigin("pickman/.tracker/rafts/R0030/R0030.md") ~= nil).toBe(true)
		local before = tip()
		trOk(main, { "stop", "R0030" })
		t.expect(git(origin, { "rev-list", "--count", `{before}..main` })).toBe("1")
		t.expect(trOk(main, { "status", "R0030" })).toBe("prepared")
		t.expect(trOk(main, { "status", "c0030" })).toBe("prepared")
		t
			.expect(git(origin, { "diff", "--name-only", before, "main" }))
			-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
			.toBe("pickman/.tracker/issues/c0030/c0030.md\npickman/.tracker/rafts/R0030/R0030.md")
	end)
end)
