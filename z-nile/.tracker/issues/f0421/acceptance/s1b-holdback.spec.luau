--!strict
-- f0421 slice 3, S1b, AC33 (design-review-002 F2): a session's own work on a CLI whose session file the engine does not
-- read (any but claude and grok) takes no final review and no activity the ROOT file sets at ultra, on every path that hands
-- work to a session; a step the engine starts (`./zn dispatch`, `./zn idea`) is told apart by an explicit input and is not
-- held back by this rule. One case per path. Sequestered: red until S1b is built.
local fs = require("@lune/fs")
local modelcmd = require("@znile/engine/modelcmd")
local models = require("@znile/engine/models")
local t = require("@tests/lib/t")
local work = require("@znile/engine/work")
local workerlive = require("@znile/engine/workerlive")

local FIXTURES = "tests/fixtures/models"
local SEED = fs.readFile(`{FIXTURES}/seed-s1b.models.toml`)

local function has(s: string?, part: string): boolean
	return s ~= nil and string.find(s, part, 1, true) ~= nil
end

-- today's root (no catalog, so a list may name its model at any level) with kimi given its one model at every level, ultra
-- included: a declared-only CLI with one model and no ZN_MODEL
local ROOT = fs.readFile(`{FIXTURES}/root-5e8f5eaa4.models.toml`)
local function kimiEverywhere(): string
	return (
		string.gsub(
			ROOT,
			'heavy = { model = "kimi%-code%-k3%.1%-pro" }',
			'xlight = { model = "kimi-code-k3.1-pro" }\nlight = { model = "kimi-code-k3.1-pro" }\nheavy = { model = "kimi-code-k3.1-pro" }\nultra = { model = "kimi-code-k3.1-pro" }'
		)
	)
end
local function walk(text: string): { models.Layer }
	return { models.parse(text, ".models.toml") }
end

local HELD =
	"is top-level work, and kimi only declares the model its session runs: only the owner's ruling (f0421, question 3) changes that"

return t.spec("f0421 S1b AC33: the hold-back on every path", function(it)
	it(
		"./zn model's path (resolveActivity, a session's own work) refuses the final review and ultra work with the fifth refusal",
		function()
			local l = walk(kimiEverywhere())
			local final, why = models.resolveActivity(l, "kimi", "final-review", "normal")
			t.expect(final).toBe(nil)
			t.expect(why).toBe(`final-review/normal {HELD}`)
			local risky, why2 = models.resolveActivity(l, "kimi", "code-review", "risky")
			t.expect(risky).toBe(nil)
			t.expect(why2).toBe(`code-review/risky {HELD}`)
			-- the same CLI below ultra delivers, and claude (its session file is read) is never held back
			t.expect(models.resolveActivity(l, "kimi", "code-review", "normal") ~= nil).toBe(true)
			t.expect(models.resolveActivity(l, "claude", "final-review", "normal") ~= nil).toBe(true)
		end
	)

	it("--can and the registration's list leave the held-back pairs out", function()
		local l = walk(kimiEverywhere())
		local can = table.concat(models.canList(l, "kimi"), ",")
		t.expect(has(can, "final-review/")).toBe(false)
		t.expect(has(can, "idea-challenge/")).toBe(false)
		t.expect(has(can, "code-review/risky")).toBe(false)
		t.expect(has(can, "code-review/normal")).toBe(true)
		local listed = workerlive.canFor("kimi", { ZN_CLI = "kimi" }, function(): { any }?
			return l
		end)
		t.expect(table.concat(listed, ",")).toBe(can)
	end)

	it("deliverers and the waiting line count only who may take it", function()
		local l = walk(kimiEverywhere())
		t.expect(models.deliverers(l, "final-review", "normal")).toEqual({ "claude" })
		t.expect(models.waiting(l, "final-review", "normal")).toBe("final-review/normal (ultra: claude)")
	end)

	it(
		"a step the engine starts (./zn dispatch --cli kimi --mode final, ./zn idea --cli kimi) is not held back by it",
		function()
			local l = walk(kimiEverywhere())
			local dispatched = models.resolveReview(l, "kimi", "final-review", "normal", {}, nil, true)
			t.expect(dispatched ~= nil and dispatched.model).toBe("kimi-code-k3.1-pro")
			local idea = models.resolveActivity(l, "kimi", "idea-challenge", "normal", nil, nil, true)
			t.expect(idea ~= nil and idea.model).toBe("kimi-code-k3.1-pro")
			-- on the step-one seed agent has no ultra, so a dispatched final review on agent ends undeliverable
			local seed = walk(SEED)
			t.expect(models.resolveReview(seed, "agent", "final-review", "normal", {}, nil, true)).toBe(nil)
			t.expect(models.resolveActivity(seed, "agent", "idea-challenge", "normal", nil, nil, true))
				.toBe(nil)
		end
	)

	it(
		"a closer file that moves an activity's level does not move the hold-back: the root file's setting decides",
		function()
			local layers = {
				models.parse(kimiEverywhere(), ".models.toml"),
				models.parse('[activities.code-review]\nrisky = "heavy"\n', "pickman/.models.toml"),
			}
			local spec, why = models.resolveActivity(layers, "kimi", "code-review", "risky")
			t.expect(spec).toBe(nil)
			t.expect(why).toBe(`code-review/risky {HELD}`)
		end
	)

	it(
		"work next: an agent's session that names no CLI is handed nothing, with the line to set ZN_CLI",
		function()
			local cap = workerlive.capability({ CURSOR_AGENT = "1" }, function(): { any }?
				return walk(SEED)
			end)
			t.expect(cap ~= nil).toBe(true)
			local d = workerlive.decide(
				work,
				{ capable = cap, rafts = {}, issues = {} },
				nil,
				nil,
				function(): (any, string?)
					return nil, nil
				end
			)
			t.expect(d.action).toBe("none")
			t.expect(has(d.why, "set ZN_CLI")).toBe(true)
			-- a person's shell with no CLI named and no marker stays unfiltered, as today (G-can3)
			local _, why = workerlive.capability({}, function(): { any }?
				return walk(SEED)
			end)
			t.expect(has(why, "work next is not filtered")).toBe(true)
		end
	)

	it(
		"the fifth refusal is not among a session model's four causes: ZN_MODEL is accepted, the work is not",
		function()
			local l = walk(kimiEverywhere())
			local session, problem = modelcmd.sessionModel({ ZN_MODEL = "" }, l, "kimi")
			t.expect(session).toBe(nil)
			t.expect(problem).toBe(nil) -- one model: nothing to name
		end
	)
end)
