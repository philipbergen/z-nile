--!strict
-- c0165 (executor's, review 001 F1 to F4): rules the sequestered specs leave open, each with the mutant it kills.
--   F1: a sqlite3 that returns a nested array as text is read like one that returns an array (the build differs by version)
--   F2: the host's jail name for "no jail" (what fence.luau writes off macOS) lets a run record on Linux
--   F3: HEAD enters the whole-gate digest only for a `*` selection (a HEAD in every digest reruns every gate per commit)
--   F4: a run's records and the prune are ONE sqlite3 call, one transaction
-- Fixtures under .cache/c0165-reuse-rules (z-nile's home).
local fingerprint = require("@znile/lib/fingerprint")
local fs = require("@lune/fs")
local process = require("@lune/process")
local resultsdb = require("@znile/lib/resultsdb")
local reuseplan = require("@znile/lib/reuseplan")
local t = require("@tests/lib/t")

local here = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local base = `{here}/.cache/c0165-reuse-rules`
local function gsubTrim(s: string): string
	return (string.gsub(s, "%s+$", ""))
end

local function stub(name: string, body: string): string
	fs.writeDir(base)
	local path = `{base}/{name}`
	fs.writeFile(path, "#!/bin/sh\n" .. body)
	process.exec("chmod", { "+x", path })
	return path
end

local function withSqlite<T>(path: string, fn: () -> T): T
	local old = process.env.PICKMAN_SQLITE3
	process.env.PICKMAN_SQLITE3 = path
	local ok, result = pcall(fn)
	process.env.PICKMAN_SQLITE3 = old
	if not ok then
		error(result, 0)
	end
	return result :: T
end

return t.spec("c0165 reuse rules beyond the sequestered specs", function(it)
	it("F1: rows reads a nested array that the sqlite3 build returns as text", function()
		local text = [[{"rows":"[{\"fp\":\"a\",\"state\":\"passed\",\"cases\":\"[]\",\"updated\":7}]"}]]
		fs.writeDir(base)
		fs.writeFile(`{base}/rows.json`, text .. "\n")
		local bin = stub(
			"text-sqlite3",
			'in=$(cat)\ncase "$in" in\n*user_version*) echo \'{"v":1}\' ;;\n*"FROM specs"*) cat "'
				.. base
				.. "/rows.json\" ;;\n*) echo '{}' ;;\nesac\n"
		)
		local rows = withSqlite(bin, function()
			local db = resultsdb.open(`{base}/text.sqlite`) :: resultsdb.Db
			return resultsdb.rows(db, { "a" })
		end)
		t.expect(rows["a"].state).toBe("passed")
		t.expect(rows["a"].updated).toBe(7)
	end)

	it("F1: a sqlite3 that fails on a read raises from rows (specs.luau turns reuse off on it)", function()
		local bin = stub(
			"failing-sqlite3",
			'in=$(cat)\ncase "$in" in\n*user_version*) echo \'{"v":1}\' ;;\n*) echo boom >&2; exit 1 ;;\nesac\n'
		)
		withSqlite(bin, function()
			local db = resultsdb.open(`{base}/fail.sqlite`) :: resultsdb.Db
			t.expect((pcall(resultsdb.rows, db, { "a" }))).toBe(false)
			return nil
		end)
	end)

	it("F2: the jail name fence.luau writes off macOS lets a Linux run record, a macOS run not", function()
		local name = "none (not macOS: environment guards only)"
		t.expect(reuseplan.records(name, "linux")).toBe(true)
		t.expect(reuseplan.records(name, "macos")).toBe(false)
		t.expect(reuseplan.records("outer sandbox (protects the repository)", "linux")).toBe(false)
		-- the producer's own text, so a rewording there turns this red
		local fence = fs.readFile(`{here}/tests/lib/fence.luau`)
		t.expect(string.find(fence, name, 1, true) ~= nil).toBe(true)
	end)

	it("F3: HEAD is in a digest's extra only for a * selection; a declared ref always", function()
		local git: fingerprint.GitState =
			{ head = string.rep("1", 40), refs = { ["refs/heads/x"] = string.rep("2", 40) } }
		local plain = fingerprint.digestExtra("affected", { "pickman" }, "b", false, git, {})
		local starred = fingerprint.digestExtra("affected", { "pickman" }, "b", true, git, {})
		t.expect(table.find(plain, `HEAD {git.head}`)).toBe(nil)
		t.expect(table.find(starred, `HEAD {git.head}`) ~= nil).toBe(true)
		local withRef = fingerprint.digestExtra(
			"affected",
			{ "pickman" },
			"b",
			false,
			git,
			{ "refs/heads/x", "refs/heads/gone" }
		)
		t.expect(table.find(withRef, `refs/heads/x\t{git.refs["refs/heads/x"]}`) ~= nil).toBe(true)
		t.expect(table.find(withRef, "refs/heads/gone\tMISSING") ~= nil).toBe(true)
		-- the projects and the base are part of it
		local two = table.concat(fingerprint.digestExtra("affected", { "a", "b" }, "b", false, git, {}), "|")
		t.expect(two ~= table.concat(plain, "|")).toBe(true)
	end)

	it("F4: recordMany writes every row and the prune in ONE sqlite3 call", function()
		local log = `{base}/calls.log`
		if fs.isFile(log) then
			fs.removeFile(log)
		end
		local real = gsubTrim(process.exec("sh", { "-c", "command -v sqlite3" }).stdout)
		local bin = stub("counting-sqlite3", `echo call >> "{log}"\nexec "{real}" "$@"\n`)
		local path = `{base}/many.sqlite`
		for _, suffix in { "", "-wal", "-shm" } do
			if fs.isFile(path .. suffix) then
				fs.removeFile(path .. suffix)
			end
		end
		withSqlite(bin, function()
			local db = resultsdb.open(path) :: resultsdb.Db
			fs.writeFile(log, "")
			local items: { resultsdb.Item } = {}
			for i = 1, 3 do
				table.insert(items, {
					fp = `fp{i}`,
					home = "z-nile",
					spec = `tests/s{i}.spec.luau`,
					loaded = true,
					cases = { { name = "c", ok = true } },
					detail = nil,
					seconds = 1,
				})
			end
			resultsdb.recordMany(db, items, 100)
			local calls = 0
			for _ in string.gmatch(fs.readFile(log), "call") do
				calls += 1
			end
			t.expect(calls).toBe(1)
			local rows = resultsdb.rows(db, { "fp1", "fp2", "fp3" })
			t.expect(rows["fp2"].state).toBe("passed")
			return nil
		end)
	end)
end)
