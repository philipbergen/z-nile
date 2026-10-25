--!strict
-- c0470: tests/run runs spec files concurrently. Fixtures are written under .cache/c0470-runner and
-- run through the real runner as child processes. Concurrency is proved by rendezvous (two specs that
-- each wait for the other's marker file), never by wall-clock thresholds.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local function trim(s: string): string
	return (string.gsub(s, "%s+$", ""))
end
-- c0120 override: the runner runs from z-nile's home (it refuses the repository root), and fixtures live under the
-- home's .cache (the jail refuses the checkout top's)
local root = trim(process.exec("pwd", { "-P" }).stdout)
local base = `{root}/.cache/c0470-runner`
local rel = ".cache/c0470-runner" -- the runner takes repo-relative paths

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local function reset()
	if fs.isDir(base) then
		fs.removeDir(base)
	end
	fs.writeDir(base)
end

local function fixture(name: string, source: string): string
	fs.writeFile(`{base}/{name}.spec.luau`, source)
	return `{rel}/{name}.spec.luau`
end

-- Fixture source is plain text with @BASE@ / @ME@ / @OTHER@ placeholders (no interpolation).
local function fill(template: string, vars: { [string]: string }): string
	local out = template
	for k, v in vars do
		out = string.gsub(out, "@" .. k .. "@", (string.gsub(v, "%%", "%%%%")))
	end
	return out
end

local function cases(body: string): string
	return 'return { name = "fixture", cases = { { name = "case", fn = function() ' .. body .. " end } } }"
end

local function casesN(n: number, body: string): string
	local list = {}
	for i = 1, n do
		table.insert(list, '{ name = "case' .. i .. '", fn = function() ' .. body .. " end }")
	end
	return 'return { name = "fixture", cases = { ' .. table.concat(list, ", ") .. " } }"
end

local PASS = cases("")

-- waits (polling) for the other fixture's marker; fails after PICKMAN_RV_TIMEOUT seconds
local RENDEZVOUS = [[
local fs = require("@lune/fs")
local process = require("@lune/process")
fs.writeFile("@BASE@/@ME@.ready", "x")
local limit = os.time() + tonumber(process.env.PICKMAN_RV_TIMEOUT or "20")
for _, other in { @OTHERS@ } do
	while not fs.isFile("@BASE@/" .. other .. ".ready") do
		if os.time() > limit then error("no rendezvous with " .. other) end
		process.exec("sleep", { "0.05" })
	end
end]]

-- a fixture that waits for every name in `others` (each of them waits for it in turn)
local function rendezvous(me: string, ...: string): string
	local quoted = {}
	for _, o in { ... } do
		table.insert(quoted, `"{o}"`)
	end
	return cases(fill(RENDEZVOUS, { BASE = base, ME = me, OTHERS = table.concat(quoted, ", ") }))
end

local ONCE = [[
-- mkdir is atomic: whichever run creates the marker first wins, any other run fails
if not require("@lune/process").exec("mkdir", { "@MARKER@" }).ok then error("ran twice") end]]

local SLEEP1 = 'require("@lune/process").exec("sleep", { "0.6" })'

local function run(args: { string }, env: { [string]: string }?): Result
	local full = { "run", "tests/run", "--" }
	for _, a in args do
		table.insert(full, a)
	end
	local merged: { [string]: string } = { PICKMAN_JOBS = "" } -- empty means unset; never inherit the caller's
	if env then
		for k, v in env do
			merged[k] = v
		end
	end
	local r = process.exec("lune", full, { cwd = root, env = merged })
	return { ok = r.ok, code = r.code, stdout = r.stdout, stderr = r.stderr }
end

local function lastLine(s: string): string
	local last = ""
	for line in string.gmatch(s, "[^\n]+") do
		last = line
	end
	return last
end

local function indexOf(haystack: string, needle: string): number?
	return (string.find(haystack, needle, 1, true))
end

return t.spec("tests/run runs spec files concurrently", function(it)
	it("two specs that wait for each other both pass with --jobs 2", function()
		reset()
		local a = fixture("a", rendezvous("a", "b"))
		local b = fixture("b", rendezvous("b", "a"))
		local r = run({ "--jobs", "2", a, b })
		t.expect(r.ok).toBe(true)
		t.expect(lastLine(r.stdout)).toBe("2 passed, 0 failed, 2 spec files")
	end)

	it("--jobs N is a cap: three specs that all wait for each other need exactly 3 lanes", function()
		reset()
		local a = fixture("a", rendezvous("a", "b", "c"))
		local b = fixture("b", rendezvous("b", "a", "c"))
		local c = fixture("c", rendezvous("c", "a", "b"))
		-- 2 lanes: a and b wait for c, which only starts after one of them times out
		local two = run({ "--jobs", "2", a, b, c }, { PICKMAN_RV_TIMEOUT = "1" })
		-- the first of a and b to give up must fail; the other may still see c's marker in time, so
		-- either 1 or 2 passes is legal. An uncapped runner passes all 3.
		t.expect(two.ok).toBe(false)
		local last = lastLine(two.stdout)
		t.expect(last == "1 passed, 2 failed, 3 spec files" or last == "2 passed, 1 failed, 3 spec files")
			.toBe(true)
		reset()
		a = fixture("a", rendezvous("a", "b", "c"))
		b = fixture("b", rendezvous("b", "a", "c"))
		c = fixture("c", rendezvous("c", "a", "b"))
		local three = run({ "--jobs", "3", a, b, c })
		t.expect(three.ok).toBe(true)
		t.expect(lastLine(three.stdout)).toBe("3 passed, 0 failed, 3 spec files")
	end)

	it("--jobs 1 runs them one at a time, so the same rendezvous times out", function()
		reset()
		local a = fixture("a", rendezvous("a", "b"))
		local b = fixture("b", rendezvous("b", "a"))
		local r = run({ "--jobs", "1", a, b }, { PICKMAN_RV_TIMEOUT = "1" })
		t.expect(r.ok).toBe(false)
		t.expect(lastLine(r.stdout)).toBe("1 passed, 1 failed, 2 spec files")
	end)

	it("with no flag the default job count is at least 2", function()
		reset()
		local a = fixture("a", rendezvous("a", "b"))
		local b = fixture("b", rendezvous("b", "a"))
		local r = run({ a, b })
		t.expect(r.ok).toBe(true)
		t.expect(lastLine(r.stdout)).toBe("2 passed, 0 failed, 2 spec files")
	end)

	it("PICKMAN_JOBS=1 forces serial, and --jobs overrides PICKMAN_JOBS", function()
		reset()
		local a = fixture("a", rendezvous("a", "b"))
		local b = fixture("b", rendezvous("b", "a"))
		local serial = run({ a, b }, { PICKMAN_JOBS = "1", PICKMAN_RV_TIMEOUT = "1" })
		t.expect(serial.ok).toBe(false)
		reset()
		a = fixture("a", rendezvous("a", "b"))
		b = fixture("b", rendezvous("b", "a"))
		local over = run({ "--jobs", "2", a, b }, { PICKMAN_JOBS = "1" })
		t.expect(over.ok).toBe(true)
	end)

	it("a bad PICKMAN_JOBS exits 2, an empty one means unset, and --jobs may follow the files", function()
		reset()
		local a = fixture("a", PASS)
		local b = fixture("b", PASS)
		local bad = run({ a, b }, { PICKMAN_JOBS = "lots" })
		t.expect(bad.code).toBe(2)
		t.expect(indexOf(bad.stdout .. bad.stderr, "PICKMAN_JOBS")).toBeTruthy()
		local empty = run({ a, b }, { PICKMAN_JOBS = "" })
		t.expect(empty.ok).toBe(true)
		local after = run({ a, b, "--jobs", "2" })
		t.expect(after.ok).toBe(true)
		t.expect(lastLine(after.stdout)).toBe("2 passed, 0 failed, 2 spec files")
	end)

	it("a bad --jobs value exits 2 and names the flag", function()
		reset()
		local a = fixture("a", PASS)
		for _, bad in { { "--jobs", "0", a }, { "--jobs", "many", a }, { "--jobs" } } do
			local r = run(bad)
			t.expect(r.code).toBe(2)
			t.expect(indexOf(r.stdout .. r.stderr, "--jobs")).toBeTruthy()
		end
	end)

	it("a failing case fails the run, prints its FAIL line, and the other specs still count", function()
		reset()
		local a = fixture("a", casesN(3, ""))
		local b = fixture("b", cases('error("boom-b")'))
		local c = fixture("c", casesN(2, ""))
		local r = run({ "--jobs", "3", a, b, c })
		t.expect(r.ok).toBe(false)
		t.expect(indexOf(r.stdout, `FAIL {b} :: case`)).toBeTruthy()
		t.expect(indexOf(r.stdout, "boom-b")).toBeTruthy()
		t.expect(lastLine(r.stdout)).toBe("5 passed, 1 failed, 3 spec files")
	end)

	it("a spec that cannot load is one failure", function()
		reset()
		local a = fixture("a", PASS)
		local b = fixture("b", 'error("cannot-load-b")')
		local r = run({ "--jobs", "2", a, b })
		t.expect(r.ok).toBe(false)
		t.expect(indexOf(r.stdout, "could not load spec")).toBeTruthy()
		t.expect(lastLine(r.stdout)).toBe("1 passed, 1 failed, 2 spec files")
	end)

	it("a worker that dies without a summary is one failure naming the file and exit code", function()
		reset()
		local a = fixture("a", PASS)
		local b = fixture("b", cases('require("@lune/process").exit(3)'))
		local r = run({ "--jobs", "2", a, b })
		t.expect(r.ok).toBe(false)
		t.expect(indexOf(r.stdout, `FAIL {b}: worker exited with code 3`)).toBeTruthy()
		t.expect(lastLine(r.stdout)).toBe("1 passed, 1 failed, 2 spec files")
	end)

	it("a worker that exits 0 without a summary, or exits non-zero after one, is one failure", function()
		reset()
		local a = fixture("a", casesN(2, ""))
		local silent = fixture("b-silent", cases('require("@lune/process").exit(0)'))
		local liar = fixture(
			"c-liar",
			cases('print("1 passed, 0 failed, 1 spec files"); require("@lune/process").exit(5)')
		)
		local r = run({ "--jobs", "3", a, silent, liar })
		t.expect(r.ok).toBe(false)
		t.expect(indexOf(r.stdout, `FAIL {silent}: worker exited with code 0`)).toBeTruthy()
		t.expect(indexOf(r.stdout, `FAIL {liar}: worker exited with code 5`)).toBeTruthy()
		t.expect(lastLine(r.stdout)).toBe("2 passed, 2 failed, 3 spec files")
	end)

	it("failures print in sorted file order, not in the order the workers finish", function()
		reset()
		local slow = fixture("a-slow", cases(SLEEP1 .. '; error("late-a")'))
		local fast = fixture("b-fast", cases('error("early-b")'))
		local r = run({ "--jobs", "2", fast, slow })
		local ia, ib = indexOf(r.stdout, "late-a"), indexOf(r.stdout, "early-b")
		t.expect(lastLine(r.stdout)).toBe("0 passed, 2 failed, 2 spec files")
		t.expect(ia ~= nil and ib ~= nil).toBe(true)
		t.expect((ia :: number) < (ib :: number)).toBe(true)
	end)

	it("every listed spec runs exactly once, with fewer jobs than specs", function()
		reset()
		local files = {}
		for i = 1, 6 do
			local marker = `{base}/ran-{i}`
			local body = fill(ONCE, { MARKER = marker })
			table.insert(files, fixture(`s{i}`, cases(body)))
		end
		local args = { "--jobs", "2" }
		for _, f in files do
			table.insert(args, f)
		end
		local r = run(args)
		t.expect(r.ok).toBe(true)
		t.expect(lastLine(r.stdout)).toBe("6 passed, 0 failed, 6 spec files")
		-- the output shape: one slowest: line naming at most 3 specs, and exactly one summary line
		local lines = {}
		for line in string.gmatch(r.stdout, "[^\n]+") do
			table.insert(lines, line)
		end
		t.expect(#lines).toBe(2)
		local entries = 0
		for _ in string.gmatch(lines[1], "%.spec%.luau %d+%.%ds") do
			entries += 1
		end
		t.expect(string.sub(lines[1], 1, 9)).toBe("slowest: ")
		t.expect(entries).toBe(3)
		for i = 1, 6 do
			t.expect(fs.isDir(`{base}/ran-{i}`)).toBe(true)
		end
	end)

	it("prints a 'slowest:' line, slowest first, before the summary", function()
		reset()
		local slow = fixture("slow", cases(SLEEP1))
		local fast = fixture("fast", PASS)
		local r = run({ "--jobs", "2", fast, slow })
		t.expect(r.ok).toBe(true)
		local line = string.match(r.stdout, "\nslowest: ([^\n]*)\n")
			or string.match(r.stdout, "^slowest: ([^\n]*)\n")
		t.expect(line).toBeTruthy()
		local slowAt, fastAt =
			indexOf(line :: string, "slow.spec.luau"), indexOf(line :: string, "fast.spec.luau")
		t.expect(slowAt ~= nil and fastAt ~= nil).toBe(true)
		t.expect((slowAt :: number) < (fastAt :: number)).toBe(true)
		t.expect(string.match(lastLine(r.stdout), "^%d+ passed, %d+ failed, %d+ spec files$")).toBeTruthy()
	end)

	it("a single spec runs in-process: same summary, no 'slowest:' line", function()
		reset()
		local a = fixture("a", PASS)
		local r = run({ a })
		t.expect(r.ok).toBe(true)
		t.expect(r.stdout).toBe("1 passed, 0 failed, 1 spec files\n")
	end)
end)
