--!strict
-- f0437 step 5: the facts the app's home view (the themes overview) and the Approvals view's "what is coming" strip show.
-- Pure: units (what the board read) in, one row per theme out, in tributaries.toml order, then `unsorted`. The one rule that
-- says "done, in flight, waiting for you, not started" is tributaries.classify; the board uses it too.
local board = require("@znile/engine/board")
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
		local got = themefacts.waiting(text)
		t.expect(got ~= nil).toBe(true)
		local w = got :: themefacts.Waiting
		t.expect(w.units["R0001"]).toBe(true)
		t.expect(w.units["c0009"]).toBe(true)
		t.expect(w.units["c0001"]).toBe(nil)
		t.expect(w.at).toBe(77)
		t.expect(w.scope).toBe("R0002")
		t.expect(themefacts.waiting("{")).toBe(nil)
		t.expect(themefacts.waiting('{"version":2,"themes":[]}')).toBe(nil)
		t.expect(themefacts.waiting('{"version":1}')).toBe(nil)
	end)

	it(
		"builds units from the board's model: a raft belongs to its own theme and every one its members name",
		function()
			local function issue(
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
					state = if stage == "done"
						then "done"
						elseif stage == "active" then "active"
						else "backlog",
					inFlight = stage == "active",
					work = stage ~= "done",
					questions = false,
					claimed = false,
				}
				local given: { [string]: any } = extra or {}
				for k, v in given do
					i[k] = v
				end
				return i
			end
			local function raft(
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
					state = if stage == "done"
						then "done"
						elseif stage == "active" then "active"
						else "backlog",
					inFlight = stage == "active",
					work = stage ~= "done" and #members > 0,
					issues = members,
					questions = false,
					claimed = false,
					rounds = { design = 0, code = 0 },
					activeAt = nil,
				}
				local given: { [string]: any } = extra or {}
				for k, v in given do
					r[k] = v
				end
				return r
			end
			local model: any = {
				rafts = {
					raft("R0001", "alpha", "active", { "c0001", "c0002" }, { activeAt = 50 }),
					raft("R0002", "unsorted", "prepared", { "c0003" }),
					raft("R0003", "alpha", "done", { "c0004" }),
					raft("R0004", "beta", "active", { "c0005" }, { rounds = { design = 1, code = 1 } }),
					raft("R0005", "unsorted", "backlog", {}),
					raft("R0006", "gamma", "preparing", { "c0010" }),
				},
				issues = {
					issue("c0001", "R0001", "alpha", "active"),
					issue("c0002", "R0001", "beta", "active"),
					issue("c0003", "R0002", "unsorted", "prepared"),
					issue("c0004", "R0003", "alpha", "done"),
					issue("c0005", "R0004", "beta", "active"),
					issue("c0006", nil, "gamma", "preparing", { claimed = true }),
					issue("c0010", "R0006", "gamma", "preparing"),
					issue("c0007", nil, "unsorted", "new"),
					issue("c0008", nil, "earlier-work", "done"),
					issue("c0009", nil, "alpha", "prepared", { questions = true }),
				},
			}
			local live = {
				at = 1,
				workers = { { id = "w1", cli = "claude", state = "working", can = {} } },
				claims = { { unit = "c0005", activity = "code", worker = "w1", raft = "R0004", since = 9 } },
			}
			local units = themefacts.units(model :: board.Model, { R0004 = true }, live :: any)
			local by: { [string]: themefacts.Unit } = {}
			for _, u in units do
				by[u.id] = u
			end
			t.expect(by["R0005"]).toBe(nil) -- an empty open raft is no work
			t.expect(by["c0001"]).toBe(nil) -- a member is its raft's, not a unit
			t.expect(by["c0008"].themes).toEqual({ "earlier-work" })
			t.expect(by["R0001"].themes).toEqual({ "alpha", "beta" })
			t.expect(by["R0001"].stage).toBe("code")
			t.expect(by["R0001"].since).toBe(50)
			t.expect(by["R0003"].done).toBe(true)
			t.expect(by["R0003"].stage).toBe("landed")
			t.expect(by["R0002"].themes).toEqual({ "unsorted" })
			t.expect(by["R0004"].approval).toBe(true)
			t.expect(by["R0004"].stage).toBe("approval")
			t.expect(by["R0004"].holders).toEqual({ "claude w1" })
			t.expect(by["c0006"].inFlight).toBe(true) -- a claimed design is in flight
			t.expect(by["R0006"].inFlight).toBe(false) -- a draft nobody took is not
			t.expect(by["R0006"].stage).toBe("design")
			t.expect(by["c0006"].stage).toBe("design")
			t.expect(by["c0007"].stage).toBe("idea")
			t.expect(by["c0007"].inFlight).toBe(false)
			t.expect(by["c0009"].questions).toBe(true)
			t.expect(by["c0009"].stage).toBe("bundle")
		end
	)

	it("counts a unit a worker holds as in flight, whatever its stage", function()
		local model: any = {
			rafts = {},
			issues = {
				{
					id = "c0001",
					project = "p",
					tributary = "alpha",
					ownLine = "alpha",
					stage = "new",
					state = "backlog",
					inFlight = false,
					claimed = false,
					work = true,
					questions = false,
					title = "t",
				},
			},
		}
		local live: any = {
			at = 1,
			workers = { { id = "w9", cli = "grok", state = "working", can = {} } },
			claims = { { unit = "c0001", activity = "design", worker = "w9" } },
		}
		local u = themefacts.units(model :: board.Model, {}, live)[1]
		t.expect(u.inFlight).toBe(true)
		t.expect(u.holders).toEqual({ "grok w9" })
	end)

	it("names a raft with a code review file in review, and never invents a time", function()
		local model: any = {
			rafts = {
				{
					id = "R0001",
					title = "x",
					project = "p",
					tributary = "alpha",
					stage = "active",
					state = "active",
					inFlight = true,
					work = true,
					issues = { "c0001" },
					questions = false,
					rounds = { design = 1, code = 1 },
					activeAt = nil,
				},
			},
			issues = {
				{
					id = "c0001",
					raft = "R0001",
					project = "p",
					tributary = "alpha",
					ownLine = "alpha",
					stage = "active",
					state = "active",
					inFlight = true,
					work = false,
					questions = false,
					title = "t",
				},
			},
		}
		local u = themefacts.units(model :: board.Model, {}, nil)[1]
		t.expect(u.stage).toBe("review")
		t.expect(u.since).toBe(nil)
		t.expect(#u.holders).toBe(0)
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

	it("reads a raft's own state from its members, its claims and its stage", function()
		local function raft(extra: { [string]: any }?): any
			local r: any = {
				id = "R0001",
				title = "Raft",
				project = "p",
				tributary = "alpha",
				stage = "prepared",
				state = "backlog",
				inFlight = false,
				work = true,
				issues = { "c0001" },
				questions = false,
				claimed = false,
				rounds = { design = 0, code = 0 },
				activeAt = 77,
			}
			local given: { [string]: any } = extra or {}
			for k, v in given do
				r[k] = v
			end
			return r
		end
		local member: any = {
			id = "c0001",
			raft = "R0001",
			project = "p",
			tributary = "alpha",
			ownLine = "alpha",
			stage = "prepared",
			state = "backlog",
			inFlight = false,
			claimed = false,
			work = false,
			questions = false,
			title = "m",
		}
		local function first(r: any, issue: any, live: any): themefacts.Unit
			return themefacts.units({ rafts = { r }, issues = { issue } } :: any, {}, live)[1]
		end
		-- a question in a member blocks the whole raft on the owner
		local asking = table.clone(member)
		asking.questions = true
		local u = first(raft(), asking, nil)
		t.expect(u.questions).toBe(true)
		t.expect(tributaries.classify(u)).toBe("owner")
		-- a worker's claim on the raft id alone (its ticket not listed as a member) holds it and puts it in flight
		local live: any = {
			at = 1,
			workers = { { id = "w3", cli = "kimi", state = "working", can = {} } },
			claims = { { unit = "c9999", activity = "bundle", worker = "w3", raft = "R0001" } },
		}
		local held = first(raft(), member, live)
		t.expect(held.holders).toEqual({ "kimi w3" })
		t.expect(held.inFlight).toBe(true)
		-- a time is carried only for a raft being coded or reviewed, never for a design or a bundle, though activeAt is set
		local designing = first(raft({ claimed = true, stage = "preparing" }), member, nil)
		t.expect(designing.stage).toBe("bundle")
		t.expect(designing.since).toBe(nil)
		local coding = first(raft({ stage = "active", state = "active", inFlight = true }), member, nil)
		t.expect(coding.stage).toBe("code")
		t.expect(coding.since).toBe(77)
		local reviewing = first(
			raft({ stage = "active", state = "active", inFlight = true, rounds = { design = 1, code = 1 } }),
			member,
			nil
		)
		t.expect(reviewing.stage).toBe("review")
		t.expect(reviewing.since).toBe(77)
		local noReview = first(raft({ stage = "active", state = "active", inFlight = true }), member, nil)
		t.expect(noReview.stage).toBe("code") -- no code review file: still code
	end)
end)
