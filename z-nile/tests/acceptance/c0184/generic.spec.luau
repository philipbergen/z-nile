--!strict
-- c0184 AC4: the places that named pickman's folders by hand take every home from the registry.
-- The reviewed .cache list covers every home's scripts/; the repository-fence scan reads every home's specs, scripts
-- and check.sh. Promoted: the cases use a third home, `snake`, that a fixture registry names, never today's seven.
-- Fixtures under .cache/c0184-generic (this home's .cache); the real tree is read from its top.
local cachepaths = require("@tests/lib/cachepaths")
local fs = require("@lune/fs")
local process = require("@lune/process")
local projects = require("@znile/engine/projects")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local HERE = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local BASE = `{HERE}/.cache/c0184-generic`

local THREE = 'retired = ["tracker"]\n\n[[project]]\nname = "pickman"\nroot = "pickman/.tracker"\n\n'
	.. '[[project]]\nname = "z-nile"\nroot = "z-nile/.tracker"\n\n[[project]]\nname = "snake"\nroot = "snake/.tracker"\n'

local function write(path: string, text: string)
	fs.writeDir(string.match(path, "^(.*)/[^/]+$") :: string)
	fs.writeFile(path, text)
end
local function copy(dest: string, rels: { string })
	for _, rel in rels do
		fs.writeDir(string.match(`{dest}/{rel}`, "^(.*)/[^/]+$") :: string)
		t.expect(process.exec("cp", { "-R", `{TOP}/{rel}`, `{dest}/{rel}` }).ok).toBe(true)
	end
end
local function fresh(name: string): string
	local dir = `{BASE}/{name}`
	if fs.isDir(dir) then
		fs.removeDir(dir)
	end
	fs.writeDir(dir)
	return dir
end

return t.spec("c0184 the hand-named pickman folders come from the registry", function(it)
	it(
		"AC4: the reviewed .cache list covers scripts/, z-nile/ and every other registered home's scripts/",
		function()
			local reg = projects.parse(THREE) :: projects.Registry
			t.expect(cachepaths.rootsOf(reg))
				.toEqual({ "scripts", "z-nile", "pickman/scripts", "snake/scripts" })
			local live = projects.load(TOP)
			local want = { "scripts", "z-nile" }
			for _, p in live.projects do
				if p.name ~= "z-nile" then
					table.insert(want, `{p.home}/scripts`)
				end
			end
			t.expect(cachepaths.ROOTS).toEqual(want)
			t.expect(table.find(cachepaths.ROOTS, "pickman/scripts") ~= nil).toBe(true)
		end
	)

	it(
		"AC4: the repository-fence scan reads a third registered home's specs, scripts and check.sh",
		function()
			local scan = fresh("scan")
			-- the runner, its harness, the guards, and the registry readers with a registry naming snake
			copy(scan, {
				"z-nile/tests/run.luau",
				"z-nile/tests/lib",
				"z-nile/tests/tooling/repo-fence.spec.luau",
				"z-nile/.luaurc",
				"z-nile/lib",
				"z-nile/engine/projects.luau",
				"z-nile/roots.luau",
				".luaurc",
				"rokit.toml",
				".gitignore",
			})
			write(`{scan}/z-nile/projects.toml`, THREE)
			t.expect(process.exec("git", { "init", "-q", "-b", "main", scan }).ok).toBe(true)
			local hooks = "hooks" .. "Path" -- spelled in two parts: once promoted, the scan reads this spec too
			write(`{scan}/snake/tests/unit/planted.spec.luau`, `-- git -c core.{hooks}=/dev/null push\n`)
			write(`{scan}/snake/scripts/planted.sh`, `git -c core.{hooks}=/dev/null push\n`)
			write(`{scan}/snake/check.sh`, "git push --no-" .. "verify origin HEAD\n")
			write(`{scan}/pickman/tests/unit/planted.spec.luau`, `-- git -c core.{hooks}=/dev/null push\n`)
			local r = process.exec(
				"lune",
				{ "run", "tests/run", "--", "tests/tooling/repo-fence.spec.luau" },
				{ cwd = `{scan}/z-nile`, env = { PICKMAN_TEST_FENCE = "" } }
			)
			local out = r.stdout .. r.stderr
			t.expect(r.ok).toBe(false)
			t.expect(
				string.find(
					out,
					":: no spec, check.sh or script switches a guard off or points git elsewhere",
					1,
					true
				) ~= nil
			).toBe(true)
			t.expect(string.find(out, `snake/tests/unit/planted.spec.luau names {hooks}`, 1, true) ~= nil)
				.toBe(true)
			t.expect(string.find(out, `snake/scripts/planted.sh names {hooks}`, 1, true) ~= nil).toBe(true)
			t.expect(string.find(out, "snake/check.sh names --no-" .. "verify", 1, true) ~= nil).toBe(true)
			t.expect(string.find(out, `pickman/tests/unit/planted.spec.luau names {hooks}`, 1, true) ~= nil)
				.toBe(true)
			fs.removeDir(scan)
		end
	)
end)
