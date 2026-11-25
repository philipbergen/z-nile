--!strict
-- d0434: restackplan, the pure part of `./zn restack`: which tip a layer is taken from and what is done with it,
-- the marker a conflicted restack leaves, and the readers of git's words about what is still unresolved.
local restackplan = require("@znile/engine/restackplan")
local t = require("@tests/lib/t")

local function facts(over: { [string]: any }): restackplan.Facts
	local out: restackplan.Facts = {
		hasLocal = true,
		hasRemote = true,
		hasOrigin = true,
		localExtra = false,
		originExtra = false,
		foreign = false,
		ontoInTip = false,
	}
	for k, v in over do
		(out :: any)[k] = v
	end
	return out
end

return t.spec("d0434: restackplan", function(it)
	it("takes the local tip whenever it holds a commit origin lacks, and origin's otherwise", function()
		t.expect(restackplan.decide(facts({ localExtra = true })).source).toBe("local")
		t.expect(restackplan.decide(facts({ localExtra = false })).source).toBe("origin")
		t.expect(restackplan.decide(facts({ hasOrigin = false, localExtra = false })).source).toBe("local")
		t.expect(restackplan.decide(facts({ hasLocal = false })).source).toBe("origin")
	end)

	it(
		"rebases a tip not based on the layer below, skips one that is and publishes a local one that is",
		function()
			t.expect(restackplan.decide(facts({})).action).toBe("rebase")
			t.expect(restackplan.decide(facts({ ontoInTip = true })).action).toBe("skip")
			t.expect(restackplan.decide(facts({ ontoInTip = true, localExtra = true })).action)
				.toBe("publish")
			t.expect(restackplan.decide(facts({ ontoInTip = true, hasOrigin = false })).action)
				.toBe("publish")
			t.expect(restackplan.decide(facts({ localExtra = true })).action).toBe("rebase")
		end
	)

	it("refuses a diverged origin that holds a foreign commit, and a layer with no tip", function()
		local diverged = facts({ localExtra = true, originExtra = true, foreign = true, ontoInTip = true })
		t.expect(restackplan.decide(diverged).action).toBe("foreign")
		t.expect(
			restackplan.decide(facts({ localExtra = true, originExtra = true, ontoInTip = true })).action
		)
			.toBe("publish")
		t.expect(restackplan.decide(facts({ hasLocal = false, hasOrigin = false })).action).toBe("none")
	end)

	it("trusts a diverged origin tip only when this clone pushed it itself", function()
		t.expect(restackplan.trusted("a", "a")).toBe(true)
		t.expect(restackplan.trusted("a", "b")).toBe(false)
		t.expect(restackplan.trusted("a", "")).toBe(false)
	end)

	it("counts an emptied commit and a moved branch", function()
		t.expect(restackplan.emptied(1, 0)).toBe(true)
		t.expect(restackplan.emptied(1, 1)).toBe(false)
		t.expect(restackplan.emptied(0, 0)).toBe(false)
		t.expect(restackplan.movedSince("x", "o", "l")).toBe(true)
		t.expect(restackplan.movedSince("l", "o", "l")).toBe(false)
		t.expect(restackplan.movedSince("o", "o", "l")).toBe(false)
	end)

	it(
		"an abort takes a pushed layer back from its tip before the run, and refuses any other move",
		function()
			t.expect(restackplan.abortRefuses("o", "o", "l", "p")).toBe(false) -- pushed, then put back by hand
			t.expect(restackplan.abortRefuses("p", "o", "l", "p")).toBe(false)
			t.expect(restackplan.abortRefuses("l", "o", "l", "p")).toBe(false)
			t.expect(restackplan.abortRefuses("x", "o", "l", "p")).toBe(true)
			t.expect(restackplan.abortRefuses("x", "o", "l", nil)).toBe(true)
			t.expect(restackplan.abortRefuses("", "o", "l", nil)).toBe(true) -- a deleted branch is a move
			t.expect(restackplan.abortRefuses("", "", "l", nil)).toBe(false) -- the run created it
		end
	)

	it(
		"--continue judges a layer the run moved or pushed: where it left it, built on it, or this clone's last push",
		function()
			-- now, orig, left, pushed, refs/zn/pushed, what the run left is an ancestor of now
			t.expect(restackplan.strayed("o", "o", "l", "l", "l", false)).toBe(true) -- back at its tip before the run
			t.expect(restackplan.strayed("l", "o", "l", "l", "l", true)).toBe(false) -- where the run left it
			t.expect(restackplan.strayed("f", "o", "l", "l", "l", true)).toBe(false) -- a fix on top of it
			t.expect(restackplan.strayed("x", "o", "l", nil, "", false)).toBe(true) -- rebased, unpushed, then moved
			t.expect(restackplan.strayed("p", "o", "l", "p", "p", false)).toBe(false) -- the tip this clone pushed
			t.expect(restackplan.strayed("x", "o", "o", nil, "", false)).toBe(false) -- the run never moved it
			t.expect(restackplan.strayed("x", "o", "o", "o", "o", false)).toBe(true) -- pushed as it was, then moved
			t.expect(restackplan.strayed("", "o", "l", "l", "l", false)).toBe(false) -- deleted: taken from origin
			local text = restackplan.strayedMessage("R0010", {
				{
					layer = "R0010/1/c0010",
					atOrig = true,
					left = "aaa c0010: alpha (2026-11-24)",
					now = "ooo c0010: alpha (2026-11-20)",
					log = "ooo c0010: alpha",
					base = "mmm",
				},
			})
			for _, part in
				{
					"R0010/1/c0010",
					"aaa c0010: alpha (2026-11-24)",
					"ooo c0010: alpha (2026-11-20)",
					"git log --oneline",
					"Nothing was changed",
				}
			do
				t.expect(string.find(text, part, 1, true) ~= nil).toBe(true)
			end
			local abortAt = string.find(text, "./zn restack R0010 --abort", 1, true) :: number
			local plainAt = string.find(text, "then ./zn restack R0010", 1, true) :: number
			t.expect(abortAt ~= nil and plainAt ~= nil and abortAt < plainAt).toBe(true)
			t.expect((string.find(text, "reset", 1, true))).toBe(nil)
			local other = restackplan.strayedMessage("R0010", {
				{
					layer = "R0010/2/c0020",
					atOrig = false,
					left = "aaa x",
					now = "bbb y",
					log = "",
					base = "mmm",
				},
			})
			t.expect(string.find(other, "(none)", 1, true) ~= nil).toBe(true)
			t.expect(string.find(other, "git rebase --onto aaa mmm R0010/2/c0020", 1, true) ~= nil).toBe(true)
			t.expect(string.find(other, "./zn restack R0010 --continue", 1, true) ~= nil).toBe(true)
			t.expect((string.find(other, "reset", 1, true))).toBe(nil)
		end
	)

	it(
		"a plain restack over a stopped run's marker keeps its record while the branches are where it left them",
		function()
			local old: restackplan.State = {
				raft = "R0010",
				back = "",
				start = "",
				orig = { { name = "a", sha = "o1" }, { name = "b", sha = "o2" }, { name = "c", sha = "" } },
				judged = {},
				left = { a = "l1", b = "l2", c = "l3" },
				pushed = { a = "l1", b = "l2" },
				pushing = {},
				red = "",
				redSha = "",
				conflict = "",
				own = 0,
				files = {},
			}
			local orig, pushed = restackplan.carried(old, "a", "l1", "l1")
			t.expect(orig).toBe("o1")
			t.expect(pushed).toBe("l1")
			orig, pushed = restackplan.carried(old, "b", "fixed", "other") -- moved by the worker, origin moved since
			t.expect(orig).toBe(nil)
			t.expect(pushed).toBe(nil)
			orig, pushed = restackplan.carried(old, "c", "l3", "")
			t.expect(orig).toBe("") -- the stopped run created it
			t.expect(pushed).toBe(nil)
			orig, pushed = restackplan.carried(nil, "a", "l1", "l1")
			t.expect(orig).toBe(nil)
			t.expect(pushed).toBe(nil)
		end
	)

	it("a refused push names the way on: --abort, then a plain restack", function()
		local text =
			restackplan.refusedPushMessage("R0010", "R0010/3/c0030", { "R0010/2/c0020" }, "! [rejected] x")
		for _, part in { "R0010/3/c0030", "R0010/2/c0020", "! [rejected] x", "does not fetch" } do
			t.expect(string.find(text, part, 1, true) ~= nil).toBe(true)
		end
		local abortAt = string.find(text, "./zn restack R0010 --abort", 1, true) :: number
		local plainAt = string.find(text, "then ./zn restack R0010", 1, true) :: number
		t.expect(abortAt ~= nil and plainAt ~= nil and abortAt < plainAt).toBe(true)
		local none = restackplan.refusedPushMessage("R0010", "R0010/1/c0010", {}, "")
		t.expect(string.find(none, "No layer was pushed", 1, true) ~= nil).toBe(true)
	end)

	it("a repository with no origin has nothing to publish: a stacked local layer is skipped", function()
		local none = facts({ hasRemote = false, hasOrigin = false, ontoInTip = true })
		t.expect(restackplan.decide(none).action).toBe("skip")
		t.expect(restackplan.decide(facts({ hasOrigin = false, ontoInTip = true })).action).toBe("publish")
	end)

	it("writes and reads the marker, and refuses a text that is not one", function()
		local state: restackplan.State = {
			raft = "R0010",
			back = "R0010/1/c0010",
			start = "abc123",
			orig = {
				{ name = "R0010/1/c0010", sha = "abc" },
				{ name = "R0010/2/c0020", sha = "" },
			},
			judged = { ["R0010/1/c0010"] = "def" },
			left = { ["R0010/1/c0010"] = "abc" },
			pushed = { ["R0010/1/c0010"] = "abc" },
			pushing = { ["R0010/2/c0020"] = "fed" },
			red = "R0010/3/c0030",
			redSha = "cab",
			conflict = "R0010/2/c0020",
			own = 2,
			files = { "a/b.luau" },
		}
		local got = restackplan.parseState(restackplan.renderState(state))
		t.expect(got ~= nil).toBe(true)
		local g = got :: restackplan.State
		t.expect(g.raft).toBe("R0010")
		t.expect(g.back).toBe("R0010/1/c0010")
		t.expect(g.start).toBe("abc123")
		t.expect(#g.orig).toBe(2)
		t.expect(g.judged["R0010/1/c0010"]).toBe("def")
		t.expect(g.orig[2].sha).toBe("")
		t.expect(g.left["R0010/1/c0010"]).toBe("abc")
		t.expect(g.pushed["R0010/1/c0010"]).toBe("abc")
		t.expect(g.pushed["R0010/2/c0020"]).toBe(nil)
		t.expect(g.pushing["R0010/2/c0020"]).toBe("fed")
		t.expect(g.red).toBe("R0010/3/c0030")
		t.expect(g.redSha).toBe("cab")
		t.expect(g.conflict).toBe("R0010/2/c0020")
		t.expect(g.own).toBe(2)
		t.expect(g.files[1]).toBe("a/b.luau")
		-- a marker written at the start of a run names no conflict yet
		state.conflict = ""
		local early = restackplan.parseState(restackplan.renderState(state)) :: restackplan.State
		t.expect(early.conflict).toBe("")
		t.expect(restackplan.parseState("nothing\n")).toBe(nil)
	end)

	it("lists the layers a run pushed in layer order, and says what an abort leaves", function()
		local state: restackplan.State = {
			raft = "R0010",
			back = "",
			start = "",
			orig = { { name = "b", sha = "1" }, { name = "a", sha = "2" }, { name = "c", sha = "3" } },
			judged = {},
			left = {},
			pushed = { a = "x", b = "y" },
			pushing = {},
			red = "",
			redSha = "",
			conflict = "",
			own = 0,
			files = {},
		}
		local names = restackplan.published(state)
		t.expect(#names).toBe(2)
		t.expect(names[1]).toBe("b") -- the order the run's layers were walked in, not alphabetical
		t.expect(names[2]).toBe("a")
		t.expect(restackplan.restoreTo(state, "c", "3")).toBe("3") -- not pushed: back to where the run found it
		t.expect(restackplan.restoreTo(state, "a", "2")).toBe("x") -- pushed: back to the tip it pushed
		t.expect(restackplan.restoreTo(state, "n", "")).toBe("") -- not pushed, created by the run: deleted
		t.expect(restackplan.restoreTo(state, "b", "")).toBe("y") -- pushed, created by the run: kept
		local kept = restackplan.abortMessage("R0010", names)
		t.expect(string.find(kept, "b, a stay as pushed", 1, true) ~= nil).toBe(true)
		t.expect(string.find(kept, "never moves origin back", 1, true) ~= nil).toBe(true)
		t.expect(
			string.find(restackplan.abortMessage("R0010", {}), "nothing had been pushed", 1, true) ~= nil
		)
			.toBe(true)
	end)

	it("keeps only git's reason for a refused push, never the remote's address", function()
		local stderr =
			"To /srv/secret-remote/origin.git\n ! [rejected]        R1/1/c1 -> R1/1/c1 (stale info)\nerror: failed to push some refs to '/srv/secret-remote/origin.git'\nhint: Updates were rejected\n"
		local reason = restackplan.pushReason(stderr)
		t.expect(string.find(reason, "stale info", 1, true) ~= nil).toBe(true)
		t.expect((string.find(reason, "secret-remote", 1, true))).toBe(nil)
		t.expect((string.find(reason, "origin.git", 1, true))).toBe(nil)
		t.expect(restackplan.pushReason("fatal: unable to access 'https://x@host/r.git/'\n")).toBe("")
	end)

	it("says what a red check leaves and what to do, in the stop and in work next", function()
		local stop = restackplan.redMessage("R0010", "R0010/2/c0020", "c0020", { "R0010/1/c0010" })
		for _, part in
			{
				"R0010/2/c0020",
				"check.sh failed",
				"not pushed",
				"R0010/1/c0010",
				"./zn finish c0020",
				"./zn restack R0010",
			}
		do
			t.expect(string.find(stop, part, 1, true) ~= nil).toBe(true)
		end
		local note = restackplan.redNote("R0010", "R0010/2/c0020", "c0020")
		t.expect(string.find(note, "./zn finish c0020", 1, true) ~= nil).toBe(true)
		t.expect(string.find(note, "not pushed", 1, true) ~= nil).toBe(true)
	end)

	it("reads conflict markers out of git diff --check and names them as file:line", function()
		local out = "a.luau:3: leftover conflict marker\n+<<<<<<< HEAD\nb.luau:9: trailing whitespace.\n"
		local found = restackplan.markers(out)
		t.expect(#found).toBe(1)
		t.expect(found[1]).toBe("a.luau:3")
	end)

	it("says the files, the layer and both commands", function()
		local text = restackplan.conflictMessage(
			"R0010",
			"R0010/2/c0020",
			{ "x.luau", "y.luau" },
			{ "R0010/1/c0010" }
		)
		for _, part in
			{
				"restack stopped at R0010/2/c0020",
				"x.luau",
				"y.luau",
				"R0010 --continue",
				"R0010 --abort",
				"already pushed: R0010/1/c0010",
			}
		do
			t.expect(string.find(text, part, 1, true) ~= nil).toBe(true)
		end
		local none = restackplan.conflictMessage("R0010", "R0010/1/c0010", { "x.luau" }, {})
		t.expect((string.find(none, "already pushed", 1, true))).toBe(nil)
		t.expect((string.find(none, "nothing is pushed until", 1, true))).toBe(nil)
		local note = restackplan.workNote("R0010", "R0010/2/c0020", { "x.luau" })
		t.expect(string.find(note, "./zn restack R0010 --continue", 1, true) ~= nil).toBe(true)
	end)
end)
