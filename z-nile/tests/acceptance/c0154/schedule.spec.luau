--!strict
-- c0154: the spec runner schedules files slowest first from the durations it recorded, and reports as each file finishes.
-- The pure rules (z-nile/tests/lib/schedule.luau) are checked on fixed inputs, the gain on the 177 durations of a real
-- z-nile run (2026-10-25: path order 213.5 s, slowest first 162.6 s, on 8 lanes), and the runner itself on a copy under
-- .cache/c0154-runner. The runner cases never compare measured times: the record they schedule by is written by hand,
-- and a file that must hold its lane holds it for 3 s, far above a loaded machine's start-up jitter (design review 001
-- F2). Which files start first is read from each fixture spec's own start time.
local fs = require("@lune/fs")
local process = require("@lune/process")
local schedule = require("@tests/lib/schedule")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local here = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local base = `{here}/.cache/c0154-runner`
local home = `{base}/z-nile`
local RECORD = `{home}/.cache/spec-durations.tsv`
local SPANS = `{home}/.cache/spans`
local R = "req" .. "uire" -- keeps literal require text out of this file (the graph scanner)
local DT = "datetime"

local function write(rel: string, text: string)
	local path = `{base}/{rel}`
	fs.writeDir(string.match(path, "^(.*)/[^/]+$") :: string)
	fs.writeFile(path, text)
end
local function copy(rel: string)
	fs.writeDir(string.match(`{base}/{rel}`, "^(.*)/[^/]+$") :: string)
	t.expect(process.exec("cp", { "-R", `{root}/{rel}`, `{base}/{rel}` }).ok).toBe(true)
end
-- a spec that records when its case starts and ends in .cache/spans/<name>, holding its lane `secs` seconds, or
-- none when .cache/fast exists (the in-process runs, whose order doesn't depend on time)
local function sleeper(name: string, secs: number, fails: boolean?): string
	return table.concat({
		"--!strict",
		`local fs = {R}("@lune/fs")`,
		`local dt = {R}("@lune/{DT}")`,
		`local task = {R}("@lune/task")`,
		`local t = {R}("@tests/lib/t")`,
		`return t.spec("{name}", function(it)`,
		'\tit("records its span", function()',
		"\t\tlocal s = dt.now().unixTimestampMillis",
		`\t\ttask.wait(if fs.isFile(".cache/fast") then 0 else {secs})`,
		'\t\tfs.writeDir(".cache/spans")',
		`\t\tfs.writeFile(".cache/spans/{name}-" .. s .. "-" .. math.random(1, 1e9), s .. " " .. dt.now().unixTimestampMillis)`,
		`\t\tt.expect({if fails then "1" else "2"}).toBe(2)`,
		"\tend)",
		"end)",
		"",
	}, "\n")
end
local function run(args: { string }, fast: boolean?): (boolean, string)
	if fs.isDir(SPANS) then
		fs.removeDir(SPANS)
	end
	if fast then
		fs.writeFile(`{home}/.cache/fast`, "")
	elseif fs.isFile(`{home}/.cache/fast`) then
		fs.removeFile(`{home}/.cache/fast`)
	end
	local argv = { "run", "tests/run", "--" }
	for _, a in args do
		table.insert(argv, a)
	end
	local r = process.exec("lune", argv, { cwd = home, env = { PICKMAN_JOBS = "" } })
	return r.ok, r.stdout .. r.stderr
end
-- the names of the fixture specs in the order their cases started (one entry per run of a file)
local function starts(): { string }
	local out = {}
	for _, n in fs.readDir(SPANS) do
		local name, at = string.match(n, "^(.-)%-(%d+)%-%d+$")
		table.insert(out, { name = name :: string, at = tonumber(at) :: number })
	end
	table.sort(out, function(x, y)
		return if x.at ~= y.at then x.at < y.at else x.name < y.name
	end)
	local names = {}
	for _, e in out do
		table.insert(names, e.name)
	end
	return names
end
-- the first `k` of starts(), sorted by name (two lanes start two files at once)
local function first(k: number): { string }
	local out = table.move(starts(), 1, k, 1, {})
	table.sort(out)
	return out
end
local function names(files: { string }, order: { number }): { string }
	local out = {}
	for _, i in order do
		table.insert(out, files[i])
	end
	return out
end

-- the 177 durations of a z-nile run on main (2026-10-25, the measurement in c0154's Verification log)
local REAL = require("./durations")

return t.spec("c0154 the runner schedules slowest first", function(it)
	it(
		"orders unrecorded files first, then recorded ones slowest first, ties by path, by position",
		function()
			local d = { ["b.spec"] = 5, ["c.spec"] = 50, ["d.spec"] = 5, ["e.spec"] = 0.5 }
			local files = { "f.spec", "e.spec", "d.spec", "c.spec", "b.spec", "a.spec" }
			t.expect(names(files, schedule.order(files, d))).toEqual({
				"a.spec",
				"f.spec",
				"c.spec",
				"b.spec",
				"d.spec",
				"e.spec",
			})
			-- no record: path order, as before c0154
			t.expect(names({ "b", "a", "c" }, schedule.order({ "b", "a", "c" }, {})))
				.toEqual({ "a", "b", "c" })
			-- twelve recorded files at one duration, given in reverse path order: path order (design review 001 F6)
			local tied: { string } = {}
			local same: schedule.Durations = {}
			for i = 12, 1, -1 do
				local f = string.format("t%02d", i)
				table.insert(tied, f)
				same[f] = 7
			end
			local want = table.clone(tied)
			table.sort(want)
			t.expect(names(tied, schedule.order(tied, same))).toEqual(want)
			-- a file listed twice keeps both positions (design review 001 F1)
			t.expect(schedule.order({ "x", "x" }, { x = 1 })).toEqual({ 1, 2 })
		end
	)

	it(
		"reads and writes the record, drops gone files on a full run, and refuses a malformed or empty one",
		function()
			local text = schedule.render(
				{ ["a.spec"] = 1, ["b.spec"] = 2 },
				{ ["b.spec"] = 3.456, ["c.spec"] = 0.1 }
			)
			t.expect(text).toBe("1.00\ta.spec\n3.46\tb.spec\n0.10\tc.spec\n")
			t.expect(schedule.parse(text)).toEqual({ ["a.spec"] = 1, ["b.spec"] = 3.46, ["c.spec"] = 0.1 })
			t.expect(
				schedule.render(
					{ ["a.spec"] = 1, ["gone.spec"] = 9 },
					{ ["b.spec"] = 2 },
					{ ["a.spec"] = true }
				)
			).toBe("1.00\ta.spec\n2.00\tb.spec\n")
			t.expect(schedule.parse("1.00\ta.spec\ngarbage\n")).toBe(nil)
			t.expect(schedule.parse("x\ta.spec\n")).toBe(nil)
			t.expect(schedule.parse("")).toBe(nil)
			t.expect(schedule.parse("\n")).toBe(nil)
			t.expect(schedule.parse("\n\n")).toBe(nil)
			t.expect(schedule.parse("1.00\ta.spec\n9.00\ta.spec\n")).toBe(nil)
		end
	)

	it("cuts a real run's wall time on 8 lanes by at least a fifth", function()
		local files = {}
		for path in REAL do
			table.insert(files, path)
		end
		table.sort(files)
		local pathOrder = {}
		for i in files do
			table.insert(pathOrder, i)
		end
		local before = schedule.makespan(files, pathOrder, REAL, 8)
		local after = schedule.makespan(files, schedule.order(files, REAL), REAL, 8)
		t.expect(before > 200).toBe(true)
		t.expect(after <= before * 0.8).toBe(true)
	end)

	it(
		"the runner starts the slowest recorded file first and the unrecorded before it, and records every run",
		function()
			if fs.isDir(base) then
				fs.removeDir(base)
			end
			for _, rel in
				{ "z-nile/tests/run.luau", "z-nile/tests/lib", "z-nile/lib", "z-nile/.luaurc", ".luaurc" }
			do
				copy(rel)
			end
			write("z-nile/.tracker/.gitkeep", "")
			fs.writeDir(`{home}/.cache`)
			for _, n in { "a", "b", "c", "n" } do
				write(`z-nile/tests/{n}.spec.luau`, sleeper(n, 3))
			end
			-- no record: path order on two lanes; a and b hold their lanes, so c and n wait
			local ok1, out1 = run({ "--jobs", "2" })
			t.expect(ok1).toBe(true)
			t.expect(first(2)).toEqual({ "a", "b" })
			local rec = schedule.parse(fs.readFile(RECORD)) :: schedule.Durations
			for _, n in { "a", "b", "c", "n" } do
				t.expect(rec[`tests/{n}.spec.luau`] ~= nil).toBe(true)
			end
			-- a record written by hand (never a measured one): c slowest, a and b fast, n not recorded
			fs.writeFile(
				RECORD,
				"1.00\ttests/a.spec.luau\n1.00\ttests/b.spec.luau\n100.00\ttests/c.spec.luau\n"
			)
			local ok2, out2 = run({ "--jobs", "2" })
			t.expect(ok2).toBe(true)
			t.expect(first(2)).toEqual({ "c", "n" })
			-- the run recorded every file over the hand-written record
			local rec2 = schedule.parse(fs.readFile(RECORD)) :: schedule.Durations
			t.expect(rec2["tests/n.spec.luau"] ~= nil).toBe(true)
			t.expect(rec2["tests/c.spec.luau"] < 100).toBe(true)
			-- --jobs 1 runs in-process in path order and neither reads nor writes the record
			local before = fs.readFile(RECORD)
			local ok3, _ = run({ "--jobs", "1" }, true)
			t.expect(ok3).toBe(true)
			t.expect(starts()).toEqual({ "a", "b", "c", "n" })
			t.expect(fs.readFile(RECORD)).toBe(before)
			t.expect((string.find(out1 .. out2, "FAIL", 1, true))).toBe(nil)
		end
	)

	it("a file listed twice runs twice and both outcomes are reported", function()
		local ok, out = run({ "--jobs", "2", "tests/a.spec.luau", "tests/a.spec.luau" }, true)
		t.expect(ok).toBe(true)
		t.expect((string.find(out, "2 passed, 0 failed, 2 spec files", 1, true)) ~= nil).toBe(true)
		t.expect(#starts()).toBe(2)
	end)

	it("a run naming only a fixture's files leaves the record byte for byte", function()
		-- a record the runner would never write itself (no decimals): a rewrite of any kind changes its bytes (review 002 F4)
		fs.writeFile(RECORD, "1\ttests/a.spec.luau\n")
		local before = fs.readFile(RECORD)
		write("z-nile/.cache/c0154-nested/x.spec.luau", sleeper("x", 0))
		local ok, _ =
			run({ "--jobs", "2", ".cache/c0154-nested/x.spec.luau", ".cache/c0154-nested/x.spec.luau" })
		t.expect(ok).toBe(true)
		t.expect(fs.readFile(RECORD)).toBe(before)
	end)

	it(
		"a full run drops the record's lines for files that are gone; a malformed record runs in path order",
		function()
			fs.writeFile(RECORD, fs.readFile(RECORD) .. "5.00\ttests/gone.spec.luau\n")
			local ok1, _ = run({}, true)
			t.expect(ok1).toBe(true)
			t.expect((string.find(fs.readFile(RECORD), "gone.spec", 1, true))).toBe(nil)
			fs.writeFile(RECORD, "garbage\n")
			local ok2, _ = run({ "--jobs", "2" })
			t.expect(ok2).toBe(true)
			t.expect(first(2)).toEqual({ "a", "b" })
			t.expect(schedule.parse(fs.readFile(RECORD)) ~= nil).toBe(true)
		end
	)

	it("reports as each file finishes rather than in path order", function()
		for _, n in fs.readDir(`{home}/tests`) do
			if string.match(n, "%.spec%.luau$") then
				fs.removeFile(`{home}/tests/{n}`)
			end
		end
		-- f1 comes first by path but is recorded fast and holds its lane; f2 is recorded slow (starts first), ends at once
		write("z-nile/tests/f1.spec.luau", sleeper("f1", 3, true))
		write("z-nile/tests/f2.spec.luau", sleeper("f2", 0, true))
		fs.writeFile(RECORD, "1.00\ttests/f1.spec.luau\n100.00\ttests/f2.spec.luau\n")
		local ok, out = run({ "--jobs", "2" })
		t.expect(ok).toBe(false)
		local i1 = string.find(out, "FAIL tests/f1.spec.luau", 1, true)
		local i2 = string.find(out, "FAIL tests/f2.spec.luau", 1, true)
		t.expect(i1 ~= nil and i2 ~= nil).toBe(true)
		t.expect((i2 :: number) < (i1 :: number)).toBe(true)
		t.expect((string.find(out, "0 passed, 2 failed, 2 spec files", 1, true)) ~= nil).toBe(true)
	end)
end)
