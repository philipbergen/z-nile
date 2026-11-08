--!strict
-- c0265: taking over a lost claim discards the old worker's worktree and recovers its work (the user, 2026-11-08):
-- `./zn worktree <name> --takeover` moves the old worktree aside as <name>-<n> (the next free number) with its branch
-- renamed <branch>-<n>, creates a fresh worktree at <name> that continues the old agent's PUSHED branch (so the PR head
-- keeps working), lists what the old worktree still holds (uncommitted files, unpushed commits), and marks the old one
-- discarded: every ./zn command run there (an old process that wakes up) refuses and says so. Only a lost claim can be
-- taken over. Time is ZN_NOW. Fixture under .cache/c0265-discard.
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local heartbeat = require("@znile/engine/heartbeat")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local h: fakecli.Harness
local T0 = os.time()
local STALE = heartbeat.STALE
local LATE = T0 + 3 * STALE
local P = "pickman/.tracker/issues"
local NAME = "prep-hello"

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function zn(cwd: string, args: { string }, now: number?): fixture.Result
	local env: { [string]: string } = {
		FAKE_DIR = h.fakes,
		PATH = `{h.bin}:{process.env.PATH}`,
		ZN_AGENT_TOKEN_FILE = h.token,
		ZN_WATERMARK_DIR = `{h.f.base}/watermark`,
	}
	if now then
		env.ZN_NOW = tostring(now)
	end
	return fixture.exec(cwd, "bash", { "scripts/tracker.sh", table.unpack(args) }, { env = env })
end
local function must(r: fixture.Result, what: string): string
	if not r.ok then
		error(`{what} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return r.stdout
end
local function trim(s: string): string
	return (string.gsub(s, "%s+$", ""))
end
local function dir(name: string): string
	return `{h.f.main}/.worktree/{name}`
end
local function branchOf(path: string): string
	return trim(fixture.git(path, { "branch", "--show-current" }))
end
local function originTip(): string
	return trim(fixture.git(h.f.origin, { "rev-parse", `refs/heads/{NAME}` }))
end

return t.spec("c0265 discarded worktrees", function(it)
	it(
		"sets up a claim worked in a worktree whose branch is pushed, with an unpushed commit and a dirty file",
		function()
			h = fakecli.new("c0265-discard", {
				[`{P}/c0010/c0010.md`] = trackerfix.stub("c0010", "c0010", "new-a-b-c"),
			})
			fs.writeFile(`{h.bin}/gh`, '#!/bin/sh\n[ "$1" = pr ] && [ "$2" = list ] && echo "[]"\nexit 0\n')
			process.exec("chmod", { "+x", `{h.bin}/gh` })
			local wt = trim(must(zn(h.f.main, { "worktree", NAME }), "worktree"))
			must(zn(wt, { "status", "c0010", "preparing" }, T0), "claim")
			fs.writeFile(`{wt}/pushed.txt`, "pushed work\n")
			fixture.git(wt, { "add", "-A" })
			fixture.git(wt, { "commit", "-q", "-m", "pushed work" })
			fixture.git(wt, { "push", "-q", "origin", `HEAD:refs/heads/{NAME}` })
			fs.writeFile(`{wt}/unpushed.txt`, "local only\n")
			fixture.git(wt, { "add", "-A" })
			fixture.git(wt, { "commit", "-q", "-m", "unpushed work" })
			fs.writeFile(`{wt}/dirty.txt`, "not even committed\n")
		end
	)

	it("a live claim cannot be taken over, and a name with no worktree is just created", function()
		local live = zn(h.f.main, { "worktree", NAME, "--takeover" }, T0 + 60)
		t.expect(live.ok).toBe(false)
		t.expect(has(live.stderr, "alive")).toBe(true)
		t.expect(fs.isDir(dir(`{NAME}-1`))).toBe(false)
		t.expect(fs.isDir(dir("prep-fresh"))).toBe(false)
		must(zn(h.f.main, { "worktree", "prep-fresh", "--takeover" }, LATE), "no worktree to take over")
		t.expect(fs.isDir(dir("prep-fresh"))).toBe(true)
	end)

	it(
		"a lost claim's worktree is moved aside as -1 with its branch renamed, and a fresh worktree continues the pushed branch",
		function()
			local pushed = originTip()
			local r = zn(h.f.main, { "worktree", NAME, "--takeover" }, LATE)
			must(r, "takeover")
			t.expect(trim(r.stdout)).toBe(dir(NAME)) -- the taker's path is the original name
			t.expect(fs.isDir(dir(`{NAME}-1`))).toBe(true)
			t.expect(branchOf(dir(`{NAME}-1`))).toBe(`{NAME}-1`) -- the old branch gave up its name
			t.expect(branchOf(dir(NAME))).toBe(NAME) -- the taker keeps the PR's branch name
			t.expect(trim(fixture.git(dir(NAME), { "rev-parse", "HEAD" }))).toBe(pushed) -- it continues the pushed work
			t.expect(originTip()).toBe(pushed) -- the PR head is untouched
			t.expect(fs.isFile(`{dir(NAME)}/pushed.txt`)).toBe(true)
			-- nothing is lost: the old worktree keeps its dirty file and its unpushed commit, and the message says so
			t.expect(fs.isFile(`{dir(`{NAME}-1`)}/dirty.txt`)).toBe(true)
			t.expect(fs.isFile(`{dir(`{NAME}-1`)}/unpushed.txt`)).toBe(true)
			t.expect(has(r.stderr, `{NAME}-1`)).toBe(true)
			t.expect(has(r.stderr, "dirty.txt")).toBe(true)
			t.expect(has(r.stderr, "unpushed work")).toBe(true)
		end
	)

	it(
		"the old process that wakes up is told it was discarded, by every command, the beat included",
		function()
			local old = dir(`{NAME}-1`)
			for _, args in
				{ { "lessons", "--tags" }, { "beat", "c0010" }, { "status", "c0010", "preparing" } }
			do
				local r = zn(old, args, LATE + 5)
				t.expect(r.ok).toBe(false)
				t.expect(has(r.stderr, "was discarded")).toBe(true)
				t.expect(has(r.stderr, "pick up something new")).toBe(true)
			end
			t.expect(fs.isFile(`{old}/.cache/discarded`)).toBe(true)
		end
	)

	it(
		"the taker claims in the fresh worktree, and ./zn busy still names the discarded one while it holds work",
		function()
			must(zn(dir(NAME), { "status", "c0010", "preparing" }, LATE), "the takeover claim")
			local busy = zn(h.f.main, { "busy", "pickman", "z-nile" }, LATE)
			t.expect(has(busy.stdout .. busy.stderr, `{NAME}-1`)).toBe(true)
		end
	)

	it("the next takeover numbers its discard -2 and leaves -1 alone", function()
		local again = LATE + 3 * STALE
		must(zn(h.f.main, { "worktree", NAME, "--takeover" }, again), "second takeover")
		t.expect(fs.isDir(dir(`{NAME}-2`))).toBe(true)
		t.expect(fs.isDir(dir(`{NAME}-1`))).toBe(true)
		t.expect(branchOf(dir(`{NAME}-2`))).toBe(`{NAME}-2`)
		t.expect(branchOf(dir(NAME))).toBe(NAME)
		local told = zn(dir(`{NAME}-2`), { "lessons", "--tags" }, again + 5)
		t.expect(told.ok).toBe(false)
		t.expect(has(told.stderr, "was discarded")).toBe(true)
	end)
end)
