--!strict
-- c0120 code review 007 F5: audit reports an item whose acceptance/ is still in its folder beside the copy `done`
-- promoted. Fixture under this home's .cache/c0120-audit-left.
local engine = require("@tests/lib/engine")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local here = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local base = `{here}/.cache/c0120-audit-left`

local function write(rel: string, text: string)
	fs.writeDir(string.match(`{base}/{rel}`, "^(.*)/[^/]+$") :: string)
	fs.writeFile(`{base}/{rel}`, text)
end

local function audit(): string
	local r = process.exec("bash", { "zn", "audit" }, { cwd = base, env = { PICKMAN_PUBLISH = "0" } })
	return r.stdout .. r.stderr
end

return t.spec("c0120 audit reports specs left beside their promoted copy", function(it)
	it(
		"a done item's acceptance/ in its done/ folder is an error, beside its promoted specs or alone",
		function()
			if fs.isDir(base) then
				fs.removeDir(base)
			end
			fs.writeDir(base)
			engine.copy(root, base)
			engine.roots(base)
			local doc = "---\nid: f0065\ntype: feature\ntitle: F\nslug: f\nstatus: done\n---\n"
			write("pickman/.tracker/issues/done/f0065/f0065.md", doc)
			write("pickman/.tracker/issues/done/f0065/check.sh", "check AC1 true\n")
			write("pickman/tests/acceptance/f0065/a.spec.luau", "-- a\n")
			t.expect((string.find(audit(), "spec-not-promoted", 1, true))).toBe(nil)
			write("pickman/.tracker/issues/done/f0065/acceptance/a.spec.luau", "-- a\n")
			local out = audit()
			t.expect(string.find(out, "spec-not-promoted", 1, true) ~= nil).toBe(true)
			t.expect(string.find(out, "are both in", 1, true) ~= nil).toBe(true)
			-- moved back: in done/ only (code review 008 F2)
			fs.removeDir(`{base}/pickman/tests/acceptance/f0065`)
			out = audit()
			t.expect(string.find(out, "its specs belong in pickman/tests/acceptance/f0065", 1, true) ~= nil)
				.toBe(true)
			fs.removeDir(base)
		end
	)
end)
