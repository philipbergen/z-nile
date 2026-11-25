--!strict
-- f0421 slice 3, S1b step one (review-007): the rules of a level's several entries where a caller passes the session, and in
-- the branches the seed cannot reach. On the step-one seed (tests/fixtures/models/seed-s1b.models.toml): a review's same-model
-- fact is the session's own entry's (F1), a session is matched by its exact id only (F4, C1), the refusal names every entry
-- (F4), the id rule keeps the catalog's ultra from agy whatever its offers say (F4), and `./zn model <level>` with no session
-- is the level's first entry as `entriesFor` defines it (F5). On the live root: no CLI that only declares its model is handed
-- the final review, the idea challenge or an ultra pair (F3).
local fs = require("@lune/fs")
local models = require("@znile/engine/models")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local FIXTURES = "tests/fixtures/models"
local SEED = fs.readFile(`{FIXTURES}/seed-s1b.models.toml`)
local OPUS = "claude-opus-5-5-high"
local ARGON = "gemini-4-argon-high"

local function walk(text: string): { models.Layer }
	return { models.parse(text, ".models.toml") }
end
local function swap(old: string, new: string): string
	local a = string.find(SEED, old, 1, true)
	assert(a ~= nil, `the seed has no {old}`)
	return string.sub(SEED, 1, (a :: number) - 1) .. new .. string.sub(SEED, (a :: number) + #old)
end
local function review(l: { models.Layer }, writers: { string }, session: string?): models.Spec
	local s, why = models.resolveReview(l, "agy", "code-review", "normal", writers, session)
	assert(s ~= nil, tostring(why))
	return s
end

-- the activity/level pairs whose root setting is ultra, by what claude (which defines every level) resolves them to
local function ultraPairs(l: { models.Layer }): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for _, act in models.ACTIVITIES do
		for _, lvl in { "easy", "normal", "risky" } do
			local s = models.resolveActivity(l, "claude", act, lvl :: any)
			if s ~= nil and s.alias == "ultra" then
				out[`{act}/{lvl}`] = true
			end
		end
	end
	return out
end

return t.spec("f0421 S1b step one: a level's entries where the caller passes the session", function(it)
	it(
		"F1: a session's review records the same-model fact of the entry it runs, not of the first entry",
		function()
			local seed = walk(SEED)
			-- an Opus session reviewing Opus-written text: its own entry (not Argon's), on its writer's model
			local own = review(seed, { OPUS }, OPUS)
			t.expect(own.model).toBe(OPUS)
			t.expect(own.sameAsAuthor).toBe(true)
			t.expect(own.writer).toBe(OPUS)
			-- the same session reviewing Argon-written text: not the writer's model
			local other = review(seed, { ARGON }, OPUS)
			t.expect(other.model).toBe(OPUS)
			t.expect(other.sameAsAuthor == nil).toBe(true)
			-- two writers: the one whose family the session's entry is
			local mixed = review(seed, { ARGON, "claude-opus-5-5-medium" }, OPUS)
			t.expect(mixed.model).toBe(OPUS)
			t.expect(mixed.sameAsAuthor).toBe(true)
			t.expect(mixed.writer).toBe("claude-opus-5-5-medium")
			-- an Argon session on Argon-written text stays the same model
			local argon = review(seed, { ARGON }, ARGON)
			t.expect(argon.model).toBe(ARGON)
			t.expect(argon.sameAsAuthor).toBe(true)
			t.expect(argon.writer).toBe(ARGON)
		end
	)

	it("F4: a session that runs none of a level's entries is told every entry, word for word", function()
		local s, why = models.resolveActivity(walk(SEED), "agy", "code", "risky", nil, ARGON)
		t.expect(s == nil).toBe(true)
		t.expect(why).toBe(
			"this session runs gemini-4-argon-high, and code on agy needs one of gemini-4-neon-high|claude-opus-5-5-high|claude-opus-5-5-medium"
		)
	end)

	it(
		"F4: agy offering every Claude id is still given nothing at ultra (the id rule keeps Fable out)",
		function()
			local wide = walk(swap('[clis.agy]\noffers = ["', '[clis.agy]\noffers = ["claude-", "'))
			local ultra = ultraPairs(wide)
			t.expect(next(ultra) ~= nil).toBe(true)
			for _, session in { "" :: string?, OPUS, ARGON, "claude-sonnet-5-5-high", "gemini-4-neon-high" } do
				local s = if session == "" then nil else session
				for _, pair in models.canList(wide, "agy", s) do
					t.expect(`{pair} {tostring(ultra[pair])}`).toBe(`{pair} nil`)
				end
			end
			local s, why = models.resolveActivity(wide, "agy", "final-review", "normal")
			t.expect(s == nil).toBe(true)
			t.expect(why).toBe("agy does not define ultra")
		end
	)

	it(
		"F4 (C1): a session is matched by its exact id; not by the bare model, a folded case or agent's -fast",
		function()
			-- an entry in the single form: its id is model-effort
			local single = walk(
				swap(
					'heavy = ["gemini-4-neon-high", "claude-opus-5-5-high", "claude-opus-5-5-medium"]\n',
					'heavy = ["gemini-4-neon-high", { model = "claude-opus-5-5", effort = "high" }]\n'
				)
			)
			local exact = models.resolveActivity(single, "agy", "code", "risky", nil, OPUS)
			t.expect(exact ~= nil and exact.model).toBe("claude-opus-5-5")
			t.expect(exact ~= nil and exact.effort).toBe("high")
			for _, near in { "claude-opus-5-5", "CLAUDE-OPUS-5-5-HIGH", "Gemini-4-Neon-High" } do
				t.expect(models.resolveActivity(single, "agy", "code", "risky", nil, near) == nil).toBe(true)
				t.expect(models.resolveAlias(single, "agy", "heavy", near) == nil).toBe(true)
				t.expect(#models.canList(single, "agy", near)).toBe(0)
			end
			t.expect((models.resolveAlias(single, "agy", "heavy", OPUS) :: models.Spec).effort).toBe("high")
			-- agent with two models at heavy: a session naming one with -fast is not that entry (step two's to build)
			local agent = walk(
				swap(
					'[clis.agent]\nheavy = { model = "claude-opus-5-5", effort = "high" }\n',
					'[clis.agent]\nheavy = [{ model = "claude-opus-5-5", effort = "high" }, { model = "claude-sonnet-5-5", effort = "high" }]\n'
				)
			)
			t.expect(#models.modelsOf(agent, "agent")).toBe(2)
			t.expect(models.resolveActivity(agent, "agent", "code-review", "normal", nil, OPUS) ~= nil)
				.toBe(true)
			t.expect(
				models.resolveActivity(agent, "agent", "code-review", "normal", nil, `{OPUS}-fast`) == nil
			)
				.toBe(true)
			t.expect(models.resolveAlias(agent, "agent", "heavy", `{OPUS}-fast`) == nil).toBe(true)
		end
	)

	it(
		"F5: ./zn model <level> with no session is the level's first entry, the catalog's when no list holds it",
		function()
			-- grok with no light table: work is handed light on grok-4.7 at high, and `./zn model light` says the same
			local noLight = walk(
				swap(
					'[clis.grok]\noffers = ["grok-4.7", "grok-4.7-build-fast", "grok-4.6", "grok-4.5"]\nlight = { model = "grok-4.7", effort = "high" }\n',
					'[clis.grok]\noffers = ["grok-4.7", "grok-4.7-build-fast", "grok-4.6", "grok-4.5"]\n'
				)
			)
			local work = models.resolveActivity(noLight, "grok", "code", "normal") :: models.Spec
			local alias, why = models.resolveAlias(noLight, "grok", "light")
			t.expect(why).toBe(nil)
			t.expect(alias ~= nil and `{alias.model}@{tostring(alias.effort)}`)
				.toBe(`{work.model}@{tostring(work.effort)}`)
			t.expect(alias ~= nil and alias.alias).toBe("light")
			-- a list's first entry, and a level the CLI has no way to is refused as before
			t.expect((models.resolveAlias(walk(SEED), "agy", "heavy") :: models.Spec).model)
				.toBe("gemini-4-neon-high")
			local none, nowhy = models.resolveAlias(walk(SEED), "agy", "ultra")
			t.expect(none == nil).toBe(true)
			t.expect(nowhy).toBe("agy does not define ultra")
		end
	)

	it(
		"F3: on the live root, no session or dispatched step of agent, agy or kimi is handed the final review, the idea challenge or an ultra pair",
		function()
			local top = (
				string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", "")
			)
			local root = walk(fs.readFile(`{top}/.models.toml`))
			local ultra = ultraPairs(root)
			local held = {}
			for _, cli in { "agent", "agy", "kimi" } do
				held[cli] = models.modelsOf(root, cli)
			end
			local function banned(pair: string): boolean
				return ultra[pair] == true
					or string.sub(pair, 1, 13) == "final-review/"
					or string.sub(pair, 1, 15) == "idea-challenge/"
			end
			for cli, ids in held do
				-- no session (a dispatched step), then each model the CLI holds
				local sessions: { string } = { "-" }
				for _, id in ids do
					table.insert(sessions, id)
				end
				for _, session in sessions do
					local s = if session == "-" then nil else session
					for _, pair in models.canList(root, cli, s) do
						t.expect(`{cli} {session} {pair} {tostring(banned(pair))}`)
							.toBe(`{cli} {session} {pair} false`)
					end
				end
				for _, act in { "final-review", "idea-challenge" } do
					for _, lvl in { "easy", "normal", "risky" } do
						t.expect(models.resolveReview(root, cli, act, lvl :: any, {}, nil) == nil).toBe(true)
					end
				end
				for pair in ultra do
					local parts = string.split(pair, "/")
					t.expect(models.resolveReview(root, cli, parts[1], parts[2] :: any, {}, nil) == nil)
						.toBe(true)
				end
			end
		end
	)
end)
