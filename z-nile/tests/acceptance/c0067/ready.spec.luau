--!strict
-- c0730: `tracker.sh ready` claims a prepared raft, moves it and its members to active/ on origin/main with their
-- check.sh paths rewritten, pulls the main checkout and writes the ignored prompt.md; `start` then only branches.
-- Fixture under .cache/c0730-ready: a seed with this tree's tooling and skills, a bare origin, a main clone (the main
-- checkout) and worktrees made by `tracker.sh worktree`. A recording pbcopy is first on PATH. Cases run in order.
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
-- c0120 override: fixtures live under the home's .cache (z-nile/.cache); root stays the checkout to copy from
local base = `{fixture.physical(".") or "."}/.cache/c0730-ready`
local seed, origin, main = `{base}/seed`, `{base}/origin.git`, `{base}/main`
local bin, clipLog = `{base}/bin`, `{base}/pbcopy.log`

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
local early = "" -- R0060's worktree, made before R0060 is readied
local readiedStamp = ""

return t.spec("tracker ready", function(it)
	it("sets up an origin with prepared, draft and blocked rafts, and a main checkout", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(seed)
		fs.writeDir(bin)
		write(bin, "pbcopy", `#!/bin/sh\ncat >> "{clipLog}"\n`, true)
		write(bin, "gh", "#!/bin/sh\necho gh is not available in this fixture >&2\nexit 1\n", true)
		process.exec("git", { "init", "-q", "-b", "main", seed }) -- raw: init to a named path
		git(seed, { "config", "user.name", "t" })
		git(seed, { "config", "user.email", "t@example.invalid" })
		for _, p in { ".claude", ".luaurc", ".gitignore" } do
			process.exec("cp", { "-R", `{root}/{p}`, `{seed}/{p}` })
		end
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		fs.writeDir(`{seed}/pickman/.tracker`)
		engine.copy(root, seed) -- c0114 override: ./zn, scripts/ and z-nile/ (the engine, the gate, the templates)
		-- c0120 override: the checkout keeps pickman's architecture.md in pickman/.tracker, the fixtures' pickman root too
		process.exec(
			"cp",
			{ `{root}/pickman/.tracker/architecture.md`, `{seed}/pickman/.tracker/architecture.md` }
		)
		for _, d in { "issues/active", "issues/done", "rafts/active", "rafts/done" } do
			-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
			write(seed, `pickman/.tracker/{d}/.gitkeep`, "")
		end
		-- R0010: prepared, members c0010 (acceptance spec, executable experiment) and c0020
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
		-- R0020: still being prepared
		write(
			seed,
			-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
			"pickman/.tracker/rafts/R0020/R0020.md",
			raftDoc("R0020", "Draft", "draft", "c0050", "draft", "preparing-a-b-c")
		)
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		write(seed, "pickman/.tracker/rafts/R0020/check.sh", simpleCheck("R0020", "rafts", ""), true)
		write(
			seed,
			-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
			"pickman/.tracker/issues/c0050/c0050.md",
			issueDoc("c0050", "Drafty", "R0020", "", "draft", "preparing-a-b-c")
		)
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		write(seed, "pickman/.tracker/issues/c0050/check.sh", simpleCheck("c0050", "issues", ""), true)
		-- R0030: prepared, but its member depends on c0090, which is not done
		write(
			seed,
			-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
			"pickman/.tracker/rafts/R0030/R0030.md",
			raftDoc("R0030", "Blocked", "blocked", "c0030", "ready", PREPARED)
		)
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		write(seed, "pickman/.tracker/rafts/R0030/check.sh", simpleCheck("R0030", "rafts", ""), true)
		write(
			seed,
			-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
			"pickman/.tracker/issues/c0030/c0030.md",
			issueDoc("c0030", "Gamma", "R0030", "c0090", "ready", PREPARED)
		)
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		write(seed, "pickman/.tracker/issues/c0030/check.sh", simpleCheck("c0030", "issues", ""), true)
		write(
			seed,
			"pickman/.tracker/issues/c0090/c0090.md",
			issueDoc("c0090", "Loose", "", "", "draft", "new-a-b-c")
		)
		write(seed, "pickman/.tracker/issues/c0090/check.sh", simpleCheck("c0090", "issues", ""), true)
		-- R0040: prepared, one member
		write(
			seed,
			-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
			"pickman/.tracker/rafts/R0040/R0040.md",
			raftDoc("R0040", "Second", "second", "c0040", "ready", PREPARED)
		)
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		write(seed, "pickman/.tracker/rafts/R0040/check.sh", simpleCheck("R0040", "rafts", ""), true)
		write(
			seed,
			-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
			"pickman/.tracker/issues/c0040/c0040.md",
			issueDoc("c0040", "Delta", "R0040", "", "ready", PREPARED)
		)
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		write(seed, "pickman/.tracker/issues/c0040/check.sh", simpleCheck("c0040", "issues", ""), true)
		-- R0050: prepared, but its member's check.sh has no check (only a commented one)
		write(
			seed,
			-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
			"pickman/.tracker/rafts/R0050/R0050.md",
			raftDoc("R0050", "Unchecked", "unchecked", "c0060", "ready", PREPARED)
		)
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		write(seed, "pickman/.tracker/rafts/R0050/check.sh", simpleCheck("R0050", "rafts", ""), true)
		write(
			seed,
			-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
			"pickman/.tracker/issues/c0060/c0060.md",
			issueDoc("c0060", "Epsilon", "R0050", "", "ready", PREPARED)
		)
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		write(
			seed,
			"pickman/.tracker/issues/c0060/check.sh",
			HEAD .. '# check "AC1: later" true\nfinish\n',
			true
		)
		-- R0060: prepared, its two members depend on each other (the workstream plan can't be built)
		write(
			seed,
			-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
			"pickman/.tracker/rafts/R0060/R0060.md",
			raftDoc("R0060", "Cyclic", "cyclic", "c0070, c0080", "ready", PREPARED)
		)
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		write(seed, "pickman/.tracker/rafts/R0060/check.sh", simpleCheck("R0060", "rafts", ""), true)
		write(
			seed,
			-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
			"pickman/.tracker/issues/c0070/c0070.md",
			issueDoc("c0070", "Zeta", "R0060", "c0080", "ready", PREPARED)
		)
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		write(seed, "pickman/.tracker/issues/c0070/check.sh", simpleCheck("c0070", "issues", ""), true)
		write(
			seed,
			-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
			"pickman/.tracker/issues/c0080/c0080.md",
			issueDoc("c0080", "Eta", "R0060", "c0070", "ready", PREPARED)
		)
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		write(seed, "pickman/.tracker/issues/c0080/check.sh", simpleCheck("c0080", "issues", ""), true)
		-- R0070: prepared on paper, but its member's design is only reviewed
		write(
			seed,
			-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
			"pickman/.tracker/rafts/R0070/R0070.md",
			raftDoc("R0070", "Unready", "unready", "c0110", "ready", PREPARED)
		)
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		write(seed, "pickman/.tracker/rafts/R0070/check.sh", simpleCheck("R0070", "rafts", ""), true)
		write(
			seed,
			-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
			"pickman/.tracker/issues/c0110/c0110.md",
			issueDoc("c0110", "Theta", "R0070", "", "reviewed", PREPARED)
		)
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		write(seed, "pickman/.tracker/issues/c0110/check.sh", simpleCheck("c0110", "issues", ""), true)
		git(seed, { "add", "-A" })
		git(seed, { "commit", "-q", "-m", "seed" })
		process.exec("git", { "clone", "-q", "--bare", seed, origin }) -- raw: clone to a named path
		process.exec("git", { "clone", "-q", origin, main })
		git(main, { "config", "user.name", "t" })
		git(main, { "config", "user.email", "t@example.invalid" })
		cap = trOk(main, { "worktree", "cap-a" })
		early = trOk(main, { "worktree", "R0060" })
		-- Finder litter, ignored as a Mac's global gitignore would: it must never block or break ready
		fs.writeFile(`{main}/.git/info/exclude`, ".DS_Store\n")
		t.expect(trOk(main, { "status", "R0010" })).toBe("prepared")
	end)

	it("ready refuses outside the main checkout, and without an origin", function()
		local before = tip()
		local r = tr(cap, { "ready", "R0010" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "main checkout")).toBe(true)
		local offline = tr(main, { "ready", "R0010" }, { PICKMAN_PUBLISH = "0" })
		t.expect(offline.ok).toBe(false)
		t.expect(has(offline.stderr, "origin")).toBe(true)
		t.expect(tip()).toBe(before)
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		t.expect(fs.isFile(`{main}/pickman/.tracker/rafts/active/R0010/prompt.md`)).toBe(false)
	end)

	it("ready refuses a raft that is not prepared", function()
		local before = tip()
		local r = tr(main, { "ready", "R0020" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "R0020")).toBe(true)
		t.expect(has(r.stderr, "prepared")).toBe(true)
		t.expect(tip()).toBe(before)
	end)

	it("ready refuses a dirty main checkout", function()
		local before = tip()
		fs.writeFile(`{main}/stray.txt`, "x")
		local r = tr(main, { "ready", "R0010" })
		fs.removeFile(`{main}/stray.txt`)
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "clean")).toBe(true)
		git(main, { "switch", "-q", "-c", "side" })
		local off = tr(main, { "ready", "R0010" })
		git(main, { "switch", "-q", "main" })
		git(main, { "branch", "-q", "-D", "side" })
		t.expect(off.ok).toBe(false)
		t.expect(has(off.stderr, "main")).toBe(true)
		t.expect(tip()).toBe(before)
	end)

	it("ready refuses an unfinished dependency outside the raft, naming it", function()
		local before = tip()
		local r = tr(main, { "ready", "R0030" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "c0090")).toBe(true)
		t.expect(tip()).toBe(before)
	end)

	it("ready refuses a raft whose member has no check", function()
		local before = tip()
		local r = tr(main, { "ready", "R0050" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "c0060")).toBe(true)
		local unready = tr(main, { "ready", "R0070" }) -- prepared, but c0110 is not design: ready
		t.expect(unready.ok).toBe(false)
		t.expect(has(unready.stderr, "c0110")).toBe(true)
		t.expect(tip()).toBe(before)
	end)

	it("ready resolves an issue to its raft and refuses a raftless issue", function()
		local before = tip()
		local viaIssue = tr(main, { "ready", "c0050" }) -- R0020 is not prepared
		t.expect(viaIssue.ok).toBe(false)
		t.expect(has(viaIssue.stderr, "R0020")).toBe(true)
		local loose = tr(main, { "ready", "c0090" })
		t.expect(loose.ok).toBe(false)
		t.expect(has(loose.stderr, "no raft")).toBe(true)
		t.expect(tip()).toBe(before)
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		t.expect(onOrigin("pickman/.tracker/rafts/R0080/R0080.md")).toBe(nil) -- no placeholder raft
	end)

	it(
		"ready moves the raft and its members to active/ on origin/main in one commit, stamped active",
		function()
			local before = tip()
			local files =
				-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
				string.split(
					git(origin, { "ls-tree", "-r", "--name-only", "main", "pickman/.tracker/" }),
					"\n"
				)
			local moving: { string } = {}
			for _, p in files do
				if
					-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
					string.match(p, "^pickman/%.tracker/rafts/R0010/")
					or string.match(p, "^pickman/%.tracker/issues/c0010/")
					or string.match(p, "^pickman/%.tracker/issues/c0020/")
				then
					table.insert(moving, p)
				end
			end
			t.expect(#moving).toBe(8)
			-- untracked litter in directories the move empties: the pull leaves them, the sweep removes them
			-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
			fs.writeFile(`{main}/pickman/.tracker/issues/c0010/.DS_Store`, "finder")
			fs.writeFile(`{main}/pickman/.tracker/rafts/R0010/.DS_Store`, "finder")
			trOk(main, { "ready", "R0010" })
			-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
			t.expect(fs.isDir(`{main}/pickman/.tracker/issues/c0010`)).toBe(false)
			t.expect(fs.isDir(`{main}/pickman/.tracker/rafts/R0010`)).toBe(false)
			t.expect(tr(main, { "list" }).ok).toBe(true)
			t.expect(git(origin, { "rev-list", "--count", `{before}..main` })).toBe("1")
			local changed =
				string.split(git(origin, { "diff", "--name-only", "--no-renames", before, "main" }), "\n")
			t.expect(#changed).toBe(16)
			for _, p in moving do
				-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
				local dest = (string.gsub(p, "^pickman/%.tracker/(%a+)/", "pickman/.tracker/%1/active/"))
				t.expect(onOrigin(p)).toBe(nil)
				t.expect(onOrigin(dest) ~= nil).toBe(true)
				t.expect(table.find(changed, p) ~= nil and table.find(changed, dest) ~= nil).toBe(true)
			end
			-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
			t.expect(onOrigin("pickman/.tracker/issues/active/c0010/acceptance/a.spec.luau")).toBe(SPEC)
			t.expect(string.sub(
				-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
				git(origin, { "ls-tree", "main", "pickman/.tracker/issues/active/c0010/experiments/E1.sh" }),
				1,
				6
			)).toBe("100755")
			local stamps: { [string]: boolean } = {}
			for _, doc in
				{
					-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
					"pickman/.tracker/rafts/active/R0010/R0010.md",
					"pickman/.tracker/issues/active/c0010/c0010.md",
					"pickman/.tracker/issues/active/c0020/c0020.md",
				}
			do
				local s = string.match(onOrigin(doc) or "", "\nstatus: (active%-%a+%-%a+%-%a+)\n")
				t.expect(s ~= nil).toBe(true)
				stamps[s :: string] = true
				readiedStamp = s :: string
			end
			local distinct = 0
			for _ in stamps do
				distinct += 1
			end
			t.expect(distinct).toBe(1) -- one claim for the raft and its members
			t.expect(trOk(main, { "status", "R0010" })).toBe("active")
			t.expect(trOk(main, { "status", "c0020" })).toBe("active")
			-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
			t.expect(onOrigin("pickman/.tracker/rafts/R0040/R0040.md") ~= nil).toBe(true) -- other rafts stay
		end
	)

	it("ready rewrites the moved check.sh paths to active/ and nothing else", function()
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		t.expect(onOrigin("pickman/.tracker/issues/active/c0010/check.sh")).toBe(c0010Check("active/"))
		t.expect(onOrigin("pickman/.tracker/rafts/active/R0010/check.sh")).toBe(r0010Check("active/"))
		t.expect(onOrigin("pickman/.tracker/issues/active/c0020/check.sh"))
			.toBe(simpleCheck("c0020", "issues", "active/"))
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		local doc = onOrigin("pickman/.tracker/issues/active/c0010/c0010.md") :: string
		t.expect((string.gsub(doc, "\nstatus: [^\n]*", "\nstatus: X"))).toBe(
			(
				string.gsub(
					issueDoc("c0010", "Alpha", "R0010", "", "ready", PREPARED),
					"\nstatus: [^\n]*",
					"\nstatus: X"
				)
			)
		)
	end)

	it("ready pulls the main checkout and writes the ignored prompt.md", function()
		t.expect(git(main, { "rev-parse", "HEAD" })).toBe(tip())
		t.expect(git(main, { "branch", "--show-current" })).toBe("main")
		t.expect(git(main, { "status", "--porcelain" })).toBe("")
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		local path = `{main}/pickman/.tracker/rafts/active/R0010/prompt.md`
		t.expect(fs.isFile(path)).toBe(true)
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		t.expect(
			run(main, "git", { "check-ignore", "-q", "pickman/.tracker/rafts/active/R0010/prompt.md" }).ok
		)
			.toBe(true)
		local prompt = fs.readFile(path)
		for _, needle in
			{
				"Marker Readied.",
				"Marker Alpha.",
				"Marker Beta.",
				"-- c0010 acceptance marker",
				-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
				"pickman/.tracker/issues/active/c0010/acceptance/a.spec.luau",
				"parallel:",
				"R0010",
			}
		do
			t.expect(has(prompt, needle)).toBe(true)
		end
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		t.expect(has(prompt, "test -f pickman/.tracker/issues/c0010/acceptance")).toBe(false) -- the rewritten check.sh is inlined
		t.expect(fs.isFile(`{cap}/pickman/.tracker/rafts/active/R0010/prompt.md`)).toBe(false)
	end)

	it("ready never calls pbcopy", function()
		t.expect(fs.isFile(clipLog)).toBe(false)
	end)

	it("prompt.md embeds the workstreams plan, or the error when it can't be built", function()
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		local plain = fs.readFile(`{main}/pickman/.tracker/rafts/active/R0010/prompt.md`)
		t.expect(has(plain, "## Workstreams plan")).toBe(true)
		t.expect(has(plain, "parallel: ")).toBe(true)
		trOk(main, { "ready", "R0060" }) -- dependencies inside the raft never block ready
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		local cyclic = fs.readFile(`{main}/pickman/.tracker/rafts/active/R0060/prompt.md`)
		t.expect(has(cyclic, "## Workstreams plan")).toBe(true)
		t.expect(has(cyclic, "plan unavailable: dependency cycle")).toBe(true)
		t.expect(has(cyclic, "parallel: no")).toBe(true)
	end)

	it("start in a worktree made before ready says to sync first", function()
		local r = tr(early, { "start", "R0060" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "sync")).toBe(true)
		t.expect(git(early, { "branch", "--show-current" })).toBe("R0060-cyclic")
		t.expect(git(early, { "log", "-1", "--format=%s" })).toBe("seed")
	end)

	it("ready on an active raft regenerates the prompt without a new commit", function()
		local before = tip()
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		local path = `{main}/pickman/.tracker/rafts/active/R0010/prompt.md`
		fs.writeFile(path, "stale\n")
		local out = trOk(main, { "ready", "R0010" })
		t.expect(has(out, "regenerated")).toBe(true)
		t.expect(tip()).toBe(before)
		t.expect(has(fs.readFile(path), "Marker Readied.")).toBe(true)
		fs.removeFile(path)
		trOk(main, { "ready", "c0010" }) -- an issue id regenerates its raft's prompt too
		t.expect(fs.isFile(path)).toBe(true)
		t.expect(tip()).toBe(before)
		t.expect(fs.isFile(clipLog)).toBe(false)
	end)

	it(
		"start on a readied raft makes the branch with an empty commit, and moves and claims nothing",
		function()
			local before = tip()
			wt = trOk(main, { "worktree", "R0010" })
			trOk(wt, { "start", "R0010" })
			t.expect(git(wt, { "branch", "--show-current" })).toBe("R0010-readied")
			t.expect(has(git(wt, { "log", "-1", "--format=%s" }), "tracker: start R0010")).toBe(true)
			t.expect(git(wt, { "diff", "--name-only", before, "HEAD" })).toBe("")
			t.expect(git(wt, { "rev-parse", "HEAD^" })).toBe(before)
			t.expect(tip()).toBe(before)
			t.expect(git(origin, { "rev-parse", "R0010-readied" })).toBe(git(wt, { "rev-parse", "HEAD" }))
			-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
			t.expect(
				has(
					fs.readFile(`{wt}/pickman/.tracker/rafts/active/R0010/R0010.md`),
					`status: {readiedStamp}`
				)
			)
				.toBe(true)
		end
	)

	it("commit works on a raft branch while another raft is readied on main", function()
		trOk(main, { "ready", "R0040" })
		git(wt, { "merge", "-q", "--no-edit", "origin/main" })
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		t.expect(fs.isFile(`{wt}/pickman/.tracker/rafts/active/R0040/R0040.md`)).toBe(true)
		fs.writeFile(`{wt}/notes.txt`, "work\n")
		trOk(wt, { "commit", "-m", "work", "--time", "1" })
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		t.expect(fs.isFile(`{wt}/pickman/.tracker/rafts/active/R0010/spend.md`)).toBe(true)
		t.expect(fs.isFile(`{wt}/pickman/.tracker/rafts/active/R0040/spend.md`)).toBe(false)
		t.expect(git(wt, { "status", "--porcelain" })).toBe("")
	end)

	it("new issue --raft needs the raft's branch", function()
		trOk(cap, { "sync" })
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		t.expect(fs.isFile(`{cap}/pickman/.tracker/rafts/active/R0010/R0010.md`)).toBe(true)
		local r = tr(cap, { "new", "issue", "c", "kappa", "--raft", "R0010" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "--raft")).toBe(true)
		local made = trOk(wt, { "new", "issue", "c", "mu", "--raft", "R0010" })
		local id = string.match(made, "(c%d%d%d%d)") :: string
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		t.expect(has(made, `pickman/.tracker/issues/active/{id}`)).toBe(true)
		t.expect(has(fs.readFile(`{wt}/pickman/.tracker/issues/active/{id}/{id}.md`), "emergent: true"))
			.toBe(true)
		trOk(wt, { "commit", "-m", "emergent", "--time", "1" })
	end)

	it("done rewrites check.sh paths to done/", function()
		local wt4 = trOk(main, { "worktree", "R0040" })
		trOk(wt4, { "start", "R0040" })
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		write(wt4, "pickman/.tracker/rafts/active/R0040/review-001.md", "# Review 001\n\nVerdict: approve\n")
		trOk(wt4, { "commit", "-m", "review", "--time", "1" })
		-- the current raft is this branch's raft, not the first or lowest active one (R0010 and R0060 are active too)
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		t.expect(fs.isFile(`{wt4}/pickman/.tracker/rafts/active/R0040/spend.md`)).toBe(true)
		t.expect(fs.isFile(`{wt4}/pickman/.tracker/rafts/active/R0010/spend.md`)).toBe(false)
		t.expect(fs.isFile(`{wt4}/pickman/.tracker/rafts/active/R0060/spend.md`)).toBe(false)
		trOk(wt4, { "done", "R0040" })
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		t.expect(fs.readFile(`{wt4}/pickman/.tracker/issues/done/c0040/check.sh`))
			.toBe(simpleCheck("c0040", "issues", "done/"))
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		t.expect(fs.readFile(`{wt4}/pickman/.tracker/rafts/done/R0040/check.sh`))
			.toBe(simpleCheck("R0040", "rafts", "done/"))
	end)

	it("sync in the main checkout sweeps what a raft that left active/ left behind", function()
		local wt4 = trOk(main, { "worktree", "R0040" })
		-- the PR merges: R0040's branch, now done, lands on origin/main
		git(wt4, { "push", "-q", "origin", "HEAD:main" })
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		local stale = `{main}/pickman/.tracker/rafts/active/R0040`
		t.expect(fs.isFile(`{stale}/prompt.md`)).toBe(true)
		fs.writeFile(`{stale}/.DS_Store`, "finder")
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		fs.writeFile(`{main}/pickman/.tracker/issues/active/c0040/.DS_Store`, "finder")
		trOk(main, { "sync" })
		t.expect(git(main, { "rev-parse", "HEAD" })).toBe(tip())
		t.expect(fs.isDir(stale)).toBe(false)
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		t.expect(fs.isDir(`{main}/pickman/.tracker/issues/active/c0040`)).toBe(false)
		t.expect(fs.isFile(`{main}/pickman/.tracker/rafts/done/R0040/R0040.md`)).toBe(true)
		-- a raft that is still readied keeps its prompt
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		t.expect(fs.isFile(`{main}/pickman/.tracker/rafts/active/R0010/prompt.md`)).toBe(true)
		t.expect(fs.isFile(`{main}/pickman/.tracker/rafts/active/R0060/prompt.md`)).toBe(true)
		local list = tr(main, { "list" })
		t.expect(list.ok).toBe(true)
		t.expect(has(list.stdout, "R0040")).toBe(true)
		t.expect(tr(main, { "board", "-O", "--out", `{base}/board.html` }).ok).toBe(true)
	end)
end)
