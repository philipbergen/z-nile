--!strict
-- c0258 AC2 through the command: after a lost push race `./zn land` merges the new main and pushes again with no gate
-- when main moved by tracker state alone and changed none of the capture's files, runs the gate again otherwise
-- (saying why), folds the gate's spend row into the commit it pushes on every try (the fold is undone before each
-- merge, which refuses a staged tree), and a gate that fails on its second run pushes nothing and leaves the tree
-- clean; after a regate the next race is judged from the main that gate passed on.
-- One fixture (trackerfix, .cache/c0258-race): five draft backlog issues seeded on origin, each case a capture worktree
-- made with raw git from origin/main. The gate is PICKMAN_LAND_GATE, a script that counts its runs and, on its first
-- run, pushes one commit from the fixture's other clone, so land's first push loses the race.
-- Reviewed exception to the fixture rule (as c0072's race case): the gate scripts run raw git only in the fixture's
-- `other` clone under this spec's .cache folder.
-- `./zn` runs with a plain session's environment (no publish broker, no dispatcher git on PATH: d0355).
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local IDS = { "c0001", "c0002", "c0003", "c0004", "c0005", "c0006" }
local function doc(id: string): string
	return `pickman/.tracker/issues/{id}/{id}.md`
end
local seed: { [string]: string } = {}
for _, id in IDS do
	seed[doc(id)] = trackerfix.stub(id, `topic-{id}`, "new-plain-quiet-otter")
end
local F = trackerfix.new("c0258-race", seed)

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
	e.ZN_DISPATCH = ""
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
-- a gate script that counts its runs in <base>/<name>.count (as $n) and then runs `body`
local function gate(name: string, body: string): (string, string)
	local count = `{F.base}/{name}.count`
	local path = `{F.base}/{name}.sh`
	fs.writeFile(
		path,
		`#!/bin/bash\nn=$(( $(cat "{count}" 2>/dev/null || echo 0) + 1 ))\necho "$n" > "{count}"\n{body}\n`
	)
	return `bash {path}`, count
end
local function runs(count: string): number
	return if fs.isFile(count) then tonumber((string.gsub(fs.readFile(count), "%s", ""))) or 0 else 0
end
-- bash that, on the gate's first run only, pushes one commit from the other clone made by `edit` (a shell command)
-- (an `if`, not `[[ $n == 1 ]] && ... || exit 9`, which exits 9 on every later run)
-- (`at`: on that run instead, and the commit's subject is race<at>)
local function race(edit: string, at: number?): string
	local run = at or 1
	local subject = if at then `race{at}` else "race"
	return `if [[ $n == {run} ]]; then ( cd "{F.other}" && git pull -q origin main && {edit} && git add -A && git commit -qm {subject} && git push -q origin HEAD:main ) || exit 9; fi`
end
-- bash that appends one measured gate row for this branch to the checkout's buffer, as check.sh's measure does
local ROW =
	[[mkdir -p .cache && printf '%s000\ttest\ttest\tstatic\t3\t2\t\t\t\t\t\t\t%s\t\n' "$(date +%s)" "$(git rev-parse --abbrev-ref HEAD)" >> .cache/measure.tsv]]

return t.spec("c0258 land race", function(it)
	it(
		"AC2: a race by tracker state alone pushes again with no gate, and the gate's row is folded in",
		function()
			local wt = capture("capture-tracker", "c0003")
			local before = tip()
			local cmd, count =
				gate("tracker", `{ROW}\n{race([[echo raced > pickman/.tracker/raced.txt]])}\nexit 0`)
			local r = zn(wt, { "land" }, { PICKMAN_LAND_GATE = cmd })
			if not r.ok then
				error(said(r))
			end
			t.expect(runs(count)).toBe(1)
			t.expect(has(r.stdout, "running the gate again")).toBe(false)
			t.expect(git(F.origin, { "rev-list", "--count", `{before}..main` })).toBe("2")
			t.expect(git(F.origin, { "log", "-1", "--format=%s", "main^" })).toBe("race")
			local landed = git(F.origin, { "diff", "--name-only", "main^", "main" })
			t.expect(has(landed, doc("c0003"))).toBe(true)
			t.expect(has(landed, "pickman/.tracker/issues/c0003/spend.d/")).toBe(true)
			t.expect(has(r.stdout, `landed {tip()} on main`)).toBe(true)
		end
	)

	it(
		"AC2: a race by more than tracker state runs the gate again before the next push, and says why",
		function()
			local wt = capture("capture-code", "c0001")
			-- the second run gates the merged tree: the race's file is in it (design review 001 F6, mutant A)
			local cmd, count = gate(
				"code",
				`{race([[echo code > race-code.txt]])}\nif [[ $n == 2 ]]; then [[ -e race-code.txt ]] || exit 7; fi\nexit 0`
			)
			local r = zn(wt, { "land" }, { PICKMAN_LAND_GATE = cmd })
			if not r.ok then
				error(said(r))
			end
			t.expect(runs(count)).toBe(2)
			t.expect(has(r.stdout, "main moved by more than tracker state")).toBe(true)
			t.expect(has(r.stdout, "race-code.txt")).toBe(true)
			t.expect(git(F.origin, { "log", "-1", "--format=%s", "main^" })).toBe("race")
			t.expect(git(F.origin, { "diff", "--name-only", "main^", "main" })).toBe(doc("c0001"))
		end
	)

	it("AC2: a race that changes the capture's own document runs the gate again, naming it", function()
		local wt = capture("capture-own", "c0002")
		local cmd, count = gate(
			"own",
			`{race(`perl -pi -e 's/^status: .*/status: new-other-moved-it/' {doc("c0002")}`)}\nexit 0`
		)
		local r = zn(wt, { "land" }, { PICKMAN_LAND_GATE = cmd })
		if not r.ok then
			error(said(r))
		end
		t.expect(runs(count)).toBe(2)
		t.expect(has(r.stdout, `main changed this capture's {doc("c0002")}`)).toBe(true)
		local text = git(F.origin, { "show", `main:{doc("c0002")}` })
		t.expect(has(text, "More about c0002.")).toBe(true)
		t.expect(has(text, "status: new-other-moved-it")).toBe(true)
	end)

	it(
		"AC2: after a regate the next race is judged from the main the gate passed on, not the first",
		function()
			local wt = capture("capture-after", "c0005")
			-- run 1 loses to a code change (a regate), run 2 to tracker state alone (no third run)
			local cmd, count = gate(
				"after",
				`{race([[echo after > race-after.txt]], 1)}\n{race(
					[[echo after > pickman/.tracker/after.txt]],
					2
				)}\nexit 0`
			)
			local r = zn(wt, { "land" }, { PICKMAN_LAND_GATE = cmd })
			if not r.ok then
				error(said(r))
			end
			t.expect(runs(count)).toBe(2)
			local _, again = string.gsub(r.stdout, "running the gate again", "")
			t.expect(again).toBe(1)
			t.expect(git(F.origin, { "log", "-1", "--format=%s", "main^" })).toBe("race2")
			t.expect(git(F.origin, { "diff", "--name-only", "main^", "main" })).toBe(doc("c0005"))
		end
	)

	it("AC2: a race that lands the capture's own change says already landed, with no second gate", function()
		local wt = capture("capture-same", "c0006")
		-- the race makes the capture's very edit, so the merged branch changes nothing against the new main
		local cmd, count =
			gate("same", `{race(`printf '\\nMore about c0006.\\n' >> {doc("c0006")}`)}\nexit 0`)
		local r = zn(wt, { "land" }, { PICKMAN_LAND_GATE = cmd })
		if not r.ok then
			error(said(r))
		end
		local now = tip()
		t.expect(has(r.stdout, `already landed on main: origin/main {now}`)).toBe(true)
		t.expect(runs(count)).toBe(1)
		t.expect(git(F.origin, { "log", "-1", "--format=%s", "main" })).toBe("race")
		t.expect(git(wt, { "rev-parse", "HEAD" })).toBe(now)
	end)

	it("AC2: a gate that fails on its second run pushes nothing and leaves the tree clean", function()
		local wt = capture("capture-red", "c0004")
		local cmd, count = gate("red", `{ROW}\n{race([[echo red > race-red.txt]])}\n[[ $n == 1 ]]`)
		local r = zn(wt, { "land" }, { PICKMAN_LAND_GATE = cmd })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "the gate failed: nothing was pushed")).toBe(true)
		t.expect(runs(count)).toBe(2)
		t.expect(git(F.origin, { "log", "-1", "--format=%s", "main" })).toBe("race")
		t.expect(git(wt, { "status", "--porcelain", "--untracked-files=all" })).toBe("")
	end)
end)
