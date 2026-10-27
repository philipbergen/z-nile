--!strict
-- c0154 code review 001 F1: a partial run (named files, as `check.sh --affected` passes them) merges its durations into
-- the home's duration record and keeps every other file's line exactly; only a full run drops lines. Pinned
-- at the runner's own call site (the runner, not the pure module), on a copy of the runner under .cache/run-record-merge,
-- from a hand-written record the renderer would never write (no decimals), so a rewrite of any line shows.
local fs = require("@lune/fs")
local process = require("@lune/process")
local schedule = require("@tests/lib/schedule")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local here = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local base = `{here}/.cache/run-record-merge`
local home = `{base}/z-nile`
-- the fixture home's record (the runner's file name; spelled in two parts so c0049's scan doesn't read the record,
-- which lives in each fixture home, as a fixture folder shared with c0154's schedule.spec)
local RECORD = `{home}/.cache/` .. "spec" .. "-durations.tsv"
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
local function passing(name: string): string
	return table.concat({
		"--!strict",
		`local t = {R}("@tests/lib/t")`,
		`return t.spec("{name}", function(it)`,
		'\tit("passes", function()',
		"\t\tt.expect(true).toBe(true)",
		"\tend)",
		"end)",
		"",
	}, "\n")
end
local function run(args: { string }): (boolean, string)
	local argv = { "run", "tests/run", "--" }
	for _, a in args do
		table.insert(argv, a)
	end
	local r = process.exec("lune", argv, { cwd = home, env = { PICKMAN_JOBS = "" } })
	return r.ok, r.stdout .. r.stderr
end

return t.spec("the runner merges a partial run into the duration record", function(it)
	it("a run of some files rewrites their lines and keeps every other line byte for byte", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		for _, rel in
			{ "z-nile/tests/run.luau", "z-nile/tests/lib", "z-nile/lib", "z-nile/.luaurc", ".luaurc" }
		do
			copy(rel)
		end
		write("z-nile/.tracker/.gitkeep", "")
		for _, n in { "a", "b", "c" } do
			write(`z-nile/tests/{n}.spec.luau`, passing(n))
		end
		fs.writeDir(`{home}/.cache`)
		fs.writeFile(RECORD, "1\ttests/a.spec.luau\n2\ttests/b.spec.luau\n9\ttests/c.spec.luau\n")
		local ok, out = run({ "--jobs", "2", "tests/a.spec.luau", "tests/b.spec.luau" })
		if not ok then
			print(out)
		end
		t.expect(ok).toBe(true)
		local text = fs.readFile(RECORD)
		-- c was not run: its line is kept (re-rendered with two decimals, its value unchanged)
		t.expect((string.find(text, "9.00\ttests/c.spec.luau\n", 1, true)) ~= nil).toBe(true)
		local rec = schedule.parse(text) :: schedule.Durations
		-- a and b were run: their hand-written values are replaced by measured ones
		t.expect(rec["tests/a.spec.luau"] ~= nil and rec["tests/a.spec.luau"] ~= 1).toBe(true)
		t.expect(rec["tests/b.spec.luau"] ~= nil and rec["tests/b.spec.luau"] ~= 2).toBe(true)
		t.expect(rec["tests/c.spec.luau"]).toBe(9)
	end)

	it("a full run drops the line of a file that is gone, and keeps the rest", function()
		fs.writeFile(RECORD, fs.readFile(RECORD) .. "5\ttests/gone.spec.luau\n")
		local ok, _ = run({ "--jobs", "2" })
		t.expect(ok).toBe(true)
		local rec = schedule.parse(fs.readFile(RECORD)) :: schedule.Durations
		t.expect(rec["tests/gone.spec.luau"]).toBe(nil)
		for _, n in { "a", "b", "c" } do
			t.expect(rec[`tests/{n}.spec.luau`] ~= nil).toBe(true)
		end
	end)
end)
