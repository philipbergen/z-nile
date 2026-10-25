--!strict
-- c0114 AC7: every lookup of the repository guards fails closed now that they live in z-nile/lib/: a check.sh whose
-- ac.sh can't find fence.sh refuses to run, the scripts/lib/ac.sh forwarder refuses when its target is gone, the
-- tracker publishes only on fence.sh's one explicit "unguarded" answer (a missing or broken fence.sh, a missing
-- pickman_guarded or any other answer publishes nothing), the fence refuses a checkout with no ref guard hooks unless
-- all of the runner's jail markers say the kernel protects it, and the spec runner refuses to start without fence.sh. Fixtures under
-- .cache/c0114-guards (repositories of their own) and .cache/c0114-guards-tf (tests/lib/trackerfix).
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local root = fixture.physical(".") :: string
local base = `{root}/.cache/c0114-guards`
-- c0120 override: the spec runs from z-nile/ (its home, whose .cache holds the fixtures), so the files it copies and the
-- checkout it asks about are the checkout's top
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
-- a repository of its own at base/<name> holding `files` copied from the checkout (relative paths)
local function repo(name: string, files: { string }): string
	local dir = `{base}/{name}`
	if fs.isDir(dir) then
		fs.removeDir(dir)
	end
	fs.writeDir(dir)
	t.expect(process.exec("git", { "init", "-q", "-b", "main", dir }).ok).toBe(true)
	for _, rel in files do
		local parent = string.match(rel, "^(.*)/[^/]+$")
		if parent then
			fs.writeDir(`{dir}/{parent}`)
		end
		t.expect(process.exec("cp", { "-R", `{TOP}/{rel}`, `{dir}/{rel}` }).ok).toBe(true) -- c0120 override: from the top
	end
	return dir
end
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/%s"\n'
	.. 'check "AC1: touches a marker" touch "$(pwd -P)/.cache/ran"\nfinish\n'

return t.spec("c0114 the guards fail closed", function(it)
	it("a check.sh whose ac.sh finds no fence.sh refuses and runs nothing", function()
		local dir = repo("no-fence", { "z-nile/lib/ac.sh" })
		fs.writeFile(`{dir}/check.sh`, string.format(CHECK, "z-nile/lib/ac.sh"))
		local r = fixture.exec(dir, "bash", { "check.sh" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "z-nile/lib/fence.sh is missing")).toBe(true)
		t.expect(fs.isFile(`{dir}/.cache/ran`)).toBe(false)
		-- with the guards beside it, the same check.sh runs
		local ok = repo("with-fence", { "z-nile/lib" })
		fs.writeFile(`{ok}/check.sh`, string.format(CHECK, "z-nile/lib/ac.sh"))
		local good = fixture.exec(ok, "bash", { "check.sh" })
		t.expect(good.ok).toBe(true)
		t.expect(has(good.stdout, "1/1 criteria passed")).toBe(true)
	end)

	it("the scripts/lib/ac.sh forwarder refuses when z-nile/lib/ac.sh is gone", function()
		local dir = repo("no-target", { "scripts/lib/ac.sh" })
		fs.writeFile(`{dir}/check.sh`, string.format(CHECK, "scripts/lib/ac.sh"))
		local r = fixture.exec(dir, "bash", { "check.sh" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "z-nile/lib/ac.sh is missing")).toBe(true)
		t.expect(fs.isFile(`{dir}/.cache/ran`)).toBe(false)
	end)

	it(
		"the tracker publishes only when fence.sh answers unguarded; any other outcome publishes nothing",
		function()
			local f = trackerfix.new("c0114-guards-tf", {})
			local wt = trackerfix.trOk(f, f.main, { "worktree", "probe" })
			local function tip(): string
				return fixture.git(f.origin, { "rev-parse", "main" })
			end
			-- the answer itself: a fixture is not one this run protects, this checkout is
			local ask = 'source z-nile/lib/fence.sh && pickman_guarded "$PWD"'
			t.expect(fixture.exec(wt, "bash", { "-c", ask }).stdout).toBe("unguarded\n")
			-- c0120 override: this checkout is asked about from its top, where z-nile/lib/fence.sh is
			t.expect(process.exec("bash", { "-c", ask }, { cwd = TOP }).stdout).toBe("guarded\n")
			-- the explicit "unguarded" publishes
			local before = tip()
			t.expect(trackerfix.tr(f, wt, { "new", "issue", "c", "published", "--project", "pickman" }).ok)
				.toBe(true)
			local published = tip()
			t.expect(published ~= before).toBe(true)
			local real = fs.readFile(`{wt}/z-nile/lib/fence.sh`)
			local broken: { [string]: string } = {
				missing = "", -- removed, not written
				["a syntax error"] = "pickman_fence() { (\n",
				["no pickman_guarded"] = "pickman_fence() { :; }\n",
				["another answer"] = "pickman_guarded() { echo maybe; }\n",
				["a failing lookup"] = "pickman_guarded() { return 2; }\n",
			}
			t.expect(broken.missing).toBe("")
			for what, text in broken do
				if text ~= "" then
					fs.writeFile(`{wt}/z-nile/lib/fence.sh`, text)
				elseif fs.isFile(`{wt}/z-nile/lib/fence.sh`) then
					fs.removeFile(`{wt}/z-nile/lib/fence.sh`)
				end
				local r = trackerfix.tr(f, wt, { "new", "issue", "c", "local-only", "--project", "pickman" })
				if not has(r.stderr, "not publishing") then
					error(`{what}: no "not publishing" in: {r.stderr}`)
				end
				if what == "missing" then
					t.expect(has(r.stderr, "z-nile/lib/fence.sh is missing")).toBe(true)
				end
				t.expect(tip()).toBe(published)
			end
			fs.writeFile(`{wt}/z-nile/lib/fence.sh`, real)
		end
	)

	it("the fence refuses a checkout with no ref guard hooks, unless the jail already protects it", function()
		local bare = repo("no-hooks", { "z-nile/lib/fence.sh" })
		local script = 'source z-nile/lib/fence.sh && pickman_fence "$(pwd -P)"'
		local outside = fixture.exec(bare, "bash", { "-c", script }, {
			env = { PICKMAN_FENCE_HOOKS = "", PICKMAN_TEST_JAIL = "" },
		})
		t.expect(outside.ok).toBe(false)
		t.expect(has(outside.stderr, "no ref guard")).toBe(true)
		local jailed = fixture.exec(bare, "bash", { "-c", script }, {
			env = { PICKMAN_FENCE_HOOKS = "", PICKMAN_TEST_JAIL = "sandbox-exec" },
		})
		t.expect(jailed.ok).toBe(true)
		-- the jail marker alone is not enough: the checkout must lie under the run's own .cache (the runner's marker)
		local stray = fixture.exec(bare, "bash", { "-c", script }, {
			env = {
				PICKMAN_FENCE_HOOKS = "",
				PICKMAN_TEST_JAIL = "sandbox-exec",
				PICKMAN_TEST_FENCE = "/nonexistent",
			},
		})
		t.expect(stray.ok).toBe(false)
		t.expect(has(stray.stderr, "no ref guard")).toBe(true)
		local hooked = repo("hooks", { "z-nile/lib/fence.sh", "z-nile/lib/git-hooks" })
		local fine = fixture.exec(hooked, "bash", { "-c", script }, {
			env = { PICKMAN_FENCE_HOOKS = "", PICKMAN_TEST_JAIL = "" },
		})
		t.expect(fine.ok).toBe(true)
	end)

	it("the spec runner refuses to start without z-nile/lib/fence.sh", function()
		-- c0120 override: the runner and its harness are z-nile's (z-nile/tests, with z-nile/.luaurc), run from the copy's
		-- z-nile home, whose .cache the probe writes to
		local dir = repo(
			"runner",
			{ "z-nile/tests/run.luau", "z-nile/tests/lib", "z-nile/.luaurc", ".luaurc", "rokit.toml" }
		)
		local home = `{dir}/z-nile`
		fs.writeDir(`{home}/tests/probe`)
		local call = "req" .. "uire" -- keeps literal require text out of this file (graph scanner)
		-- c0120 override: the spec runs from z-nile/, its home, after the move
		fs.writeFile(
			`{home}/tests/probe/marker.spec.luau`,
			`--!strict\nlocal fs = {call}("@lune/fs")\nlocal t = {call}("@tests/lib/t")\nfs.writeFile(".cache/spec-ran", "")\n`
				.. 'return t.spec("marker", function(it)\n\tit("runs", function() end)\nend)\n'
		)
		-- c0120 override: the spec runs from z-nile/, its home, after the move
		local r = process.exec("lune", { "run", "tests/run", "--", "tests/probe/marker.spec.luau" }, {
			cwd = home,
			env = { PICKMAN_TEST_FENCE = "" }, -- a top-level run of the copy: only the marker is cleared
		})
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stdout .. r.stderr, "z-nile/lib/fence.sh")).toBe(true)
		-- c0120 override: the spec runs from z-nile/, its home, after the move
		t.expect(fs.isFile(`{home}/.cache/spec-ran`)).toBe(false)
		fs.removeDir(base)
	end)
end)
