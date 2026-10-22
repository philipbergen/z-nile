--!strict
-- c0120 code review 004 F3: the gate gives every project home's .cache the fence's refusals before it writes there
-- (its builds write each home's check*.rbxl there), and before --plan, which only reads. A home .cache an unjailed spec
-- swapped for a symlink refuses the gate. Runs --plan only, in a copy under this home's .cache.
local engine = require("@tests/lib/engine")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local here = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local base = `{here}/.cache/c0120-gate-home-cache`

local function plan(dir: string, extra: { string }?): (boolean, string)
	local argv = { "z-nile/check.sh", "--plan" }
	for _, a in extra or {} do
		table.insert(argv, a)
	end
	local r = process.exec("bash", argv, { cwd = dir })
	return r.ok, r.stdout .. r.stderr
end

return t.spec("c0120 the gate refuses a bad home .cache", function(it)
	it(
		"a symlinked .cache in any home, or at the root, refuses the gate, even its plan; a plain one plans",
		function()
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
			t.expect((string.find(out, "format:", 1, true))).toBe(nil)
			fs.removeFile(`{dir}/pickman/.cache`)
			-- every home, not the first (code review 005 F3): z-nile's, even when only pickman is picked
			t.expect(process.exec("ln", { "-s", away, `{dir}/z-nile/.cache` }).ok).toBe(true)
			ok, out = plan(dir, { "--project", "pickman" })
			fs.removeFile(`{dir}/z-nile/.cache`)
			t.expect(ok).toBe(false)
			t.expect(string.find(out, "z-nile/.cache is not a plain folder", 1, true) ~= nil).toBe(true)
			-- and the root's
			t.expect(process.exec("ln", { "-s", away, `{dir}/.cache` }).ok).toBe(true)
			ok, out = plan(dir)
			fs.removeFile(`{dir}/.cache`)
			t.expect(ok).toBe(false)
			t.expect(string.find(out, "tree/.cache is not a plain folder", 1, true) ~= nil).toBe(true)
			fs.removeDir(base)
		end
	)
end)
