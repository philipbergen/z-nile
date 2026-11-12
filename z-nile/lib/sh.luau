--!strict
-- Subprocess helpers for Lune scripts.
local process = require("@lune/process")
local task = require("@lune/task")
-- this module's folder, z-nile/lib/: its helper scripts are found from here, wherever the caller runs (a spec runs from
-- its project's home since c0120, not the root)
local LIB = string.match(debug.info(1, "s"), "^(.*)/[^/]+$") or "z-nile/lib"

local sh = {}

export type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local function trim(s: string): string
	return (string.gsub(s, "^%s+", ""):gsub("%s+$", ""))
end
sh.trim = trim

-- Run and return the result; never throws.
function sh.run(cmd: string, args: { string }, stdin: string?): Result
	local r: Result = if stdin
		then process.exec(cmd, args, { stdio = { stdin = stdin } })
		else process.exec(cmd, args)
	-- c0275: a fetch meeting another process's lock on a ref every worktree shares (the heartbeat's beaters, ticks and
	-- dispatcher child fetch `main` too) is tried once more after a second; a second failure is the answer
	if
		cmd == "git"
		and args[1] == "fetch"
		and not r.ok
		and string.find(r.stderr, "cannot lock ref", 1, true)
	then
		task.wait(1)
		r = if stdin then process.exec(cmd, args, { stdio = { stdin = stdin } }) else process.exec(cmd, args)
	end
	return r
end

-- Run with output streamed to the terminal; returns success.
function sh.stream(cmd: string, args: { string }): boolean
	return process.exec(cmd, args, { stdio = { stdout = "forward", stderr = "forward" } }).ok
end

-- sh.stream with `dir` as the working directory (c0120: a project's specs run from its home).
function sh.streamIn(dir: string, cmd: string, args: { string }): boolean
	return process.exec(cmd, args, { cwd = dir, stdio = { stdout = "forward", stderr = "forward" } }).ok
end

-- Run and return trimmed stdout; throws with stderr on failure.
function sh.must(cmd: string, args: { string }): string
	local r = sh.run(cmd, args)
	if not r.ok then
		error(`{cmd} {table.concat(args, " ")} failed ({r.code}):\n{r.stderr}{r.stdout}`, 0)
	end
	return trim(r.stdout)
end

function sh.git(args: { string }): string
	return sh.must("git", args)
end

-- Writes `text` to `path` through z-nile/lib/replace-file.pl: a sibling temporary file, created exclusively and never
-- followed, renamed onto `path`. A symlink a spec swapped in at `path` (to a file or to a directory) is replaced,
-- never followed; a real directory there is an error (c0077). `path` is relative to the current folder (the
-- repository root for every tracker command; a project's home for a spec, c0120), or absolute.
function sh.writeReplacing(path: string, text: string)
	local r = process.exec("perl", { `{LIB}/replace-file.pl`, path }, { stdio = { stdin = text } })
	if not r.ok then
		error(`writeReplacing {path}: {trim(r.stderr)}`, 0)
	end
end

return sh
