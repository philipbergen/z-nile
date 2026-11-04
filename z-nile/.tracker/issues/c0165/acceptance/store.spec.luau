--!strict
-- c0165 AC4: the results db through the sqlite3 CLI: a record reads back, recording is idempotent (the latest result
-- wins, so two runs that reach one fingerprint at once leave one row), any text round-trips, gates are kept, prune drops
-- only old rows, and `open` answers nil with a reason instead of failing. The schema version is resultsdb.SCHEMA, never a
-- literal: later issues raise it. Real sqlite3, on databases under
-- .cache/c0165-store (z-nile's home).
local fs = require("@lune/fs")
local process = require("@lune/process")
local resultsdb = require("@znile/lib/resultsdb")
local t = require("@tests/lib/t")

local here = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local base = `{here}/.cache/c0165-store`

local function fresh(name: string): string
	fs.writeDir(base)
	local path = `{base}/{name}.sqlite`
	for _, suffix in { "", "-wal", "-shm", "-journal" } do
		if fs.isFile(path .. suffix) then
			fs.removeFile(path .. suffix)
		end
	end
	return path
end
local function opened(name: string): any
	local db, err = resultsdb.open(fresh(name))
	if db == nil then
		error(`open failed: {err}`)
	end
	return db
end

local R = "req" .. "uire"

return t.spec("c0165 results db", function(it)
	it("AC4: a record reads back; passed needs a loaded file and every case ok", function()
		local db = opened("record")
		local cases = { { name = "one", ok = true }, { name = "two", ok = true } }
		t.expect(resultsdb.rows(db, { "a" })["a"]).toBe(nil)
		resultsdb.record(db, "a", "z-nile", "tests/a.spec.luau", true, cases, nil, 2.25, 100)
		local ra = resultsdb.rows(db, { "a", "missing" })
		t.expect(ra["missing"]).toBe(nil)
		t.expect(ra["a"].state).toBe("passed")
		t.expect(ra["a"].cases).toEqual(cases)
		t.expect(ra["a"].seconds).toBe(2.25)
		t.expect(ra["a"].updated).toBe(100)
		-- a failing case, or a file that did not load, is failed, with the run's FAIL text
		resultsdb.record(
			db,
			"b",
			"z-nile",
			"tests/b.spec.luau",
			true,
			{ { name = "one", ok = false } },
			"FAIL b",
			1,
			102
		)
		local rb = resultsdb.rows(db, { "b" })["b"]
		t.expect(rb.state).toBe("failed")
		t.expect(rb.detail).toBe("FAIL b")
		resultsdb.record(db, "c", "z-nile", "tests/c.spec.luau", false, {}, "could not load", 0, 103)
		t.expect(resultsdb.rows(db, { "c" })["c"].state).toBe("failed")
	end)

	it("AC4: recording is idempotent, and the latest result for a fingerprint wins", function()
		local db = opened("idem")
		local ok = { { name = "c", ok = true } }
		local bad = { { name = "c", ok = false } }
		resultsdb.record(db, "fp", "z-nile", "tests/a.spec.luau", true, ok, nil, 1, 10)
		resultsdb.record(db, "fp", "z-nile", "tests/a.spec.luau", true, ok, nil, 1, 10) -- the same record again
		t.expect(resultsdb.rows(db, { "fp" })["fp"].state).toBe("passed")
		resultsdb.record(db, "fp", "z-nile", "tests/a.spec.luau", true, bad, "FAIL a", 2, 11)
		t.expect(resultsdb.rows(db, { "fp" })["fp"].state).toBe("failed")
		resultsdb.record(db, "fp", "z-nile", "tests/a.spec.luau", true, ok, nil, 3, 12)
		local last = resultsdb.rows(db, { "fp" })["fp"]
		t.expect(last.state).toBe("passed")
		t.expect(last.seconds).toBe(3)
		t.expect(last.detail).toBe(nil)
	end)

	it("AC4: concurrent recorders of one fingerprint leave one row and none fails", function()
		local path = fresh("race")
		local db = opened("race")
		-- warm the schema, then race 12 separate sqlite3 processes through the adapter's own record
		resultsdb.record(db, "warm", "z-nile", "w", true, {}, nil, 1, 1)
		local script = table.concat({
			-- the script lives in .cache/c0165-store, two folders under the home; R keeps literal require text out of this file
			`local r = {R}("../../lib/resultsdb")`,
			`local db = r.open("{path}")`,
			`local process = {R}("@lune/process")`,
			'r.record(db, "racefp", "z-nile", "tests/r.spec.luau", true, { { name = "c", ok = true } }, nil, 1, tonumber(process.args[1]) :: number)',
			'print("done")',
		}, "\n")
		fs.writeFile(`{base}/race.luau`, script)
		local r = process.exec("bash", {
			"-c",
			'for i in $(seq 1 12); do lune run "$1" -- "$i" & done; wait',
			"_",
			`{base}/race.luau`,
		})
		t.expect(r.ok).toBe(true)
		local _, done = string.gsub(r.stdout, "done", "")
		t.expect(done).toBe(12)
		t.expect(process.exec("sqlite3", { path, "select count(*) from specs where fp = 'racefp'" }).stdout)
			.toBe("1\n")
		t.expect(resultsdb.rows(db, { "racefp" })["racefp"].state).toBe("passed")
	end)

	it("AC4: any text round-trips: quotes, newlines, comment markers, unicode", function()
		local db = opened("text")
		local odd = "it's a \"case\" -- with; DROP TABLE specs; --\nsecond line \u{2713} ''"
		local cases = { { name = odd, ok = true } }
		resultsdb.record(db, odd, "z-nile", "tests/o'dd -- .spec.luau", true, cases, odd, 0.5, 5)
		local r = resultsdb.rows(db, { odd })[odd]
		t.expect(r ~= nil).toBe(true)
		t.expect(r.cases).toEqual(cases)
		t.expect(r.detail).toBe(odd)
		-- the table survived
		t.expect(resultsdb.rows(db, { "nothing" })["nothing"]).toBe(nil)
	end)

	it("AC4: gates are kept; prune drops only old rows", function()
		local db = opened("gates")
		t.expect(resultsdb.gatePassed(db, "k1")).toBe(nil)
		local summary = "== lint (selene) (0.4s)\nwarnings: 0 it's\n== format (stylua --check) (0.1s)\n"
		resultsdb.recordGate(db, "k1", "affected", "pickman,z-nile", summary, 1000)
		t.expect(resultsdb.gatePassed(db, "k1")).toEqual({ passedAt = 1000, summary = summary })
		resultsdb.record(db, "old", "z-nile", "tests/old.spec.luau", true, {}, nil, 1, 1000)
		resultsdb.record(db, "new", "z-nile", "tests/new.spec.luau", true, {}, nil, 1, 1000 + 29 * 86400)
		resultsdb.prune(db, 1000 + 31 * 86400)
		local rows = resultsdb.rows(db, { "old", "new" })
		t.expect(rows["old"]).toBe(nil)
		t.expect(rows["new"] ~= nil).toBe(true)
		t.expect(resultsdb.gatePassed(db, "k1")).toBe(nil)
	end)

	it(
		"AC4: open stamps the module's own schema version and answers nil with a reason: a newer schema, unwritable, no sqlite3",
		function()
			-- the rule, not today's number: a new db is stamped resultsdb.SCHEMA, and c0238 / c0240 raise that constant
			local made = fresh("version")
			t.expect(resultsdb.open(made) ~= nil).toBe(true)
			t.expect(process.exec("sqlite3", { made, "PRAGMA user_version;" }).stdout)
				.toBe(`{resultsdb.SCHEMA}\n`)
			-- opening it again keeps it ours
			t.expect(resultsdb.open(made) ~= nil).toBe(true)
			-- a db a newer version of the code made (any number above SCHEMA): this code leaves it alone
			local path = fresh("schema")
			t.expect(process.exec("sqlite3", { path, `PRAGMA user_version={resultsdb.SCHEMA + 1};` }).ok)
				.toBe(true)
			local db, err = resultsdb.open(path)
			t.expect(db).toBe(nil)
			t.expect(string.find(string.lower(err or ""), "schema", 1, true) ~= nil).toBe(true)
			-- and it did not touch it
			t.expect(process.exec("sqlite3", { path, "PRAGMA user_version;" }).stdout)
				.toBe(`{resultsdb.SCHEMA + 1}\n`)
			-- a folder it can't write
			local ro = `{base}/readonly`
			fs.writeDir(ro)
			process.exec("chmod", { "555", ro })
			local db2, err2 = resultsdb.open(`{ro}/x.sqlite`)
			process.exec("chmod", { "755", ro })
			t.expect(db2).toBe(nil)
			t.expect(err2 ~= nil and err2 ~= "").toBe(true)
			-- no sqlite3 on PATH
			local oldPath = process.env.PATH
			process.env.PATH = `{base}/no-such-bin`
			local ok, db3, err3 = pcall(resultsdb.open, fresh("nosqlite"))
			process.env.PATH = oldPath
			t.expect(ok).toBe(true)
			t.expect(db3).toBe(nil)
			t.expect(string.find(err3 or "", "sqlite3", 1, true) ~= nil).toBe(true)
		end
	)
end)
