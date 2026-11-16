--!strict
-- c0175 AC3: the `agy-cli` adapter. Its command line, and its reader of the stream, from lines recorded from agy 1.5.7 on
-- 2026-11-15 (E1, E2, E3 in the issue): the token count, the tool steps that are running, the session, a failed step and a quota
-- failure. Pure: lines in, a count and an outcome out. New exports are read through `any`.
local adapters = require("@znile/engine/adapters")
local t = require("@tests/lib/t")

local CONV = "42ff9e41-9cbe-4ae1-b516-6596a9b79704"
-- a step that ran one shell command (init's tool list left out)
local INIT =
	`\{"event":"init","conversation_id":"{CONV}","init":\{"model":"gemini-3.8-flash-low","cwd":"/tmp/x","permission_mode":"always-proceed"}}`
local USER =
	`\{"event":"step_update","step_update":\{"conversation_id":"{CONV}","step_index":0,"state":"DONE","step_type":"user_input"}}`
local STEP1 =
	`\{"event":"step_update","step_update":\{"conversation_id":"{CONV}","step_index":1,"state":"DONE","step_type":"agent_response","duration_seconds":1.68,"usage":\{"input_tokens":8826,"output_tokens":35,"thinking_tokens":0,"cache_read_tokens":0,"total_tokens":8861}}}`
local TOOL_ON =
	`\{"event":"step_update","step_update":\{"conversation_id":"{CONV}","step_index":2,"state":"ACTIVE","step_type":"tool","tool_name":"run_command","tool_info":\{"name":"run_command","parameters":\{"CommandLine":"echo hi"}}}}`
local TOOL_OFF =
	`\{"event":"step_update","step_update":\{"conversation_id":"{CONV}","step_index":2,"state":"DONE","step_type":"tool","tool_name":"run_command","duration_seconds":0.05,"tool_info":\{"name":"run_command","parameters":\{"CommandLine":"echo hi"},"output":"hi"}}}`
local TEXT_ON =
	`\{"event":"step_update","step_update":\{"conversation_id":"{CONV}","step_index":3,"state":"ACTIVE","step_type":"agent_response","text_delta":"done"}}`
local STEP3 =
	`\{"event":"step_update","step_update":\{"conversation_id":"{CONV}","step_index":3,"state":"DONE","step_type":"agent_response","text_delta":"\\n","usage":\{"input_tokens":2163,"output_tokens":1,"thinking_tokens":0,"cache_read_tokens":6785,"total_tokens":2164}}}`
local RESULT =
	`\{"event":"result","result":\{"conversation_id":"{CONV}","status":"SUCCESS","response":"done\\n","duration_seconds":3.35,"num_turns":1,"usage":\{"input_tokens":10989,"output_tokens":36,"thinking_tokens":0,"cache_read_tokens":6785,"total_tokens":11025}}}`
-- E3: the CLI refuses a model it does not know
local BAD_MODEL =
	[[{"event":"result","result":{"conversation_id":"","status":"ERROR","response":"","error":"invalid model selection (--model \"nosuch-model\" --effort \"\"): model nosuch-model is not recognized as a known model or custom model in settings","duration_seconds":0,"num_turns":0,"usage":{"input_tokens":0,"output_tokens":0,"thinking_tokens":0,"cache_read_tokens":0,"total_tokens":0},"finished_reason":"error"}}]]
local NO_EFFORT =
	[[{"event":"result","result":{"conversation_id":"","status":"ERROR","response":"","error":"invalid model selection (--model \"gemini-3.8-flash\" --effort \"max\"): gemini-3.8-flash has no \"max\" effort (available: low, medium, high)","duration_seconds":0,"num_turns":0,"usage":{"input_tokens":0,"output_tokens":0,"thinking_tokens":0,"cache_read_tokens":0,"total_tokens":0},"finished_reason":"error"}}]]
local QUOTA =
	[[{"event":"result","result":{"conversation_id":"c1","status":"ERROR","response":"","error":"RESOURCE_EXHAUSTED: quota exceeded for this model, try again later","finished_reason":"error"}}]]

local function feedAll(lines: { string }): any
	local adapter = adapters.get("agy-cli")
	local acc = adapters.newAcc()
	for _, line in lines do
		adapter.feed(acc, line)
	end
	return acc
end

return t.spec("c0175 the agy-cli adapter", function(it)
	it(
		"AC3: the adapter is agy's local runtime, not call-capped, and starts agy headless with its permission-skipping flag",
		function()
			local a = adapters.get("agy-cli")
			t.expect(a.cli).toBe("agy")
			t.expect(a.runtime).toBe("agy-cli")
			t.expect(a.callCapped).toBe(false)
			local argv = a.argv({
				prompt = "do the thing",
				model = "claude-opus-5-5",
				effort = "high",
				cwd = "/work",
				session = "s1",
			})
			t.expect(argv).toEqual({
				"agy",
				"-p",
				"do the thing",
				"--output-format",
				"stream-json",
				"--model",
				"claude-opus-5-5",
				"--dangerously-skip-permissions",
				"--effort",
				"high",
			})
		end
	)

	it(
		"AC3: no effort on the stage means no --effort flag, and the model is passed as the bare id",
		function()
			local argv = adapters
				.get("agy-cli")
				.argv({ prompt = "p", model = "gemini-3.8-flash", cwd = "/work", session = "s" })
			t.expect(table.find(argv, "--effort")).toBe(nil)
			t.expect(argv[table.find(argv, "--model") :: number + 1]).toBe("gemini-3.8-flash")
			t.expect(table.find(argv, "--dangerously-skip-permissions") ~= nil).toBe(true)
			-- the process directory is the work directory (agy has no --cwd), and nothing waits on a print timeout of its own
			t.expect(table.find(argv, "--cwd")).toBe(nil)
			t.expect(table.find(argv, "--print-timeout")).toBe(nil)
		end
	)

	it(
		"AC3: it counts input + output of each finished step once, with cache reads left out, and the result's total as the final",
		function()
			local adapter = adapters.get("agy-cli")
			local acc = adapters.newAcc()
			for _, line in { INIT, USER, STEP1 } do
				adapter.feed(acc, line)
			end
			t.expect(acc.live).toBe(8861)
			adapter.feed(acc, STEP1) -- a repeated event is the same step
			t.expect(acc.live).toBe(8861)
			for _, line in { TOOL_ON, TOOL_OFF, TEXT_ON } do
				adapter.feed(acc, line)
			end
			t.expect(acc.live).toBe(8861) -- an ACTIVE step carries no usage
			adapter.feed(acc, STEP3)
			t.expect(acc.live).toBe(8861 + 2164)
			t.expect(acc.final).toBe(nil)
			adapter.feed(acc, RESULT)
			t.expect(acc.final).toBe(11025)
			t.expect(adapters.tokens(acc)).toBe(11025)
			local outcome, why = adapters.finish(acc, true, "", "agy-cli")
			t.expect(outcome).toBe("ok")
			t.expect(why).toBe("done")
		end
	)

	it("AC3: thinking tokens are inside output, never added twice", function()
		local line =
			[[{"event":"result","result":{"conversation_id":"c","status":"SUCCESS","response":"ok","usage":{"input_tokens":8816,"output_tokens":62,"thinking_tokens":61,"cache_read_tokens":0,"total_tokens":8878}}}]]
		t.expect(adapters.tokens(feedAll({ line }))).toBe(8878)
	end)

	it(
		"AC3: a tool step is running from ACTIVE to DONE, with its name and command on the note, and the session is the conversation",
		function()
			local adapter = adapters.get("agy-cli")
			local acc = adapters.newAcc()
			adapter.feed(acc, INIT)
			t.expect(acc.session).toBe(CONV)
			adapter.feed(acc, TOOL_ON)
			t.expect(adapters.toolRunning(acc)).toBe(true)
			t.expect(acc.note).toBe("run_command echo hi")
			adapter.feed(acc, TOOL_OFF)
			t.expect(adapters.toolRunning(acc)).toBe(false)
			-- two tools at once close one at a time
			local second = string.gsub(TOOL_ON, '"step_index":2', '"step_index":4')
			adapter.feed(acc, TOOL_ON)
			adapter.feed(acc, second)
			adapter.feed(acc, TOOL_OFF)
			t.expect(adapters.toolRunning(acc)).toBe(true)
		end
	)

	it(
		"AC3: a stream with no usage is ok and unmeasured, and a line that is not JSON is the CLI's own text",
		function()
			local acc = feedAll({ INIT, USER, "Connecting to Antigravity..." })
			t.expect(acc.cliText).toBe("Connecting to Antigravity...")
			local outcome, why = adapters.finish(acc, true, "", "agy-cli")
			t.expect(outcome).toBe("ok")
			t.expect(why).toBe("no token count (agy-cli)")
		end
	)

	it(
		"AC3: an error result fails the step with the CLI's words, whether the model or the effort was refused",
		function()
			for _, case in
				{
					{ BAD_MODEL, "model nosuch-model is not recognized" },
					{ NO_EFFORT, 'has no "max" effort' },
				}
			do
				local acc = feedAll({ case[1] })
				local outcome, why = adapters.finish(acc, false, "", "agy-cli")
				t.expect(outcome).toBe("failed")
				t.expect(string.find(why, case[2], 1, true) ~= nil).toBe(true)
				t.expect(adapters.tokens(acc)).toBe(0)
			end
		end
	)

	it("AC3: an error result that says quota is a quota failure, not a failed step", function()
		local acc = feedAll({ INIT, STEP1, QUOTA })
		local outcome, why = adapters.finish(acc, false, "", "agy-cli")
		t.expect(outcome).toBe("quota")
		t.expect(string.find(why, "quota exceeded", 1, true) ~= nil).toBe(true)
		-- what it spent first still counts
		t.expect(adapters.tokens(acc)).toBe(8861)
		-- and the words on stderr, with a non-zero exit, are quota too
		local plain = feedAll({ INIT })
		local o2 = adapters.finish(plain, false, "error: 429 Too Many Requests", "agy-cli")
		t.expect(o2).toBe("quota")
	end)
end)
