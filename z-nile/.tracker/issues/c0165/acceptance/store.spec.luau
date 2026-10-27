--!strict
-- c0165 AC4: the results db through the sqlite3 CLI: claims by insert or compare-and-swap (one winner), records only
-- into its own or an absent row, round-trips any text, keeps gates and learned inputs, and `open` answers nil with a
-- reason instead of failing. Real sqlite3, on databases under .cache/c0165-store (z-nile's home).
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
local A = { pid = 101, start = "1700000000.000001" }
local B = { pid = 202, start = "1700000000.000002" }

return t.spec("c0165 results db", function(it)
	it("AC4: claim by insert has one winner, and a row reads back", function()
		local db = opened("claim")
		t.expect(resultsdb.claim(db, "fp1", "z-nile", "tests/a.spec.luau", A, nil)).toBe(true)
		t.expect(resultsdb.claim(db, "fp1", "z-nile", "tests/a.spec.luau", B, nil)).toBe(false)
		local rows = resultsdb.rows(db, { "fp1", "missing" })
		t.expect(rows["missing"]).toBe(nil)
		t.expect(rows["fp1"].state).toBe("running")
		t.expect(rows["fp1"].pid).toBe(A.pid)
		t.expect(rows["fp1"].start).toBe(A.start)
	end)

	it("AC4: compare-and-swap takes over only the row it read", function()
		local db = opened("cas")
		t.expect(resultsdb.claim(db, "fp", "z-nile", "tests/a.spec.luau", A, nil)).toBe(true)
		local seen = resultsdb.rows(db, { "fp" })["fp"]
		-- B and a third claimer both read A's row; the first swap wins, the second finds it changed
		t.expect(resultsdb.claim(db, "fp", "z-nile", "tests/a.spec.luau", B, seen)).toBe(true)
		t.expect(resultsdb.claim(db, "fp", "z-nile", "tests/a.spec.luau", { pid = 303, start = "x" }, seen))
			.toBe(false)
		t.expect(resultsdb.rows(db, { "fp" })["fp"].pid).toBe(B.pid)
		-- a failed row is claimed the same way
		resultsdb.record(
			db,
			"fp",
			"z-nile",
			"tests/a.spec.luau",
			B,
			{ { name = "c", ok = false } },
			"FAIL x",
			1.5,
			10
		)
		local failed = resultsdb.rows(db, { "fp" })["fp"]
		t.expect(failed.state).toBe("failed")
		t.expect(resultsdb.claim(db, "fp", "z-nile", "tests/a.spec.luau", A, failed)).toBe(true)
		t.expect(resultsdb.rows(db, { "fp" })["fp"].state).toBe("running")
	end)

	it("AC4: concurrent claimers of one fingerprint: exactly one wins", function()
		local path = fresh("race")
		local db = opened("race")
		-- warm the schema, then race 12 separate sqlite3 processes through the adapter's own insert
		t.expect(resultsdb.claim(db, "warm", "z-nile", "w", A, nil)).toBe(true)
		local script = table.concat({
			-- the script lives in .cache/c0165-store, two folders under the home; R keeps literal require text out of this file
			`local r = {R}("../../lib/resultsdb")`,
			`local db = r.open("{path}")`,
			`local process = {R}("@lune/process")`,
			'print(if r.claim(db, "racefp", "z-nile", "tests/r.spec.luau", { pid = tonumber(process.args[1]) :: number, start = "s" }, nil) then "won" else "lost")',
		}, "\n")
		fs.writeFile(`{base}/race.luau`, script)
		local r = process.exec("bash", {
			"-c",
			'for i in $(seq 1 12); do lune run "$1" -- "$i" & done; wait',
			"_",
			`{base}/race.luau`,
		})
		t.expect(r.ok).toBe(true)
		local _, wins = string.gsub(r.stdout, "won", "")
		local _, losses = string.gsub(r.stdout, "lost", "")
		t.expect(wins).toBe(1)
		t.expect(losses).toBe(11)
	end)

	it("AC4: record writes only into its own or an absent row, never over another live run", function()
		local db = opened("record")
		local cases = { { name = "one", ok = true }, { name = "two", ok = true } }
		-- absent row: a full run records it
		resultsdb.record(db, "a", "z-nile", "tests/a.spec.luau", A, cases, nil, 2.25, 100)
		local ra = resultsdb.rows(db, { "a" })["a"]
		t.expect(ra.state).toBe("passed")
		t.expect(ra.cases).toEqual(cases)
		t.expect(ra.seconds).toBe(2.25)
		t.expect(ra.updated).toBe(100)
		-- B is running "b": A's record must not land
		t.expect(resultsdb.claim(db, "b", "z-nile", "tests/b.spec.luau", B, nil)).toBe(true)
		resultsdb.record(db, "b", "z-nile", "tests/b.spec.luau", A, cases, nil, 1, 101)
		t.expect(resultsdb.rows(db, { "b" })["b"].state).toBe("running")
		t.expect(resultsdb.rows(db, { "b" })["b"].pid).toBe(B.pid)
		-- its owner's record lands, and a failing case makes it failed
		resultsdb.record(
			db,
			"b",
			"z-nile",
			"tests/b.spec.luau",
			B,
			{ { name = "one", ok = false } },
			"FAIL b",
			1,
			102
		)
		local rb = resultsdb.rows(db, { "b" })["b"]
		t.expect(rb.state).toBe("failed")
		t.expect(rb.detail).toBe("FAIL b")
		-- release drops only the owner's running row
		t.expect(resultsdb.claim(db, "c", "z-nile", "tests/c.spec.luau", B, nil)).toBe(true)
		resultsdb.release(db, "c", A)
		t.expect(resultsdb.rows(db, { "c" })["c"] ~= nil).toBe(true)
		resultsdb.release(db, "c", B)
		t.expect(resultsdb.rows(db, { "c" })["c"]).toBe(nil)
	end)

	it("AC4: any text round-trips: quotes, newlines, comment markers, unicode", function()
		local db = opened("text")
		local odd = "it's a \"case\" -- with; DROP TABLE specs; --\nsecond line \u{2713} ''"
		local cases = { { name = odd, ok = true } }
		resultsdb.record(db, odd, "z-nile", "tests/o'dd -- .spec.luau", A, cases, odd, 0.5, 5)
		local r = resultsdb.rows(db, { odd })[odd]
		t.expect(r ~= nil).toBe(true)
		t.expect(r.cases).toEqual(cases)
		t.expect(r.detail).toBe(odd)
		-- the table survived
		t.expect(resultsdb.rows(db, { "nothing" })["nothing"]).toBe(nil)
	end)

	it("AC4: gates and learned inputs are kept; prune drops only old rows", function()
		local db = opened("gates")
		t.expect(resultsdb.gatePassed(db, "k1")).toBe(nil)
		resultsdb.recordGate(db, "k1", "full", "pickman,z-nile", 1000)
		t.expect(resultsdb.gatePassed(db, "k1")).toBe(1000)
		resultsdb.learn(db, "pickman", "tests/unit/Maze.spec.luau", "pickman/tests/fixtures/data/", 1000)
		resultsdb.learn(db, "pickman", "tests/unit/Maze.spec.luau", "pickman/tests/fixtures/data/", 1001) -- once only
		resultsdb.learn(db, "z-nile", "tests/a.spec.luau", "z-nile/templates/raft/check.sh", 1000)
		local l = resultsdb.learned(db)
		t.expect(l["pickman"]["tests/unit/Maze.spec.luau"]).toEqual({ "pickman/tests/fixtures/data/" })
		t.expect(l["z-nile"]["tests/a.spec.luau"]).toEqual({ "z-nile/templates/raft/check.sh" })
		resultsdb.record(db, "old", "z-nile", "tests/old.spec.luau", A, {}, nil, 1, 1000)
		resultsdb.record(db, "new", "z-nile", "tests/new.spec.luau", A, {}, nil, 1, 1000 + 29 * 86400)
		resultsdb.prune(db, 1000 + 31 * 86400)
		local rows = resultsdb.rows(db, { "old", "new" })
		t.expect(rows["old"]).toBe(nil)
		t.expect(rows["new"] ~= nil).toBe(true)
		t.expect(resultsdb.gatePassed(db, "k1")).toBe(nil)
		-- learned inputs are never pruned: they describe the code, not a run
		t.expect(resultsdb.learned(db)["pickman"] ~= nil).toBe(true)
	end)

	it("AC4: open answers nil with a reason: a newer schema, an unwritable folder, no sqlite3", function()
		-- a db whose schema is not this version
		local path = fresh("schema")
		local made = process.exec("sqlite3", {
			path,
			"CREATE TABLE meta(k TEXT PRIMARY KEY, v TEXT NOT NULL); INSERT INTO meta VALUES('schema','2');",
		})
		t.expect(made.ok).toBe(true)
		local db, err = resultsdb.open(path)
		t.expect(db).toBe(nil)
		t.expect(string.find(string.lower(err or ""), "schema", 1, true) ~= nil).toBe(true)
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
	end)
end)
