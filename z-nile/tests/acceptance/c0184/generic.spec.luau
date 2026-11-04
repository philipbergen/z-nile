--!strict
-- c0184 AC4: the three places that named pickman's folders by hand take every home from the registry.
-- The stop hook gates a change under any registered home (and every change when the registry does not parse); the
-- reviewed .cache list covers every home's scripts/; the repository-fence scan reads every home's specs, scripts and
-- check.sh. Promoted: the cases use a third home, `snake`, that a fixture registry names, never today's seven.
-- Fixtures under .cache/c0184-generic (this home's .cache); the real tree is read from its top.
local cachepaths = require("@tests/lib/cachepaths")
local fixture = require("@tests/lib/fixture")
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

-- a fixture repository holding the registry readers, a stub gate at scripts/check.sh that records its call, and the
-- registry text `toml`; stop(dir) runs the real hook there and says whether the gate ran
local function tree(name: string, toml: string?, roots: string?): string
	local dir = fresh(name)
	t.expect(process.exec("git", { "init", "-q", "-b", "main", dir }).ok).toBe(true)
	fixture.git(dir, { "config", "user.name", "c0184-generic" })
	fixture.git(dir, { "config", "user.email", "c0184-generic@example.invalid" })
	write(`{dir}/scripts/check.sh`, '#!/usr/bin/env bash\necho "$@" >> "$(dirname "$0")/../gate.log"\n')
	process.exec("chmod", { "+x", `{dir}/scripts/check.sh` })
	if roots then
		write(`{dir}/z-nile/roots.luau`, roots) -- a registry reader of another age
	elseif toml then
		copy(dir, { "z-nile/roots.luau", "z-nile/engine/projects.luau" })
		write(`{dir}/z-nile/projects.toml`, toml)
	end
	write(`{dir}/readme`, "x\n")
	fixture.git(dir, { "add", "-A" })
	fixture.git(dir, { "commit", "-q", "-m", "base" })
	return dir
end
local function gated(dir: string): boolean
	fixture.exec(dir, "bash", { `{TOP}/scripts/hooks/stop.sh` }, { stdin = '{"cwd": "' .. dir .. '"}' })
	local ran = fs.isFile(`{dir}/gate.log`)
	if ran then
		fs.removeFile(`{dir}/gate.log`)
	end
	return ran
end

return t.spec("c0184 the hand-named pickman folders come from the registry", function(it)
	it("AC4: the stop hook gates a change under a third registered home, not its root's documents", function()
		local dir = tree("hook", THREE)
		write(`{dir}/snake/.tracker/issues/f0001/f0001.md`, "doc\n")
		t.expect(gated(dir)).toBe(false) -- the third project's root alone: documents select no spec
		write(`{dir}/snake/src/shared/X.luau`, "--!strict\nreturn 1\n")
		t.expect(gated(dir)).toBe(true) -- its code: the gate runs
		fs.removeDir(`{dir}/snake/src`)
		write(`{dir}/pickman/src/shared/X.luau`, "--!strict\nreturn 1\n")
		t.expect(gated(dir)).toBe(true) -- pickman's code still gates
		fs.removeDir(`{dir}/pickman/src`)
		write(`{dir}/elsewhere/x.luau`, "--!strict\nreturn 1\n")
		t.expect(gated(dir)).toBe(false) -- a folder the registry does not name is no project's home
		fs.removeDir(dir)
	end)

	it(
		"AC4: a registry that does not parse gates every change, and a tree before c0114 keeps its folders",
		function()
			local broken = tree("hook-broken", "[[project]\nname = \n")
			write(`{broken}/elsewhere/x.luau`, "--!strict\nreturn 1\n")
			t.expect(gated(broken)).toBe(true) -- fail closed: the gate runs and reports the registry
			fs.removeDir(broken)
			local old = tree("hook-old", nil) -- no z-nile/roots.luau
			write(`{old}/pickman/src/shared/X.luau`, "--!strict\nreturn 1\n")
			t.expect(gated(old)).toBe(true)
			fs.removeDir(`{old}/pickman/src`)
			write(`{old}/snake/src/x.luau`, "--!strict\nreturn 1\n")
			t.expect(gated(old)).toBe(false) -- it has no registry to name snake
			fs.removeDir(old)
		end
	)

	it("AC4: a registry reader that prints roots, not projects, gates every change", function()
		-- z-nile/roots.luau of c0114's age ignores --projects and prints one root per line (here: tracker)
		local dir = tree("hook-oldreader", THREE, '--!strict\nprint("tracker")\n')
		write(`{dir}/elsewhere/x.luau`, "--!strict\nreturn 1\n")
		t.expect(gated(dir)).toBe(true) -- it cannot name the homes, so no folder is exempt
		fs.removeDir(dir)
	end)

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
