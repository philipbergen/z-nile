--!strict
-- c0265: taking over a lost claim discards the old worker's worktree and recovers its work (the user, 2026-11-08):
-- `./zn worktree <name> --takeover` leaves the old worktree at its path, marks it discarded and renames its branch, and
-- creates the numbered copy <name>-<n> (the next free number) on the original branch name, continuing the old agent's
-- PUSHED branch (so the PR head keeps working), listing what the old worktree still holds (uncommitted files, unpushed
-- commits). Every ./zn command run in the discarded worktree (an old process that wakes up) refuses and says so; a plain
-- `./zn worktree <name>` finds the copy, not the discarded one. Only a lost claim, in a worktree no taker is still
-- starting in, can be taken over. Time is ZN_NOW. Fixture under .cache/c0265-discard.
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
local GH =
	'#!/bin/sh\nif [ "$1" = pr ] && [ "$2" = list ]; then\n  [ -f "$FAKE_DIR/ghfail" ] && { echo "gh: fake failure" >&2; exit 1; }\n  cat "$FAKE_DIR/prs.json" 2>/dev/null || echo "[]"\n  exit 0\nfi\nexit 0\n'
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
				[`{P}/c0020/c0020.md`] = trackerfix.stub("c0020", "c0020", "preparing-lucky-violet-heron"), -- claimed, no worktree on this host
			})
			fs.writeFile(`{h.bin}/gh`, GH)
			process.exec("chmod", { "+x", `{h.bin}/gh` })
			local wt = trim(must(zn(h.f.main, { "worktree", NAME }), "worktree"))
			t.expect(wt).toBe(dir(NAME))
			must(zn(wt, { "status", "c0010", "preparing" }, T0), "claim")
			fs.writeFile(`{wt}/pickman/pushed.txt`, "pushed work\n")
			fixture.git(wt, { "add", "-A" })
			fixture.git(wt, { "commit", "-q", "-m", "pushed work" })
			fixture.git(wt, { "push", "-q", "origin", `HEAD:refs/heads/{NAME}` })
			fs.writeFile(`{wt}/pickman/unpushed.txt`, "local only\n")
			fixture.git(wt, { "add", "-A" })
			fixture.git(wt, { "commit", "-q", "-m", "unpushed work" })
			fs.writeFile(`{wt}/pickman/dirty.txt`, "not even committed\n")
		end
	)

	it("a live claim cannot be taken over, and a name with no worktree is just created", function()
		local live = zn(h.f.main, { "worktree", NAME, "--takeover" }, T0 + 60)
		t.expect(live.ok).toBe(false)
		t.expect(has(live.stderr, "alive")).toBe(true)
		t.expect(fs.isDir(dir(`{NAME}-1`))).toBe(false)
		must(zn(h.f.main, { "worktree", "prep-fresh", "--takeover" }, LATE), "no worktree to take over")
		t.expect(fs.isDir(dir("prep-fresh"))).toBe(true)
		-- by id, with no worktree holding the claim: prep-<slug> is created, marked fresh; a second taker is refused
		local byId = zn(h.f.main, { "worktree", "--takeover", "c0020" }, LATE)
		must(byId, "by-id takeover with no worktree")
		t.expect(trim(byId.stdout)).toBe(dir("prep-c0020"))
		t.expect(fs.isFile(`{dir("prep-c0020")}/.cache/fresh`)).toBe(true)
		local twice = zn(h.f.main, { "worktree", "--takeover", "c0020" }, LATE)
		t.expect(twice.ok).toBe(false)
		t.expect(has(twice.stderr, "fresh")).toBe(true)
	end)

	it(
		"a parked claim, an unreadable verdict and a worktree with no claim memory are refused and nothing moves",
		function()
			fs.writeFile(`{h.fakes}/prs.json`, '[{"title":"tracker: prep c0010","headRefName":"x"}]')
			local parked = zn(h.f.main, { "worktree", NAME, "--takeover" }, LATE)
			t.expect(parked.ok).toBe(false)
			t.expect(has(parked.stderr, "parked")).toBe(true)
			fs.writeFile(`{h.fakes}/prs.json`, "[]")
			fs.writeFile(`{h.fakes}/ghfail`, "1")
			local blind = zn(h.f.main, { "worktree", NAME, "--takeover" }, LATE)
			t.expect(blind.ok).toBe(false)
			t.expect(has(blind.stderr, "no heartbeat verdict")).toBe(true)
			fs.removeFile(`{h.fakes}/ghfail`)
			local young = zn(h.f.main, { "worktree", "prep-fresh", "--takeover" }, LATE) -- created by a takeover: a taker is starting in it
			t.expect(young.ok).toBe(false)
			t.expect(has(young.stderr, "fresh")).toBe(true)
			must(zn(h.f.main, { "worktree", "prep-plain" }), "a plain worktree") -- no claim memory, no fresh marker
			local none = zn(h.f.main, { "worktree", "prep-plain", "--takeover" }, LATE)
			t.expect(none.ok).toBe(false)
			t.expect(has(none.stderr, "--item")).toBe(true)
			-- --item is accepted only for the item's own branch: prep-plain is an unrelated worktree with no claim
			local unrelated =
				zn(h.f.main, { "worktree", "prep-plain", "--takeover", "--item", "c0010" }, LATE)
			t.expect(unrelated.ok).toBe(false)
			t.expect(has(unrelated.stderr, "prep-plain")).toBe(true)
			t.expect(branchOf(dir("prep-plain"))).toBe("prep-plain")
			t.expect(fs.isDir(dir(`{NAME}-1`))).toBe(false)
			t.expect(branchOf(dir(NAME))).toBe(NAME)
		end
	)

	it(
		"a lost claim's worktree is marked discarded and a numbered copy continues the pushed branch",
		function()
			local pushed = originTip()
			-- the claim memory of a worktree made before this lands is only tracker-claim-<id>
			fs.removeFile(`{dir(NAME)}/.cache/tracker-stamp-c0010`)
			local r = zn(h.f.main, { "worktree", NAME, "--takeover" }, LATE)
			must(r, "takeover")
			t.expect(trim(r.stdout)).toBe(dir(`{NAME}-1`)) -- the taker works in the numbered copy
			t.expect(branchOf(dir(`{NAME}-1`))).toBe(NAME) -- which keeps the PR's branch name
			t.expect(branchOf(dir(NAME))).toBe(`{NAME}-discarded-1`) -- the old worktree's branch gave up its name
			t.expect(trim(fixture.git(dir(`{NAME}-1`), { "rev-parse", "HEAD" }))).toBe(pushed) -- it continues the pushed work
			t.expect(originTip()).toBe(pushed) -- the PR head is untouched
			t.expect(fs.isFile(`{dir(`{NAME}-1`)}/pickman/pushed.txt`)).toBe(true)
			t.expect(fs.isFile(`{dir(`{NAME}-1`)}/.cache/fresh`)).toBe(true)
			-- nothing is lost: the old worktree keeps its dirty file and its unpushed commit, and the message says so
			t.expect(fs.isFile(`{dir(NAME)}/pickman/dirty.txt`)).toBe(true)
			t.expect(fs.isFile(`{dir(NAME)}/pickman/unpushed.txt`)).toBe(true)
			t.expect(has(r.stderr, `discarded worktree: {dir(NAME)}`)).toBe(true)
			t.expect(has(r.stderr, "dirty.txt")).toBe(true)
			t.expect(has(r.stderr, "unpushed work")).toBe(true)
			-- a plain lookup finds the copy, never the discarded worktree
			t.expect(trim(must(zn(h.f.main, { "worktree", NAME }), "worktree"))).toBe(dir(`{NAME}-1`))
			-- a second taker cannot discard the copy while the first is still starting in it
			local second = zn(h.f.main, { "worktree", NAME, "--takeover" }, LATE)
			t.expect(second.ok).toBe(false)
			t.expect(has(second.stderr, "fresh")).toBe(true)
			local byIdTwice = zn(h.f.main, { "worktree", "--takeover", "c0010" }, LATE)
			t.expect(byIdTwice.ok).toBe(false)
			t.expect(has(byIdTwice.stderr, "fresh")).toBe(true)
			-- the lookup keeps its old refusal for a branch checked out elsewhere (c0005): `worktree main` is still refused
			local main = zn(h.f.main, { "worktree", "main" })
			t.expect(main.ok).toBe(false)
			t.expect(has(main.stderr, "already used by worktree at")).toBe(true)
		end
	)

	it(
		"the old process that wakes up is told it was discarded, by every command, the beat included",
		function()
			local old = dir(NAME)
			for _, args in
				{ { "lessons", "--tags" }, { "beat", "c0010" }, { "status", "c0010", "preparing" } }
			do
				local r = zn(old, args, LATE + 5)
				t.expect(r.ok).toBe(false)
				t.expect(has(r.stderr, "was discarded")).toBe(true)
				t.expect(has(r.stderr, "pick up something new")).toBe(true)
			end
			t.expect(fs.isFile(`{old}/.cache/discarded`)).toBe(true)
			-- cleanup is not refused: the session-end reaper of a session in this directory still runs
			local reap = zn(old, { "reap", "--quiet" }, LATE + 5)
			t.expect(has(reap.stderr, "was discarded")).toBe(false)
		end
	)

	it(
		"the taker claims in its copy, and ./zn busy names the discarded worktree while it holds changes",
		function()
			must(zn(dir(`{NAME}-1`), { "status", "c0010", "preparing" }, LATE), "the takeover claim")
			t.expect(fs.isFile(`{dir(`{NAME}-1`)}/.cache/fresh`)).toBe(false) -- it holds claim memory now
			local busy = zn(h.f.main, { "busy", "pickman" }, LATE)
			t.expect(has(busy.stdout .. busy.stderr, `{NAME}-discarded-1`)).toBe(true) -- its renamed branch holds the unpushed commit
		end
	)

	it(
		"the next takeover discards the copy and numbers the new one -2, leaving the first discarded worktree alone",
		function()
			local again = LATE + 3 * STALE
			local r = zn(h.f.main, { "worktree", "--takeover", "c0010" }, again) -- by id: found by its claim
			must(r, "second takeover")
			t.expect(trim(r.stdout)).toBe(dir(`{NAME}-2`))
			t.expect(branchOf(dir(`{NAME}-2`))).toBe(NAME)
			t.expect(branchOf(dir(`{NAME}-1`))).toBe(`{NAME}-discarded-2`)
			t.expect(branchOf(dir(NAME))).toBe(`{NAME}-discarded-1`) -- the first one is untouched
			local told = zn(dir(`{NAME}-1`), { "lessons", "--tags" }, again + 5)
			t.expect(told.ok).toBe(false)
			t.expect(has(told.stderr, "was discarded")).toBe(true)
			t.expect(trim(must(zn(h.f.main, { "worktree", NAME }), "worktree"))).toBe(dir(`{NAME}-2`))
			-- the copy had an upstream (origin/prep-hello): the discarded branch has none, so a bare push cannot move the PR head
			local upstream =
				fixture.exec(h.f.main, "git", { "config", "--get", `branch.{NAME}-discarded-2.remote` })
			t.expect(trim(upstream.stdout)).toBe("")
		end
	)

	it("a fresh copy whose taker never claimed can be taken over after the limit", function()
		local r = zn(h.f.main, { "worktree", "--takeover", "c0020" }, LATE + 2 * STALE)
		must(r, "takeover of a stale fresh copy")
		t.expect(trim(r.stdout)).toBe(dir("prep-c0020-1"))
	end)
end)
