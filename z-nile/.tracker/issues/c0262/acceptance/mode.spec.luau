--!strict
-- c0262 AC3: `final` is a zz-review mode of the dispatcher: its prompt, its landing and its spend phase. Pure: z-nile/engine/dispatch.luau.
local dispatch = require("@znile/engine/dispatch")
local t = require("@tests/lib/t")

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

local function prompt(mode: string, worktree: string): string
	return dispatch.prompt({
		step = "zz-review",
		id = "c0010",
		mode = mode,
		skillPath = "z-nile/skills/zz-review/SKILL.md",
		worktree = worktree,
		stateDir = "/x/.cache/dispatch/c0010",
	})
end

return t.spec("c0262 AC3 the final mode of the dispatcher", function(it)
	it("AC3: final is a zz-review mode that reads no lessons, records as a code review and is the sharp tier", function()
		t.expect(dispatch.phaseOf("zz-review", "final")).toBe("code-review")
		local m = (dispatch.REVIEW_MODES :: any).final
		t.expect(m ~= nil).toBe(true)
		t.expect(m.tier).toBe("sharp")
		local ok, e = pcall(dispatch.phaseOf, "zz-review", "finale")
		t.expect(ok).toBe(false)
		t.expect(has(tostring(e), "final")).toBe(true)
	end)

	it("AC3: the final prompt works in the view folder, reads skill.md there, names no lessons command and no repository path", function()
		local p = prompt("final", "/x/.cache/dispatch/c0010/view")
		t.expect(has(p, "final mode")).toBe(true)
		t.expect(has(p, "/x/.cache/dispatch/c0010/view")).toBe(true)
		t.expect(has(p, "skill.md")).toBe(true)
		t.expect(has(p, "review.md")).toBe(true)
		t.expect(has(p, "final-review-c0010-NNN.md")).toBe(true)
		t.expect(has(p, "./zn lessons")).toBe(false)
		t.expect(has(p, "z-nile/")).toBe(false)
		t.expect(has(p, "Never edit the main checkout")).toBe(false)
	end)

	it("AC3: the other modes' prompts are unchanged: their lessons lines, skill path and worktree", function()
		local want = { design = "design", raft = "design", code = "build", stream = "build" }
		for mode, lessons in want do
			local p = prompt(mode, "/x/.worktree/R0001")
			t.expect(has(p, `./zn lessons --when {lessons} --full`)).toBe(true)
			t.expect(has(p, "`z-nile/skills/zz-review/SKILL.md`")).toBe(true)
			t.expect(has(p, "Work only in `/x/.worktree/R0001`")).toBe(true)
		end
	end)

	it("AC3: a final review lands in the raft's folder as final-review-<issue>-NNN.md; the other modes land where they did", function()
		local land = dispatch.landing("final", "c0010", "z-nile/.tracker/issues/active/c0010", "z-nile/.tracker/rafts/active/R0099")
		t.expect(land.dir).toBe("z-nile/.tracker/rafts/active/R0099")
		t.expect(land.prefix).toBe("final-review-c0010-")
		local design = dispatch.landing("design", "c0010", "z-nile/.tracker/issues/c0010", "")
		t.expect(design.dir).toBe("z-nile/.tracker/issues/c0010")
		t.expect(design.prefix).toBe("design-review-")
		t.expect(dispatch.landing("code", "R0099", "z-nile/.tracker/rafts/active/R0099", "").prefix).toBe("review-")
		local stream = dispatch.landing("stream", "c0010", "z-nile/.tracker/issues/active/c0010", "z-nile/.tracker/rafts/active/R0099")
		t.expect(stream.dir).toBe("z-nile/.tracker/rafts/active/R0099")
		t.expect(stream.prefix).toBe("stream-review-c0010-")
	end)
end)
