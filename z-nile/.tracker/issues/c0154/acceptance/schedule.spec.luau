--!strict
-- c0154: the spec runner schedules files slowest first from the durations it recorded, and reports exactly as before. The pure rules (z-nile/tests/lib/schedule.luau) are checked on fixed inputs, the gain
-- on the 177 durations of a real z-nile run (2026-10-25: path order 213.5 s, slowest first 162.6 s, on 8 lanes), and
-- the runner itself on a copy under .cache/c0154-runner, with spec files that log the order they start in.
local fs = require("@lune/fs")
local process = require("@lune/process")
local schedule = require("@tests/lib/schedule")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local here = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local base = `{here}/.cache/c0154-runner`
local R = "req" .. "uire" -- keeps literal require text out of this file (the graph scanner)

local function write(rel: string, text: string)
	local path = `{base}/{rel}`
	fs.writeDir(string.match(path, "^(.*)/[^/]+$") :: string)
	fs.writeFile(path, text)
end
local function copy(rel: string)
	fs.writeDir(string.match(`{base}/{rel}`, "^(.*)/[^/]+$") :: string)
	t.expect(process.exec("cp", { "-R", `{root}/{rel}`, `{base}/{rel}` }).ok).toBe(true)
end
-- a spec that records when it starts and ends in .cache/spans/<name> ("<start ms> <end ms>"), waiting `secs` between
local DT = "datetime"
local function sleeper(name: string, secs: number): string
	return table.concat({
		"--!strict",
		`local fs = {R}("@lune/fs")`,
		`local dt = {R}("@lune/{DT}")`,
		`local task = {R}("@lune/task")`,
		`local t = {R}("@tests/lib/t")`,
		`return t.spec("{name}", function(it)`,
		'\tit("records its span", function()',
		"\t\tlocal s = dt.now().unixTimestampMillis",
		`\t\ttask.wait({secs})`,
		'\t\tfs.writeDir(".cache/spans")',
		`\t\tfs.writeFile(".cache/spans/{name}", s .. " " .. dt.now().unixTimestampMillis)`,
		"\t\tt.expect(true).toBe(true)",
		"\tend)",
		"end)",
		"",
	}, "\n")
end
local function run(env: { [string]: string }?, args: { string }?): (boolean, string)
	local argv = { "run", "tests/run" }
	if args then
		table.insert(argv, "--")
		for _, a in args do
			table.insert(argv, a)
		end
	end
	local r = process.exec("lune", argv, { cwd = `{base}/z-nile`, env = env })
	return r.ok, r.stdout .. r.stderr
end
local SPANS = `{base}/z-nile/.cache/spans`
local function clearStarted()
	if fs.isDir(SPANS) then
		fs.removeDir(SPANS)
	end
end
local function spans(): { { name: string, from: number, to: number } }
	local out = {}
	for _, n in fs.readDir(SPANS) do
		local a, b = string.match(fs.readFile(`{SPANS}/{n}`), "^(%d+) (%d+)$")
		table.insert(out, { name = n, from = tonumber(a) :: number, to = tonumber(b) :: number })
	end
	table.sort(out, function(x, y)
		return if x.from ~= y.from then x.from < y.from else x.name < y.name
	end)
	return out
end
-- the names of the first `k` files to start, sorted by name (two lanes start two files at once)
local function firstStarted(k: number): { string }
	local out = {}
	for i, sp in spans() do
		if i <= k then
			table.insert(out, sp.name)
		end
	end
	table.sort(out)
	return out
end
-- the 177 durations of a z-nile run on main (2026-10-25, the measurement in c0154's Verification log), in path order
local REAL = require("./durations")

return t.spec("c0154 the runner schedules slowest first", function(it)
	it("orders unrecorded files first, then recorded ones slowest first, ties by path", function()
		local d = { ["b.spec"] = 5, ["c.spec"] = 50, ["d.spec"] = 5, ["e.spec"] = 0.5 }
		local order = schedule.order({ "a.spec", "b.spec", "c.spec", "d.spec", "e.spec", "f.spec" }, d)
		t.expect(order).toEqual({ "a.spec", "f.spec", "c.spec", "b.spec", "d.spec", "e.spec" })
		-- no record: path order, as before c0154
		t.expect(schedule.order({ "b", "a", "c" }, {})).toEqual({ "a", "b", "c" })
	end)

	it("reads and writes the record, and refuses a malformed one whole", function()
		local text = schedule.render(
			{ ["a.spec"] = 1, ["b.spec"] = 2 },
			{ ["b.spec"] = 3.456, ["c.spec"] = 0.1 }
		)
		t.expect(text).toBe("1.00\ta.spec\n3.46\tb.spec\n0.10\tc.spec\n")
		t.expect(schedule.parse(text)).toEqual({ ["a.spec"] = 1, ["b.spec"] = 3.46, ["c.spec"] = 0.1 })
		t.expect(schedule.parse("1.00\ta.spec\ngarbage\n")).toBe(nil)
		t.expect(schedule.parse("x\ta.spec\n")).toBe(nil)
	end)

	it("cuts a real run's wall time on 8 lanes by at least a fifth", function()
		local files = {}
		for path in REAL do
			table.insert(files, path)
		end
		table.sort(files)
		local before = schedule.makespan(files, REAL, 8)
		local after = schedule.makespan(schedule.order(files, REAL), REAL, 8)
		t.expect(before > 200).toBe(true)
		t.expect(after <= before * 0.8).toBe(true)
	end)

	it(
		"the runner starts the slowest recorded file first, records every run, and reports in path order",
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
			write("z-nile/tests/a.spec.luau", sleeper("a", 0.1))
			write("z-nile/tests/b.spec.luau", sleeper("b", 0.1))
			write("z-nile/tests/c.spec.luau", sleeper("c", 0.6))
			-- first run: no record, path order; two lanes (an idle machine of 2 CPUs)
			local ok1, out1 = run({ PICKMAN_JOBS = "" }, { "--jobs", "2" })
			if not ok1 then
				print(out1)
			end
			t.expect(ok1).toBe(true)
			t.expect(firstStarted(2)).toEqual({ "a", "b" })
			local rec =
				schedule.parse(fs.readFile(`{base}/z-nile/.cache/spec-durations.tsv`)) :: schedule.Durations
			t.expect(rec["tests/c.spec.luau"] > rec["tests/a.spec.luau"]).toBe(true)
			t.expect(rec["tests/b.spec.luau"] ~= nil).toBe(true)
			-- second run: the recorded slowest (c) starts first, and a new file with no record before it
			write("z-nile/tests/n.spec.luau", sleeper("n", 0.1))
			clearStarted()
			local ok2, out2 = run(nil, { "--jobs", "1" })
			t.expect(ok2).toBe(true)
			-- --jobs 1 runs in-process in path order (unchanged); with lanes the schedule applies
			t.expect(#spans()).toBe(4)
			t.expect(firstStarted(1)).toEqual({ "a" })
			clearStarted()
			local ok3, out3 = run(nil, { "--jobs", "2" })
			t.expect(ok3).toBe(true)
			t.expect(firstStarted(2)).toEqual({ "c", "n" })
			-- the report is in path order whatever the schedule
			local ia, ib = string.find(out3, "4 passed, 0 failed, 4 spec files", 1, true)
			t.expect(ia ~= nil and ib ~= nil).toBe(true)
			t.expect((string.find(out1 .. out2, "FAIL", 1, true))).toBe(nil)
			-- a run that names a fixture's spec file (a spec testing the runner) records only the home's own tests/ files
			write("z-nile/.cache/c0154-nested/x.spec.luau", sleeper("x", 0.1))
			local ok4, _ = run(
				{ PICKMAN_JOBS = "" },
				{ "--jobs", "2", "tests/a.spec.luau", ".cache/c0154-nested/x.spec.luau" }
			)
			t.expect(ok4).toBe(true)
			local rec4 =
				schedule.parse(fs.readFile(`{base}/z-nile/.cache/spec-durations.tsv`)) :: schedule.Durations
			t.expect(rec4[".cache/c0154-nested/x.spec.luau"]).toBe(nil)
			t.expect(rec4["tests/a.spec.luau"] ~= nil).toBe(true)
		end
	)

	it("a malformed record runs in path order and is replaced by a good one", function()
		write("z-nile/.cache/spec-durations.tsv", "garbage\n")
		clearStarted()
		local ok, _ = run({ PICKMAN_JOBS = "" }, { "--jobs", "2" })
		t.expect(ok).toBe(true)
		t.expect(firstStarted(2)).toEqual({ "a", "b" })
		t.expect(schedule.parse(fs.readFile(`{base}/z-nile/.cache/spec-durations.tsv`)) ~= nil).toBe(true)
	end)

	it("reports in path order whatever order the files ran and finished in", function()
		for _, n in fs.readDir(`{base}/z-nile/tests`) do
			if string.match(n, "%.spec%.luau$") then
				fs.removeFile(`{base}/z-nile/tests/{n}`)
			end
		end
		local function failing(name: string, secs: number): string
			return table.concat({
				"--!strict",
				`local task = {R}("@lune/task")`,
				`local t = {R}("@tests/lib/t")`,
				`return t.spec("{name}", function(it)`,
				'\tit("fails", function()',
				`\t\ttask.wait({secs})`,
				"\t\tt.expect(1).toBe(2)",
				"\tend)",
				"end)",
				"",
			}, "\n")
		end
		-- f1 comes first by path but is recorded fast and runs slow; f2 is recorded slow (starts first) and ends first
		write("z-nile/tests/f1.spec.luau", failing("f1", 1.0))
		write("z-nile/tests/f2.spec.luau", failing("f2", 0))
		write("z-nile/.cache/spec-durations.tsv", "1.00\ttests/f1.spec.luau\n100.00\ttests/f2.spec.luau\n")
		local ok, out = run({ PICKMAN_JOBS = "" }, { "--jobs", "2" })
		t.expect(ok).toBe(false)
		local i1 = string.find(out, "FAIL tests/f1.spec.luau", 1, true)
		local i2 = string.find(out, "FAIL tests/f2.spec.luau", 1, true)
		t.expect(i1 ~= nil and i2 ~= nil).toBe(true)
		t.expect((i1 :: number) < (i2 :: number)).toBe(true)
		t.expect((string.find(out, "0 passed, 2 failed, 2 spec files", 1, true)) ~= nil).toBe(true)
	end)
end)
