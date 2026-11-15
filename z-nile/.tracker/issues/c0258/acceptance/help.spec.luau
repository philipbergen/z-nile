--!strict
-- c0258 AC1 through the command: `./zn -h`, `./zn --help` and `-h`/`--help` after any command print usage and run
-- nothing (no merge, no gate, no push, no item, no approve refusal), `./zn run --help` is the runner's, and a `--help`
-- that belongs to something else (the command `./zn run` bounds, the value of `-m`) is not help.
-- One fixture (trackerfix, .cache/c0258-help): three draft backlog issues seeded on origin; the land cases use a capture
-- worktree made with raw git from origin/main. The gate is PICKMAN_LAND_GATE, a script that counts its runs.
-- `./zn` runs with a plain session's environment (no publish broker, no dispatcher git on PATH: d0355), so the cases
-- pass in a dispatched session too.
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
local F = trackerfix.new("c0258-help", seed)

local function git(cwd: string, args: { string }): string
	return fixture.git(cwd, args)
end
local function has(text: string?, needle: string): boolean
	return text ~= nil and string.find(text, needle, 1, true) ~= nil
end
local function tip(): string
	return git(F.origin, { "rev-parse", "main" })
end
-- a plain session's environment over `env`: no publish broker, no dispatcher git wrapper on PATH (d0355)
local function plain(env: { [string]: string }?): { [string]: string }
	local e: { [string]: string } = env or {}
	local keep: { string } = {}
	for part in string.gmatch(process.env.PATH or "", "[^:]+") do
		if not string.match(part, "/z%-nile/bin/?$") then
			table.insert(keep, part)
		end
	end
	e.PATH = table.concat(keep, ":")
	e.ZN_PUBLISH_BROKER = ""
	e.ZN_PUBLISH_TOKEN = ""
	-- land kicks the watch net after a push: not in a fixture
	e.PICKMAN_WATCH_NET = "off"
	e.ZN_DISPATCH = e.ZN_DISPATCH or ""
	return e
end
local function zn(cwd: string, args: { string }, env: { [string]: string }?): Result
	return trackerfix.tr(F, cwd, args, plain(env))
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

return t.spec("c0258 help", function(it)
	it(
		"AC1: ./zn -h and ./zn --help print the whole usage and exit 0; an unknown command still exits 1",
		function()
			for _, flag in { "-h", "--help" } do
				local r = zn(F.main, { flag })
				t.expect(r.ok).toBe(true)
				t.expect(has(r.stdout, "usage: ./zn <command> ...")).toBe(true)
				t.expect(has(r.stdout, "  land [-m <message>]")).toBe(true)
			end
			local bogus = zn(F.main, { "bogus", "--help" })
			t.expect(bogus.ok).toBe(false)
			t.expect(has(bogus.stdout, "usage: ./zn <command> ...")).toBe(true)
		end
	)

	it(
		"AC1: land --help and land -h print land's usage and run nothing: no merge, no gate, no push",
		function()
			local wt = capture("capture-help", "c0001")
			local head = git(wt, { "rev-parse", "HEAD" })
			-- main moves, so a land that ran would merge it
			trackerfix.elsewhere(F, { ["pickman/.tracker/moved.txt"] = "moved\n" }, "move main")
			local before = tip()
			local cmd, count = gate("help")
			for _, flag in { "--help", "-h" } do
				local r = zn(wt, { "land", flag }, { PICKMAN_LAND_GATE = cmd })
				t.expect(r.ok).toBe(true)
				t.expect(string.sub(r.stdout, 1, #"usage: ./zn land ...")).toBe("usage: ./zn land ...")
				t.expect(has(r.stdout, "  land [-m <message>]")).toBe(true)
				t.expect(has(r.stdout, "  stamp <state>")).toBe(false)
			end
			t.expect(runs(count)).toBe(0)
			t.expect(tip()).toBe(before)
			t.expect(git(wt, { "rev-parse", "HEAD" })).toBe(head)
			t.expect(git(wt, { "status", "--porcelain", "--untracked-files=all" })).toBe("")
		end
	)

	it("AC1: new --help prints new's usage and creates nothing, here or on origin", function()
		local wt = capture("capture-help-new", "c0002")
		local before = tip()
		local r = zn(wt, { "new", "issue", "c", "helped", "--project", "pickman", "--help" })
		t.expect(r.ok).toBe(true)
		t.expect(has(r.stdout, "usage: ./zn new ...")).toBe(true)
		t.expect(tip()).toBe(before)
		t.expect(git(wt, { "status", "--porcelain", "--untracked-files=all" })).toBe("")
	end)

	it(
		"AC1: approve --help prints approve's usage even under the dispatcher, which refuses approve itself",
		function()
			local r = zn(F.main, { "approve", "c0001", "--help" }, { ZN_DISPATCH = "1" })
			t.expect(r.ok).toBe(true)
			t.expect(has(r.stdout, "usage: ./zn approve ...")).toBe(true)
			t.expect(has(r.stderr, "refused")).toBe(false)
			local refused = zn(F.main, { "approve", "c0001" }, { ZN_DISPATCH = "1" })
			t.expect(refused.ok).toBe(false)
			t.expect(has(refused.stderr, "refused")).toBe(true)
		end
	)

	it(
		"AC1: run --help prints the runner's usage and runs nothing; after the command it is the command's",
		function()
			local r = zn(F.main, { "run", "--help" })
			t.expect(r.ok).toBe(true)
			t.expect(string.sub(r.stdout, 1, #"usage: ./zn run ")).toBe("usage: ./zn run ")
			local passed = zn(F.main, { "run", "--time", "5", "--", "echo", "--help" })
			t.expect(passed.ok).toBe(true)
			t.expect(passed.stdout).toBe("--help\n")
		end
	)

	it("AC1: a -h that is -m's value is the message, not help: land lands it", function()
		local wt = capture("capture-help-value", "c0003")
		local cmd, count = gate("value")
		local r = zn(wt, { "land", "-m", "-h" }, { PICKMAN_LAND_GATE = cmd })
		if not r.ok then
			error(`exit {r.code}\n{r.stdout}\n{r.stderr}`)
		end
		t.expect(runs(count)).toBe(1)
		t.expect(git(F.origin, { "log", "-1", "--format=%s", "main" })).toBe("-h")
		t.expect(has(r.stdout, "usage:")).toBe(false)
	end)
end)
