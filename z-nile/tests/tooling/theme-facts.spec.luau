--!strict
-- f0437 step 5: the facts the app's home view (the themes overview) and the Approvals view's "what is coming" strip show.
-- Pure: units (what the board read) in, one row per theme out, in tributaries.toml order, then `unsorted`. The one rule that
-- says "done, in flight, waiting for you, not started" is tributaries.classify; the board uses it too.
local approvalfacts = require("@znile/engine/approvalfacts")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")
local themefacts = require("@znile/engine/themefacts")
local tributaries = require("@znile/engine/tributaries")

local DEFS: { themefacts.ThemeDef } = {
	{ project = "p", name = "alpha", purpose = "first theme" },
	{ project = "p", name = "beta", purpose = "second theme" },
	{ project = "p", name = "gamma", purpose = "nothing here" },
}

local function unit(id: string, themes: { string }, extra: { [string]: any }?): themefacts.Unit
	local u: any = {
		id = id,
		title = `Title {id}`,
		project = "p",
		themes = themes,
		done = false,
		inFlight = false,
		questions = false,
		approval = false,
		stage = "idea",
		since = nil,
		holders = {},
		claimed = false,
		claimedAt = nil,
		ids = { id },
	}
	local given: { [string]: any } = extra or {}
	for k, v in given do
		u[k] = v
	end
	return u :: themefacts.Unit
end

local function build(units: { themefacts.Unit }): themefacts.Facts
	return themefacts.build({
		at = 100,
		themes = DEFS,
		units = units,
		approvalsAt = nil,
		approvalsScope = "",
		live = true,
	})
end

local function names(list: { themefacts.Theme }): { string }
	local out: { string } = {}
	for _, th in list do
		table.insert(out, th.id)
	end
	return out
end

return t.spec("f0437 theme facts: counts per theme, one rule", function(it)
	it(
		"classifies by one rule: done, then waiting on the owner, then approval, then in flight, else not started",
		function()
			local function c(f: { [string]: boolean }): string
				return tributaries.classify({
					done = f.done == true,
					inFlight = f.inFlight == true,
					questions = f.questions == true,
					approval = f.approval == true,
				})
			end
			t.expect(c({})).toBe("open")
			t.expect(c({ inFlight = true })).toBe("flight")
			t.expect(c({ inFlight = true, approval = true })).toBe("approval")
			t.expect(c({ inFlight = true, approval = true, questions = true })).toBe("owner")
			t.expect(c({ questions = true })).toBe("owner")
			t.expect(c({ approval = true })).toBe("approval")
			t.expect(c({ done = true, questions = true, approval = true, inFlight = true })).toBe("done")
		end
	)

	it("one row per theme in tributaries.toml order, an empty one included, then unsorted", function()
		local facts = build({
			unit("c0001", { "beta" }, { done = true }),
			unit("c0002", { "alpha" }, { inFlight = true, stage = "code" }),
			unit("c0003", { "unsorted" }),
		})
		t.expect(names(facts.themes)).toEqual({ "alpha", "beta", "gamma", "unsorted" })
		t.expect(facts.themes[3].counts).toEqual({ done = 0, flight = 0, approval = 0, owner = 0, open = 0 })
		t.expect(facts.themes[1].purpose).toBe("first theme")
		t.expect(facts.themes[4].counts.open).toBe(1)
		t.expect(facts.version).toBe(1)
	end)

	it("leaves unsorted out when it holds nothing, and counts a name no file defines as unsorted", function()
		local without = build({ unit("c0001", { "alpha" }) })
		t.expect(names(without.themes)).toEqual({ "alpha", "beta", "gamma" })
		local stray = build({ unit("c0001", { "no-such-theme" }) })
		t.expect(names(stray.themes)).toEqual({ "alpha", "beta", "gamma", "unsorted" })
		t.expect(stray.themes[4].counts.open).toBe(1)
	end)

	it(
		"counts each phase, never a unit twice inside one theme, and a unit in every theme it names",
		function()
			local facts = build({
				unit("c0001", { "alpha" }, { done = true }),
				unit("c0002", { "alpha" }, { inFlight = true }),
				unit("c0003", { "alpha" }, { approval = true }),
				unit("c0004", { "alpha" }, { questions = true }),
				unit("c0005", { "alpha" }),
				-- a raft whose members name alpha twice and beta once: alpha once, beta once
				unit("R0001", { "alpha", "alpha", "beta" }, { inFlight = true, stage = "code" }),
			})
			t.expect(facts.themes[1].counts)
				.toEqual({ done = 1, flight = 2, approval = 1, owner = 1, open = 1 })
			t.expect(facts.themes[2].counts)
				.toEqual({ done = 0, flight = 1, approval = 0, owner = 0, open = 0 })
		end
	)

	it("keys a theme by project: the same name in two projects is two rows", function()
		local defs: { themefacts.ThemeDef } = {
			{ project = "p", name = "alpha", purpose = "p's" },
			{ project = "q", name = "alpha", purpose = "q's" },
		}
		local facts = themefacts.build({
			at = 1,
			themes = defs,
			units = {
				unit("c0001", { "alpha" }, { done = true }),
				unit("c0002", { "alpha" }, { project = "q" }),
			},
			approvalsAt = nil,
			approvalsScope = "",
			live = true,
		})
		t.expect(#facts.themes).toBe(2)
		t.expect(facts.themes[1].counts.done).toBe(1)
		t.expect(facts.themes[2].counts.open).toBe(1)
		t.expect(facts.themes[1].project).toBe("p")
	end)

	it(
		"names the workers that hold units in a theme, once each and in order, and lists what is on its way",
		function()
			local facts = build({
				unit("c0001", { "alpha" }, { inFlight = true, stage = "design", holders = { "kimi b" } }),
				unit(
					"R0002",
					{ "alpha" },
					{ inFlight = true, stage = "code", holders = { "claude a" }, since = 40 }
				),
				unit("c0003", { "alpha" }, { inFlight = true, stage = "code", holders = { "claude a" } }),
				unit("c0004", { "alpha" }, { questions = true, stage = "idea" }),
				unit("c0005", { "alpha" }, { approval = true, stage = "approval" }),
				unit("c0006", { "alpha" }, { done = true, stage = "landed", holders = { "gone z" } }),
			})
			local alpha = facts.themes[1]
			t.expect(alpha.workers).toEqual({ "claude a", "kimi b" })
			local ids: { string } = {}
			for _, u in alpha.units do
				table.insert(ids, u.id)
			end
			t.expect(ids).toEqual({ "c0001", "R0002", "c0003", "c0004" })
			t.expect(alpha.units[2].stage).toBe("code")
			t.expect(alpha.units[2].holder).toBe("claude a")
			t.expect(alpha.units[2].since).toBe(40)
			t.expect(alpha.units[3].since).toBe(nil)
			t.expect(alpha.units[4].phase).toBe("owner")
			t.expect(alpha.units[4].holder).toBe("")
		end
	)

	it("says whether the live layer and the approval queue were known when the facts were made", function()
		local facts = themefacts.build({
			at = 100,
			themes = DEFS,
			units = {},
			approvalsAt = 90,
			approvalsScope = "R0002",
			live = false,
		})
		t.expect(facts.live).toBe(false)
		t.expect(facts.approvalsAt).toBe(90)
		t.expect(facts.approvalsScope).toBe("R0002")
		local json = serde.decode("json" :: "json", themefacts.encode(build({})))
		t.expect(json.live).toBe(true)
		t.expect(json.approvalsAt).toBe(nil)
		t.expect(#json.themes).toBe(3)
	end)

	it("reads the units that wait from the approval facts file, and nothing from a bad one", function()
		local text =
			'{"version":1,"at":77,"run":"r","scope":"R0002","themes":[{"id":"alpha","rafts":[{"id":"R0001","tickets":[]},{"id":"c0009","tickets":[]}]},{"id":"beta","rafts":[{"id":"R0001","tickets":[]}]}]}'
		local got = approvalfacts.waiting(text)
		t.expect(got ~= nil).toBe(true)
		local w = got :: approvalfacts.Waiting
		t.expect(w.units["R0001"]).toBe(true)
		t.expect(w.units["c0009"]).toBe(true)
		t.expect(w.units["c0001"]).toBe(nil)
		t.expect(w.at).toBe(77)
		t.expect(w.scope).toBe("R0002")
		t.expect(approvalfacts.waiting("{")).toBe(nil)
		t.expect(approvalfacts.waiting('{"version":2,"themes":[]}')).toBe(nil)
		t.expect(approvalfacts.waiting('{"version":1}')).toBe(nil)
	end)

	-- a full model entry, as board.collect makes it (one fact per unit: asks, holders, active)
	local function mraft(
		id: string,
		line: string,
		stage: string,
		members: { string },
		extra: { [string]: any }?
	): any
		local r: any = {
			id = id,
			title = `Raft {id}`,
			project = "p",
			tributary = line,
			stage = stage,
			state = if stage == "done" then "done" elseif stage == "active" then "active" else "backlog",
			inFlight = stage == "active",
			work = stage ~= "done" and #members > 0,
			issues = members,
			questions = false,
			asks = false,
			holders = {},
			claimed = false,
			claimedAt = nil,
			rounds = { design = 0, code = 0 },
			activeAt = nil,
		}
		local given: { [string]: any } = extra or {}
		for k, v in given do
			r[k] = v
		end
		return r
	end
	local function missue(
		id: string,
		raft: string?,
		line: string,
		stage: string,
		extra: { [string]: any }?
	): any
		local i: any = {
			id = id,
			title = `T {id}`,
			project = "p",
			raft = raft,
			tributary = line,
			ownLine = line,
			stage = stage,
			state = if stage == "done" then "done" elseif stage == "active" then "active" else "backlog",
			inFlight = stage == "active",
			work = stage ~= "done",
			questions = false,
			asks = false,
			holders = {},
			claimed = false,
			claimedAt = nil,
		}
		local given: { [string]: any } = extra or {}
		for k, v in given do
			i[k] = v
		end
		return i
	end
	local function unitsOf(
		rafts: { any },
		issues: { any },
		waiting: { [string]: boolean }?
	): { [string]: themefacts.Unit }
		local by: { [string]: themefacts.Unit } = {}
		for _, u in themefacts.units({ rafts = rafts, issues = issues } :: any, waiting or {}) do
			by[u.id] = u
		end
		return by
	end

	it(
		"builds units from the board's model: a raft belongs to its own theme and every one its members name",
		function()
			local by = unitsOf({
				mraft("R0001", "alpha", "active", { "c0001", "c0002" }, { activeAt = 50 }),
				mraft("R0002", "unsorted", "prepared", { "c0003" }),
				mraft("R0003", "alpha", "done", { "c0004" }),
				mraft("R0004", "beta", "active", { "c0005" }, { holders = { "claude w1" } }),
				mraft("R0005", "unsorted", "backlog", {}),
				mraft("R0006", "gamma", "preparing", { "c0010" }),
			}, {
				missue("c0001", "R0001", "alpha", "active"),
				missue("c0002", "R0001", "beta", "active"),
				missue("c0003", "R0002", "unsorted", "prepared"),
				missue("c0004", "R0003", "alpha", "done"),
				missue("c0005", "R0004", "beta", "active"),
				missue("c0006", nil, "gamma", "preparing", { claimed = true }),
				missue("c0010", "R0006", "gamma", "preparing"),
				missue("c0007", nil, "unsorted", "new"),
				missue("c0008", nil, "earlier-work", "done"),
				missue("c0009", nil, "alpha", "prepared", { questions = true, asks = true }),
			}, { R0004 = true })
			t.expect(by["R0005"]).toBe(nil) -- an empty open raft is no work
			t.expect(by["c0001"]).toBe(nil) -- a member is its raft's, not a unit
			t.expect(by["c0008"].themes).toEqual({ "earlier-work" })
			t.expect(by["R0001"].themes).toEqual({ "alpha", "beta" })
			t.expect(by["R0001"].ids).toEqual({ "R0001", "c0001", "c0002" })
			t.expect(by["R0001"].stage).toBe("code")
			t.expect(by["R0001"].since).toBe(50)
			t.expect(by["R0003"].done).toBe(true)
			t.expect(by["R0003"].stage).toBe("landed")
			t.expect(by["R0002"].themes).toEqual({ "unsorted" })
			t.expect(by["R0002"].stage).toBe("ready") -- prepared, not coded
			t.expect(by["R0004"].approval).toBe(true)
			t.expect(by["R0004"].stage).toBe("approval")
			t.expect(by["R0004"].holders).toEqual({ "claude w1" })
			t.expect(by["c0006"].inFlight).toBe(false) -- a stored claim with no live holder is not in flight
			t.expect(by["c0006"].claimed).toBe(true)
			t.expect(by["R0006"].inFlight).toBe(false)
			t.expect(by["R0006"].stage).toBe("design")
			t.expect(by["c0006"].stage).toBe("design")
			t.expect(by["c0007"].stage).toBe("idea")
			t.expect(by["c0007"].inFlight).toBe(false)
			t.expect(by["c0009"].questions).toBe(true)
			t.expect(by["c0009"].stage).toBe("bundle")
		end
	)

	it("a held unit is in flight whatever its stage, and a held raft says so by its members' ids", function()
		local by = unitsOf({}, { missue("c0001", nil, "alpha", "new", { holders = { "grok w9" } }) })
		t.expect(by["c0001"].inFlight).toBe(true)
		t.expect(by["c0001"].holders).toEqual({ "grok w9" })
		local raftBy = unitsOf(
			{ mraft("R0001", "alpha", "prepared", { "c0001" }, { holders = { "kimi w3" } }) },
			{ missue("c0001", "R0001", "alpha", "prepared") }
		)
		t.expect(raftBy["R0001"].inFlight).toBe(true)
		t.expect(raftBy["R0001"].stage).toBe("ready") -- held, but not in active/: not `code`
	end)

	it("counts no earlier-work unit anywhere, and clips a long title", function()
		local long = string.rep("x", 500)
		local facts = build({
			unit("c0001", { "earlier-work" }, { done = true }),
			unit("c0002", { "alpha" }, { inFlight = true, stage = "code", title = long }),
		})
		t.expect(names(facts.themes)).toEqual({ "alpha", "beta", "gamma" })
		t.expect(facts.themes[1].counts.done).toBe(0)
		t.expect(#facts.themes[1].units[1].title <= themefacts.TITLE_CAP + 3).toBe(true)
		t.expect(#facts.themes[1].units[1].title < #long).toBe(true)
	end)

	it("a prepared raft is ready, never code: held, with questions or neither", function()
		local member = missue("c0001", "R0001", "alpha", "prepared")
		for _, extra in { {}, { holders = { "kimi w3" } }, { asks = true, questions = true } } do
			local by = unitsOf({ mraft("R0001", "alpha", "prepared", { "c0001" }, extra) }, { member })
			t.expect(by["R0001"].stage).toBe("ready")
		end
		local coding = unitsOf({ mraft("R0001", "alpha", "active", { "c0001" }) }, { member })
		t.expect(coding["R0001"].stage).toBe("code")
	end)

	it("a question in a member blocks the raft on the owner; the raft's own questions too", function()
		local asking = missue("c0001", "R0001", "alpha", "prepared", { questions = true, asks = true })
		-- the model's one fact: board.collect sets asks on the raft from its members, and the units read it
		local by = unitsOf({ mraft("R0001", "alpha", "prepared", { "c0001" }, { asks = true }) }, { asking })
		t.expect(by["R0001"].questions).toBe(true)
		t.expect(tributaries.classify(by["R0001"])).toBe("owner")
	end)

	it(
		"a stored claim with no live holder counts where it would without the claim, and the strip says so",
		function()
			local by = unitsOf({}, {
				missue("c0180", nil, "alpha", "preparing", { claimed = true, claimedAt = "2026-10-31" }),
				missue("c0181", nil, "alpha", "new"),
			})
			t.expect(tributaries.classify(by["c0180"])).toBe("open")
			-- the same for a raft that a session took to group (a stored stamp on the raft, no live holder)
			local raftBy = unitsOf({
				mraft(
					"R0093",
					"alpha",
					"preparing",
					{ "c0093" },
					{ claimed = true, claimedAt = "2026-10-31" }
				),
			}, { missue("c0093", "R0093", "alpha", "preparing") })
			t.expect(raftBy["R0093"].inFlight).toBe(false)
			t.expect(tributaries.classify(raftBy["R0093"])).toBe("open")
			t.expect(raftBy["R0093"].stage).toBe("bundle")
			t.expect(by["c0180"].claimedAt).toBe("2026-10-31")
			local facts = themefacts.build({
				at = 1,
				themes = DEFS,
				units = { by["c0180"], by["c0181"] },
				approvalsAt = nil,
				approvalsScope = "",
				live = true,
				commit = "abc1234",
			})
			t.expect(facts.commit).toBe("abc1234")
			local alpha = facts.themes[1]
			t.expect(alpha.counts.open).toBe(2) -- both not started
			t.expect(alpha.counts.flight).toBe(0)
			t.expect(#alpha.units).toBe(1) -- only the claimed one is listed
			t.expect(alpha.units[1].phase).toBe("claimed")
			t.expect(alpha.units[1].claimedAt).toBe("2026-10-31")
			t.expect(alpha.units[1].holder).toBe("")
		end
	)

	it("a raft with a review file and an active time shows no review duration and no review stage", function()
		local by = unitsOf({
			mraft(
				"R0001",
				"alpha",
				"active",
				{ "c0001" },
				{ rounds = { design = 1, code = 2 }, activeAt = 77 }
			),
		}, { missue("c0001", "R0001", "alpha", "active") })
		t.expect(by["R0001"].stage).toBe("code") -- no record says when review began, so the word is dropped
		t.expect(by["R0001"].stage ~= "review").toBe(true)
		t.expect(by["R0001"].since).toBe(77) -- the time it entered active/, which is when code began
		local prepared = unitsOf(
			{ mraft("R0002", "alpha", "prepared", { "c0002" }, { activeAt = 77, holders = { "kimi w1" } }) },
			{ missue("c0002", "R0002", "alpha", "prepared") }
		)
		t.expect(prepared["R0002"].since).toBe(nil) -- never a duration for a stage a record does not time
	end)

	it(
		"pins what the encoder writes for an empty list: the Go reader accepts that form (f0437 empty lists)",
		function()
			-- Luau cannot tell an empty list from an empty map, so Lune's encoder writes `{}` where a list is empty. The daemon's
			-- reader (z-nile/go/internal/web/themes.go, the list type of approvals.go) takes `{}` as an empty list for every list
			-- of this file (themes, workers, units); its tests (TestEveryThemesListTakesAnEmptyObjectAndRefusesAFullOne) hold
			-- fixtures shaped like this text. If this expectation fails the encoder changed: update them.
			local empty = themefacts.encode(themefacts.build({
				at = 5,
				themes = {},
				units = {},
				approvalsAt = nil,
				approvalsScope = "",
				live = true,
			}))
			t.expect(string.find(empty, '"themes":{}', 1, true) ~= nil).toBe(true)
			local quiet = themefacts.encode(build({}))
			t.expect(string.find(quiet, '"workers":{}', 1, true) ~= nil).toBe(true)
			t.expect(string.find(quiet, '"units":{}', 1, true) ~= nil).toBe(true)
			local busy = themefacts.encode(build({
				unit("c0001", { "alpha" }, { inFlight = true, stage = "code", holders = { "claude w1" } }),
			}))
			t.expect(string.find(busy, '"workers":["claude w1"]', 1, true) ~= nil).toBe(true) -- a full list stays an array
			t.expect(string.find(busy, '"units":[{', 1, true) ~= nil).toBe(true)
		end
	)
end)
