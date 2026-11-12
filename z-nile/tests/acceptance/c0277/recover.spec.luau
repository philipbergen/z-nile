--!strict
-- c0277: a takeover RECOVERS the old worker's work, it does not just discard it (the user, 2026-11-08: "I assume that
-- there is a point in trying to recover the work and not just discarding it"). Pushed commits are in the taker's copy,
-- unpushed commits stay on the renamed branch and uncommitted files stay in the old worktree, all three are shown to the
-- taker, and the commands the note offers work. Time is ZN_NOW. Fixture under .cache/c0277-recover.
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local heartbeat = require("@znile/engine/heartbeat")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local h: fakecli.Harness
local T0 = os.time()
local LATE = T0 + 3 * heartbeat.STALE
local P = "pickman/.tracker/issues"
local GH =
	'#!/bin/sh\nif [ "$1" = pr ] && [ "$2" = list ]; then\n  cat "$FAKE_DIR/prs.json" 2>/dev/null || echo "[]"\n  exit 0\nfi\nexit 0\n'
local MARKS = "." .. "cache/tracker-beats"
local BEATER = "." .. "cache/tracker-beater"
local DISCARDED = "." .. "cache/discarded"

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
local function gone(name: string, n: number): string -- the renamed directory of a discarded worktree
	return dir(`{name}-discarded-{n}`)
end
local function commit(wt: string, file: string, text: string, subject: string)
	fs.writeFile(`{wt}/pickman/{file}`, text)
	fixture.git(wt, { "add", "-A" })
	fixture.git(wt, { "commit", "-q", "-m", subject })
end
-- the command the note offers for the unpushed commits, run as written
local function cherryPick(note: string): (string, string)
	local copy, range = string.match(note, "git %-C (%S+) cherry%-pick (%S+)%)")
	if not copy or not range then
		error(`the note offers no cherry-pick command:\n{note}`, 2)
	end
	fixture.git(copy, { "cherry-pick", range })
	return copy, range
end

return t.spec("c0277 recovering a discarded worktree's work", function(it)
	it(
		"sets up three old workers: one with pushed, unpushed and uncommitted work, one never pushed, one raft",
		function()
			h = fakecli.new("c0277-recover", {
				[`{P}/c0010/c0010.md`] = trackerfix.stub("c0010", "c0010", "new-a-b-c"),
				[`{P}/c0020/c0020.md`] = trackerfix.stub("c0020", "c0020", "new-a-b-c"),
				[`{P}/c0030/c0030.md`] = trackerfix.stub("c0030", "c0030", "new-a-b-c"),
			})
			fs.writeFile(`{h.bin}/gh`, GH)
			process.exec("chmod", { "+x", `{h.bin}/gh` })
			-- prep-keep: a pushed commit, an unpushed commit, a changed tracked file and an untracked one
			local keep = trim(must(zn(h.f.main, { "worktree", "prep-keep" }), "worktree"))
			must(zn(keep, { "status", "c0010", "preparing" }, T0), "claim c0010")
			commit(keep, "pushed.txt", "pushed v1\n", "pushed work")
			fixture.git(keep, { "push", "-q", "origin", "HEAD:refs/heads/prep-keep" })
			commit(keep, "unpushed.txt", "local only\n", "unpushed work")
			fs.writeFile(`{keep}/pickman/pushed.txt`, "pushed v2, edited and not committed\n")
			fs.writeFile(`{keep}/pickman/untracked.txt`, "never added\n")
			-- prep-never: nothing was ever pushed
			local never = trim(must(zn(h.f.main, { "worktree", "prep-never" }), "worktree"))
			must(zn(never, { "status", "c0020", "preparing" }, T0), "claim c0020")
			commit(never, "never.txt", "only here\n", "never pushed work")
			-- raft-lost: a rafting claim with members, worked in a named worktree
			local raft = trim(must(zn(h.f.main, { "worktree", "raft-lost" }), "worktree"))
			must(
				zn(raft, { "new", "raft", "chore", "lostraft", "c0030", "--project", "pickman" }, T0),
				"new raft"
			)
			fs.writeFile(`{raft}/pickman/raft-note.txt`, "raft draft\n")
		end
	)

	it(
		"pushed commits are in the taker's copy, unpushed ones on the renamed branch, uncommitted files in place",
		function()
			local old = gone("prep-keep", 1)
			local pushedTip = trim(fixture.git(h.f.origin, { "rev-parse", "refs/heads/prep-keep" }))
			-- the old worker's beat marks are there before, and gone after
			t.expect(fs.isFile(`{dir("prep-keep")}/{MARKS}/c0010`)).toBe(true)
			local r = zn(h.f.main, { "worktree", "prep-keep", "--takeover" }, LATE)
			must(r, "takeover")
			local copy = dir("prep-keep-1")
			t.expect(trim(r.stdout)).toBe(copy)
			-- pushed: in the copy, at the pushed tip, and shown
			t.expect(trim(fixture.git(copy, { "rev-parse", "HEAD" }))).toBe(pushedTip)
			t.expect(fs.readFile(`{copy}/pickman/pushed.txt`)).toBe("pushed v1\n")
			t.expect(has(r.stderr, "pushed commits (the copy has them)")).toBe(true)
			t.expect(has(r.stderr, "pushed work")).toBe(true)
			-- unpushed: not in the copy, kept on the renamed branch, shown with the command to take it
			t.expect(fs.isFile(`{copy}/pickman/unpushed.txt`)).toBe(false)
			t.expect(
				has(
					trim(fixture.git(h.f.main, { "log", "--format=%s", "prep-keep-discarded-1" })),
					"unpushed work"
				)
			).toBe(true)
			t.expect(has(r.stderr, "unpushed commits (kept on prep-keep-discarded-1")).toBe(true)
			t.expect(has(r.stderr, "unpushed work")).toBe(true)
			-- only the unpushed commit is offered: the pushed one is in the copy already
			local offered = string.match(r.stderr, "unpushed commits.-\n(.-)uncommitted files") or ""
			t.expect(string.find(offered, "%x+ unpushed work") ~= nil).toBe(true)
			t.expect((string.find(offered, "%x+ pushed work"))).toBe(nil)
			-- uncommitted: both the edit of a tracked file and the untracked file stay, byte for byte, and are listed
			t.expect(fs.readFile(`{old}/pickman/pushed.txt`)).toBe("pushed v2, edited and not committed\n")
			t.expect(fs.readFile(`{old}/pickman/untracked.txt`)).toBe("never added\n")
			t.expect(has(r.stderr, "uncommitted files (kept in")).toBe(true)
			t.expect(has(r.stderr, "pickman/pushed.txt")).toBe(true)
			t.expect(has(r.stderr, "pickman/untracked.txt")).toBe(true)
			-- the remote branch is untouched and the old worktree's marks are gone
			t.expect(trim(fixture.git(h.f.origin, { "rev-parse", "refs/heads/prep-keep" }))).toBe(pushedTip)
			t.expect(fs.isFile(`{old}/{MARKS}/c0010`)).toBe(false)
			t.expect(fs.isFile(`{old}/{BEATER}/c0010`)).toBe(false)
			t.expect(fs.isFile(`{old}/{DISCARDED}`)).toBe(true)
			-- the command the note offers works as written: the unpushed commit lands in the copy
			cherryPick(r.stderr)
			t.expect(fs.readFile(`{copy}/pickman/unpushed.txt`)).toBe("local only\n")
			-- and the copy command for a file works too
			fs.writeFile(`{copy}/pickman/untracked.txt`, fs.readFile(`{old}/pickman/untracked.txt`))
			t.expect(fs.readFile(`{copy}/pickman/untracked.txt`)).toBe("never added\n")
		end
	)

	it("a branch that was never pushed gives a copy cut from main and a cherry-pick from main", function()
		local r = zn(h.f.main, { "worktree", "--takeover", "c0020" }, LATE)
		must(r, "takeover")
		local copy = dir("prep-never-1")
		t.expect(trim(r.stdout)).toBe(copy)
		t.expect(fs.isFile(`{copy}/pickman/never.txt`)).toBe(false)
		t.expect(has(r.stderr, "nothing was pushed")).toBe(true)
		t.expect(fs.isDir(dir("prep-never"))).toBe(false) -- the old path is gone
		t.expect(has(r.stderr, "never pushed work")).toBe(true)
		t.expect(has(r.stderr, "cherry-pick origin/main..prep-never-discarded-1")).toBe(true)
		t.expect(fs.isFile(`{gone("prep-never", 1)}/pickman/never.txt`)).toBe(true)
		cherryPick(r.stderr)
		t.expect(fs.readFile(`{copy}/pickman/never.txt`)).toBe("only here\n")
	end)

	it(
		"a rafting claim's worktree is taken over for the raft, and its commits and files are listed",
		function()
			local r = zn(h.f.main, { "worktree", "raft-lost", "--takeover" }, LATE)
			must(r, "takeover")
			t.expect(trim(r.stdout)).toBe(dir("raft-lost-1"))
			local marker = fs.readFile(`{gone("raft-lost", 1)}/{DISCARDED}`)
			local d = heartbeat.discardParse(marker)
			t.expect(d ~= nil).toBe(true)
			local items = table.concat((d :: heartbeat.Discard).items, " ")
			t.expect(items).toBe("R0010") -- the members share the raft's stamp: one claim
			t.expect(has(r.stderr, "tracker: R0010 members")).toBe(true) -- the worktree's unpushed commit, listed
			t.expect(has(r.stderr, "raft-note.txt")).toBe(true)
			t.expect(fs.readFile(`{gone("raft-lost", 1)}/pickman/raft-note.txt`)).toBe("raft draft\n")
		end
	)

	it("a detached worktree's own commits are kept on a branch of the discard's name", function()
		-- a raft with no layer yet is a detached worktree; it holds a commit of its own and the raft's claim
		must(zn(h.f.main, { "sync" }), "sync") -- the raft is on origin/main since `new raft` published it
		local raftWt = trim(must(zn(h.f.main, { "worktree", "R0010" }), "worktree"))
		t.expect(trim(fixture.git(raftWt, { "branch", "--show-current" }))).toBe("")
		local stamp = fs.readFile(`{gone("raft-lost", 1)}/` .. "." .. "cache/tracker-stamp-R0010")
		fs.writeDir(`{raftWt}/` .. "." .. "cache")
		fs.writeFile(`{raftWt}/` .. "." .. "cache/tracker-stamp-R0010", stamp)
		commit(raftWt, "detached.txt", "on no branch\n", "detached work")
		local r = zn(h.f.main, { "worktree", "R0010", "--takeover" }, LATE)
		must(r, "takeover")
		local copy = dir("R0010-1")
		t.expect(trim(r.stdout)).toBe(copy)
		t.expect(trim(fixture.git(copy, { "branch", "--show-current" }))).toBe("") -- the copy is detached, like a new raft worktree
		t.expect(fs.isFile(`{copy}/pickman/detached.txt`)).toBe(false)
		t.expect(has(r.stderr, "detached work")).toBe(true)
		t.expect(
			has(trim(fixture.git(h.f.main, { "log", "--format=%s", "R0010-discarded-1" })), "detached work")
		)
			.toBe(true)
		cherryPick(r.stderr)
		t.expect(fs.readFile(`{copy}/pickman/detached.txt`)).toBe("on no branch\n")
		-- a plain lookup finds the copy, not the discarded directory
		t.expect(trim(must(zn(h.f.main, { "worktree", "R0010" }), "worktree"))).toBe(copy)
	end)
end)
