--!strict
-- c0258 AC2 to AC4: what `./zn land` does after each push (z-nile/engine/landrace.luau), in process. A push that says
-- it failed has landed when origin/main holds its commit; a main that did not move is a real failure; the last try
-- gives up; a move by more than tracker state, or one that changes a capture file, runs the gate again; any other
-- move pushes again with no gate. Before the gate, a branch whose changes main already holds has already landed.
local landrace = require("@znile/engine/landrace")
local t = require("@tests/lib/t")

type Facts = landrace.Facts

local function facts(over: { [string]: any }): Facts
	local f: { [string]: any } = {
		attempt = 1,
		max = landrace.TRIES,
		pushed = false,
		answered = true,
		moved = true,
		contains = false,
		trackerWhy = nil,
		touched = {},
	}
	for k, v in over do
		f[k] = v
	end
	return (f :: any) :: Facts
end

local function step(over: { [string]: any }): string
	local s = landrace.next(facts(over))
	return s
end

return t.spec("c0258 land race", function(it)
	it("AC3: one land makes up to ten pushes", function()
		t.expect(landrace.TRIES).toBe(10)
	end)

	it("AC3: a push that pushed has landed", function()
		t.expect(step({ pushed = true, moved = false })).toBe("landed")
	end)

	it("AC4: a push that reports a failure has landed when origin/main holds its commit", function()
		t.expect(step({ contains = true })).toBe("landed")
		-- on the last try too, and whatever else moved main with it
		t.expect(step({ contains = true, attempt = landrace.TRIES })).toBe("landed")
		t.expect(step({ contains = true, trackerWhy = "x.lua is not tracker state" })).toBe("landed")
	end)

	it("AC3: a failed push while main did not move is a push failure, on any try", function()
		t.expect(step({ moved = false })).toBe("unmoved")
		t.expect(step({ moved = false, attempt = landrace.TRIES })).toBe("unmoved")
	end)

	it("AC3: a publish broker that gave no answer stops the land at once, on any try", function()
		t.expect(step({ answered = false })).toBe("no-answer")
		t.expect(step({ answered = false, moved = false })).toBe("no-answer")
		t.expect(step({ answered = false, attempt = landrace.TRIES })).toBe("no-answer")
		t.expect(step({ answered = false, trackerWhy = "x is not tracker state" })).toBe("no-answer")
		-- a commit origin/main holds has landed, answer or none
		t.expect(step({ answered = false, contains = true })).toBe("landed")
	end)

	it("AC3: the last try gives up, and an earlier one does not", function()
		t.expect(step({ attempt = landrace.TRIES })).toBe("give-up")
		t.expect(step({ attempt = landrace.TRIES, trackerWhy = "x is not tracker state" })).toBe("give-up")
		t.expect(step({ attempt = landrace.TRIES - 1 })).toBe("again")
		-- the bound is the one the facts carry, not a number of its own
		t.expect(step({ attempt = 3, max = 3 })).toBe("give-up")
		t.expect(step({ attempt = 3, max = 4 })).toBe("again")
	end)

	it("AC2: a move by tracker state alone that touches no capture file pushes again with no gate", function()
		local s, why = landrace.next(facts({}))
		t.expect(s).toBe("again")
		t.expect(why).toBe(nil)
	end)

	it("AC2: a move by more than tracker state runs the gate again, and says why", function()
		local s, why = landrace.next(facts({ trackerWhy = "abc123: README.md is not tracker state" }))
		t.expect(s).toBe("regate")
		t.expect(why).toBe("main moved by more than tracker state: abc123: README.md is not tracker state")
	end)

	it("AC2: a move that changes a capture file runs the gate again, naming the files", function()
		local s, why = landrace.next(facts({ touched = { "p/.tracker/issues/c0001/c0001.md", "p/x.md" } }))
		t.expect(s).toBe("regate")
		t.expect(why).toBe("main changed this capture's p/.tracker/issues/c0001/c0001.md, p/x.md")
		-- both: the tracker-state reason is the one given
		local both, said = landrace.next(facts({ trackerWhy = "y", touched = { "a" } }))
		t.expect(both).toBe("regate")
		t.expect(said).toBe("main moved by more than tracker state: y")
	end)

	it("AC2: touched is the capture files main changed, sorted, each once", function()
		t.expect(landrace.touched({ "b", "a", "c" }, { "c", "z", "a", "c" })).toEqual({ "a", "c" })
		t.expect(landrace.touched({ "a" }, { "b" })).toEqual({})
		t.expect(landrace.touched({}, { "a" })).toEqual({})
		-- a path is a whole path, never a prefix
		t.expect(landrace.touched({ "p/c0001.md" }, { "p/c0001.md.orig", "p/c0001" })).toEqual({})
	end)

	it(
		"AC4: before the gate, changes main already holds have landed; no changes are nothing to land",
		function()
			t.expect(landrace.start(2, 1)).toBe("land")
			t.expect(landrace.start(0, 1)).toBe("land")
			t.expect(landrace.start(2, 0)).toBe("already")
			t.expect(landrace.start(1, 0)).toBe("already")
			t.expect(landrace.start(0, 0)).toBe("nothing")
		end
	)
end)
