--!strict
-- c0254 AC2, AC3: a raft's layer branch on two hosts. Two clones of one bare origin under .cache/c0254-layer stand for two machines.
-- Host A holds raft R0010 (its claim memory is the stand-in for what the dispatcher, or c0274's adopt, writes), commits a layer,
-- and is pushed. Host B takes the raft over (a new stamp on origin) and pushes the layer on top. Host A, which has not heard, then
-- commits, finishes and restacks: nothing it does moves B's commit, the refusal is c0274's own words, and the exit says so. A
-- numbered copy of A's worktree that remembers no claim is refused too. Everything is a fixture: no real host, no real remote.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local MINE = "active-quiet-copper-falcon"
local THEIRS = "active-brisk-otter-lynx"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
local BRANCH = "R0010/1/c0030"

local f: trackerfix.Fixture
local wtA, wtB = "", ""

local function raftDoc(stamp: string): string
	return `---\nid: R0010\ntype: chore\ntitle: Carry\nslug: carry\nsingle: false\nissues: [c0030]\ndesign: ready\ncreated: 2026-11-10\nstatus: {stamp}\n---\n\n# R0010\n`
end
local function issueDoc(stamp: string): string
	return `---\nid: c0030\ntype: chore\ntitle: c0030\nslug: c0030\nraft: R0010\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-11-10\nstatus: {stamp}\n---\n\n# c0030\n`
end
local function tipOf(dir: string, ref: string): string
	local r = fixture.exec(dir, "git", { "rev-parse", "--verify", "--quiet", ref })
	return if r.ok then (string.gsub(r.stdout, "%s+$", "")) else ""
end
local function has(text: string?, needle: string): boolean
	return text ~= nil and string.find(text, needle, 1, true) ~= nil
end
local function remember(wt: string, stamp: string)
	fs.writeDir(`{wt}/.cache`)
	fs.writeFile(`{wt}/.cache/tracker-stamp-R0010`, stamp)
end

return t.spec("c0254 a raft's layer on two hosts", function(it)
	it("sets up an active raft, host A's worktree on its first layer and the claim A remembers", function()
		f = trackerfix.new("c0254-layer", {
			[".gitignore"] = ".cache/\n.worktree/\n.DS_Store\n",
			["pickman/.tracker/architecture.md"] = "# Architecture\n",
			["pickman/.tracker/rafts/active/R0010/R0010.md"] = raftDoc(MINE),
			["pickman/.tracker/rafts/active/R0010/check.sh"] = CHECK,
			["pickman/.tracker/issues/active/c0030/c0030.md"] = issueDoc(MINE),
			["pickman/.tracker/issues/active/c0030/check.sh"] = CHECK,
		})
		wtA = f.main .. "/.worktree/R0010"
		fixture.git(f.main, { "worktree", "add", "-b", BRANCH, wtA, "origin/main" })
		remember(wtA, MINE)
	end)

	it("AC3: a layer commit is pushed to its own branch, and main does not move", function()
		local main0 = tipOf(f.origin, "main")
		fs.writeFile(`{wtA}/one.txt`, "one\n")
		local r = trackerfix.tr(f, wtA, { "commit", "-m", "layer one" }, { ZN_CLI = "claude" })
		t.expect(r.code).toBe(0)
		t.expect(tipOf(f.origin, BRANCH)).toBe(tipOf(wtA, "HEAD"))
		t.expect(tipOf(f.origin, "main")).toBe(main0)
	end)

	it("sets up host B as the taker: a new stamp on origin, and B's worktree on the pushed layer", function()
		trackerfix.elsewhere(f, {
			["pickman/.tracker/rafts/active/R0010/R0010.md"] = raftDoc(THEIRS),
			["pickman/.tracker/issues/active/c0030/c0030.md"] = issueDoc(THEIRS),
		}, "tracker: R0010 taken over")
		wtB = f.other .. "/.worktree/R0010"
		fixture.git(f.other, { "fetch", "-q", "origin" })
		fixture.git(f.other, { "worktree", "add", "--track", "-b", BRANCH, wtB, `origin/{BRANCH}` })
		remember(wtB, THEIRS)
		fs.writeFile(`{wtB}/taker.txt`, "from the taker\n")
		t.expect(trackerfix.tr(f, wtB, { "commit", "-m", "taker adds a file" }, { ZN_CLI = "grok" }).code)
			.toBe(0)
		t.expect(tipOf(f.origin, BRANCH)).toBe(tipOf(wtB, "HEAD"))
	end)

	it(
		"AC2, AC3: host A's next commit stands, is refused with c0274's words, exits 7, and origin keeps the taker's tip",
		function()
			local theirs = tipOf(f.origin, BRANCH)
			local seenByA = tipOf(wtA, `refs/remotes/origin/{BRANCH}`)
			fs.writeFile(`{wtA}/late.txt`, "late\n")
			local r = trackerfix.tr(f, wtA, { "commit", "-m", "late layer commit" }, { ZN_CLI = "claude" })
			t.expect(r.code).toBe(7)
			t.expect(
				has(
					r.stderr,
					`R0010's claim was taken over (now {THEIRS}): this checkout's work is no longer the claim's; stop here (./zn lost lists lost work to pick up)`
				)
			).toBe(true)
			t.expect(has(r.stderr, "continue")).toBe(false)
			t.expect(has(r.stdout, "committed: late layer commit")).toBe(true)
			t.expect(tipOf(f.origin, BRANCH)).toBe(theirs)
			-- the lease ref finish and restack use is not what the per-commit read refreshed
			t.expect(tipOf(wtA, `refs/remotes/origin/{BRANCH}`)).toBe(seenByA)
			t.expect(tipOf(wtA, `refs/zn/seen/{BRANCH}`)).toBe(theirs)
		end
	)

	it(
		"AC2: host A's finish and restack are refused before they touch anything, and the taker's commit survives",
		function()
			local theirs = tipOf(f.origin, BRANCH)
			local fin = trackerfix.tr(f, wtA, { "finish", "c0030" })
			t.expect(fin.ok).toBe(false)
			t.expect(has(fin.stderr, "claim was taken over")).toBe(true)
			local rs = trackerfix.tr(f, wtA, { "restack", "R0010" })
			t.expect(rs.ok).toBe(false)
			t.expect(has(rs.stderr, "claim was taken over")).toBe(true)
			t.expect(tipOf(f.origin, BRANCH)).toBe(theirs)
			local files = fixture.git(f.origin, { "ls-tree", "-r", "--name-only", BRANCH })
			t.expect(has(files, "taker.txt")).toBe(true)
		end
	)

	it(
		"AC2: a numbered copy of the lost worktree remembers no claim and does not push the taken layer either",
		function()
			local theirs = tipOf(f.origin, BRANCH)
			local copy = f.main .. "/.worktree/R0010-1"
			fixture.git(f.main, { "fetch", "-q", "origin" })
			fixture.git(f.main, { "worktree", "add", "--detach", copy, `origin/{BRANCH}` })
			-- what c0277's numbered copy is: the taker's tip on the old branch's name, with no claim memory
			fixture.git(f.main, { "branch", "-m", BRANCH, `{BRANCH}-discarded-1` })
			fixture.git(copy, { "switch", "-q", "-c", BRANCH })
			fs.writeDir(`{copy}/.cache`)
			fs.writeFile(`{copy}/.cache/fresh`, "1700000000") -- what c0277's takeover leaves in a numbered copy
			fs.writeFile(`{copy}/copy.txt`, "copy\n")
			local r = trackerfix.tr(f, copy, { "commit", "-m", "from a copy that holds no claim" })
			t.expect(r.code).toBe(7)
			t.expect(has(r.stderr, "holds no claim")).toBe(true)
			t.expect(tipOf(f.origin, BRANCH)).toBe(theirs)
		end
	)
end)
