--!strict
-- Kimi's headless stream prints a session id and no usage. The usage records live in
-- that session's wire file, under a sessions root:
--   <root>/<workspace>/<session_id>/agents/main/wire.jsonl
-- This is the reader of that layout. `read` returns the wire's text, or nil when the
-- id is empty, the root is missing, or no wire file sits within six directories of it.
-- The runner reads $PICKMAN_KIMI_SESSIONS when that is set (a spec's fixture under
-- .cache), and otherwise $HOME/.kimi-code/sessions.

local fs = require("@lune/fs")

local kimisession = {}

local function baseName(dir: string): string
	return string.match(dir, "/([^/]+)$") or dir
end

local function walk(dir: string, id: string, depth: number): string?
	if depth > 6 or not fs.isDir(dir) then
		return nil
	end
	local name = baseName(dir)
	local wire = `{dir}/agents/main/wire.jsonl`
	if (name == id or name == "session_" .. id) and fs.isFile(wire) then
		return wire
	end
	local ok, names = pcall(fs.readDir, dir)
	if not ok then
		return nil
	end
	for _, child in names :: { string } do
		local found = walk(`{dir}/{child}`, id, depth + 1)
		if found ~= nil then
			return found
		end
	end
	return nil
end

function kimisession.read(root: string, sessionId: string): string?
	if sessionId == "" or not fs.isDir(root) then
		return nil
	end
	local path = walk(root, sessionId, 0)
	if path == nil then
		return nil
	end
	local ok, text = pcall(fs.readFile, path)
	return if ok then text :: string else nil
end

return kimisession
