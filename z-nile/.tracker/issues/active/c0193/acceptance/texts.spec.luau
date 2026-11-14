--!strict
-- c0193 AC2: hostile.texts builds every short text over the hostile characters, in a fixed order and without
-- randomness, and refuses a request that is empty, ambiguous or too large.
local hostile = require("@tests/lib/hostile")
local t = require("@tests/lib/t")

return t.spec("c0193 hostile.texts", function(it)
	it("lists the empty text, then every text of each length in the alphabet's order", function()
		t.expect(hostile.texts({ "a", "b" }, 2)).toEqual({ "", "a", "b", "aa", "ab", "ba", "bb" })
	end)

	it("a length of 0 gives only the empty text", function()
		t.expect(hostile.texts({ "a", "b" }, 0)).toEqual({ "" })
	end)

	it(
		"the default is every text of up to 4 characters over hostile.ALPHABET: the sum of its powers",
		function()
			local all = hostile.texts()
			local n = #hostile.ALPHABET
			t.expect(#all).toBe(1 + n + n ^ 2 + n ^ 3 + n ^ 4)
			t.expect(all[1]).toBe("")
			t.expect(all[2]).toBe(hostile.ALPHABET[1])
			t.expect(all[#all]).toBe(string.rep(hostile.ALPHABET[n], 4))
		end
	)

	it(
		"covers the characters that broke raftcheck: a lone backslash, an open quote, an unterminated expansion",
		function()
			local set: { [string]: boolean } = {}
			for _, s in hostile.texts() do
				set[s] = true
			end
			t.expect(set["\\"]).toBe(true)
			t.expect(set["'"]).toBe(true)
			t.expect(set['"\\']).toBe(true)
			t.expect(set["$("]).toBe(true)
			t.expect(set["a\\\n"]).toBe(true)
			-- the long-bracket, tab, assignment and comment characters the swept scanners branch on
			for _, c in { "[", "]", "=", "\t", "#", "`", "$", "-" } do
				t.expect(`{string.format("%q", c)} {set[c] == true}`).toBe(`{string.format("%q", c)} true`)
			end
		end
	)

	it("is the same list on every call", function()
		t.expect(hostile.texts({ "x", "y", "z" }, 3)).toEqual(hostile.texts({ "x", "y", "z" }, 3))
	end)

	it("has no text twice", function()
		local seen: { [string]: boolean } = {}
		local dup = 0
		for _, s in hostile.texts() do
			if seen[s] then
				dup += 1
			end
			seen[s] = true
		end
		t.expect(dup).toBe(0)
	end)

	it(
		"refuses an empty alphabet, a repeated or longer entry, a bad length and a request over MAX_TEXTS",
		function()
			t.expect(function()
				hostile.texts({}, 2)
			end).toThrow("empty alphabet")
			t.expect(function()
				hostile.texts({ "a", "a" }, 2)
			end).toThrow("repeated")
			t.expect(function()
				hostile.texts({ "ab" }, 2)
			end).toThrow("not one character")
			t.expect(function()
				hostile.texts({ "a" }, -1)
			end).toThrow("whole number")
			t.expect(function()
				hostile.texts({ "a" }, 1.5)
			end).toThrow("whole number")
			t.expect(function()
				hostile.texts(nil, 5)
			end).toThrow("more than")
		end
	)
end)
