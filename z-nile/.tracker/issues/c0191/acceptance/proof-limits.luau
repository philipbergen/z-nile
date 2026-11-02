--!strict
-- c0191 AC2 and AC5, the one-time proof with real CPU limits: a process that burns CPU under the spec runner's limit
-- dies of SIGXCPU (not of its own alarm), a spinning engine under `zn`'s limit is stopped, and a hook entry that hangs
-- is stopped by pre-bash.sh's limit. It spins CPU on purpose (about four seconds of CPU, six of wall clock), so it is NOT a spec: check.sh
-- runs it only before `./zn done`, bounded (`./zn run --time 120 -- lune run proof-limits.luau`), to prove the implementation, and
-- `tests/run` never runs it (no `.spec.luau` name), so `./zn done` promotes it as a file the suite does not execute.
-- The suite's half is runner-cpu.spec, engine-cpu.spec and hooks.spec, which watch what is asked for through stand-ins.
-- Every fixture is a throwaway under .cache with its own repository. Prints one line per case; exit 1 on a failure.
local fs = require("@lune/fs")
local process = require("@lune/process")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local base =
	`{(string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))}/.cache/limits-proof-{os.time()}-{math.random(
		1,
		1e9
	)}`
local REQ = "req" .. "uire" -- keeps literal require text out of this file (graph scanner)

local failed = 0
local function expect(name: string, ok: boolean, why: string?)
	print(`{if ok then "ok  " else "FAIL"} {name}{if not ok and why then `: {why}` else ""}`)
	if not ok then
		failed += 1
	end
end

local function must(r: Result, what: string): string
	if not r.ok then
		error(`{what} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return (string.gsub(r.stdout, "%s+$", ""))
end

local function copyTree(repo: string, rel: string)
	local src = `{root}/{rel}`
	if fs.isDir(src) then
		fs.writeDir(`{repo}/{rel}`)
		for _, name in fs.readDir(src) do
			copyTree(repo, `{rel}/{name}`)
		end
	elseif fs.isFile(src) then
		fs.writeFile(`{repo}/{rel}`, fs.readFile(src))
	end
end

-- source of a stand-in that records its own Lune pid in `pidFile`, says it started, then spins for up to `secs` CPU seconds
local function spinner(pidFile: string, secs: number, finish: string): string
	return "--!strict\nlocal fs = "
		.. REQ
		.. '("@lune/fs")\nlocal process = '
		.. REQ
		.. '("@lune/process")\n'
		.. 'fs.writeFile("'
		.. pidFile
		.. '", process.exec("sh", { "-c", "echo $PPID" }).stdout)\n'
		.. 'print("started")\nlocal t = os.clock()\nwhile os.clock() - t < '
		.. secs
		.. " do end\n"
		.. finish
end

-- true once the Lune process the stand-in recorded is gone (a bounded poll, a fifth of a second a try)
local function recordedGone(pidFile: string): boolean
	if not fs.isFile(pidFile) then
		return false -- it never started
	end
	local pid = (string.gsub(fs.readFile(pidFile), "%s+$", ""))
	for _ = 1, 25 do
		if not process.exec("kill", { "-0", pid }).ok then
			return true
		end
		process.exec("sleep", { "0.2" })
	end
	-- only a process that still runs the stand-in is signalled: a reused pid is left alone
	if string.find(process.exec("ps", { "-o", "command=", "-p", pid }).stdout, "z-nile/", 1, true) then
		process.exec("kill", { "-KILL", pid })
	end
	return false
end

-- 1. the spec runner's limit, in a fixture repository holding a copy of the runner
local function runnerBurn()
	local repo = `{base}/runner`
	fs.writeDir(`{repo}/z-nile/tests/probe`)
	fs.writeDir(`{repo}/z-nile/lib`)
	for _, rel in
		{
			"z-nile/tests/run.luau",
			"z-nile/tests/lib",
			"z-nile/.luaurc",
			"z-nile/lib/ac.sh",
			"z-nile/lib/cpu.sh",
			"z-nile/lib/fence.sh",
			"z-nile/lib/git-hooks",
			".luaurc",
			"rokit.toml",
			".gitignore",
		}
	do
		copyTree(repo, rel)
	end
	must(process.exec("chmod", { "-R", "+x", `{repo}/z-nile/lib/git-hooks` }), "chmod")
	-- the probe burns CPU under the limit; its own alarm ends it at 20 s if the limit is not there (142 is the alarm,
	-- 152 the CPU limit's signal)
	fs.writeFile(
		`{repo}/z-nile/tests/probe/burn.spec.luau`,
		`--!strict\nlocal fs = {REQ}("@lune/fs")\nlocal process = {REQ}("@lune/process")\nlocal t = {REQ}("@tests/lib/t")\n`
			.. 'return t.spec("burn", function(it)\n\tit("burns CPU", function()\n'
			.. '\t\tlocal b = process.exec("sh", { "-c", "perl -e \'alarm 20; 1 while 1\'; echo $?" })\n'
			.. '\t\tfs.writeFile(".cache/burn.txt", b.stdout)\n'
			.. "\t\tt.expect(1).toBe(1)\n\tend)\nend)\n"
	)
	must(process.exec("git", { "init", "-q", "-b", "main", repo }), "git init")
	local top = must(process.exec("git", { "rev-parse", "--show-toplevel" }, { cwd = repo }), "rev-parse")
	if top ~= must(process.exec("pwd", { "-P" }, { cwd = repo }), "pwd") then
		error(`{repo} is not a fixture repository; not running git there`)
	end
	must(process.exec("git", { "add", "-A" }, { cwd = repo }), "git add")
	must(
		process.exec(
			"git",
			{ "-c", "user.name=dev", "-c", "user.email=dev@example.invalid", "commit", "-qm", "runner" },
			{ cwd = repo }
		),
		"git commit"
	)
	local r = process.exec(
		"lune",
		{ "run", "tests/run", "--", "tests/probe/burn.spec.luau" },
		{ cwd = `{repo}/z-nile`, env = { PICKMAN_TEST_FENCE = "", PICKMAN_SPEC_CPU = "1" } }
	)
	local path = `{repo}/z-nile/.cache/burn.txt`
	local burn = if fs.isFile(path) then (string.gsub(fs.readFile(path), "%s+$", "")) else ""
	expect(
		"AC5: a process that burns CPU is stopped by the runner's limit (152), not by its own alarm",
		r.ok and burn == "152",
		`run {r.code} burn "{burn}" {r.stderr}`
	)
end

-- 2. zn's engine limit: a copy of zn runs an engine that spins for up to 20 CPU seconds
local function engineSpin()
	local dir = `{base}/engine`
	fs.writeDir(`{dir}/z-nile/engine`)
	fs.writeDir(`{dir}/z-nile/lib`)
	fs.writeFile(`{dir}/z-nile/lib/cpu.sh`, fs.readFile(`{root}/z-nile/lib/cpu.sh`))
	fs.writeFile(`{dir}/zn`, fs.readFile(`{root}/zn`))
	process.exec("chmod", { "+x", `{dir}/zn` })
	fs.writeFile(`{dir}/z-nile/engine/main.luau`, spinner(`{dir}/entry.pid`, 20, 'print("finished")\n'))
	local r = process.exec("sh", { "-c", `exec {dir}/zn` }, { cwd = dir, env = { ZN_ENGINE_CPU = "1" } })
	expect(
		"AC5: an engine that spins is stopped by zn's limit before it finishes, and its process is gone",
		string.find(r.stdout, "started", 1, true) ~= nil
			and string.find(r.stdout, "finished", 1, true) == nil
			and r.code ~= 0
			and recordedGone(`{dir}/entry.pid`),
		`{r.code} {r.stdout}`
	)
end

-- 3. the hook's limit: pre-bash.sh runs an entry that spins for up to 15 CPU seconds under its 2 s limit
local function hookHang()
	local dir = `{base}/hook`
	fs.writeDir(`{dir}/scripts/hooks`)
	fs.writeDir(`{dir}/z-nile/lib`)
	fs.writeFile(`{dir}/z-nile/lib/cpu.sh`, fs.readFile(`{root}/z-nile/lib/cpu.sh`))
	fs.writeFile(`{dir}/scripts/hooks/pre-bash.sh`, fs.readFile(`{root}/scripts/hooks/pre-bash.sh`))
	process.exec("chmod", { "+x", `{dir}/scripts/hooks/pre-bash.sh` })
	fs.writeFile(`{dir}/z-nile/guard-bash.luau`, spinner(`{dir}/entry.pid`, 15, ""))
	local r = process.exec("bash", { `{dir}/scripts/hooks/pre-bash.sh` }, {
		cwd = "/",
		stdio = { stdin = "{}" },
	})
	-- stopped by SIGXCPU long before its own 15 seconds are up: a non-zero status that is not the refusal's 2, from an
	-- entry that did start
	expect(
		"AC2: a hook entry that hangs is stopped by pre-bash.sh's limit, and does not refuse the call",
		string.find(r.stdout, "started", 1, true) ~= nil and r.code ~= 0 and r.code ~= 2,
		tostring(r.code)
	)
	expect("AC2: and its process is gone", recordedGone(`{dir}/entry.pid`))
end

fs.writeDir(base)
for _, step in { runnerBurn, engineSpin, hookHang } do
	local ok, err = pcall(step :: () -> any)
	if not ok then
		expect("a proof step ran", false, tostring(err))
	end
end
if fs.isDir(base) then
	fs.removeDir(base)
end
process.exit(if failed == 0 then 0 else 1)
