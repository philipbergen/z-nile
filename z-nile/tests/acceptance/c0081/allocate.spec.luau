--!strict
-- c0870: ids come from z-nile/next on origin/main, counting by one. Every allocation pushes the raised counter
-- (with a fresh phrase) in the same commit as what it creates; a lost race is a rejected lease push, retried on the
-- new origin/main. Without z-nile/next the numbering is unchanged (next multiple of 10). Fixture under
-- .cache/c0870-allocate: a seed with this tree's tooling, a bare origin, a main clone and a second clone.
local engine = require("@tests/lib/engine")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local ids = require("@scripts/tracker/ids")
local process = require("@lune/process")
local publish = require("@scripts/tracker/publish")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end
local root = trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)
-- c0120 override: fixtures live under the spec's home's .cache (the jail refuses the checkout top's)
local here = trim(process.exec("pwd", { "-P" }).stdout)
local base = `{here}/.cache/c0870-allocate`
local seed, origin, main, other = `{base}/seed`, `{base}/origin.git`, `{base}/main`, `{base}/other`
local SEED_NEXT = "issue 891 seed-seed-seed\nraft 271 seed-seed-seed\n"

local function git(cwd: string, args: { string }): string
	return fixture.git(cwd, args)
end
local function tr(cwd: string, args: { string }, env: { [string]: string }?): Result
	return fixture.exec(cwd, "bash", { "scripts/tracker.sh", table.unpack(args) }, { env = env })
end
local function trOk(cwd: string, args: { string }, env: { [string]: string }?): string
	local r = tr(cwd, args, env)
	if not r.ok then
		error(`tracker.sh {table.concat(args, " ")} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return trim(r.stdout)
end
local function onOrigin(path: string): string?
	local r = fixture.exec(origin, "git", { "show", `main:{path}` })
	return if r.ok then r.stdout else nil
end
local function counters(): ids.Counters
	local c = ids.parse(onOrigin(ids.FILE) or "")
	if not c then
		error("origin's z-nile/next does not parse", 2)
	end
	return c
end
local function phraseOf(text: string): string
	return string.match(text, "^issue %d+ (%S+)\n") :: string
end
local function lastChanged(): { string } -- the files origin's last commit on main changed, sorted
	local out = string.split(git(origin, { "show", "--name-only", "--format=", "main" }), "\n")
	table.sort(out)
	return out
end
local function write(path: string, text: string, exec: boolean?)
	fs.writeDir(string.match(path, "^(.*)/[^/]+$") :: string)
	fs.writeFile(path, text)
	if exec then
		process.exec("chmod", { "+x", path })
	end
end
local function identity(dir: string)
	git(dir, { "config", "user.name", "alloc" })
	git(dir, { "config", "user.email", "alloc@example.invalid" })
end
local function stub(id: string, title: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {title}\nslug: {title}\nraft: \ndepends_on: []\nemergent: false\ndesign: draft\ncreated: 2026-01-01\nstatus: new\n---\n\n# {id}\n`
end
-- another terminal pushes straight to origin's main
local function elsewhere(files: { [string]: string | false }, message: string)
	git(other, { "pull", "-q", "origin", "main" })
	for path, text in files do
		if type(text) == "string" then
			write(`{other}/{path}`, text)
		else
			git(other, { "rm", "-q", path })
		end
	end
	git(other, { "add", "-A" })
	git(other, { "commit", "-q", "-m", message })
	git(other, { "push", "-q", "origin", "HEAD:main" })
end
local function worktree(name: string): string
	local wt = trOk(main, { "worktree", name })
	identity(wt)
	return wt
end
local function realGit(): string
	for _, dir in string.split(process.env.PATH or "", ":") do
		if dir ~= "" and fs.isFile(`{dir}/git`) then
			return `{dir}/git`
		end
	end
	error("no git on PATH")
end

local phrases: { string } = {}

return t.spec("c0870 allocation from z-nile/next", function(it)
	it("sets up a bare origin holding z-nile/next, a main checkout and a second clone", function()
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(seed)
		process.exec("git", { "init", "-q", "-b", "main", seed }) -- raw: init to a named path
		identity(seed)
		for _, p in { ".claude", ".luaurc", ".gitignore" } do
			process.exec("cp", { "-R", `{root}/{p}`, `{seed}/{p}` })
		end
		engine.copy(root, seed) -- c0114 override: ./zn, scripts/ and z-nile/ (the engine, the gate, the templates)
		engine.roots(seed) -- c0120 override: the fixture is on the final layout (engine.roots lays out every root)
		write(`{seed}/{ids.FILE}`, SEED_NEXT)
		write(`{seed}/pickman/.tracker/issues/c0890/c0890.md`, stub("c0890", "older"))
		write(
			`{seed}/pickman/.tracker/rafts/done/R0270/R0270.md`,
			"---\nid: R0270\ntype: chore\ntitle: Old\nslug: old\nissues: []\ndesign: ready\n---\n\n# R0270\n"
		)
		git(seed, { "add", "-A" })
		git(seed, { "commit", "-q", "-m", "seed" })
		process.exec("git", { "clone", "-q", "--bare", seed, origin }) -- raw: clone to a named path
		for _, c in { main, other } do
			process.exec("git", { "clone", "-q", origin, c }) -- raw: clone to a named path
			identity(c)
		end
		table.insert(phrases, phraseOf(SEED_NEXT))
		t.expect(counters().issue).toBe(891)
	end)

	it("new issue takes the counter and pushes it raised by one in the same commit", function()
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		local wt = worktree("cap-a")
		t.expect(trOk(wt, { "new", "issue", "c", "alpha", "--project", "pickman" }))
			.toBe("pickman/.tracker/issues/c0891/c0891.md")
		t.expect(lastChanged()).toEqual({
			"pickman/.tracker/issues/c0891/c0891.md",
			"pickman/.tracker/issues/c0891/check.sh",
			"z-nile/next",
		})
		local c = counters()
		t.expect(c.issue).toBe(892)
		t.expect(c.raft).toBe(271)
		local text = onOrigin(ids.FILE) :: string
		local phrase = phraseOf(text)
		t.expect(string.match(phrase, "^[a-z]+%-[a-z]+%-[a-z]+$") ~= nil).toBe(true)
		t.expect(string.find(text, `\nraft 271 {phrase}\n`, 1, true) ~= nil).toBe(true) -- one phrase, both lines
		t.expect(phrase ~= phraseOf(SEED_NEXT)).toBe(true)
		table.insert(phrases, phrase)
		-- the worktree is synced to what it published
		t.expect(fs.readFile(`{wt}/{ids.FILE}`)).toBe(text)
	end)

	it("the next issue is 892: counting by one, not the next multiple of 10", function()
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		local wt = worktree("cap-b")
		t.expect(trOk(wt, { "new", "issue", "f", "beta", "--project", "pickman" }))
			.toBe("pickman/.tracker/issues/f0892/f0892.md")
		t.expect(counters().issue).toBe(893)
		table.insert(phrases, phraseOf(onOrigin(ids.FILE) :: string))
	end)

	it("a counter behind the ids on origin is passed, never reused", function()
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		elsewhere(
			{ ["pickman/.tracker/issues/c0950/c0950.md"] = stub("c0950", "oldcode") },
			"an old tracker made c0950"
		)
		local wt = worktree("cap-c")
		t.expect(trOk(wt, { "new", "issue", "c", "gamma", "--project", "pickman" }))
			.toBe("pickman/.tracker/issues/c0951/c0951.md")
		t.expect(counters().issue).toBe(952)
		table.insert(phrases, phraseOf(onOrigin(ids.FILE) :: string))
		-- three writes by the tracker, not all one phrase: a fixed phrase would let two writes merge silently
		t.expect(phrases[2] == phrases[3] and phrases[3] == phrases[4]).toBe(false)
	end)

	it("a lost race keeps the other terminal's number and takes the next one", function()
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		local wt = worktree("cap-d")
		-- A git shim first on PATH: before the tracker's first push it lets another terminal take c0952 and raise the
		-- counter, so the lease push is rejected and the tracker must start over on the new origin/main. Reviewed
		-- exception to the fixture rule: the shim runs raw git only in `other`, a fixture clone under this spec's
		-- .cache directory.
		local real = realGit()
		local shim = `{base}/shim`
		local marker = `{base}/raced`
		write(
			`{shim}/git`,
			`#!/bin/bash\nif [ "$1" = push ] && [ ! -e "{marker}" ]; then\n  touch "{marker}"\n`
				.. `  [ -d "{other}/.git" ] || exit 1\n`
				.. `  ( cd "{other}" && "{real}" pull -q origin main && mkdir -p pickman/.tracker/issues/c0952 && `
				.. `printf -- '---\\nid: c0952\\ntype: chore\\ntitle: theirs\\nslug: theirs\\nraft: \\ndepends_on: []\\nstatus: new\\n---\\n' > pickman/.tracker/issues/c0952/c0952.md && `
				.. `printf 'issue 953 other-other-other\\nraft 271 other-other-other\\n' > z-nile/next && `
				.. `"{real}" add -A && "{real}" commit -qm theirs && "{real}" push -q origin HEAD:main ) || exit 1\nfi\n`
				.. `exec "{real}" "$@"\n`,
			true
		)
		local out = trOk(
			wt,
			{ "new", "issue", "c", "delta", "--project", "pickman" },
			{ PATH = `{shim}:{process.env.PATH or ""}` }
		)
		t.expect(fs.isFile(marker)).toBe(true)
		t.expect(out).toBe("pickman/.tracker/issues/c0953/c0953.md")
		t.expect(
			string.find(onOrigin("pickman/.tracker/issues/c0952/c0952.md") or "", "title: theirs", 1, true)
				~= nil
		).toBe(true)
		t.expect(counters().issue).toBe(954)
		t.expect(git(origin, { "log", "-1", "--format=%s", "main^" })).toBe("theirs")
	end)

	it("new raft takes the raft counter and leaves the issue counter alone", function()
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		local wt = worktree("cap-e")
		t.expect(trOk(wt, { "new", "raft", "chore", "solo", "c0891", "--single", "--project", "pickman" }))
			.toBe("pickman/.tracker/rafts/R0271/R0271.md")
		local c = counters()
		t.expect(c.raft).toBe(272)
		t.expect(c.issue).toBe(954)
		t.expect(table.find(lastChanged(), "z-nile/next") ~= nil).toBe(true)
	end)

	it("an emergent issue reserves its number on origin and is created only locally", function()
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		local wt = worktree("cap-f")
		write(
			`{wt}/pickman/.tracker/rafts/active/R0900/R0900.md`,
			"---\nid: R0900\ntype: chore\ntitle: Busy\nslug: busy\nissues: []\ndesign: ready\n---\n\n# R0900\n"
		)
		git(wt, { "add", "-A" })
		git(wt, { "commit", "-q", "-m", "a raft in progress" })
		git(wt, { "branch", "-m", "R0900-busy" })
		local before = git(origin, { "rev-parse", "main" })
		local localNext = fs.readFile(`{wt}/{ids.FILE}`)
		t.expect(trOk(wt, { "new", "issue", "c", "eps", "--raft", "R0900" }))
			.toBe("pickman/.tracker/issues/active/c0954/c0954.md")
		t.expect(git(origin, { "rev-parse", "main^" })).toBe(before) -- exactly one commit
		t.expect(lastChanged()).toEqual({ "z-nile/next" })
		t.expect(counters().issue).toBe(955)
		t.expect(onOrigin("pickman/.tracker/issues/c0954/c0954.md")).toBe(nil)
		t.expect(onOrigin("pickman/.tracker/issues/active/c0954/c0954.md")).toBe(nil)
		-- the local counter is not raised (it moves only on origin/main), so it now lags: a warning, never an error
		t.expect(fs.readFile(`{wt}/{ids.FILE}`)).toBe(localNext)
		local audited = tr(wt, { "audit" })
		t.expect(audited.ok).toBe(true)
		t.expect(string.find(audited.stdout, "warning next-behind z-nile/next", 1, true) ~= nil).toBe(true)
	end)

	it("renumber takes its number from the counter and reserves it on origin", function()
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		local wt = worktree("cap-g")
		t.expect(trOk(wt, { "new", "issue", "c", "zeta", "--project", "pickman" }))
			.toBe("pickman/.tracker/issues/c0955/c0955.md")
		local r = trOk(wt, { "renumber", "c0955" })
		t.expect(string.find(r, "c0955 -> c0956", 1, true) ~= nil).toBe(true)
		t.expect(fs.isFile(`{wt}/pickman/.tracker/issues/c0956/c0956.md`)).toBe(true)
		t.expect(fs.isDir(`{wt}/pickman/.tracker/issues/c0955`)).toBe(false)
		t.expect(counters().issue).toBe(957)
		t.expect(lastChanged()).toEqual({ "z-nile/next" })
	end)

	it("PICKMAN_PUBLISH=0 numbers from the local counter and ids, and writes no counter", function()
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		local wt = worktree("cap-h")
		local localNext = fs.readFile(`{wt}/{ids.FILE}`)
		t.expect((ids.parse(localNext) :: ids.Counters).issue).toBe(957)
		local before = git(origin, { "rev-parse", "main" })
		local out = trOk(
			wt,
			{ "new", "issue", "c", "eta", "--project", "pickman" },
			{ PICKMAN_PUBLISH = "0" }
		)
		t.expect(out).toBe("pickman/.tracker/issues/c0957/c0957.md")
		t.expect(fs.readFile(`{wt}/{ids.FILE}`)).toBe(localNext)
		t.expect(git(origin, { "rev-parse", "main" })).toBe(before)
		-- a local counter behind the local ids is passed too
		write(`{wt}/pickman/.tracker/issues/c0970/c0970.md`, stub("c0970", "local"))
		t.expect(
			trOk(wt, { "new", "issue", "c", "theta", "--project", "pickman" }, { PICKMAN_PUBLISH = "0" })
		)
			.toBe("pickman/.tracker/issues/c0971/c0971.md")
	end)

	it("a published counter may only go up, and must parse", function()
		local now = counters()
		local function push(content: string): publish.Result
			return publish.commit(main, function()
				return { { path = ids.FILE, content = content } }
			end, "tracker: counter")
		end
		local before = git(origin, { "rev-parse", "main" })
		local down = push(ids.format({ issue = now.issue - 1, raft = now.raft }, "down-down-down"))
		t.expect(down.ok).toBe(false)
		t.expect(string.find(down.reason or "", "z-nile/next", 1, true) ~= nil).toBe(true)
		local rafts = push(ids.format({ issue = now.issue, raft = now.raft - 1 }, "down-down-down"))
		t.expect(rafts.ok).toBe(false)
		local bad = push("issue 99999 x\n")
		t.expect(bad.ok).toBe(false)
		t.expect(git(origin, { "rev-parse", "main" })).toBe(before)
		local up = push(ids.format({ issue = now.issue + 5, raft = now.raft }, "up-up-up"))
		t.expect(up.ok).toBe(true)
		t.expect(counters().issue).toBe(now.issue + 5)
	end)

	it(
		"without z-nile/next on origin, numbering is the next multiple of 10 and no counter appears",
		function()
			-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
			elsewhere({ [ids.FILE] = false }, "no counter")
			local highest = 0
			for _, p in
				string.split(
					git(origin, { "ls-tree", "-r", "--name-only", "main", "pickman/.tracker/issues" }),
					"\n"
				)
			do
				local n = string.match(p, "/[fdc](%d%d%d%d)/[^/]+$")
				if n then
					highest = math.max(highest, tonumber(n) :: number)
				end
			end
			local want = (math.floor(highest / 10) + 1) * 10
			local wt = worktree("cap-i")
			t.expect(trOk(wt, { "new", "issue", "c", "iota", "--project", "pickman" }))
				.toBe(string.format("pickman/.tracker/issues/c%04d/c%04d.md", want, want))
			t.expect(onOrigin(ids.FILE)).toBe(nil)
			t.expect(fs.isFile(`{wt}/{ids.FILE}`)).toBe(false)
		end
	)

	it("cleans up", function()
		fs.removeDir(base)
	end)
end)
