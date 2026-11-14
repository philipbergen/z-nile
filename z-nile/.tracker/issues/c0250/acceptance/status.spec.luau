--!strict
-- c0250 AC1: `blocked` is a status with exactly four new edges, stamped and parsed like the others, and a command that
-- is not block or resolve cannot take them. Pure over engine/status; the refusals of `./zn status` are pinned in the
-- engine's source here and exercised in block-resolve.spec (real git in a fixture).
local fs = require("@lune/fs")
local process = require("@lune/process")
local status = require("@znile/engine/status")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local ALL = { "new", "preparing", "prepared", "active", "blocked", "done" }
local ALLOWED = {
	["new>preparing"] = true,
	["preparing>prepared"] = true,
	["preparing>new"] = true,
	["prepared>active"] = true,
	["prepared>preparing"] = true,
	["active>prepared"] = true,
	-- c0250: ./zn block takes the first two and ./zn resolve the last two
	["preparing>blocked"] = true,
	["active>blocked"] = true,
	["blocked>new"] = true,
	["blocked>prepared"] = true,
}

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

return t.spec("c0250 blocked is a status", function(it)
	it(
		"AC1: blocked is a status with four edges, stamped and parsed like the others, and status refuses to block or unblock",
		function()
			-- exactly the ten edges of the 36 pairs, and no more
			local edges = 0
			for _, from in ALL do
				for _, to in ALL do
					local want = ALLOWED[`{from}>{to}`] == true
					t.expect(status.canMove(from, to)).toBe(want)
					if want then
						edges += 1
					end
				end
			end
			t.expect(edges).toBe(10)
			-- blocked never goes straight back to where it came from by an edge it was not given
			t.expect(status.canMove("blocked", "active")).toBe(false)
			t.expect(status.canMove("blocked", "preparing")).toBe(false)
			t.expect(status.canMove("blocked", "done")).toBe(false)
			t.expect(status.canMove("new", "blocked")).toBe(false)
			t.expect(status.canMove("prepared", "blocked")).toBe(false)
			-- none of the new edges rides a pull request
			for _, edge in
				{
					{ "preparing", "blocked" },
					{ "active", "blocked" },
					{ "blocked", "new" },
					{ "blocked", "prepared" },
				}
			do
				t.expect(status.carriedByPr(edge[1], edge[2])).toBe(false)
			end
			-- a stamp is `blocked-` and three words, and parse and phrase read it back
			local value = status.stamp("blocked", function(max)
				return max
			end)
			t.expect(string.match(value, "^blocked%-%a+%-%a+%-%a+$") ~= nil).toBe(true)
			t.expect(status.parse(value)).toBe("blocked")
			t.expect(status.parse("blocked")).toBe("blocked")
			t.expect(status.phrase(value) ~= nil).toBe(true)
			t.expect(status.parse("blocked-raging-pink")).toBe(nil)
			-- effective reads it, in the backlog
			t.expect(status.effective({ status = value, design = "ready" }, "backlog")).toBe("blocked")
			t.expect(status.effective({ status = value, raft = "R0100" }, "backlog")).toBe("blocked")
			-- ./zn status neither blocks nor unblocks: the refusals are in the command (exercised in block-resolve.spec)
			local main = fs.readFile(`{TOP}/z-nile/engine/main.luau`)
			t.expect(has(main, "only ./zn block blocks")).toBe(true)
			t.expect(has(main, "only ./zn resolve unblocks")).toBe(true)
		end
	)
end)
