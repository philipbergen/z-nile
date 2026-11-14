--!strict
-- c0193 AC1: scan.advance is the fail-closed step of a scanning loop: it returns the next position only when that is
-- past the current one, and raises, naming both, when the position stays, goes back, or is not a number.
local scan = require("@znile/engine/scan")
local t = require("@tests/lib/t")

return t.spec("c0193 scan.advance", function(it)
	it("returns the next position when it is past the current one", function()
		t.expect(scan.advance(1, 2)).toBe(2)
		t.expect(scan.advance(5, 9)).toBe(9)
		t.expect(scan.advance(0, 1)).toBe(1)
	end)

	it("raises when the position stays where it was, naming both", function()
		t.expect(function()
			scan.advance(3, 3)
		end).toThrow("scanner did not advance: from 3 to 3")
	end)

	it("raises when the position goes back", function()
		t.expect(function()
			scan.advance(3, 2)
		end).toThrow("from 3 to 2")
	end)

	it("raises on a position that is not a number", function()
		t.expect(function()
			scan.advance(3, 0 / 0)
		end).toThrow("did not advance")
	end)

	it(
		"[zz-arch/scanning-loops-advance] turns the incident's loop shape into an error instead of a spin",
		function()
			-- a stop helper that returns its start on a backslash, as raftcheck's word() did (PR #125)
			local function stop(text: string, i: number): number
				local j = i
				while j <= #text and string.sub(text, j, j) ~= " " and string.sub(text, j, j) ~= "\\" do
					j += 1
				end
				return j
			end
			local function walk(text: string)
				local i = 1
				local fuel = 0 -- a spec must not spin, even for a wrong scan.advance
				while i <= #text do
					fuel += 1
					if fuel > 100 then
						error("walk spun")
					end
					if string.sub(text, i, i) == " " then
						i += 1
					else
						i = scan.advance(i, stop(text, i))
					end
				end
			end
			walk("ab cd ef") -- a well-formed text still walks to its end
			t.expect(function()
				walk("ab \\ cd")
			end).toThrow("did not advance")
		end
	)
end)
