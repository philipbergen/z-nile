--!strict
-- c0261 AC5 to AC7: which tier each dispatcher step runs: authors and rounds on the way cheap, every final review
-- sharp, waiting on the wait tier, and nothing expensive orchestrates or waits. Pure: engine/dispatch.
local dispatch = require("@znile/engine/dispatch")
local t = require("@tests/lib/t")

local d = dispatch :: any -- the API this issue adds, reached through `any` until the code exists (promote-check)

local function errorOf(f: () -> ()): string
	local ok: boolean, e: any = pcall(f)
	if ok then
		error("expected an error", 2)
	end
	return tostring(e)
end
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

return t.spec("c0261 dispatcher tiers", function(it)
	it("a review round runs cheap, and sharp only when it is the final round (AC5)", function()
		for _, mode in { "design", "raft", "code" } do
			t.expect(d.tierOf("zz-review", mode, false)).toBe("cheap")
			t.expect(d.tierOf("zz-review", mode, true)).toBe("sharp")
		end
	end)

	it("a stream review is on the way: cheap, and never final (AC5)", function()
		t.expect(d.tierOf("zz-review", "stream", false)).toBe("cheap")
		t.expect(has(errorOf(function()
			d.tierOf("zz-review", "stream", true)
		end), "stream")).toBe(true)
	end)

	it("every review mode declares its tier, and the idea and final (full-force) reviews are sharp whenever they exist (AC5)", function()
		for mode, m in dispatch.REVIEW_MODES do
			local tier = (m :: any).tier
			t.expect(`{mode}: {tier}`).toBe(`{mode}: {if tier == "round" or tier == "cheap" or tier == "sharp" then tier else "?"}`)
		end
		for _, mode in { "idea", "final" } do
			if dispatch.REVIEW_MODES[mode] then
				t.expect((dispatch.REVIEW_MODES[mode] :: any).tier).toBe("sharp")
				t.expect(d.tierOf("zz-review", mode, false)).toBe("sharp")
			end
		end
	end)

	it("the authoring steps carry no tier of their own: the file's table names it, cheap (AC6)", function()
		for _, step in { "z-ticket", "z-design", "z-raft", "z-run" } do
			t.expect(d.tierOf(step, nil, false)).toBe(nil)
		end
	end)

	it("the wait step is a model step on the wait tier with a phase of its own (AC7)", function()
		local s = dispatch.STEPS["z-wait"]
		t.expect(s ~= nil and s.kind == "model").toBe(true)
		t.expect(d.tierOf("z-wait", nil, false)).toBe("wait")
		t.expect(dispatch.phaseOf("z-wait")).toBe("wait")
		t.expect(has(errorOf(function()
			dispatch.step("z-poll")
		end), "unknown step")).toBe(true)
	end)

	it("only zz-review can be sharp: no step that authors or orchestrates is (AC6)", function()
		for name, s in dispatch.STEPS do
			if s.kind == "model" and name ~= "zz-review" then
				t.expect(d.tierOf(name, nil, false) == "sharp").toBe(false)
			end
		end
	end)

	it("the wait command is bounded, polls one condition and exits 0 when it holds, 3 when not yet (AC7)", function()
		local c: string = d.waitCommand("checks", 42, 600)
		t.expect(has(c, "./zn run --time 600 --")).toBe(true)
		t.expect(has(c, "gh pr checks 42")).toBe(true)
		local merged: string = d.waitCommand("merged", 42, 600)
		t.expect(has(merged, "gh pr view 42")).toBe(true)
		t.expect(has(merged, "exit 3")).toBe(true)
		t.expect(has(errorOf(function()
			d.waitCommand("tomorrow", 42, 600)
		end), "checks, merged")).toBe(true)
		t.expect(has(errorOf(function()
			d.waitCommand("checks", 42, 0)
		end), "seconds")).toBe(true)
	end)

	it("the wait prompt says to run only that command, again on exit 3, at most N times, and nothing else (AC7)", function()
		local p: string = d.waitPrompt("./zn run --time 600 -- true", 3)
		t.expect(has(p, "./zn run --time 600 -- true")).toBe(true)
		t.expect(has(p, "exit code 3")).toBe(true)
		t.expect(has(p, "at most 3 times")).toBe(true)
		t.expect(has(p, "Do nothing else")).toBe(true)
	end)
end)
