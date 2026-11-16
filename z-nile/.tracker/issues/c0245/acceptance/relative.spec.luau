--!strict
-- c0245 AC2: the seatbelt's tooling match decides by the file a `lune run` target reaches in this checkout (R0075
-- review 002 F3): its path from the top of its tree (the checkout or one of its worktrees) is an entry of TOOLING or a
-- registered home's runner, written relative or absolute; a path that leaves the checkout never is, and no suffix
-- counts. Relative paths from the call's folder and its `cd`s, pure over `boundcmd.check`.
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

return t.spec("c0245 a relative path counts by where it lands", function(it)
	it("AC2: a relative path from a folder counts by where it lands, `..` and all", function()
		expectAll({
			{ "lune run ../snake/tests/run", `{C}/pickman`, true },
			{ "lune run ../../snake/tests/run -- a", `{C}/pickman/tests`, true },
			{ "lune run tests/run", `{C}/snake`, true },
			{ "lune run ./tests/run.luau", `{C}/pickman`, true },
			{ "lune run tests/run", `{C}/.worktree/R1/snake`, true },
			{ "lune run affected -- x", `{C}/z-nile`, true },
			{ "lune run ../z-nile/affected", `{C}/scripts`, true },
			-- the folder the path is read from must be inside the checkout, as before, even when the path reaches into it
			{ "lune run pickman/snake/tests/run", "/Users/me/code", false },
			-- R0075 review 002 F3: `..` that leaves the checkout, from a home
			{ "lune run ../../snake/tests/run", `{C}/pickman`, false },
			{ "lune run ../../../../snake/tests/run", `{C}/pickman`, false },
			{ "lune run ../../../../pickman/tests/run", `{C}/pickman`, false },
			{ "lune run ../nowhere/tests/run", `{C}/pickman`, false },
			-- the runner's name from a folder that is no home's top
			{ "lune run tests/run", `{C}/z-nile/.cache/probe`, false },
			{ "lune run tests/run", `{C}/pickman/tests`, false },
			{ "lune run tests/run", C, false },
			{ "lune run tests/run", `{C}/.worktree/R1`, false },
			{ "lune run snake/tests/run", `{C}/pickman`, false },
		})
	end)

	it("AC2: a relative home runner counts only while the registry names the home", function()
		t.expect(ok("lune run tests/run", `{C}/snake`, { "snake" })).toBe(true)
		t.expect(ok("lune run tests/run", `{C}/snake`, { "pickman" })).toBe(false)
		t.expect(ok("lune run ../snake/tests/run", `{C}/pickman`, { "pickman" })).toBe(false)
	end)

	it("AC2: the `cd`s before the command move the folder the path is read from", function()
		expectAll({
			{ "cd ../snake && lune run tests/run", `{C}/pickman`, true },
			{ "cd .. && lune run pickman/tests/run", `{C}/z-nile`, true },
			{ "cd .. && lune run tests/run", `{C}/z-nile`, false },
			{ "cd .cache && lune run tests/run", `{C}/z-nile`, false },
			{ `cd {C}/snake && lune run tests/run`, "/tmp", true },
			{ 'cd "$X" && lune run tests/run', `{C}/snake`, false },
		})
	end)

	it("AC2: a background call reads each command from the folder its `cd`s moved to", function()
		-- design review 001 F1: the background walk asks the tooling match again, after the foreground walk
		local cases: { { any } } = {
			{ "cd pickman && lune run tests/run", C, true },
			{ "cd z-nile && lune run tests/run -- a 2>&1 | tail -5", C, true },
			{ "cd snake\nlune run tests/run", C, true },
			{ "cd snake; lune run tests/run", C, true },
			{ "cd .worktree/R1/snake && lune run tests/run", C, true },
			{ "cd z-nile && lune run affected -- x", C, true },
			{ "cd .. && lune run tests/run", `{C}/z-nile`, false },
			{ "cd nowhere && lune run tests/run", C, false },
			{ 'cd "$X" && lune run tests/run', `{C}/snake`, false },
		}
		local bad: { string } = {}
		for _, c in cases do
			local command, cwd, want = c[1] :: string, c[2] :: string, c[3] :: boolean
			local v = boundcmd.check(command, { checkout = C, cwd = cwd, homes = HOMES, background = true })
			if v.ok ~= want then
				table.insert(
					bad,
					`{command} (from {cwd}, background): expected {if want then "ok" else "refused"}`
				)
			end
		end
		t.expect(table.concat(bad, "\n")).toBe("")
	end)
end)
