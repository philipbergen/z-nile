--!strict
-- c0230 AC2: the coordinator reports the spec files over the per-file budget (`--budget`, default 60 s wall and 5 s cpu)
-- before its summary, from each worker's own seconds and the CPU its measurer saw (the worker and every process it waited
-- for). It reports only, and no nested run inherits the limits. Fixture spec files are written under .cache/c0230-budget
-- and run through the real runner as child processes, on worker lanes of their own (or none). Nothing here burns CPU
-- (lesson zz-test/specs-never-burn-real-resources): every perl of a nested run gets a stand-in `times` through PERL5OPT
-- (a CORE::GLOBAL override in a module under the fixture folder), so the measurer's number is exact through the real
-- path; the real count of a grandchild's CPU is the one-time proof proof-cpu.luau, which check.sh runs before `./zn done`.
local budget = require("@tests/lib/budget")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local base = `{root}/.cache/c0230-budget`
local rel = ".cache/c0230-budget"
local LESSON = "zz-test/specs-never-burn-real-resources"
-- own user 0.25 and system 0.5, children's user 3 and system 4.125: a measurer that sums the children prints 7.125
local STAND_IN = "BEGIN { *CORE::GLOBAL::times = sub () { (0.25, 0.5, 3, 4.125) } } "

type Result = { code: number, stdout: string, stderr: string }

local function reset()
	if fs.isDir(base) then
		fs.removeDir(base)
	end
	fs.writeDir(`{base}/lanes`)
	for n = 1, 8 do
		fs.writeFile(`{base}/lanes/{n}`, "")
	end
	fs.writeDir(`{base}/perl`)
	fs.writeFile(`{base}/perl/ZnFakeTimes.pm`, STAND_IN .. "1;\n")
end

local function fixture(name: string, body: string): string
	fs.writeFile(
		`{base}/{name}.spec.luau`,
		'return { name = "fixture", cases = { { name = "case", fn = function() ' .. body .. " end } } }"
	)
	return `{rel}/{name}.spec.luau`
end

local PASS = ""
-- a fifth of a second of wall time and no CPU: over a 0.1 s wall budget on any machine
local NAP = 'require("@lune/process").exec("sleep", { "0.2" })'
local MARK = `require("@lune/fs").writeFile("{base}/ran", "x")`
-- a spec that runs a concurrent nested run of two no-op fixtures and keeps its stdout
local NESTED =
	`local r = require("@lune/process").exec("lune", \{ "run", "tests/run", "--", "{rel}/n1.spec.luau", "{rel}/n2.spec.luau" }, \{ cwd = "{root}", env = \{ PICKMAN_JOBS = "2" } }); require("@lune/fs").writeFile("{base}/nested.out", r.stdout)`

local function run(args: { string }, env: { [string]: string }?): Result
	local full = { "run", "tests/run", "--" }
	for _, a in args do
		table.insert(full, a)
	end
	local merged: { [string]: string } = { PICKMAN_JOBS = "2", PICKMAN_WORKER_LANES = `{base}/lanes` }
	if env then
		for k, v in env do
			merged[k] = v
		end
	end
	local r = process.exec("lune", full, { cwd = root, env = merged })
	return { code = r.code, stdout = r.stdout, stderr = r.stderr }
end

local FAKE = { PERL5OPT = `-I{base}/perl -MZnFakeTimes` }

local function lines(s: string): { string }
	local out = {}
	for line in string.gmatch(s, "[^\n]+") do
		table.insert(out, line)
	end
	return out
end

local function indexOf(list: { string }, prefix: string): number?
	for i, l in list do
		if string.sub(l, 1, #prefix) == prefix then
			return i
		end
	end
	return nil
end

local function escape(s: string): string
	return (string.gsub(s, "%p", "%%%0"))
end

-- the report block: its header, its file lines, and where it sits (after slowest:, and after c0178's fixtures: line
-- when that prints, right before the summary)
local function block(r: Result): { string }
	local all = lines(r.stdout)
	local header = indexOf(all, "over budget: ")
	if header == nil then
		error(`no over budget line in:\n{r.stdout}`)
	end
	local slowest = indexOf(all, "slowest: ")
	t.expect(slowest ~= nil and (slowest :: number) < (header :: number)).toBe(true)
	local out = { all[header :: number] }
	local i = (header :: number) + 1
	while all[i] ~= nil and string.sub(all[i], 1, 2) == "  " do
		table.insert(out, all[i])
		i += 1
	end
	t.expect(string.match(all[i] or "", "^%d+ passed, %d+ failed, %d+ spec files$") ~= nil).toBe(true)
	t.expect(all[i + 1]).toBe(nil)
	return out
end

-- the line of `file` in a block, or an error naming the block
local function lineOf(b: { string }, file: string): string
	for i = 2, #b do
		if string.sub(b[i], 1, #file + 3) == `  {file} ` then
			return b[i]
		end
	end
	error(`no line for {file} in:\n{table.concat(b, "\n")}`)
end

return t.spec("c0230 runner budget report", function(it)
	it("AC2: the measurer prints its children's cpu last and exits with the command's status", function()
		local r = process.exec("perl", { "-e", STAND_IN .. budget.MEASURE, "sh", "-c", "echo out; exit 3" })
		t.expect(r.stdout).toBe("out\nzn-spec-cpu 7.125\n")
		t.expect(r.code).toBe(3)
		local k = process.exec("perl", { "-e", STAND_IN .. budget.MEASURE, "sh", "-c", "kill -TERM $$" })
		t.expect(k.stdout).toBe("zn-spec-cpu 7.125\n")
		t.expect(k.code).toBe(143)
		local m = process.exec("perl", { "-e", STAND_IN .. budget.MEASURE, `{base}-no-such-command` })
		t.expect(m.code).toBe(127)
	end)

	it("AC2: the report shows the measurer's number as each file's cpu, on lanes and without", function()
		for _, lanes in { `{base}/lanes`, "" } do
			reset()
			local a = fixture("a", NAP)
			local c = fixture("c", NAP)
			local env = table.clone(FAKE)
			env.PICKMAN_WORKER_LANES = lanes
			local r = run({ "--budget", "0.1:1000", a, c }, env)
			t.expect(r.code).toBe(0)
			local b = block(r)
			t.expect(b[1]).toBe(`over budget: 2 spec files over 0.1 s wall or 1000 s cpu (lesson {LESSON})`)
			t.expect(#b).toBe(3)
			for _, f in { a, c } do
				t.expect(
					string.match(lineOf(b, f), "^  " .. escape(f) .. " %d+%.%d s wall, 7%.1 s cpu$") ~= nil
				)
					.toBe(true)
			end
			t.expect((string.find(r.stdout, "zn-spec-cpu", 1, true))).toBe(nil)
		end
	end)

	it("AC2: files over the cpu limit alone are listed, and none at a limit above their cpu", function()
		reset()
		local a = fixture("a", PASS)
		local c = fixture("c", PASS)
		local over = run({ "--budget", "1000:7", a, c }, FAKE)
		t.expect(over.code).toBe(0)
		local b = block(over)
		t.expect(b[1]).toBe(`over budget: 2 spec files over 1000 s wall or 7 s cpu (lesson {LESSON})`)
		t.expect(string.match(lineOf(b, a), " s wall, 7%.1 s cpu$") ~= nil).toBe(true)
		t.expect(string.match(lineOf(b, c), " s wall, 7%.1 s cpu$") ~= nil).toBe(true)
		local under = run({ "--budget", "1000:8", a, c }, FAKE)
		t.expect(under.code).toBe(0)
		t.expect((string.find(under.stdout, "over budget", 1, true))).toBe(nil)
	end)

	it("AC2: over budget never changes the outcome: a failing file still fails the run", function()
		reset()
		local bad = fixture("bad", NAP .. '; error("boom")')
		local ok = fixture("ok", NAP)
		local r = run({ "--budget", "0.1:1000", bad, ok })
		t.expect(r.code).toBe(1)
		t.expect(#block(r)).toBe(3)
		t.expect(string.find(r.stdout, "1 passed, 1 failed, 2 spec files", 1, true) ~= nil).toBe(true)
	end)

	it("AC2: nothing over budget prints no report and the output is as before", function()
		reset()
		local a = fixture("a", PASS)
		local c = fixture("c", PASS)
		local r = run({ a, c })
		t.expect(r.code).toBe(0)
		t.expect((string.find(r.stdout, "over budget", 1, true))).toBe(nil)
		t.expect((string.find(r.stdout, "zn-spec-cpu", 1, true))).toBe(nil)
		local all = lines(r.stdout)
		t.expect(#all).toBe(4)
		t.expect(string.sub(all[3], 1, 9)).toBe("slowest: ")
		t.expect(all[4]).toBe("2 passed, 0 failed, 2 spec files")
	end)

	it("AC2: a single file runs in-process and prints no report", function()
		reset()
		local a = fixture("a", NAP)
		local r = run({ "--budget", "0.1:0.000001", a })
		t.expect(r.code).toBe(0)
		t.expect((string.find(r.stdout, "over budget", 1, true))).toBe(nil)
	end)

	it("AC2: a run's budget never reaches the runs its specs start, concurrent or in-process", function()
		for _, concurrent in { true, false } do
			reset()
			fixture("n1", PASS)
			fixture("n2", PASS)
			local outer = fixture("outer", NESTED)
			local args = { "--budget", "0.001:0.001", outer }
			if concurrent then
				table.insert(args, fixture("noop", PASS))
			end
			local r = run(args)
			t.expect(r.code).toBe(0)
			local nested = fs.readFile(`{base}/nested.out`)
			t.expect((string.find(nested, "over budget", 1, true))).toBe(nil)
			t.expect(string.match(nested, "\n2 passed, 0 failed, 2 spec files\n$") ~= nil).toBe(true)
			if concurrent then
				t.expect(string.find(block(r)[1], "over 0.001 s wall or 0.001 s cpu", 1, true) ~= nil)
					.toBe(true)
			else
				t.expect((string.find(r.stdout, "over budget", 1, true))).toBe(nil)
			end
		end
	end)

	it("AC2: a malformed or missing --budget value exits 2 before any spec runs", function()
		for _, v in { "5", "0:5", "abc", "" } do
			reset()
			local m = fixture("mark", MARK)
			local c = fixture("c", PASS)
			local r = run({ "--budget", v, m, c })
			t.expect(r.code).toBe(2)
			local want = `--budget must be <wall seconds>:<cpu seconds>, each a positive number (got "{v}")`
			t.expect(string.find(r.stderr, want, 1, true) ~= nil).toBe(true)
			t.expect(fs.isFile(`{base}/ran`)).toBe(false)
		end
		reset()
		local m = fixture("mark", MARK)
		local r = run({ m, "--budget" })
		t.expect(r.code).toBe(2)
		t.expect(fs.isFile(`{base}/ran`)).toBe(false)
	end)
end)
