--!strict
-- Fixture repositories for specs (testing skill, "Specs never touch the real repository"). Every git or
-- tracker.sh command a spec runs in a fixture goes through here, and runs only in a repository that lies under
-- a .cache folder and is that directory itself: if a fixture's repository were missing, git would otherwise find
-- the enclosing real one. Creating a fixture (git init, git clone to a new path) needs no check: the new path is
-- named explicitly.
local process = require("@lune/process")

local fixture = {}

export type Result = { ok: boolean, code: number, stdout: string, stderr: string }
export type Options = { env: { [string]: string }?, stdin: string? }

local function trim(s: string): string
	return (string.gsub(s, "^%s+", ""):gsub("%s+$", ""))
end

-- The path with its symlinks resolved, or nil when it isn't a directory.
function fixture.physical(path: string): string?
	local ok, r = pcall(process.exec, "pwd", { "-P" }, { cwd = path })
	if not ok or not r.ok then
		return nil
	end
	return trim(r.stdout)
end

-- Raises unless `dir` is a fixture repository: under this run's .cache folder (the spec runs at the checkout's root),
-- and the top of its own worktree (or a bare repository's own git directory).
function fixture.check(dir: string)
	local here = fixture.physical(dir)
	local cache = `{fixture.physical(".") or "?"}/.cache/`
	local fail = `refusing to run in {dir}: it is not a fixture repository under {cache}`
	if not here or string.sub(here .. "/", 1, #cache) ~= cache then
		error(fail, 3)
	end
	local top = process.exec("git", { "rev-parse", "--show-toplevel" }, { cwd = here })
	if top.ok and trim(top.stdout) == here then
		return
	end
	local bare = process.exec(
		"git",
		{ "rev-parse", "--is-bare-repository", "--absolute-git-dir" },
		{ cwd = here }
	)
	local lines = string.split(trim(bare.stdout), "\n")
	if bare.ok and lines[1] == "true" and fixture.physical(lines[2] or "") == here then
		return
	end
	error(fail, 3)
end

-- What would point git at another repository than `dir`: these variables, and git's own options before its command.
local ELSEWHERE_ENV =
	{ "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR", "GIT_OBJECT_DIRECTORY" }

local function pointsElsewhere(cmd: string, args: { string }, env: { [string]: string }?): string?
	for _, name in ELSEWHERE_ENV do
		if env and env[name] then
			return name
		end
	end
	-- config handed in through the environment can set core.worktree and the like (review 001 F4)
	if env then
		for name in env do
			if string.sub(name, 1, 11) == "GIT_CONFIG_" then
				return name
			end
		end
	end
	if cmd ~= "git" then
		return nil
	end
	local i = 1
	while args[i] and string.sub(args[i], 1, 1) == "-" do
		local a = args[i]
		if a == "-C" or string.match(a, "^%-%-git%-dir") or string.match(a, "^%-%-work%-tree") then
			return a
		end
		if a == "-c" and string.match(string.lower(args[i + 1] or ""), "^core%.worktree") then
			return "-c " .. args[i + 1]
		end
		i += if a == "-c" then 2 else 1
	end
	return nil
end

-- Runs `cmd` in the fixture `dir`, after checking it; never raises for the command's own failure.
function fixture.exec(dir: string, cmd: string, args: { string }, options: Options?): Result
	fixture.check(dir)
	local o: Options = options or {}
	local away = pointsElsewhere(cmd, args, o.env)
	if away then
		error(`refusing to run in {dir}: {away} would point git at another repository`, 2)
	end
	if o.stdin then
		return process.exec(cmd, args, { cwd = dir, env = o.env, stdio = { stdin = o.stdin } })
	end
	return process.exec(cmd, args, { cwd = dir, env = o.env })
end

-- git in the fixture `dir`; raises with git's output when it fails, and returns trimmed stdout.
function fixture.git(dir: string, args: { string }, options: Options?): string
	fixture.check(dir)
	local r = fixture.exec(dir, "git", args, options)
	if not r.ok then
		error(`git {table.concat(args, " ")} in {dir} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return trim(r.stdout)
end

return fixture
