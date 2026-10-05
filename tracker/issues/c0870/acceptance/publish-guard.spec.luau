--!strict
-- c0870: every publish from the tracker CLI goes through `publishFresh`, the one helper that refuses a tree from
-- before a compaction. `cmd.remap` is the only exception: it is the way out of that state. A command added later
-- (R0250's ready and stop, say) that calls publish.commit directly fails here instead of publishing from a stale tree.
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

-- the top-level function (a line starting `function ` or `local function `) around each mention of `publish.commit`
-- outside comments: a call, or an alias such as `local commit = publish.commit`, which would get past a call-only check
local function callers(text: string): { string }
	local out: { string } = {}
	local current = "(top level)"
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		local name = string.match(line, "^function ([%w_%.:]+)%(")
			or string.match(line, "^local function ([%w_]+)%(")
		if name then
			current = name
		end
		local code = string.gsub(line, "%-%-.*$", "") -- comments do not count
		if string.find(code, "publish.commit", 1, true) then
			table.insert(out, current)
		end
	end
	return out
end

return t.spec("c0870 every publish checks for a stale tree", function(it)
	it("main.luau calls publish.commit only in publishFresh and cmd.remap", function()
		local found = callers(fs.readFile("scripts/tracker/main.luau"))
		t.expect(#found > 0).toBe(true)
		local seenFresh = false
		for _, name in found do
			t.expect(name == "publishFresh" or name == "cmd.remap").toBe(true)
			seenFresh = seenFresh or name == "publishFresh"
		end
		t.expect(seenFresh).toBe(true)
	end)

	it("the finder sees a call or an alias in any other function, and ignores comments", function()
		local sample = "local function publishFresh(a)\n\treturn publish.commit(a)\nend\n"
			.. "function cmd.ready(p)\n\tlocal r = publish.commit(p)\nend\n"
			.. "function cmd.stop()\n\t-- publish.commit( is not called here\nend\n"
			.. "local function sneaky()\n\tlocal commit = publish.commit\nend\n"
		t.expect(callers(sample)).toEqual({ "publishFresh", "cmd.ready", "sneaky" })
	end)
end)
