--!strict
-- c0245 AC5: the seatbelt's tooling match decides by the file a `lune run` target reaches in this checkout (R0075
-- review 002 F3): its path from the top of its tree (the checkout or one of its worktrees) is an entry of TOOLING or a
-- registered home's runner, written relative or absolute; a path that leaves the checkout never is, and no suffix
-- counts. The hook end to end, with the registry of the checkout it is told.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local ROOT = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function hook(command: string, checkout: string, cwd: string?, background: boolean?)
	local payload = serde.encode("json", {
		tool_name = "Bash",
		cwd = cwd or checkout,
		tool_input = { command = command, run_in_background = background == true },
	})
	return process.exec(
		"lune",
		{ "run", `{ROOT}/z-nile/guard-bash` },
		{ cwd = ROOT, env = { ZN_CHECKOUT = checkout }, stdio = { stdin = payload } }
	)
end

return t.spec("c0245 the hook reads paths by file with its registry", function(it)
	it(
		"AC5: the hook reads absolute and `..` paths by the file they reach, with its checkout's registry",
		function()
			t.expect(hook(`lune run {ROOT}/snake/tests/run`, ROOT, "/tmp").code).toBe(0)
			-- a background call that cds into a home (design review 001 F1)
			t.expect(hook("cd pickman && lune run tests/run", ROOT, ROOT, true).code).toBe(0)
			t.expect(hook("cd nowhere && lune run tests/run", ROOT, ROOT, true).code).toBe(2)
			t.expect(hook(`lune run {ROOT}/nowhere/tests/run`, ROOT, "/tmp").code).toBe(2)
			t.expect(hook(`lune run {ROOT}/z-nile/.cache/probe/tests/run.luau`, ROOT).code).toBe(2)
			t.expect(hook("lune run ../snake/tests/run", ROOT, `{ROOT}/pickman`).code).toBe(0)
			t.expect(hook("lune run ../../snake/tests/run", ROOT, `{ROOT}/pickman`).code).toBe(2)
			t.expect(hook("lune run tests/run", ROOT, `{ROOT}/z-nile/.cache`).code).toBe(2)
		end
	)

	it("AC5: an absolute runner path counts only for a home the hook's registry names", function()
		-- a fixture checkout under the home's .cache whose registry names one project, `zz`
		local dir = `{ROOT}/z-nile/.cache/c0245-own-registry`
		local okRun, result = pcall(function(): { number }
			fs.writeDir(`{dir}/z-nile`)
			fs.writeFile(
				`{dir}/z-nile/projects.toml`,
				'retired = []\n\n[[project]]\nname = "zz"\nroot = "zz/.tracker"\n'
			)
			return {
				hook(`lune run {dir}/zz/tests/run`, dir, "/tmp").code,
				hook(`lune run {dir}/snake/tests/run`, dir, "/tmp").code,
				hook(`lune run {dir}/pickman/tests/run`, dir, "/tmp").code,
				hook("lune run ../zz/tests/run", dir, `{dir}/z-nile`).code,
			}
		end)
		pcall(fs.removeDir, dir)
		t.expect(fs.isDir(dir)).toBe(false)
		if not okRun then
			error(result, 0)
		end
		local codes = result :: { number }
		-- zz is registered; snake is not; pickman's runner is TOOLING's own entry
		t.expect(`{codes[1]} {codes[2]} {codes[3]} {codes[4]}`).toBe("0 2 0 0")
	end)
end)
