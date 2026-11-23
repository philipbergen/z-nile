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
		t.expect(string.find(reason, "secret-remote", 1, true)).toBe(nil)
		t.expect(string.find(reason, "origin.git", 1, true)).toBe(nil)
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
		t.expect(string.find(none, "already pushed", 1, true)).toBe(nil)
		t.expect(string.find(none, "nothing is pushed until", 1, true)).toBe(nil)
		local note = restackplan.workNote("R0010", "R0010/2/c0020", { "x.luau" })
		t.expect(string.find(note, "./zn restack R0010 --continue", 1, true) ~= nil).toBe(true)
	end)
end)
