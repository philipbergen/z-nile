--!strict
-- f0421 slice 3: every answer the models engine gives for one walk, one line each, in a fixed order. The pin
-- (tests/tooling/models-pin.spec.luau) compares these lines for the root `.models.toml` as origin/main held it at 5e8f5eaa4
-- with the text the engine gave before slice 3, so a change that alters any answer for a table that does not use slice 3's
-- keys shows the line that changed. Pure: layers in, lines out; every call is guarded, so a refusal is a line too.
local models = require("@znile/engine/models")
local rounds = require("@znile/engine/rounds")

local modelspin = {}

-- the activities whose setting is another's (design-answer is design's, ...), after the configured ones
local ANSWERS = { "design-answer", "code-answer", "final-answer", "trace", "fix" }
local REVIEWS = { "idea-challenge", "design-review", "raft-review", "code-review", "final-review" }
-- a writer recorded on claude at high effort, and one of agy's writers: the cross-CLI same-model cases
local CROSS = { "claude-opus-5-5-high", "gemini-4-neon-medium" }

local function shown(v: any): string
	return if v == nil then "-" else tostring(v)
end

local function spec(s: models.Spec): string
	return `{s.model}@{shown(s.effort)} alias={shown(s.alias)} ctx={shown(s.context)} rank={s.rank} runtime={s.runtime} tokens={s.maxTokens} calls={shown(
		s.maxCalls
	)} minutes={shown(s.maxMinutes)} same={shown(s.sameAsAuthor)} writer={shown(s.writer)}`
end

-- one guarded call: its value through `show`, or the error's text
local function guarded(show: any, f: () -> ...any): string
	local result = table.pack(pcall(f))
	if not result[1] then
		return `error {tostring(result[2])}`
	end
	return show(table.unpack(result, 2, result.n))
end

local function resolved(s: models.Spec?, why: string?): string
	return if s ~= nil then spec(s) else `- {shown(why)}`
end

function modelspin.lines(layers: { models.Layer }): { string }
	local out: { string } = {}
	local function add(line: string)
		table.insert(out, line)
	end
	local acts: { string } = table.clone(models.ACTIVITIES)
	for _, a in ANSWERS do
		table.insert(acts, a)
	end
	for _, cli in models.CLIS do
		add(`cli {cli} subagents={tostring(models.hasSubagents(cli))}`)
		add(`  models {guarded(function(m)
			return table.concat(m, ",")
		end, function()
			return models.modelsOf(layers, cli)
		end)} needsSession={guarded(tostring, function()
			return models.needsSession(layers, cli)
		end)}`)
		-- the sessions to answer for: none, and each model a session of this CLI may name
		local sessions: { string } = { "" }
		local ok, held = pcall(models.modelsOf, layers, cli)
		if ok then
			for _, m in held :: { string } do
				table.insert(sessions, m)
			end
		end
		for _, session in sessions do
			local s: string? = if session == "" then nil else session
			add(`  session {if s then s else "-"}`)
			add(`    can {guarded(function(l)
				return table.concat(l, ",")
			end, function()
				return models.canList(layers, cli, s)
			end)}`)
			for _, act in acts do
				for _, lvl in rounds.LEVELS do
					add(`    {act}/{lvl} {guarded(resolved, function()
						return models.resolveActivity(layers, cli, act, lvl :: rounds.Level, nil, s)
					end)}`)
				end
			end
		end
		for _, act in REVIEWS do
			for _, lvl in rounds.LEVELS do
				for _, author in CROSS do
					add(`  author {author} {act}/{lvl} {guarded(resolved, function()
						return models.resolveActivity(layers, cli, act, lvl :: rounds.Level, author)
					end)}`)
				end
				add(`  writers {act}/{lvl} {guarded(resolved, function()
					return models.resolveReview(layers, cli, act, lvl :: rounds.Level, CROSS)
				end)}`)
			end
		end
		for _, alias in models.ALIASES do
			add(`  alias {alias} {guarded(resolved, function()
				return models.resolveAlias(layers, cli, alias)
			end)}`)
		end
		for _, lvl in rounds.LEVELS do
			add(`  builder {lvl} {guarded(shown, function()
				return models.builderGuess(layers, cli, lvl :: rounds.Level)
			end)}`)
			for _, act in acts do
				add(`  refusal {act}/{lvl} {guarded(shown, function()
					return models.refusal(layers, cli, act, lvl :: rounds.Level, "why")
				end)}`)
			end
		end
	end
	for _, act in acts do
		add(`activity {act} cliFor={guarded(function(c, p)
			return `{shown(c)} {shown(p)}`
		end, function()
			return models.cliFor(layers, act, nil, nil, "pin")
		end)}`)
		for _, lvl in rounds.LEVELS do
			add(`  {lvl} need={guarded(shown, function()
				return models.need(layers, act, lvl :: rounds.Level)
			end)} deliverers={guarded(function(l)
				return table.concat(l, ",")
			end, function()
				return models.deliverers(layers, act, lvl :: rounds.Level)
			end)}`)
			add(`  {lvl} waiting={guarded(shown, function()
				return models.waiting(layers, act, lvl :: rounds.Level)
			end)}`)
		end
	end
	return out
end

return modelspin
