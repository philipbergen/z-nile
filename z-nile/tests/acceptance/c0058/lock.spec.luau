--!strict
-- c0640: one run at a time per checkout. Runs share the checkout's .cache fixtures, and two runs deleting
-- each other's fixtures is how a spec's git once reached the real repository. A throwaway repository holds a
-- copy of the runner; its runs keep the outer guards and clear only the marker. Waits are rendezvous files
-- with timeouts, never fixed sleeps, except one bounded observation window that proves two runs never overlap.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local task = require("@lune/task")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local base = `{root}/.cache/c0640-lock`
local repo = `{base}/real`
local lock = `{repo}/.cache/tests-run.lock`
local REQ = "req" .. "uire" -- keeps literal require text out of this file (graph scanner)

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
		return -- not built yet: each case then fails on its own assertion
	elseif fs.isDir(src) then
		for _, name in fs.readDir(src) do
			copyTree(`{rel}/{name}`)
		end
	else
		write(rel, fs.readFile(src))
	end
end

local function probe(name: string, body: string)
	write(
		`tests/probe/{name}.spec.luau`,
		`--!strict\nlocal fs = {REQ}("@lune/fs")\nlocal process = {REQ}("@lune/process")\n`
			.. `local task = {REQ}("@lune/task")\nlocal t = {REQ}("@tests/lib/t")\n`
			.. 'local here = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))\n'
			.. "local function waitFor(f: string): boolean\n\tlocal waited = 0\n"
			.. "\twhile not fs.isFile(`{here}/.cache/{f}`) and waited < 30 do\n"
			.. "\t\ttask.wait(0.05)\n\t\twaited += 0.05\n\tend\n\treturn fs.isFile(`{here}/.cache/{f}`)\nend\n"
			.. `return t.spec("{name}", function(it)\n\tit("probe", function()\n{body}\n\tend)\nend)\n`
	)
end

local ENV: { [string]: string } = { PICKMAN_TEST_FENCE = "" }

local function run(name: string, extra: { [string]: string }?): Result
	local env = table.clone(ENV)
	local more: { [string]: string } = extra or {}
	for k, v in more do
		env[k] = v
	end
	return process.exec(
		"lune",
		{ "run", "tests/run", "--", `tests/probe/{name}.spec.luau` },
		{ cwd = repo, env = env }
	)
end

-- Starts `name` in the background; the returned function waits for it and gives its result.
local function start(name: string, extra: { [string]: string }?): () -> Result
	local result: Result? = nil
	task.spawn(function()
		result = run(name, extra)
	end)
	return function(): Result
		local waited = 0
		while result == nil and waited < 60 do
			task.wait(0.05)
			waited += 0.05
		end
		if result == nil then
			error(`{name} did not finish`)
		end
		return result :: Result
	end
end

local function waitFor(f: string)
	local waited = 0
	while not fs.isFile(`{repo}/.cache/{f}`) and waited < 30 do
		task.wait(0.05)
		waited += 0.05
	end
	if not fs.isFile(`{repo}/.cache/{f}`) then
		error(`{f} never appeared`)
	end
end

local function clear(names: { string })
	for _, f in names do
		if fs.isFile(`{repo}/.cache/{f}`) then
			fs.removeFile(`{repo}/.cache/{f}`)
		end
	end
end

-- The pid of a process that has certainly exited.
local function deadPid(): string
	return trim(process.exec("sh", { "-c", "echo $$" }).stdout)
end

local function staleLock()
	fs.writeDir(lock)
	fs.writeFile(`{lock}/pid`, deadPid())
	fs.writeFile(`{lock}/pid-{deadPid()}`, "")
end

local ready = false
local function setUp()
	if not ready then
		error("setup did not finish: not running this case", 2)
	end
end

return t.spec("c0640 one run at a time per checkout", function(it)
	it("sets up a repository holding a copy of the runner and its guards", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(repo)
		for _, rel in { "tests/run.luau", "tests/lib", "z-nile/lib/ac.sh", "z-nile/lib/fence.sh" } do
			copyTree(rel)
		end
		for _, rel in { "z-nile/lib/git-hooks", ".luaurc", "rokit.toml", ".gitignore" } do
			copyTree(rel)
		end
		if fs.isDir(`{repo}/z-nile/lib/git-hooks`) then
			must(process.exec("chmod", { "-R", "+x", `{repo}/z-nile/lib/git-hooks` }), "chmod hooks")
		end
		must(process.exec("git", { "init", "-q", "-b", "main", repo }), "git init")
		-- git below acts only once `repo` is proven to be the repository this spec just created: were it
		-- missing, git would find the enclosing real one (c0640's Problem)
		local top = process.exec("git", { "rev-parse", "--show-toplevel" }, { cwd = repo })
		local here = must(process.exec("pwd", { "-P" }, { cwd = repo }), "pwd -P")
		if not top.ok or trim(top.stdout) ~= here then
			error(`refusing to run git in {repo}: it is not a fixture repository this spec created`)
		end
		must(process.exec("git", { "add", "-A" }, { cwd = repo }), "git add")
		-- no local identity: the runner refuses a repository whose identity is a fixture's
		local commit =
			{ "-c", "user.name=dev", "-c", "user.email=dev@example.com", "commit", "-qm", "runner" }
		must(process.exec("git", commit, { cwd = repo }), "git commit")
		fs.writeDir(`{repo}/.cache`)
		probe("ok", "\t\tt.expect(1).toBe(1)")
		-- holds the lock until the second run has said that it waits
		probe(
			"first",
			'\t\tfs.writeFile(`{here}/.cache/l-first-started`, "")\n'
				.. "\t\tlocal waited = 0\n"
				.. "\t\twhile waited < 30 do\n"
				.. "\t\t\tlocal f = `{here}/.cache/l-second.out`\n"
				.. '\t\t\tif fs.isFile(f) and string.find(fs.readFile(f), "waiting", 1, true) then break end\n'
				.. "\t\t\ttask.wait(0.05)\n\t\t\twaited += 0.05\n\t\tend\n"
				.. '\t\tfs.writeFile(`{here}/.cache/l-first-end`, "")'
		)
		probe(
			"second",
			'\t\tfs.writeFile(`{here}/.cache/l-second-saw`, if fs.isFile(`{here}/.cache/l-first-end`) then "yes" else "no")'
		)
		probe(
			"hold",
			'\t\tfs.writeFile(`{here}/.cache/l-held`, "")\n\t\tt.expect(waitFor("l-go")).toBe(true)\n'
				.. '\t\tfs.writeFile(`{here}/.cache/l-held-done`, "")'
		)
		probe(
			"exclusive",
			'\t\tlocal me = (string.gsub(process.exec("sh", { "-c", "echo $PPID" }).stdout, "%s+$", ""))\n'
				.. "\t\tfor _, name in fs.readDir(`{here}/.cache`) do\n"
				.. '\t\t\tif string.match(name, "^l%-running%-") then fs.writeFile(`{here}/.cache/l-overlap`, name) end\n'
				.. "\t\tend\n"
				.. '\t\tfs.writeFile(`{here}/.cache/l-running-{me}`, "")\n'
				.. '\t\tt.expect(waitFor("l-go-exclusive")).toBe(true)\n'
				.. "\t\tfs.removeFile(`{here}/.cache/l-running-{me}`)"
		)
		probe(
			"nested",
			'\t\tlocal r = process.exec("lune", { "run", "tests/run", "--", "tests/probe/ok.spec.luau" }, { cwd = here })\n'
				.. "\t\tif not r.ok then error(r.stdout .. r.stderr) end"
		)
		must(run("ok"), "first run")
		ready = true
	end)

	it("a second run in the same checkout waits until the first has finished", function()
		setUp()
		clear({ "l-first-started", "l-first-end", "l-second.out", "l-second-saw" })
		local first = start("first")
		waitFor("l-first-started")
		-- the second run's output goes to a file the first run watches, so it holds the lock until then
		local second = process.exec(
			"sh",
			{ "-c", "lune run tests/run -- tests/probe/second.spec.luau > .cache/l-second.out 2>&1" },
			{ cwd = repo, env = ENV }
		)
		t.expect(first().ok).toBe(true)
		t.expect(second.ok).toBe(true)
		t.expect(fs.readFile(`{repo}/.cache/l-second-saw`)).toBe("yes")
		t.expect(has(fs.readFile(`{repo}/.cache/l-second.out`), "waiting for another test run")).toBe(true)
	end)

	it("a lock whose every process is gone is taken over, and released at the end", function()
		setUp()
		staleLock()
		local r = run("ok", { PICKMAN_TEST_LOCK_WAIT = "10" })
		if not r.ok then
			error(r.stdout .. r.stderr)
		end
		t.expect(fs.isDir(lock)).toBe(false)
	end)

	it("a lock held by a live process is waited for, then the run fails naming it", function()
		setUp()
		local pid = trim(process.exec("sh", { "-c", "sleep 30 >/dev/null 2>&1 & echo $!" }).stdout)
		fs.writeDir(lock)
		fs.writeFile(`{lock}/pid`, deadPid())
		fs.writeFile(`{lock}/pid-{pid}`, "") -- the top process is gone, a spec process still runs
		local r = run("ok", { PICKMAN_TEST_LOCK_WAIT = "1" })
		process.exec("kill", { pid })
		fs.removeDir(lock)
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, pid)).toBe(true)
		t.expect(has(r.stdout .. r.stderr, "1 passed")).toBe(false) -- no spec ran
	end)

	it("a run whose top process was killed keeps the lock while its specs still run", function()
		setUp()
		clear({ "l-held", "l-go", "l-held-done" })
		local held = start("hold")
		waitFor("l-held")
		t.expect(fs.isFile(`{lock}/pid`)).toBe(true) -- the run holds the lock
		local top = trim(fs.readFile(`{lock}/pid`))
		process.exec("kill", { "-TERM", top })
		-- the orphaned specs still hold the lock (their output keeps the held run open until they end)
		local meanwhile = run("ok", { PICKMAN_TEST_LOCK_WAIT = "1" })
		fs.writeFile(`{repo}/.cache/l-go`, "")
		waitFor("l-held-done")
		held()
		t.expect(meanwhile.ok).toBe(false)
		t.expect(has(meanwhile.stdout .. meanwhile.stderr, "1 passed")).toBe(false)
		-- once the orphaned specs have finished, the lock is stale and the next run takes it over
		local after = run("ok", { PICKMAN_TEST_LOCK_WAIT = "10" })
		if not after.ok then
			error(after.stdout .. after.stderr)
		end
	end)

	it("two runs waiting on one dead lock take it one at a time", function()
		setUp()
		clear({ "l-go-exclusive", "l-overlap" })
		staleLock()
		-- the first waiter holds the takeover mutex for a moment; the second arrives meanwhile and would judge
		-- the same dead lock stale, then (later, after its longer pause) remove the first's fresh lock: only
		-- the mutex keeps it out
		local a = start("exclusive", { PICKMAN_TEST_LOCK_WAIT = "30", PICKMAN_TEST_TAKEOVER_PAUSE = "0.3" })
		local held = 0
		while not fs.isFile(`{lock}.takeover/pid`) and held < 20 do
			task.wait(0.01)
			held += 0.01
		end
		local b = start("exclusive", { PICKMAN_TEST_LOCK_WAIT = "30", PICKMAN_TEST_TAKEOVER_PAUSE = "1" })
		local function running(): number
			local n = 0
			for _, name in fs.readDir(`{repo}/.cache`) do
				if string.match(name, "^l%-running%-") then
					n += 1
				end
			end
			return n
		end
		local waited = 0
		while running() == 0 and waited < 20 do
			task.wait(0.05)
			waited += 0.05
		end
		-- the one bounded observation window: a second holder would appear within it
		local window = 0
		while window < 1 do
			t.expect(running() <= 1).toBe(true)
			task.wait(0.05)
			window += 0.05
		end
		fs.writeFile(`{repo}/.cache/l-go-exclusive`, "")
		for _, finished in { a(), b() } do
			if not finished.ok then
				error(finished.stdout .. finished.stderr)
			end
		end
		t.expect(fs.isFile(`{repo}/.cache/l-overlap`)).toBe(false)
	end)

	it("a run started from inside a run does not wait for the lock its parent holds", function()
		setUp()
		local r = run("nested", { PICKMAN_TEST_LOCK_WAIT = "3" })
		if not r.ok then
			error(r.stdout .. r.stderr)
		end
	end)

	it("a takeover left by a waiter that died before claiming it is cleared", function()
		setUp()
		staleLock()
		fs.writeDir(`{lock}.takeover`) -- no pid: its waiter died between creating it and claiming it
		local r = run("ok", { PICKMAN_TEST_LOCK_WAIT = "10" })
		if not r.ok then
			error(r.stdout .. r.stderr)
		end
		t.expect(fs.isDir(`{lock}.takeover`)).toBe(false)
	end)

	it("cleans up", function()
		fs.removeDir(base)
	end)
end)
