--!strict
-- c0117 AC6: one adapter per runtime. Each starts its CLI headless and unattended with the flags pinned here, and
-- reads its stream into one token count (input + cache writes + output, cache reads left out), the same for every
-- CLI, and a quota or error signal. The stream lines are the ones the CLIs printed in prep's probes (2026-10-21,
-- E1/E2), trimmed. Pure: adapters.luau.
local adapters = require("@znile/engine/adapters")
local t = require("@tests/lib/t")

local CLAUDE = {
	'{"type":"system","subtype":"init","session_id":"66c90db9"}',
	'{"type":"assistant","message":{"model":"claude-haiku-5-5","id":"msg_1","content":[{"type":"text","text":"ok"}],"usage":{"input_tokens":2,"cache_creation_input_tokens":9841,"cache_read_input_tokens":11228,"output_tokens":4}},"session_id":"66c90db9"}',
	'{"type":"assistant","message":{"model":"claude-haiku-5-5","id":"msg_1","content":[{"type":"tool_use","name":"Bash"}],"usage":{"input_tokens":2,"cache_creation_input_tokens":9841,"cache_read_input_tokens":11228,"output_tokens":4}},"session_id":"66c90db9"}',
	'{"type":"rate_limit_event","rate_limit_info":{"status":"allowed","rateLimitType":"five_hour","resetsAt":1792595400}}',
	'{"type":"result","subtype":"success","is_error":false,"usage":{"input_tokens":2,"cache_creation_input_tokens":9841,"cache_read_input_tokens":11228,"output_tokens":4},"modelUsage":{"claude-haiku-5-5":{"inputTokens":2,"outputTokens":4,"cacheReadInputTokens":11228,"cacheCreationInputTokens":9841}}}',
}
local GROK = {
	'{"type":"available_commands","commands":[]}',
	'{"type":"usage","usage":{"input_tokens":16114,"output_tokens":112,"cache_read_input_tokens":1536,"cache_creation_input_tokens":0,"reasoning_tokens":41}}',
	'{"type":"text","data":"done"}',
	'{"type":"usage","usage":{"input_tokens":296,"output_tokens":11,"cache_read_input_tokens":17536,"cache_creation_input_tokens":0,"reasoning_tokens":10}}',
	'{"type":"end","stopReason":"end_turn","sessionId":"01a15e63","usage":{"input_tokens":16410,"cache_read_input_tokens":19072,"cache_creation_input_tokens":0,"output_tokens":123,"reasoning_tokens":51,"total_tokens":35605}}',
}
local AGENT = {
	'{"type":"system","subtype":"init","session_id":"22eb88c2","model":"Grok 4.7 256K Low Fast"}',
	'{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"ok"}]},"session_id":"22eb88c2"}',
	'{"type":"result","subtype":"success","is_error":false,"result":"ok","session_id":"22eb88c2","usage":{"inputTokens":15155,"outputTokens":28,"cacheReadTokens":0,"cacheWriteTokens":0}}',
}

local function feed(runtime: string, lines: { string }): adapters.Acc
	local a = adapters.get(runtime)
	local acc = adapters.newAcc()
	for _, line in lines do
		a.feed(acc, line)
	end
	return acc
end
local function req(effort: string?): adapters.Request
	return { prompt = "PROMPT", model = "M", effort = effort, cwd = "/w/wt", session = "uuid-1" }
end
local function argv(runtime: string, effort: string?): { string }
	return adapters.get(runtime).argv(req(effort))
end
local function finish(acc: adapters.Acc, ok: boolean, stderr: string?): string
	return (adapters.finish(acc, ok, stderr or "", "x"))
end

return t.spec("c0117 adapters", function(it)
	it("claude runs -p with stream-json, the model, bypassed permissions and no prompts", function()
		t.expect(argv("claude-cli")).toEqual({
			"claude",
			"-p",
			"PROMPT",
			"--output-format",
			"stream-json",
			"--verbose",
			"--model",
			"M",
			"--permission-mode",
			"bypassPermissions",
			"--permission-prompts",
			"none",
			"--session-id",
			"uuid-1",
			"--settings",
			'{"sandbox":{"enabled":false}}',
		})
		local e = argv("claude-cli", "high")
		t.expect({ e[#e - 1], e[#e] }).toEqual({ "--effort", "high" })
		-- the remote runtimes are unproven (E7 to E9): only their program, the model and the prompt's delivery are
		-- pinned, so a fallback the executor takes keeps this case green
		local cloud = argv("claude-cloud")
		t.expect(cloud[1]).toBe("claude")
		t.expect(table.find(cloud, "--cloud") ~= nil).toBe(true)
		t.expect(table.find(cloud, "M") ~= nil).toBe(true)
		t.expect(table.find(cloud, "PROMPT") ~= nil).toBe(true)
	end)

	it("grok runs -p with streaming-json in the step's folder, auto-approved, with its session id", function()
		t.expect(argv("grok-cli")).toEqual({
			"grok",
			"-p",
			"PROMPT",
			"--output-format",
			"streaming-json",
			"-m",
			"M",
			"--always-approve",
			"--cwd",
			"/w/wt",
			"-s",
			"uuid-1",
		})
		local e = argv("grok-cli", "xhigh")
		t.expect({ e[#e - 1], e[#e] }).toEqual({ "--reasoning-effort", "xhigh" })
		local bot = argv("grok-bot", "xhigh")
		t.expect(bot[1]).toBe("grok")
		t.expect(table.find(bot, "M") ~= nil).toBe(true)
		t.expect(table.find(bot, "xhigh") ~= nil).toBe(true)
		t.expect(adapters.STDIN["grok-bot"]).toBe(true)
	end)

	it(
		"agent runs -p with stream-json, forced and trusted, its own sandbox off, in the step's workspace",
		function()
			t.expect(argv("cursor-cli")).toEqual({
				"agent",
				"-p",
				"--output-format",
				"stream-json",
				"--model",
				"M",
				"--force",
				"--trust",
				"--sandbox",
				"disabled",
				"--workspace",
				"/w/wt",
				"PROMPT",
			})
			t.expect(argv("cursor-cli", "high")[6]).toBe("M[effort=high]")
			local app = argv("cursor-app")
			t.expect(app[1]).toBe("agent")
			t.expect(table.find(app, "M") ~= nil).toBe(true)
			t.expect(adapters.STDIN["cursor-app"]).toBe(true)
			t.expect(adapters.STDIN["cursor-cli"]).toBe(nil)
		end
	)

	it("every runtime has an adapter of its own CLI, and no other name has one", function()
		for runtime, cli in
			{
				["claude-cli"] = "claude",
				["claude-cloud"] = "claude",
				["grok-cli"] = "grok",
				["grok-bot"] = "grok",
				["cursor-cli"] = "agent",
				["cursor-app"] = "agent",
			}
		do
			local a = adapters.get(runtime :: string)
			t.expect(a.cli).toBe(cli)
			t.expect(a.argv(req())[1]).toBe(cli)
		end
		t.expect((pcall(adapters.get, "cursor"))).toBe(false)
	end)

	it("claude: one message counted once at its usage, and the final count from modelUsage", function()
		local acc = feed("claude-cli", CLAUDE)
		t.expect(acc.live).toBe(2 + 9841 + 4)
		t.expect(acc.final).toBe(2 + 9841 + 4)
		t.expect(adapters.tokens(acc)).toBe(9847)
		t.expect(finish(acc, true)).toBe("ok")
		local two = feed("claude-cli", {
			CLAUDE[2],
			(string.gsub(CLAUDE[2], '"msg_1"', '"msg_2"')),
		})
		t.expect(two.live).toBe(2 * 9847)
	end)

	it("grok: a usage line per model call, and the end line's total", function()
		local acc = feed("grok-cli", GROK)
		t.expect(acc.live).toBe((16114 + 112) + (296 + 11))
		t.expect(acc.final).toBe(16410 + 123)
		t.expect(acc.session).toBe("01a15e63")
		t.expect(finish(acc, true)).toBe("ok")
	end)

	it("agent: an estimate while it runs, the result line's count at the end", function()
		local running = feed("cursor-cli", { AGENT[1], AGENT[2] })
		t.expect(running.final).toBe(nil)
		t.expect(running.live > 0).toBe(true)
		t.expect(adapters.get("cursor-cli").estimated).toBe(true)
		local acc = feed("cursor-cli", AGENT)
		t.expect(acc.final).toBe(15155 + 28)
		t.expect(adapters.tokens(acc)).toBe(15183)
	end)

	it("tracks the tool calls that are running, per CLI, for the tool limit", function()
		local c = feed("claude-cli", {
			'{"type":"assistant","message":{"id":"m","content":[{"type":"tool_use","id":"t1","name":"Bash"}]}}',
		})
		t.expect(adapters.toolRunning(c)).toBe(true)
		adapters
			.get("claude-cli")
			.feed(c, '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1"}]}}')
		t.expect(adapters.toolRunning(c)).toBe(false)
		local g = feed("grok-cli", { '{"type":"tool_call","toolCallId":"c1","status":"pending"}' })
		t.expect(adapters.toolRunning(g)).toBe(true)
		adapters.get("grok-cli").feed(g, '{"type":"tool_call_update","toolCallId":"c1","status":null}')
		t.expect(adapters.toolRunning(g)).toBe(true)
		adapters.get("grok-cli").feed(g, '{"type":"tool_call_update","toolCallId":"c1","status":"completed"}')
		t.expect(adapters.toolRunning(g)).toBe(false)
		local a = feed("cursor-cli", { '{"type":"tool_call","subtype":"started","call_id":"x"}' })
		t.expect(adapters.toolRunning(a)).toBe(true)
		adapters.get("cursor-cli").feed(a, '{"type":"tool_call","subtype":"completed","call_id":"x"}')
		t.expect(adapters.toolRunning(a)).toBe(false)
	end)

	it("only what the CLI itself prints is read for quota or a wait, never the model's words", function()
		local prose = feed("claude-cli", {
			'{"type":"assistant","message":{"id":"m","content":[{"type":"text","text":"rate limit: waiting for the gate, I will try again"}]}}',
		})
		t.expect(prose.quota).toBe(nil)
		t.expect(prose.cliText).toBe("")
		local raw = feed("cursor-cli", { "Usage limit reached, retrying in 60s" })
		t.expect(raw.cliText).toBe("Usage limit reached, retrying in 60s")
	end)

	it(
		"a quota or rate limit is quota: claude's rejected event, an error result, or a failed CLI's stderr",
		function()
			local rejected = feed("claude-cli", {
				'{"type":"rate_limit_event","rate_limit_info":{"status":"rejected","rateLimitType":"five_hour","resetsAt":1}}',
			})
			t.expect(rejected.quota ~= nil).toBe(true)
			t.expect(finish(rejected, false)).toBe("quota")
			local limit = feed("claude-cli", {
				'{"type":"result","subtype":"error_during_execution","is_error":true,"result":"Claude usage limit reached. Your limit will reset at 3pm"}',
			})
			t.expect(finish(limit, false)).toBe("quota")
			t.expect(finish(feed("grok-cli", {}), false, "Error: rate limit exceeded")).toBe("quota")
			t.expect(finish(feed("cursor-cli", {}), false, "HTTP 429 Too Many Requests")).toBe("quota")
			-- an allowed event is not quota
			t.expect(feed("claude-cli", { CLAUDE[4] }).quota).toBe(nil)
		end
	)

	it("any other failure is failed, and so is an exit 0 with no token count", function()
		t.expect(finish(feed("grok-cli", {}), false, "boom")).toBe("failed")
		local _, why = adapters.finish(feed("cursor-cli", { AGENT[2] }), true, "", "cursor-cli")
		t.expect(why).toBe("cursor-cli exited without a token count")
		t.expect(finish(feed("claude-cli", { CLAUDE[2] }), true)).toBe("failed")
		local errored = feed("cursor-cli", {
			'{"type":"result","subtype":"error","is_error":true,"result":"tool crashed","usage":{"inputTokens":1,"outputTokens":1}}',
		})
		t.expect(finish(errored, true)).toBe("failed")
	end)
end)
