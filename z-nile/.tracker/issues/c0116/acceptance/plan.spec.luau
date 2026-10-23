--!strict
-- c0116 AC3: z-raft's no-argument policy, raftplan.plan (pure). One type and one project per raft; only prepared
-- backlog rafts that are not single take more; defects fold into the lowest open prepared defect raft that fits, chores
-- the same; features group only by a shared surface (overlapping Touched paths, as connected groups; none shares
-- nothing); the size cap of 1,500 changed lines starts another raft; an over-cap or solo issue is a raft by itself; an
-- issue with no size: is skipped and named; the same backlog in any order gives the same plan.
local raftplan = require("@znile/engine/raftplan")
local t = require("@tests/lib/t")

local Z, P = "z-nile/.tracker", "pickman/.tracker"

local function issue(id: string, size: number?, opts: { [string]: any }?): raftplan.Issue
	local kinds = { f = "feature", d = "defect", c = "chore" }
	local o: { [string]: any } = opts or {}
	return {
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
-- the plan as one line per op: "fold R0010 d0001,d0002", "new defect d0003", "new chore c0004 single"
local function lines(issues: { raftplan.Issue }, rafts: { raftplan.Raft }?, cap: number?): { string }
	local ops = raftplan.plan(issues, rafts or {}, cap)
	local out: { string } = {}
	for _, op in ops do
		local head = if op.kind == "fold" then `fold {op.raft}` else `new {op.type}`
		table.insert(out, `{head} {table.concat(op.issues, ",")}{if op.single then " single" else ""}`)
	end
	return out
end

return t.spec("c0116 raftplan.plan: z-raft's policy with no argument", function(it)
	it("folds defects into the one open prepared defect raft, chores likewise, never mixing types", function()
		local issues = {
			issue("d0001", 100),
			issue("d0002", 100),
			issue("c0003", 100),
			issue("c0004", 100),
			issue("d0090", 100, { raft = "R0010" }),
		}
		t.expect(lines(issues, { raft("R0010", "defect", { "d0090" }) })).toEqual({
			"fold R0010 d0001,d0002",
			"new chore c0003,c0004",
		})
	end)

	it(
		"never folds into a raft that is not prepared in the backlog, or is single, and opens a new one instead",
		function()
			local issues = { issue("d0001", 100) }
			for _, r in
				{
					raft("R0010", "defect", {}, { status = "preparing" }),
					raft("R0010", "defect", {}, { status = "new" }),
					raft("R0010", "defect", {}, { state = "active", status = "active" }),
					raft("R0010", "defect", {}, { state = "done", status = "done" }),
					raft("R0010", "defect", {}, { single = true }),
				}
			do
				t.expect(lines(issues, { r })).toEqual({ "new defect d0001" })
			end
		end
	)

	it("folds into the lowest open raft that still fits, and starts another raft past the cap", function()
		local issues = {
			issue("d0090", 1000, { raft = "R0010" }),
			issue("d0001", 400),
			issue("d0002", 600),
			issue("d0003", 1000),
			issue("d0004", 100),
		}
		local rafts = { raft("R0020", "defect", {}), raft("R0010", "defect", { "d0090" }) }
		-- R0010 holds 1000: d0001 (400) fits; d0002 (600) only fits R0020; d0003 (1000) fits neither; d0004 tops R0010 up to 1500
		t.expect(lines(issues, rafts)).toEqual({
			"fold R0010 d0001,d0004",
			"fold R0020 d0002",
			"new defect d0003",
		})
		-- exactly at the cap still fits
		t.expect(lines({ issue("c0001", 1000), issue("c0002", 500) })).toEqual({ "new chore c0001,c0002" })
		t.expect(lines({ issue("c0001", 1000), issue("c0002", 501) }))
			.toEqual({ "new chore c0001", "new chore c0002" })
	end)

	it("makes an over-cap issue a raft by itself, never split, and a smaller cap is honoured", function()
		t.expect(lines({ issue("c0001", 2400), issue("c0002", 100) }))
			.toEqual({ "new chore c0001 single", "new chore c0002" })
		t.expect(lines({ issue("c0001", 300), issue("c0002", 300) }, {}, 500))
			.toEqual({ "new chore c0001", "new chore c0002" })
	end)

	it("keeps solo issues alone: three solo chores make three single rafts, and none is folded", function()
		local issues = {
			issue("c0001", 100, { solo = true }),
			issue("c0002", 100, { solo = true }),
			issue("c0003", 100, { solo = true }),
			issue("c0090", 100, { raft = "R0010" }),
		}
		t.expect(lines(issues, { raft("R0010", "chore", { "c0090" }) })).toEqual({
			"new chore c0001 single",
			"new chore c0002 single",
			"new chore c0003 single",
		})
	end)

	it("skips and names an issue with no size, and plans the rest", function()
		local ops, skips = raftplan.plan({ issue("c0001", nil), issue("c0002", 100) }, {})
		t.expect(#ops).toBe(1)
		t.expect(ops[1].issues).toEqual({ "c0002" })
		t.expect(#skips).toBe(1)
		t.expect(skips[1].id).toBe("c0001")
		t.expect(string.find(skips[1].reason, "size:", 1, true) ~= nil).toBe(true)
	end)

	it("never crosses projects", function()
		local issues = {
			issue("c0001", 100, { root = P }),
			issue("c0002", 100),
			issue("c0090", 100, { raft = "R0010" }),
		}
		local ops = raftplan.plan(issues, { raft("R0010", "chore", { "c0090" }) })
		t.expect(#ops).toBe(2)
		for _, op in ops do
			if table.find(op.issues, "c0001") then
				t.expect(op.kind).toBe("new")
				t.expect(op.root).toBe(P)
			else
				t.expect(op.raft).toBe("R0010")
				t.expect(op.root).toBe(Z)
			end
		end
	end)

	it("groups features only by a shared surface, as connected groups, and none shares nothing", function()
		local issues = {
			issue("f0001", 100, { touched = { "z-nile/engine/board.luau" } }),
			issue("f0002", 100, { touched = { "z-nile/engine" } }), -- a parent folder overlaps
			issue("f0003", 100, { touched = { "z-nile/engine-extra" } }), -- a longer name is not a child
			issue("f0004", 100, { touched = { "zn", "z-nile/engine-extra/x.luau" } }), -- links f0003 in
			issue("f0005", 100), -- no Touched modules
			issue("f0006", 100, { touched = {} }),
		}
		t.expect(lines(issues)).toEqual({
			"new feature f0001,f0002",
			"new feature f0003,f0004",
			"new feature f0005",
			"new feature f0006",
		})
	end)

	it("folds a feature into an open feature raft whose member shares its surface", function()
		local issues = {
			issue("f0090", 100, { raft = "R0010", touched = { "pickman/src/Maze" } }),
			issue("f0001", 100, { touched = { "pickman/src/Maze/grid.luau" } }),
			issue("f0002", 100, { touched = { "pickman/src/Ghost" } }),
		}
		t.expect(lines(issues, { raft("R0010", "feature", { "f0090" }) })).toEqual({
			"fold R0010 f0001",
			"new feature f0002",
		})
	end)

	it("plans only prepared, raftless backlog issues with a ready design", function()
		local issues = {
			issue("c0001", 100, { status = "preparing" }),
			issue("c0002", 100, { design = "reviewed" }),
			issue("c0003", 100, { raft = "R0010" }),
			issue("c0004", 100, { state = "active", status = "active" }),
			issue("c0005", 100, { status = "new", design = "draft" }),
		}
		local ops, skips = raftplan.plan(issues, {})
		t.expect(#ops).toBe(0)
		t.expect(#skips).toBe(0)
	end)

	it("gives the same plan for the same backlog in any order", function()
		local issues = {
			issue("d0001", 700),
			issue("d0002", 700),
			issue("d0003", 700),
			issue("c0004", 100, { solo = true }),
			issue("c0005", 100),
			issue("f0006", 100, { touched = { "a" } }),
			issue("f0007", 100, { touched = { "a/b" } }),
			issue("f0008", 100, { touched = { "b" } }),
			issue("f0090", 100, { raft = "R0020", touched = { "b/c" } }),
		}
		local rafts =
			{ raft("R0010", "defect", {}), raft("R0020", "feature", { "f0090" }), raft("R0030", "chore", {}) }
		local want = lines(issues, rafts)
		local seed = 7
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

	it("reads size: as a positive whole number of lines", function()
		t.expect(raftplan.parseSize("300")).toBe(300)
		t.expect(raftplan.parseSize("0")).toBe(nil)
		t.expect(raftplan.parseSize("about 300")).toBe(nil)
		t.expect(raftplan.parseSize("-5")).toBe(nil)
		t.expect(raftplan.parseSize(nil)).toBe(nil)
	end)

	it("never folds into an open raft with a member that has no size:, and says so", function()
		local issues = {
			issue("f0090", nil, { raft = "R0010", touched = { "a" } }),
			issue("f0091", 100, { raft = "R0010", touched = { "a" } }),
			issue("f0001", 100, { touched = { "a/b" } }),
			issue("d0002", 100),
		}
		local rafts = { raft("R0010", "feature", { "f0090", "f0091" }), raft("R0020", "defect", { "d0099" }) }
		local ops, skips = raftplan.plan(issues, rafts)
		t.expect(lines(issues, rafts)).toEqual({ "new feature f0001", "new defect d0002" })
		local named: { [string]: string } = {}
		for _, sk in skips do
			named[sk.id] = sk.reason
		end
		t.expect(string.find(named.R0010 or "", "f0090 has no size:", 1, true) ~= nil).toBe(true)
		t.expect(string.find(named.R0020 or "", "d0099 has no size:", 1, true) ~= nil).toBe(true)
		t.expect(#ops).toBe(2)
	end)

	it(
		"hashes a member's design without its status: and raft: lines, and changes with anything else",
		function()
			local doc =
				"---\nid: c0001\nraft: \nsize: 100\nstatus: prepared-a-b-c\n---\n\n# c0001\n\n## Design\nOne.\n"
			local h = raftplan.designHash(doc)
			t.expect(string.match(h, "^%x+$") ~= nil and #h == 12).toBe(true)
			local moved = (string.gsub(doc, "status: prepared%-a%-b%-c", "status: active-d-e-f"))
			moved = (string.gsub(moved, "raft: \n", "raft: R0010\n"))
			t.expect(raftplan.designHash(moved)).toBe(h)
			t.expect(raftplan.designHash(doc .. "Two.\n") ~= h).toBe(true)
			t.expect(raftplan.designHash((string.gsub(doc, "size: 100", "size: 200"))) ~= h).toBe(true)
		end
	)

	it("reads and writes the grouped: record, refusing a malformed entry and an id twice", function()
		local map, problem = raftplan.parseGrouped("[c0002@bbbbbbbbbbbb, c0001@aaaaaaaaaaaa]")
		t.expect(problem).toBe(nil)
		t.expect(map).toEqual({ c0001 = "aaaaaaaaaaaa", c0002 = "bbbbbbbbbbbb" })
		t.expect(raftplan.renderGrouped(map)).toBe("[c0001@aaaaaaaaaaaa, c0002@bbbbbbbbbbbb]")
		t.expect(select(2, raftplan.parseGrouped("[c0001@aaaa, c0001@bbbb]")) ~= nil).toBe(true)
		t.expect(select(2, raftplan.parseGrouped("[c0001]")) ~= nil).toBe(true)
		t.expect(select(2, raftplan.parseGrouped("c0001@aaaa")) ~= nil).toBe(true)
		t.expect((raftplan.parseGrouped(nil))).toEqual({})
	end)

	it(
		"records a member over its design files: document, check.sh, acceptance specs, reviews and harvest",
		function()
			local base: { [string]: string } = {
				["c0001.md"] = "---\nid: c0001\nraft: \nstatus: prepared-a-b-c\n---\n\n# c0001\n",
				["check.sh"] = 'check "AC1: x" true\n',
				["acceptance/a.spec.luau"] = "--!strict\nreturn nil\n",
				["design-review-001.md"] = "# Review 001\n",
			}
			local function with(rel: string, text: string?): { [string]: string }
				local c = table.clone(base)
				c[rel] = text :: any
				return c
			end
			local h = raftplan.recordHash("c0001", base)
			for _, rel in { "check.sh", "acceptance/a.spec.luau", "design-review-001.md" } do
				t.expect(raftplan.recordHash("c0001", with(rel, base[rel] .. "more\n")) ~= h).toBe(true)
			end
			for _, rel in { "acceptance/b.spec.luau", "design-refute-001.md", "harvest.md" } do
				t.expect(raftplan.recordHash("c0001", with(rel, "new\n")) ~= h).toBe(true)
			end
			-- files that change for other reasons leave it alone
			for _, rel in { "spend.md", "prompt.md", "experiments/e1.luau" } do
				t.expect(raftplan.recordHash("c0001", with(rel, "anything\n"))).toBe(h)
			end
			local moved =
				with("c0001.md", "---\nid: c0001\nraft: R0010\nstatus: active-d-e-f\n---\n\n# c0001\n")
			t.expect(raftplan.recordHash("c0001", moved)).toBe(h)
			t.expect(raftplan.isDesignFile("c0001.md", "c0001")).toBe(true)
			t.expect(raftplan.isDesignFile("c0002.md", "c0001")).toBe(false)
		end
	)
end)
