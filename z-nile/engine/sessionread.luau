--!strict
-- Reads the session files the CLIs in .models.toml leave on this machine, and reduces them with sessions.luau.
-- Claude Code writes a project jsonl (`~/.claude/projects/<cwd-with-slashes-as-dashes>`). Grok writes
-- `events.jsonl` and `updates.jsonl` under `~/.grok/sessions/<url-encoded cwd>`. The Cursor `agent` CLI writes
-- transcripts under `~/.cursor/projects/<cwd>` that, today, have neither timestamps nor token counts.
-- Kimi's wire is `~/.kimi-code/sessions/<workspace>/<id>/agents/main/wire.jsonl` (or $PICKMAN_KIMI_SESSIONS).
-- A wire belongs to a checkout only when that session's state.json cwd is the checkout. The workspace folder
-- name is not enough to tell, so a wire with no cwd is not counted.
-- `running` is the session executing this command: Claude's `CLAUDE_CODE_SESSION_ID`, or Kimi's session id when
-- one is set. The whole file counts (each Claude message id once). The layer's base commit is not the span:
-- that commit can predate the session, and the project folder holds other sessions.
local fs = require("@lune/fs")
local process = require("@lune/process")
local sessions = require("./sessions")

local sessionread = {}

local function home(): string
	return process.env.HOME or ""
end

function sessionread.encode(path: string): string
	return (
		string.gsub(path, "([^%w%-%._~])", function(c: string): string
			return string.format("%%%02X", string.byte(c))
		end)
	)
end

-- Lune's metadata timestamp is a DateTime (userdata with a unixTimestamp field). A table with the same
-- field is accepted so a test double can stand in. Nil means unknown, and an unknown time is read.
local function modifiedUnix(path: string): number?
	local ok, meta = pcall(fs.metadata, path)
	if not ok or not meta then
		return nil
	end
	local at = (meta :: any).modifiedAt
	if type(at) ~= "table" and type(at) ~= "userdata" then
		return nil
	end
	local n = (at :: any).unixTimestamp
	if type(n) == "number" then
		return n
	end
	return nil
end

-- At most 200 files, the newest ones modified at or after `sinceUnix`. Directory order is not a time order,
-- so stopping at the first 200 would miss the session that just wrote.
local function filesUnder(dir: string, suffix: string, sinceUnix: number): { string }
	local out: { string } = {}
	if dir == "" or not fs.isDir(dir) then
		return out
	end
	local found: { { path: string, at: number } } = {}
	local function walk(d: string)
		local ok, names = pcall(fs.readDir, d)
		if not ok then
			return
		end
		for _, name in names :: { string } do
			local path = `{d}/{name}`
			if fs.isDir(path) then
				walk(path)
			elseif string.sub(name, -#suffix) == suffix then
				local at = modifiedUnix(path)
				if at == nil or at >= sinceUnix - 1 then
					table.insert(found, { path = path, at = at or 0 })
				end
			end
		end
	end
	walk(dir)
	table.sort(found, function(a, b)
		return a.at > b.at
	end)
	local n = math.min(200, #found)
	for i = 1, n do
		table.insert(out, found[i].path)
	end
	return out
end

local function text(path: string): string?
	local ok, body = pcall(fs.readFile, path)
	return if ok then body :: string else nil
end

local function add(into: sessions.Part, part: sessions.Part)
	if part.tokens ~= nil then
		into.tokens = (into.tokens or 0) + part.tokens
	end
	if part.ai ~= nil then
		into.ai = (into.ai or 0) + part.ai
	end
	if part.inn ~= nil then
		into.inn = (into.inn or 0) + part.inn
	end
	if part.out ~= nil then
		into.out = (into.out or 0) + part.out
	end
	if part.model and not into.model then
		into.model = part.model
	end
end

local function blank(): sessions.Part
	return { tokens = nil, ai = nil }
end

-- The checkout a Kimi session was started in, from its state.json. Nil when the layout does not say.
local function kimiCwd(wire: string): string?
	local dir = string.match(wire, "^(.*)/agents/main/wire%.jsonl$")
	if not dir then
		return nil
	end
	local body = text(`{dir}/state.json`)
	if not body then
		return nil
	end
	local cwd = string.match(body, '"cwd":"([^"]*)"')
	if not cwd or cwd == "" then
		return nil
	end
	return (string.gsub(cwd, "/+$", ""))
end

local function samePath(a: string, b: string): boolean
	return (string.gsub(a, "/+$", "")) == (string.gsub(b, "/+$", ""))
end

function sessionread.span(
	cwd: string,
	sinceIso: string,
	sinceUnix: number,
	untilIso: string,
	untilUnix: number
): sessions.Read
	local h = home()
	local found: { sessions.Found } = {}
	local claudeDir = `{h}/.claude/projects/{string.gsub(cwd, "/", "-")}`
	local claude = blank()
	local claudeSaw = false
	for _, path in filesUnder(claudeDir, ".jsonl", sinceUnix) do
		local body = text(path)
		local part = if body then sessions.claude(body, sinceIso, untilIso) else nil
		if part then
			claudeSaw = true
			add(claude, part)
		end
	end
	table.insert(found, { cli = "claude", part = if claudeSaw then claude else nil })
	local grokDir = `{h}/.grok/sessions/{sessionread.encode(cwd)}`
	local grok = blank()
	local grokSaw = false
	for _, path in filesUnder(grokDir, "updates.jsonl", sinceUnix) do
		local body = text(path)
		local part = if body then sessions.grokUpdates(body, sinceUnix, untilUnix) else nil
		if part then
			grokSaw = true
			add(grok, part)
		end
	end
	for _, path in filesUnder(grokDir, "events.jsonl", sinceUnix) do
		local body = text(path)
		local part = if body then sessions.grokEvents(body, sinceIso, untilIso) else nil
		if part then
			grokSaw = true
			add(grok, part)
		end
	end
	table.insert(found, { cli = "grok", part = if grokSaw then grok else nil })
	local cursorKey = string.gsub(string.gsub(cwd, "^/", ""), "/", "-")
	local cursorDir = `{h}/.cursor/projects/{cursorKey}/agent-transcripts`
	local cursor = blank()
	local cursorSaw = false
	for _, path in filesUnder(cursorDir, ".jsonl", sinceUnix) do
		local body = text(path)
		local part = if body then sessions.cursor(body) else nil
		if part then
			cursorSaw = true
			add(cursor, part)
		end
	end
	table.insert(found, { cli = "agent", part = if cursorSaw then cursor else nil })
	local fromEnv = process.env.PICKMAN_KIMI_SESSIONS
	local kimiRoot = if fromEnv ~= nil and fromEnv ~= "" then fromEnv else `{h}/.kimi-code/sessions`
	local kimi = blank()
	local kimiSaw = false
	for _, path in filesUnder(kimiRoot, "wire.jsonl", sinceUnix) do
		local cwdOf = kimiCwd(path)
		if cwdOf ~= nil and samePath(cwdOf, cwd) then
			local body = text(path)
			local part = if body then sessions.kimi(body) else nil
			if part then
				kimiSaw = true
				add(kimi, part)
			end
		end
	end
	table.insert(found, { cli = "kimi", part = if kimiSaw then kimi else nil })
	return sessions.combine(found)
end

-- The session that is running this command, in this checkout. Not a time span, and not every file in the folder.
function sessionread.running(): sessions.Read
	local cwd = (string.gsub(process.cwd, "/+$", ""))
	local h = home()
	local found: { sessions.Found } = {}
	local wideSince = "1970-01-01T00:00:00.000Z"
	local wideUntil = "9999-12-31T23:59:59.999Z"
	local claude = blank()
	local claudeSaw = false
	local sid = process.env.CLAUDE_CODE_SESSION_ID
	if sid ~= nil and sid ~= "" then
		local dir = `{h}/.claude/projects/{string.gsub(cwd, "/", "-")}`
		local path = `{dir}/{sid}.jsonl`
		if not fs.isFile(path) then
			path = `{dir}/{sid}`
		end
		local body = text(path)
		local part = if body then sessions.claude(body, wideSince, wideUntil) else nil
		if part then
			claudeSaw = true
			add(claude, part)
		end
	end
	table.insert(found, { cli = "claude", part = if claudeSaw then claude else nil })
	table.insert(found, { cli = "grok", part = nil })
	table.insert(found, { cli = "agent", part = nil })
	local kimi = blank()
	local kimiSaw = false
	local kid = process.env.KIMI_SESSION_ID
	if kid == nil or kid == "" then
		kid = process.env.KIMI_CODE_SESSION_ID
	end
	if kid ~= nil and kid ~= "" then
		local fromEnv = process.env.PICKMAN_KIMI_SESSIONS
		local kimiRoot = if fromEnv ~= nil and fromEnv ~= "" then fromEnv else `{h}/.kimi-code/sessions`
		local needle = if string.sub(kid, 1, 8) == "session_" then kid else "session_" .. kid
		for _, path in filesUnder(kimiRoot, "wire.jsonl", 0) do
			local dir = string.match(path, "^(.*)/agents/main/wire%.jsonl$")
			local name = if dir then string.match(dir, "([^/]+)$") else nil
			local cwdOf = kimiCwd(path)
			if (name == kid or name == needle) and cwdOf ~= nil and samePath(cwdOf, cwd) then
				local body = text(path)
				local part = if body then sessions.kimi(body) else nil
				if part then
					kimiSaw = true
					add(kimi, part)
				end
			end
		end
	end
	table.insert(found, { cli = "kimi", part = if kimiSaw then kimi else nil })
	return sessions.combine(found)
end

-- f0399: Claude Code's folder for a checkout: every character outside letters, digits and "-" becomes "-"
-- (a dot too: `.worktree/x` is `--worktree-x`). The older spelling, which keeps dots, is tried second.
function sessionread.claudeDirs(cwd: string): { string }
	local base = `{home()}/.claude/projects/`
	local strict = base .. (string.gsub(cwd, "[^%w%-]", "-"))
	local loose = base .. (string.gsub(cwd, "/", "-"))
	return if strict == loose then { strict } else { strict, loose }
end

-- f0399: a name for the session running this command, or "" when it cannot be named. Claude Code is named only
-- when its transcript for this checkout exists, so an id inherited from another checkout's session names nothing.
function sessionread.id(): string
	local cwd = (string.gsub(process.cwd, "/+$", ""))
	local sid = process.env.CLAUDE_CODE_SESSION_ID
	if sid ~= nil and sid ~= "" then
		for _, dir in sessionread.claudeDirs(cwd) do
			if fs.isFile(`{dir}/{sid}.jsonl`) or fs.isFile(`{dir}/{sid}`) then
				return `claude:{sid}`
			end
		end
	end
	local kid = process.env.KIMI_SESSION_ID
	if kid == nil or kid == "" then
		kid = process.env.KIMI_CODE_SESSION_ID
	end
	if kid ~= nil and kid ~= "" then
		-- the same checkout test as running(): a Kimi id inherited from another checkout names nothing
		local fromEnv = process.env.PICKMAN_KIMI_SESSIONS
		local kimiRoot = if fromEnv ~= nil and fromEnv ~= "" then fromEnv else `{home()}/.kimi-code/sessions`
		local needle = if string.sub(kid, 1, 8) == "session_" then kid else "session_" .. kid
		for _, path in filesUnder(kimiRoot, "wire.jsonl", 0) do
			local dir = string.match(path, "^(.*)/agents/main/wire%.jsonl$")
			local name = if dir then string.match(dir, "([^/]+)$") else nil
			local cwdOf = kimiCwd(path)
			if (name == kid or name == needle) and cwdOf ~= nil and samePath(cwdOf, cwd) then
				return `kimi:{kid}`
			end
		end
	end
	return ""
end

-- This row does not carry wall or cpu (the measure buffer does). The reading says which of tokens and ai it had.
function sessionread.flags(reading: sessions.Read): string
	local have: { [string]: boolean } = { wall = true, cpu = true }
	local out = { "wall", "cpu" }
	if reading.unmeasured then
		for part in string.gmatch(reading.unmeasured, "[^,]+") do
			if not have[part] then
				have[part] = true
				table.insert(out, part)
			end
		end
	end
	return table.concat(out, ",")
end

return sessionread
