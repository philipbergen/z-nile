--!strict
-- What a CLI transcript holds for one span: tokens the way the adapters count them (input + cache writes + output,
-- cache reads left out) and the seconds the model was working. Pure over the transcript text. A file this does not
-- understand returns nil; a file it understands with no numbers returns an empty part, which the caller records as
-- unmeasured. Nothing here is a guess.
local sessions = {}

export type Part = {
	tokens: number?,
	ai: number?,
	inn: number?,
	out: number?,
	model: string?,
}

export type Read = {
	tokens: number?,
	ai: number?,
	model: string?,
	note: string,
	unmeasured: string?,
}

local function days(y: number, m: number, d: number): number
	local a = math.floor((14 - m) / 12)
	local yy = y + 4800 - a
	local mm = m + 12 * a - 3
	local jdn = d
		+ math.floor((153 * mm + 2) / 5)
		+ 365 * yy
		+ math.floor(yy / 4)
		- math.floor(yy / 100)
		+ math.floor(yy / 400)
		- 32045
	return jdn - 2440588
end

-- Seconds since 1970 for an ISO timestamp, or nil when it is not one. The fraction is kept.
function sessions.unix(ts: string): number?
	local y, mo, d, h, mi, se, fr = string.match(ts, "(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)%.?(%d*)")
	if not y then
		return nil
	end
	local fraction = fr or ""
	local frac = if fraction ~= "" then tonumber("0." .. fraction) :: number else 0
	return days(tonumber(y) :: number, tonumber(mo) :: number, tonumber(d) :: number) * 86400
		+ (tonumber(h) :: number) * 3600
		+ (tonumber(mi) :: number) * 60
		+ (tonumber(se) :: number)
		+ frac
end

function sessions.delta(a: string, b: string): number
	local aa, bb = sessions.unix(a), sessions.unix(b)
	if not aa or not bb or bb < aa then
		return 0
	end
	return bb - aa
end

local function inside(ts: string, sinceIso: string, untilIso: string): boolean
	return ts >= sinceIso and ts <= untilIso
end

local function overlap(startTs: string, stopTs: string, sinceIso: string, untilIso: string): number
	local a, b = sessions.unix(startTs), sessions.unix(stopTs)
	local s, u = sessions.unix(sinceIso), sessions.unix(untilIso)
	if not a or not b or not s or not u then
		return 0
	end
	local lo = if a > s then a else s
	local hi = if b < u then b else u
	return if hi > lo then hi - lo else 0
end

-- Claude Code's project jsonl: assistant messages carry usage and a timestamp. AI time is the gap from the previous
-- event to each assistant message in the span (the wait on the model).
function sessions.claude(text: string, sinceIso: string, untilIso: string): Part?
	local saw = false
	local prev: string? = nil
	local ai, inn, outn, cache = 0, 0, 0, 0
	local model: string? = nil
	local sawTokens = false
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		local ts = string.match(line, '"timestamp":"([^"]+)"')
		if ts and inside(ts, sinceIso, untilIso) then
			saw = true
			local assistant = string.find(line, '"type":"assistant"', 1, true) ~= nil
			if assistant and prev then
				ai += sessions.delta(prev, ts)
			end
			if assistant then
				local i = tonumber(string.match(line, '"input_tokens":(%d+)')) or 0
				local c = tonumber(string.match(line, '"cache_creation_input_tokens":(%d+)')) or 0
				local o = tonumber(string.match(line, '"output_tokens":(%d+)')) or 0
				if i + c + o > 0 then
					sawTokens = true
					inn += i
					cache += c
					outn += o
				end
				if not model then
					model = string.match(line, '"model":"([^"]+)"')
				end
			end
			prev = ts
		elseif ts and ts < sinceIso then
			prev = ts
		end
	end
	if not saw then
		return nil
	end
	return {
		tokens = if sawTokens then inn + cache + outn else nil,
		ai = ai,
		inn = inn,
		out = outn,
		model = model,
	}
end

-- Grok's updates.jsonl: `_meta.totalTokens` climbs through a turn and drops when the next one starts. The tokens are
-- the sum of the climbs. Timestamps are unix seconds.
function sessions.grokUpdates(text: string, sinceUnix: number, untilUnix: number): Part?
	local prev: number? = nil
	local sum = 0
	local saw = false
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		local ts = tonumber(string.match(line, '"timestamp":(%d+)'))
		local tok = tonumber(string.match(line, '"totalTokens":(%d+)'))
		if ts and tok then
			if ts < sinceUnix then
				prev = tok
			elseif ts <= untilUnix then
				saw = true
				if prev == nil or tok < prev then
					sum += tok
				else
					sum += tok - prev
				end
				prev = tok
			end
		end
	end
	if not saw then
		return nil
	end
	return { tokens = sum, ai = nil }
end

-- Grok's events.jsonl: a turn's AI time is turn_ended minus turn_started, clipped to the span.
function sessions.grokEvents(text: string, sinceIso: string, untilIso: string): Part?
	local open: string? = nil
	local ai = 0
	local model: string? = nil
	local saw = false
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		local ts = string.match(line, '"ts":"([^"]+)"')
		local kind = string.match(line, '"type":"([^"]+)"')
		if ts and kind == "turn_started" then
			open = ts
			model = string.match(line, '"model_id":"([^"]+)"') or model
		elseif ts and kind == "turn_ended" and open then
			local slice = overlap(open, ts, sinceIso, untilIso)
			if slice > 0 then
				saw = true
				ai += slice
			end
			open = nil
		end
	end
	if not saw then
		return nil
	end
	return { tokens = nil, ai = ai, model = model }
end

-- Cursor's agent transcripts (the `agent` CLI) carry the messages and, today, neither timestamps nor usage.
-- Nil means the text has nothing this reader understands.
function sessions.cursor(text: string): Part?
	local hasTs = string.find(text, '"timestamp"', 1, true) ~= nil
		or string.find(text, '"createdAt"', 1, true) ~= nil
	local hasTok = string.find(text, '"input_tokens"', 1, true) ~= nil
		or string.find(text, '"inputTokens"', 1, true) ~= nil
	if not hasTs and not hasTok then
		return nil
	end
	return { tokens = nil, ai = nil }
end

export type Found = { cli: string, part: Part? }

-- One reading for the span. A CLI with no part is named unmeasured. Tokens and AI are the sums of the parts that
-- had them; either is left open when no CLI had it.
function sessions.combine(found: { Found }): Read
	local tokens, ai = 0, 0
	local sawTokens, sawAi = false, false
	local model: string? = nil
	local notes: { string } = {}
	for _, f in found do
		local p = f.part
		if not p or (p.tokens == nil and p.ai == nil) then
			table.insert(notes, `{f.cli} unmeasured`)
		else
			local bits: { string } = { f.cli }
			if p.tokens ~= nil then
				sawTokens = true
				tokens += p.tokens
				table.insert(bits, `tokens={p.tokens}`)
				if p.inn ~= nil and p.out ~= nil then
					table.insert(bits, `in={p.inn} out={p.out}`)
				end
			end
			if p.ai ~= nil then
				sawAi = true
				ai += p.ai
				table.insert(bits, string.format("ai=%.3f", p.ai))
			end
			if p.model and not model then
				model = p.model
			end
			table.insert(notes, table.concat(bits, " "))
		end
	end
	local flags: { string } = {}
	if not sawTokens then
		table.insert(flags, "tokens")
	end
	if not sawAi then
		table.insert(flags, "ai")
	end
	return {
		tokens = if sawTokens then tokens else nil,
		ai = if sawAi then ai else nil,
		model = model,
		note = table.concat(notes, "; "),
		unmeasured = if #flags > 0 then table.concat(flags, ",") else nil,
	}
end

return sessions
