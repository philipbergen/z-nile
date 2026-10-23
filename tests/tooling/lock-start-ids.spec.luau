--!strict
-- R0047 review 001 F1, F2 (beside c0127's sequestered reuse.spec, which cannot change during execution): a run
-- that waits for the test lock reads its own start id once, not on every wait step, and a live top process whose
-- recorded start id (`start-<pid>`) matches still holds the lock. A throwaway repository holds a copy of the runner,
-- as c0127's reuse.spec does; a stand-in perl first on PATH logs every pid the start reader is asked about and hands
-- every call to the real perl.
local fence = require("@tests/lib/fence")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local base = `{root}/.cache/lock-start-ids`
local repo = `{base}/real`
local bin = `{base}/bin`
local log = `{base}/asked`
local lock = `{repo}/.cache/tests-run.lock`

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

return t.spec("R0047 lock start ids", function(it)
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
		local commit = {
			"-c",
			"user.name=lock-start-ids",
			"-c",
			"user.email=lock-start-ids@example.invalid",
			"commit",
			"-qm",
			"runner",
		}
		must(process.exec("git", commit, { cwd = repo }), "git commit")
		fs.writeDir(`{repo}/.cache`)
		write(
			"tests/probe/ok.spec.luau",
			'--!strict\nlocal t = require("@tests/lib/t")\nreturn t.spec("ok", function(it)\n'
				.. '\tit("probe", function()\n\t\tt.expect(1).toBe(1)\n\tend)\nend)\n'
		)
		ready = true
	end)

	it(
		"a live top process whose recorded start id matches still holds: the run waits, then fails naming it",
		function()
			setUp()
			freshLock()
			local pid, stop = livePid()
			fs.writeFile(`{lock}/pid`, pid)
			fs.writeFile(`{lock}/start-{pid}`, fence.startOf(pid) or "unreadable")
			local r = run()
			stop()
			heldBy(r, pid)
		end
	)

	it("a waiting run reads its own start id once, however many steps it waits", function()
		setUp()
		freshLock()
		local pid, stop = livePid()
		fs.writeFile(`{lock}/pid`, deadPid())
		fs.writeFile(`{lock}/pid-{pid}`, fence.startOf(pid) or "unreadable") -- a live worker: the run waits 1 s
		standIn(nil)
		local r = run(nil, true)
		stop()
		heldBy(r, pid)
		local asked: { string } = {}
		if fs.isFile(log) then
			asked = string.split(trim(fs.readFile(log)), "\n")
		end
		local holder, others = 0, 0
		for _, p in asked do
			if p == pid then
				holder += 1
			else
				others += 1
			end
		end
		-- the holder is judged on every step (about ten in 1 s), the waiting run's own id is read once
		t.expect({ steps = holder >= 5, own = others }).toEqual({ steps = true, own = 1 })
	end)

	it("cleans up", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		t.expect(fs.isDir(base)).toBe(false)
	end)
end)
