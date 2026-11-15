--!strict
-- c0230 AC1: the per-file budget module (tests/lib/budget.luau) is pure: the `--budget` limits, the measurer's CPU line,
-- which files are over, and the report's exact text. Instant: nothing here starts a process.
local budget = require("@tests/lib/budget")
local t = require("@tests/lib/t")

local LESSON = "zz-test/specs-never-burn-real-resources"

-- the module's Cost, spelled here so the spec type-checks before the module exists
type Cost = { file: string, seconds: number, cpu: number? }

local function refusal(v: string): string
	return `tests/run: --budget must be <wall seconds>:<cpu seconds>, each a positive number (got "{v}")`
end

return t.spec("c0230 budget module", function(it)
	it("AC1: no --budget is 60 s wall and 5 s cpu", function()
		local l, e = budget.limits(nil)
		t.expect(e).toBe(nil)
		t.expect(l).toEqual({ seconds = 60, cpu = 5 })
	end)

	it("AC1: <wall>:<cpu> sets both limits, decimals allowed", function()
		local l, e = budget.limits("5:2.5")
		t.expect(e).toBe(nil)
		t.expect(l).toEqual({ seconds = 5, cpu = 2.5 })
		t.expect((budget.limits("0.001:.5"))).toEqual({ seconds = 0.001, cpu = 0.5 })
	end)

	it(
		"AC1: anything else, the empty string included, is refused with the message naming the value",
		function()
			local bad = {
				"",
				"abc",
				"5",
				"0:5",
				"5:0",
				"5:-1",
				"5:",
				":5",
				"1:2:3",
				".:1",
				"1e3:1",
				" 5:1",
				"0x10:1",
			}
			for _, v in bad do
				local l, e = budget.limits(v)
				t.expect(l).toBe(nil)
				t.expect(e).toBe(refusal(v))
			end
		end
	)

	it("AC1: the measurer's line is read only as the last line, and taken off", function()
		local cpu, rest = budget.takeCpu("FAIL x\n1 passed, 0 failed, 1 spec files\nzn-spec-cpu 1.250\n")
		t.expect(cpu).toBe(1.25)
		t.expect(rest).toBe("FAIL x\n1 passed, 0 failed, 1 spec files\n")
		local c2, r2 = budget.takeCpu("zn-spec-cpu 0.004")
		t.expect(c2).toBe(0.004)
		t.expect(r2).toBe("")
	end)

	it(
		"AC1: no measurer's line, one that is not last, or a malformed one leaves the output unchanged",
		function()
			local summary = "1 passed, 0 failed, 1 spec files\n"
			local unchanged = {
				summary,
				"zn-spec-cpu 1.000\n" .. summary,
				summary .. "zn-spec-cpu x\n",
				summary .. "zn-spec-cpu 1\n",
				summary .. " zn-spec-cpu 1.000\n",
				summary .. "xzn-spec-cpu 1.000\n",
				-- the last line is 65 bytes and its last 64 begin like the measurer's line: it is not the measurer's
				summary .. "x" .. "zn-spec-cpu 1." .. string.rep("0", 50) .. "\n",
				"",
			}
			for _, s in unchanged do
				local cpu, rest = budget.takeCpu(s)
				t.expect(cpu).toBe(nil)
				t.expect(rest).toBe(s)
			end
		end
	)

	it("AC1: a megabyte line before the measurer's line, or as the last line, is read at once", function()
		local long = 'FAIL x :: y\n     expected "'
			.. string.rep("a", 1000000)
			.. '"\n1 passed, 1 failed, 1 spec files\n'
		local cpu, rest = budget.takeCpu(long .. "zn-spec-cpu 0.100\n")
		t.expect(cpu).toBe(0.1)
		t.expect(rest == long).toBe(true)
		local none = "1 passed, 0 failed, 1 spec files\n" .. string.rep("b", 1000000)
		local c2, r2 = budget.takeCpu(none)
		t.expect(c2).toBe(nil)
		t.expect(r2 == none).toBe(true)
	end)

	it("AC1: a file is over when its wall or its cpu is strictly over the limit", function()
		local costs: { Cost } = {
			{ file = "tests/at.spec.luau", seconds = 10, cpu = 5 },
			{ file = "tests/wall.spec.luau", seconds = 10.01, cpu = 1 },
			{ file = "tests/cpu.spec.luau", seconds = 2, cpu = 5.01 },
			{ file = "tests/under.spec.luau", seconds = 9, cpu = 4 },
			{ file = "tests/nocpu.spec.luau", seconds = 9 },
			{ file = "tests/nocpu-slow.spec.luau", seconds = 11 },
		}
		local names = {}
		for _, c in budget.over(costs, { seconds = 10, cpu = 5 }) do
			table.insert(names, c.file)
		end
		t.expect(names)
			.toEqual({ "tests/nocpu-slow.spec.luau", "tests/wall.spec.luau", "tests/cpu.spec.luau" })
	end)

	it("AC1: over budget is slowest first, ties by path", function()
		local costs: { Cost } = {
			{ file = "tests/b.spec.luau", seconds = 70, cpu = 1 },
			{ file = "tests/c.spec.luau", seconds = 90, cpu = 1 },
			{ file = "tests/a.spec.luau", seconds = 70, cpu = 1 },
		}
		local over = budget.over(costs, budget.DEFAULT)
		t.expect({ over[1].file, over[2].file, over[3].file }).toEqual({
			"tests/c.spec.luau",
			"tests/a.spec.luau",
			"tests/b.spec.luau",
		})
	end)

	it("AC1: nothing over renders nothing", function()
		t.expect(budget.render({}, budget.DEFAULT)).toBe(nil)
	end)

	it("AC1: the report names the limits and the lesson, then each file's wall and cpu", function()
		local costs: { Cost } = {
			{ file = "tests/a.spec.luau", seconds = 75.24, cpu = 41 },
			{ file = "tests/b.spec.luau", seconds = 61.06 },
		}
		t.expect(budget.render(costs, budget.DEFAULT)).toBe(
			`over budget: 2 spec files over 60 s wall or 5 s cpu (lesson {LESSON})\n`
				.. "  tests/a.spec.luau 75.2 s wall, 41.0 s cpu\n"
				.. "  tests/b.spec.luau 61.1 s wall, cpu not measured"
		)
		local one: { Cost } = { { file = "x", seconds = 1, cpu = 0.3 } }
		t.expect(budget.render(one, { seconds = 0.5, cpu = 0.125 })).toBe(
			`over budget: 1 spec files over 0.5 s wall or 0.125 s cpu (lesson {LESSON})\n  x 1.0 s wall, 0.3 s cpu`
		)
	end)

	it("AC1: the report shows ten files and counts the rest", function()
		local list: { Cost } = {}
		for i = 1, 12 do
			table.insert(
				list,
				{ file = string.format("tests/f%02d.spec.luau", i), seconds = 100 - i, cpu = 1 }
			)
		end
		local lines = string.split(budget.render(list, budget.DEFAULT) :: string, "\n")
		t.expect(#lines).toBe(12)
		t.expect(lines[1]).toBe(`over budget: 12 spec files over 60 s wall or 5 s cpu (lesson {LESSON})`)
		t.expect(lines[2]).toBe("  tests/f01.spec.luau 99.0 s wall, 1.0 s cpu")
		t.expect(lines[11]).toBe("  tests/f10.spec.luau 90.0 s wall, 1.0 s cpu")
		t.expect(lines[12]).toBe("  and 2 more")
		local ten = { table.unpack(list, 1, 10) }
		t.expect(#string.split(budget.render(ten, budget.DEFAULT) :: string, "\n")).toBe(11)
	end)
end)
