--!strict
-- c0550 review-001 F1: when the outermost runner can't re-run itself under the browser guard (no `lune` on PATH),
-- it says so on stderr, exits 1, and removes its guard directory.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local DIR = ".cache/run-guard-relaunch"

return t.spec("tests/run guard relaunch", function(it)
	it("without lune on PATH, the guard fails clearly and leaves no guard directory", function()
		if fs.isDir(DIR) then
			fs.removeDir(DIR)
		end
		fs.writeDir(`{DIR}/tmp`)
		local tmp = `{process.cwd}{DIR}/tmp`
		local lune = string.gsub(process.exec("sh", { "-c", "command -v lune" }).stdout, "%s+$", "")
		local r = process.exec(lune, { "run", "tests/run", "--", "tests/tooling/affected.spec.luau" }, {
			env = { PATH = "/usr/bin:/bin", PICKMAN_OPEN_GUARD = "", TMPDIR = tmp },
		})
		t.expect(r.code).toBe(1)
		t.expect(string.find(r.stderr, "could not re-run itself with the browser guard", 1, true) ~= nil)
			.toBe(true)
		t.expect(#fs.readDir(tmp)).toBe(0)
		fs.removeDir(DIR)
	end)
end)
