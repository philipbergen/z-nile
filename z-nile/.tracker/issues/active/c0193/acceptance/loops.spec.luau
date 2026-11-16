--!strict
-- c0193 AC4: loops.find reads every while and repeat loop of a Luau text and says whether it provably advances: its
-- condition compares a variable, and the loop's own top level steps that variable by a positive literal in the
-- condition's direction (or through scan.advance) before any continue. Anything else, including a loop it cannot read
-- whole, is not proven.
local loops = require("@tests/lib/loops")
local t = require("@tests/lib/t")

local function src(...: string): string
	return table.concat({ ... }, "\n") .. "\n"
end

local function first(text: string): loops.Loop
	local found = loops.find(text)
	t.expect(#found >= 1).toBe(true)
	return found[1]
end

return t.spec("c0193 loops.find", function(it)
	it("proves a loop that steps its variable by a literal at its top level", function()
		t.expect(first(src("while i <= #items do", "\tlocal c = items[i]", "\ti += 1", "end")).advances)
			.toBe(true)
		t.expect(first(src("while i < n do", "\ti = i + 2", "end")).advances).toBe(true)
		t.expect(first(src("while n >= 1 do", "\tn -= 1", "end")).advances).toBe(true)
		t.expect(first(src("while n > 0 do", "\tn = n - 3", "end")).advances).toBe(true)
		t.expect(first(src("while i <= n do", "\ti += 1 -- past the char", "end")).advances).toBe(true)
	end)

	it("proves a loop that steps through scan.advance", function()
		t.expect(first(src("while i <= #text do", "\ti = scan.advance(i, next(text, i))", "end")).advances)
			.toBe(true)
	end)

	it(
		"[zz-arch/scanning-loops-advance] does not prove a step that only some branches take (the incident's loop shape)",
		function()
			local l = first(
				src(
					"while j <= #text do",
					"\tlocal ch = string.sub(text, j, j)",
					"\tif ch == ' ' then",
					"\t\tj += 1",
					"\telse",
					"\t\tlocal nxt = word(text, j)",
					"\t\tj = nxt",
					"\tend",
					"end"
				)
			)
			t.expect(l.advances).toBe(false)
			t.expect(l.header).toBe("while j <= #text do")
			t.expect(l.line).toBe(1)
			t.expect(l.scansText).toBe(true)
		end
	)

	it("does not prove a step whose size is not a positive literal", function()
		t.expect(first(src("while i <= n do", "\ti += 0", "end")).advances).toBe(false)
		t.expect(first(src("while i <= n do", "\ti += step", "end")).advances).toBe(false)
		t.expect(first(src("while i <= n do", "\ti += -1", "end")).advances).toBe(false)
		t.expect(first(src("while i <= n do", "\ti = j", "end")).advances).toBe(false)
		t.expect(first(src("while i <= n do", "\ti += if a then 2 else 1", "end")).advances).toBe(false)
	end)

	it("does not prove a step in the wrong direction, or of another variable", function()
		t.expect(first(src("while i <= n do", "\ti -= 1", "end")).advances).toBe(false)
		t.expect(first(src("while i >= 1 do", "\ti += 1", "end")).advances).toBe(false)
		t.expect(first(src("while i <= n do", "\tj += 1", "end")).advances).toBe(false)
		t.expect(first(src("while i >= 1 do", "\ti = scan.advance(i, k)", "end")).advances).toBe(false)
	end)

	it(
		"does not prove a step that a continue before it can skip, and does prove one with a continue after it",
		function()
			t.expect(
				first(src("while i <= n do", "\tif a then", "\t\tcontinue", "\tend", "\ti += 1", "end")).advances
			).toBe(false)
			t.expect(
				first(src("while i <= n do", "\ti += 1", "\tif a then", "\t\tcontinue", "\tend", "end")).advances
			).toBe(true)
		end
	)

	it("does not prove a step nested deeper than the loop's own level, or one in a comment", function()
		t.expect(first(src("while i <= n do", "\tif a then", "\t\ti += 1", "\tend", "end")).advances)
			.toBe(false)
		t.expect(first(src("while i <= n do", "\t-- i += 1", "end")).advances).toBe(false)
		t.expect(first(src("while i <= n do", "\tfor _ = 1, 2 do", "\t\ti += 1", "\tend", "end")).advances)
			.toBe(false)
	end)

	it(
		"does not prove loops with no position to prove: while true, repeat, a call, an or, a table field",
		function()
			t.expect(first(src("while true do", "\tbreak", "end")).advances).toBe(false)
			t.expect(first(src("repeat", "\ti += 1", "until i > 3")).advances).toBe(false)
			t.expect(first(src("while #stack > 0 do", "\ti += 1", "end")).advances).toBe(false)
			t.expect(first(src("while i <= n or more do", "\ti += 1", "end")).advances).toBe(false)
			t.expect(first(src("while t.i <= n do", "\tt.i += 1", "end")).advances).toBe(false)
		end
	)

	it(
		"fails closed on a header it cannot read whole: several lines, a one-liner, a loop with no end",
		function()
			t.expect(first(src("while", "\ti <= n", "do", "\ti += 1", "end")).advances).toBe(false)
			t.expect(first(src("while i <= n do i += 1 end")).advances).toBe(false)
			t.expect(first(src("while i <= n do", "\ti += 1")).advances).toBe(false)
		end
	)

	it("reads indented and nested loops, each on its own, in order, with their lines", function()
		local found = loops.find(
			src(
				"local function f()",
				"\twhile i <= n do",
				"\t\tlocal ok = string.find(text, 'x', i, true)",
				"\t\twhile true do",
				"\t\t\tbreak",
				"\t\tend",
				"\t\ti += 1",
				"\tend",
				"end"
			)
		)
		t.expect(#found).toBe(2)
		t.expect(found[1].advances).toBe(false) -- it reads text, so it is never proven (see the next case)
		t.expect(found[1].line).toBe(2)
		t.expect(found[1].scansText).toBe(true)
		t.expect(found[2].advances).toBe(false)
		t.expect(found[2].header).toBe("while true do")
		t.expect(found[2].line).toBe(4)
		t.expect(found[2].scansText).toBe(false)
	end)

	it("ignores for loops, a commented loop and text with no loop", function()
		t.expect(#loops.find(src("for i = 1, 3 do", "\tprint(i)", "end", "-- while true do", "local x = 1")))
			.toBe(0)
		t.expect(#loops.find("")).toBe(0)
	end)

	it(
		"ends a one-line loop and a repeat at their own end, so the lines after them are not their body",
		function()
			local after = "local c = string.sub(s, 1, 1)"
			local one = loops.find(src("while i <= n do i += 1 end", after))
			t.expect(one[1].scansText).toBe(false)
			local rep = loops.find(src("repeat", "\ti += 1", "until i > 3", after))
			t.expect(rep[1].scansText).toBe(false)
		end
	)

	it("does not prove a loop that also resets, steps back or rewrites its variable, at any depth", function()
		t.expect(first(src("while i <= n do", "\ti = 1", "\ti += 1", "end")).advances).toBe(false)
		t.expect(
			first(src("while i <= n do", "\ti += 1", "\tif x then", "\t\ti -= 1", "\tend", "end")).advances
		)
			.toBe(false)
		t.expect(
			first(
				src(
					"while i <= n do",
					"\ti += 1",
					"\twhile true do",
					"\t\ti = 1",
					"\t\tbreak",
					"\tend",
					"end"
				)
			).advances
		).toBe(false)
		t.expect(first(src("while i <= n do", "\ti += 1", "\tlocal i = 5", "end")).advances).toBe(false)
		t.expect(first(src("while i <= n do", "\ti += 1", "\ti, j = j, i", "end")).advances).toBe(false)
		t.expect(first(src("while i <= n do", "\ti += 1", "\tfor i = 1, 3 do", "\tend", "end")).advances)
			.toBe(false)
	end)

	it("proves a loop that takes further steps in the same direction, or only reads its variable", function()
		t.expect(
			first(src("while i <= n do", "\ti += 1", "\tif a then", "\t\ti += 1", "\tend", "end")).advances
		)
			.toBe(true)
		t.expect(
			first(
				src(
					"while i <= n do",
					"\tt[i] = i",
					"\tif i == 3 then",
					"\t\tx = i",
					"\tend",
					"\ti += 1",
					"end"
				)
			).advances
		).toBe(true)
	end)

	it(
		"does not prove a loop whose bound is not a number, a name or #name, or that the body writes",
		function()
			t.expect(first(src("while i < math.huge do", "\ti += 1", "end")).advances).toBe(false)
			t.expect(first(src("while i <= f(x) do", "\ti += 1", "end")).advances).toBe(false)
			t.expect(first(src("while i <= #q do", "\ttable.insert(q, q[i])", "\ti += 1", "end")).advances)
				.toBe(false)
			t.expect(first(src("while i <= #q do", "\tq[#q + 1] = q[i]", "\ti += 1", "end")).advances)
				.toBe(false)
			t.expect(first(src("while i <= n do", "\tn += 1", "\ti += 1", "end")).advances).toBe(false)
			t.expect(first(src("while i <= n do", "\tn = n + 1", "\ti += 1", "end")).advances).toBe(false)
			t.expect(first(src("while i <= #q do", "\tq:push(i)", "\ti += 1", "end")).advances).toBe(false)
			t.expect(
				first(
					src(
						"while i <= #args do",
						"\tlocal a = args[i]",
						"\tif a == 'x' then",
						"\t\ti += 1",
						"\tend",
						"\ti += 1",
						"end"
					)
				).advances
			).toBe(true)
			t.expect(first(src("while i <= 10 do", "\ti += 1", "end")).advances).toBe(true)
			t.expect(first(src("while i <= opts.max do", "\ti += 1", "end")).advances).toBe(true)
		end
	)

	it(
		"finds a loop's end by its structure: a trailing comment on end, a wrong end line, blank lines",
		function()
			local found = loops.find(
				src(
					"local function f()",
					"\twhile i <= n do",
					"\t\ti = nextOf(i)",
					"\tend -- the end",
					"end",
					"local function g()",
					"\twhile i <= m do",
					"\t\ti += 1",
					"\tend",
					"end"
				)
			)
			t.expect(#found).toBe(2)
			t.expect(found[1].advances).toBe(false)
			t.expect(found[2].advances).toBe(true)
			-- a line at the loop's indent that is not its end leaves the end unfound
			t.expect(first(src("do", "\twhile i <= n do", "\t\ti += 1", "\telse", "\tend", "end")).advances)
				.toBe(false)
			-- a trailing comment on a provable loop's end is still its end
			t.expect(first(src("while i <= n do", "\ti += 1", "end -- done")).advances).toBe(true)
			-- blank lines inside the body do not end it
			t.expect(first(src("while i <= n do", "", "\ti += 1", "", "end")).advances).toBe(true)
		end
	)

	it(
		"never proves a loop that reads text, even with a literal step: a scanner is listed and swept",
		function()
			local text = src("while i <= #text do", "\tlocal c = string.sub(text, i, i)", "\ti += 1", "end")
			local l = first(text)
			t.expect(l.scansText).toBe(true)
			t.expect(l.advances).toBe(false)
			t.expect(first(src("while i <= n do", "\tlocal c = s:byte(i)", "\ti += 1", "end")).advances)
				.toBe(false)
			t.expect(first(src("while i <= n do", "\tlocal c = items[i]", "\ti += 1", "end")).advances)
				.toBe(true)
		end
	)

	it("takes scan.advance only as one whole call, not with a tail after it", function()
		t.expect(first(src("while i <= n do", "\ti = scan.advance(i, f(x))", "end")).advances).toBe(true)
		t.expect(first(src("while i <= n do", "\ti = scan.advance(i, f(x)) - f(k)", "end")).advances)
			.toBe(false)
		t.expect(first(src("while i <= n do", "\ti = scan.advance(i, j) + 0", "end")).advances).toBe(false)
	end)

	it("tells a loop that reads text from one that does not", function()
		t.expect(first(src("while q > 0 do", "\tq = f(q)", "end")).scansText).toBe(false)
		t.expect(first(src("while q > 0 do", "\tlocal c = s:sub(q, q)", "\tq = f(q)", "end")).scansText)
			.toBe(true)
		t.expect(first(src("while string.find(s, 'a', k, true) do", "\tk = f(k)", "end")).scansText)
			.toBe(true)
	end)
end)
