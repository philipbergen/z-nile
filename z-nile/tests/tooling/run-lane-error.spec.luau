--!strict
-- c0470 review F1: a worker that cannot be spawned is one failure per file, not a hung runner.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local function trim(s: string): string
	return (string.gsub(s, "%s+$", ""))
end

return t.spec("tests/run when workers cannot start", function(it)
	it("reports each file as a failure instead of hanging", function()
		local root = trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)
		local dir = `{root}/.cache/run-lane-error`
		if fs.isDir(dir) then
			fs.removeDir(dir)
		end
		fs.writeDir(dir)
		local body = 'return { name = "x", cases = { { name = "c", fn = function() end } } }'
		fs.writeFile(`{dir}/a.spec.luau`, body)
		fs.writeFile(`{dir}/b.spec.luau`, body)
		local home = process.env.HOME or ""
		-- the runner itself is started by absolute path; its workers need `lune` on PATH, which is empty
		local r = process.exec("perl", {
			"-e",
			"alarm 30; exec @ARGV",
			`{home}/.rokit/bin/lune`,
			"run",
			"tests/run",
			"--",
			"--jobs",
			"2",
			".cache/run-lane-error/a.spec.luau",
			".cache/run-lane-error/b.spec.luau",
		}, { cwd = root, env = { PATH = "/usr/bin:/bin", PICKMAN_JOBS = "" } })
		fs.removeDir(dir)
		t.expect(r.code).toBe(1)
		t.expect(string.find(r.stdout, "0 passed, 2 failed, 2 spec files", 1, true) ~= nil).toBe(true)
	end)
end)
