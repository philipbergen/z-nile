--!strict
-- f0420 step 2 (AC12, AC13, AC19's first clause): `work.graph`'s lines, the board's order against the walk's, the
-- Stops message, and the commands that print them. The first cases are pure; the last run `./zn` on a small fixture.
local board = require("@scripts/tracker/board")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")
local work = require("@znile/engine/work")
local workgraph = require("@znile/engine/workgraph")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function has(text: string?, needle: string): boolean
	return string.find(text or "", needle, 1, true) ~= nil
end

local function raft(id: string, over: { [string]: any }?): work.RaftFact
	local r: work.RaftFact = {
		id = id,
		title = id,
		where = "backlog",
		status = "prepared",
		designReady = true,
		depsMet = true,
		questions = false,
		issues = {},
		layers = {},
		holder = "",
		since = "",
		stacked = false,
		codeReview = "none",
		finalReview = "none",
		trace = false,
		traceOk = false,
		root = "z-nile/.tracker",
	}
	for k, v in (over or {}) :: { [string]: any } do
		(r :: any)[k] = v
	end
	return r
end

local function issue(id: string, over: { [string]: any }?): work.IssueFact
	local i: work.IssueFact = {
		id = id,
		root = "z-nile/.tracker",
		status = "prepared",
		raft = "",
		designReady = true,
		sized = true,
		deps = {},
		draftBlock = "",
	}
	for k, v in (over or {}) :: { [string]: any } do
		(i :: any)[k] = v
	end
	return i
end

local function layer(position: number, id: string, finished: boolean, onlyStart: boolean): work.LayerFact
	return {
		position = position,
		issue = id,
		name = `R0091/{position}/{id}`,
		commits = if onlyStart then 1 else 3,
		onlyStart = onlyStart,
		finished = finished,
	}
end

-- The Design's example: R0099 waits on R0091 (being built, held by a worker), R0093 (built, owes an approval; it is built
-- on R0091) and R0095 (which waits on the unwritten design c0410).
local function example(): work.Input
	local r91 = raft("R0091", {
		where = "active",
		status = "active",
		issues = { "c0387", "f0388" },
		layers = { layer(1, "c0387", true, false), layer(2, "f0388", false, true) },
		level = "normal",
	})
	local r93 = raft("R0093", {
		where = "active",
		status = "active",
		issues = { "f0377" },
		outside = { "c0387" },
		layers = { layer(1, "f0377", true, false) },
		stacked = true,
		codeReview = "resolved",
		finalReview = "approved",
		trace = true,
		traceOk = true,
		lands = true,
		unapproved = { "f0377 (no approval)" },
	})
	local r95 = raft("R0095", { issues = { "c0095" }, outside = { "c0410" }, depsMet = false })
	local r99 = raft("R0099", {
		issues = { "c0099" },
		outside = { "f0388", "f0377", "c0095" },
		depsMet = false,
	})
	return {
		asked = "R0099",
		rafts = { r99, r95, r93, r91 },
		issues = {
			issue("c0387", { raft = "R0091", status = "active" }),
			issue("f0388", { raft = "R0091", status = "active" }),
			issue("f0377", { raft = "R0093", status = "active", deps = { "c0387" } }),
			issue("c0095", { raft = "R0095", deps = { "c0410" } }),
			issue("c0099", { raft = "R0099", deps = { "f0388", "f0377", "c0095" } }),
			issue("c0410", { status = "new", designReady = false, sized = false, level = "easy" }),
		},
		claims = { R0091 = "grok-8812@mbp" },
	}
end

local EXAMPLE = table.concat({
	"R0099 needs 5 units; 2 can be worked now",
	"band 0  R0091  implement     code/normal          held by grok-8812@mbp  layer 2 f0388",
	"band 0  c0410  draft         design/easy          unblocks 2",
	"band 1  R0093  owed          ./zn approve f0377   unblocks 1",
	"band 1  R0095  waits on c0410",
	"band 2  R0099  waits on R0091, R0093, R0095",
	"now: c0410 (claude, grok, kimi can)",
	"owed:",
	"./zn approve f0377 # in R0093 (no approval); ./zn guesses R0093 lists what to review",
}, "\n")

local function sayOf(r: fixture.Result): string
	return (string.gsub(r.stderr .. r.stdout, "\r", ""))
end

local ROOT = "pickman/.tracker"
local PREPARED = "prepared-quiet-copper-falcon"
local NEW = "new-amber-otter-marble"

local function item(id: string, rid: string, deps: string, status: string, design: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id} title\nslug: {id}\nraft: {rid}\ndepends_on: [{deps}]\nemergent: false\ndesign: {design}\ncreated: 2026-11-16\nstatus: {status}\n---\n\n# {id}\n\n## Problem\nx\n`
end

local function raftDoc(id: string, member: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id} raft\nslug: {id}\nsingle: false\nissues: [{member}]\ndesign: ready\ncreated: 2026-11-16\nstatus: {PREPARED}\n---\n\n# {id}\n\n## Order & dependencies\n{member}\n`
end

local f: trackerfix.Fixture = nil :: any

local function setup()
	if f then
		return
	end
	f = trackerfix.new("f0420-walk-graph", {
		[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
		[`{ROOT}/architecture.md`] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
		[`{ROOT}/rafts/R0100/R0100.md`] = raftDoc("R0100", "c0101"),
		[`{ROOT}/issues/c0101/c0101.md`] = item("c0101", "R0100", "c0090", PREPARED, "ready"),
		[`{ROOT}/issues/c0090/c0090.md`] = item("c0090", "", "", NEW, "draft"),
		[`{ROOT}/rafts/R0110/R0110.md`] = raftDoc("R0110", "c0111"),
		[`{ROOT}/rafts/R0110/questions.md`] = "## Q1\nWhich one?\n",
		[`{ROOT}/issues/c0111/c0111.md`] = item("c0111", "R0110", "", PREPARED, "ready"),
	})
end

local function zn(args: { string }): string
	local argv = {}
	for _, a in args do
		table.insert(argv, a)
	end
	return sayOf(trackerfix.tr(f, f.main, argv))
end

return t.spec("f0420: the graph and the stop", function(it)
	it("AC12: the graph prints the Design's lines for its fixture", function()
		local input = example()
		t.expect(workgraph.of(input, "R0099", { "claude", "grok", "kimi" })).toBe(EXAMPLE)
		-- nothing held and no CLI named: the unit is free, and any CLI is taken to do it
		input.claims = nil
		local free = workgraph.of(input, "R0099")
		t.expect(has(free, "band 0  R0091  implement     code/normal          unblocks 2")).toBe(true)
		t.expect(has(free, "now: R0091, c0410 (any CLI can)")).toBe(true)
	end)

	it("AC12: a landed raft and an unknown one have no graph", function()
		local input = example()
		t.expect(workgraph.of(input, "R0777")).toBe("R0777 is not in the tracker")
		input.rafts[1].where = "done"
		t.expect(has(workgraph.of(input, "R0099"), "has landed")).toBe(true)
	end)

	it("AC13: the board's Flow order and the walk's order of the same units are equal", function()
		local dir = ".cache/work-graph-board"
		if fs.isDir(dir) then
			fs.removeDir(dir)
		end
		local function doc(path: string, id: string, front: string)
			fs.writeDir(path)
			fs.writeFile(`{path}/{id}.md`, `---\nid: {id}\n{front}\n---\n\n# {id}\n`)
		end
		local base = `{dir}/tracker`
		doc(`{base}/rafts/R0010`, "R0010", "type: chore\ntitle: First")
		doc(`{base}/issues/c0010`, "c0010", "type: chore\ntitle: First\nraft: R0010")
		doc(`{base}/rafts/R0011`, "R0011", "type: feature\ntitle: Second")
		doc(`{base}/issues/c0011`, "c0011", "type: feature\ntitle: Second\nraft: R0011\ndepends_on: [c0010]")
		doc(`{base}/rafts/R0012`, "R0012", "type: feature\ntitle: Third")
		doc(
			`{base}/issues/c0012`,
			"c0012",
			"type: feature\ntitle: Third\nraft: R0012\ndepends_on: [c0011, c0020, c0021]"
		)
		doc(`{base}/issues/c0020`, "c0020", "type: defect\ntitle: Loose")
		doc(`{base}/issues/c0021`, "c0021", "type: defect\ntitle: Loose too")
		-- c0022 is outside R0012's closure and waits on c0021: over the whole graph c0021 unblocks 2, c0020 only 1
		doc(`{base}/issues/c0022`, "c0022", "type: chore\ntitle: Outside\ndepends_on: [c0021]")
		local m = board.collect(base)
		fs.removeDir(dir)
		-- the board's order of the closure of R0012
		local closure = { R0010 = true, R0011 = true, R0012 = true, c0020 = true, c0021 = true }
		local flowOrder: { string } = {}
		for _, band in m.flow.bands do
			for _, id in band.ids do
				if closure[id] then
					table.insert(flowOrder, id)
				end
			end
		end
		local input: work.Input = {
			asked = "R0012",
			rafts = {
				raft("R0010", { issues = { "c0010" } }),
				raft("R0011", { issues = { "c0011" }, outside = { "c0010" }, depsMet = false }),
				raft(
					"R0012",
					{ issues = { "c0012" }, outside = { "c0011", "c0020", "c0021" }, depsMet = false }
				),
			},
			issues = {
				issue("c0010", { raft = "R0010" }),
				issue("c0011", { raft = "R0011", deps = { "c0010" } }),
				issue("c0012", { raft = "R0012", deps = { "c0011", "c0020", "c0021" } }),
				issue("c0020"),
				issue("c0021"),
				issue("c0022", { deps = { "c0021" } }),
			},
		}
		local walk = work.walk(input, "R0012")
		-- the graph lists band by band, each band most-unblocking first: the same sequence as the board's
		local lines = string.split(workgraph.render(input, walk), "\n")
		local graphOrder: { string } = {}
		for _, line in lines do
			local id = string.match(line, "^band %d+  (%S+)")
			if id then
				table.insert(graphOrder, id)
			end
		end
		t.expect(graphOrder).toEqual(flowOrder)
		-- band 0 is not in id order (c0021 holds up more than c0020 over the whole graph), and not by the closure's count
		t.expect(graphOrder).toEqual({ "R0010", "c0021", "c0020", "R0011", "R0012" })
		t.expect(walk.workable[1]).toBe("R0010")
		t.expect(#flowOrder).toBe(5)
	end)

	it("the Stops message: where it stopped, what each is owed, how to resume", function()
		local input = example()
		input.claims = nil
		local issues = input.issues :: { work.IssueFact }
		input.rafts[4].where = "done" -- R0091 landed: R0093 and R0099 are what is left
		table.remove(input.rafts, 4)
		table.remove(issues, 1)
		table.remove(issues, 1)
		issues[1].deps = {}
		issues[3].deps = { "f0377", "c0095" }
		input.rafts[1].outside = { "f0377", "c0095" }
		-- c0410 still has to be designed: that is workable, so there is no stop yet
		local d = work.decide(input)
		t.expect(d.action).toBe("draft")
		t.expect(d.owed).toBe(nil)
		-- with the design and R0095 out of the way, only the approval is left
		local top = raft("R0099", { issues = { "c0099" }, outside = { "f0377" }, depsMet = false })
		local owing: work.Input = {
			asked = "R0099",
			rafts = { top, input.rafts[3] },
			issues = {
				issue("f0377", { raft = "R0093", status = "active" }),
				issue("c0099", { raft = "R0099", deps = { "f0377" } }),
			},
		}
		local stop = work.decide(owing)
		-- R0099 can be readied on R0093 (its layers are finished): that is workable, the approval is not in its way
		t.expect(stop.action).toBe("ready")
		t.expect(has(stop.why, "./zn ready R0099 --on R0093")).toBe(true)
		-- R0099 itself built on it and waiting: only the person can move it
		local built = raft("R0099", {
			where = "active",
			status = "active",
			issues = { "c0099" },
			outside = { "f0377" },
			layers = { layer(1, "c0099", true, false) },
			stacked = true,
			codeReview = "resolved",
			finalReview = "approved",
			trace = true,
			traceOk = true,
			lands = true,
			unapproved = { "c0099 (no approval)" },
			on = "R0093",
			onLanded = false,
		})
		owing.rafts = { built, input.rafts[3] }
		local d2 = work.decide(owing)
		t.expect(d2.action).toBe("wait")
		t.expect(work.report(owing, d2)).toBe(table.concat({
			"R0099: wait - R0099 is not landed yet: 2 units needed, 0 can be worked now, 2 wait for you",
			"./zn approve f0377 # in R0093 (no approval); ./zn guesses R0093 lists what to review",
			"./zn approve c0099 # in R0099 (no approval); ./zn guesses R0099 lists what to review",
			"Then run ./zn work R0099 again.",
		}, "\n"))
		-- --one is not walked and prints no stop
		owing.one = true
		t.expect(has(work.report(owing, work.decide(owing)), "is not landed yet")).toBe(false)
	end)

	it("a landed raft is not a stop, and a raft with questions.md ends with the file to answer", function()
		local landed: work.Input =
			{ asked = "R0100", rafts = { raft("R0100", { where = "done" }) }, issues = {} }
		local d = work.decide(landed)
		t.expect(d.action).toBe("end")
		t.expect(work.report(landed, d)).toBe(work.say(d))
		local asking: work.Input = {
			asked = "R0100",
			rafts = { raft("R0100", { questions = true, issues = { "c0100" } }) },
			issues = { issue("c0100", { raft = "R0100" }) },
		}
		local out = work.report(asking, work.decide(asking))
		t.expect(
			has(
				out,
				"R0100 is not landed yet: 1 unit needed, 0 can be worked now, 1 wait for you\nz-nile/.tracker/rafts/R0100/questions.md # answer each question in it\nThen run ./zn work R0100 again."
			)
		).toBe(true)
	end)

	it("./zn work graph R prints the graph, and ./zn work R prints it after the skill", function()
		setup()
		local graph = zn({ "work", "graph", "R0100" })
		t.expect(graph).toBe(table.concat({
			"R0100 needs 2 units; 1 can be worked now",
			"band 0  c0090  draft         design/normal        unblocks 1",
			"band 1  R0100  waits on c0090",
			"now: c0090 (any CLI can)",
			"",
		}, "\n"))
		local skill = zn({ "work", "R0100" })
		t.expect(has(skill, "# Work the queue")).toBe(true)
		t.expect(has(skill, "This session's raft is R0100. Pass it to every ./zn work next.")).toBe(true)
		t.expect(has(skill, graph)).toBe(true)
		t.expect(has(zn({ "work", "graph" }), "usage: ./zn work graph <R-id>")).toBe(true)
	end)

	it("./zn work next on a raft that waits only for the person prints the stop", function()
		setup()
		local out = zn({ "work", "next", "R0110" })
		t.expect(has(out, "R0110: end - ")).toBe(true)
		t.expect(
			has(
				out,
				"R0110 is not landed yet: 1 unit needed, 0 can be worked now, 1 wait for you\npickman/.tracker/rafts/R0110/questions.md # answer each question in it\nThen run ./zn work R0110 again."
			)
		).toBe(true)
		-- --one is the raft's own answer, with no stop
		t.expect(has(zn({ "work", "next", "--one", "R0110" }), "is not landed yet")).toBe(false)
	end)

	it(
		"the z-work skill: delivers the raft and its dependencies, and a person-only wait is a stop",
		function()
			local text = fs.readFile(`{TOP}/z-nile/skills/z-work/SKILL.md`)
			t.expect(
				has(
					text,
					"delivers that raft and the rafts it depends on until it lands or only you can move it"
				)
			).toBe(true)
			t.expect(has(text, "A named raft is delivered, with the rafts it depends on")).toBe(true)
			t.expect(has(text, "it is the Stops message")).toBe(true)
			t.expect(has(text, "a landed raft needs no more than that line")).toBe(true)
			local run = fs.readFile(`{TOP}/z-nile/skills/z-run/SKILL.md`)
			t.expect(has(run, "`/z-run <R>` is z-work with that raft named.")).toBe(true)
			t.expect(has(run, "A named raft is delivered, not stepped")).toBe(true)
		end
	)
end)
