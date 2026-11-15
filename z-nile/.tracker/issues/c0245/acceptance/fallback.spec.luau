--!strict
-- c0245 AC3: the seatbelt's tooling match decides by the file a `lune run` target reaches in this checkout (R0075
-- review 002 F3): its path from the top of its tree (the checkout or one of its worktrees) is an entry of TOOLING or a
-- registered home's runner, written relative or absolute; a path that leaves the checkout never is, and no suffix
-- counts. What stays when the checkout or the folder is unknown.
local boundcmd = require("@znile/engine/boundcmd")
local t = require("@tests/lib/t")

local C = "/Users/me/code/pickman"

return t.spec("c0245 with too little context the path alone decides", function(it)
	it("AC3: with no checkout, or a relative path and no folder, the path alone decides as before", function()
		local cases = {
			{ command = "lune run tests/run", ctx = {} :: boundcmd.Context, want = true },
			{ command = "lune run ../../z-nile/tests/run", ctx = {} :: boundcmd.Context, want = true },
			{ command = "lune run /x/y/tests/run", ctx = {} :: boundcmd.Context, want = true },
			{ command = "lune run /x/y/z-nile/affected", ctx = {} :: boundcmd.Context, want = true },
			{ command = "lune run /x/y/probe", ctx = {} :: boundcmd.Context, want = false },
			{
				command = "lune run snake/tests/run",
				ctx = { homes = { "snake" } } :: boundcmd.Context,
				want = true,
			},
			{ command = "lune run tests/run", ctx = { checkout = C } :: boundcmd.Context, want = true },
			{
				command = "lune run nowhere/tests/run",
				ctx = { checkout = C } :: boundcmd.Context,
				want = false,
			},
			-- an absolute path with a known checkout is read by its file even when the call names no folder
			{
				command = `lune run {C}/nowhere/tests/run`,
				ctx = { checkout = C } :: boundcmd.Context,
				want = false,
			},
		}
		local bad: { string } = {}
		for _, c in cases do
			if boundcmd.check(c.command, c.ctx).ok ~= c.want then
				table.insert(bad, `{c.command}: expected {if c.want then "ok" else "refused"}`)
			end
		end
		t.expect(table.concat(bad, "\n")).toBe("")
	end)
end)
