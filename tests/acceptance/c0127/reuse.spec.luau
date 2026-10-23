--!strict
-- c0127 AC2: a lock's recorded pid holds the lock only while it is alive and it is not a reused pid, one whose start
-- id (fence.startOf: the kernel's own record of when the process started, never the clock) differs from the id
-- recorded with it: a worker's id is the content of its own `pid-<n>` record, the top process's is in `start-<pid>`
-- beside its `pid` record, and the takeover's owner keeps pid and id together in `owner`. A record with no id (from
-- an older runner) or whose id can't be read now still holds. Ids are read only for live pids, and every run
-- records ids for itself, its workers and a waiter that takes over. A throwaway repository holds a copy of the
-- runner (as c0058's lock.spec does); its runs keep the outer guards and clear only the marker. Some cases put a
-- stand-in perl first on PATH for one run: it passes every call to the real perl, and either logs the pids the
-- reader is asked about or refuses the reader for one pid only.
local fence = require("@tests/lib/fence")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local task = require("@lune/task")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local base = `{root}/.cache/c0127-reuse`
local repo = `{base}/real`
local bin = `{base}/bin`
local log = `{base}/asked`
local lock = `{repo}/.cache/tests-run.lock`
local OTHER = "1.0" -- a start id no live process has

local function trim(s: string): string
	return (string.gsub(s, "^%s+", ""):gsub("%s+$", ""))
end

local function must(r: Result, what: string): string
	if not r.ok then
		error(`{what} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return trim(r.stdout)
end

local function has(s: string, needle: string): boolean
	return string.find(s, needle, 1, true) ~= nil
end

local function write(path: string, text: string)
	local parent = string.match(path, "^(.*)/[^/]+$")
	if parent then
		fs.writeDir(`{repo}/{parent}`)
	end
	fs.writeFile(`{repo}/{path}`, text)
end

local function copyTree(rel: string)
	local src = `{root}/{rel}`
	if not fs.isFile(src) and not fs.isDir(src) then
		return
	elseif fs.isDir(src) then
		for _, name in fs.readDir(src) do
			copyTree(`{rel}/{name}`)
		end
	else
		write(rel, fs.readFile(src))
	end
end

-- A stand-in perl first on PATH: it hands every call to the real perl (by its absolute path), except that the
-- reader's exact call (`-e <fence.STARTED> <pid>`) is logged (`refuse` nil) or, for the pid `refuse` only, refused
-- as a refused sysctl or a hidden /proc would refuse it.
local function standIn(refuse: string?)
	local real = trim(process.exec("sh", { "-c", "command -v perl" }).stdout)
	if real == "" then
		error("no perl on PATH")
	end
	local prefix = string.sub(fence.STARTED, 1, 40)
	t.expect(string.find(prefix, "'", 1, true) == nil).toBe(true) -- the prefix goes inside single quotes below
	local act = if refuse then `if [ "$3" = "{refuse}" ]; then exit 1; fi` else `echo "$3" >> '{log}'`
	fs.writeDir(bin)
	fs.writeFile(
		`{bin}/perl`,
		"#!/bin/sh\n"
			.. `if [ "$1" = "-e" ] && [ "$#" -eq 3 ]; then case "$2" in '{prefix}'*) {act} ;; esac; fi\n`
			.. `exec '{real}' "$@"\n`
	)
	must(process.exec("chmod", { "+x", `{bin}/perl` }), "chmod perl")
	if fs.isFile(log) then
		fs.removeFile(log)
	end
end

local function run(probeName: string?, withBin: boolean?, extra: { [string]: string }?): Result
	local path = process.env.PATH or "/usr/bin:/bin"
	local env: { [string]: string } = {
		PICKMAN_TEST_FENCE = "",
		PICKMAN_TEST_LOCK_WAIT = "1",
		PATH = if withBin then `{bin}:{path}` else path,
	}
	if extra then
		for k, v in extra do
			env[k] = v
		end
	end
	return process.exec(
		"lune",
		{ "run", "tests/run", "--", `tests/probe/{probeName or "ok"}.spec.luau` },
		{ cwd = repo, env = env }
	)
end

-- Starts a run in the background; the returned function waits for it and gives its result.
local function start(probeName: string?, extra: { [string]: string }?): () -> Result
	local result: Result? = nil
	task.spawn(function()
		result = run(probeName, false, extra)
	end)
	return function(): Result
		local waited = 0
		while result == nil and waited < 60 do
			task.wait(0.05)
			waited += 0.05
		end
		if result == nil then
			error("the run did not finish")
		end
		return result :: Result
	end
end

-- Waits up to 30 s for `path` to exist.
local function waitFor(path: string): boolean
	local waited = 0
	while not fs.isFile(path) and waited < 30 do
		task.wait(0.05)
		waited += 0.05
	end
	return fs.isFile(path)
end

-- The pid of a process that has certainly exited.
local function deadPid(): string
	return trim(process.exec("sh", { "-c", "echo $$" }).stdout)
end

-- A live process of this spec's own, stopped by the returned function.
local function livePid(): (string, () -> ())
	local pid = trim(process.exec("sh", { "-c", "sleep 30 >/dev/null 2>&1 & echo $!" }).stdout)
	return pid, function()
		process.exec("kill", { pid })
	end
end

local function freshLock()
	if fs.isDir(lock) then
		fs.removeDir(lock)
	end
	if fs.isDir(`{lock}.takeover`) then
		fs.removeDir(`{lock}.takeover`)
	end
	fs.writeDir(lock)
end

local function takenOver(r: Result)
	t.expect({ ok = r.ok, waited = has(r.stderr, "waiting for another test run") }).toEqual({
		ok = true,
		waited = false,
	})
	t.expect(fs.isDir(lock)).toBe(false)
end

local function heldBy(r: Result, pid: string)
	t.expect(r.ok).toBe(false)
	t.expect(has(r.stderr, "gave up after")).toBe(true)
	t.expect(has(r.stderr, pid)).toBe(true)
	t.expect(fs.isDir(lock)).toBe(true)
end

local ready = false
local function setUp()
	if not ready then
		error("setup did not finish: not running this case", 2)
	end
end

-- the probe a held run executes: it says it is running, then waits for the spec to let it end
local HOLD_PROBE = [[--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local task = require("@lune/task")
local here = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
return t.spec("hold", function(it)
	it("probe", function()
		fs.writeFile(`{here}/.cache/c0127-held`, "")
		local waited = 0
		while not fs.isFile(`{here}/.cache/c0127-go`) and waited < 30 do
			task.wait(0.05)
			waited += 0.05
		end
		t.expect(fs.isFile(`{here}/.cache/c0127-go`)).toBe(true)
	end)
end)
]]

local function clearSignals()
	for _, f in { "c0127-held", "c0127-go" } do
		if fs.isFile(`{repo}/.cache/{f}`) then
			fs.removeFile(`{repo}/.cache/{f}`)
		end
	end
end

return t.spec("c0127 a reused pid does not hold the test lock", function(it)
	it("sets up a repository holding a copy of the runner and its guards", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(repo)
		for _, rel in { "tests/run.luau", "tests/lib", "z-nile/lib/ac.sh", "z-nile/lib/fence.sh" } do -- c0114: the guards moved
			copyTree(rel)
		end
		for _, rel in { "z-nile/lib/git-hooks", ".luaurc", "rokit.toml", ".gitignore" } do
			copyTree(rel)
		end
		if fs.isDir(`{repo}/z-nile/lib/git-hooks`) then
			must(process.exec("chmod", { "-R", "+x", `{repo}/z-nile/lib/git-hooks` }), "chmod hooks")
		end
		must(process.exec("git", { "init", "-q", "-b", "main", repo }), "git init")
		-- git below acts only once `repo` is proven to be the repository this spec just created
		local top = process.exec("git", { "rev-parse", "--show-toplevel" }, { cwd = repo })
		local here = must(process.exec("pwd", { "-P" }, { cwd = repo }), "pwd -P")
		if not top.ok or trim(top.stdout) ~= here then
			error(`refusing to run git in {repo}: it is not a fixture repository this spec created`)
		end
		must(process.exec("git", { "add", "-A" }, { cwd = repo }), "git add")
		local commit =
			{ "-c", "user.name=c0127", "-c", "user.email=c0127@example.invalid", "commit", "-qm", "runner" }
		must(process.exec("git", commit, { cwd = repo }), "git commit")
		fs.writeDir(`{repo}/.cache`)
		write(
			"tests/probe/ok.spec.luau",
			'--!strict\nlocal t = require("@tests/lib/t")\nreturn t.spec("ok", function(it)\n'
				.. '\tit("probe", function()\n\t\tt.expect(1).toBe(1)\n\tend)\nend)\n'
		)
		write("tests/probe/hold.spec.luau", HOLD_PROBE)
		ready = true
	end)

	it("a run records the start ids of its top process and of its workers beside their pids", function()
		setUp()
		freshLock()
		fs.removeDir(lock) -- no lock: the run takes it at once
		clearSignals()
		local finish = start("hold")
		t.expect(waitFor(`{repo}/.cache/c0127-held`)).toBe(true)
		-- judged here, outside the run, while it holds the lock: each record's id is the id of the pid it names
		local seen = {}
		for _, name in fs.readDir(lock) do
			local pid = if name == "pid"
				then trim(fs.readFile(`{lock}/pid`))
				else string.match(name, "^pid%-(%d+)$")
			if pid then
				local file = if name == "pid" then `{lock}/start-{pid}` else `{lock}/{name}`
				local recorded = if fs.isFile(file) then trim(fs.readFile(file)) else ""
				local kind = if name == "pid" then "top" else "worker"
				table.insert(seen, `{kind} {recorded ~= "" and recorded == fence.startOf(pid)}`)
			end
		end
		fs.writeFile(`{repo}/.cache/c0127-go`, "")
		local r = finish()
		table.sort(seen)
		t.expect(r.ok).toBe(true)
		t.expect(seen[1]).toBe("top true")
		t.expect(#seen >= 2 and seen[#seen] == "worker true" and table.find(seen, "worker false") == nil)
			.toBe(true)
	end)

	it(
		"a live pid whose recorded start id differs (a reused pid) no longer holds: the lock is taken over",
		function()
			setUp()
			freshLock()
			local pid, stop = livePid()
			fs.writeFile(`{lock}/pid`, deadPid())
			fs.writeFile(`{lock}/pid-{pid}`, OTHER)
			local r = run()
			stop()
			takenOver(r)
		end
	)

	it("the top process's pid is judged by its own start id: a reused one there is taken over", function()
		setUp()
		freshLock()
		local pid, stop = livePid()
		fs.writeFile(`{lock}/pid`, pid)
		fs.writeFile(`{lock}/start-{pid}`, OTHER)
		local r = run()
		stop()
		takenOver(r)
	end)

	it(
		"a live pid whose recorded start id matches still holds: the run waits, then fails naming it",
		function()
			setUp()
			freshLock()
			local pid, stop = livePid()
			fs.writeFile(`{lock}/pid`, deadPid())
			fs.writeFile(`{lock}/pid-{pid}`, fence.startOf(pid) or "unreadable")
			local r = run()
			stop()
			heldBy(r, pid)
		end
	)

	it("a live pid with no recorded start id (a lock from an older runner) still holds", function()
		setUp()
		freshLock()
		local pid, stop = livePid()
		fs.writeFile(`{lock}/pid`, deadPid())
		fs.writeFile(`{lock}/pid-{pid}`, "")
		local r = run()
		stop()
		heldBy(r, pid)
	end)

	it("a live pid whose start id can't be read now still holds, whatever was recorded", function()
		setUp()
		freshLock()
		local pid, stop = livePid()
		fs.writeFile(`{lock}/pid`, deadPid())
		fs.writeFile(`{lock}/pid-{pid}`, OTHER)
		standIn(pid) -- refuses the reader for this pid only
		local r = run(nil, true)
		stop()
		heldBy(r, pid)
	end)

	it(
		"a takeover whose owner file names a reused pid is cleared, so the dead lock behind it is taken over",
		function()
			setUp()
			freshLock()
			fs.writeFile(`{lock}/pid`, deadPid())
			local pid, stop = livePid()
			fs.writeDir(`{lock}.takeover`)
			fs.writeFile(`{lock}.takeover/owner`, `{pid} {OTHER}`)
			fs.writeFile(`{lock}.takeover/pid`, pid)
			local r = run()
			stop()
			t.expect(r.ok).toBe(true)
			t.expect(fs.isDir(`{lock}.takeover`)).toBe(false)
			t.expect(fs.isDir(lock)).toBe(false)
		end
	)

	it(
		"a waiter that takes over records its pid and start id together, in the takeover's owner file",
		function()
			setUp()
			freshLock()
			fs.writeFile(`{lock}/pid`, deadPid()) -- a dead lock: the run takes it over, pausing while it holds the takeover
			local finish = start(nil, { PICKMAN_TEST_TAKEOVER_PAUSE = "2" })
			local owner = `{lock}.takeover/owner`
			t.expect(waitFor(owner)).toBe(true)
			local pid, id = string.match(trim(fs.readFile(owner)), "^(%d+) (%S+)$")
			local now = if pid then fence.startOf(pid) else nil
			local r = finish()
			t.expect({ pid = pid ~= nil, same = id ~= nil and id == now })
				.toEqual({ pid = true, same = true })
			t.expect(r.ok).toBe(true)
		end
	)

	it(
		"a takeover whose live owner left no owner file (an older runner) is kept: the run waits, then fails",
		function()
			setUp()
			freshLock()
			fs.writeFile(`{lock}/pid`, deadPid())
			local pid, stop = livePid()
			fs.writeDir(`{lock}.takeover`)
			fs.writeFile(`{lock}.takeover/pid`, pid)
			local r = run()
			stop()
			t.expect({ ok = r.ok, gaveUp = has(r.stderr, "gave up after") })
				.toEqual({ ok = false, gaveUp = true })
			t.expect(fs.isDir(`{lock}.takeover`)).toBe(true)
		end
	)

	it(
		"a takeover whose live owner's start id can't be read now is kept: the run waits, then fails",
		function()
			setUp()
			freshLock()
			fs.writeFile(`{lock}/pid`, deadPid())
			local pid, stop = livePid()
			fs.writeDir(`{lock}.takeover`)
			fs.writeFile(`{lock}.takeover/owner`, `{pid} {OTHER}`)
			fs.writeFile(`{lock}.takeover/pid`, pid)
			standIn(pid) -- refuses the reader for this pid only
			local r = run(nil, true)
			stop()
			t.expect({ ok = r.ok, gaveUp = has(r.stderr, "gave up after") })
				.toEqual({ ok = false, gaveUp = true })
			t.expect(fs.isDir(`{lock}.takeover`)).toBe(true)
		end
	)

	it("start ids are read only for live pids: the dead records of a stale lock cost no reads", function()
		setUp()
		freshLock()
		local dead = { deadPid(), deadPid(), deadPid() }
		fs.writeFile(`{lock}/pid`, dead[1])
		for _, d in dead do
			fs.writeFile(`{lock}/pid-{d}`, OTHER)
		end
		local pid, stop = livePid()
		fs.writeFile(`{lock}/pid-{pid}`, OTHER)
		standIn(nil) -- logs every pid the reader is asked about
		local r = run(nil, true)
		stop()
		takenOver(r)
		local asked = if fs.isFile(log) then string.split(trim(fs.readFile(log)), "\n") else {}
		t.expect(table.find(asked, pid) ~= nil).toBe(true)
		local readDead = {}
		for _, d in dead do
			if table.find(asked, d) then
				table.insert(readDead, d)
			end
		end
		t.expect(table.concat(readDead, ", ")).toBe("")
	end)

	it("cleans up", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		t.expect(fs.isDir(base)).toBe(false)
	end)
end)
