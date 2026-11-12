--!strict
-- A headless kimi step prints a session id and no usage. The runner reads that
-- session's wire and counts its usage.record lines. A missing wire is ok and
-- unmeasured. A stream that already carried a count is not counted again.
local adapters = require("@znile/engine/adapters")
local fs = require("@lune/fs")
local kimisession = require("@znile/engine/kimisession")
local process = require("@lune/process")
local runner = require("@znile/engine/runner")
local t = require("@tests/lib/t")

local here = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local base = `{here}/.cache/kimi-wire`
local WIRE =
	[[{"type":"usage.record","usage":{"inputOther":2061,"output":300,"inputCacheRead":15104,"inputCacheCreation":0}}]]

local function mkdir(path: string)
	process.exec("mkdir", { "-p", path })
end

local function wireAt(root: string, sessionId: string, text: string)
	local dir = `{root}/wd/{sessionId}/agents/main`
	mkdir(dir)
	fs.writeFile(`{dir}/wire.jsonl`, text .. "\n")
end

local function runKimi(script: string, sessions: string)
	mkdir(base)
	local saved = process.env.PICKMAN_KIMI_SESSIONS
	process.env.PICKMAN_KIMI_SESSIONS = sessions
	local state = `{base}/state`
	mkdir(state)
	local result = runner.run({
		argv = { "sh", "-c", script },
		cwd = base,
		env = { PATH = process.env.PATH or "/usr/bin:/bin" },
		adapter = adapters.get("kimi-cli"),
		cap = 1000000,
		stallSeconds = 30,
		toolSeconds = 30,
		stateDir = state,
	})
	process.env.PICKMAN_KIMI_SESSIONS = if saved == nil then "" else saved
	return result
end

return t.spec("kimi's session wire supplies the token count the stream omits", function(it)
	it("reads a wire under the sessions root and refuses a walk deeper than six", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		mkdir(base)
		t.expect(kimisession.read(`{base}/missing`, "session_abc")).toBe(nil)
		t.expect(kimisession.read(base, "")).toBe(nil)
		wireAt(`{base}/sessions`, "session_abc", WIRE)
		local text = kimisession.read(`{base}/sessions`, "session_abc")
		t.expect(text ~= nil and string.find(text :: string, "usage.record", 1, true) ~= nil).toBe(true)
		local deep = `{base}/deep`
		local path = deep
		for n = 1, 7 do
			path ..= `/d{n}`
		end
		mkdir(`{path}/session_deep/agents/main`)
		fs.writeFile(`{path}/session_deep/agents/main/wire.jsonl`, WIRE .. "\n")
		t.expect(kimisession.read(deep, "session_deep")).toBe(nil)
	end)

	it("counts the wire after a stream that only named the session", function()
		wireAt(`{base}/sessions`, "session_abc", WIRE)
		local hint =
			[[printf '%s\n' '{"role":"meta","type":"session.resume_hint","session_id":"session_abc"}' '{"role":"assistant","content":"pong"}']]
		local r = runKimi(hint, `{base}/sessions`)
		t.expect(r.outcome).toBe("ok")
		t.expect(r.detail).toBe("done")
		t.expect(r.tokens).toBe(2361)
	end)

	it("is ok and unmeasured when the session wire cannot be read", function()
		local hint =
			[[printf '%s\n' '{"role":"meta","type":"session.resume_hint","session_id":"session_gone"}']]
		mkdir(`{base}/empty`)
		local r = runKimi(hint, `{base}/empty`)
		t.expect(r.outcome).toBe("ok")
		t.expect(r.detail).toBe("no token count (kimi-cli)")
		t.expect(r.tokens).toBe(0)
	end)

	it("does not add the wire when the stream already carried a count", function()
		wireAt(`{base}/sessions`, "session_abc", WIRE)
		local both =
			[[printf '%s\n' '{"type":"usage.record","usage":{"inputOther":5,"output":1,"inputCacheCreation":0}}' '{"role":"meta","type":"session.resume_hint","session_id":"session_abc"}']]
		local r = runKimi(both, `{base}/sessions`)
		t.expect(r.outcome).toBe("ok")
		t.expect(r.tokens).toBe(6)
	end)
end)
