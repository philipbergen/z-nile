--!strict
-- c0107 AC1: board.collect groups every raft and issue into ready / not / done and sets the next command.
local board = require("@scripts/tracker/board")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

local ROOT = ".cache/c0107-views"

local function dirname(path: string): string
	return string.match(path, "^(.*)/[^/]*$") or "."
end

local function write(path: string, front: { string }, body: string)
	local full = `{ROOT}/{path}`
	fs.writeDir(`{ROOT}/{dirname(path)}`)
	fs.writeFile(full, "---\n" .. table.concat(front, "\n") .. "\n---\n\n" .. body)
end

local function byId(list: { any }): { [string]: any }
	local out: { [string]: any } = {}
	for _, item in list do
		out[item.id] = item
	end
	return out
end

local function bucket(groups: any, id: string): string?
	local found: string? = nil
	for _, name in { "ready", "not", "done" } do
		for _, item in groups[name] do
			if item == id then
				if found then
					error(`{id} is in {found} and {name}`)
				end
				found = name
			end
		end
	end
	return found
end

return t.spec("c0107 board views", function(it)
	if fs.isDir(ROOT) then
		fs.removeDir(ROOT)
	end
	write("rafts/R9001/R9001.md", {
		"id: R9001",
		"type: feature",
		"title: Prepared",
		"issues: [f9001, f9017]",
		"design: ready",
		"status: prepared-a-b-c",
	}, "# R9001: Prepared\n")
	write("rafts/R9002/R9002.md", {
		"id: R9002",
		"type: chore",
		"title: Preparing",
		"issues: [c9002]",
		"design: ready",
		"status: preparing-a-b-c",
	}, "# R9002: Preparing\n")
	write("rafts/R9003/R9003.md", {
		"id: R9003",
		"type: defect",
		"title: Reviewed",
		"issues: [d9003]",
		"design: reviewed",
		"status: prepared-a-b-c",
	}, "# R9003: Reviewed\n")
	write("rafts/active/R9004/R9004.md", {
		"id: R9004",
		"type: feature",
		"title: Launched",
		"issues: [f9004, c9004]",
		"design: draft",
	}, "# R9004: Launched\n")
	write("rafts/done/R9005/R9005.md", {
		"id: R9005",
		"type: chore",
		"title: Finished",
		"issues: [c9005]",
		"design: ready",
		"status: prepared-a-b-c",
	}, "# R9005: Finished\n")
	write("rafts/R9006/R9006.md", {
		"id: R9006",
		"type: feature",
		"title: Unstamped",
		"issues: []",
		"design: ready",
	}, "# R9006: Unstamped\n")
	write("rafts/R9007/R9007.md", {
		"id: R9007",
		"type: feature",
		"title: Blank type",
		"issues: [f9007]",
		"design: draft",
	}, "# R9007: Blank type\n")
	write("rafts/R9008/R9008.md", {
		"id: R9008",
		"type: feature",
		"title: Defects",
		"issues: [d9008, d9018]",
		"design: draft",
	}, "# R9008: Defects\n")
	write("rafts/R9009/R9009.md", {
		"id: R9009",
		"type: feature",
		"title: Plain",
		"issues: []",
		"design: ready",
		"status: prepared",
	}, "# R9009: Plain\n")
	write("rafts/R9010/R9010.md", {
		"id: R9010",
		"type: chore",
		"title: Legacy",
		"issues: []",
		"design: ready",
		"status: active-quiet-copper-falcon",
	}, "# R9010: Legacy\n")
	write("issues/f9001/f9001.md", {
		"id: f9001",
		"type: feature",
		"title: Member",
		"raft: R9001",
		"depends_on: [c9009]",
		"design: ready",
	}, "# f9001: Member\n")
	write("issues/f9017/f9017.md", {
		"id: f9017",
		"type:",
		"title: Untyped",
		"raft: R9001",
		"depends_on: []",
		"design: draft",
	}, "# f9017: Untyped\n")
	write("issues/c9002/c9002.md", {
		"id: c9002",
		"type: chore",
		"title: Still preparing",
		"raft: R9002",
		"depends_on: []",
		"design: ready",
	}, "# c9002: Still preparing\n")
	write("issues/d9003/d9003.md", {
		"id: d9003",
		"type: defect",
		"title: In review",
		"raft: R9003",
		"depends_on: []",
		"design: reviewed",
	}, "# d9003: In review\n")
	write("issues/active/f9004/f9004.md", {
		"id: f9004",
		"type: feature",
		"title: Live feature",
		"raft: R9004",
		"depends_on: []",
		"design: draft",
	}, "# f9004: Live feature\n")
	write("issues/active/c9004/c9004.md", {
		"id: c9004",
		"type: chore",
		"title: Live chore",
		"raft: R9004",
		"depends_on: []",
		"design: draft",
	}, "# c9004: Live chore\n")
	write("issues/done/c9005/c9005.md", {
		"id: c9005",
		"type: chore",
		"title: Closed member",
		"raft: R9005",
		"depends_on: []",
		"design: ready",
	}, "# c9005: Closed member\n")
	write("issues/done/f9006/f9006.md", {
		"id: f9006",
		"type: feature",
		"title: Closed early",
		"raft: R9004",
		"depends_on: []",
		"design: draft",
	}, "# f9006: Closed early\n")
	write("issues/f9007/f9007.md", {
		"id: f9007",
		"type:",
		"title: No type",
		"raft: R9007",
		"depends_on: []",
		"design: draft",
	}, "# f9007: No type\n")
	write("issues/d9008/d9008.md", {
		"id: d9008",
		"type: defect",
		"title: Defect A",
		"raft: R9008",
		"depends_on: []",
		"design: draft",
	}, "# d9008: Defect A\n")
	write("issues/d9018/d9018.md", {
		"id: d9018",
		"type: defect",
		"title: Defect B",
		"raft: R9008",
		"depends_on: []",
		"design: draft",
	}, "# d9018: Defect B\n")
	write("issues/c9009/c9009.md", {
		"id: c9009",
		"type: feature",
		"title: Loose",
		"raft:",
		"depends_on: []",
		"design: draft",
	}, "# c9009: Loose\n")
	write("issues/f9005/f9005.md", {
		"id: f9005",
		"type: feature",
		"title: Left behind",
		"raft: R9005",
		"depends_on: [c9008]",
		"design: draft",
	}, "# f9005: Left behind\n")
	write("issues/done/c9008/c9008.md", {
		"id: c9008",
		"type: chore",
		"title: Closed loose",
		"raft:",
		"depends_on: []",
		"design: draft",
	}, "# c9008: Closed loose\n")

	local m = board.collect(ROOT) :: any
	local rafts = byId(m.rafts)
	local issues = byId(m.issues)

	it("opens on Rafts and drops the Active, Waiting and Done lists", function()
		t.expect(m.initialView).toBe("rafts")
		t.expect(m.tabs).toBe(nil)
		t.expect(m.initialTab).toBe(nil)
		t.expect(rafts.R9001.tab).toBe(nil)
		t.expect(rafts.R9001.pseudo).toBe(false)
		for _, raft in m.rafts do
			t.expect((string.find(raft.id, "none:", 1, true))).toBe(nil)
		end
	end)

	it("puts each raft in one group, including a blocked raft whose prep has merged", function()
		t.expect(m.views.rafts.ready).toEqual({ "R9001", "R9004", "R9006", "R9009" })
		t.expect(m.views.rafts["not"]).toEqual({ "R9002", "R9003", "R9007", "R9008", "R9010" })
		t.expect(m.views.rafts.done).toEqual({ "R9005" })
		t.expect(rafts.R9001.topLevel).toBe(false)
		t.expect(rafts.R9001.blockedBy).toEqual({ "c9009" })
		t.expect(bucket(m.views.rafts, "R9001")).toBe("ready")
	end)

	it("sets the raft command from its directory, design and status stamp", function()
		t.expect(rafts.R9001.command).toBe("/ready-raft R9001")
		t.expect(rafts.R9004.command).toBe("/launch-raft R9004")
		t.expect(rafts.R9002.command).toBe(nil)
		t.expect(rafts.R9003.command).toBe(nil)
		t.expect(rafts.R9005.command).toBe(nil)
		t.expect(rafts.R9006.command).toBe("/ready-raft R9006")
		t.expect(rafts.R9006.stage).toBe("prepared")
		t.expect(rafts.R9009.command).toBe("/ready-raft R9009")
		t.expect(rafts.R9010.command).toBe(nil)
		t.expect(rafts.R9010.stage).toBe("active")
		t.expect(rafts.R9002.stage).toBe("preparing")
		t.expect(rafts.R9002.status).toBe("ready")
		t.expect(rafts.R9007.label).toBe("feature")
		t.expect(issues.f9017.label).toBe("")
	end)

	it("puts each issue in one group and copies a command only when one exists", function()
		t.expect(m.views.issues.ready).toEqual({ "c9004", "f9001", "f9004", "f9017" })
		t.expect(m.views.issues["not"])
			.toEqual({ "c9002", "c9009", "d9003", "d9008", "d9018", "f9005", "f9007" })
		t.expect(m.views.issues.done).toEqual({ "c9005", "c9008", "f9006" })
		t.expect(issues.f9001.command).toBe("/ready-raft R9001")
		t.expect(issues.f9017.command).toBe("/ready-raft R9001")
		t.expect(issues.f9004.command).toBe("/launch-raft R9004")
		t.expect(issues.c9004.command).toBe("/launch-raft R9004")
		t.expect(issues.c9009.command).toBe("/ticket-prep c9009")
		t.expect(issues.c9002.command).toBe(nil)
		t.expect(issues.f9006.command).toBe(nil)
		t.expect(issues.c9008.command).toBe(nil)
		t.expect(issues.c9005.command).toBe(nil)
		t.expect(issues.f9005.command).toBe(nil)
		t.expect(bucket(m.views.issues, "f9005")).toBe("not")
		t.expect(issues.f9001.stage).toBe("prepared")
		t.expect(issues.f9017.stage).toBe("preparing")
		t.expect(issues.f9004.stage).toBe("active")
		t.expect(issues.c9005.stage).toBe("done")
		t.expect(issues.c9009.stage).toBe("new")
	end)

	it("maps every id to itself and keeps who a loose issue blocks", function()
		for _, id in
			{
				"R9001",
				"R9002",
				"R9003",
				"R9004",
				"R9005",
				"R9006",
				"R9007",
				"R9008",
				"R9009",
				"R9010",
				"f9001",
				"f9005",
				"f9017",
				"c9002",
				"d9003",
				"f9004",
				"c9004",
				"c9005",
				"f9006",
				"f9007",
				"d9008",
				"d9018",
				"c9009",
				"c9008",
			}
		do
			t.expect(m.home[id]).toBe(id)
			local where = bucket(m.views.rafts, id) or bucket(m.views.issues, id)
			t.expect(where ~= nil).toBe(true)
		end
		t.expect(m.home["none:waiting"]).toBe(nil)
		t.expect(issues.c9009.dependents).toEqual({ "R9001" })
		t.expect(issues.c9008.dependents).toEqual({ "R9005" })
		t.expect(issues.f9001.dependents).toEqual({})
	end)

	fs.removeDir(ROOT)
end)
