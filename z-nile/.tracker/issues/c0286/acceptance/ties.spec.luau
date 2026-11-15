--!strict
-- c0286 AC1: raftplan.plan keeps tied issues together. An issue's `tied:` names other issues (a recorded user decision
-- that they land as one raft); the ties are undirected and taken as connected groups over every issue in the tree,
-- whatever its state. While any member of a tie is not prepared, the plan rafts none of it and skips each prepared
-- member naming why; once every member is prepared the tie is one raft, whatever its size or surface, or folds into the
-- one open raft that holds the rest of it. A raft that holds a tied issue takes no other issue from the plan. A tie
-- that one raft can't hold (two types or projects, a solo member, a member gone elsewhere) is skipped and named.
local raftplan = require("@znile/engine/raftplan")
local t = require("@tests/lib/t")

local Z, P = "z-nile/.tracker", "pickman/.tracker"

local function issue(id: string, size: number?, opts: { [string]: any }?): raftplan.Issue
	local kinds = { f = "feature", d = "defect", c = "chore" }
	local o: { [string]: any } = opts or {}
	local i: raftplan.Issue = {
		id = id,
		type = kinds[string.sub(id, 1, 1)],
		root = o.root or Z,
		state = o.state or "backlog",
		status = o.status or "prepared",
		design = o.design or "ready",
		raft = o.raft or "",
		size = size,
		solo = o.solo == true,
		touched = o.touched,
	}
	(i :: any).tied = o.tied -- the raw `tied:` value, as main reads it from the front matter
	return i
end
-- an issue that is not prepared yet: new, with a draft design
local function fresh(id: string, opts: { [string]: any }?): raftplan.Issue
	local o: { [string]: any } = table.clone(opts or {})
	o.status = o.status or "new"
	o.design = o.design or "draft"
	return issue(id, nil, o)
end
local function raft(id: string, kind: string, members: { string }, opts: { [string]: any }?): raftplan.Raft
	local o: { [string]: any } = opts or {}
	return {
		id = id,
		type = kind,
		root = o.root or Z,
		state = o.state or "backlog",
		status = o.status or "prepared",
		single = o.single == true,
		members = members,
	}
end
-- the plan as one line per op ("fold R0010 c0001,c0002", "new chore c0003", "new chore c0004 single"), then the skips
-- as "skip <id>: <reason>"
local function lines(issues: { raftplan.Issue }, rafts: { raftplan.Raft }?, cap: number?): { string }
	local ops, skips = raftplan.plan(issues, rafts or {}, cap)
	local out: { string } = {}
	for _, op in ops do
		local head = if op.kind == "fold" then `fold {op.raft}` else `new {op.type}`
		table.insert(out, `{head} {table.concat(op.issues, ",")}{if op.single then " single" else ""}`)
	end
	for _, sk in skips do
		table.insert(out, `skip {sk.id}: {sk.reason}`)
	end
	return out
end
local WAIT =
	"not prepared yet: raft-plan rafts them together when every one is (retry a dispatched member once that rafting has merged)"

return t.spec("c0286 raftplan.plan: tied issues are rafted together", function(it)
	it("reads tied: as a list of issue ids, refusing anything else", function()
		t.expect((raftplan.parseTied(nil))).toEqual({})
		t.expect((raftplan.parseTied(""))).toEqual({})
		t.expect((raftplan.parseTied("[]"))).toEqual({})
		local ids, problem = raftplan.parseTied("[c0002, f0003,d0004 ]")
		t.expect(problem).toBe(nil)
		t.expect(ids).toEqual({ "c0002", "f0003", "d0004" })
		local function problemOf(value: string): string?
			local list, why = raftplan.parseTied(value)
			t.expect(list).toEqual({})
			return why
		end
		t.expect(problemOf("c0002")).toBe("tied: is not a list of issue ids: c0002")
		t.expect(problemOf("[c0002, R0010]")).toBe("tied: names R0010, which is not an issue id")
		t.expect(problemOf("[c2]")).toBe("tied: names c2, which is not an issue id")
		t.expect(problemOf("[c0002, c0002]")).toBe("tied: names c0002 twice")
	end)

	it("rafts none of a tie while a member is not prepared, and names why on each prepared one", function()
		local issues = {
			issue("c0001", 100, { tied = "[c0002, c0003]" }),
			fresh("c0002", { tied = "[c0001, c0003]" }),
			fresh("c0003", { status = "preparing" }),
			issue("c0004", 100, { tied = "[c0001]" }),
			issue("c0005", 100), -- untied: planned as before
		}
		t.expect(lines(issues)).toEqual({
			"new chore c0005",
			`skip c0001: tied to c0002, c0003, c0004: c0002 (new, design draft), c0003 (preparing, design draft) {WAIT}`,
			`skip c0004: tied to c0001, c0002, c0003: c0002 (new, design draft), c0003 (preparing, design draft) {WAIT}`,
		})
	end)

	it("makes a tie one raft once every member is prepared, whatever the cap, and not single", function()
		local issues = {
			issue("c0001", 900, { tied = "[c0002, c0003]" }),
			issue("c0002", 900),
			issue("c0003", 2000), -- over the cap alone: it still goes with its tie
			issue("c0004", 100),
		}
		t.expect(lines(issues)).toEqual({ "new chore c0001,c0002,c0003", "new chore c0004" })
	end)

	it("reads the ties both ways and through each other, from any member's line, in any state", function()
		-- c0001 has no tied: line; c0002 (not prepared) names it, and c0003 is reached through c0002
		local issues = {
			issue("c0001", 100),
			fresh("c0002", { tied = "[c0001]" }),
			issue("c0003", 100, { tied = "[c0002]" }),
		}
		t.expect(lines(issues)).toEqual({
			`skip c0001: tied to c0002, c0003: c0002 (new, design draft) {WAIT}`,
			`skip c0003: tied to c0001, c0002: c0002 (new, design draft) {WAIT}`,
		})
		issues[2] = issue("c0002", 100, { tied = "[c0001]" })
		t.expect(lines(issues)).toEqual({ "new chore c0001,c0002,c0003" })
	end)

	it("groups tied features whatever their surface", function()
		local issues = {
			issue("f0001", 100, { touched = { "a" }, tied = "[f0002]" }),
			issue("f0002", 100, { touched = { "b" } }),
			issue("f0003", 100, { touched = { "a/x" } }), -- shares f0001's surface, but is not tied
		}
		t.expect(lines(issues)).toEqual({ "new feature f0001,f0002", "new feature f0003" })
	end)

	it("folds the rest of a tie into the one open raft that holds some of it, past the cap", function()
		local issues = {
			issue("c0090", 1400, { raft = "R0010", tied = "[c0001, c0002]" }),
			issue("c0001", 900),
			issue("c0002", 100),
		}
		t.expect(lines(issues, { raft("R0010", "chore", { "c0090" }) })).toEqual({ "fold R0010 c0001,c0002" })
	end)

	it("never rafts a tie apart from members held by a raft that can't take the rest", function()
		local issues = {
			issue("c0090", 100, { raft = "R0010", tied = "[c0001]" }),
			issue("c0001", 100),
		}
		local cases: { { r: raftplan.Raft, what: string } } = {
			{
				r = raft("R0010", "chore", { "c0090" }, { state = "active", status = "active" }),
				what = "active, active",
			},
			{
				r = raft("R0010", "chore", { "c0090" }, { state = "done", status = "done" }),
				what = "done, done",
			},
			{ r = raft("R0010", "chore", { "c0090" }, { single = true }), what = "single" },
		}
		for _, case in cases do
			t.expect(lines(issues, { case.r })).toEqual({
				`skip c0001: tied to c0090: R0010, which holds some of them, is {case.what}: z-raft with arguments decides`,
			})
		end
		t.expect(lines(issues)).toEqual({
			"skip c0001: tied to c0090: R0010, which holds some of them, is not in the tree",
		})
		-- review 001 F4: a raft being rafted (a fold not landed yet) is waited for, not sent to z-raft with arguments
		t.expect(lines(issues, { raft("R0010", "chore", { "c0090" }, { status = "preparing" }) })).toEqual({
			"skip c0001: tied to c0090: R0010, which holds some of them, is being rafted: raft-plan places them once that rafting lands",
		})
		-- members in two rafts
		local split = {
			issue("c0090", 100, { raft = "R0010", tied = "[c0001, c0091]" }),
			issue("c0091", 100, { raft = "R0020" }),
			issue("c0001", 100),
		}
		t.expect(lines(split, { raft("R0010", "chore", { "c0090" }), raft("R0020", "chore", { "c0091" }) }))
			.toEqual({
				"skip c0001: tied to c0090, c0091: its members are in R0010 and R0020: z-raft with arguments decides (./zn recombine)",
			})
		-- a member delivered with no raft
		t.expect(lines({
			issue("c0001", 100, { tied = "[c0090]" }),
			fresh("c0090", { state = "done", status = "done" }),
		})).toEqual({
			"skip c0001: tied to c0090: c0090 is done with no raft: z-raft with arguments decides",
		})
	end)

	it("waits for every member before folding into the raft that holds some of them", function()
		local issues = {
			issue("c0090", 100, { raft = "R0010", tied = "[c0001, c0002]" }),
			issue("c0001", 100),
			fresh("c0002"),
		}
		t.expect(lines(issues, { raft("R0010", "chore", { "c0090" }) })).toEqual({
			`skip c0001: tied to c0002, c0090: c0002 (new, design draft) {WAIT}`,
		})
	end)

	it("folds no untied issue into a raft that holds a tied one", function()
		local untied = issue("c0001", 100)
		local held = {
			issue("c0090", 100, { raft = "R0010", tied = "[c0091]" }),
			issue("c0091", 100, { raft = "R0010" }),
			untied,
		}
		local rafts = { raft("R0010", "chore", { "c0090", "c0091" }) }
		t.expect(lines(held, rafts)).toEqual({ "new chore c0001" })
		-- the control: the same raft with no tie takes it
		held[1] = issue("c0090", 100, { raft = "R0010" })
		t.expect(lines(held, rafts)).toEqual({ "fold R0010 c0001" })
		-- and features: a tied raft is no surface to fold into
		local feats = {
			issue("f0090", 100, { raft = "R0020", touched = { "a" }, tied = "[f0091]" }),
			issue("f0091", 100, { raft = "R0020", touched = { "b" } }),
			issue("f0001", 100, { touched = { "a/x" } }),
		}
		t.expect(lines(feats, { raft("R0020", "feature", { "f0090", "f0091" }) }))
			.toEqual({ "new feature f0001" })
	end)

	it("skips a tie one raft can't hold, and names the member that breaks it", function()
		t.expect(lines({ issue("c0001", 100, { tied = "[c0009]" }) }))
			.toEqual({ "skip c0001: tied to c0009: c0009 is not in the tree" })
		t.expect(lines({ issue("c0001", 100, { tied = "[d0002]" }), issue("d0002", 100) })).toEqual({
			"skip c0001: tied to d0002: d0002 is a defect of z-nile/.tracker and c0001 a chore of z-nile/.tracker: one raft holds one type of one project",
			"skip d0002: tied to c0001: d0002 is a defect of z-nile/.tracker and c0001 a chore of z-nile/.tracker: one raft holds one type of one project",
		})
		t.expect(lines({ issue("c0001", 100, { tied = "[c0002]" }), issue("c0002", 100, { root = P }) }))
			.toEqual({
				"skip c0001: tied to c0002: c0002 is a chore of pickman/.tracker and c0001 a chore of z-nile/.tracker: one raft holds one type of one project",
				"skip c0002: tied to c0001: c0002 is a chore of pickman/.tracker and c0001 a chore of z-nile/.tracker: one raft holds one type of one project",
			})
		t.expect(lines({ issue("c0001", 100, { tied = "[c0002]" }), issue("c0002", 100, { solo = true }) }))
			.toEqual({
				"skip c0001: tied to c0002: c0002 is solo: true, a raft by itself: z-raft with arguments decides",
				"skip c0002: tied to c0001: c0002 is solo: true, a raft by itself: z-raft with arguments decides",
			})
	end)

	it("skips an issue whose tied: it can't read, and its tie waits for it", function()
		t.expect(lines({ issue("c0001", 100, { tied = "c0002" }), issue("c0002", 100) })).toEqual({
			"new chore c0002",
			"skip c0001: tied: is not a list of issue ids: c0002",
		})
		t.expect(
			lines({ issue("c0001", 100, { tied = "[c0002, R1]" }), issue("c0002", 100, { tied = "[c0001]" }) })
		)
			.toEqual({
				"skip c0001: tied: names R1, which is not an issue id",
				`skip c0002: tied to c0001: c0001 (tied: unreadable) {WAIT}`,
			})
	end)

	it("skips a tied issue with no size: as before, and its tie waits for it", function()
		t.expect(lines({ issue("c0001", nil, { tied = "[c0002]" }), issue("c0002", 100) })).toEqual({
			"skip c0001: no size: (z-design records its estimate of changed lines)",
			`skip c0002: tied to c0001: c0001 (no size:) {WAIT}`,
		})
	end)

	it("names an unreadable tied: on a backlog issue that is not prepared, too", function()
		-- review 001 F2: a malformed line on a member that is not a candidate never loses the tie silently
		t.expect(lines({ issue("c0001", 100), fresh("c0002", { tied = "c0001" }) })).toEqual({
			"new chore c0001",
			"skip c0002: tied: is not a list of issue ids: c0001",
		})
		-- not in the backlog: not the plan's to name
		t.expect(
			lines({ issue("c0001", 100), fresh("c0002", { tied = "c0001", state = "done", status = "done" }) })
		)
			.toEqual({ "new chore c0001" })
	end)

	it("names the first cause in the stated order when a tie has several", function()
		-- review 001 F5: a raft that is not open (6) is named before members still waiting (7)
		t.expect(lines({
			issue("c0090", 100, { raft = "R0010", tied = "[c0001, c0002]" }),
			issue("c0001", 100),
			fresh("c0002"),
		}, { raft("R0010", "chore", { "c0090" }, { state = "active", status = "active" }) })).toEqual({
			"skip c0001: tied to c0002, c0090: R0010, which holds some of them, is active, active: z-raft with arguments decides",
		})
		-- so is a raft being rafted
		t.expect(lines({
			issue("c0090", 100, { raft = "R0010", tied = "[c0001, c0002]" }),
			issue("c0001", 100),
			fresh("c0002"),
		}, { raft("R0010", "chore", { "c0090" }, { status = "preparing" }) })).toEqual({
			"skip c0001: tied to c0002, c0090: R0010, which holds some of them, is being rafted: raft-plan places them once that rafting lands",
		})
		-- an id not in the tree (1) before members still waiting (7)
		t.expect(lines({ issue("c0001", 100, { tied = "[c0002, c0009]" }), fresh("c0002") })).toEqual({
			"skip c0001: tied to c0002, c0009: c0009 is not in the tree",
		})
		-- two types (2) before a solo member (3)
		t.expect(lines({ issue("c0001", 100, { tied = "[d0002]" }), issue("d0002", 100, { solo = true }) }))
			.toEqual({
				"skip c0001: tied to d0002: d0002 is a defect of z-nile/.tracker and c0001 a chore of z-nile/.tracker: one raft holds one type of one project",
				"skip d0002: tied to c0001: d0002 is a defect of z-nile/.tracker and c0001 a chore of z-nile/.tracker: one raft holds one type of one project",
			})
		-- a member done with no raft (4) before members in two rafts (5)
		t.expect(lines({
			issue("c0001", 100, { tied = "[c0002, c0090, c0091]" }),
			fresh("c0002", { state = "done", status = "done" }),
			issue("c0090", 100, { raft = "R0010" }),
			issue("c0091", 100, { raft = "R0020" }),
		}, { raft("R0010", "chore", { "c0090" }), raft("R0020", "chore", { "c0091" }) })).toEqual({
			"skip c0001: tied to c0002, c0090, c0091: c0002 is done with no raft: z-raft with arguments decides",
		})
		-- members in two rafts (5) before a raft that is not open (6)
		t.expect(lines({
			issue("c0001", 100, { tied = "[c0090, c0091]" }),
			issue("c0090", 100, { raft = "R0010" }),
			issue("c0091", 100, { raft = "R0020" }),
		}, {
			raft("R0010", "chore", { "c0090" }, { state = "active", status = "active" }),
			raft("R0020", "chore", { "c0091" }),
		})).toEqual({
			"skip c0001: tied to c0090, c0091: its members are in R0010 and R0020: z-raft with arguments decides (./zn recombine)",
		})
	end)

	it(
		"folds a tie into the open raft that holds some of it beside untied members, once the rest are prepared",
		function()
			-- review 001 F1's shape: R0010 holds an untied c0080 and a tied c0090; the tie's other members are raftless,
			-- some not prepared yet; an untied prepared chore c0005 is never folded into R0010
			local issues = {
				issue("c0080", 100, { raft = "R0010" }),
				issue("c0090", 100, { raft = "R0010" }),
				issue("c0001", 900, { tied = "[c0002, c0003, c0090]" }),
				issue("c0002", 900),
				fresh("c0003", { tied = "[c0001, c0002, c0090]" }),
				issue("c0005", 100),
			}
			local rafts = { raft("R0010", "chore", { "c0080", "c0090" }), raft("R0030", "chore", {}) }
			t.expect(lines(issues, rafts)).toEqual({
				"fold R0030 c0005",
				`skip c0001: tied to c0002, c0003, c0090: c0003 (new, design draft) {WAIT}`,
				`skip c0002: tied to c0001, c0003, c0090: c0003 (new, design draft) {WAIT}`,
			})
			issues[5] = issue("c0003", 900, { tied = "[c0001, c0002, c0090]" })
			t.expect(lines(issues, rafts)).toEqual({ "fold R0010 c0001,c0002,c0003", "fold R0030 c0005" })
		end
	)

	it("gives the same plan and skips for the same backlog in any order", function()
		local issues = {
			issue("c0001", 900, { tied = "[c0002]" }),
			issue("c0002", 900, { tied = "[c0003]" }),
			issue("c0003", 900),
			issue("c0004", 100, { tied = "[c0005]" }),
			fresh("c0005"),
			issue("c0006", 100),
			issue("c0090", 100, { raft = "R0010", tied = "[c0007]" }),
			issue("c0007", 100),
			issue("d0008", 100),
		}
		local rafts =
			{ raft("R0010", "chore", { "c0090" }), raft("R0020", "defect", {}), raft("R0030", "chore", {}) }
		local want = lines(issues, rafts)
		t.expect(want).toEqual({
			"fold R0020 d0008",
			"new chore c0001,c0002,c0003",
			"fold R0030 c0006", -- R0010 holds a tied issue, so the chore goes to the next open raft
			"fold R0010 c0007",
			`skip c0004: tied to c0005: c0005 (new, design draft) {WAIT}`,
		})
		local seed = 11
		local function rand(n: number): number
			seed = (seed * 1103515245 + 12345) % 2147483648
			return seed % n + 1
		end
		for _ = 1, 20 do
			local a, b = table.clone(issues), table.clone(rafts)
			for i = #a, 2, -1 do
				local j = rand(i)
				a[i], a[j] = a[j], a[i]
			end
			for i = #b, 2, -1 do
				local j = rand(i)
				b[i], b[j] = b[j], b[i]
			end
			t.expect(lines(a, b)).toEqual(want)
		end
	end)
end)
