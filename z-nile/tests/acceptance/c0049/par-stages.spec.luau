--!strict
-- c0470: scripts/lib/par.sh runs gate stages concurrently with buffered, ordered output.
-- Each case drives the library through `bash -c` under /bin/bash (macOS ships bash 3.2, so the
-- library must not need bash 4 features). Concurrency is proved by rendezvous on marker files.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local function trim(s: string): string
	return (string.gsub(s, "%s+$", ""))
end
local root = trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)
-- c0120 override: fixtures live under the spec's home's .cache (the jail refuses the checkout top's)
local here = trim(process.exec("pwd", { "-P" }).stdout)
local base = `{here}/.cache/c0470-par`

local function reset()
	if fs.isDir(base) then
		fs.removeDir(base)
	end
	fs.writeDir(base)
end

-- runs `script` after sourcing the library; returns the result
local function sh(script: string, env: { [string]: string }?)
	local r = process.exec(
		"/bin/bash",
		{ "-c", `set -euo pipefail\nsource z-nile/lib/par.sh\n{script}` },
		{ cwd = root, env = env }
	)
	return { ok = r.ok, code = r.code, out = r.stdout .. r.stderr }
end

local function indexOf(haystack: string, needle: string): number?
	return (string.find(haystack, needle, 1, true))
end

-- a stage that signals `me` and waits for `other` (at most 20 s)
local function meet(me: string, other: string): string
	return `bash -c 'touch {base}/{me}; for i in $(seq 1 400); do [ -e {base}/{other} ] && exit 0; sleep 0.05; done; exit 9'`
end

return t.spec("scripts/lib/par.sh", function(it)
	it("two stages that wait for each other both pass: they run concurrently", function()
		reset()
		local r = sh(`par_start one {meet("one", "two")}\npar_start two {meet("two", "one")}\npar_wait`)
		t.expect(r.ok).toBe(true)
	end)

	it("a stage starts when par_start is called, not when par_wait is", function()
		reset()
		-- polls up to 5 s for the marker before par_wait is ever called: a lazy library never creates it
		local r = sh(
			`par_start mark touch {base}/started\nfor i in $(seq 1 100); do [ -e {base}/started ] && break; sleep 0.05; done\n`
				.. `[ -e {base}/started ] && echo started-before-wait\npar_wait`
		)
		t.expect(indexOf(r.out, "started-before-wait")).toBeTruthy()
	end)

	it("par_wait fails when any stage fails, after printing every stage", function()
		reset()
		local r = sh(
			"par_start ok true\npar_start bad bash -c 'echo broken-output; exit 4'\npar_start ok2 true\npar_wait"
		)
		t.expect(r.ok).toBe(false)
		t.expect(indexOf(r.out, "== ok (")).toBeTruthy()
		t.expect(indexOf(r.out, "== bad (")).toBeTruthy()
		t.expect(indexOf(r.out, "== ok2 (")).toBeTruthy()
		t.expect(indexOf(r.out, "broken-output")).toBeTruthy()
	end)

	it("a failing stage is marked and a passing one is not", function()
		reset()
		local r = sh("par_start good true\npar_start bad false\npar_wait")
		t.expect(indexOf(r.out, "== bad (")).toBeTruthy()
		local header = string.match(r.out, "== bad %(([^\n]*)\n")
		t.expect(header).toBeTruthy()
		t.expect(indexOf(header :: string, "FAILED")).toBeTruthy()
		local goodHeader = string.match(r.out, "== good %(([^\n]*)\n")
		t.expect(goodHeader).toBeTruthy()
		t.expect(indexOf(goodHeader :: string, "FAILED")).toBe(nil)
	end)

	it("stages print in start order, not finish order", function()
		reset()
		local r = sh(
			"par_start first bash -c 'sleep 1; echo late-first'\n"
				.. "par_start second bash -c 'echo early-second'\npar_wait"
		)
		t.expect(r.ok).toBe(true)
		local a, b = indexOf(r.out, "late-first"), indexOf(r.out, "early-second")
		t.expect(a ~= nil and b ~= nil).toBe(true)
		t.expect((a :: number) < (b :: number)).toBe(true)
	end)

	it("a stage's stdout and stderr stay together under its own header", function()
		reset()
		local r =
			sh("par_start a bash -c 'echo a-out; echo a-err >&2'\npar_start b bash -c 'echo b-out'\npar_wait")
		local ha, hb = indexOf(r.out, "== a ("), indexOf(r.out, "== b (")
		local ao, ae, bo = indexOf(r.out, "a-out"), indexOf(r.out, "a-err"), indexOf(r.out, "b-out")
		t.expect(ha ~= nil and hb ~= nil and ao ~= nil and ae ~= nil and bo ~= nil).toBe(true)
		t.expect((ha :: number) < (ao :: number) and (ao :: number) < (hb :: number)).toBe(true)
		t.expect((ha :: number) < (ae :: number) and (ae :: number) < (hb :: number)).toBe(true)
		t.expect((hb :: number) < (bo :: number)).toBe(true)
	end)

	it("every header carries that stage's own elapsed seconds, measured when it ends", function()
		reset()
		-- the slow stage is started first and waited for first; a library that stamps the end time
		-- when `wait` returns would report the quick stage as slow too
		local r = sh("par_start napping sleep 2\npar_start quick true\npar_wait")
		local napping = tonumber(string.match(r.out, "== napping %((%d+%.%d)s") or "")
		local quick = tonumber(string.match(r.out, "== quick %((%d+%.%d)s") or "")
		t.expect(napping ~= nil and quick ~= nil).toBe(true)
		t.expect((napping :: number) >= 2).toBe(true)
		t.expect((quick :: number) < 1.5).toBe(true)
	end)

	it("two gates running at once do not mix their output", function()
		reset()
		local script = `( par_start only-a bash -c 'sleep 0.5; echo output-a'; par_wait ) > {base}/a.out &\n`
			.. `( par_start only-b bash -c 'sleep 0.5; echo output-b'; par_wait ) > {base}/b.out &\nwait`
		local r = sh(script)
		t.expect(r.ok).toBe(true)
		local a, b = fs.readFile(`{base}/a.out`), fs.readFile(`{base}/b.out`)
		t.expect(indexOf(a, "output-a")).toBeTruthy()
		t.expect(indexOf(a, "output-b")).toBe(nil)
		t.expect(indexOf(b, "output-b")).toBeTruthy()
		t.expect(indexOf(b, "output-a")).toBe(nil)
	end)

	it("par_wait is reusable: a second batch is independent of the first", function()
		reset()
		local r =
			sh("par_start one false\npar_wait || true\npar_start two true\npar_wait\necho second-batch-rc=$?")
		t.expect(indexOf(r.out, "second-batch-rc=0")).toBeTruthy()
		local second = string.sub(r.out, indexOf(r.out, "== two (") :: number)
		t.expect(indexOf(second, "== one (")).toBe(nil)
	end)
end)
