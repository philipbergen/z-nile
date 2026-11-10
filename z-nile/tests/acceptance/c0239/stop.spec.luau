--!strict
-- c0239 AC6. `z-nile/specs scope` takes no paths: it reads the change set the affected gate itself selects
-- from (the branch against its base, plus uncommitted and untracked files) and prints one project name only when the
-- selector's answer for that whole set is a non-empty selection inside that project, every changed path lies under
-- that project's home or tracker root, and nothing forces a full run; otherwise ALL.
-- Fixtures: c0165's gatefix (a repository under .cache with a tiny pickman home). Everything a case's change set must
-- not see (the stub gate, declared inputs) goes into the fixture's base commit through `setup` (design review 003 F2,
-- zz-test/case-change-set-in-the-base-commit); a case writes only what it changes, by appending to a file that exists
-- (so the file stays valid) or creating a new one.
local fs = require("@lune/fs")
local gatefix = require("@tests/acceptance/c0165/gatefix")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local here = gatefix.trim(process.exec("pwd", { "-P" }).stdout)
local base = `{here}/.cache/c0239-stop`

local function git(dir: string, args: { string })
	local r = process.exec("git", args, { cwd = dir })
	if not r.ok then
		error(`git {table.concat(args, " ")} failed: {r.stderr}`)
	end
end
local function commit(dir: string, message: string)
	git(dir, { "add", "-A" })
	git(dir, { "-c", "user.email=t@example.invalid", "-c", "user.name=t", "commit", "-qm", message })
end

-- the stub gate logs its arguments to gate.log; `more` adds the case's other base files
local function fixture(name: string, more: ((dir: string) -> ())?): string
	return gatefix.make(base, name, {
		setup = function(dir: string)
			gatefix.write(
				`{dir}/scripts/check.sh`,
				'#!/usr/bin/env bash\necho "$*" >> "$(dirname "$0")/../gate.log"\n'
			)
			process.exec("chmod", { "+x", `{dir}/scripts/check.sh` })
			gatefix.write(
				`{dir}/pickman/default.project.json`,
				'{ "name": "pickman", "tree": { "$className": "DataModel" } }\n'
			)
			if more ~= nil then
				more(dir)
			end
		end,
	})
end
-- back to the committed state between cases
local function reset(dir: string)
	git(dir, { "reset", "--hard", "-q" })
	git(dir, { "clean", "-fdq", "-e", ".cache", "-e", "ran.log" })
end
-- a change that keeps the file valid: append to an existing file, or create a new one
local function touch(dir: string, rel: string)
	local path = `{dir}/{rel}`
	if fs.isFile(path) then
		fs.writeFile(
			path,
			fs.readFile(path) .. (if string.match(rel, "%.json$") then "\n" else "\n-- edit\n")
		)
	else
		gatefix.write(path, "-- edit\n")
	end
end

-- touches the files, runs `lune run z-nile/specs -- scope` in the fixture, resets; its success and stdout
local function scope(dir: string, changed: { string }): (boolean, string)
	for _, p in changed do
		touch(dir, p)
	end
	local r = process.exec(
		"lune",
		{ "run", "z-nile/specs", "--", "scope" },
		{ cwd = dir, env = gatefix.env(dir) }
	)
	reset(dir)
	return r.ok, gatefix.trim(r.stdout)
end

return t.spec("c0239 the scope command", function(it)
	it("AC6: with nothing changed, scope answers ALL (the fixture's change set starts empty)", function()
		local dir = fixture("empty")
		local ok, out = scope(dir, {})
		t.expect(ok).toBe(true)
		t.expect(out).toBe("ALL")
	end)

	it("AC6: scope names a project for a pure project change and ALL for everything else", function()
		local dir = fixture("scope")
		local function expectScope(changed: { string }, want: string)
			local ok, out = scope(dir, changed)
			t.expect(ok).toBe(true)
			t.expect(out).toBe(want)
		end
		expectScope({ "pickman/src/A.luau" }, "pickman")
		expectScope({ "pickman/src/A.luau", "pickman/tests/unit/a.spec.luau" }, "pickman")
		expectScope({ "z-nile/lib/changed.luau" }, "ALL") -- a forcing path
		expectScope({ "scripts/other.sh" }, "ALL") -- outside every home: the change set the hook never passed on
		expectScope({ "zn" }, "ALL")
		expectScope({ "pickman/default.project.json" }, "ALL")
		expectScope({ "pickman/src/A.luau", "z-nile/lib/changed.luau" }, "ALL") -- one path forces, the rest do not narrow
		expectScope({ "pickman/src/A.luau", "scripts/other.sh" }, "ALL")
		expectScope({ "pickman/src/NoSpecReadsThis.luau" }, "ALL") -- an empty selection is not a project
		-- a committed change on the branch counts like an uncommitted one
		touch(dir, "scripts/other.sh")
		commit(dir, "branch change")
		expectScope({ "pickman/src/A.luau" }, "ALL")
	end)

	it("AC6: a declared input in the other suite does not cross suite isolation", function()
		local dir = fixture("declared", function(d: string)
			-- a z-nile spec declares a pickman file as an input: a game change still selects no tooling spec
			gatefix.write(`{d}/z-nile/tests/inputs.tsv`, "tests/unit/zdecl.spec.luau\tpickman/src/A.luau\n")
			gatefix.write(`{d}/z-nile/tests/unit/zdecl.spec.luau`, "--!strict\nreturn {}\n")
		end)
		local ok, out = scope(dir, { "pickman/src/A.luau" })
		t.expect(ok).toBe(true)
		t.expect(out).toBe("pickman")
	end)

	it("AC6: a declared input in the other suite does not cross suite isolation", function()
		local dir = fixture("rule3", function(d: string)
			-- the same non-spec file under z-nile/tests is an input of a pickman spec and of a z-nile spec
			gatefix.write(`{d}/z-nile/tests/shared.txt`, "x\n")
			gatefix.write(
				`{d}/z-nile/tests/inputs.tsv`,
				"tests/unit/zdecl.spec.luau\tz-nile/tests/shared.txt\n"
			)
			gatefix.write(`{d}/z-nile/tests/unit/zdecl.spec.luau`, "--!strict\nreturn {}\n")
			gatefix.write(`{d}/pickman/tests/inputs.tsv`, "tests/unit/a.spec.luau\tz-nile/tests/shared.txt\n")
		end)
		local ok, out = scope(dir, { "z-nile/tests/shared.txt" })
		t.expect(ok).toBe(true)
		t.expect(out).toBe("z-nile")
	end)

	it("AC6: a * declaration in the tooling suite is not selected by a game change", function()
		local dir = fixture("star", function(d: string)
			gatefix.write(`{d}/z-nile/tests/inputs.tsv`, "tests/unit/zstar.spec.luau\t*\n")
			gatefix.write(`{d}/z-nile/tests/unit/zstar.spec.luau`, "--!strict\nreturn {}\n")
		end)
		local ok, out = scope(dir, { "pickman/src/A.luau" })
		t.expect(ok).toBe(true)
		t.expect(out).toBe("pickman")
	end)

	it(
		"AC6: rule 4: a path outside the project's home or tracker root that selects nothing makes the answer ALL",
		function()
			local dir = fixture("rule4")
			local function expectScope(changed: { string }, want: string)
				local ok, out = scope(dir, changed)
				t.expect(ok).toBe(true)
				t.expect(out).toBe(want)
			end
			-- none of these forces a full run or selects a spec by itself: only rule 4 turns them into ALL
			expectScope({ "pickman/src/A.luau", "SETUP.md" }, "ALL")
			expectScope({ "pickman/src/A.luau", "z-nile/tests/notes.md" }, "ALL")
			expectScope({ "pickman/src/A.luau", "z-nile/.tracker/notes.md" }, "ALL")
			-- the project's own tracker root is allowed
			expectScope({ "pickman/src/A.luau", "pickman/.tracker/notes.md" }, "pickman")
		end
	)
end)
