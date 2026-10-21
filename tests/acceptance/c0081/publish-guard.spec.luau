--!strict
-- c0870: every publish from the tracker CLI first refuses a tree from before a compaction (`refuseStale()`).
-- `cmd.remap` is the only exception: it is the way out of that state. A command added later that calls publish.commit
-- without refusing first fails here instead of publishing from a stale tree. (Overridden by R0025's c0070, which puts
-- every publish site behind `published(...)` for the board refresh, so the one-helper rule became a per-function one.)
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

export type Mention = { fn: string, code: string, refused: boolean }

-- each mention of `publish.commit` outside comments, with its top-level function (a line starting `function ` or
-- `local function `) and whether the code line right before it (blank and comment-only lines skipped) calls
-- `refuseStale()`: a call, or an alias such as `local commit = publish.commit`, which would get past a call-only check
local function mentions(text: string): { Mention }
	local out: { Mention } = {}
	local current, previous = "(top level)", ""
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		local name = string.match(line, "^function ([%w_%.:]+)%(")
			or string.match(line, "^local function ([%w_]+)%(")
		if name then
			current = name
		end
		local code = string.gsub(line, "%-%-.*$", "") -- comments do not count
		if string.find(code, "publish.commit", 1, true) then
			table.insert(out, {
				fn = current,
				code = code,
				refused = string.find(previous, "refuseStale()", 1, true) ~= nil,
			})
		end
		if string.match(code, "%S") then
			previous = code
		end
	end
	return out
end

return t.spec("c0870 every publish checks for a stale tree", function(it)
	it("main.luau refuses a stale tree right before every publish.commit but remap's", function()
		local found = mentions(fs.readFile("z-nile/engine/main.luau"))
		t.expect(#found > 0).toBe(true)
		local others = 0
		for _, m in found do
			t.expect(string.find(m.code, "publish.commit(", 1, true) ~= nil).toBe(true) -- a call, never an alias
			if m.fn ~= "cmd.remap" then
				others += 1
				t.expect(m.refused).toBe(true)
			end
		end
		t.expect(others > 0).toBe(true)
	end)

	it("the finder sees a call or an alias in any other function, and ignores comments", function()
		local sample = "local function fresh(a)\n\trefuseStale()\n\t-- why\n\n\treturn publish.commit(a)\nend\n"
			.. "function cmd.ready(p)\n\trefuseStale()\n\tlocal x = 1\n\tlocal r = publish.commit(p)\n\trefuseStale()\nend\n"
			.. "function cmd.stop()\n\t-- publish.commit( is not called here\nend\n"
			.. "local function sneaky()\n\tlocal commit = publish.commit\nend\n"
		local got = mentions(sample)
		t.expect(#got).toBe(3)
		t.expect({ got[1].fn, got[2].fn, got[3].fn }).toEqual({ "fresh", "cmd.ready", "sneaky" })
		t.expect({ got[1].refused, got[2].refused, got[3].refused }).toEqual({ true, false, false })
		t.expect(string.find(got[3].code, "publish.commit(", 1, true) == nil).toBe(true)
	end)
end)
