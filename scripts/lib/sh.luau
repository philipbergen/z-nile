--!strict
-- Subprocess helpers for Lune scripts.
local process = require("@lune/process")

local sh = {}

export type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local function trim(s: string): string
	return (string.gsub(s, "^%s+", ""):gsub("%s+$", ""))
end
sh.trim = trim

-- Run and return the result; never throws.
function sh.run(cmd: string, args: { string }, stdin: string?): Result
	if stdin then
		return process.exec(cmd, args, { stdio = { stdin = stdin } })
	end
	return process.exec(cmd, args)
end

-- Run with output streamed to the terminal; returns success.
function sh.stream(cmd: string, args: { string }): boolean
	return process.exec(cmd, args, { stdio = { stdout = "forward", stderr = "forward" } }).ok
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

return sh
