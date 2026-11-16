--!strict
-- c0175 AC6 and AC7: the runner starts a step on the new CLIs and acts on what they print. AC6: fake `agy` and `opencode`
-- scripts under .cache print the lines recorded from the real ones (E1 to E5): the step's tokens are recorded, a quota error
-- ends it as quota, a tool that opencode shows only on stderr gets the tool limit instead of the stall limit, and the token cap
-- kills it. AC7: a stream with no count is read back from the CLI's own session store (the user's ruling): `opencode export
-- <session>` for opencode, and not at all for a stream that already carried a count or a CLI that keeps no reader.
-- Fixture under .cache/c0175-runner. No real CLI starts.
local adapters = require("@znile/engine/adapters")
local fs = require("@lune/fs")
local process = require("@lune/process")
local runner = require("@znile/engine/runner")
local t = require("@tests/lib/t")

local U: any = require("@znile/engine/sessionusage")

local here = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local base = `{here}/.cache/c0175-runner`
local bin = `{base}/bin`
local log = `{base}/log`

local SES = "ses_e1d4805b5ffeSgAdiHRr6v58GE"
local STEP_FINISH =
	`\{"type":"step_finish","sessionID":"{SES}","part":\{"id":"p1","tokens":\{"input":6709,"output":38,"reasoning":0,"cache":\{"write":0,"read":5888}}}}`
local TEXT = `\{"type":"text","sessionID":"{SES}","part":\{"id":"t1","type":"text","text":"done"}}`
local TOOL =
	`\{"type":"tool_use","sessionID":"{SES}","part":\{"type":"tool","tool":"bash","state":\{"status":"completed","input":\{"command":"sleep 2"}}}}`
local EXPORT =
	`Exporting session: {SES}\n\{"info":\{"id":"{SES}","tokens":\{"input":6942,"output":40,"reasoning":3,"cache":\{"write":10,"read":18304}}},"messages":[]}`
local PERMISSION =
	'timestamp=2026-11-16T04:58:05.329Z level=INFO run=f6cdde9a message=evaluated permission=bash pattern="sleep 2" action.permission=* action.action=allow'

local AGY_OK = table.concat({
	[[{"event":"init","conversation_id":"c-1","init":{"model":"gemini-3.8-flash-low"}}]],
	[[{"event":"step_update","step_update":{"conversation_id":"c-1","step_index":1,"state":"DONE","step_type":"agent_response","usage":{"input_tokens":8826,"output_tokens":35,"thinking_tokens":0,"cache_read_tokens":0,"total_tokens":8861}}}]],
	[[{"event":"result","result":{"conversation_id":"c-1","status":"SUCCESS","response":"ok","usage":{"input_tokens":8826,"output_tokens":35,"thinking_tokens":0,"cache_read_tokens":0,"total_tokens":8861}}}]],
}, "\n")
local AGY_QUOTA =
	[[{"event":"result","result":{"conversation_id":"c-1","status":"ERROR","response":"","error":"RESOURCE_EXHAUSTED: quota exceeded for this model","finished_reason":"error"}}]]

local AGY_NOCOUNT = [[{"event":"init","conversation_id":"ses_agy9","init":{}}]]

local function mkdir(path: string)
	process.exec("mkdir", { "-p", path })
end

-- A fake `agy` or `opencode`: runs `body`, a shell script, with $1 the subcommand; the log records each call.
local function fake(name: string, body: string): string
	mkdir(bin)
	local path = `{bin}/{name}`
	fs.writeFile(path, `#!/bin/sh\necho "$@" >> "{log}"\n{body}\n`)
	process.exec("chmod", { "+x", path })
	return path
end

local function run(
	name: string,
	program: string,
	runtime: string,
	caps: { stall: number?, tool: number?, cap: number? }?
)
	local c: { stall: number?, tool: number?, cap: number? } = caps or {}
	local state = `{base}/state-{name}`
	if fs.isDir(state) then
		fs.removeDir(state)
	end
	mkdir(state)
	return runner.run({
		argv = { program, "run", "the prompt" },
		cwd = base,
		env = { PATH = process.env.PATH or "/usr/bin:/bin", HOME = base },
		adapter = adapters.get(runtime),
		cap = c.cap or 1000000,
		stallSeconds = c.stall or 30,
		toolSeconds = c.tool or 30,
		stateDir = state,
	})
end

local function logged(): string
	return if fs.isFile(log) then fs.readFile(log) else ""
end
local function reset()
	if fs.isDir(base) then
		fs.removeDir(base)
	end
	mkdir(base)
end

return t.spec("c0175 the runner on agy and opencode", function(it)
	it(
		"AC6: an agy step's tokens are recorded from its stream, and the session is its conversation",
		function()
			reset()
			local agy = fake("agy", `cat <<'EOF'\n{AGY_OK}\nEOF`)
			local r = run("agy-ok", agy, "agy-cli")
			t.expect(r.outcome).toBe("ok")
			t.expect(r.detail).toBe("done")
			t.expect(r.tokens).toBe(8861)
			t.expect(r.final).toBe(8861)
			t.expect(r.session).toBe("c-1")
		end
	)

	it("AC6: an agy error that says quota ends the step as quota, with the CLI's words", function()
		reset()
		local agy = fake("agy", `cat <<'EOF'\n{AGY_QUOTA}\nEOF\nexit 1`)
		local r = run("agy-quota", agy, "agy-cli")
		t.expect(r.outcome).toBe("quota")
		t.expect(string.find(r.detail, "quota exceeded", 1, true) ~= nil).toBe(true)
	end)

	it(
		"AC6: an opencode step's tokens are recorded, with cache reads left out, and the session is its sessionID",
		function()
			reset()
			local oc = fake("opencode", `cat <<'EOF'\n{TEXT}\n{STEP_FINISH}\nEOF`)
			local r = run("oc-ok", oc, "opencode-cli")
			t.expect(r.outcome).toBe("ok")
			t.expect(r.tokens).toBe(6709 + 38)
			t.expect(r.session).toBe(SES)
		end
	)

	it(
		"AC6: an opencode tool that shows only on stderr gets the tool limit: quiet past the stall limit, it is not stalled",
		function()
			reset()
			local oc =
				fake("opencode", `echo '{PERMISSION}' >&2\nsleep 2\ncat <<'EOF'\n{TOOL}\n{STEP_FINISH}\nEOF`)
			local r = run("oc-tool", oc, "opencode-cli", { stall = 1, tool = 20 })
			t.expect(r.outcome).toBe("ok")
			t.expect(r.tokens).toBe(6709 + 38)
		end
	)

	it("AC6: the same quiet with no tool on stderr is a stall", function()
		reset()
		local oc = fake("opencode", `sleep 20\ncat <<'EOF'\n{STEP_FINISH}\nEOF`)
		local r = run("oc-stall", oc, "opencode-cli", { stall = 1, tool = 20 })
		t.expect(r.outcome).toBe("stalled")
	end)

	it("AC6: an opencode step past max_tokens is killed as cap, on the running count", function()
		reset()
		local oc = fake(
			"opencode",
			[[i=0; while [ $i -lt 20 ]; do echo "{\"type\":\"step_finish\",\"part\":{\"id\":\"p$i\",\"tokens\":{\"input\":1000,\"output\":1}}}"; i=$((i+1)); done; sleep 20]]
		)
		local r = run("oc-cap", oc, "opencode-cli", { cap = 5000 })
		t.expect(r.outcome).toBe("cap")
		t.expect(string.find(r.detail, "max_tokens 5000", 1, true) ~= nil).toBe(true)
	end)

	it(
		"AC7: a stream with a session and no count is read back from opencode's own store: export gives the session's tokens",
		function()
			reset()
			local oc = fake(
				"opencode",
				`if [ "$1" = export ]; then cat <<'EOF'\n{EXPORT}\nEOF\nexit 0; fi\ncat <<'EOF'\n{TEXT}\nEOF`
			)
			local r = run("oc-export", oc, "opencode-cli")
			t.expect(r.outcome).toBe("ok")
			t.expect(r.detail).toBe("done")
			t.expect(r.tokens).toBe(6942 + 10 + 40 + 3) -- input + cache writes + output + reasoning, cache reads left out
			t.expect(string.find(logged(), `export {SES}`, 1, true) ~= nil).toBe(true)
		end
	)

	it("AC7: the store is not asked when the stream already carried a count", function()
		reset()
		local oc = fake(
			"opencode",
			`if [ "$1" = export ]; then cat <<'EOF'\n{EXPORT}\nEOF\nexit 0; fi\ncat <<'EOF'\n{TEXT}\n{STEP_FINISH}\nEOF`
		)
		local r = run("oc-counted", oc, "opencode-cli")
		t.expect(r.tokens).toBe(6709 + 38)
		t.expect((string.find(logged(), "export", 1, true))).toBe(nil)
	end)

	it("AC7: a store that cannot be read leaves the step ok and unmeasured", function()
		reset()
		local failing = fake(
			"opencode",
			`if [ "$1" = export ]; then echo 'boom' >&2; exit 1; fi\ncat <<'EOF'\n{TEXT}\nEOF`
		)
		local r = run("oc-fail", failing, "opencode-cli")
		t.expect(r.outcome).toBe("ok")
		t.expect(r.detail).toBe("no token count (opencode-cli)")
		t.expect(r.tokens).toBe(0)
		local junk = fake(
			"opencode",
			`if [ "$1" = export ]; then echo 'not json'; exit 0; fi\ncat <<'EOF'\n{TEXT}\nEOF`
		)
		local r2 = run("oc-junk", junk, "opencode-cli")
		t.expect(r2.detail).toBe("no token count (opencode-cli)")
	end)

	it(
		"AC7: the reader of an export text: the heading is skipped, the tokens become one step_finish line, and anything else gives none",
		function()
			local line = U.opencodeLine(EXPORT)
			t.expect(type(line)).toBe("string")
			local acc = adapters.newAcc()
			adapters.get("opencode-cli").feed(acc, line)
			t.expect(adapters.tokens(acc)).toBe(6942 + 10 + 40 + 3)
			t.expect(U.opencodeLine("Exporting session: x\n{}")).toBe(nil)
			t.expect(U.opencodeLine('{"info":{"id":"x"}}')).toBe(nil)
			t.expect(U.opencodeLine("no session here")).toBe(nil)
			t.expect(U.opencodeLine("")).toBe(nil)
		end
	)

	it(
		"AC7: only kimi and opencode keep a reader: agy's conversations are protobuf, so its steps stay unmeasured",
		function()
			reset()
			t.expect(U.lines("agy-cli", "ses_agy9", `{base}/no-such-agy`, {}, base)).toEqual({})
			t.expect(U.lines("claude-cli", "ses_s", `{base}/no-such-claude`, {}, base)).toEqual({})
			t.expect(U.lines("opencode-cli", "", `{base}/no-such-opencode`, {}, base)).toEqual({})
			-- an id that is not an opencode session id never reaches the CLI
			t.expect(U.lines("opencode-cli", "--help", `{base}/no-such-opencode`, {}, base)).toEqual({})
			local agy = fake("agy", `cat <<'EOF'\n{AGY_NOCOUNT}\nEOF`)
			local r = run("agy-none", agy, "agy-cli")
			t.expect(r.outcome).toBe("ok")
			t.expect(r.detail).toBe("no token count (agy-cli)")
			t.expect((string.find(logged(), "export", 1, true))).toBe(nil)
		end
	)
end)
