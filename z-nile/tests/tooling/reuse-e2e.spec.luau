--!strict
-- c0165 (executor's, review 002 F2 to F4): the rules of the orchestrator tested through `z-nile/specs` itself, in fixture
-- repositories (tests/lib/reusefix.luau, a copy of the item's gatefix), so a wrong implementation in specs.luau turns
-- one of them red:
--   a db whose read fails turns reuse off and never fails the run          (a missing pcall around resultsdb.rows)
--   a run records with ONE sqlite3 write call                              (a call per spec)
--   a failed spec is recorded failed, with its FAIL text                   (failures never recorded)
--   a weak-jail run writes its no-record marker even when the db is off    (the guard inside the db branch)
--   HEAD enters the whole-gate digest only for a `*` selection             (HEAD in every digest)
-- Fixtures under .cache/c0165-reuse-e2e (z-nile's home).
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local reusefix = require("@tests/lib/reusefix")
local t = require("@tests/lib/t")

local here = reusefix.trim(process.exec("pwd", { "-P" }).stdout)
local base = `{here}/.cache/c0165-reuse-e2e`
local AB = reusefix.AB
local has, count, ran, write = reusefix.has, reusefix.count, reusefix.ran, reusefix.write

local function realSqlite(): string
	return reusefix.trim(process.exec("sh", { "-c", "command -v sqlite3" }).stdout)
end

-- a sqlite3 that fails the read of the specs table and passes everything else through
local function failingRead(dir: string): string
	write(
		`{dir}/sqlite3-failing-read`,
		'#!/bin/sh\nin=$(cat)\ncase "$in" in\n*"FROM specs WHERE fp IN"*) echo boom >&2; exit 1 ;;\nesac\n'
			.. `printf '%s' "$in" | exec "{realSqlite()}" "$@"\n`
	)
	process.exec("chmod", { "+x", `{dir}/sqlite3-failing-read` })
	return `{dir}/sqlite3-failing-read`
end

return t.spec("c0165 the orchestrator's rules, end to end", function(it)
	it("a db whose read fails turns reuse off: the run still passes and runs every spec", function()
		local dir = reusefix.make(base, "readfail")
		local ok, out = reusefix.specs(dir, AB, { PICKMAN_SQLITE3 = failingRead(dir) })
		t.expect(ok).toBe(true)
		t.expect(has(out, "reuse off:")).toBe(true)
		t.expect(count(ran(dir), "a")).toBe(1)
		t.expect(count(ran(dir), "b")).toBe(1)
	end)

	it("a run of two specs records with one sqlite3 write call", function()
		local dir = reusefix.make(base, "onecall")
		write(
			`{dir}/sqlite3-counting`,
			'#!/bin/sh\nin=$(cat)\ncase "$in" in\n*INSERT*) echo write >> "'
				.. `{dir}/writes.log"`
				.. ' ;;\nesac\nprintf \'%s\' "$in" | exec "'
				.. realSqlite()
				.. '" "$@"\n'
		)
		process.exec("chmod", { "+x", `{dir}/sqlite3-counting` })
		local ok, _ = reusefix.specs(dir, AB, { PICKMAN_SQLITE3 = `{dir}/sqlite3-counting` })
		t.expect(ok).toBe(true)
		t.expect(count(fs.readFile(`{dir}/writes.log`), "write")).toBe(1)
		t.expect(reusefix.sql(dir, "select count(*) from specs")).toBe("2")
	end)

	it("a failed spec is recorded failed with its FAIL text, and is run again", function()
		local dir = reusefix.make(base, "failrow")
		write(`{dir}/pickman/src/A.luau`, "return { value = 2 }\n")
		local ok1, _ = reusefix.specs(dir, AB)
		t.expect(ok1).toBe(false)
		t.expect(reusefix.sql(dir, "select state from specs where spec = 'tests/unit/a.spec.luau'"))
			.toBe("failed")
		t.expect(
			reusefix.sql(
				dir,
				"select count(*) from specs where spec = 'tests/unit/a.spec.luau' and detail like '%FAIL%'"
			)
		).toBe("1")
		-- the passing spec of the same failing run is not recorded as passed (the run exited non-zero)
		t.expect(reusefix.sql(dir, "select count(*) from specs where state = 'passed'")).toBe("0")
		reusefix.clearRan(dir)
		local _, _ = reusefix.specs(dir, AB)
		t.expect(count(ran(dir), "a")).toBe(1)
	end)

	it("a weak-jail run writes its no-record marker even when the db read fails", function()
		local dir = reusefix.make(base, "marker")
		local env = {
			PATH = reusefix.weakJail(dir),
			PICKMAN_SQLITE3 = failingRead(dir),
			PICKMAN_GATE_PID = "4242",
		}
		local ok, out = reusefix.specs(dir, AB, env)
		t.expect(ok).toBe(true)
		t.expect(has(out, "not recorded: outer sandbox")).toBe(true)
		t.expect(fs.isFile(`{dir}/pickman/.cache/spec-norecord-4242`)).toBe(true)
	end)

	it(
		"a results file cannot put SQL into the db: a forged number is stored as 0 and nothing else runs",
		function()
			local dir = reusefix.make(base, "forge")
			local path = reusefix.editResults(
				dir,
				"forge",
				[[doc.files[1].seconds = "0); ATTACH DATABASE 'PWNED.sqlite' AS x; --"]]
			)
			local ok, _ = reusefix.specs(dir, { "--", "tests/unit/a.spec.luau" }, { PATH = path })
			t.expect(ok).toBe(true)
			t.expect(fs.isFile(`{dir}/PWNED.sqlite`)).toBe(false)
			t.expect(fs.isFile(`{dir}/pickman/PWNED.sqlite`)).toBe(false)
			t.expect(reusefix.sql(dir, "select seconds from specs where spec = 'tests/unit/a.spec.luau'"))
				.toBe("0.0")
		end
	)

	it("a record for another file, or with a wrong type, counts as no result", function()
		local dir = reusefix.make(base, "wrongfile")
		local path = reusefix.editResults(dir, "wrongfile", [[doc.files[1].file = "tests/unit/b.spec.luau"]])
		local ok, out = reusefix.specs(dir, { "--", "tests/unit/a.spec.luau" }, { PATH = path })
		t.expect(ok).toBe(false)
		t.expect(has(out, "FAIL tests/unit/a.spec.luau: no result for it")).toBe(true)
		t.expect(reusefix.sql(dir, "select count(*) from specs")).toBe("0")
	end)

	it("a link is part of a digest the way git stores it: a link to a folder, added and removed", function()
		local dir = reusefix.make(base, "link")
		write(`{dir}/pickman/src/A.luau`, "return { value = 1 } -- edited\n")
		local function digest(): string
			local r = process.exec(
				"lune",
				{ "run", "z-nile/specs", "--", "digest", "--mode", "affected", "--projects", "pickman" },
				{ cwd = dir, env = reusefix.env(dir) }
			)
			return reusefix.trim(r.stdout)
		end
		local d0 = digest()
		t.expect(#d0).toBe(64)
		t.expect(process.exec("ln", { "-s", "pickman/src", `{dir}/folderlink` }).ok).toBe(true)
		local d1 = digest()
		t.expect(d1 ~= d0).toBe(true)
		process.exec("rm", { `{dir}/folderlink` })
		t.expect(digest()).toBe(d0)
		t.expect(process.exec("ln", { "-s", "does-not-exist", `{dir}/dangling` }).ok).toBe(true)
		t.expect(digest() ~= d0).toBe(true)
	end)

	it("HEAD moves a whole-gate digest only when a * spec is selected", function()
		local function digest(dir: string): string
			local r = process.exec(
				"lune",
				{ "run", "z-nile/specs", "--", "digest", "--mode", "affected", "--projects", "pickman" },
				{ cwd = dir, env = reusefix.env(dir) }
			)
			return reusefix.trim(r.stdout)
		end
		local plain = reusefix.make(base, "digest-plain")
		write(`{plain}/pickman/src/A.luau`, "return { value = 1 } -- edited\n")
		local d1 = digest(plain)
		t.expect(#d1).toBe(64)
		fixture.git(plain, { "commit", "-qam", "same content, new HEAD" })
		t.expect(digest(plain)).toBe(d1)
		local starred = reusefix.make(base, "digest-star", {
			setup = function(d: string)
				write(`{d}/pickman/tests/inputs.tsv`, "# extra inputs per spec\ntests/unit/b.spec.luau\t*\n")
			end,
		})
		write(`{starred}/pickman/src/A.luau`, "return { value = 1 } -- edited\n")
		local s1 = digest(starred)
		fixture.git(starred, { "commit", "-qam", "same content, new HEAD" })
		t.expect(digest(starred) ~= s1).toBe(true)
	end)
end)
