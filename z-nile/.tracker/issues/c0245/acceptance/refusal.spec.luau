--!strict
-- c0245 AC4: the seatbelt's tooling match decides by the file a `lune run` target reaches in this checkout (R0075
-- review 002 F3): its path from the top of its tree (the checkout or one of its worktrees) is an entry of TOOLING or a
-- registered home's runner, written relative or absolute; a path that leaves the checkout never is, and no suffix
-- counts. The refusal says why a tooling-looking path is not the gate's.
local boundcmd = require("@znile/engine/boundcmd")
local t = require("@tests/lib/t")

local C = "/Users/me/code/pickman"
local HOMES = { "pickman", "z-nile", "snake" }

return t.spec("c0245 the refusal names why the path is not the gate's", function(it)
	it("AC4: a refused path that looks like the tooling says why it is not the gate's own", function()
		local v =
			boundcmd.check(`lune run {C}/nowhere/tests/run`, { checkout = C, cwd = "/tmp", homes = HOMES })
		t.expect(v.rule).toBe("unbounded")
		local say = boundcmd.explain(v)
		t.expect(string.find(say, `\`{C}/nowhere/tests/run\` here is not the gate's own`, 1, true) ~= nil)
			.toBe(true)
		t.expect(string.find(say, "run --time 60 -- lune run", 1, true) ~= nil).toBe(true)
		-- the parenthesis says where `lune run tests/run` needs no wrapper (design review 001 F3)
		t.expect(
			string.find(say, "`lune run tests/run` from a project's home need no wrapper", 1, true) ~= nil
		)
			.toBe(true)
		-- relative targets and a folder the scanner could not resolve get the reason too (design review 001 F2)
		for _, c in
			{
				{ "lune run tests/run", C, "tests/run" },
				{ "lune run ../../snake/tests/run", `{C}/pickman`, "../../snake/tests/run" },
				{ 'cd "$X" && lune run tests/run', `{C}/snake`, "tests/run" },
			}
		do
			local r = boundcmd.check(c[1], { checkout = C, cwd = c[2], homes = HOMES })
			t.expect(`{c[1]}: {tostring(r.rule)}`).toBe(`{c[1]}: unbounded`)
			local text = boundcmd.explain(r)
			t.expect(`{c[1]}: {string.find(text, `\`{c[3]}\` here is not the gate's own`, 1, true) ~= nil}`)
				.toBe(`{c[1]}: true`)
		end
		-- a probe with no tooling name gets the plain refusal
		local probe =
			boundcmd.explain(boundcmd.check("lune run p2.luau", { checkout = C, cwd = C, homes = HOMES }))
		t.expect(string.find(probe, "not the gate's own", 1, true) ~= nil).toBe(false)
	end)
end)
