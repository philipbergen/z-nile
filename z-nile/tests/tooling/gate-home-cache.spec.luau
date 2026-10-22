--!strict
-- c0120 code review 004 F3: the gate gives every project home's .cache the fence's refusals before it writes there
-- (its builds write <home>/.cache/check*.rbxl), and before --plan, which only reads. A home .cache an unjailed spec
-- swapped for a symlink refuses the gate. Runs --plan only, in a copy under this home's .cache.
local engine = require("@tests/lib/engine")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local here = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local base = `{here}/.cache/c0120-gate-home-cache`

local function plan(dir: string): (boolean, string)
	local r = process.exec("bash", { "z-nile/check.sh", "--plan" }, { cwd = dir })
	return r.ok, r.stdout .. r.stderr
end

return t.spec("c0120 the gate refuses a bad home .cache", function(it)
	it("a symlinked pickman/.cache refuses the gate, even its plan; a plain one plans", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		local dir = `{base}/tree`
		fs.writeDir(dir)
		engine.copy(root, dir)
		fs.writeFile(
			`{dir}/z-nile/projects.toml`,
			'retired = ["tracker"]\n\n[[project]]\nname = "pickman"\nroot = "pickman/.tracker"\n\n'
				.. '[[project]]\nname = "z-nile"\nroot = "z-nile/.tracker"\n'
		)
		for _, rel in { "pickman/src/shared", "pickman/.tracker/issues", "z-nile/.tracker/issues" } do
			fs.writeDir(`{dir}/{rel}`)
		end
		local ok, out = plan(dir)
		if not ok then
			print(out)
		end
		t.expect(ok).toBe(true)
		local away = `{base}/away`
		fs.writeDir(away)
		t.expect(process.exec("ln", { "-s", away, `{dir}/pickman/.cache` }).ok).toBe(true)
		ok, out = plan(dir)
		t.expect(ok).toBe(false)
		t.expect(string.find(out, "pickman/.cache is not a plain folder", 1, true) ~= nil).toBe(true)
		t.expect(string.find(out, "format:", 1, true)).toBe(nil)
		fs.removeDir(base)
	end)
end)
