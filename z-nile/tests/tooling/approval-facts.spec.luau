--!strict
-- f0437 step 4: the facts the Approvals view shows, built from what `./zn approve <scope> --queue` read. Pure: entries in
-- queue order (a stack's bottom first) in, themes then rafts then tickets out; the order is the person's one linear pass.
local approvalfacts = require("@znile/engine/approvalfacts")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local function entry(id: string, unit: string, tributary: string, state: string?): approvalfacts.Entry
	return {
		id = id,
		title = `Title of {id}`,
		unit = unit,
		unitTitle = if unit == id then `Title of {id}` else `Raft {unit}`,
		tributary = tributary,
		state = state or "waits",
		why = "no approval (1 guesses)",
		place = "origin/main",
		problem = `Problem of {id}`,
		solution = `Solution of {id}`,
		design = { { heading = "Slim design", text = `Design of {id}` } },
		guesses = {
			{
				id = "G1",
				step = "design",
				when = "2026-11-20",
				open = "which",
				chose = "this",
				why = "because",
			},
		},
		reviews = { { name = "design-review-001", verdict = "pass" } },
		hash = "0123456789abcdef0123456789abcdef",
		project = "p",
		tokens = 1200,
		minutes = 14,
		pr = nil,
		branch = nil,
	}
end

local THEMES: { approvalfacts.ThemeDef } = {
	{ project = "p", name = "alpha", purpose = "first" },
	{ project = "p", name = "beta", purpose = "second" },
	{ project = "p", name = "gamma", purpose = "third" },
}

local function byId(x: { id: string }): string
	return x.id
end

-- generic over the element type: a list of themes is not a list of `{ id: string }` (lists are invariant)
local function ids<T>(list: { T }, idOf: (T) -> string): { string }
	local out: { string } = {}
	for _, x in list do
		table.insert(out, idOf(x))
	end
	return out
end

return t.spec("f0437 approval facts: theme, raft bottom first, ticket", function(it)
	it("orders themes as tributaries.toml does, rafts bottom first and tickets as queued", function()
		-- R0002 waits on R0001 (so the queue has R0001's tickets first); beta's R0005 sits between; gamma has nothing waiting
		local entries = {
			entry("c0002", "R0001", "beta"),
			entry("c0003", "R0001", "beta"),
			entry("c0001", "R0002", "beta"),
			entry("c0010", "R0003", "alpha"),
			entry("c0011", "c0011", "alpha"),
			entry("c0020", "R0009", "no-such-theme"),
			entry("c0030", "R0010", "alpha", "working"),
		}
		local facts = approvalfacts.build({
			at = 5,
			run = "20261122T010203Z-a1b2",
			scope = "",
			themes = THEMES,
			entries = entries,
		})
		t.expect(ids(facts.themes, byId)).toEqual({ "alpha", "beta", "unsorted" })
		local beta = facts.themes[2]
		t.expect(ids(beta.rafts, byId)).toEqual({ "R0001", "R0002" })
		t.expect(ids(beta.rafts[1].tickets, byId)).toEqual({ "c0002", "c0003" })
		t.expect(ids(beta.rafts[2].tickets, byId)).toEqual({ "c0001" })
		local alpha = facts.themes[1]
		t.expect(ids(alpha.rafts, byId)).toEqual({ "R0003", "c0011" })
		t.expect(alpha.rafts[2].single).toBe(true)
		t.expect(alpha.rafts[1].single).toBe(false)
		t.expect(facts.version).toBe(1)
		t.expect(facts.run).toBe("20261122T010203Z-a1b2")
	end)

	it("leaves out what is still being worked, and says no theme when nothing waits", function()
		local facts = approvalfacts.build({
			at = 5,
			run = "20261122T010203Z-a1b2",
			scope = "",
			themes = THEMES,
			entries = { entry("c0030", "R0010", "alpha", "working") },
		})
		t.expect(#facts.themes).toBe(0)
		local json = approvalfacts.encode(facts)
		local back = serde.decode("json" :: "json", json)
		t.expect(back.version).toBe(1)
		t.expect(#back.themes).toBe(0)
	end)

	it(
		"pins what the encoder writes for an empty list: the Go reader accepts that form (f0437 empty lists)",
		function()
			local e = entry("c0001", "R0001", "alpha")
			e.guesses, e.reviews, e.design = {}, {}, {}
			local facts = approvalfacts.build({
				at = 5,
				run = "20261122T010203Z-a1b2",
				scope = "",
				themes = THEMES,
				entries = { e },
			})
			local json = approvalfacts.encode(facts)
			-- Luau cannot tell an empty list from an empty map, so Lune's encoder writes `{}` where a list is empty. The daemon's
			-- reader (z-nile/go/internal/web/approvals.go, the list type) accepts `{}` as an empty list, and its cross-check test
			-- (TestEngineEmptyListFixture) holds a fixture shaped like what approvalfacts.encode writes (empty lists as {}). If this
			-- expectation fails, the encoder changed: update the Go fixture and make sure the reader still accepts what is written.
			t.expect(string.find(json, '"guesses":{}', 1, true) ~= nil).toBe(true)
			t.expect(string.find(json, '"reviews":{}', 1, true) ~= nil).toBe(true)
			t.expect(string.find(json, '"design":{}', 1, true) ~= nil).toBe(true)
		end
	)

	it("carries each ticket's idea, design, guesses, reviews, cost and links", function()
		local e = entry("c0001", "R0001", "alpha")
		e.pr = "https://example.test/pr/1"
		e.branch = "c0001-x"
		local facts = approvalfacts.build({
			at = 5,
			run = "20261122T010203Z-a1b2",
			scope = "",
			themes = THEMES,
			entries = { e },
		})
		local back = serde.decode("json" :: "json", approvalfacts.encode(facts))
		local tk = back.themes[1].rafts[1].tickets[1]
		t.expect(tk.idea.problem).toBe("Problem of c0001")
		t.expect(tk.design[1].heading).toBe("Slim design")
		t.expect(tk.guesses[1].chose).toBe("this")
		t.expect(tk.reviews[1].verdict).toBe("pass")
		t.expect(tk.cost.tokens).toBe(1200)
		t.expect(tk.links.pr).toBe("https://example.test/pr/1")
		t.expect(tk.links.branch).toBe("c0001-x")
		-- no cost recorded: the field is absent, never a made-up zero
		local bare = entry("c0002", "R0001", "alpha")
		bare.tokens, bare.minutes = nil, nil
		local b2 = serde.decode(
			"json" :: "json",
			approvalfacts.encode(approvalfacts.build({
				at = 5,
				run = "20261122T010203Z-a1b2",
				scope = "",
				themes = THEMES,
				entries = { bare },
			}))
		)
		t.expect(b2.themes[1].rafts[1].tickets[1].cost).toBe(nil)
	end)

	it("carries the contract hash and the scope of the queue (f0437 review 1, 3)", function()
		local facts = approvalfacts.build({
			at = 5,
			run = "20261122T010203Z-a1b2",
			scope = "R0002",
			themes = THEMES,
			entries = { entry("c0001", "R0002", "alpha") },
		})
		t.expect(facts.scope).toBe("R0002")
		local back = serde.decode("json" :: "json", approvalfacts.encode(facts))
		t.expect(back.scope).toBe("R0002")
		t.expect(back.themes[1].rafts[1].tickets[1].hash).toBe("0123456789abcdef0123456789abcdef")
	end)

	it("clips on a character boundary so the facts always encode (f0437 review 2)", function()
		local dash = "\u{2014}"
		local e = entry("c0001", "R0001", "alpha")
		e.problem = string.rep("a", approvalfacts.TEXT_CAP - 1) .. dash .. "tail"
		e.design =
			{ { heading = "Design", text = string.rep("b", approvalfacts.TEXT_CAP - 2) .. dash .. dash } }
		local facts = approvalfacts.build({
			at = 5,
			run = "20261122T010203Z-a1b2",
			scope = "",
			themes = THEMES,
			entries = { e },
		})
		local json = approvalfacts.encode(facts)
		local back = serde.decode("json" :: "json", json)
		local problem = back.themes[1].rafts[1].tickets[1].idea.problem
		t.expect(utf8.len(problem) ~= nil).toBe(true)
		t.expect(#problem <= approvalfacts.TEXT_CAP + 3).toBe(true)
		local doc = approvalfacts.designParts(
			"## Design\n### Big\n" .. string.rep("c", approvalfacts.TEXT_CAP - 1) .. dash .. "\n"
		)
		t.expect(utf8.len(doc[1].text) ~= nil).toBe(true)
	end)

	it(
		"keeps two projects' same-named themes apart, and a raft's own tributary wins (f0437 review 6)",
		function()
			local a, b = entry("c0001", "R0001", "alpha"), entry("c0002", "R0002", "alpha")
			a.project, b.project = "p", "q"
			local themes: { approvalfacts.ThemeDef } = {
				{ project = "p", name = "alpha", purpose = "p's" },
				{ project = "q", name = "alpha", purpose = "q's" },
			}
			local facts = approvalfacts.build({
				at = 5,
				run = "20261122T010203Z-a1b2",
				scope = "",
				themes = themes,
				entries = { a, b },
			})
			t.expect(#facts.themes).toBe(2)
			t.expect(facts.themes[1].purpose).toBe("p's")
			t.expect(facts.themes[2].purpose).toBe("q's")
			t.expect(approvalfacts.themeOf("beta", "alpha")).toBe("beta")
			t.expect(approvalfacts.themeOf("", "alpha")).toBe("alpha")
		end
	)

	it("cuts the Design section into its headed parts, short", function()
		local doc =
			"## Problem\nP\n\n## Design\nIntro line.\n\n### Slim design\nOne.\nTwo.\n\n### Touched modules\n- `a`\n\n## Acceptance criteria\nAC\n"
		local parts = approvalfacts.designParts(doc)
		t.expect(#parts).toBe(3)
		t.expect(parts[1].heading).toBe("Design")
		t.expect(parts[1].text).toBe("Intro line.")
		t.expect(parts[2].heading).toBe("Slim design")
		t.expect(parts[2].text).toBe("One.\nTwo.")
		t.expect(parts[3].heading).toBe("Touched modules")
		local long = approvalfacts.designParts("## Design\n### Big\n" .. string.rep("x", 5000) .. "\n")
		t.expect(#long[1].text <= approvalfacts.TEXT_CAP + 3).toBe(true)
		t.expect(#approvalfacts.designParts("## Design\n<!-- only a comment -->\n")).toBe(0)
	end)
end)
