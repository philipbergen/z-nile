--!strict
-- What a CLI writes into the repository it runs in, that the dispatcher keeps it from writing (c0175 E15). opencode keeps
-- its project id in `<common git dir>/opencode` (40 bytes) and rewrites it on every run, in a worktree into the main
-- repository's `.git`. It runs the same with that file read-only (probed), so an existing file is made read-only before
-- and after each step: the one write left is its creation, in a repository that never had it (and the after-seal then locks it).
local fs = require("@lune/fs")
local process = require("@lune/process")

local cliguard = {}

local FILES = { ["opencode-cli"] = "opencode" } :: { [string]: string }

-- Makes the CLI's project file in `cwd`'s common git directory read-only, when it exists. True when it did.
function cliguard.seal(runtime: string, cwd: string, env: { [string]: string }): boolean
	local name = FILES[runtime]
	if name == nil then
		return false
	end
	local git = env.ZN_REAL_GIT or process.env.ZN_REAL_GIT
	if git == nil or git == "" then
		git = "git"
	end
	local r = process.exec(
		git :: string,
		{ "-C", cwd, "rev-parse", "--path-format=absolute", "--git-common-dir" },
		{ env = env }
	)
	if not r.ok then
		return false
	end
	local dir = string.gsub(r.stdout, "%s+$", "")
	local path = `{dir}/{name}`
	if dir == "" or not fs.isFile(path) then
		return false
	end
	return process.exec("chmod", { "444", path }).ok
end

return cliguard
