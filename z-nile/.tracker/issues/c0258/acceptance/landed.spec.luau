--!strict
-- c0258 AC4 through the command: a push that reports a failure while origin/main holds its commit has landed (say so,
-- exit 0, and leave the branch at main); a branch whose change main already holds says "already landed", exits 0,
-- runs no gate and pushes nothing, also when it has merged the main that holds it (as `./zn sync` does); a branch with
-- no change of its own still has nothing to land.
-- One fixture (trackerfix, .cache/c0258-landed): two draft backlog issues seeded on origin, each case a capture
-- worktree made with raw git from origin/main. The gate is PICKMAN_LAND_GATE, a script that counts its runs.
-- A stand-in git first on PATH for land alone pushes for real and then reports a failure.
-- Reviewed exception to the fixture rule (as c0072's race case): the stand-in forwards to the real git, whose push goes
-- only to the fixture's origin under this spec's .cache folder.
-- `./zn` runs with a plain session's environment (no publish broker, no dispatcher git on PATH: d0355).
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local IDS = { "c0001", "c0002", "c0003" }
local function doc(id: string): string
	return `pickman/.tracker/issues/{id}/{id}.md`
end
local seed: { [string]: string } = {}
for _, id in IDS do
	seed[doc(id)] = trackerfix.stub(id, `topic-{id}`, "new-plain-quiet-otter")
end
local F = trackerfix.new("c0258-landed", seed)

local function git(cwd: string, args: { string }): string
	return fixture.git(cwd, args)
end
local function has(text: string?, needle: string): boolean
	return text ~= nil and string.find(text, needle, 1, true) ~= nil
end
local function tip(): string
	return git(F.origin, { "rev-parse", "main" })
end
local function said(r: Result): string
	return `exit {r.code}\n{r.stdout}\n{r.stderr}`
end
-- the PATH of a plain session (d0355), with `first` in front when given
local function pathOf(first: string?): string
	local keep: { string } = if first then { first } else {}
	for part in string.gmatch(process.env.PATH or "", "[^:]+") do
		if not string.match(part, "/z%-nile/bin/?$") then
			table.insert(keep, part)
		end
	end
	return table.concat(keep, ":")
end
local function zn(cwd: string, args: { string }, env: { [string]: string }, first: string?): Result
	env.PATH = pathOf(first)
	env.ZN_PUBLISH_BROKER = ""
	env.ZN_PUBLISH_TOKEN = ""
	-- land kicks the watch net after a push: not in a fixture
	env.PICKMAN_WATCH_NET = "off"
	env.ZN_DISPATCH = ""
	return trackerfix.tr(F, cwd, args, env)
end
-- a capture worktree from origin/main whose one commit adds a line to issue `id`'s document
local function capture(name: string, id: string): string
	git(F.main, { "fetch", "-q", "origin" })
	local wt = `{F.main}/.worktree/{name}`
	git(F.main, { "worktree", "add", "-q", "-b", name, wt, "origin/main" })
	local path = `{wt}/{doc(id)}`
	fs.writeFile(path, fs.readFile(path) .. `\nMore about {id}.\n`)
	git(wt, { "add", "-A" })
	git(wt, { "commit", "-q", "-m", `tracker: new {id} topic-{id}` })
	return wt
end
-- a gate script that counts its runs in <base>/<name>.count
local function gate(name: string): (string, string)
	local count = `{F.base}/{name}.count`
	local path = `{F.base}/{name}.sh`
	fs.writeFile(
		path,
		`#!/bin/bash\nn=$(( $(cat "{count}" 2>/dev/null || echo 0) + 1 ))\necho "$n" > "{count}"\nexit 0\n`
	)
	return `bash {path}`, count
end
local function runs(count: string): number
	return if fs.isFile(count) then tonumber((string.gsub(fs.readFile(count), "%s", ""))) or 0 else 0
end
-- the stand-in git: a push pushes and then reports a failure
local FAKE = `{F.base}/fakebin`
fs.writeDir(FAKE)
fs.writeFile(
	`{FAKE}/git`,
	table.concat({
		"#!/bin/bash",
		-- never itself again (lesson zz-test/forwarding-stand-ins-never-find-themselves): zn puts ~/.rokit/bin in
		-- front of this folder, so the folder leaves every position of PATH, and a nested run stops at once
		'[[ -n ${LAND_FAKE_IN:-} ]] && { echo "stand-in git ran inside itself" >&2; exit 97; }',
		"export LAND_FAKE_IN=1",
		'self=$(cd "$(dirname "$0")" && pwd -P)',
		'p=":$PATH:"; p=${p//":$self:"/":"}; p=${p#:}; PATH=${p%:}',
		'if [[ $1 == push ]]; then git "$@" >/dev/null 2>&1; echo "fatal: the remote end hung up" >&2; exit 1; fi',
		'exec git "$@"',
		"",
	}, "\n")
)
process.exec("chmod", { "+x", `{FAKE}/git` })

return t.spec("c0258 land landed", function(it)
	it("AC4: a push that reports a failure while origin/main holds its commit has landed", function()
		local wt = capture("capture-lie", "c0001")
		local before = tip()
		local cmd = gate("lie")
		local r = zn(wt, { "land" }, { PICKMAN_LAND_GATE = cmd }, FAKE)
		if not r.ok then
			error(said(r))
		end
		t.expect(has(r.stdout, `landed {tip()} on main`)).toBe(true)
		t.expect(has(r.stdout, "the push reported a failure")).toBe(true)
		t.expect(git(F.origin, { "rev-list", "--count", `{before}..main` })).toBe("1")
		t.expect(git(wt, { "rev-parse", "HEAD" })).toBe(tip())
	end)

	it(
		"AC4: a branch whose change main already holds says it already landed, exits 0 and runs no gate",
		function()
			-- two captures of one change: the first lands
			local first = capture("capture-twice-a", "c0002")
			local second = `{F.main}/.worktree/capture-twice-b`
			git(F.main, { "worktree", "add", "-q", "-b", "capture-twice-b", second, "origin/main" })
			git(second, { "cherry-pick", git(first, { "rev-parse", "HEAD" }) })
			local cmd, count = gate("twice")
			local landed = zn(first, { "land" }, { PICKMAN_LAND_GATE = cmd })
			if not landed.ok then
				error(said(landed))
			end
			t.expect(runs(count)).toBe(1)
			local before = tip()
			local r = zn(second, { "land" }, { PICKMAN_LAND_GATE = cmd })
			if not r.ok then
				error(said(r))
			end
			t.expect(has(r.stdout, `already landed on main: origin/main {before}`)).toBe(true)
			t.expect(has(r.stdout, "remove this worktree")).toBe(true)
			t.expect(runs(count)).toBe(1)
			t.expect(tip()).toBe(before)
			t.expect(git(second, { "rev-parse", "HEAD" })).toBe(before)
			-- a branch with no change of its own still has nothing to land
			local empty = `{F.main}/.worktree/capture-empty`
			git(F.main, { "worktree", "add", "-q", "-b", "capture-empty", empty, "origin/main" })
			local nothing = zn(empty, { "land" }, { PICKMAN_LAND_GATE = cmd })
			t.expect(nothing.ok).toBe(false)
			t.expect(has(nothing.stderr, "nothing to land")).toBe(true)
			t.expect(runs(count)).toBe(1)
		end
	)

	it(
		"AC4: a branch that merged the main holding its change (as ./zn sync does) still says already landed",
		function()
			local first = capture("capture-synced-a", "c0003")
			local second = `{F.main}/.worktree/capture-synced-b`
			git(F.main, { "worktree", "add", "-q", "-b", "capture-synced-b", second, "origin/main" })
			git(second, { "cherry-pick", git(first, { "rev-parse", "HEAD" }) })
			local cmd, count = gate("synced")
			local landed = zn(first, { "land" }, { PICKMAN_LAND_GATE = cmd })
			if not landed.ok then
				error(said(landed))
			end
			-- the second branch merges the main that holds its change: its merge base is now past its own commit
			git(second, { "fetch", "-q", "origin" })
			git(second, { "merge", "-q", "--no-edit", "origin/main" })
			local before = tip()
			local r = zn(second, { "land" }, { PICKMAN_LAND_GATE = cmd })
			if not r.ok then
				error(said(r))
			end
			t.expect(has(r.stdout, `already landed on main: origin/main {before}`)).toBe(true)
			t.expect(runs(count)).toBe(1)
			t.expect(tip()).toBe(before)
			t.expect(git(second, { "rev-parse", "HEAD" })).toBe(before)
		end
	)
end)
