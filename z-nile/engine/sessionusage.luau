--!strict
-- A stream that carried no token count is read back from the CLI's own session store (c0175, the user's ruling: "Read their
-- session store"). One reader per runtime, each giving the lines its adapter's `feed` counts:
--   kimi-cli      the session's wire.jsonl (kimisession.luau): its `usage.record` lines
--   opencode-cli  `opencode export <session>`, the CLI reading its own store: the session's `info.tokens`, as one
--                 `step_finish` line
-- agy keeps its conversations as protobuf blobs in SQLite, which no reader here takes: its stream prints usage (probed), so
-- an agy step without a count stays unmeasured.
local kimisession = require("./kimisession")
local process = require("@lune/process")
local serde = require("@lune/serde")

local sessionusage = {}

-- How long `opencode export` may run before it is given up on, in seconds.
sessionusage.EXPORT_SECONDS = 20

-- The one `step_finish` line an `opencode export` text gives (a heading line, then the session as JSON), or nil when the
-- text holds no session with tokens.
function sessionusage.opencodeLine(text: string): string?
	local from = string.find(text, "{", 1, true)
	if from == nil then
		return nil
	end
	local ok, decoded = pcall(function()
		return serde.decode("json", string.sub(text, from :: number))
	end)
	if not ok or type(decoded) ~= "table" then
		return nil
	end
	local info = (decoded :: any).info
	if type(info) ~= "table" or type(info.tokens) ~= "table" then
		return nil
	end
	return serde.encode("json", { type = "step_finish", part = { id = "export", tokens = info.tokens } })
end

local function kimiLines(session: string): { string }
	local root = process.env.PICKMAN_KIMI_SESSIONS
	if root == nil or root == "" then
		local home = process.env.HOME
		if home ~= nil and home ~= "" then
			root = `{home}/.kimi-code/sessions`
		end
	end
	local text = if root ~= nil and root ~= "" then kimisession.read(root, session) else nil
	local out: { string } = {}
	if text ~= nil then
		for line in string.gmatch(text, "[^\n]+") do
			if string.find(line, '"usage.record"', 1, true) then
				table.insert(out, line)
			end
		end
	end
	return out
end

local function opencodeLines(session: string, bin: string, env: { [string]: string }, cwd: string): { string }
	if string.sub(session, 1, 4) ~= "ses_" then
		return {}
	end
	local r = process.exec(
		"perl",
		{ "-e", `alarm {sessionusage.EXPORT_SECONDS}; exec @ARGV`, bin, "export", session },
		{ env = env, cwd = cwd }
	)
	local line = if r.ok then sessionusage.opencodeLine(r.stdout) else nil
	return if line ~= nil then { line } else {}
end

-- The lines to feed `runtime`'s adapter for `session`, from the CLI's own store; none when the runtime keeps no reader, the
-- store is missing or unreadable. `bin` is the CLI the step ran (the one on its PATH).
function sessionusage.lines(
	runtime: string,
	session: string,
	bin: string,
	env: { [string]: string },
	cwd: string
): { string }
	if session == "" then
		return {}
	end
	if runtime == "kimi-cli" then
		return kimiLines(session)
	elseif runtime == "opencode-cli" then
		return opencodeLines(session, bin, env, cwd)
	end
	return {}
end

return sessionusage
