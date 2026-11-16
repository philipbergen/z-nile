--!strict
-- c0175 AC4 and AC5: the `opencode-cli` adapter. AC4: the ledger id `opencode-<provider>-<model>` and opencode's
-- `<provider>/<model>`, and the command line. AC5: the reader of the stream, from lines recorded from opencode 1.18.31 on
-- 2026-11-15 (E4, E5 in the issue): the token count, a tool running, the session, a failed step and a quota failure.
-- Pure: lines in, a count and an outcome out. New exports are read through `any`.
local adapters = require("@znile/engine/adapters")
local ledger = require("@znile/engine/ledger")
local t = require("@tests/lib/t")

local A: any = adapters

local SES = "ses_e1d4805b5ffeSgAdiHRr6v58GE"
local START =
	`\{"type":"step_start","timestamp":1,"sessionID":"{SES}","part":\{"id":"prt_1","messageID":"msg_1","sessionID":"{SES}","type":"step-start"}}`
local TOOL =
	`\{"type":"tool_use","timestamp":2,"sessionID":"{SES}","part":\{"type":"tool","tool":"bash","callID":"call_1","state":\{"status":"completed","input":\{"command":"echo hi"},"output":"hi\\n","metadata":\{"exit":0},"title":"echo hi"},"id":"prt_2"}}`
local FINISH1 =
	`\{"type":"step_finish","timestamp":3,"sessionID":"{SES}","part":\{"id":"prt_3","reason":"tool-calls","type":"step-finish","tokens":\{"total":12635,"input":6709,"output":38,"reasoning":0,"cache":\{"write":0,"read":5888}},"cost":0.001}}`
local TEXT =
	`\{"type":"text","timestamp":4,"sessionID":"{SES}","part":\{"id":"prt_4","type":"text","text":"done","time":\{"start":1,"end":2}}}`
local FINISH2 =
	`\{"type":"step_finish","timestamp":5,"sessionID":"{SES}","part":\{"id":"prt_5","reason":"stop","type":"step-finish","tokens":\{"total":12651,"input":233,"output":2,"reasoning":0,"cache":\{"write":0,"read":12416}},"cost":0.0001}}`
-- E5: an unknown model, and a provider with no credentials
local UNKNOWN =
	`\{"type":"error","timestamp":9,"sessionID":"{SES}","error":\{"name":"UnknownError","data":\{"message":"Unexpected server error. Check server logs for details.","ref":"err_e2843eb3"}}}`
local LIMITED =
	`\{"type":"error","timestamp":9,"sessionID":"{SES}","error":\{"name":"APIError","data":\{"message":"Rate limit reached for deepseek-v4-pro: retry in 30s","statusCode":429}}}`
local STATUS_ONLY =
	`\{"type":"error","timestamp":9,"sessionID":"{SES}","error":\{"name":"APIError","data":\{"message":"Too Many Requests","statusCode":429}}}`
local LOGPREFIX = "timestamp=2026-11-16T06:07:11.753Z level=INFO run=befeb02f "
local LOGERR =
	'timestamp=2026-11-16T06:07:11.753Z level=ERROR run=befeb02f message="stream error" providerID=fake modelID=m session.id=ses_x small=false agent=build mode=primary error.error="AI_APICallError: Rate limit exceeded: too many requests"'
-- E5 (recorded against a loopback provider that answers 429): the log line `created … parentID=` of a subagent's session
local CREATED_PARENT =
	'timestamp=2026-11-16T06:06:29.794Z level=INFO run=9e6b6f7a message=created id=ses_e1d092a5dffe3Tw1Cu5JmfOwXI slug=swift-panda version=1.18.31 projectID=6dda path="" workspaceID=undefined parentID=undefined title="New session" agent=undefined'
local CREATED_CHILD =
	'timestamp=2026-11-16T06:06:30.624Z level=INFO run=9e6b6f7a message=created id=ses_e1d09271fffeT7DtBgHC6Zrm9I slug=neon-moon version=1.18.31 projectID=6dda path="" workspaceID=undefined parentID=ses_e1d092a5dffe3Tw1Cu5JmfOwXI title="child (@general subagent)" agent=undefined'
local BODY_429 =
	`\{"type":"error","sessionID":"{SES}","error":\{"name":"APIError","data":\{"message":"Provider returned error","responseBody":"\{\\"error\\":\{\\"code\\":\\"rate_limit_exceeded\\"}}"}}}`
local STATUS_429 =
	`\{"type":"error","sessionID":"{SES}","error":\{"name":"APIError","data":\{"message":"Provider returned error","statusCode":429}}}`
local PERMISSION =
	'timestamp=2026-11-16T04:58:05.329Z level=INFO run=f6cdde9a message=evaluated permission=bash pattern="sleep 6" action.permission=* action.action=allow action.pattern=*'

local function feedAll(lines: { string }): any
	local adapter = adapters.get("opencode-cli")
	local acc = adapters.newAcc()
	for _, line in lines do
		adapter.feed(acc, line)
	end
	return acc
end

return t.spec("c0175 the opencode-cli adapter", function(it)
	it("AC4: opencodeModel turns the ledger id into opencode's provider/model", function()
		t.expect(A.opencodeModel("opencode-deepseek-deepseek-v4-pro")).toBe("deepseek/deepseek-v4-pro")
		t.expect(A.opencodeModel("opencode-deepseek-deepseek-flash")).toBe("deepseek/deepseek-flash")
		t.expect(A.opencodeModel("opencode-xai-grok-4.7")).toBe("xai/grok-4.7")
		t.expect(A.opencodeModel("opencode-opencode-big-pickle")).toBe("opencode/big-pickle")
		t.expect(A.opencodeModel("opencode-opencode-deepseek-v4.1-flash-free"))
			.toBe("opencode/deepseek-v4.1-flash-free")
		-- a hyphen in a provider's name is an underscore in the id
		t.expect(A.opencodeModel("opencode-github_copilot-gpt-5")).toBe("github-copilot/gpt-5")
		-- an id that is not one is passed as it is, for the CLI to refuse
		t.expect(A.opencodeModel("deepseek-v4-pro")).toBe("deepseek-v4-pro")
	end)

	it(
		"AC4: every id the ledger takes: opencode ids are plain ledger ids, and none is another CLI's id",
		function()
			for _, id in
				{
					"opencode-deepseek-deepseek-v4-pro",
					"opencode-xai-grok-4.7",
					"opencode-opencode-big-pickle",
					"opencode-github_copilot-gpt-5",
				}
			do
				t.expect(ledger.isModel(id)).toBe(true)
				t.expect(string.sub(id, 1, 9)).toBe("opencode-")
			end
		end
	)

	it(
		"AC4: the adapter is opencode's local runtime and starts opencode headless, json, auto-approving, in the work directory",
		function()
			local a = adapters.get("opencode-cli")
			t.expect(a.cli).toBe("opencode")
			t.expect(a.runtime).toBe("opencode-cli")
			t.expect(a.callCapped).toBe(false)
			local argv = a.argv({
				prompt = "do the thing",
				model = "opencode-deepseek-deepseek-v4-pro",
				effort = "high",
				cwd = "/work",
				session = "s1",
			})
			t.expect(argv).toEqual({
				"opencode",
				"run",
				"do the thing",
				"-m",
				"deepseek/deepseek-v4-pro",
				"--format",
				"json",
				"--auto",
				"--dir",
				"/work",
				"--print-logs",
				"--log-level",
				"INFO",
				"--variant",
				"high",
			})
		end
	)

	it("AC4: no effort on the stage means no --variant", function()
		local argv = adapters.get("opencode-cli").argv({
			prompt = "p",
			model = "opencode-xai-grok-4.7",
			cwd = "/work",
			session = "s",
		})
		t.expect(table.find(argv, "--variant")).toBe(nil)
		t.expect(table.find(argv, "xai/grok-4.7") ~= nil).toBe(true)
		t.expect(table.find(argv, "--auto") ~= nil).toBe(true)
	end)

	it(
		"AC5: it counts input + cache writes + output + reasoning of each finished step once, with cache reads left out",
		function()
			local adapter = adapters.get("opencode-cli")
			local acc = adapters.newAcc()
			for _, line in { START, TOOL, FINISH1 } do
				adapter.feed(acc, line)
			end
			t.expect(acc.live).toBe(6709 + 38)
			adapter.feed(acc, FINISH1) -- the same part again is the same step
			t.expect(acc.live).toBe(6709 + 38)
			for _, line in { START, TEXT, FINISH2 } do
				adapter.feed(acc, line)
			end
			t.expect(adapters.tokens(acc)).toBe(6709 + 38 + 233 + 2)
			local outcome, why = adapters.finish(acc, true, "", "opencode-cli")
			t.expect(outcome).toBe("ok")
			t.expect(why).toBe("done")
			local rich = feedAll({
				`\{"type":"step_finish","sessionID":"{SES}","part":\{"id":"a","tokens":\{"input":100,"output":10,"reasoning":5,"cache":\{"write":20,"read":9000}}}}`,
			})
			t.expect(adapters.tokens(rich)).toBe(135)
		end
	)

	it("AC5: the session is the sessionID, and a step that printed no count is ok and unmeasured", function()
		local acc = feedAll({ START, TEXT })
		t.expect(acc.session).toBe(SES)
		t.expect(acc.note).toBe("done")
		local outcome, why = adapters.finish(acc, true, "", "opencode-cli")
		t.expect(outcome).toBe("ok")
		t.expect(why).toBe("no token count (opencode-cli)")
	end)

	it(
		"AC5: a tool is running from its permission check on stderr until the step finishes, because stdout shows it only once done",
		function()
			local adapter = adapters.get("opencode-cli")
			local feedErr = (adapter :: any).feedErr
			t.expect(type(feedErr)).toBe("function")
			local acc = adapters.newAcc()
			adapter.feed(acc, START)
			t.expect(adapters.toolRunning(acc)).toBe(false)
			feedErr(
				acc,
				'timestamp=2026-11-16T04:58:03.934Z level=INFO run=f6cdde9a message="llm runtime selected" llm.provider=deepseek'
			)
			t.expect(adapters.toolRunning(acc)).toBe(false)
			feedErr(acc, PERMISSION)
			t.expect(adapters.toolRunning(acc)).toBe(true)
			adapter.feed(acc, TOOL)
			t.expect(adapters.toolRunning(acc)).toBe(false)
			t.expect(acc.note).toBe("bash echo hi")
			feedErr(acc, PERMISSION)
			t.expect(adapters.toolRunning(acc)).toBe(true)
			adapter.feed(acc, FINISH1)
			t.expect(adapters.toolRunning(acc)).toBe(false)
			-- the other adapters read no stderr
			for _, rt in { "claude-cli", "grok-cli", "kimi-cli", "cursor-cli", "agy-cli" } do
				t.expect((adapters.get(rt) :: any).feedErr).toBe(nil)
			end
		end
	)

	it("AC5: an error event fails the step with the CLI's message", function()
		local acc = feedAll({ START, UNKNOWN })
		local outcome, why = adapters.finish(acc, false, "", "opencode-cli")
		t.expect(outcome).toBe("failed")
		t.expect(string.find(why, "Unexpected server error", 1, true) ~= nil).toBe(true)
	end)

	it(
		"AC5: an error that says rate limit or too many requests is a quota failure, and a step that spent first keeps its count",
		function()
			for _, line in { LIMITED, STATUS_ONLY } do
				local acc = feedAll({ START, FINISH1, line })
				local outcome = adapters.finish(acc, false, "", "opencode-cli")
				t.expect(outcome).toBe("quota")
				t.expect(adapters.tokens(acc)).toBe(6709 + 38)
			end
		end
	)
	it(
		"AC4: every name opencode reaches is written in the ledger's alphabet and read back: / : @ _ and any other byte",
		function()
			for _, case in
				{
					{ "deepseek", "deepseek-v4-pro", "opencode-deepseek-deepseek-v4-pro" },
					{ "xai", "grok-4.7", "opencode-xai-grok-4.7" },
					{
						"openrouter",
						"anthropic/claude-3.5-sonnet:beta",
						"opencode-openrouter-anthropic_sclaude-3.5-sonnet_cbeta",
					},
					{
						"huggingface",
						"Qwen/Qwen3-Coder-480B@fp8",
						"opencode-huggingface-Qwen_sQwen3-Coder-480B_afp8",
					},
					{ "vercel", "openai/gpt_5_mini", "opencode-vercel-openai_sgpt__5__mini" },
					{ "github-copilot", "gpt-5", "opencode-github_copilot-gpt-5" },
					{ "x", "a b+c", "opencode-x-a_x20b_x2bc" },
				}
			do
				local id = A.opencodeId(case[1], case[2])
				t.expect(id).toBe(case[3])
				t.expect(ledger.isModel(id)).toBe(true)
				t.expect(A.opencodeModel(id)).toBe(`{case[1]}/{case[2]}`)
			end
			-- an escape no encoder writes is passed through for the CLI to refuse
			t.expect(A.opencodeModel("opencode-x-a_zb")).toBe("opencode-x-a_zb")
			t.expect(A.opencodeModel("opencode-x-a_")).toBe("opencode-x-a_")
		end
	)

	it(
		"AC4: the step's environment turns opencode's snapshots and title call off, and leaves the other CLIs' as they were",
		function()
			local env = (A.STEP_ENV :: any)["opencode-cli"]
			local ok, cfg = pcall(function()
				return require("@lune/serde").decode("json", env.OPENCODE_CONFIG_CONTENT)
			end)
			t.expect(ok).toBe(true)
			t.expect((cfg :: any).snapshot).toBe(false)
			t.expect((cfg :: any).agent.title.disable).toBe(true)
			-- subagents stay on (their tokens are read after the step): no permission is denied
			t.expect((cfg :: any).permission).toBe(nil)
			t.expect((A.STEP_ENV :: any)["claude-cli"].BASH_MAX_TIMEOUT_MS).toBe("7200000")
			t.expect((A.STEP_ENV :: any)["agy-cli"]).toBe(nil)
		end
	)

	it(
		"AC5: tools run in parallel: the first to finish does not hide a long sibling, and the step's end ends them all",
		function()
			local adapter = adapters.get("opencode-cli")
			local feedErr = (adapter :: any).feedErr
			local acc = adapters.newAcc()
			feedErr(acc, PERMISSION)
			feedErr(acc, PERMISSION)
			adapter.feed(acc, TOOL)
			t.expect(adapters.toolRunning(acc)).toBe(true) -- two started, one finished
			adapter.feed(acc, TOOL)
			t.expect(adapters.toolRunning(acc)).toBe(false)
			adapter.feed(acc, TOOL) -- a tool_use with nothing running does not go below zero
			feedErr(acc, PERMISSION)
			t.expect(adapters.toolRunning(acc)).toBe(true)
			-- a tool that checked two permissions stays running until the step ends: bounded by the tool limit
			feedErr(acc, PERMISSION)
			adapter.feed(acc, TOOL)
			t.expect(adapters.toolRunning(acc)).toBe(true)
			adapter.feed(acc, FINISH1)
			t.expect(adapters.toolRunning(acc)).toBe(false)
		end
	)

	it(
		"AC5: isLog tells opencode's log lines from the CLI's own text, and only a log line is a permission check",
		function()
			local adapter = adapters.get("opencode-cli") :: any
			t.expect(adapter.isLog(PERMISSION)).toBe(true)
			t.expect(adapter.isLog(LOGERR)).toBe(true)
			t.expect(adapter.isLog("Error: rate limit exceeded")).toBe(false)
			t.expect(adapter.isLog('evaluated permission=bash pattern="x"')).toBe(false)
			t.expect(adapter.isLog("")).toBe(false)
			-- the other adapters keep no log lines apart
			for _, rt in { "claude-cli", "grok-cli", "kimi-cli", "cursor-cli", "agy-cli" } do
				t.expect((adapters.get(rt) :: any).isLog).toBe(nil)
			end
		end
	)

	it(
		"AC5: a log line that quotes a quota word in a command is not a wait; the CLI's own stream error is",
		function()
			local adapter = adapters.get("opencode-cli")
			local feedErr = (adapter :: any).feedErr
			local acc = adapters.newAcc()
			feedErr(
				acc,
				LOGPREFIX
					.. 'message=evaluated permission=bash pattern="grep -n quota rate limit try again engine.luau"'
			)
			t.expect((acc :: any).waiting).toBe(nil)
			t.expect(acc.quota).toBe(nil)
			feedErr(acc, LOGERR)
			t.expect((acc :: any).waiting).toBe("AI_APICallError: Rate limit exceeded: too many requests")
			-- a stream error that is no quota error is not a wait
			local other = adapters.newAcc()
			feedErr(other, (string.gsub(LOGERR, "Rate limit exceeded: too many requests", "Unauthorized")))
			t.expect((other :: any).waiting).toBe(nil)
			-- the error line is quoted with the same prefix by a model's command: only the CLI's own ERROR line counts
			local quoted = adapters.newAcc()
			feedErr(
				quoted,
				LOGPREFIX
					.. 'message=evaluated permission=bash pattern="level=ERROR message="stream error" rate limit"'
			)
			t.expect((quoted :: any).waiting).toBe(nil)
		end
	)

	it(
		"AC5: a created line with a parentID names a child session (a subagent); one without does not",
		function()
			local adapter = adapters.get("opencode-cli")
			local feedErr = (adapter :: any).feedErr
			local acc = adapters.newAcc()
			feedErr(acc, CREATED_PARENT)
			t.expect(#(acc :: any).children).toBe(0)
			feedErr(acc, CREATED_CHILD)
			t.expect((acc :: any).children).toEqual({ "ses_e1d09271fffeT7DtBgHC6Zrm9I" })
			-- a grandchild is a child of the child: it is named too
			feedErr(acc, (string.gsub(CREATED_CHILD, "ses_e1d09271fffeT7DtBgHC6Zrm9I", "ses_grand1")))
			t.expect(#(acc :: any).children).toBe(2)
		end
	)

	it("AC5: an error whose message has no quota word but whose body or status says 429 is quota", function()
		for _, line in { BODY_429, STATUS_429 } do
			local acc = feedAll({ START, line })
			t.expect((adapters.finish(acc, false, "", "opencode-cli"))).toBe("quota")
		end
		-- opencode's and agy's own words
		for _, text in { "Free usage exceeded, subscribe to Go", "Resource exhausted", "RESOURCE_EXHAUSTED" } do
			local acc = feedAll({
				`\{"type":"error","sessionID":"{SES}","error":\{"name":"APIError","data":\{"message":"{text}"}}}`,
			})
			t.expect((adapters.finish(acc, false, "", "opencode-cli"))).toBe("quota")
		end
		-- an error with none of it is a failure
		t.expect((adapters.finish(feedAll({ START, UNKNOWN }), false, "", "opencode-cli"))).toBe("failed")
	end)
end)
