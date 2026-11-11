--!strict
-- Reads the session files the CLIs in .models.toml leave on this machine, for one span, and reduces them with
-- sessions.luau. Claude Code writes a project jsonl (`~/.claude/projects/<cwd-with-slashes-as-dashes>`). Grok writes
-- `events.jsonl` and `updates.jsonl` under `~/.grok/sessions/<url-encoded cwd>`. The Cursor `agent` CLI writes
-- transcripts under `~/.cursor/projects/<cwd>` that, today, have neither timestamps nor token counts.
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
	return sessions.combine(found)
end

return sessionread
