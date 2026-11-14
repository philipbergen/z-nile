--!strict
-- c0165 AC6: with PICKMAN_RESULTS set, the runner writes every file's cases and results (in process and in concurrent
-- workers), a worker that dies marks its file not loaded, and the runner's printed output and exit code are exactly
-- what they are without it. On a copy of the runner under .cache/c0165-results (as tooling/run-record-merge does).
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local here = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local base = `{here}/.cache/c0165-results`
local home = `{base}/z-nile`
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
local function specText(name: string, body: { string }): string
	local lines = { "--!strict", `local t = {R}("@tests/lib/t")`, `return t.spec("{name}", function(it)` }
	for _, l in body do
		table.insert(lines, l)
	end
	table.insert(lines, "end)")
	return table.concat(lines, "\n") .. "\n"
end

local function setup()
	if fs.isDir(base) then
		fs.removeDir(base)
	end
	for _, rel in { "z-nile/tests/run.luau", "z-nile/tests/lib", "z-nile/lib", "z-nile/.luaurc", ".luaurc" } do
		copy(rel)
	end
	write("z-nile/.tracker/.gitkeep", "")
	write(
		"z-nile/tests/a.spec.luau",
		specText("a", {
			'\tit("first", function() t.expect(1).toBe(1) end)',
			'\tit("second", function() t.expect(2).toBe(2) end)',
		})
	)
	write(
		"z-nile/tests/b.spec.luau",
		specText("b", {
			'\tit("passes", function() t.expect(1).toBe(1) end)',
			'\tit("fails", function() t.expect(1).toBe(2) end)',
		})
	)
	-- loads, then kills its own process before any case runs: in a worker, nothing reports
	write(
		"z-nile/tests/c.spec.luau",
		"--!strict\nlocal process = " .. R .. '("@lune/process")\nprocess.exit(3)\nreturn nil\n'
	)
	write("z-nile/tests/d.spec.luau", "--!strict\nreturn 42\n") -- not a spec: fails to load
	fs.writeDir(`{home}/.cache`)
end

local function run(args: { string }, results: string?): (number, string)
	local argv = { "run", "tests/run", "--" }
	for _, a in args do
		table.insert(argv, a)
	end
	local env: { [string]: string } = { PICKMAN_JOBS = "" }
	if results then
		env.PICKMAN_RESULTS = results
	end
	local r = process.exec("lune", argv, { cwd = home, env = env })
	return r.code, r.stdout .. r.stderr
end
-- the run's report without its timings (the slowest: line holds measured seconds), normalized for finish order
local function stable(out: string): string
	local keep = {}
	for line in string.gmatch(out, "[^\n]+") do
		if string.sub(line, 1, 8) ~= "slowest:" then
			table.insert(keep, line)
		end
	end
	table.sort(keep)
	return table.concat(keep, "\n")
end
type FileResult = {
	file: string,
	loaded: boolean,
	cases: { { name: string, ok: boolean } },
	detail: string,
	seconds: number,
}
local function byFile(path: string): { [string]: FileResult }
	local doc = serde.decode("json", fs.readFile(path)) :: any
	local out: { [string]: FileResult } = {}
	for _, f in doc.files do
		out[f.file] = f
	end
	return out
end

return t.spec("c0165 runner results", function(it)
	it(
		"AC6: concurrent workers: every file's cases, a dead worker not loaded, output and exit code unchanged",
		function()
			setup()
			local files =
				{ "tests/a.spec.luau", "tests/b.spec.luau", "tests/c.spec.luau", "tests/d.spec.luau" }
			local args = { "--jobs", "2", table.unpack(files) }
			local plainCode, plainOut = run(args, nil)
			local path = `{home}/.cache/spec-results-test.json`
			local code, out = run(args, path)
			t.expect(code).toBe(plainCode)
			t.expect(code ~= 0).toBe(true)
			t.expect(stable(out)).toBe(stable(plainOut))
			local r = byFile(path)
			-- the run reports its jail (the orchestrator records only the host's strongest); a nested run inherits this run's
			local doc = serde.decode("json", fs.readFile(path)) :: any
			t.expect(doc.jail).toBe(process.env.PICKMAN_TEST_JAIL or "")
			t.expect(r["tests/a.spec.luau"].detail).toBe("")
			t.expect(string.find(r["tests/b.spec.luau"].detail, "fails", 1, true) ~= nil).toBe(true)
			t.expect(r["tests/a.spec.luau"].loaded).toBe(true)
			t.expect(r["tests/a.spec.luau"].cases)
				.toEqual({ { name = "first", ok = true }, { name = "second", ok = true } })
			t.expect(r["tests/b.spec.luau"].cases)
				.toEqual({ { name = "passes", ok = true }, { name = "fails", ok = false } })
			t.expect(r["tests/c.spec.luau"].loaded).toBe(false)
			t.expect(r["tests/d.spec.luau"].loaded).toBe(false)
			t.expect(type(r["tests/a.spec.luau"].seconds)).toBe("number")
			-- the workers' part files are merged and gone
			for _, name in fs.readDir(`{home}/.cache`) do
				t.expect(string.find(name, "spec-results-test.json.", 1, true) == nil).toBe(true)
			end
		end
	)

	it("AC6: in process (one job): the same record, and output unchanged", function()
		setup()
		local args = { "--jobs", "1", "tests/a.spec.luau", "tests/b.spec.luau", "tests/d.spec.luau" }
		local plainCode, plainOut = run(args, nil)
		local path = `{home}/.cache/spec-results-one.json`
		local code, out = run(args, path)
		t.expect(code).toBe(plainCode)
		t.expect(stable(out)).toBe(stable(plainOut))
		local r = byFile(path)
		t.expect(r["tests/a.spec.luau"].cases)
			.toEqual({ { name = "first", ok = true }, { name = "second", ok = true } })
		t.expect(r["tests/b.spec.luau"].cases[2]).toEqual({ name = "fails", ok = false })
		t.expect(r["tests/d.spec.luau"].loaded).toBe(false)
	end)

	it(
		"AC6: a passing run exits 0 and records every file; a path outside the home's .cache is never written",
		function()
			setup()
			local path = `{home}/.cache/spec-results-ok.json`
			local code, _ = run({ "--jobs", "2", "tests/a.spec.luau" }, path)
			t.expect(code).toBe(0)
			t.expect(byFile(path)["tests/a.spec.luau"].loaded).toBe(true)
			local outside = `{base}/outside.json`
			local code2, _ = run({ "--jobs", "1", "tests/a.spec.luau" }, outside)
			t.expect(code2).toBe(0)
			t.expect(fs.isFile(outside)).toBe(false)
		end
	)
end)
