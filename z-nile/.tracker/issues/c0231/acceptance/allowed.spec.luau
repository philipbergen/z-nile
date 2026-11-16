--!strict
-- c0231 AC2: a `yes` that a `head` reads straight from its pipe passes (c0191's promoted spec requires `yes | head -3`),
-- in every spelling and nesting, and the wrapper runs any `yes` pipeline.
local boundcmd = require("@znile/engine/boundcmd")
local t = require("@tests/lib/t")

local function expectOk(commands: { string }, ctx: boundcmd.Context?)
	for _, command in commands do
		local v = boundcmd.check(command, ctx)
		t.expect(`{command}: {if v.ok then "ok" else tostring(v.rule)}`).toBe(`{command}: ok`)
	end
end

return t.spec("c0231 a yes that head reads passes", function(it)
	it("AC2: yes piped straight into head passes, with any non-negative count and either pipe", function()
		expectOk({
			"yes | head -3",
			"yes | head",
			"yes n | head -n 5",
			"yes | head -n3",
			"yes | head -c 100",
			"yes | head --lines=2",
			"yes | head --bytes 10",
			"yes |& head -1",
			"yes | /usr/bin/head -2",
			"yes |\nhead -2",
			"yes 2>/dev/null | head -1",
			"yes 2>&1 | head -1",
			"yes | head -3 | sort",
			"yes | head -3 > out",
			"yes | (head -3)",
			"yes | { head -3; }",
			"yes | env LC_ALL=C head -3",
			"env yes | head -3",
			"/usr/bin/yes y | head -1",
			"caffeinate -t 5 yes | head -1",
		})
	end)

	it("AC2: a head-fed yes passes inside $(...), sh -c, eval and beside other commands", function()
		expectOk({
			"x=$(yes | head -1)",
			"echo `yes n | head -2`",
			"sh -c 'yes | head -3'",
			"eval 'yes | head -3'",
			"cd d && yes | head -3; echo done",
			"bash <<EOF\nyes | head -2\nEOF",
		})
	end)

	it("AC2: the wrapper runs any yes pipeline", function()
		expectOk({
			"./zn run --time 10 -- sh -c 'yes | rm -i a'",
			"./zn run --time 5 -- yes",
		})
	end)
end)
