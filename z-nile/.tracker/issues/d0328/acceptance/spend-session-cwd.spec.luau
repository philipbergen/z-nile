--!strict
-- d0328 AC1: `sessionread.span`, which `./zn spend` and `record` call with `process.cwd`, measures a .worktree cwd that
-- ends in a slash under the folder Claude Code names for that checkout (no trailing "-", "-" for each "/" and "."). The
-- session is seeded only under that real folder name.
local fs = require("@lune/fs")
local process = require("@lune/process")
local sessionread = require("@znile/engine/sessionread")
local t = require("@tests/lib/t")

local ROOT = ".cache/d0328-spend-session"

local LINE1 =
	'{"type":"assistant","timestamp":"2026-11-03T23:33:00.000Z","message":{"id":"msg_1","model":"claude-opus-4","usage":{"input_tokens":2,"cache_creation_input_tokens":10,"output_tokens":4}}}\n'
local LINE2 =
	'{"type":"assistant","timestamp":"2026-11-03T23:33:10.000Z","message":{"id":"msg_2","model":"claude-opus-4","usage":{"input_tokens":1,"cache_creation_input_tokens":0,"output_tokens":3}}}\n'

-- seeds one transcript under `folder` (a Claude Code project folder name) and reads the cwd with HOME pointed there
local function readAs(folder: string, cwd: string)
	local root = `{process.cwd}/{ROOT}/{folder}`
	pcall(function()
		fs.removeDir(root)
	end)
	local dir = `{root}/home/.claude/projects/{folder}`
	fs.writeDir(dir)
	fs.writeFile(`{dir}/s1.jsonl`, LINE1 .. LINE2)
	local oldHome = process.env.HOME
	process.env.HOME = `{root}/home`
	local ok, reading =
		pcall(sessionread.span, cwd, "2020-01-01T00:00:00.000Z", 0, "2099-01-01T00:00:00.000Z", os.time())
	process.env.HOME = oldHome
	assert(ok, "sessionread.span failed")
	return reading
end

return t.spec("d0328 spend finds the Claude session of a worktree cwd", function(it)
	it("AC1: a .worktree cwd ending in a slash is measured under its real folder name", function()
		local reading = readAs("-a-b--worktree-x", "/a/b/.worktree/x/")
		t.expect(reading.model).toBe("claude-opus-4")
		t.expect(reading.tokens).toBe(20)
		t.expect(reading.ai).toBe(10)
	end)
end)
