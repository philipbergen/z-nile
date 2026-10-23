--!strict
-- R0210 review 005 F2: a process a spec leaves behind does not outlive the run. The runner starts the specs in a
-- process group of their own and stops what is left in it when they end. A copy of the runner in a fixture runs a
-- probe that leaves a background process (reaped) and a detached one (setsid leaves the group on purpose: the testing
-- skill lists that under "Caught only by review"); this spec stops the detached one itself.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local repo = `{root}/.cache/fence-leftovers`
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
	local path = `{repo}/.cache/{name}`
	return if fs.isFile(path) then (string.gsub(fs.readFile(path), "%s+$", "")) else ""
end

return t.spec("a run leaves no process behind", function(it)
	it("a background process a spec leaves is stopped when the run ends", function()
		if fs.isDir(repo) then
			fs.removeDir(repo)
		end
		fs.writeDir(`{repo}/tests/probe`)
		fs.writeDir(`{repo}/z-nile/lib`)
		for _, rel in
			{
				"tests/run.luau",
				"tests/lib",
				"z-nile/lib/ac.sh",
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
		fs.writeFile(
			`{repo}/tests/probe/leave.spec.luau`,
			`--!strict\nlocal process = {REQ}("@lune/process")\nlocal t = {REQ}("@tests/lib/t")\n`
				.. 'return t.spec("leave", function(it)\n\tit("starts two processes and returns", function()\n'
				.. '\t\tprocess.exec("sh", { "-c", "sleep 60 >/dev/null 2>&1 & echo $! > .cache/bg.pid" })\n'
				.. '\t\tprocess.exec("perl", { "-MPOSIX", "-e", \'my $p = fork; if ($p) { open my $f, ">", ".cache/detached.pid"; print $f $p; exit } POSIX::setsid(); open STDOUT, ">/dev/null"; open STDERR, ">/dev/null"; sleep 60\' })\n'
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
			{ "run", "tests/run", "--", "tests/probe/leave.spec.luau" },
			{ cwd = repo, env = { PICKMAN_TEST_FENCE = "" } }
		)
		local bg, detached = read("bg.pid"), read("detached.pid")
		local function alive(pid: string): boolean
			return pid ~= "" and process.exec("kill", { "-0", pid }).ok
		end
		local survived = alive(bg)
		-- the detached one left the group on purpose (review only); stop both so nothing lingers
		for _, pid in { bg, detached } do
			if alive(pid) then
				process.exec("kill", { "-KILL", pid })
			end
		end
		if not r.ok then
			error(r.stdout .. r.stderr)
		end
		t.expect(bg ~= "").toBe(true)
		t.expect(survived).toBe(false)
		fs.removeDir(repo)
	end)
end)
