--!strict
-- c0191 AC5: the spec runner gives every spec process a CPU-time limit (`ulimit -t`), a second line behind the jail's
-- sweeper. A copy of the runner in a fixture repository runs a probe spec that reports the limit it sees and burns CPU
-- under it; nothing here touches the real repository.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local repo = `{(string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))}/.cache/runner-cpu`
local REQ = "req" .. "uire" -- keeps literal require text out of this file (graph scanner)

local function must(r: Result, what: string): string
	if not r.ok then
		error(`{what} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return (string.gsub(r.stdout, "%s+$", ""))
end

local function copyTree(rel: string)
	local src = `{root}/{rel}`
	if fs.isDir(src) then
		fs.writeDir(`{repo}/{rel}`)
		for _, name in fs.readDir(src) do
			copyTree(`{rel}/{name}`)
		end
	elseif fs.isFile(src) then
		fs.writeFile(`{repo}/{rel}`, fs.readFile(src))
	end
end

local function read(name: string): string
	local path = `{repo}/z-nile/.cache/{name}` -- the probe runs in the fixture's z-nile home
	return if fs.isFile(path) then (string.gsub(fs.readFile(path), "%s+$", "")) else ""
end

local made = false
local function fixture()
	if made then
		return
	end
	made = true
	if fs.isDir(repo) then
		fs.removeDir(repo)
	end
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
		}
	do
		copyTree(rel)
	end
	for _, rel in { ".luaurc", "rokit.toml", ".gitignore" } do
		copyTree(rel)
	end
	must(process.exec("chmod", { "-R", "+x", `{repo}/z-nile/lib/git-hooks` }), "chmod")
	-- the probe: writes the limit a child process sees, then burns CPU under it (its own alarm ends it at 20 s if the
	-- limit is not there: 142 is the alarm, 152 the CPU limit's signal)
	fs.writeFile(
		`{repo}/z-nile/tests/probe/limit.spec.luau`,
		`--!strict\nlocal fs = {REQ}("@lune/fs")\nlocal process = {REQ}("@lune/process")\nlocal t = {REQ}("@tests/lib/t")\n`
			.. 'return t.spec("limit", function(it)\n\tit("reports the limit and burns CPU", function()\n'
			.. '\t\tlocal r = process.exec("sh", { "-c", "ulimit -t" })\n'
			.. '\t\tfs.writeFile(".cache/limit.txt", r.stdout)\n'
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
end

-- A stand-in `ulimit` for the nested runner's shell (bash reads BASH_ENV before `bash -c`): it answers `ulimit -t` with
-- FAKE_LIMIT (default unlimited) and records every value the runner asks for, so the case sees what the runner
-- requested, not what a limit this spec already has makes of it (every spec runs under the jail's 1200 s, which would
-- hide any default at or above it).
local function standIn()
	fs.writeFile(
		`{repo}/fake-ulimit.sh`,
		'ulimit() { if [ "$1" = -t ] && [ $# -eq 1 ]; then echo "${FAKE_LIMIT:-unlimited}"; '
			.. 'elif [ "$1" = -t ]; then echo "$2" >> "$FAKE_LOG"; fi; }\n'
	)
end

-- what the runner asked for, with `limit` as the limit it found in force, and PICKMAN_SPEC_CPU = `cpu`
local function asked(cpu: string?, limit: string?): string
	fixture()
	standIn()
	local log = `{repo}/asked.log`
	if fs.isFile(log) then
		fs.removeFile(log)
	end
	local env: { [string]: string } = {
		PICKMAN_TEST_FENCE = "",
		PICKMAN_SPEC_CPU = cpu or "",
		BASH_ENV = `{repo}/fake-ulimit.sh`,
		FAKE_LOG = log,
		FAKE_LIMIT = limit or "unlimited",
	}
	local r = process.exec(
		"lune",
		{ "run", "tests/run", "--", "tests/probe/limit.spec.luau" },
		{ cwd = `{repo}/z-nile`, env = env }
	)
	if not r.ok then
		error(`the nested run failed: {r.stdout}{r.stderr}`, 0)
	end
	return if fs.isFile(log) then (string.gsub(fs.readFile(log), "%s+$", "")) else ""
end

local function runProbe(cpu: string?): Result
	fixture()
	for _, f in { "limit.txt", "burn.txt" } do
		local path = `{repo}/z-nile/.cache/{f}`
		if fs.isFile(path) then
			fs.removeFile(path)
		end
	end
	-- PICKMAN_SPEC_CPU is cleared unless the case sets it: this spec may itself run under one
	local env: { [string]: string } = { PICKMAN_TEST_FENCE = "", PICKMAN_SPEC_CPU = cpu or "" }
	return process.exec(
		"lune",
		{ "run", "tests/run", "--", "tests/probe/limit.spec.luau" },
		{ cwd = `{repo}/z-nile`, env = env }
	)
end

return t.spec("the spec runner's CPU limit", function(it)
	it("AC5: the runner asks for 1200 seconds of CPU by default, and PICKMAN_SPEC_CPU sets it", function()
		t.expect(asked(nil, nil)).toBe("1200")
		t.expect(asked("77", nil)).toBe("77")
	end)

	it("AC5: a limit the run already has stays when it is lower; a higher one is lowered", function()
		t.expect(asked("300", "100")).toBe("")
		t.expect(asked("300", "300")).toBe("")
		t.expect(asked("40", "5000")).toBe("40")
		t.expect(asked(nil, "unlimited")).toBe("1200")
	end)

	it("AC5: a process that burns CPU is stopped by the limit, not by its own alarm", function()
		local r = runProbe("2")
		t.expect(r.ok).toBe(true)
		t.expect(read("burn.txt")).toBe("152")
	end)

	it("AC5: the limit is in force in the spec's processes (the real thing, with a lower caller)", function()
		fixture()
		local r = process.exec(
			"sh",
			{ "-c", "ulimit -t 100; exec lune run tests/run -- tests/probe/limit.spec.luau" },
			{ cwd = `{repo}/z-nile`, env = { PICKMAN_TEST_FENCE = "", PICKMAN_SPEC_CPU = "300" } }
		)
		t.expect(r.ok).toBe(true)
		t.expect(read("limit.txt")).toBe("100")
	end)

	it(
		"AC5: a value that is not a whole number of 1 to 86400 seconds refuses the run before any spec starts",
		function()
			for _, bad in { "abc", "0", "-5", "1.5", "86401", " 5" } do
				local r = runProbe(bad)
				if r.code ~= 2 then
					error(`PICKMAN_SPEC_CPU={bad}: expected exit 2, got {r.code}: {r.stdout}{r.stderr}`, 0)
				end
				t.expect(
					string.find(
						r.stderr,
						"PICKMAN_SPEC_CPU must be a whole number of seconds, 1 to 86400",
						1,
						true
					) ~= nil
				).toBe(true)
				t.expect(read("limit.txt")).toBe("")
				-- refused before the lock is taken: a run that exits late would leave it behind
				t.expect(fs.isDir(`{repo}/z-nile/.cache/tests-run.lock`)).toBe(false)
			end
			if fs.isDir(repo) then
				fs.removeDir(repo)
			end
		end
	)
end)
