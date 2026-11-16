--!strict
-- R0072 review-001 F1 and F4: every assignment form voids the advance proof, and an unreadable loop body needs a sweep.
local loops = require("@tests/lib/loops")
local t = require("@tests/lib/t")

local function one(text: string): loops.Loop
	local found = loops.find(text)
	t.expect(#found).toBe(1)
	return found[1]
end

local function stepped(body: string): string
	return `while i < n do\n\ti += 1\n\t{body}\nend\n`
end

return t.spec("R0072 review-001 loop writes and unreadable bodies", function(it)
	it("does not prove a loop whose variable takes any compound assignment", function()
		for _, op in { "*=", "/=", "//=", "%=", "^=", "..=" } do
			t.expect(one(stepped(`i {op} 2`)).advances).toBe(false)
		end
	end)

	it("does not prove a loop with a typed local or for declaration shadowing its variable", function()
		t.expect(one(stepped("local i: number = 0")).advances).toBe(false)
		t.expect(one(stepped("for i: number = 1, 2 do\n\t\tprint(i)\n\tend")).advances).toBe(false)
	end)

	it("still proves a stepped loop with comparisons and method calls", function()
		t.expect(one("while i < n do\n\ti += 1\nend\n").advances).toBe(true)
		t.expect(one(stepped("if i == n or i ~= 0 then\n\t\tt:push(i)\n\tend")).advances).toBe(true)
	end)

	it("treats a loop whose end it cannot find as reading text and requiring a sweep", function()
		local text =
			"while i <= #text do\n\tlocal c = string.sub(text, i, i)\n\tlocal s = [[\nlong\n]]\n\ti = g(text, i)\nend\n"
		local found = one(text)
		t.expect(found.scansText).toBe(true)
		local problems = loops.problems("fixture.luau", text, {
			{ loop = found.header, why = "the helper advances or this entry is rejected" },
		}, {})
		t.expect(#problems).toBe(1)
		t.expect(string.find(problems[1], "reads text", 1, true) ~= nil).toBe(true)
	end)

	it("does not call a readable loop with no text operation a text scanner", function()
		t.expect(one("while true do\n\tbreak\nend\n").scansText).toBe(false)
	end)

	it("does not prove a wrapped assignment of the variable or the bound", function()
		t.expect(
			one("while i < n do\n\ti += 1\n\tif state.reset then\n\t\ti =\n\t\t\tstate.current\n\tend\nend\n").advances
		).toBe(false)
		t.expect(one("while i < n do\n\ti +=\n\t\t1\nend\n").advances).toBe(false)
		t.expect(one("while i <= #items do\n\ti += 1\n\titems =\n\t\tstate.previous\nend\n").advances)
			.toBe(false)
	end)

	it("still proves when a wrapped local names neither the variable nor the bound", function()
		t.expect(one("while i < n do\n\ti += 1\n\tlocal x =\n\t\tstate.currentDocument\nend\n").advances)
			.toBe(true)
	end)

	it("reads a header comment that ends in end as a body, and asks for a sweep", function()
		local function asks(text: string)
			local found = one(text)
			t.expect(found.scansText).toBe(true)
			local problems = loops.problems("fixture.luau", text, {
				{ loop = found.header, why = "the helper advances or this entry is rejected" },
			}, {})
			t.expect(#problems).toBe(1)
			t.expect(string.find(problems[1], "reads text", 1, true) ~= nil).toBe(true)
		end
		asks(
			"while i <= #text do -- read to the end\n\tlocal c = string.sub(text, i, i)\n\ti = g(text, i)\nend\n"
		)
		asks(
			"repeat -- scan up to the end\n\tlocal c = string.sub(text, i, i)\n\ti = g(text, i)\nuntil i > n\n"
		)
	end)

	it("treats an unfound end with no text call as reading text", function()
		local text = "while i < n do\n\ti += 1\n[[\nlong\n]]\nend\n"
		t.expect(one(text).scansText).toBe(true)
	end)

	it("refuses sweep = true and accepts an explicit false", function()
		local text = "while i <= #text do\n\tlocal c = string.sub(text, i, i)\n\ti = g(text, i)\nend\n"
		local found = one(text)
		local entries: { loops.Allowed } = {
			{ loop = found.header, why = "the helper advances, reviewed", sweep = false },
		}
		local none = loops.problems("fixture.luau", text, entries, {})
		t.expect(#none).toBe(0)
		local raw: { any } = {
			{ loop = found.header, why = "the helper advances, reviewed", sweep = true },
		}
		local bad = loops.problems("fixture.luau", text, raw :: any, {})
		t.expect(#bad).toBe(1)
		t.expect(string.find(bad[1], "or false", 1, true) ~= nil).toBe(true)
	end)

	it("does not prove a bound written by a wrapped call, an owner or a split method", function()
		local wrapped =
			"while head <= #queue do\n\tlocal item = queue[head]\n\thead += 1\n\ttable.insert(\n\t\tqueue,\n\t\tchildOf(item)\n\t)\nend\n"
		t.expect(one(wrapped).advances).toBe(false)
		t.expect(one("while i <= opts.max do\n\ti += 1\n\topts = { max = i + 1 }\nend\n").advances)
			.toBe(false)
		t.expect(one('while i <= opts.max do\n\ti += 1\n\topts["max"] = i + 1\nend\n').advances).toBe(false)
		t.expect(one("while i <= #q do\n\ti += 1\n\ttable.move(a, 1, 1, #q + 1, q)\nend\n").advances)
			.toBe(false)
		t.expect(one("while i <= #q do\n\ti += 1\n\tq\n\t\t:push(i)\nend\n").advances).toBe(false)
	end)

	it("still proves loops whose bound is only read", function()
		t.expect(one("while i <= opts.max do\n\ti += 1\nend\n").advances).toBe(true)
		t.expect(one("while i <= #items do\n\tlocal c = items[i]\n\ti += 1\nend\n").advances).toBe(true)
		local other = "while i <= #items do\n\ti += 1\n\ttable.insert(\n\t\tout,\n\t\tx\n\t)\nend\n"
		t.expect(one(other).advances).toBe(true)
	end)

	it("does not prove a step inside a block comment or a long string", function()
		t.expect(one("while i <= n do\n\tf(i)\n\t--[[\n\ti += 1\n\t]]\nend\n").advances).toBe(false)
		t.expect(one("while i <= n do\n\tlocal s = [[\n\ti += 1\n\t]]\n\temit(s)\nend\n").advances)
			.toBe(false)
		t.expect(one("while i <= n do\n\tlocal c = rows[cols[i]]\n\ti += 1\nend\n").advances).toBe(true)
	end)
end)
