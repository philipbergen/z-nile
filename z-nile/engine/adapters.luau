--!strict
-- One adapter per runtime (c0117): the command line that starts a model step headless and unattended, the reader of
-- its output stream (a token count as it runs, the final count, a quota or error signal), and the outcome. Pure: the
-- runner (runner.luau) starts the process and feeds this module its lines.
--
-- The token count is the same for every CLI: input + cache writes + output (reasoning included), cache reads left
-- out. Probed 2026-10-21 (c0117 E1, E2): `claude -p --output-format stream-json --verbose` gives `usage` on each
-- assistant message, a `rate_limit_event` per call and a final `result` with `modelUsage`; `grok -p --output-format
-- streaming-json` gives a `usage` line per model call and an `end` line with the total; `agent -p --output-format
-- stream-json` gives usage only on its final `result` line, so its step is capped by model calls instead.
local serde = require("@lune/serde")

local adapters = {}

export type Request = {
	prompt: string,
	model: string,
	effort: string?,
	cwd: string,
	session: string, -- a fresh UUID: grok's session id, the others' marker in the run state
}
export type Acc = {
	live: number, -- the running count (an estimate for agent)
	final: number?, -- the count the CLI reported at its end
	byMessage: { [string]: number },
	quota: string?, -- why the CLI is out of quota, when it said so
	errorText: string?,
	cliText: string, -- the last text the CLI itself printed (not the model's words): a stall's wait message
	open: { [string]: boolean }, -- the tool calls started and not finished yet
	calls: number, -- model calls seen (agent: distinct model_call_id values, and turns that carry none)
	callIds: { [string]: boolean },
	turns: number,
	inTurn: boolean,
	turnHasId: boolean,
	noIdTurns: number, -- turns in a row that carried no model_call_id
	unknown: string?, -- why the call cap can't be trusted on this stream (fail closed)
	session: string?,
}
export type Outcome = "ok" | "failed" | "quota"
export type Adapter = {
	cli: string,
	runtime: string,
	callCapped: boolean, -- no running token count: the step stops on max_calls, and the row takes the final total
	argv: (Request) -> { string },
	feed: (Acc, string) -> (),
}

-- What a CLI prints when it is out of quota or rate limited (any of these, case-insensitive).
adapters.QUOTA = {
	"rate limit",
	"rate_limit",
	"rate-limit",
	"usage limit",
	"quota",
	"insufficient credit",
	"insufficient balance",
	"out of credits",
	"limit reached",
	"too many requests",
	"status 429",
	"error 429",
	"http 429",
}
-- What a CLI prints while it waits for quota instead of failing: a stall after one of these is a quota failure.
adapters.WAITING = { "retrying in", "retry in", "waiting for", "try again", "resets at", "reset at" }

local function mentions(text: string, words: { string }): string?
	local lower = string.lower(text)
	for _, w in words do
		if string.find(lower, w, 1, true) then
			return w
		end
	end
	return nil
end
adapters.mentions = mentions

function adapters.newAcc(): Acc
	return {
		live = 0,
		final = nil,
		byMessage = {},
		quota = nil,
		errorText = nil,
		cliText = "",
		open = {},
		calls = 0,
		callIds = {},
		turns = 0,
		inTurn = false,
		turnHasId = false,
		noIdTurns = 0,
		unknown = nil,
		session = nil,
	}
end

local function num(v: any): number
	return if type(v) == "number" then v else 0
end

local function decode(line: string): { [string]: any }?
	if string.sub(line, 1, 1) ~= "{" then
		return nil
	end
	local ok, value = pcall(function()
		return serde.decode("json", line)
	end)
	return if ok and type(value) == "table" then value else nil
end

-- claude's and grok's usage objects (snake_case): input + cache writes + output.
local function snake(u: any): number
	if type(u) ~= "table" then
		return 0
	end
	return num(u.input_tokens) + num(u["cache_creation_input_tokens"]) + num(u.output_tokens)
end

local function sumLive(acc: Acc)
	local n = 0
	for _, v in acc.byMessage do
		n += v
	end
	acc.live = n
end

-- Whether a tool call is running: the stall timer gives way to the tool ceiling while one is (c0117 review 001 F8).
function adapters.toolRunning(acc: Acc): boolean
	return next(acc.open) ~= nil
end

local function claudeFeed(acc: Acc, line: string)
	local j = decode(line)
	if not j then
		acc.cliText = line
		return
	end
	if j.session_id then
		acc.session = j.session_id
	end
	if j.type == "assistant" and type(j.message) == "table" then
		local m = j.message
		local id = if type(m.id) == "string" then m.id else "message"
		-- every content block of one message repeats its usage: count the message once, at its largest
		acc.byMessage[id] = math.max(acc.byMessage[id] or 0, snake(m.usage))
		sumLive(acc)
		if type(m.content) == "table" then
			for _, block in m.content do
				if type(block) == "table" and block.type == "tool_use" and type(block.id) == "string" then
					acc.open[block.id] = true
				end
			end
		end
	elseif j.type == "user" and type(j.message) == "table" and type(j.message.content) == "table" then
		for _, block in j.message.content do
			if
				type(block) == "table"
				and block.type == "tool_result"
				and type(block.tool_use_id) == "string"
			then
				acc.open[block.tool_use_id] = nil
			end
		end
	elseif j.type == "rate_limit_event" and type(j.rate_limit_info) == "table" then
		local info = j.rate_limit_info
		if info.status == "rejected" then
			acc.quota = `rate limit rejected ({tostring(info.rateLimitType or "?")}, resets {tostring(
				info.resetsAt or "?"
			)})`
		end
	elseif j.type == "system" then
		-- the CLI's own notices (an API retry names its error): text the stall rule may read
		if type(j.error) == "string" or type(j.message) == "string" then
			acc.cliText = tostring(j.error or j.message)
		end
	elseif j.type == "result" then
		if type(j.modelUsage) == "table" then
			local n = 0
			for _, u in j.modelUsage do
				if type(u) == "table" then
					n += num(u.inputTokens) + num(u["cacheCreationInputTokens"]) + num(u.outputTokens)
				end
			end
			acc.final = n
		elseif type(j.usage) == "table" then
			acc.final = snake(j.usage)
		end
		if j.is_error == true or (type(j.subtype) == "string" and j.subtype ~= "success") then
			-- an error result is the CLI's report, not the model's prose
			local text = if type(j.result) == "string" then j.result else tostring(j.subtype)
			acc.errorText = text
			acc.cliText = text
			if mentions(text, adapters.QUOTA) then
				acc.quota = acc.quota or text
			end
		end
	end
end

local function grokFeed(acc: Acc, line: string)
	local j = decode(line)
	if not j then
		acc.cliText = line
		return
	end
	if j.type == "usage" then
		acc.live += snake(j.usage)
	elseif j.type == "end" then
		acc.final = snake(j.usage)
		if type(j.sessionId) == "string" then
			acc.session = j.sessionId
		end
	elseif j.type == "tool_call" and type(j.toolCallId) == "string" then
		acc.open[j.toolCallId] = true
	elseif j.type == "tool_call_update" and type(j.toolCallId) == "string" then
		if j.status == "completed" or j.status == "failed" then
			acc.open[j.toolCallId] = nil
		end
	elseif j.type == "error" or j.error ~= nil then
		local text = tostring(j.message or j.error or j.data or line)
		acc.errorText = text
		acc.cliText = text
		if mentions(text, adapters.QUOTA) then
			acc.quota = text
		end
	end
end

-- agent's line types (probes E1, E3): anything else is a stream the call cap can't be trusted on
local AGENT_TYPES =
	{ system = true, user = true, assistant = true, thinking = true, tool_call = true, result = true }
-- turns in a row with no model_call_id after which the call cap is unknown (fail closed: review 002 F8)
adapters.NO_ID_TURNS = 3

local function agentFeed(acc: Acc, line: string)
	local j = decode(line)
	if not j then
		acc.cliText = line
		acc.unknown = acc.unknown or "a line that is not JSON"
		return
	end
	if not AGENT_TYPES[j.type] then
		acc.unknown = acc.unknown or `a line of type {tostring(j.type)}`
	end
	if j.type == "result" then
		local u = j.usage
		if type(u) == "table" then
			acc.final = num(u.inputTokens) + num(u["cacheWriteTokens"]) + num(u.outputTokens)
		end
		if j.is_error == true then
			local text = tostring(j.result or j.subtype or "error")
			acc.errorText = text
			acc.cliText = text
			if mentions(text, adapters.QUOTA) then
				acc.quota = text
			end
		end
		return
	end
	if j.type == "user" then
		acc.inTurn = false
	end
	if j.type == "tool_call" and type(j.call_id) == "string" then
		if j.subtype == "started" then
			acc.open[j.call_id] = true
		elseif j.subtype == "completed" then
			acc.open[j.call_id] = nil
			acc.inTurn = false
		end
	end
	-- a turn starts at the first thinking or assistant line, or tool call started without a model_call_id, after a user
	-- line or a finished tool call: a model call, counted even when it carries no model_call_id (the fallback count;
	-- review 003 F7: a stream of bare tool calls is turns too)
	local bareTool = j.type == "tool_call" and j.subtype == "started" and type(j.model_call_id) ~= "string"
	if (j.type == "thinking" or j.type == "assistant" or bareTool) and not acc.inTurn then
		if acc.turns > 0 and not acc.turnHasId then
			acc.noIdTurns += 1
		elseif acc.turnHasId then
			acc.noIdTurns = 0
		end
		acc.turns += 1
		acc.inTurn = true
		acc.turnHasId = false
		acc.calls += 1
		if acc.noIdTurns >= adapters.NO_ID_TURNS then
			acc.unknown = acc.unknown
				or `{adapters.NO_ID_TURNS} turns with no model_call_id: max_calls can't be enforced`
		end
	end
	-- the calls themselves (probe E3): one per distinct model_call_id; an id inside a turn already counted is that
	-- turn's own. The running token count stays 0 and the row takes the result's real total (the user's decision)
	if type(j.model_call_id) == "string" and not acc.callIds[j.model_call_id] then
		acc.callIds[j.model_call_id] = true
		if acc.inTurn and not acc.turnHasId then
			acc.turnHasId = true
		else
			acc.calls += 1
		end
	elseif type(j.model_call_id) == "string" and acc.inTurn then
		acc.turnHasId = true
	end
end

-- claude's own sandbox off, whatever the user's settings say, so the gate's jail can engage inside the step
-- (programme review E6; macOS can't nest sandboxes)
adapters.CLAUDE_SETTINGS = '{"sandbox":{"enabled":false}}'

-- What a runtime's step environment adds (review 004 F2, 005 F2): Claude Code never allows one shell command more than
-- BASH_MAX_TIMEOUT_MS (600 s by default), but an author waits on its nested review as one command
-- (`./zn dispatch zz-review …`), and reviews here take up to 29 minutes. Only the maximum is raised, to two hours (G22);
-- the default (120 s) stays, so a hung command is still a two-minute tool error the model recovers from, and the
-- headless section tells the author to pass a two-hour timeout on its review command alone. E15 measures the rest.
adapters.STEP_ENV = {
	["claude-cli"] = { BASH_MAX_TIMEOUT_MS = "7200000" },
} :: { [string]: { [string]: string } }

local function withEffort(args: { string }, flag: string, effort: string?): { string }
	if effort then
		table.insert(args, flag)
		table.insert(args, effort)
	end
	return args
end

local ADAPTERS: { [string]: Adapter } = {
	["claude-cli"] = {
		cli = "claude",
		runtime = "claude-cli",
		callCapped = false,
		argv = function(r: Request): { string }
			return withEffort({
				"claude",
				"-p",
				r.prompt,
				"--output-format",
				"stream-json",
				"--verbose",
				"--model",
				r.model,
				"--permission-mode",
				"bypassPermissions",
				"--permission-prompts",
				"none",
				"--session-id",
				r.session,
				"--settings",
				adapters.CLAUDE_SETTINGS,
			}, "--effort", r.effort)
		end,
		feed = claudeFeed,
	},
	["claude-cloud"] = {
		cli = "claude",
		runtime = "claude-cloud",
		callCapped = false,
		argv = function(r: Request): { string }
			return withEffort({
				"claude",
				"--cloud",
				r.prompt,
				"-p",
				"--output-format",
				"stream-json",
				"--verbose",
				"--model",
				r.model,
			}, "--effort", r.effort)
		end,
		feed = claudeFeed,
	},
	["grok-cli"] = {
		cli = "grok",
		runtime = "grok-cli",
		callCapped = false,
		argv = function(r: Request): { string }
			return withEffort({
				"grok",
				"-p",
				r.prompt,
				"--output-format",
				"streaming-json",
				"-m",
				r.model,
				"--always-approve",
				"--cwd",
				r.cwd,
				"-s",
				r.session,
			}, "--reasoning-effort", r.effort)
		end,
		feed = grokFeed,
	},
	["grok-bot"] = {
		cli = "grok",
		runtime = "grok-bot",
		callCapped = false,
		argv = function(r: Request): { string }
			local args = withEffort({ "grok", "agent", "-m", r.model }, "--reasoning-effort", r.effort)
			table.insert(args, "--always-approve")
			table.insert(args, "headless")
			return args
		end,
		feed = grokFeed,
	},
	["cursor-cli"] = {
		cli = "agent",
		runtime = "cursor-cli",
		callCapped = true,
		argv = function(r: Request): { string }
			return {
				"agent",
				"-p",
				"--output-format",
				"stream-json",
				"--model",
				if r.effort then `{r.model}[effort={r.effort}]` else r.model,
				"--force",
				"--trust",
				"--sandbox",
				"disabled",
				"--workspace",
				r.cwd,
				r.prompt,
			}
		end,
		feed = agentFeed,
	},
	["cursor-app"] = {
		cli = "agent",
		runtime = "cursor-app",
		callCapped = true,
		argv = function(r: Request): { string }
			return {
				"agent",
				"worker",
				"--model",
				if r.effort then `{r.model}[effort={r.effort}]` else r.model,
				"--workspace",
				r.cwd,
			}
		end,
		feed = agentFeed,
	},
}

-- The runtimes whose prompt goes on stdin (they take none on the command line).
adapters.STDIN = { ["grok-bot"] = true, ["cursor-app"] = true }

function adapters.get(runtime: string): Adapter
	local a = ADAPTERS[runtime]
	if not a then
		error(`no adapter for runtime {runtime}`, 0)
	end
	return a
end

-- The outcome of a step that ended by itself: quota when the CLI said so (in its stream or its stderr), ok when it
-- exited 0 with a token count and no error, else failed. A step that exits 0 with no count failed: every adapter
-- returns one (the capture's Solution).
function adapters.finish(acc: Acc, exitOk: boolean, stderr: string, runtime: string): (Outcome, string)
	if acc.quota then
		return "quota", acc.quota
	end
	local w = mentions(stderr, adapters.QUOTA)
	if not exitOk and w then
		return "quota", (string.match(stderr, "[^\n]*$") or w)
	end
	if exitOk and acc.final ~= nil and not acc.errorText then
		return "ok", "done"
	end
	if exitOk and acc.final == nil then
		return "failed", `{runtime} exited without a token count`
	end
	local why = acc.errorText or (string.match(string.gsub(stderr, "%s+$", ""), "[^\n]*$") or "")
	return "failed", if why ~= "" then why else `{runtime} failed`
end

-- The count a step's row records: the CLI's final count when it gave one, else the running count.
function adapters.tokens(acc: Acc): number
	return acc.final or acc.live
end

return adapters
