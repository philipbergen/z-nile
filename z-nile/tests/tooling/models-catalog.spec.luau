--!strict
-- f0421 slice 3, S1a (AC29): the parser reads every slice-3 key and acts on none of them. `[catalog]` (root file only), a
-- level's list of models, `offers` and the consent record are read and checked; a list resolves as its first entry, which is
-- today's single form, so no answer changes for any table. The S1b seed (tests/fixtures/models/seed-s1b.models.toml) and a
-- consent record (model-consent.md) load, and the root table's pinned answers stay as they were.
local fs = require("@lune/fs")
local modelconsent = require("@znile/engine/modelconsent")
local models = require("@znile/engine/models")
local modelspin = require("@tests/lib/modelspin")
local t = require("@tests/lib/t")

local FIXTURES = "tests/fixtures/models"
local ROOT = fs.readFile(`{FIXTURES}/root-5e8f5eaa4.models.toml`)

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

-- the frozen root with only claude's table among the CLIs, so a case adds the CLI tables it needs
local CLAUDE = [[
[clis.claude]
xlight = { model = "claude-haiku-5-5", effort = "low" }
light = { model = "claude-sonnet-5-5", effort = "medium" }
heavy = { model = "claude-opus-5-5", effort = "high" }
ultra = { model = "claude-fable-5-2", effort = "xhigh", context = 1000000 }
]]
local function base(extra: string): string
	local a = string.find(ROOT, "[clis.claude]", 1, true) :: number
	local b = string.find(ROOT, "\n[activities.idea]", a, true) :: number
	return string.sub(ROOT, 1, a - 1) .. CLAUDE .. extra .. "\n" .. string.sub(ROOT, b + 1)
end
-- a catalog that places claude's four entries, plus the given lines' entries at their levels
local function catalog(levels: { [string]: { string } }?): string
	local l: { [string]: { string } } = {
		xlight = { "claude-haiku-5-5-low" },
		light = { "claude-sonnet-5-5-medium" },
		heavy = { "claude-opus-5-5-high" },
		ultra = { "claude-fable-5-2-xhigh" },
	}
	local given: { [string]: { string } } = levels or {}
	for level, ids in given do
		for _, id in ids do
			table.insert(l[level], id)
		end
	end
	local out = { "[catalog]" }
	for _, level in models.ALIASES do
		local quoted: { string } = {}
		for _, id in l[level] do
			table.insert(quoted, `"{id}"`)
		end
		table.insert(out, `{level} = [{table.concat(quoted, ", ")}]`)
	end
	return table.concat(out, "\n") .. "\n"
end

local function load(text: string, path: string?): { models.Layer }
	local l = { models.parse(text, path or ".models.toml") }
	models.config(l)
	return l
end
-- the error loading `text` raises, without its file prefix
local function refused(text: string, path: string?): string
	local ok, e = pcall(load, text, path)
	t.expect(ok).toBe(false)
	local msg = tostring(e)
	local p = `{path or ".models.toml"}: `
	return if string.sub(msg, 1, #p) == p then string.sub(msg, #p + 1) else msg
end

local function expected(): { string }
	local out: { string } = {}
	for line in string.gmatch(fs.readFile(`{FIXTURES}/models-pin.expected.txt`), "[^\n]+") do
		table.insert(out, line)
	end
	return out
end

return t.spec(
	"f0421 slice 3, S1a: the catalog, the lists, offers and the consent record are read, not acted on",
	function(it)
		it(
			"the S1b seed loads, its lists resolve as their first entries, and the root's pinned answers stay",
			function()
				local seed = load(fs.readFile(`{FIXTURES}/seed-s1b.models.toml`))
				local cfg = models.config(seed)
				local ultra = (cfg.catalog :: any).ultra
				t.expect(ultra[1].model).toBe("claude-fable-5-2-xhigh")
				t.expect(ultra[1].context).toBe(1000000)
				t.expect(ultra[2].model).toBe("claude-fable-5-2-high")
				t.expect(#(cfg.catalog :: any).heavy).toBe(5)
				local agy = cfg.clis.agy
				t.expect(agy.aliases.heavy.model).toBe("gemini-4-neon-high")
				t.expect((agy.aliases.heavy.rest :: any)[1].model).toBe("claude-opus-5-5-high")
				t.expect((agy.aliases.heavy.rest :: any)[2].model).toBe("claude-opus-5-5-medium")
				t.expect(agy.review.heavy.model).toBe("gemini-4-argon-high")
				t.expect(#(agy.offers :: { string })).toBe(27)
				t.expect((cfg.clis.agent.offers :: { string })[1]).toBe("claude-")
				-- read, not acted on: a list is its first entry, and the catalog gives agent nothing yet
				t.expect((models.resolveActivity(seed, "agy", "code", "risky") :: models.Spec).model)
					.toBe("gemini-4-neon-high")
				t.expect((models.resolveActivity(seed, "agy", "code-review", "normal") :: models.Spec).model)
					.toBe("gemini-4-argon-high")
				t.expect(#models.canList(seed, "agent")).toBe(0)
				t.expect(models.modelsOf(seed, "agy")).toEqual({
					"gemini-4-argon-high",
					"gemini-4-argon-medium",
					"gemini-4-neon-high",
					"gemini-4-neon-low",
					"gemini-4-neon-medium",
				})
				-- the root table, read beside the seed fixture, answers exactly as pinned
				local root = { models.parse(ROOT, ".models.toml") }
				t.expect(modelspin.lines(root)).toEqual(expected())
			end
		)

		it(
			"a consent record is read: each row's CLI, kind, needed level, stand-in entries and answer",
			function()
				local path = `{FIXTURES}/model-consent.md`
				local rows = modelconsent.parse(fs.readFile(path), path)
				t.expect(#rows).toBe(2)
				t.expect(rows[1].cli).toBe("agy")
				t.expect(rows[1].kind).toBe("review")
				t.expect(rows[1].needed).toBe("ultra")
				t.expect(rows[1].standIn)
					.toEqual({ "gemini-4-argon-high", "claude-opus-5-5-high", "claude-opus-5-5-medium" })
				t.expect(rows[1].answer).toBe("yes")
				t.expect(rows[1].who).toBe("Philip Bergen")
				t.expect((modelconsent.latest(rows, "agy", "writing", "ultra") :: any).answer).toBe("no")
				t.expect(modelconsent.latest(rows, "agent", "review", "ultra")).toBe(nil)
			end
		)

		it(
			"a consent record that is not well formed is refused, naming the file, the line and the rule",
			function()
				local HEAD = "# model consent\nwhen\twho\tcli\tkind\tneeded\tstand-in\tanswer\n"
				local function bad(text: string): string
					local ok, e = pcall(modelconsent.parse, text, "c.md")
					t.expect(ok).toBe(false)
					return tostring(e)
				end
				local good =
					"2026-11-24T20:00:00Z\tPhilip Bergen\tagy\treview\tultra\tgemini-4-argon-high\tyes"
				t.expect(#modelconsent.parse(HEAD .. good .. "\n", "c.md")).toBe(1)
				t.expect(#modelconsent.parse("", "c.md")).toBe(0) -- no record yet: no rows
				t.expect(bad("# model consent\nwhen\twho\n"))
					.toBe("c.md: line 2 is not the header (when, who, cli, kind, needed, stand-in, answer)")
				t.expect(bad("# nope\n")).toBe("c.md: line 1 is not # model consent")
				local function row(cells: { string }): string
					return bad(HEAD .. table.concat(cells, "\t") .. "\n")
				end
				local cells = string.split(good, "\t")
				local function with(i: number, v: string): { string }
					local c = table.clone(cells)
					c[i] = v
					return c
				end
				t.expect(row({ "2026-11-24T20:00:00Z", "x" })).toBe("c.md: line 3 has 2 fields, not 7")
				t.expect(row(with(1, "yesterday")))
					.toBe("c.md: line 3: when is yesterday, not a UTC time (2026-11-24T20:00:00Z)")
				t.expect(row(with(2, ""))).toBe("c.md: line 3: who is empty")
				t.expect(row(with(3, "gemini")))
					.toBe("c.md: line 3: cli is gemini, not a supported CLI (claude, grok, agent, kimi, agy)")
				t.expect(row(with(4, "both"))).toBe("c.md: line 3: kind is both: writing or review")
				t.expect(row(with(5, "medium")))
					.toBe("c.md: line 3: needed is medium, not a level (xlight, light, heavy, ultra)")
				t.expect(row(with(6, ""))).toBe("c.md: line 3: stand-in names no model")
				t.expect(row(with(6, "a b")))
					.toBe("c.md: line 3: stand-in names a b, which is not a model id")
				t.expect(row(with(7, "maybe"))).toBe("c.md: line 3: answer is maybe: yes or no")
			end
		)

		it("[catalog] is read from the root file only", function()
			local layers = {
				models.parse(base(""), ".models.toml"),
				models.parse(catalog(), "pickman/.models.toml"),
			}
			local ok, e = pcall(models.config, layers)
			t.expect(ok).toBe(false)
			t.expect(tostring(e)).toBe(
				"pickman/.models.toml: [catalog] is read from the root .models.toml only: a closer file cannot change a model's rank"
			)
			-- the root file's catalog loads
			load(base("") .. catalog())
		end)

		it(
			"a catalog is refused when a level is not a list of model ids, or an entry is placed twice or unsplit",
			function()
				t.expect(refused(base("") .. "[catalog]\nultra = []\n"))
					.toBe("catalog.ultra is empty: name at least one model")
				t.expect(refused(base("") .. '[catalog]\nultra = "claude-fable-5-2-high"\n'))
					.toBe("catalog.ultra is a list of model ids")
				t.expect(refused(base("") .. '[catalog]\nmedium = ["claude-opus-5-5-high"]\n'))
					.toBe("catalog.medium is not a level (xlight, light, heavy, ultra)")
				t.expect(refused(base("") .. '[catalog]\nlight = ["bad id"]\n'))
					.toBe("catalog.light names bad id, which is not a model id")
				t.expect(
					refused(
						base("")
							.. '[catalog]\nheavy = ["claude-opus-5-5-high"]\nultra = ["Claude-Opus-5-5-High"]\n'
					)
				).toBe(
					"catalog places claude-opus-5-5-high at heavy and at ultra: an entry has one level"
				)
				t.expect(refused(base("") .. '[catalog]\nultra = ["claude-4.6-opus-high-thinking"]\n')).toBe(
					'catalog.ultra names claude-4.6-opus-high-thinking, whose family still holds high once its effort is removed: state its family ({ id = "claude-4.6-opus-high-thinking", family = "..." })'
				)
				t.expect(refused(base("") .. '[catalog]\nlight = ["grok-4.7-high-fast"]\n')).toBe(
					"catalog.light names grok-4.7-high-fast: the catalog names the plain id (grok-4.7-high), and -fast is a CLI's spelling"
				)
				t.expect(refused(base("") .. '[catalog]\nlight = [{ id = "grok-4.7-high", rank = 2 }]\n'))
					.toBe("catalog.light[1].rank is not a field (id, family, context)")
				t.expect(refused(base("") .. "[catalog]\nlight = [3]\n"))
					.toBe("catalog.light[1] is a model id or { id, family?, context? }")
				-- a stated family loads an id the rule cannot split
				local stated = load(
					base("")
						.. '[catalog]\nxlight = ["claude-haiku-5-5-low"]\nlight = ["claude-sonnet-5-5-medium"]\nheavy = ["claude-opus-5-5-high"]\n'
						.. 'ultra = ["claude-fable-5-2-xhigh", { id = "claude-4.6-opus-high-thinking", family = "claude-4.6-opus" }]\n'
				)
				local entry = (models.config(stated).catalog :: any).ultra[2]
				t.expect(entry.model).toBe("claude-4.6-opus-high-thinking")
				t.expect(entry.family).toBe("claude-4.6-opus")
			end
		)

		it(
			"a level's list is refused when empty, repeated, spelled -fast off agent, or naming its effort twice",
			function()
				t.expect(refused(base("[clis.agy]\nheavy = []\n")))
					.toBe("clis.agy.heavy is empty: name at least one model")
				t.expect(refused(base('[clis.agy]\nheavy = ["gemini-4-neon-high", "gemini-4-neon-high"]\n')))
					.toBe("clis.agy.heavy names gemini-4-neon-high twice")
				t.expect(
					refused(
						base('[clis.agy.review]\nheavy = ["gemini-4-argon-high", "Gemini-4-Argon-High"]\n')
					)
				)
					.toBe("clis.agy.review.heavy names gemini-4-argon-high twice")
				t.expect(
					refused(base('[clis.agy]\nheavy = [{ model = "gemini-4-neon-high", effort = "high" }]\n'))
				)
					.toBe("clis.agy.heavy[1] names its effort twice (gemini-4-neon-high and effort = high)")
				t.expect(refused(base('[clis.grok]\nlight = ["grok-4.7-high-fast"]\n'))).toBe(
					'clis.grok.light names grok-4.7-high-fast: -fast is agent\'s spelling; on grok name the plain id (grok-4.7-high), the single form ({ model = "grok-4.7-high-fast" }), or hold the exact id in clis.grok.offers'
				)
				-- review-006 F2: grok's own default model, which grok lists and its offers hold, loads in a list
				local default = load(
					base(
						'[clis.grok]\noffers = ["grok-4.7", "grok-4.7-build-fast"]\nlight = ["grok-4.7-build-fast"]\n'
					)
				)
				t.expect((models.resolveActivity(default, "grok", "code", "normal") :: models.Spec).model)
					.toBe("grok-4.7-build-fast")
				-- the way out the refusal names works: the single form
				load(base('[clis.grok]\nlight = { model = "grok-4.7-build-fast" }\n'))
				t.expect(
					refused(
						base(
							'[clis.agent]\nmax_calls = 9\nmax_minutes = 9\nheavy = ["claude-4.6-opus-high-thinking"]\n'
						)
					)
				).toBe(
					'clis.agent.heavy names claude-4.6-opus-high-thinking, whose family still holds high once its effort is removed: place it in [catalog] with its family ({ id = "claude-4.6-opus-high-thinking", family = "..." })'
				)
				-- agent takes -fast; a list entry names an entry by its id, so it states no family (review-005 F3)
				load(base('[clis.agent]\nmax_calls = 9\nmax_minutes = 9\nlight = ["grok-4.7-high-fast"]\n'))
				t.expect(
					refused(
						base(
							'[clis.agent]\nmax_calls = 9\nmax_minutes = 9\nheavy = [{ id = "claude-4.6-opus-high-thinking", family = "claude-4.6-opus" }]\n'
						)
					)
				).toBe(
					"clis.agent.heavy[1].family is stated in [catalog] only: a CLI's list names an entry by its id"
				)
				-- the id rule holds for every form: agy runs Gemini, Claude Opus, Claude Sonnet and GPT-OSS, and no Fable
				load(base('[clis.agy]\nheavy = ["gemini-4-neon-high", "claude-opus-5-5-high"]\n'))
				t.expect(
					refused(base('[clis.agy]\nheavy = ["gemini-4-neon-high", "claude-fable-5-2-high"]\n'))
				)
					.toBe("clis.agy.heavy names claude-fable-5-2-high, not a model of cli agy")
			end
		)

		it("with a catalog, a list holds placed entries at their level or lower, never higher", function()
			local cat = catalog({ light = { "gemini-4-neon-medium" }, heavy = { "gemini-4-neon-high" } })
			load(
				base('[clis.agy]\nlight = ["gemini-4-neon-medium"]\nheavy = ["gemini-4-neon-high"]\n') .. cat
			)
			-- lower: one model serves xlight and light (the owner's 2026-11-20 ruling)
			load(
				base('[clis.agy]\nxlight = ["gemini-4-neon-medium"]\nlight = ["gemini-4-neon-medium"]\n')
					.. cat
			)
			t.expect(refused(base('[clis.agy]\nheavy = ["gemini-4-neon-medium"]\n') .. cat)).toBe(
				"clis.agy.heavy names gemini-4-neon-medium, which [catalog] places at light: a CLI's list holds an entry at its catalog level or lower, never higher"
			)
			t.expect(refused(base('[clis.agy]\nheavy = ["gemini-4-neon-xhigh"]\n') .. cat))
				.toBe("clis.agy.heavy names gemini-4-neon-xhigh, which is not placed: place it in [catalog] first")
			-- the single form is an entry too: its model and effort
			t.expect(refused(base('[clis.grok]\nlight = { model = "grok-4.7", effort = "high" }\n') .. cat))
				.toBe("clis.grok.light names grok-4.7-high, which is not placed: place it in [catalog] first")
			-- without a catalog the lists are read as today
			load(base('[clis.agy]\nheavy = ["gemini-4-neon-xhigh"]\n'))
		end)

		it(
			"offers is a list of ids and prefixes, read and checked: every entry of the CLI must be one, and the id rule still holds",
			function()
				t.expect(refused(base("[clis.agy]\noffers = []\n")))
					.toBe("clis.agy.offers is empty: name the ids, or prefixes ending in -, that the CLI runs")
				t.expect(refused(base('[clis.agy]\noffers = "gemini-"\n')))
					.toBe("clis.agy.offers is a list of ids and prefixes ending in -")
				t.expect(refused(base('[clis.agy]\noffers = ["gemini-", "bad id"]\n')))
					.toBe("clis.agy.offers names bad id, which is not an id or a prefix")
				t.expect(
					refused(base('[clis.agy]\noffers = ["gemini-"]\nheavy = ["claude-opus-5-5-high"]\n'))
				)
					.toBe(
						"clis.agy.heavy names claude-opus-5-5-high, which clis.agy.offers (set in .models.toml) does not hold"
					)
				-- offers never widens the id rule: kimi offering claude ids still runs no Claude model
				t.expect(
					refused(
						base(
							'[clis.kimi]\noffers = ["kimi-code-", "claude-"]\nheavy = ["claude-opus-5-5-high"]\n'
						)
					)
				).toBe("clis.kimi.heavy names claude-opus-5-5-high, not a model of cli kimi")
				-- the single form and the models key meet the offers too
				t.expect(
					refused(
						base('[clis.agy]\noffers = ["gemini-"]\nheavy = { model = "claude-opus-5-5-high" }\n')
					)
				).toBe(
					"clis.agy.heavy names claude-opus-5-5-high, which clis.agy.offers (set in .models.toml) does not hold"
				)
				t.expect(
					refused(
						base(
							'[clis.agy]\noffers = ["gemini-"]\nheavy = { model = "gemini-4-neon-high" }\nmodels = ["claude-opus-5-5-high"]\n'
						)
					)
				).toBe(
					"clis.agy.models names claude-opus-5-5-high, which clis.agy.offers (set in .models.toml) does not hold"
				)
				local l = load(
					base(
						'[clis.agy]\noffers = ["gemini-", "claude-opus-5-5-high"]\nheavy = ["claude-opus-5-5-high"]\n'
					)
				)
				t.expect((models.resolveActivity(l, "agy", "code", "risky") :: models.Spec).model)
					.toBe("claude-opus-5-5-high")
				-- a closer file's offers: the refusal names the file that set the level, and the file that set the offers
				local okK, eK = pcall(models.config, {
					models.parse(
						base('[clis.kimi]\nheavy = { model = "kimi-code-k3.1-pro" }\n'),
						".models.toml"
					),
					models.parse('[clis.kimi]\noffers = ["kimi-other-"]\n', "x/.models.toml"),
				})
				t.expect(okK).toBe(false)
				t.expect(tostring(eK)).toBe(
					".models.toml: clis.kimi.heavy names kimi-code-k3.1-pro, which clis.kimi.offers (set in x/.models.toml) does not hold"
				)
				-- a closer file's single form on agy, under the seed's offers, loads
				local seedText = fs.readFile(`{FIXTURES}/seed-s1b.models.toml`)
				models.config({
					models.parse(seedText, ".models.toml"),
					models.parse(
						'[clis.agy]\nheavy = { model = "claude-opus-5-5-high" }\n',
						"y/.models.toml"
					),
				})
				-- a closer file's entry is checked against the merged offers
				local near = '[clis.agy]\nlight = ["claude-sonnet-5-5-medium"]\n'
				local ok, e = pcall(models.config, {
					models.parse(
						base(
							'[clis.agy]\noffers = ["gemini-", "claude-opus-"]\nheavy = ["claude-opus-5-5-high"]\n'
						),
						".models.toml"
					),
					models.parse(near, "pickman/.models.toml"),
				})
				t.expect(ok).toBe(false)
				t.expect(tostring(e)).toBe(
					"pickman/.models.toml: clis.agy.light names claude-sonnet-5-5-medium, which clis.agy.offers (set in .models.toml) does not hold"
				)
			end
		)

		it(
			"review-005 F3: a catalog entry is its id; a stated family is data, and a list names an entry by its id",
			function()
				local seedText = fs.readFile(`{FIXTURES}/seed-s1b.models.toml`)
				-- a closer file cannot borrow a stronger family to raise a light model
				local raise = function(line: string): string
					-- the parse runs inside the pcall: a list's refusal can come from the parser or from the merge
					local ok, e = pcall(function()
						models.config({
							models.parse(seedText, ".models.toml"),
							models.parse(`[clis.claude]\n{line}\n`, "z/.models.toml"),
						})
					end)
					t.expect(ok).toBe(false)
					return tostring(e)
				end
				t.expect(raise('ultra = [{ id = "claude-haiku-5-5-xhigh", family = "claude-fable-5-2" }]'))
					.toBe(
						"z/.models.toml: clis.claude.ultra[1].family is stated in [catalog] only: a CLI's list names an entry by its id"
					)
				t.expect(raise('ultra = ["claude-haiku-5-5-xhigh"]')).toBe(
					"z/.models.toml: clis.claude.ultra names claude-haiku-5-5-xhigh, which is not placed: place it in [catalog] first"
				)
				-- two ids of one family and one effort word are two entries, and so are two thinking ids of one family
				local cat = '[catalog]\nxlight = ["claude-haiku-5-5-low"]\nlight = ["claude-sonnet-5-5-medium"]\n'
					.. 'heavy = ["claude-opus-5-5-high", "gpt-5.5-high", { id = "gpt-5.5-extra-high", family = "gpt-5.5" }]\n'
					.. 'ultra = ["claude-fable-5-2-xhigh", { id = "claude-4.6-opus-high-thinking", family = "claude-4.6-opus" }, { id = "claude-4.6-opus-max-thinking", family = "claude-4.6-opus" }]\n'
				local both = load(base("") .. cat)
				t.expect(#(models.config(both).catalog :: any).heavy).toBe(3)
				t.expect(#(models.config(both).catalog :: any).ultra).toBe(3)
				-- the single form names an entry whose family the catalog states
				load(
					base(
						'[clis.agent]\nmax_calls = 9\nmax_minutes = 9\nheavy = { model = "gpt-5.5-extra-high" }\n'
					) .. cat
				)
				-- one id twice in one level, and twice across levels
				t.expect(
					refused(
						base("") .. '[catalog]\nheavy = ["claude-opus-5-5-high", "Claude-Opus-5-5-High"]\n'
					)
				)
					.toBe("catalog.heavy names claude-opus-5-5-high twice")
			end
		)

		it(
			"review-005 F6: on claude and grok a list's id is its model and effort, as the single form gives them",
			function()
				local single = load(base('[clis.grok]\nlight = { model = "grok-4.7", effort = "high" }\n'))
				local listedText = string.gsub(
					base('[clis.grok]\nlight = ["grok-4.7-high", "grok-4.7-medium"]\n'),
					'heavy = { model = "claude%-opus%-5%-5", effort = "high" }',
					'heavy = ["claude-opus-5-5-high", "claude-opus-5-5-medium"]'
				)
				local listed = load(listedText)
				local function same(cli: string, act: string, lvl: string)
					local a = models.resolveActivity(single, cli, act, lvl :: any) :: models.Spec
					local b = models.resolveActivity(listed, cli, act, lvl :: any) :: models.Spec
					t.expect(b.model).toBe(a.model)
					t.expect(b.effort).toBe(a.effort)
					t.expect(b.alias).toBe(a.alias)
					t.expect(b.rank).toBe(a.rank)
				end
				same("claude", "code", "risky")
				same("grok", "code", "normal")
				t.expect((models.resolveActivity(listed, "claude", "code", "risky") :: models.Spec).effort)
					.toBe("high")
				t.expect(models.modelsOf(listed, "claude")).toEqual(models.modelsOf(single, "claude"))
				-- the duplicate key reads the id: the list form and the single form of one entry are one entry
				t.expect(
					refused(
						base(
							'[clis.grok]\nlight = ["grok-4.7-high", { model = "grok-4.7", effort = "high" }]\n'
						)
					)
				).toBe("clis.grok.light names grok-4.7-high twice")
				-- an effort word the CLI's flag does not take is refused
				t.expect(refused(base('[clis.grok]\nlight = ["grok-4.7-minimal"]\n'))).toBe(
					"clis.grok.light names grok-4.7-minimal: grok takes its effort as a flag, and minimal is not one (low, medium, high, xhigh, max)"
				)
			end
		)

		it(
			"review-005 F7: review lists meet the catalog and the offers, an offered id is not a prefix, and the seed offers every listed id",
			function()
				-- review-006 F3: agent's -fast spelling finds the catalog's plain entry
				load(
					base('[clis.agent]\nmax_calls = 9\nmax_minutes = 9\nlight = ["grok-4.7-high-fast"]\n')
						.. catalog({ light = { "grok-4.7-high" } })
				)
				-- agy runs GPT-OSS, and no other GPT model
				load(base('[clis.agy]\nheavy = ["gpt-oss-120b-medium"]\n'))
				t.expect(refused(base('[clis.agy]\nheavy = ["gpt-5.5-high"]\n')))
					.toBe("clis.agy.heavy names gpt-5.5-high, not a model of cli agy")
				local cat =
					catalog({ light = { "gemini-4-argon-medium" }, heavy = { "gemini-4-argon-high" } })
				t.expect(refused(base('[clis.agy.review]\nheavy = ["gemini-4-argon-xhigh"]\n') .. cat)).toBe(
					"clis.agy.review.heavy names gemini-4-argon-xhigh, which is not placed: place it in [catalog] first"
				)
				t.expect(refused(base('[clis.agy.review]\nheavy = ["gemini-4-argon-medium"]\n') .. cat)).toBe(
					"clis.agy.review.heavy names gemini-4-argon-medium, which [catalog] places at light: a CLI's list holds an entry at its catalog level or lower, never higher"
				)
				t.expect(
					refused(
						base(
							'[clis.agy]\noffers = ["gemini-4-neon-"]\n[clis.agy.review]\nheavy = ["gemini-4-argon-high"]\n'
						)
					)
				).toBe(
					"clis.agy.review.heavy names gemini-4-argon-high, which clis.agy.offers (set in .models.toml) does not hold"
				)
				-- an id in offers is that id only; a prefix ends in -
				t.expect(
					refused(
						base(
							'[clis.agent]\nmax_calls = 9\nmax_minutes = 9\noffers = ["kimi-k3"]\nheavy = ["kimi-k3-high"]\n'
						)
					)
				).toBe(
					"clis.agent.heavy names kimi-k3-high, which clis.agent.offers (set in .models.toml) does not hold"
				)
				load(
					base(
						'[clis.agent]\nmax_calls = 9\nmax_minutes = 9\noffers = ["kimi-k3-"]\nheavy = ["kimi-k3-high"]\n'
					)
				)
				t.expect(
					refused(
						base("") .. '[catalog]\nultra = [{ id = "claude-fable-5-2-xhigh", context = 0 }]\n'
					)
				)
					.toBe("catalog.ultra[1].context is 0: a whole number of tokens, 1 to 1000000000")
				-- every id each CLI lists, but agent's `auto`, is held by that CLI's offers in the seed
				local cfg = models.config({
					models.parse(fs.readFile(`{FIXTURES}/seed-s1b.models.toml`), ".models.toml"),
				})
				local formats: { [string]: string } =
					{ agent = "^(%S+) %- ", agy = "^(%S+)\t", grok = "^%s+[%-%*] (%S+)" }
				local missing: { string } = {}
				for cli, pattern in formats do
					for line in string.gmatch(fs.readFile(`{FIXTURES}/{cli}-models.txt`), "[^\n]+") do
						local id = string.match(line, pattern)
						if
							id
							and id ~= "auto"
							and not models.offered(cfg.clis[cli].offers :: { string }, id)
						then
							table.insert(missing, `{cli}:{id}`)
						end
					end
				end
				t.expect(missing).toEqual({})
			end
		)

		it("the parser's lists of tables and keys name the new ones", function()
			t.expect(
				has(
					refused(base("") .. "[nope]\nx = 1\n"),
					"the file has catalog, clis, activities, roles, fallback, dispatch and rounds"
				)
			).toBe(true)
			t.expect(refused(base('[clis.agy]\nfast = ["gemini-4-neon-high"]\n'))).toBe(
				"clis.agy.fast is not an alias or setting (xlight, light, heavy, ultra, review, models, offers, runtime, max_calls, max_minutes)"
			)
		end)
	end
)
