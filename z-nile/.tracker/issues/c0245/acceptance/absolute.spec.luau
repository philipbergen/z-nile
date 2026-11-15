--!strict
-- c0245 AC1: the seatbelt's tooling match decides by the file a `lune run` target reaches in this checkout (R0075
-- review 002 F3): its path from the top of its tree (the checkout or one of its worktrees) is an entry of TOOLING or a
-- registered home's runner, written relative or absolute; a path that leaves the checkout never is, and no suffix
-- counts. Absolute paths, pure over `boundcmd.check`.
local boundcmd = require("@znile/engine/boundcmd")
local t = require("@tests/lib/t")

local C = "/Users/me/code/pickman"
local HOMES = { "pickman", "z-nile", "snake" }

local function ok(command: string, cwd: string?, homes: { string }?): boolean
	return boundcmd.check(command, { checkout = C, cwd = cwd, homes = homes or HOMES }).ok
end

-- every case: the command, the call's folder (nil: none given), and whether it passes
local function expectAll(cases: { { any } }, homes: { string }?)
	local bad: { string } = {}
	for _, c in cases do
		local command, cwd, want = c[1] :: string, c[2] :: string?, c[3] :: boolean
		if ok(command, cwd, homes) ~= want then
			table.insert(
				bad,
				`{command} (from {cwd or "nowhere"}): expected {if want then "ok" else "refused"}`
			)
		end
	end
	t.expect(table.concat(bad, "\n")).toBe("")
end

return t.spec("c0245 an absolute path counts by the file it reaches", function(it)
	it(
		"AC1: an absolute path under the checkout counts only for a registered home's runner or a TOOLING entry",
		function()
			expectAll({
				{ `lune run {C}/snake/tests/run`, "/tmp", true },
				{ `lune run {C}/snake/tests/run.luau -- a`, nil, true },
				{ `lune run {C}/z-nile/affected -- x`, "/tmp", true },
				{ `lune run {C}/.worktree/R1/snake/tests/run`, "/tmp", true },
				{ `lune run {C}/.worktree/R1/scripts/affected`, "/tmp", true },
				-- R0075 review 002 F3's two forms: no home there, a scratch probe under a home's .cache
				{ `lune run {C}/nowhere/tests/run`, "/tmp", false },
				{ `lune run {C}/z-nile/.cache/probe/tests/run.luau`, "/tmp", false },
				-- a TOOLING entry's name below some other folder is not the entry
				{ `lune run {C}/z-nile/.cache/probe/z-nile/affected`, "/tmp", false },
				{ `lune run {C}/.worktree/R1/nowhere/tests/run`, "/tmp", false },
				{ `lune run {C}/.worktree/tests/run`, "/tmp", false },
				-- the root and a worktree's top belong to no project: no runner there
				{ `lune run {C}/tests/run`, "/tmp", false },
				{ `lune run {C}/.worktree/R1/tests/run`, "/tmp", false },
				-- outside the checkout, a folder whose name starts with the checkout's included
				{ "lune run /tmp/x/snake/tests/run", C, false },
				{ `lune run {C}2/snake/tests/run`, C, false },
				{ `lune run {C}`, C, false },
			})
		end
	)

	it(
		"AC1: an absolute path is read by the file it reaches: `.`, `..` and repeated slashes resolved",
		function()
			expectAll({
				{ `lune run {C}/pickman/../snake/tests/run`, "/tmp", true },
				{ `lune run {C}/./snake//tests/./run`, "/tmp", true },
				{ `lune run {C}/../pickman/snake/tests/run`, "/tmp", true },
				{ `lune run {C}/snake/tests/run/../../probe`, "/tmp", false },
				{ `lune run {C}/snake/../nowhere/tests/run`, "/tmp", false },
				-- `/..` is `/`, as the file system reads it
				{ `lune run /../..{C}/snake/tests/run`, "/tmp", true },
				{ "lune run /../../snake/tests/run", C, false },
			})
		end
	)

	it("AC1: an absolute home runner counts only while the registry names the home", function()
		t.expect(ok(`lune run {C}/snake/tests/run`, "/tmp", { "snake" })).toBe(true)
		t.expect(ok(`lune run {C}/snake/tests/run`, "/tmp", { "pickman" })).toBe(false)
		t.expect(ok(`lune run {C}/.worktree/R1/snake/tests/run`, "/tmp", { "pickman" })).toBe(false)
	end)
end)
