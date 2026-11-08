--!strict
-- c0262 AC3: `final` is a zz-review mode of the dispatcher: its prompt, its landing and its spend phase. Pure: z-nile/engine/dispatch.luau.
local dispatch = require("@znile/engine/dispatch")
local t = require("@tests/lib/t")

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

return t.spec("c0262 AC3 the final mode of the dispatcher", function(it)
	it("AC3: final is a zz-review mode that reads no lessons and records as a code review", function()
		t.expect(dispatch.phaseOf("zz-review", "final")).toBe("code-review")
		t.expect(dispatch.REVIEW_MODES.final ~= nil).toBe(true)
		local ok, e = pcall(dispatch.phaseOf, "zz-review", "finale")
		t.expect(ok).toBe(false)
		t.expect(has(tostring(e), "final")).toBe(true)
	end)

	it("AC3: the final prompt works in the view folder, names no lessons command and no repository worktree", function()
		local p = dispatch.prompt({
			step = "zz-review",
			id = "c0010",
			mode = "final",
			skillPath = "z-nile/skills/zz-review/SKILL.md",
			worktree = "/x/.cache/dispatch/c0010/view",
			stateDir = "/x/.cache/dispatch/c0010/zz-review-final-c0010-1",
			promptPath = nil,
			description = nil,
			project = nil,
		})
		t.expect(has(p, "final mode")).toBe(true)
		t.expect(has(p, "/x/.cache/dispatch/c0010/view")).toBe(true)
		t.expect(has(p, "review.md")).toBe(true)
		t.expect(has(p, "final-review-c0010-NNN.md")).toBe(true)
		t.expect(has(p, "./zn lessons")).toBe(false)
		t.expect(has(p, "Never edit the main checkout")).toBe(false)
		-- the code mode's prompt is unchanged: it still names the lessons command
		local code = dispatch.prompt({
			step = "zz-review",
			id = "c0010",
			mode = "code",
			skillPath = "z-nile/skills/zz-review/SKILL.md",
			worktree = "/x/.worktree/R0001",
			stateDir = "/x/.cache/dispatch/s",
		})
		t.expect(has(code, "./zn lessons --when design --full")).toBe(true)
	end)

	it("AC3: a final review lands in the raft's folder as final-review-<issue>-NNN.md", function()
		local land = dispatch.landing("final", "c0010", "z-nile/.tracker/issues/active/c0010", "z-nile/.tracker/rafts/active/R0099")
		t.expect(land.dir).toBe("z-nile/.tracker/rafts/active/R0099")
		t.expect(land.prefix).toBe("final-review-c0010-")
		local design = dispatch.landing("design", "c0010", "z-nile/.tracker/issues/c0010", "")
		t.expect(design.dir).toBe("z-nile/.tracker/issues/c0010")
		t.expect(design.prefix).toBe("design-review-")
		t.expect(dispatch.landing("code", "R0099", "z-nile/.tracker/rafts/active/R0099", "").prefix).toBe("review-")
	end)
end)
