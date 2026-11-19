--!strict
-- f0417 AC5: assumptions.md, the record of what the work takes as true without proof, has one reader
-- (z-nile/engine/assumptions.luau) with a strict, append-only grammar, the twin of guesses.md. Pure.
local assumptions = require("@znile/engine/assumptions")
local t = require("@tests/lib/t")

return t.spec("f0417: the assumption record", function(it)
	it("append numbers from A1 and parse reads back what was written", function()
		local one, e1 = assumptions.append(
			nil,
			"design",
			"2026-11-18",
			"Ten calls fit the two-hour timeout.",
			"Each call takes minutes.",
			"A run stopped by the timeout."
		)
		t.expect(e1).toBe(nil)
		t.expect(one).toBe(
			"# assumptions\n- A1 (design, 2026-11-18): Ten calls fit the two-hour timeout. Because: Each call takes minutes. Unproven: A run stopped by the timeout.\n"
		)
		local two = assumptions.append(one, "build", "2026-11-19", "Git sorts names.", "Its docs.", "A fixture.")
		local list = assumptions.parse(two :: string) :: { assumptions.Assumption }
		t.expect(#list).toBe(2)
		t.expect(list[2].id).toBe("A2")
		t.expect(list[2].step).toBe("build")
		t.expect(list[2].when).toBe("2026-11-19")
		t.expect(list[2].what).toBe("Git sorts names.")
		t.expect(list[2].because).toBe("Its docs.")
		t.expect(list[2].unproven).toBe("A fixture.")
		t.expect(assumptions.render(list)).toBe(two)
		t.expect(assumptions.has(two, "A2")).toBe(true)
		t.expect(assumptions.has(two, "A3")).toBe(false)
		for _, step in { "idea", "design", "raft", "build" } do
			t.expect(table.find(assumptions.STEPS, step) ~= nil).toBe(true)
		end
	end)

	it("a bad step, an empty field, a mark inside a field and a gap are refused", function()
		local _, bad = assumptions.append(nil, "deploy", "2026-11-18", "a", "b", "c")
		t.expect(bad ~= nil).toBe(true)
		local _, empty = assumptions.append(nil, "design", "2026-11-18", "a", " ", "c")
		t.expect(empty ~= nil).toBe(true)
		local _, mark = assumptions.append(nil, "design", "2026-11-18", "a Because: b", "b", "c")
		t.expect(mark ~= nil).toBe(true)
		local _, line = assumptions.append(nil, "design", "2026-11-18", "a\nb", "b", "c")
		t.expect(line ~= nil).toBe(true)
		local _, date = assumptions.append(nil, "design", "18 Nov", "a", "b", "c")
		t.expect(date ~= nil).toBe(true)
		local gap = "# assumptions\n- A1 (design, 2026-11-18): a Because: b Unproven: c\n- A3 (design, 2026-11-18): a Because: b Unproven: c\n"
		local none, why = assumptions.parse(gap)
		t.expect(none).toBe(nil)
		t.expect(string.find(why or "", "A3", 1, true) ~= nil).toBe(true)
		local _, noUnproven = assumptions.parse("# assumptions\n- A1 (design, 2026-11-18): a Because: b\n")
		t.expect(noUnproven ~= nil).toBe(true)
	end)

	it("extends is append-only", function()
		local one = assumptions.append(nil, "design", "2026-11-18", "a", "b", "c") :: string
		local two = assumptions.append(one, "design", "2026-11-18", "d", "e", "f") :: string
		t.expect(assumptions.extends(nil, one)).toBe(true)
		t.expect(assumptions.extends(one, two)).toBe(true)
		t.expect(assumptions.extends(one, one)).toBe(true)
		t.expect(assumptions.extends(two, one)).toBe(false) -- A2 removed
		local edited = string.gsub(two, "Because: b", "Because: x")
		t.expect(assumptions.extends(two, edited)).toBe(false)
		t.expect(assumptions.extends(one, nil)).toBe(false)
	end)
end)
