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
				{ name = "R0010/1/c0010", sha = "abc", origin = "def" },
				{ name = "R0010/2/c0020", sha = "", origin = "" },
			},
			left = { ["R0010/1/c0010"] = "abc" },
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
		t.expect(g.conflict).toBe("R0010/2/c0020")
		t.expect(g.own).toBe(2)
		t.expect(g.files[1]).toBe("a/b.luau")
		-- a marker written at the start of a run names no conflict yet
		state.conflict = ""
		local early = restackplan.parseState(restackplan.renderState(state)) :: restackplan.State
		t.expect(early.conflict).toBe("")
		t.expect(restackplan.parseState("nothing\n")).toBe(nil)
	end)

	it("reads conflict markers out of git diff --check and names them as file:line", function()
		local out = "a.luau:3: leftover conflict marker\n+<<<<<<< HEAD\nb.luau:9: trailing whitespace.\n"
		local found = restackplan.markers(out)
		t.expect(#found).toBe(1)
		t.expect(found[1]).toBe("a.luau:3")
	end)

	it("says the files, the layer and both commands", function()
		local text = restackplan.conflictMessage("R0010", "R0010/2/c0020", { "x.luau", "y.luau" })
		for _, part in
			{ "restack stopped at R0010/2/c0020", "x.luau", "y.luau", "R0010 --continue", "R0010 --abort" }
		do
			t.expect(string.find(text, part, 1, true) ~= nil).toBe(true)
		end
		local note = restackplan.workNote("R0010", "R0010/2/c0020", { "x.luau" })
		t.expect(string.find(note, "./zn restack R0010 --continue", 1, true) ~= nil).toBe(true)
	end)
end)
