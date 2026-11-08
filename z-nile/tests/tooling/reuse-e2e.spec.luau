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
			PICKMAN_GATE_PID = "7316",
		}
		local ok, out = reusefix.specs(dir, AB, env)
		t.expect(ok).toBe(true)
		t.expect(has(out, "not recorded: outer sandbox")).toBe(true)
		t.expect(fs.isFile(`{dir}/pickman/.cache/spec-norecord-7316`)).toBe(true)
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

	it("a record for another file counts as no result", function()
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

	it("a link's text is part of the digest, a nested repository turns reuse off", function()
		local dir = reusefix.make(base, "linktext")
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
		-- the same link name pointing at two folders, then at a file, then a copy of that file
		process.exec("ln", { "-s", "pickman/src", `{dir}/L` })
		local toSrc = digest()
		process.exec("rm", { `{dir}/L` })
		process.exec("ln", { "-s", "pickman", `{dir}/L` })
		local toHome = digest()
		t.expect(toSrc ~= toHome).toBe(true)
		process.exec("rm", { `{dir}/L` })
		process.exec("ln", { "-s", "pickman/src/A.luau", `{dir}/L` })
		local toFile = digest()
		process.exec("rm", { `{dir}/L` })
		process.exec("cp", { `{dir}/pickman/src/A.luau`, `{dir}/L` })
		t.expect(digest() ~= toFile).toBe(true)
		process.exec("rm", { `{dir}/L` })
		t.expect(digest()).toBe(d0)
		-- an untracked nested repository (git lists it as a folder): no digest at all, so no reuse
		t.expect(process.exec("git", { "init", "-q", `{dir}/nested` }).ok).toBe(true)
		write(`{dir}/nested/x.luau`, "return 1\n")
		fixture.git(`{dir}/nested`, { "config", "user.name", "c0165-nested" })
		fixture.git(`{dir}/nested`, { "config", "user.email", "c0165-nested@example.invalid" })
		fixture.git(`{dir}/nested`, { "add", "-A" })
		fixture.git(`{dir}/nested`, { "commit", "-qm", "nested" })
		t.expect(digest()).toBe("")
		process.exec("rm", { "-rf", `{dir}/nested` })
		t.expect(digest()).toBe(d0)
		-- a submodule (a gitlink in the index) turns reuse off too (review 005 F2)
		t.expect(process.exec("git", { "init", "-q", `{dir}/sub` }).ok).toBe(true)
		write(`{dir}/sub/x.luau`, "return 1\n")
		fixture.git(`{dir}/sub`, { "config", "user.name", "c0165-sub" })
		fixture.git(`{dir}/sub`, { "config", "user.email", "c0165-sub@example.invalid" })
		fixture.git(`{dir}/sub`, { "add", "-A" })
		fixture.git(`{dir}/sub`, { "commit", "-qm", "sub" })
		local subHead =
			reusefix.trim(process.exec("git", { "rev-parse", "HEAD" }, { cwd = `{dir}/sub` }).stdout)
		fixture.git(dir, { "update-index", "--add", "--cacheinfo", `160000,{subHead},sub` })
		t.expect(digest()).toBe("")
		fixture.git(dir, { "update-index", "--force-remove", "sub" })
		process.exec("rm", { "-rf", `{dir}/sub` })
		t.expect(digest()).toBe(d0)
	end)

	-- review 005 F1: the digest holds the selection, which reads the merge-base and HEAD's tree besides the files
	local function digestAt(dir: string): string
		local r = process.exec(
			"lune",
			{ "run", "z-nile/specs", "--", "digest", "--mode", "affected", "--projects", "pickman" },
			{ cwd = dir, env = reusefix.env(dir) }
		)
		return reusefix.trim(r.stdout)
	end
	local function withC(name: string): string
		return reusefix.make(base, name, {
			extra = { c = { needs = "C", expect = 1 } },
			setup = function(d: string)
				write(`{d}/pickman/src/C.luau`, "return { value = 1 }\n")
			end,
		})
	end

	it("the same tree on main by another commit is another digest when the selection differs", function()
		local dir = withC("sel-mergebase")
		write(`{dir}/pickman/src/C.luau`, "return { value = 3 }\n")
		fixture.git(dir, { "commit", "-qam", "C = 3" })
		fixture.git(dir, { "checkout", "-q", "main" })
		fixture.git(dir, { "checkout", "-q", "work", "--", "." })
		fixture.git(dir, { "commit", "-qm", "same tree by another commit" })
		local onMain = digestAt(dir) -- nothing affected
		fixture.git(dir, { "checkout", "-q", "work" })
		local onWork = digestAt(dir) -- c.spec affected
		t.expect(#onMain).toBe(64)
		t.expect(#onWork).toBe(64)
		t.expect(onMain ~= onWork).toBe(true)
	end)

	it("a commit undone in the index leaves the same tree and another selection: another digest", function()
		local dir = withC("sel-head")
		local onMain = digestAt(dir)
		write(`{dir}/pickman/src/C.luau`, "return { value = 2 }\n")
		fixture.git(dir, { "commit", "-qam", "C = 2" })
		fixture.git(dir, { "checkout", "-q", "main", "--", "pickman/src/C.luau" })
		local undone = digestAt(dir)
		t.expect(#undone).toBe(64)
		t.expect(undone ~= onMain).toBe(true)
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

	-- review 006 F1: git's index is part of how git stores a path
	it("a staged mode that differs from the tree moves the digest, and a plain git add does not", function()
		local dir = withC("index")
		write(`{dir}/pickman/src/C.luau`, "return { value = 1 } -- edited\n")
		local d0 = digestAt(dir)
		t.expect(#d0).toBe(64)
		fixture.git(dir, { "add", "pickman/src/C.luau" }) -- the cost guard: staging an edit moves nothing
		t.expect(digestAt(dir)).toBe(d0)
		fixture.git(dir, { "reset", "-q" })
		t.expect(digestAt(dir)).toBe(d0)
		-- a link staged as a regular file: the tree holds the same bytes, the index another mode
		t.expect(process.exec("ln", { "-s", "pickman/src", `{dir}/L` }).ok).toBe(true)
		fixture.git(dir, { "add", "L" })
		local staged = digestAt(dir)
		fixture.git(dir, {
			"update-index",
			"--cacheinfo",
			`100644,{reusefix.trim(
				process.exec(
					"git",
					{ "hash-object", "--stdin" },
					{ cwd = dir, stdio = { stdin = "pickman/src" } }
				).stdout
			)},L`,
		})
		t.expect(digestAt(dir) ~= staged).toBe(true)
	end)
end)
