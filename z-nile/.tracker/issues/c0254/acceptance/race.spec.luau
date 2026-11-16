--!strict
-- c0254 AC1, AC2, AC3, AC5: two hosts, one origin. Two clones of one bare origin under .cache/c0254-race stand for two machines
-- (a fixture, never a real host or remote). Both start from the same origin/main; host A claims a draft issue; host B's claim
-- of the same issue is refused and publishes nothing; the claim commit says who made it; the lost host's prep branch is
-- pushed after every commit and stops being pushed once its claim is taken over; the taker on host B continues in a worktree of
-- its own from the pushed branch.
local board = require("@znile/engine/board")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")
local xhost = require("@znile/engine/xhost")

local DOC = "pickman/.tracker/issues/c0010/c0010.md"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
local DOC2 = "pickman/.tracker/issues/c0011/c0011.md"
local DRAFT =
	"---\nid: c0010\ntype: chore\ntitle: c0010\nslug: c0010\nraft: \ndepends_on: []\nemergent: false\ndesign: draft\ncreated: 2026-10-20\nstatus: new-amber-otter-lynx\n---\n\n# c0010\n"

local f: trackerfix.Fixture
local wtA, wtB = "", ""
local HOST_A = { ZN_CLI = "claude", ZN_MODEL = "claude-opus-5-5" }

local function onOrigin(path: string): string
	return fixture.git(f.origin, { "show", `main:{path}` })
end
local function stampOnOrigin(): string
	return string.match(onOrigin(DOC), "\nstatus: (%S+)\n") or ""
end
local function claimCommits(): number
	local out = fixture.git(f.origin, { "log", "main", "--format=%s", "--grep=^tracker: c0010 preparing" })
	local n = 0
	for _ in string.gmatch(out, "[^\n]+") do
		n += 1
	end
	return n
end
-- origin's tip of a branch, or "" when it has none (so a missing push is a failed assertion, not a git error)
local function originTip(branch: string): string
	local r = fixture.exec(f.origin, "git", { "rev-parse", "--verify", "--quiet", branch })
	return if r.ok then (string.gsub(r.stdout, "%s+$", "")) else ""
end
local function has(text: string?, needle: string): boolean
	return text ~= nil and string.find(text, needle, 1, true) ~= nil
end

return t.spec("c0254 two hosts claim one issue", function(it)
	it("sets up one origin, two clones and a prep worktree on each", function()
		f = trackerfix.new("c0254-race", {
			[".gitignore"] = ".cache/\n.worktree/\n.DS_Store\n",
			["pickman/.tracker/architecture.md"] = "# Architecture\n",
			[DOC] = DRAFT,
			["pickman/.tracker/issues/c0010/check.sh"] = CHECK,
			[DOC2] = (string.gsub(DRAFT, "c0010", "c0011")),
			["pickman/.tracker/issues/c0011/check.sh"] = CHECK,
		})
		wtA = trackerfix.trOk(f, f.main, { "worktree", "prep-c0010" })
		wtB = trackerfix.trOk(f, f.other, { "worktree", "prep-c0010" })
		t.expect(wtA ~= wtB).toBe(true)
	end)

	it("AC1: the claim is the push: host A wins, host B is refused and publishes nothing", function()
		local before = claimCommits()
		t.expect(before).toBe(0)
		local a = trackerfix.tr(f, wtA, { "status", "c0010", "preparing" }, HOST_A)
		t.expect(a.ok).toBe(true)
		t.expect(claimCommits()).toBe(1)
		local stamp = stampOnOrigin()
		t.expect(string.sub(stamp, 1, 10)).toBe("preparing-")
		local tip = fixture.git(f.origin, { "rev-parse", "main" })
		local b = trackerfix.tr(
			f,
			wtB,
			{ "status", "c0010", "preparing" },
			{ ZN_CLI = "grok", ZN_MODEL = "grok-4.7" }
		)
		t.expect(b.ok).toBe(false)
		t.expect(has(b.stderr, "cannot move to preparing")).toBe(true)
		t.expect(fixture.git(f.origin, { "rev-parse", "main" })).toBe(tip)
		t.expect(claimCommits()).toBe(1)
		t.expect(stampOnOrigin()).toBe(stamp)
	end)

	it("AC5: the claim commit says who made it, and the board reads it back", function()
		local body =
			fixture.git(f.origin, { "log", "main", "-1", "--format=%B", "--grep=^tracker: c0010 preparing" })
		local line = string.match(body, "(Worker: [^\n]+)") :: string
		t.expect(line ~= nil).toBe(true)
		local who = xhost.parseTrailer(line)
		t.expect(who ~= nil and who.id or "").toBe("c0010")
		t.expect(who ~= nil and who.cli or "").toBe("claude")
		t.expect(who ~= nil and who.model or "").toBe("claude-opus-5-5")
		t.expect(who ~= nil and who.stamp or "").toBe(stampOnOrigin())
		t.expect(who ~= nil and who.host ~= "" or false).toBe(true)
		-- the board's read, from a clone that fetched
		fixture.git(f.other, { "fetch", "-q", "origin" })
		local facts = board.readFacts(f.other)
		local holders = xhost.holders(facts.workers or {}, { c0010 = stampOnOrigin() })
		t.expect(holders.c0010 ~= nil).toBe(true)
		t.expect(holders.c0010.cli).toBe("claude")
		-- and no holder for a stamp that is not the one on origin now
		t.expect(xhost.holders(facts.workers or {}, { c0010 = "preparing-not-the-one" }).c0010).toBe(nil)
	end)

	it("AC5: the board's card for the issue says which worker holds it", function()
		fixture.git(f.main, { "pull", "-q", "origin", "main" })
		local facts = board.readFacts(f.main)
		local model = board.collect(`{f.main}/pickman/.tracker`, f.main, facts)
		local card
		for _, issue in model.issues do
			if issue.id == "c0010" then
				card = issue
			end
		end
		t.expect(card ~= nil).toBe(true)
		t.expect(string.find(card.held or "", "(claude, claude-opus-5-5)", 1, true) ~= nil).toBe(true)
	end)

	it("AC3: host A's prep commits are pushed one by one, the first sets the upstream", function()
		fs.writeFile(`{wtA}/pickman/.tracker/issues/c0010/notes-1.md`, "first\n")
		local c1 = trackerfix.tr(f, wtA, { "commit", "-m", "tracker: prep c0010 draft 1" }, HOST_A)
		t.expect(c1.ok).toBe(true)
		local tip1 = fixture.git(wtA, { "rev-parse", "HEAD" })
		t.expect(originTip("prep-c0010")).toBe(tip1)
		fs.writeFile(`{wtA}/pickman/.tracker/issues/c0010/notes-2.md`, "second\n")
		local c2 = trackerfix.tr(f, wtA, { "commit", "-m", "tracker: prep c0010 draft 2" }, HOST_A)
		t.expect(c2.ok).toBe(true)
		local tip2 = fixture.git(wtA, { "rev-parse", "HEAD" })
		t.expect(tip2 ~= tip1).toBe(true)
		t.expect(originTip("prep-c0010")).toBe(tip2)
	end)

	it("AC2: a taker on host B continues in a worktree of its own, built from the pushed branch", function()
		local tipA = fixture.git(wtA, { "rev-parse", "HEAD" })
		-- host B's earlier prep worktree knows nothing of A's work; the taker's is built from origin's branch in B's own clone
		fixture.git(f.other, { "worktree", "remove", "--force", wtB })
		fixture.git(f.other, { "branch", "-D", "prep-c0010" })
		local taker = trackerfix.trOk(f, f.other, { "worktree", "prep-c0010" })
		t.expect(string.sub(taker, 1, #f.other + 1)).toBe(f.other .. "/")
		t.expect(taker ~= wtA).toBe(true)
		t.expect(fixture.git(taker, { "rev-parse", "HEAD" })).toBe(tipA)
		t.expect(fs.isFile(`{taker}/pickman/.tracker/issues/c0010/notes-2.md`)).toBe(true)
		-- host A's worktree is as it was: nothing of host B reached it
		t.expect(fixture.git(wtA, { "rev-parse", "HEAD" })).toBe(tipA)
		t.expect(fixture.git(wtA, { "status", "--porcelain" })).toBe("")
	end)

	it(
		"AC2, AC3: once host B holds the claim, host A's next commit stays local and origin keeps B's branch",
		function()
			local taker = trackerfix.trOk(f, f.other, { "worktree", "prep-c0010" })
			-- the takeover as the heartbeat raft publishes it: the old claim gives way and host B claims in one step
			local gave = trackerfix.tr(f, taker, { "status", "c0010", "new" })
			t.expect(gave.ok).toBe(true)
			local took = trackerfix.tr(
				f,
				taker,
				{ "status", "c0010", "preparing" },
				{ ZN_CLI = "grok", ZN_MODEL = "grok-4.7" }
			)
			t.expect(took.ok).toBe(true)
			fs.writeFile(`{taker}/pickman/.tracker/issues/c0010/notes-3.md`, "from the taker\n")
			local pushedB = trackerfix.tr(
				f,
				taker,
				{ "commit", "-m", "tracker: prep c0010 draft 3" },
				{ ZN_CLI = "grok" }
			)
			t.expect(pushedB.ok).toBe(true)
			local tipB = fixture.git(taker, { "rev-parse", "HEAD" })
			t.expect(originTip("prep-c0010")).toBe(tipB)
			-- host A wakes up and commits: the commit stands, the push is refused and says why
			fs.writeFile(`{wtA}/pickman/.tracker/issues/c0010/notes-late.md`, "late\n")
			local late = trackerfix.tr(f, wtA, { "commit", "-m", "tracker: prep c0010 late" }, HOST_A)
			t.expect(late.ok).toBe(true)
			t.expect(has(late.stderr, "was taken over by another worker")).toBe(true)
			t.expect(originTip("prep-c0010")).toBe(tipB)
			t.expect(fixture.git(wtA, { "rev-parse", "HEAD" }) ~= tipB).toBe(true)
			-- the board now names host B's worker, not host A's
			fixture.git(f.main, { "fetch", "-q", "origin" })
			local facts = board.readFacts(f.main)
			local holders = xhost.holders(facts.workers or {}, { c0010 = stampOnOrigin() })
			t.expect(holders.c0010.cli).toBe("grok")
		end
	)

	it(
		"AC2, AC3: a worker that still holds its claim does not push over commits origin has and it lacks",
		function()
			local a = trackerfix.trOk(f, f.main, { "worktree", "prep-c0011" })
			t.expect(trackerfix.tr(f, a, { "status", "c0011", "preparing" }, HOST_A).ok).toBe(true)
			fs.writeFile(`{a}/pickman/.tracker/issues/c0011/n-1.md`, "one\n")
			t.expect(trackerfix.tr(f, a, { "commit", "-m", "tracker: prep c0011 one" }, HOST_A).ok).toBe(true)
			local pushed = originTip("prep-c0011")
			t.expect(pushed).toBe(fixture.git(a, { "rev-parse", "HEAD" }))
			-- another worker (a person on host B) pushes a commit to the same branch
			local b = trackerfix.trOk(f, f.other, { "worktree", "prep-c0011" })
			fs.writeFile(`{b}/pickman/.tracker/issues/c0011/n-b.md`, "from b\n")
			fixture.git(b, { "add", "-A" })
			fixture.git(b, { "commit", "-q", "-m", "b adds a file" })
			fixture.git(b, { "push", "-q", "origin", "HEAD:prep-c0011" })
			local theirs = originTip("prep-c0011")
			t.expect(theirs ~= pushed).toBe(true)
			-- host A, claim intact, commits again: the commit stands and the push is refused
			fs.writeFile(`{a}/pickman/.tracker/issues/c0011/n-2.md`, "two\n")
			local c = trackerfix.tr(f, a, { "commit", "-m", "tracker: prep c0011 two" }, HOST_A)
			t.expect(c.ok).toBe(true)
			t.expect(has(c.stderr, "commit(s) this checkout lacks")).toBe(true)
			t.expect(originTip("prep-c0011")).toBe(theirs)
		end
	)
end)
