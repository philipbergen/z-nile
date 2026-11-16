--!strict
-- c0254 AC1, AC2, AC3, AC5, AC7: two hosts, one origin. Two clones of one bare origin under .cache/c0254-race stand for two
-- machines (a fixture, never a real host or remote). Host B starts a prep worktree for an issue, then host A claims it: host B's
-- claim is refused and publishes nothing. The claim commit says who made it, A's prep branch is pushed after every commit to its
-- own branch name, and B's stale worktree is brought forward to A's push, never discarded. When B takes the claim over, A's
-- next commit stands but is refused with c0274's words and exit 7, a numbered copy that remembers no claim is refused, and A's
-- idle worktree is marked discarded, kept while B's claim lives, kept when it holds an unpushed commit, and removed once
-- the work has ended and nothing is left to recover. A push that fails is exit 8. Two hosts rafting one issue meet at the lease.
local board = require("@znile/engine/board")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")
local xhost = require("@znile/engine/xhost")

local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
local function draft(id: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {id}\nraft: \ndepends_on: []\nemergent: false\ndesign: draft\ncreated: 2026-10-20\nstatus: new-amber-otter-lynx\n---\n\n# {id}\n`
end
local function prepared(id: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {id}\nraft: \ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-10-20\nsize: 100\nstatus: prepared-quiet-copper-falcon\n---\n\n# {id}\n`
end
local function doc(id: string): string
	return `pickman/.tracker/issues/{id}/{id}.md`
end

local f: trackerfix.Fixture
local wtA, wtB = "", ""
local HOST_A = { ZN_CLI = "claude", ZN_MODEL = "claude-opus-5-5", ZN_ATTEMPT = "tokA" }
local HOST_B = { ZN_CLI = "grok", ZN_MODEL = "grok-4.7", ZN_ATTEMPT = "tokB" }

local function tip(branch: string): string
	local r = fixture.exec(f.origin, "git", { "rev-parse", "--verify", "--quiet", branch })
	return if r.ok then (string.gsub(r.stdout, "%s+$", "")) else ""
end
local function head(dir: string): string
	return fixture.git(dir, { "rev-parse", "HEAD" })
end
local function stampOf(id: string): string
	return string.match(fixture.git(f.origin, { "show", `main:{doc(id)}` }), "\nstatus: (%S+)\n") or ""
end
local function claimCommits(id: string): number
	local out = fixture.git(f.origin, { "log", "main", "--format=%s", `--grep=^tracker: {id} preparing` })
	local n = 0
	for _ in string.gmatch(out, "[^\n]+") do
		n += 1
	end
	return n
end
local function has(text: string?, needle: string): boolean
	return text ~= nil and string.find(text, needle, 1, true) ~= nil
end
local function commitIn(wt: string, id: string, name: string, env: { [string]: string }): fixture.Result
	fs.writeFile(`{wt}/pickman/.tracker/issues/{id}/{name}.md`, `{name}\n`)
	return trackerfix.tr(f, wt, { "commit", "-m", `tracker: prep {id} {name}` }, env)
end

return t.spec("c0254 two hosts claim one issue", function(it)
	it(
		"sets up one origin, two clones, and host B's prep worktree made by its claim step before host A claims",
		function()
			local seed: { [string]: string } = {
				[".gitignore"] = ".cache/\n.worktree/\n.DS_Store\n",
				["pickman/.tracker/architecture.md"] = "# Architecture\n",
			}
			for _, id in { "c0010", "c0011", "c0012", "c0013", "c0014" } do
				seed[doc(id)] = draft(id)
				seed[`pickman/.tracker/issues/{id}/check.sh`] = CHECK
			end
			for _, id in { "c0020", "c0021" } do
				seed[doc(id)] = prepared(id)
				seed[`pickman/.tracker/issues/{id}/check.sh`] = CHECK
			end
			f = trackerfix.new("c0254-race", seed)
			wtB = trackerfix.trOk(f, f.other, { "worktree", "prep-c0010" })
			wtA = trackerfix.trOk(f, f.main, { "worktree", "prep-c0010" })
			t.expect(wtA ~= wtB).toBe(true)
		end
	)

	it("AC1: the claim is the push: host A wins, host B is refused and publishes nothing", function()
		t.expect(claimCommits("c0010")).toBe(0)
		t.expect(trackerfix.tr(f, wtA, { "status", "c0010", "preparing" }, HOST_A).ok).toBe(true)
		t.expect(claimCommits("c0010")).toBe(1)
		local stamp = stampOf("c0010")
		t.expect(string.sub(stamp, 1, 10)).toBe("preparing-")
		local main0 = tip("main")
		local b = trackerfix.tr(f, wtB, { "status", "c0010", "preparing" }, HOST_B)
		t.expect(b.ok).toBe(false)
		t.expect(has(b.stderr, "cannot move to preparing")).toBe(true)
		t.expect(tip("main")).toBe(main0)
		t.expect(claimCommits("c0010")).toBe(1)
		t.expect(stampOf("c0010")).toBe(stamp)
	end)

	it("AC5: the claim commit says who made it, with the attempt, and the board reads it back", function()
		local body =
			fixture.git(f.origin, { "log", "main", "-1", "--format=%B", "--grep=^tracker: c0010 preparing" })
		local line = string.match(body, "(Worker: [^\n]+)") :: string
		local who = xhost.parseTrailer(line)
		t.expect(who ~= nil and who.id or "").toBe("c0010")
		t.expect(who ~= nil and who.cli or "").toBe("claude")
		t.expect(who ~= nil and who.model or "").toBe("claude-opus-5-5")
		t.expect(who ~= nil and who.attempt or "").toBe("tokA")
		t.expect(who ~= nil and who.stamp or "").toBe(stampOf("c0010"))
		fixture.git(f.main, { "pull", "-q", "origin", "main" })
		local facts = board.readFacts(f.main)
		local holders = xhost.holders(facts.workers or {}, { c0010 = stampOf("c0010") })
		t.expect(holders.c0010 ~= nil).toBe(true)
		t.expect(holders.c0010.cli).toBe("claude")
		local model = board.collect(`{f.main}/pickman/.tracker`, f.main, facts)
		local card
		for _, issue in model.issues do
			if issue.id == "c0010" then
				card = issue
			end
		end
		t.expect(card ~= nil).toBe(true)
		t.expect(has(card.held, "(claude, claude-opus-5-5)")).toBe(true)
		t.expect(xhost.holders(facts.workers or {}, { c0010 = "preparing-not-the-one" }).c0010).toBe(nil)
	end)

	it(
		"AC3: host A's prep commits are pushed one by one to the branch's own name, the first sets the upstream",
		function()
			local main0 = tip("main")
			local c1 = commitIn(wtA, "c0010", "notes-1", HOST_A)
			t.expect(c1.code).toBe(0)
			t.expect(tip("prep-c0010")).toBe(head(wtA))
			local c2 = commitIn(wtA, "c0010", "notes-2", HOST_A)
			t.expect(c2.code).toBe(0)
			t.expect(tip("prep-c0010")).toBe(head(wtA))
			t.expect(tip("main")).toBe(main0)
		end
	)

	it(
		"AC2: host B's stale worktree, made by its lost claim step, is brought forward to host A's push, not discarded",
		function()
			local tipA = head(wtA)
			t.expect(head(wtB) ~= tipA).toBe(true)
			local again = trackerfix.trOk(f, f.other, { "worktree", "prep-c0010" })
			t.expect(again).toBe(wtB)
			t.expect(head(wtB)).toBe(tipA)
			t.expect(fs.isFile(`{wtB}/pickman/.tracker/issues/c0010/notes-2.md`)).toBe(true)
			-- host A's worktree is as it was
			t.expect(head(wtA)).toBe(tipA)
			t.expect(fixture.git(wtA, { "status", "--porcelain" })).toBe("")
		end
	)

	it(
		"AC2: a local branch that has diverged from the pushed one is refused, and nothing local is discarded",
		function()
			local a = trackerfix.trOk(f, f.main, { "worktree", "prep-c0012" })
			t.expect(trackerfix.tr(f, a, { "status", "c0012", "preparing" }, HOST_A).ok).toBe(true)
			t.expect(commitIn(a, "c0012", "one", HOST_A).code).toBe(0)
			local b = trackerfix.trOk(f, f.other, { "worktree", "prep-c0012" })
			fs.writeFile(`{b}/pickman/.tracker/issues/c0012/local.md`, "b's own\n")
			fixture.git(b, { "add", "-A" })
			fixture.git(b, { "commit", "-q", "-m", "b's own commit" })
			local own = head(b)
			t.expect(commitIn(a, "c0012", "two", HOST_A).code).toBe(0)
			local r = trackerfix.tr(f, f.other, { "worktree", "prep-c0012" })
			t.expect(r.ok).toBe(false)
			t.expect(has(r.stderr, "has diverged from origin/prep-c0012")).toBe(true)
			t.expect(head(b)).toBe(own)
		end
	)

	it(
		"AC3: a worker that still holds its claim does not push over commits origin has and it lacks",
		function()
			local a = trackerfix.trOk(f, f.main, { "worktree", "prep-c0011" })
			t.expect(trackerfix.tr(f, a, { "status", "c0011", "preparing" }, HOST_A).ok).toBe(true)
			t.expect(commitIn(a, "c0011", "n-1", HOST_A).code).toBe(0)
			local pushed = tip("prep-c0011")
			t.expect(pushed).toBe(head(a))
			local b = trackerfix.trOk(f, f.other, { "worktree", "prep-c0011" })
			fs.writeFile(`{b}/pickman/.tracker/issues/c0011/n-b.md`, "from b\n")
			fixture.git(b, { "add", "-A" })
			fixture.git(b, { "commit", "-q", "-m", "b adds a file" })
			fixture.git(b, { "push", "-q", "origin", "HEAD:prep-c0011" })
			local theirs = tip("prep-c0011")
			t.expect(theirs ~= pushed).toBe(true)
			local c = commitIn(a, "c0011", "n-2", HOST_A)
			t.expect(c.code).toBe(7)
			t.expect(has(c.stderr, "commit(s) this checkout lacks")).toBe(true)
			t.expect(tip("prep-c0011")).toBe(theirs)
			t.expect(has(c.stdout, `committed: tracker: prep c0011 n-2`)).toBe(true)
		end
	)

	it(
		"AC1: a claim this checkout already holds is an idempotent success, so a session's own claim passes",
		function()
			local a = trackerfix.trOk(f, f.main, { "worktree", "prep-c0013" })
			t.expect(trackerfix.tr(f, a, { "status", "c0013", "preparing" }, HOST_A).ok).toBe(true)
			local stamp = stampOf("c0013")
			local again = trackerfix.tr(f, a, { "status", "c0013", "preparing" }, HOST_A)
			t.expect(again.ok).toBe(true)
			t.expect(has(again.stdout, "already claimed by this checkout")).toBe(true)
			t.expect(stampOf("c0013")).toBe(stamp)
			t.expect(claimCommits("c0013")).toBe(1)
		end
	)

	it(
		"AC3: the push goes to the branch's own name whatever push.default and the upstream say, and main does not move",
		function()
			local a = f.main .. "/.worktree/prep-c0013"
			fixture.git(a, { "branch", "--set-upstream-to=origin/main" })
			fixture.git(f.main, { "config", "push.default", "upstream" })
			local main0 = tip("main")
			local c = commitIn(a, "c0013", "one", HOST_A)
			t.expect(c.code).toBe(0)
			t.expect(tip("prep-c0013")).toBe(head(a))
			t.expect(tip("main")).toBe(main0)
			fixture.git(f.main, { "config", "--unset", "push.default" })
		end
	)

	it("AC3: a push that fails exits 8 after the commit, says so, and the next commit pushes both", function()
		local a = trackerfix.trOk(f, f.main, { "worktree", "prep-c0014" })
		t.expect(trackerfix.tr(f, a, { "status", "c0014", "preparing" }, HOST_A).ok).toBe(true)
		fixture.git(f.main, { "config", "remote.origin.pushurl", `{f.base}/nowhere.git` })
		local c = commitIn(a, "c0014", "one", HOST_A)
		t.expect(c.code).toBe(8)
		t.expect(has(c.stderr, "not pushed:")).toBe(true)
		t.expect(has(c.stderr, "the next ./zn commit retries")).toBe(true)
		t.expect(tip("prep-c0014")).toBe("")
		fixture.git(f.main, { "config", "--unset", "remote.origin.pushurl" })
		t.expect(commitIn(a, "c0014", "two", HOST_A).code).toBe(0)
		t.expect(tip("prep-c0014")).toBe(head(a))
	end)

	it(
		"sets up host B as the taker of c0010 and of c0013: each gives the claim back and claims it again",
		function()
			for _, id in { "c0010", "c0013" } do
				local b = trackerfix.trOk(f, f.other, { "worktree", `prep-{id}` })
				t.expect(trackerfix.tr(f, b, { "status", id, "new" }).ok).toBe(true)
				t.expect(trackerfix.tr(f, b, { "status", id, "preparing" }, HOST_B).ok).toBe(true)
			end
			t.expect(commitIn(wtB, "c0010", "taker", HOST_B).code).toBe(0)
			t.expect(tip("prep-c0010")).toBe(head(wtB))
		end
	)

	it(
		"AC2, AC3: host A's next commit stands, is refused with c0274's words and exit 7, and origin keeps the taker's tip",
		function()
			local theirs = tip("prep-c0010")
			local seenByA = fixture.exec(
				wtA,
				"git",
				{ "rev-parse", "--verify", "--quiet", "refs/remotes/origin/prep-c0010" }
			)
			local c = commitIn(wtA, "c0010", "late", HOST_A)
			t.expect(c.code).toBe(7)
			t.expect(
				has(
					c.stderr,
					`c0010's claim was taken over (now {stampOf("c0010")}): this checkout's work is no longer the claim's; stop here (./zn lost lists lost work to pick up)`
				)
			).toBe(true)
			t.expect(has(c.stderr, "continue")).toBe(false)
			t.expect(has(c.stdout, "committed: tracker: prep c0010 late")).toBe(true)
			t.expect(tip("prep-c0010")).toBe(theirs)
			t.expect(head(wtA) ~= theirs).toBe(true)
			-- the per-commit read did not refresh the lease ref
			local after = fixture.exec(
				wtA,
				"git",
				{ "rev-parse", "--verify", "--quiet", "refs/remotes/origin/prep-c0010" }
			)
			t.expect(after.stdout).toBe(seenByA.stdout)
		end
	)

	it(
		"AC2: a numbered copy of the lost worktree remembers no claim and does not push the taken prep either",
		function()
			local theirs = tip("prep-c0010")
			local copy = f.main .. "/.worktree/prep-c0010-1"
			fixture.git(f.main, { "fetch", "-q", "origin" })
			fixture.git(f.main, { "worktree", "add", "--detach", copy, "origin/prep-c0010" })
			fixture.git(f.main, { "branch", "-m", "prep-c0010", "prep-c0010-discarded-1" })
			fixture.git(copy, { "switch", "-q", "-c", "prep-c0010" })
			fs.writeFile(`{copy}/pickman/.tracker/issues/c0010/copy.md`, "copy\n")
			local r = trackerfix.tr(f, copy, { "commit", "-m", "from a copy that holds no claim" })
			t.expect(r.code).toBe(7)
			t.expect(has(r.stderr, "holds no claim")).toBe(true)
			t.expect(tip("prep-c0010")).toBe(theirs)
			fixture.git(f.main, { "worktree", "remove", "--force", copy })
			fixture.git(f.main, { "branch", "-D", "prep-c0010" })
			fixture.git(f.main, { "branch", "-m", "prep-c0010-discarded-1", "prep-c0010" })
		end
	)

	it(
		"AC7: host A's sync marks its worktrees whose claims host B took over as discarded, with no copy",
		function()
			local r = trackerfix.tr(f, f.main, { "sync" })
			t.expect(r.ok).toBe(true)
			t.expect(has(r.stdout, `discarded worktree {wtA}: c0010's claim was taken over`)).toBe(true)
			t.expect(fs.isFile(`{wtA}/.cache/discarded`)).toBe(true)
			local c13 = f.main .. "/.worktree/prep-c0013"
			t.expect(fs.isFile(`{c13}/.cache/discarded`)).toBe(true)
			-- B's own worktrees hold their claims: nothing of B's is marked on host B
			local rb = trackerfix.tr(f, f.other, { "sync" })
			t.expect(rb.ok).toBe(true)
			t.expect(fs.isFile(`{wtB}/.cache/discarded`)).toBe(false)
		end
	)

	it("AC7: a discarded worktree is kept while the taker's claim lives, and listed", function()
		local r = trackerfix.tr(f, f.main, { "sync" })
		t.expect(
			has(
				r.stdout,
				`leftover worktree {wtA}: holds the discarded work of c0010 (its claim is still live)`
			)
		).toBe(true)
		t.expect(fs.isDir(wtA)).toBe(true)
	end)

	it(
		"AC7: when the work ends, a clean worktree whose commits are all on origin is removed, and one holding an unpushed commit is kept and listed",
		function()
			local b10 = f.other .. "/.worktree/prep-c0010"
			local b13 = f.other .. "/.worktree/prep-c0013"
			t.expect(trackerfix.tr(f, b10, { "status", "c0010", "new" }).ok).toBe(true)
			t.expect(trackerfix.tr(f, b13, { "status", "c0013", "new" }).ok).toBe(true)
			local r = trackerfix.tr(f, f.main, { "sync" })
			t.expect(r.ok).toBe(true)
			local c13 = f.main .. "/.worktree/prep-c0013"
			t.expect(has(r.stdout, `removed discarded worktree {c13}`)).toBe(true)
			t.expect(fs.isDir(c13)).toBe(false)
			t.expect(
				has(
					r.stdout,
					`leftover worktree {wtA}: the work of c0010 ended, kept: 1 commit(s) on no origin ref`
				)
			).toBe(true)
			t.expect(fs.isDir(wtA)).toBe(true)
		end
	)

	it(
		"AC1: two hosts rafting one approved issue meet at the lease: the second `new raft` is refused and publishes nothing",
		function()
			local ra = trackerfix.trOk(f, f.main, { "worktree", "raft-pair-a" })
			local rb = trackerfix.trOk(f, f.other, { "worktree", "raft-pair-b" })
			local a = trackerfix.tr(
				f,
				ra,
				{ "new", "raft", "chore", "pair", "c0020", "--project", "pickman" },
				HOST_A
			)
			t.expect(a.ok).toBe(true)
			local raftsBefore =
				fixture.git(f.origin, { "ls-tree", "-r", "--name-only", "main", "pickman/.tracker/rafts" })
			local b = trackerfix.tr(
				f,
				rb,
				{ "new", "raft", "chore", "pair2", "c0020", "--project", "pickman" },
				HOST_B
			)
			t.expect(b.ok).toBe(false)
			t.expect(has(b.stderr, "is being rafted by")).toBe(true)
			t.expect(
				fixture.git(f.origin, { "ls-tree", "-r", "--name-only", "main", "pickman/.tracker/rafts" })
			)
				.toBe(raftsBefore)
		end
	)

	it("AC5: the rafting claim names its worker too, the raft and the member it stamped", function()
		local out = fixture.git(f.origin, { "log", "main", "-1", "--format=%B", "--grep=^tracker: new raft" })
		local rid = string.match(out, "tracker: new raft (R%d+)") :: string
		t.expect(rid ~= nil).toBe(true)
		local mine = xhost.attemptOf(
			{ "Worker: " .. (string.match(out, "Worker: ([^\n]+)") :: string) },
			rid,
			string.match(out, "Worker: " .. rid .. " (%S+)") :: string
		)
		t.expect(mine).toBe("tokA")
		t.expect(has(out, `Worker: c0020 `)).toBe(true)
	end)
end)
