--!strict
-- f0422: the tributary file (definitions only) and the unit's own `tributary:` line: the parser, every problem the
-- definitions' check names, where a unit stands, the counts, `audit.tributaries` on fixture trees and on the real
-- tracker (the gate's check that no unit names a tributary that is not defined), and `./zn list` with tributaries.
local audit = require("@znile/engine/audit")
local board = require("@znile/engine/board")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local themefacts = require("@znile/engine/themefacts")
local trackerfix = require("@tests/lib/trackerfix")
local tributaries = require("@znile/engine/tributaries")
local work = require("@znile/engine/work")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function parsed(text: string): { tributaries.Tributary }
	local list, problem = tributaries.parse(text)
	if not list then
		error(problem or "no list", 0)
	end
	return list
end

local function tr(name: string): tributaries.Tributary
	return { name = name, purpose = "Why." }
end

local function has(list: { string }, needle: string): boolean
	for _, line in list do
		if string.find(line, needle, 1, true) then
			return true
		end
	end
	return false
end

-- an item document; `extra` is more frontmatter lines
local function doc(id: string, extra: string): string
	return `---\nid: {id}\nslug: s\ntype: chore\n{extra}\n---\n\n# {id}\n`
end

return t.spec("tributaries", function(it)
	it("parse reads the ordered definitions with a name and a purpose", function()
		local list = parsed(
			'[[tributary]]\nname = "worker"\npurpose = "Carries work."\n\n[[tributary]]\nname = "lessons"\npurpose = "Learns."\n'
		)
		t.expect(#list).toBe(2)
		t.expect(list[1]).toEqual({ name = "worker", purpose = "Carries work." })
		t.expect(list[2].name).toBe("lessons")
		t.expect(parsed("")).toEqual({})
	end)

	it("parse names an invalid file, an unknown key, a units key and a value of the wrong shape", function()
		local _, bad = tributaries.parse("[[tributary")
		t.expect(bad ~= nil and string.find(bad, "not valid TOML", 1, true) ~= nil).toBe(true)
		local _, top = tributaries.parse("stray = 1\n")
		t.expect(top ~= nil and string.find(top, "unknown key stray", 1, true) ~= nil).toBe(true)
		local _, key = tributaries.parse('[[tributary]]\nname = "a"\npurpose = "p"\ncolor = "red"\n')
		t.expect(key ~= nil and string.find(key, "unknown key color", 1, true) ~= nil).toBe(true)
		local _, units = tributaries.parse('[[tributary]]\nname = "a"\npurpose = "p"\nunits = ["c0010"]\n')
		t.expect(
			units ~= nil
				and string.find(units, "membership is the unit's own tributary: line", 1, true) ~= nil
		)
			.toBe(true)
		local _, noName = tributaries.parse('[[tributary]]\npurpose = "p"\n')
		t.expect(noName ~= nil and string.find(noName, "needs a name", 1, true) ~= nil).toBe(true)
		local _, shape = tributaries.parse('tributary = "a"\n')
		t.expect(shape ~= nil and string.find(shape, "list of [[tributary]]", 1, true) ~= nil).toBe(true)
	end)

	it(
		"check passes good definitions and names a duplicate, empty, bad and reserved name and a missing purpose",
		function()
			t.expect(tributaries.check({ tr("a"), tr("worker-two") })).toEqual({})
			local problems = tributaries.check({
				tr("a"),
				tr("a"),
				tr(""),
				tr("Bad Name"),
				{ name = "nope", purpose = "  " },
			})
			t.expect(has(problems, "tributary a is named twice")).toBe(true)
			t.expect(has(problems, "an empty name")).toBe(true)
			t.expect(has(problems, "tributary Bad Name: a name is lowercase words")).toBe(true)
			t.expect(has(problems, "tributary nope has no purpose")).toBe(true)
			t.expect(#problems).toBe(4)
			for _, word in
				{ "backlog", "active", "done", "closed", "retired", "unsorted", "earlier-work", "all" }
			do
				t.expect(has(tributaries.check({ tr(word) }), "uses a reserved word")).toBe(true)
			end
		end
	)

	it("a unit's tributary is its own line, else unsorted when open and earlier-work when done", function()
		t.expect(tributaries.nameOf("worker", false)).toBe("worker")
		t.expect(tributaries.nameOf("worker", true)).toBe("worker") -- a done unit with a line stays
		t.expect(tributaries.nameOf(nil, false)).toBe("unsorted")
		t.expect(tributaries.nameOf("", false)).toBe("unsorted")
		t.expect(tributaries.nameOf(nil, true)).toBe("earlier-work")
		t.expect(tributaries.checkUnit({ tr("a") }, "c0010", nil)).toBe(nil)
		t.expect(tributaries.checkUnit({ tr("a") }, "c0010", "a")).toBe(nil)
		local msg = tributaries.checkUnit({ tr("a") }, "c0010", "b")
		t.expect(
			msg ~= nil
				and string.find(
						msg,
						"c0010 has tributary: b, which tributaries.toml does not define",
						1,
						true
					)
					~= nil
		).toBe(true)
	end)

	it(
		"counts sorts units into done, in flight, waiting and not started, in file order, then the implicit ones",
		function()
			local rows = tributaries.counts({ tr("b"), tr("a") }, {
				{ tributary = "b", phase = "done" },
				{ tributary = "b", phase = "flight" },
				{ tributary = "a", phase = "waiting" },
				{ tributary = "a", phase = "open" },
				{ tributary = "unsorted", phase = "open" },
				{ tributary = "earlier-work", phase = "done" },
				{ tributary = "gone", phase = "open" }, -- named, but defined nowhere: counted as unsorted
			})
			t.expect(#rows).toBe(4)
			t.expect(rows[1]).toEqual({
				name = "b",
				purpose = "Why.",
				implicit = false,
				done = 1,
				inFlight = 1,
				waiting = 0,
				notStarted = 0,
			})
			t.expect(rows[2].waiting).toBe(1)
			t.expect(rows[2].notStarted).toBe(1)
			t.expect(rows[3].name).toBe("unsorted")
			t.expect(rows[3].implicit).toBe(true)
			t.expect(rows[3].notStarted).toBe(2)
			t.expect(rows[4].name).toBe("earlier-work")
			t.expect(rows[4].done).toBe(1)
			t.expect(#tributaries.counts({ tr("a") }, {})).toBe(1) -- no units: no implicit rows
		end
	)

	it(
		"audit.tributaries fails a bad tributary: value, a bad file and a bad definition, and skips what is no unit",
		function()
			local dir = ".cache/tributaries-audit"
			if fs.isDir(dir) then
				fs.removeDir(dir)
			end
			fs.writeDir(`{dir}/z-nile`)
			fs.writeFile(
				`{dir}/z-nile/projects.toml`,
				'[[project]]\nname = "demo"\nroot = "demo/.tracker"\n\n[[project]]\nname = "other"\nroot = "other/.tracker"\n'
			)
			local function item(project: string, path: string, id: string, front: string)
				fs.writeDir(`{dir}/{project}/.tracker/{path}`)
				fs.writeFile(`{dir}/{project}/.tracker/{path}/{id}.md`, doc(id, front))
			end
			fs.writeDir(`{dir}/demo/.tracker`)
			fs.writeFile(
				`{dir}/demo/.tracker/tributaries.toml`,
				'[[tributary]]\nname = "one"\npurpose = "P."\n'
			)
			item("demo", "rafts/R0010", "R0010", "tributary: one")
			item("demo", "issues/c0010", "c0010", "raft: R0010\ntributary: ignored-in-a-raft") -- a member's own line is ignored
			item("demo", "issues/c0020", "c0020", "") -- no line: unsorted, never an error
			item("demo", "issues/done/c0030", "c0030", "status: done") -- no line: earlier-work
			item("demo", "issues/c0040", "c0040", "status: closed-a-b-c\nwont_do: moot\ntributary: nope") -- closed: no unit
			item("demo", "rafts/retired/R0020", "R0020", "tributary: nope") -- retired: no unit
			item("other", "issues/c0050", "c0050", "raft: R0010\ntributary: nope") -- a member of a raft in another project
			local function problems(): { string }
				local out = {}
				for _, p in audit.tributaries(dir) do
					table.insert(out, audit.format(p))
				end
				return out
			end
			t.expect(problems()).toEqual({}) -- no file under `other` at all is fine
			item("demo", "issues/c0060", "c0060", "tributary: nope")
			local bad = problems()
			t.expect(#bad).toBe(1)
			t.expect(
				has(bad, "error tributaries demo/.tracker/issues/c0060/c0060.md: c0060 has tributary: nope")
			)
				.toBe(true)
			fs.writeFile(
				`{dir}/demo/.tracker/tributaries.toml`,
				'[[tributary]]\nname = "one"\npurpose = "P."\n\n[[tributary]]\nname = "one"\npurpose = ""\n'
			)
			local defs = problems()
			t.expect(has(defs, "demo/.tracker/tributaries.toml: tributary one is named twice")).toBe(true)
			t.expect(has(defs, "tributary one has no purpose")).toBe(true)
			fs.writeFile(`{dir}/demo/.tracker/tributaries.toml`, "[[tributary")
			local broken = problems()
			t.expect(#broken).toBe(1) -- the file is named once, not once per unit
			t.expect(has(broken, "demo/.tracker/tributaries.toml: tributaries.toml is not valid TOML"))
				.toBe(true)
			fs.writeFile(
				`{dir}/demo/.tracker/tributaries.toml`,
				'[[tributary]]\nname = "one"\npurpose = "P."\nunits = ["c0020"]\n'
			)
			t.expect(has(problems(), "membership is the unit's own tributary: line")).toBe(true)
			fs.removeDir(dir)
		end
	)

	it(
		"the real tracker names only defined tributaries and defines them well, so a bad line fails the gate",
		function()
			local found = {}
			for _, p in audit.tributaries(TOP) do
				table.insert(found, audit.format(p))
			end
			t.expect(found).toEqual({})
			t.expect(fs.isFile(`{TOP}/z-nile/.tracker/tributaries.toml`)).toBe(true)
		end
	)

	it("list takes a tributary and a state in either order, and refuses a word that is neither", function()
		local seedDoc = function(id: string, extra: string): string
			return `---\nid: {id}\ntype: chore\ntitle: {id} title\nslug: slug-{id}\nraft: \ndepends_on: []\nemergent: false\ndesign: draft\ncreated: 2026-11-15\n{extra}\n---\n\n# {id}\n`
		end
		local issues = "pickman/.tracker/issues"
		local seed: { [string]: string } = {
			["pickman/.tracker/tributaries.toml"] = '[[tributary]]\nname = "alpha"\npurpose = "A."\n\n[[tributary]]\nname = "beta"\npurpose = "B."\n',
			[`{issues}/c0510/c0510.md`] = seedDoc("c0510", "status: new-a-b-c\ntributary: alpha"),
			[`{issues}/c0520/c0520.md`] = seedDoc("c0520", "status: new-a-b-c\ntributary: beta"),
			[`{issues}/c0530/c0530.md`] = seedDoc("c0530", "status: new-a-b-c"),
			[`{issues}/done/c0540/c0540.md`] = seedDoc("c0540", "status: done\ntributary: alpha"),
			[`{issues}/done/c0550/c0550.md`] = seedDoc("c0550", "status: done"),
			[`{issues}/c0560/c0560.md`] = seedDoc(
				"c0560",
				"status: new-a-b-c\ntributary: alpha\nraft: R0510"
			),
			["pickman/.tracker/rafts/R0510/R0510.md"] = `---\nid: R0510\ntype: chore\ntitle: Raft\nslug: raft-r\nsingle: false\nissues: [c0560]\ntributary: beta\ndesign: draft\ncreated: 2026-11-15\nstatus: new-a-b-c\n---\n\n# R0510\n`,
		}
		local f = trackerfix.new("f0422-list", seed)
		local function ids(args: { string }): string
			local out = {}
			for line in string.gmatch(trackerfix.trOk(f, f.main, args), "[^\n]+") do
				table.insert(out, (string.match(line, "^(%S+)")))
			end
			return table.concat(out, " ")
		end
		-- f0437 override: was "c0510 c0540". The raft R0510 (beta) counts in alpha too, through its member c0560 (tributaries.themesOf, G24)
		t.expect(ids({ "list", "alpha", "--project", "pickman" })).toBe("R0510 c0510 c0540")
		t.expect(ids({ "list", "beta", "--project", "pickman" })).toBe("R0510 c0520") -- a raft's member is not listed itself
		t.expect(ids({ "list", "alpha", "done", "--project", "pickman" })).toBe("c0540")
		t.expect(ids({ "list", "done", "alpha", "--project", "pickman" })).toBe("c0540")
		t.expect(ids({ "list", "unsorted", "--project", "pickman" })).toBe("c0530")
		t.expect(ids({ "list", "earlier-work", "--project", "pickman" })).toBe("c0550")
		t.expect(ids({ "list", "done", "--project", "pickman" })).toBe("c0540 c0550")
		local refused = trackerfix.tr(f, f.main, { "list", "nonesuch", "--project", "pickman" })
		t.expect(refused.ok).toBe(false)
		t.expect(has({ refused.stderr }, "states: backlog, active, done, closed, retired")).toBe(true)
		t.expect(has({ refused.stderr }, "tributaries: alpha, beta, unsorted, earlier-work")).toBe(true)
		local twice = trackerfix.tr(f, f.main, { "list", "alpha", "beta", "--project", "pickman" })
		t.expect(twice.ok).toBe(false)
		fs.writeFile(`{f.main}/pickman/.tracker/tributaries.toml`, "[[tributary")
		local broken = trackerfix.tr(f, f.main, { "list", "alpha", "--project", "pickman" })
		t.expect(broken.ok).toBe(false)
		t.expect(has({ broken.stderr }, "pickman/.tracker/tributaries.toml")).toBe(true)
		fixture.git(f.main, { "status", "--short" })
		fs.removeDir(f.base)
	end)

	it(
		"f0437 G24: list, the board, the themes facts and work.inTributary name the same units for a theme",
		function()
			local issues = "pickman/.tracker/issues"
			local function seedDoc(id: string, extra: string): string
				return `---\nid: {id}\ntype: chore\ntitle: {id} title\nslug: slug-{id}\nraft: \ndepends_on: []\nemergent: false\ndesign: draft\ncreated: 2026-11-15\n{extra}\n---\n\n# {id}\n`
			end
			local seed: { [string]: string } = {
				["pickman/.tracker/tributaries.toml"] = '[[tributary]]\nname = "alpha"\npurpose = "A."\n\n[[tributary]]\nname = "beta"\npurpose = "B."\n',
				[`{issues}/c0510/c0510.md`] = seedDoc("c0510", "status: new-a-b-c\ntributary: alpha"),
				[`{issues}/c0520/c0520.md`] = seedDoc("c0520", "status: new-a-b-c\ntributary: beta"),
				[`{issues}/c0560/c0560.md`] = seedDoc(
					"c0560",
					"status: new-a-b-c\ntributary: alpha\nraft: R0510"
				),
				["pickman/.tracker/rafts/R0510/R0510.md"] = `---\nid: R0510\ntype: chore\ntitle: Raft\nslug: raft-r\nsingle: false\nissues: [c0560]\ntributary: beta\ndesign: draft\ncreated: 2026-11-15\nstatus: new-a-b-c\n---\n\n# R0510\n`,
			}
			local f = trackerfix.new("f0437-four-views", seed)
			local function sorted(list: { string }): string
				table.sort(list)
				return table.concat(list, " ")
			end
			-- ./zn list alpha
			local listed: { string } = {}
			for line in
				string.gmatch(
					trackerfix.trOk(f, f.main, { "list", "alpha", "--project", "pickman" }),
					"[^\n]+"
				)
			do
				table.insert(listed, (string.match(line, "^(%S+)") or ""))
			end
			-- the board: its chip's count, and the model's units that name alpha
			local NO_FACTS: any = { asOf = nil, refs = {}, worktrees = {}, dispatch = {} }
			local model = board.collect(`{f.main}/pickman/.tracker`, nil, NO_FACTS)
			local chip = 0
			for _, row in model.tributaries[model.projects[1].name] do
				if row.name == "alpha" then
					chip = row.done + row.inFlight + row.waiting + row.notStarted
				end
			end
			-- the themes facts
			local named: { string } = {}
			for _, u in themefacts.units(model, {}) do
				if table.find(u.themes, "alpha") then
					table.insert(named, u.id)
				end
			end
			-- ./zn work alpha: the units the worker's scope reaches
			local function inTr(id: string, line: string, extra: { [string]: any }?): any
				local x: any = {
					id = id,
					tributary = line,
					root = "pickman/.tracker",
					status = "new",
					raft = "",
					deps = {},
					issues = {},
				}
				local given: { [string]: any } = extra or {}
				for k, v in given do
					x[k] = v
				end
				return x
			end
			local reached = (work :: any).inTributary({
				tributary = "alpha",
				rafts = { inTr("R0510", "beta", { issues = { "c0560" }, outside = {} }) },
				issues = {
					inTr("c0510", "alpha"),
					inTr("c0520", "beta"),
					inTr("c0560", "alpha", { raft = "R0510" }),
				},
			}, "alpha")
			t.expect(sorted(listed)).toBe("R0510 c0510")
			t.expect(chip).toBe(2)
			t.expect(sorted(named)).toBe("R0510 c0510")
			t.expect(sorted(reached)).toBe("R0510 c0510")
		end
	)
end)
