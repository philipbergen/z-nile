--!strict
-- f0437 step 6, slice 2: the units index (units.json) the app's id links and detail view read. Pure: the board's model in (plus
-- the git log of deleted documents as text), one list of units out. Every document is a unit: open, done, closed (a ticket that
-- stays in a backlog folder with a closed status), retired (a raft folded into another) and withdrawn (an id git remembers,
-- whose document is gone). Closed, retired, withdrawn and done units carry no text. A fixture tracker under this home's .cache.
local approvalfacts = require("@znile/engine/approvalfacts")
local board = require("@znile/engine/board")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")
local tributaries = require("@znile/engine/tributaries")
local unitsfacts = require("@znile/engine/unitsfacts")

local DIR = ".cache/units-facts"
local FENCE = string.rep(string.char(96), 3)
local NO_FACTS: any = { asOf = nil, refs = {}, worktrees = {}, dispatch = {} }

local function doc(path: string, id: string, front: string, body: string?)
	fs.writeDir(path)
	fs.writeFile(`{path}/{id}.md`, `---\nid: {id}\n{front}\n---\n\n# {id}\n{body or ""}`)
end

local SECTIONS =
	"\n## Problem\nThe problem of it.\n\n## Solution\nThe solution of it.\n\n## Design\n### First part\nDesign text.\n\n### Second part\nMore.\n\n## Acceptance criteria\n- AC1\n"

-- c0001 open (backlog) with a status stamp; c0002 active member of R0010; c0003 done; c0004 closed in a backlog folder;
-- R0010 open raft (members c0002 and c0005; c0005 names theme beta); R0011 done; R0012 retired into R0010.
local function fixture(): string
	if fs.isDir(DIR) then
		fs.removeDir(DIR)
	end
	local base = `{DIR}/tracker`
	doc(
		`{base}/issues/c0001`,
		"c0001",
		"type: feature\ntitle: Open one\nstatus: preparing-aa-bb-cc\ntributary: alpha\ndepends_on: [c0003]",
		SECTIONS
	)
	doc(
		`{base}/issues/active/c0002`,
		"c0002",
		"type: chore\ntitle: Active member\nraft: R0010\nstatus: active-d-e-f",
		SECTIONS
	)
	doc(`{base}/issues/done/c0003`, "c0003", "type: chore\ntitle: Done one\nstatus: done", SECTIONS)
	doc(
		`{base}/issues/c0004`,
		"c0004",
		"type: chore\ntitle: Closed one\nstatus: closed-aa-bb-cc\nwont_do: no longer wanted",
		SECTIONS
	)
	doc(
		`{base}/issues/c0005`,
		"c0005",
		"type: chore\ntitle: Names beta\nraft: R0010\ntributary: beta",
		SECTIONS
	)
	doc(`{base}/rafts/R0010`, "R0010", "type: chore\ntitle: The open raft\ntributary: alpha", SECTIONS)
	doc(`{base}/rafts/done/R0011`, "R0011", "type: chore\ntitle: The done raft\nstatus: done", SECTIONS)
	doc(
		`{base}/rafts/retired/R0012`,
		"R0012",
		"type: chore\ntitle: The retired raft\nretired: R0010",
		SECTIONS
	)
	fs.writeFile(
		`{base}/tributaries.toml`,
		'[[tributary]]\nname = "alpha"\npurpose = "First."\n\n[[tributary]]\nname = "beta"\npurpose = "Second."\n'
	)
	return base
end

local function unitsOf(
	model: board.Model,
	withdrawn: { unitsfacts.Withdrawn }?
): { [string]: unitsfacts.Unit }
	local list = unitsfacts.units(model, approvalfacts.templateComments({}), withdrawn or {})
	local by: { [string]: unitsfacts.Unit } = {}
	for _, u in list do
		by[u.id] = u
	end
	return by
end

local function keys(v: any): string
	local out: { string } = {}
	for k in v do
		table.insert(out, k)
	end
	table.sort(out)
	return table.concat(out, ",")
end

return t.spec("f0437 slice 2: the units index from the board's model", function(it)
	it("lists every document: open, done, closed, retired and withdrawn, each with its state", function()
		local base = fixture()
		local model = board.collect(base, nil, NO_FACTS)
		local by = unitsOf(model, {
			{
				id = "c0261",
				when = "2026-11-02",
				subject = "tracker: withdraw c0261 (met by #299)",
				fate = "withdrawn",
			},
		})
		t.expect(by.c0001.state).toBe("backlog")
		t.expect(by.c0002.state).toBe("active")
		t.expect(by.c0003.state).toBe("done")
		t.expect(by.c0004.state).toBe("closed") -- sits in a backlog folder: the board's model drops it, the index does not
		t.expect(by.R0010.state).toBe("backlog")
		t.expect(by.R0011.state).toBe("done")
		t.expect(by.R0012.state).toBe("retired") -- rafts/retired/: store.all misses it
		t.expect(by.c0261.state).toBe("withdrawn")
		t.expect(by.c0001.kind).toBe("ticket")
		t.expect(by.R0010.kind).toBe("raft")
		t.expect(by.c0261.kind).toBe("ticket")
		local n = 0
		for _ in by do
			n += 1
		end
		t.expect(n).toBe(9) -- 5 tickets + 3 rafts + 1 withdrawn: one unit per document on disk, plus the stub
		fs.removeDir(DIR)
	end)

	it("a unit has exactly the reviewed key set, a stub too, and an empty list is a list", function()
		local base = fixture()
		local by = unitsOf(
			board.collect(base, nil, NO_FACTS),
			{ { id = "c0261", when = "2026-11-02", subject = "withdraw", fate = "withdrawn" } }
		)
		local want =
			"clipped,depends_on,design,id,kind,members,problem,problem_size,project,raft,solution,solution_size,state,themes,title,tributary"
		t.expect(keys(by.c0001)).toBe(want)
		t.expect(keys(by.R0010)).toBe(want)
		t.expect(keys(by.c0003)).toBe("depends_on,id,kind,members,project,raft,state,themes,title,tributary") -- no text
		t.expect(keys(by.c0004)).toBe("depends_on,id,kind,members,project,raft,state,themes,title,tributary")
		t.expect(keys(by.R0012)).toBe("depends_on,id,kind,members,project,raft,state,themes,title,tributary")
		t.expect(keys(by.c0261))
			.toBe("depends_on,fate,id,kind,members,project,raft,state,subject,themes,title,tributary,when")
		-- the facts file: lists are written the way the Go reader takes (an empty one as {} from Lune's encoder)
		local text =
			unitsfacts.encode(unitsfacts.build({ at = 5, commit = "abc1234", units = { by.c0003 }, cut = 0 }))
		local got = serde.decode("json" :: "json", text)
		t.expect(got.version).toBe(1)
		t.expect(got.commit).toBe("abc1234")
		t.expect(keys(got)).toBe("at,commit,pre,sig,units,version,withdrawn_cut")
		t.expect(#got.units).toBe(1)
		fs.removeDir(DIR)
	end)

	it("only open units carry text; a done, closed, retired or withdrawn one carries none", function()
		local base = fixture()
		local by = unitsOf(
			board.collect(base, nil, NO_FACTS),
			{ { id = "c0261", when = "d", subject = "s", fate = "withdrawn" } }
		)
		t.expect(by.c0001.problem).toBe("The problem of it.")
		t.expect(by.c0001.solution).toBe("The solution of it.")
		t.expect(#(by.c0001.design :: any)).toBe(2)
		t.expect((by.c0001.design :: any)[1].heading).toBe("First part")
		for _, id in { "c0003", "c0004", "R0011", "R0012", "c0261" } do
			t.expect(by[id].problem).toBe(nil)
			t.expect(by[id].solution).toBe(nil)
			t.expect(by[id].design).toBe(nil)
		end
		fs.removeDir(DIR)
	end)

	it(
		"the preview is the approval facts' section clipped: 500 and 500 and 1,500 in all, on a character boundary",
		function()
			local base = fixture()
			local long = string.rep("é", 400) -- 800 bytes: a byte cut at an odd place would split a character
			doc(
				`{base}/issues/c0006`,
				"c0006",
				"type: chore\ntitle: Long",
				`\n## Problem\n{long}\n\n## Solution\n{string.rep("x", 900)}\n\n## Design\n### A\n{string.rep(
					"ü",
					600
				)}\n\n### B\n{string.rep("y", 600)}\n`
			)
			local model = board.collect(base, nil, NO_FACTS)
			local by = unitsOf(model)
			local u = by.c0006
			t.expect(u.clipped).toBe(true)
			t.expect(utf8.len(u.problem :: string) ~= nil).toBe(true) -- valid UTF-8: the JSON encoder takes it
			t.expect(#(u.problem :: string) <= 503).toBe(true)
			t.expect(#(u.solution :: string) <= 503).toBe(true)
			local total = 0
			for _, p in u.design :: any do
				total += #p.text
				t.expect(utf8.len(p.text) ~= nil).toBe(true)
			end
			t.expect(total <= 1500 + 6).toBe(true)
			t.expect(#(u.design :: any) >= 1).toBe(true)
			-- an open unit under the clips says clipped = false
			t.expect(by.c0001.clipped).toBe(false)
			-- the sections are the approval facts' own, then clipped (one section rule)
			local whole = approvalfacts.sections(fs.readFile(`{base}/issues/c0001/c0001.md`), nil)
			t.expect(by.c0001.problem).toBe(whole.problem)
			t.expect(by.c0001.solution).toBe(whole.solution)
			t.expect((by.c0001.design :: any)[2].text).toBe(whole.design[2].text)
			fs.removeDir(DIR)
		end
	)

	it(
		"the preview drops the template's own comments and keeps every other one, as the approval facts do",
		function()
			local base = fixture()
			doc(
				`{base}/issues/c0007`,
				"c0007",
				"type: chore\ntitle: Comments",
				"\n## Problem\n<!-- the template says this -->\nReal problem.\n<!-- executor: also delete X -->\n\n## Solution\nS\n"
			)
			local templates = approvalfacts.templateComments({ "x\n<!-- the template says this -->\ny" })
			local list = unitsfacts.units(board.collect(base, nil, NO_FACTS), templates, {})
			local u: unitsfacts.Unit? = nil
			for _, x in list do
				if x.id == "c0007" then
					u = x
				end
			end
			t.expect(u ~= nil).toBe(true)
			local problem = (u :: unitsfacts.Unit).problem :: string
			t.expect((string.find(problem, "the template says this", 1, true))).toBe(nil)
			t.expect(string.find(problem, "Real problem.", 1, true) ~= nil).toBe(true)
			t.expect(string.find(problem, "executor: also delete X", 1, true) ~= nil).toBe(true) -- any other comment stays, for the renderer to show
			fs.removeDir(DIR)
		end
	)

	it("never carries the status stamp, spend or a path, and a unit's themes are the one rule's", function()
		local base = fixture()
		local model = board.collect(base, nil, NO_FACTS)
		local by = unitsOf(model)
		local text = unitsfacts.encode(unitsfacts.build({
			at = 1,
			commit = "",
			units = unitsfacts.units(model, approvalfacts.templateComments({}), {}),
			cut = 0,
		}))
		t.expect((string.find(text, "preparing", 1, true))).toBe(nil) -- a worker's claim token
		t.expect((string.find(text, "active-d-e-f", 1, true))).toBe(nil)
		t.expect((string.find(text, ".tracker", 1, true))).toBe(nil)
		t.expect((string.find(text, DIR, 1, true))).toBe(nil)
		t.expect((string.find(text, '"spend"', 1, true))).toBe(nil)
		t.expect((string.find(text, '"status"', 1, true))).toBe(nil)
		-- R0010 is alpha's own and beta through its member c0005: tributaries.themesOf
		t.expect(by.R0010.themes).toEqual(tributaries.themesOf("alpha", { "", "beta" }))
		t.expect(by.R0010.themes).toEqual({ "alpha", "beta" })
		t.expect(by.c0001.themes).toEqual({ "alpha" })
		t.expect(by.c0004.themes).toEqual({ tributaries.UNSORTED }) -- a closed ticket with no line
		t.expect(by.R0012.themes).toEqual({ tributaries.UNSORTED })
		t.expect(by.R0010.members).toEqual({ "c0002", "c0005" })
		t.expect(by.c0002.raft).toBe("R0010")
		t.expect(by.c0001.depends_on).toEqual({ "c0003" })
		t.expect(by.c0001.project).toBe("tracker")
		fs.removeDir(DIR)
	end)

	it(
		"withdrawn ids come from the deletion log: the newest deletion, never an id that exists now",
		function()
			local log = table.concat({
				"@@\t2026-11-20\ttracker: withdraw c0261 (met by #299)",
				"z-nile/.tracker/issues/c0261/c0261.md",
				"z-nile/.tracker/issues/c0261/check.sh",
				"",
				"@@\t2026-11-10\tmove c0001 to active",
				"z-nile/.tracker/issues/c0001/c0001.md", -- exists now: left out
				"",
				"@@\t2026-11-05\tfinish c0123",
				"z-nile/.tracker/issues/done/c0123/c0123.md",
				"z-nile/.tracker/rafts/R0090/R0090.md",
				"z-nile/.tracker/issues/c0777/notes.md", -- not a document: the folder's other files are no unit
				"z-nile/.tracker/issues/c0778/c0888.md", -- a file named for another id is no document of this folder
				"",
				"@@\t2026-10-01\tearlier withdraw of c0261",
				"z-nile/.tracker/issues/c0261/c0261.md", -- the older deletion of the same id is not the one
				"",
			}, "\n")
			local got = unitsfacts.parseWithdrawn(log, { c0001 = true })
			local ids: { string } = {}
			for _, w in got do
				table.insert(ids, w.id)
			end
			t.expect(ids).toEqual({ "R0090", "c0123", "c0261" }) -- sorted by id
			local by: { [string]: unitsfacts.Withdrawn } = {}
			for _, w in got do
				by[w.id] = w
			end
			t.expect(by.c0261.when).toBe("2026-11-20")
			t.expect(by.c0261.subject).toBe("tracker: withdraw c0261 (met by #299)")
			t.expect(by.c0123.when).toBe("2026-11-05")
			t.expect(by.R0090.subject).toBe("finish c0123")
			t.expect(by.c0777).toBe(nil)
			t.expect(by.c0778).toBe(nil)
			t.expect(by.c0888).toBe(nil)
		end
	)

	it(
		"a long subject is cut on a character boundary and says so, and a hostile log is read in one pass",
		function()
			local log = `@@\t2026-11-20\t{string.rep("é", 400)}\nz-nile/.tracker/issues/c0261/c0261.md\n`
			local got = unitsfacts.parseWithdrawn(log, {})
			t.expect(#got).toBe(1)
			t.expect(utf8.len(got[1].subject) ~= nil).toBe(true)
			t.expect(#got[1].subject <= unitsfacts.SUBJECT_CAP + 3).toBe(true)
			t.expect(string.sub(got[1].subject, -3)).toBe("...")
			-- 20,000 deleted ids: the cap holds and the count of the rest is carried
			local lines: { string } = {}
			for i = 1, 20000 do
				table.insert(lines, `@@\t2026-11-20\ts{i}`)
				table.insert(
					lines,
					`z/.tracker/issues/c{string.format("%04d", i % 10000)}/c{string.format("%04d", i % 10000)}.md`
				)
			end
			local many = unitsfacts.parseWithdrawn(table.concat(lines, "\n"), {})
			t.expect(#many).toBe(10000) -- 10,000 distinct ids, the newest of each
			local capped, cut = unitsfacts.units(
				board.collect(fixture(), nil, NO_FACTS),
				approvalfacts.templateComments({}),
				many
			)
			t.expect(cut).toBe(10000 - unitsfacts.WITHDRAWN_MAX)
			local stubs = 0
			for _, u in capped do
				if u.state == "withdrawn" then
					stubs += 1
				end
			end
			t.expect(stubs).toBe(unitsfacts.WITHDRAWN_MAX)
			fs.removeDir(DIR)
		end
	)

	it("the signature ignores the time and the commit, and changes when anything shown changes", function()
		local base = fixture()
		local model = board.collect(base, nil, NO_FACTS)
		local list = unitsfacts.units(model, approvalfacts.templateComments({}), {})
		local a = unitsfacts.build({ at = 1, commit = "aaa", units = list, cut = 0 })
		local b = unitsfacts.build({ at = 999, commit = "bbb", units = list, cut = 0 })
		t.expect(a.sig).toBe(b.sig)
		t.expect(#a.sig).toBe(64)
		local changed = unitsfacts.units(
			model,
			approvalfacts.templateComments({}),
			{ { id = "c0261", when = "d", subject = "s", fate = "withdrawn" } }
		)
		t.expect(unitsfacts.build({ at = 1, commit = "", units = changed, cut = 0 }).sig == a.sig).toBe(false)
		local other = unitsfacts.units(model, approvalfacts.templateComments({}), {})
		for _, u in other do
			if u.id == "c0001" then
				u.title = "A different title"
			end
		end
		t.expect(unitsfacts.build({ at = 1, commit = "", units = other, cut = 0 }).sig == a.sig).toBe(false)
		local cutOne = unitsfacts.build({ at = 1, commit = "", units = list, cut = 1 })
		t.expect(cutOne.sig == a.sig).toBe(false)
		fs.removeDir(DIR)
	end)

	it("the facts of a tracker with no units are a valid, empty file", function()
		local text = unitsfacts.encode(unitsfacts.build({ at = 1, commit = "", units = {}, cut = 0 }))
		local got = serde.decode("json" :: "json", text)
		t.expect(got.version).toBe(1)
		t.expect((next(got.units))).toBe(nil)
	end)

	it(
		"withdrawn ids say what happened: withdrawn only when the subject says so, renumbered to the new id when the compaction map names it, else removed",
		function()
			local log = table.concat({
				"@@\t2026-11-20\ttracker: withdraw c0261 (met by #299)",
				"z-nile/.tracker/issues/c0261/c0261.md",
				"@@\t2026-10-05\ttracker: compact ids (#64)",
				"z-nile/.tracker/issues/c0090/c0090.md",
				"@@\t2026-09-01\tfold c0460 into c0010",
				"z-nile/.tracker/issues/c0460/c0460.md",
			}, "\n")
			local got = unitsfacts.parseWithdrawn(log, {}, { c0090 = "c0010" })
			local by: { [string]: unitsfacts.Withdrawn } = {}
			for _, w in got do
				by[w.id] = w
			end
			t.expect(by.c0261.fate).toBe("withdrawn")
			t.expect(by.c0090.fate).toBe("renumbered")
			t.expect(by.c0090.to).toBe("c0010")
			t.expect(by.c0460.fate).toBe("removed")
			t.expect(by.c0460.to).toBe(nil)
		end
	)

	it("a path outside a .tracker folder mints no stub", function()
		local log =
			"@@\t2026-11-20\tx\nz-nile/tests/fixtures/issues/c0777/c0777.md\nz-nile/.tracker/issues/c0778/c0778.md\ntracker/rafts/R0779/R0779.md\n"
		local got = unitsfacts.parseWithdrawn(log, {}, {})
		local ids: { string } = {}
		for _, w in got do
			table.insert(ids, w.id)
		end
		t.expect(ids).toEqual({ "R0779", "c0778" }) -- the old root and the tracker folders only
	end)

	it(
		"the preview says the full size of every part, closes a fence the clip cut open, and keeps every part",
		function()
			local base = fixture()
			doc(
				`{base}/issues/c0008`,
				"c0008",
				"type: chore\ntitle: Sizes",
				"\n## Problem\n"
					.. FENCE
					.. "\n"
					.. string.rep("x", 700)
					.. "\n"
					.. FENCE
					.. "\n\n## Solution\nShort.\n\n## Design\n### A\n"
					.. string.rep("a", 1500)
					.. "\n\n### B\n"
					.. string.rep("b", 300)
					.. "\n\n### C\nc\n"
			)
			local by = unitsOf(board.collect(base, nil, NO_FACTS))
			local u = by.c0008
			t.expect(u.problem_size).toBe(#FENCE + 1 + 700 + 1 + #FENCE)
			t.expect(u.solution_size).toBe(#"Short.")
			local parts = u.design :: any
			t.expect(#parts).toBe(3)
			t.expect(parts[1].size).toBe(1500)
			t.expect(parts[2].size).toBe(300)
			t.expect(parts[2].text).toBe("") -- past the budget: the heading and the size stay
			t.expect(parts[3].size).toBe(1)
			t.expect(parts[3].text).toBe("")
			-- the clipped problem was cut inside a fence: it is closed, and says the code goes on
			local problem = u.problem :: string
			local fences = 0
			for _ in string.gmatch(problem, FENCE) do
				fences += 1
			end
			t.expect(fences % 2).toBe(0)
			t.expect(string.find(problem, "the code continues in the ticket file", 1, true) ~= nil).toBe(true)
			fs.removeDir(DIR)
		end
	)

	it("the signature is of the encoded content, so the version is in it", function()
		local list =
			unitsfacts.units(board.collect(fixture(), nil, NO_FACTS), approvalfacts.templateComments({}), {})
		local a = unitsfacts.build({ at = 1, commit = "", units = list, cut = 0 }).sig
		local was = unitsfacts.VERSION
		unitsfacts.VERSION = was + 1
		local b = unitsfacts.build({ at = 1, commit = "", units = list, cut = 0 }).sig
		unitsfacts.VERSION = was
		t.expect(a == b).toBe(false)
		fs.removeDir(DIR)
	end)

	it("a model board.collect did not make is refused, not read as a model with nothing dropped", function()
		local model = board.collect(fixture(), nil, NO_FACTS)
		t.expect(#board.droppedOf(model) > 0).toBe(true)
		local copy: any = table.clone(model)
		t.expect((pcall(board.droppedOf, copy))).toBe(false)
		fs.removeDir(DIR)
	end)
end)
