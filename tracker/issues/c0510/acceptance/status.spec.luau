--!strict
-- c0510: the pure status rules (no git, no files): which transitions exist, which ride a PR, how a
-- missing `status:` is derived, and id allocation over the union of two trees.
local status = require("@scripts/tracker/status")
local t = require("@tests/lib/t")

local ALL = { "new", "preparing", "prepared", "active", "done" }
local ALLOWED = {
	["new>preparing"] = true,
	["preparing>prepared"] = true,
	["preparing>new"] = true,
	["prepared>active"] = true,
	["prepared>preparing"] = true,
	["active>prepared"] = true,
}

return t.spec("tracker status rules", function(it)
	it("allows exactly the six documented transitions out of the 25 pairs", function()
		for _, from in ALL do
			for _, to in ALL do
				t.expect(status.canMove(from, to)).toBe(ALLOWED[`{from}>{to}`] == true)
			end
		end
	end)

	it("done is never a move target and nothing leaves it or repeats a state", function()
		for _, s in ALL do
			t.expect(status.canMove("done", s)).toBe(false)
			t.expect(status.canMove(s, "done")).toBe(false)
			t.expect(status.canMove(s, s)).toBe(false)
		end
	end)

	it("only preparing>prepared rides a pull request; every other move is published", function()
		for _, from in ALL do
			for _, to in ALL do
				if ALLOWED[`{from}>{to}`] then
					t.expect(status.carriedByPr(from, to)).toBe(from == "preparing" and to == "prepared")
				end
			end
		end
	end)

	it("a stamp is the state plus three words from the list, and parse and phrase read it back", function()
		local words: { [string]: boolean } = {}
		local picks = 0
		for _, state in ALL do
			local v = status.stamp(state, function(max)
				picks += 1
				return (picks * 7) % max + 1
			end)
			t.expect(string.match(v, "^" .. state .. "%-%a+%-%a+%-%a+$") ~= nil).toBe(true)
			t.expect(status.parse(v)).toBe(state)
			local phrase = status.phrase(v) :: string
			t.expect(phrase ~= nil).toBe(true)
			for word in string.gmatch(phrase, "%a+") do
				words[word] = true
			end
		end
		t.expect(status.phrase("active")).toBe(nil)
		t.expect(next(words) ~= nil).toBe(true)
	end)

	it("stamps made from different picks differ, and a pick of 1 is the first word of the list", function()
		local a = status.stamp("preparing", function()
			return 1
		end)
		local b = status.stamp("preparing", function()
			return 2
		end)
		local c = status.stamp("preparing", function(max)
			return max
		end)
		t.expect(a == b).toBe(false)
		t.expect(a == c).toBe(false)
		t.expect(status.parse(a)).toBe("preparing")
		t.expect(status.parse(c)).toBe("preparing")
		t.expect(string.match(a, "^preparing%-(%a+)%-%1%-%1$") ~= nil).toBe(true) -- the same pick gives the same word
	end)

	it("parse accepts the five names and nothing else", function()
		for _, s in ALL do
			t.expect(status.parse(s)).toBe(s)
		end
		t.expect(status.parse("new-raging-pink-mongoose")).toBe("new")
		t.expect(status.parse("new-raging-pink")).toBe(nil)
		t.expect(status.parse("bogus-raging-pink-mongoose")).toBe(nil)
		t.expect(status.parse("ready")).toBe(nil)
		t.expect(status.parse("")).toBe(nil)
		t.expect(status.parse(nil)).toBe(nil)
	end)

	it("derives a missing status from the directory and the design field", function()
		t.expect(status.derive("backlog", nil)).toBe("new")
		t.expect(status.derive("backlog", "draft")).toBe("new")
		t.expect(status.derive("backlog", "reviewed")).toBe("new")
		t.expect(status.derive("backlog", "ready")).toBe("prepared")
		t.expect(status.derive("active", "ready")).toBe("active")
		t.expect(status.derive("done", "ready")).toBe("done")
		t.expect(status.derive("done", nil)).toBe("done")
	end)

	it("a draft item that belongs to a raft, and a draft raft, derive preparing", function()
		t.expect(status.derive("backlog", "draft", true)).toBe("preparing")
		t.expect(status.derive("backlog", nil, true)).toBe("preparing")
		t.expect(status.derive("backlog", "ready", true)).toBe("prepared")
		t.expect(status.derive("backlog", "draft", false)).toBe("new")
		t.expect(status.derive("active", "draft", true)).toBe("active")
		t.expect(status.effective({ raft = "R0100", design = "draft" }, "backlog")).toBe("preparing")
		t.expect(status.effective({ raft = "", design = "draft" }, "backlog")).toBe("new")
		t.expect(status.effective({ issues = "[f0010]", design = "draft" }, "backlog")).toBe("preparing")
		t.expect(status.effective({ issues = "[f0010]", design = "ready" }, "backlog")).toBe("prepared")
		t.expect(status.effective({ raft = "R0100", status = "new-aa-bb-cc" }, "backlog")).toBe("new")
	end)

	it("an existing draft raft is claimed by stamping preparing, once; a lone issue never is", function()
		t.expect(status.canClaim("preparing", "preparing", false, true)).toBe(true)
		t.expect(status.canClaim("preparing", "preparing", true, true)).toBe(false) -- already stamped: someone owns it
		t.expect(status.canClaim("preparing", "preparing", false, false)).toBe(false) -- an issue on its own
		t.expect(status.canClaim("new", "preparing", false, true)).toBe(false) -- that is an ordinary move
		t.expect(status.canClaim("prepared", "preparing", false, true)).toBe(false)
	end)

	it("an explicit status wins over the derived one; an invalid one is ignored", function()
		t.expect(status.effective({ status = "preparing", design = "ready" }, "backlog")).toBe("preparing")
		t.expect(status.effective({ status = "active" }, "backlog")).toBe("active")
		t.expect(status.effective({ status = "bogus", design = "ready" }, "backlog")).toBe("prepared")
		t.expect(status.effective({}, "done")).toBe("done")
		-- a finished item is done whatever an old status field still says
		t.expect(status.effective({ status = "active" }, "done")).toBe("done")
		t.expect(status.effective({ status = "preparing-quiet-copper-falcon" }, "backlog")).toBe("preparing")
	end)

	it("the next number is the next multiple of 10 above the highest id in either tree", function()
		t.expect(status.nextNumber({})).toBe(10)
		t.expect(status.nextNumber({ "c0090" })).toBe(100)
		t.expect(status.nextNumber({ "c0090", "f0100" })).toBe(110)
		t.expect(status.nextNumber({ "c0020", "R0140", "d0105" })).toBe(150)
	end)
end)
