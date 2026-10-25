--!strict
-- c0330 AC1-AC3: a check.sh finds the repo root and its specs both before and after
-- `tracker.sh done` promotes the acceptance specs. The template does, every done item's check.sh
-- does, and scripts/lib/ac.sh can list an item's checks without running them (AC_LIST=1), which is
-- how this spec proves the other two cheaply.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
-- c0120 override: fixtures live under the spec's home's .cache (the jail refuses the checkout top's)
local here = fixture.physical(".") :: string
local base = `{here}/.cache/c0330-locator`

local function frontmatter(path: string): string
	if not fs.isFile(path) then
		return ""
	end
	return string.match(fs.readFile(path), "^%-%-%-\n(.-)\n%-%-%-") or ""
end

-- AC_LIST honoured: set by the first case. The cases that run every done check.sh refuse to start
-- without it, because a check.sh that ignored AC_LIST would run the whole gate recursively.
local listing = false
local runnerRefuses = false

return t.spec("c0330 check.sh locates the repo after promotion", function(it)
	it("AC_LIST=1 lists a check without running it, and says so", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(base)
		local marker = `{base}/ran`
		-- the scripts run in a fixture repository of their own (testing skill, Fixtures)
		local fx = `{base}/ac`
		assert(process.exec("git", { "init", "-q", fx }).ok, "git init")
		local script = 'source "$1"; check "AC1: touches a file" touch "$2"; finish'
		local ac = `{root}/scripts/lib/ac.sh`
		local listed = fixture.exec(
			fx,
			"bash",
			{ "-c", script, "_", ac, marker },
			{ env = { AC_LIST = "1" } }
		)
		t.expect(listed.ok).toBe(true)
		t.expect(string.find(listed.stdout, "AC1: touches a file", 1, true) ~= nil).toBe(true)
		-- listing is not passing: the summary must not claim that criteria passed
		t.expect(string.find(listed.stdout, "1 criteria listed", 1, true) ~= nil).toBe(true)
		t.expect((string.find(listed.stdout, "criteria passed", 1, true))).toBe(nil)
		t.expect(fs.isFile(marker)).toBe(false)
		local ran = fixture.exec(fx, "bash", { "-c", script, "_", ac, marker })
		t.expect(ran.ok).toBe(true)
		t.expect(string.find(ran.stdout, "1/1 criteria passed", 1, true) ~= nil).toBe(true)
		t.expect(fs.isFile(marker)).toBe(true) -- without AC_LIST the check runs as before
		fs.removeFile(marker)
		-- an empty check.sh still never passes, listed or not
		local empty = fixture.exec(
			fx,
			"bash",
			{ "-c", 'source "$1"; finish', "_", ac },
			{ env = { AC_LIST = "1" } }
		)
		t.expect(empty.ok).toBe(false)
		listing = true
	end)

	it("the spec runner refuses to run specs when AC_LIST is set", function()
		-- c0120 override: the runner runs from z-nile's home, not the repository root
		local r = process.exec("lune", { "run", "tests/run", "--", "tests/meta/architecture.spec.luau" }, {
			cwd = here,
			env = { AC_LIST = "1" },
		})
		t.expect(r.ok).toBe(false)
		t.expect(string.find(r.stdout .. r.stderr, "AC_LIST", 1, true) ~= nil).toBe(true)
		t.expect((string.find(r.stdout, "passed", 1, true))).toBe(nil)
		runnerRefuses = true
	end)

	it("a check.sh that runs a spec at top level only lists in list mode", function()
		-- the shared-fixture pattern runs its spec outside `check`; in list mode that must be inert
		local dir = `{base}/top`
		fs.writeDir(dir)
		local marker = `{dir}/spec-ran`
		local call = "req" .. "uire" -- keeps literal require text out of this file (graph scanner)
		fs.writeFile(
			`{dir}/marker.spec.luau`,
			"--!strict\nlocal fs = "
				.. call
				.. '("@lune/fs")\nlocal t = '
				.. call
				.. '("@tests/lib/t")\n'
				.. `fs.writeFile("{marker}", "")\n`
				.. 'return t.spec("marker", function(it)\n\tit("holds", function()\n\t\tt.expect(1).toBe(1)\n\tend)\nend)\n'
		)
		fs.writeFile(
			`{dir}/check.sh`,
			table.concat({
				"#!/usr/bin/env bash",
				`source "{root}/scripts/lib/ac.sh"`,
				-- c0120 override: the runner runs from z-nile's home; ac.sh leaves a check.sh under no project root at the repository's
				`spec_out=$(cd "$ZN_ROOT/z-nile" && lune run tests/run -- "{dir}/marker.spec.luau" 2>&1)`,
				'check "AC1: fixture" true',
				"finish",
				"",
			}, "\n")
		)
		local listed = process.exec("bash", { `{dir}/check.sh` }, { cwd = base, env = { AC_LIST = "1" } })
		t.expect(listed.ok).toBe(true)
		t.expect(fs.isFile(marker)).toBe(false)
		local ran = process.exec("bash", { `{dir}/check.sh` }, { cwd = base })
		t.expect(ran.ok).toBe(true)
		t.expect(fs.isFile(marker)).toBe(true) -- without AC_LIST the spec runs
	end)

	it("tracker.sh check and done refuse to run with AC_LIST set", function()
		-- Without the guards, `tracker.sh check` of an item whose check.sh runs a spec at the top level
		-- would run that spec, which would run this one again: refuse to start unless the layers below
		-- (ac.sh list mode, the spec runner's refusal) are proven, and use an item with no such script.
		if not (listing and runnerRefuses) then
			error("AC_LIST list mode is not safe (ac.sh or tests/run): not running tracker.sh check under it")
		end
		-- In a fixture holding the tracker, never the real repository: `done` pushes and resets when it gets
		-- past its refusals (testing skill, "Specs never touch the real repository").
		local repo = `{base}/tracker`
		if fs.isDir(repo) then
			fs.removeDir(repo)
		end
		fs.writeDir(repo)
		local listed = process.exec("git", {
			"ls-files",
			"-co",
			"--exclude-standard",
			"zn",
			"scripts",
			"z-nile",
			":(exclude)z-nile/.tracker",
			":(exclude)z-nile/next",
			":(exclude)z-nile/compaction.txt",
			"rokit.toml",
		}, { cwd = root })
		for path in string.gmatch(listed.stdout, "[^\n]+") do
			if fs.isFile(`{root}/{path}`) then
				local parent = string.match(path, "^(.*)/[^/]+$")
				if parent then
					fs.writeDir(`{repo}/{parent}`)
				end
				fs.writeFile(`{repo}/{path}`, fs.readFile(`{root}/{path}`))
			end
		end
		t.expect(process.exec("git", { "init", "-q", repo }).ok).toBe(true)
		t.expect(
			fixture.exec(
				repo,
				"bash",
				{ "scripts/tracker.sh", "new", "issue", "c", "probe", "--project", "pickman" }
			).ok
		).toBe(true)
		local env = { AC_LIST = "1" }
		local checked = fixture.exec(repo, "bash", { "scripts/tracker.sh", "check", "c0010" }, { env = env })
		t.expect(checked.ok).toBe(false)
		t.expect(string.find(checked.stderr, "AC_LIST", 1, true) ~= nil).toBe(true)
		t.expect((string.find(checked.stdout, "criteria", 1, true))).toBe(nil)
		-- `done` refuses before it looks at anything else (R9999 does not exist)
		local finished = fixture.exec(repo, "bash", { "scripts/tracker.sh", "done", "R9999" }, { env = env })
		t.expect(finished.ok).toBe(false)
		t.expect(string.find(finished.stderr, "AC_LIST", 1, true) ~= nil).toBe(true)
	end)

	it("the issue template's check.sh works before and after the acceptance specs are promoted", function()
		local repo = `{base}/repo`
		fs.writeDir(`{repo}/scripts/lib`)
		fs.writeFile(`{repo}/scripts/lib/ac.sh`, fs.readFile(`{root}/scripts/lib/ac.sh`))
		-- c0120 override: pickman's files live in pickman/ (its home)
		-- c0114 override: scripts/lib/ac.sh forwards to z-nile/lib/, which brings the guards it needs (c0120: pickman's root is pickman/.tracker)
		fs.writeDir(`{repo}/z-nile`)
		process.exec("cp", { "-R", `{root}/z-nile/lib`, `{repo}/z-nile/lib` })
		t.expect(process.exec("git", { "init", "-q", repo }).ok).toBe(true)
		local template = fs.readFile(`{root}/z-nile/templates/issue/check.sh`)
		local withCheck, n = string.gsub(
			string.gsub(template, "{{ID}}", "x0001"),
			"\nfinish\n",
			'\ncheck "AC1: finds its spec" test -f "$A/marker.txt"\nfinish\n'
		)
		t.expect(n).toBe(1)
		-- before `done`: the specs sit in acceptance/ next to check.sh
		fs.writeDir(`{repo}/tracker/issues/x0001/acceptance`)
		fs.writeFile(`{repo}/tracker/issues/x0001/check.sh`, withCheck)
		fs.writeFile(`{repo}/tracker/issues/x0001/acceptance/marker.txt`, "")
		local before = process.exec("bash", { `{repo}/tracker/issues/x0001/check.sh` }, { cwd = base })
		if not before.ok then
			error(before.stderr .. before.stdout)
		end
		t.expect(string.find(before.stdout, "PASS  AC1: finds its spec", 1, true) ~= nil).toBe(true)
		-- after `done`: the item moved to done/ and its specs to tests/acceptance/<id>/
		fs.writeDir(`{repo}/tracker/issues/done/x0001`)
		fs.writeFile(`{repo}/tracker/issues/done/x0001/check.sh`, withCheck)
		fs.writeDir(`{repo}/tests/acceptance/x0001`)
		fs.writeFile(`{repo}/tests/acceptance/x0001/marker.txt`, "")
		fs.removeDir(`{repo}/tracker/issues/x0001`)
		local after = process.exec("bash", { `{repo}/tracker/issues/done/x0001/check.sh` }, { cwd = base })
		if not after.ok then
			error(after.stderr .. after.stdout)
		end
		t.expect(string.find(after.stdout, "PASS  AC1: finds its spec", 1, true) ~= nil).toBe(true)
	end)

	it("every finished item's check.sh finds the repo from any directory", function()
		if not (listing and runnerRefuses) then
			error("AC_LIST list mode is not safe (ac.sh or tests/run): not running every done check.sh")
		end
		local checked = 0
		-- c0120 override: pickman's files live in pickman/ (its home)
		-- c0114 override: finished items live under every project root (c0120: pickman's root is pickman/.tracker)
		for _, kind in
			-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
			{
				"pickman/.tracker/issues",
				"pickman/.tracker/rafts",
				"z-nile/.tracker/issues",
				"z-nile/.tracker/rafts",
			}
		do
			local dir = `{root}/{kind}/done`
			for _, name in fs.readDir(dir) do
				local item = `{dir}/{name}`
				if
					fs.isDir(item)
					and fs.isFile(`{item}/check.sh`)
					and not string.find(frontmatter(`{item}/{name}.md`), "\nclosed:", 1, true)
				then
					local ran, r = pcall(
						process.exec,
						"bash",
						{ `{item}/check.sh` },
						{ cwd = base, env = { AC_LIST = "1" } }
					)
					if not ran then
						error(`{name}: could not run check.sh: {r}`)
					end
					if not r.ok or not string.find(r.stdout, "criteria listed", 1, true) then
						error(`{name}: check.sh cannot locate the repo or its specs:\n{r.stderr}{r.stdout}`)
					end
					checked += 1
				end
			end
		end
		t.expect(checked >= 20).toBe(true)
	end)

	it("no live check.sh or the template uses the locator that needs acceptance/ to exist", function()
		local old = '"$A/.."'
		-- c0120 override: pickman's files live in pickman/ (its home)
		-- c0114 override: the template moved to z-nile/templates, and items live under every project root (c0120: pickman's root is pickman/.tracker)
		local paths: { string } = { `{root}/z-nile/templates/issue/check.sh` }
		local dirs: { string } = {}
		-- c0120 override: the tooling's files live in z-nile/ (its home)
		for _, top in { "pickman/.tracker", "z-nile/.tracker" } do
			for _, d in { "issues/active", "issues/done", "rafts/active", "rafts/done" } do
				table.insert(dirs, `{top}/{d}`)
			end
		end
		for _, dir in dirs do
			if not fs.isDir(`{root}/{dir}`) then
				continue
			end
			for _, name in fs.readDir(`{root}/{dir}`) do
				local file = `{root}/{dir}/{name}/check.sh`
				if fs.isDir(`{root}/{dir}/{name}`) and fs.isFile(file) then
					table.insert(paths, file)
				end
			end
		end
		for _, file in paths do
			if string.find(fs.readFile(file), old, 1, true) then
				local doc = string.match(file, "^(.*)/check%.sh$") :: string
				local name = string.match(doc, "([^/]+)$") :: string
				local closed = fs.isFile(`{doc}/{name}.md`)
					and string.find(frontmatter(`{doc}/{name}.md`), "\nclosed:", 1, true)
				if not closed then
					error(
						`{file} finds the repo through "$A/..", which fails once acceptance/ is promoted away`
					)
				end
			end
		end
	end)

	it("cleans up", function()
		fs.removeDir(base)
	end)
end)
