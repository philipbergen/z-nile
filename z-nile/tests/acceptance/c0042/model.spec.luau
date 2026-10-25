--!strict
-- c0400 AC1: board.collect reads a tracker tree into the designed model: statuses, raft
-- dependencies both ways, top-level rafts per tab, the "No raft" entries, and a home for every ID.
local board = require("@scripts/tracker/board")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

local fixture = {} :: any

-- { path relative to root, frontmatter lines, body }
fixture.FILES = {
	{
		path = "rafts/done/R0010/R0010.md",
		front = {
			"id: R0010",
			"type: chore",
			"title: Alpha",
			"single: true",
			"issues: [c0010]",
			"design: ready",
		},
		body = "# R0010: Alpha\n\nThe first raft.\n",
	},
	{
		path = "rafts/active/R0020/R0020.md",
		front = {
			"id: R0020",
			"type: feature",
			"title: Beta",
			"single: true",
			"issues: [f0020]",
			"design: ready",
		},
		body = "# R0020: Beta\n\nIn progress.\n",
	},
	{
		path = "rafts/R0030/R0030.md",
		front = {
			"id: R0030",
			"type: feature",
			"title: Gamma",
			"single: false",
			"issues: [f0030, f0031]",
			"design: ready",
		},
		body = "# R0030: Gamma\n\n| a | b |\n|---|---|\n| 1 | 2 |\n",
	},
	{
		path = "rafts/R0040/R0040.md",
		front = {
			"id: R0040",
			"type: feature",
			"title: Delta",
			"single: true",
			"issues: [f0040]",
			"design: draft",
		},
		body = "# R0040: Delta\n",
	},
	{
		path = "rafts/R0050/R0050.md",
		front = {
			"id: R0050",
			"type: chore",
			"title: Epsilon",
			"single: true",
			"issues: [c0050]",
			"design: reviewed",
		},
		body = "# R0050: Epsilon\n",
	},
	{
		path = "issues/done/c0010/c0010.md",
		front = {
			"id: c0010",
			"type: chore",
			"title: First",
			"raft: R0010",
			"depends_on: []",
			"emergent: false",
			"design: ready",
		},
		body = "# c0010: First\n",
	},
	{
		path = "issues/active/f0020/f0020.md",
		front = {
			"id: f0020",
			"type: feature",
			"title: Second",
			"raft: R0020",
			"depends_on: [c0010, f0040]",
			"emergent: false",
			"design: ready",
		},
		body = "# f0020: Second\n",
	},
	{
		path = "issues/f0030/f0030.md",
		front = {
			"id: f0030",
			"type: feature",
			"title: Third",
			"raft: R0030",
			"depends_on: [f0020]",
			"emergent: false",
			"design: ready",
		},
		body = "# f0030: Third\n",
	},
	{
		path = "issues/f0031/f0031.md",
		front = {
			"id: f0031",
			"type: feature",
			"title: Third B",
			"raft: R0030",
			"depends_on: [f0099]",
			"emergent: false",
			"design: ready",
		},
		body = "# f0031: Third B\n\nMentions </script><script>alert(1)</script> literally.\n",
	},
	{
		path = "issues/f0040/f0040.md",
		front = {
			"id: f0040",
			"type: feature",
			"title: Fourth",
			"raft: R0040",
			"depends_on: [c0050]",
			"emergent: false",
			"design: draft",
		},
		body = "# f0040: Fourth\n",
	},
	{
		path = "issues/c0050/c0050.md",
		front = {
			"id: c0050",
			"type: chore",
			"title: Fifth",
			"raft: R0050",
			"depends_on: [c0010]",
			"emergent: false",
			"design: reviewed",
		},
		body = "# c0050: Fifth\n",
	},
	{
		path = "issues/f0060/f0060.md",
		front = {
			"id: f0060",
			"type: feature",
			"title: Loose",
			"raft: ",
			"depends_on: []",
			"emergent: false",
			"design: draft",
		},
		body = "# f0060: Loose\n",
	},
	{
		path = "issues/done/c0070/c0070.md",
		front = {
			"id: c0070",
			"type: chore",
			"title: Closed",
			"raft: ",
			"depends_on: []",
			"emergent: false",
			"design: draft",
		},
		body = "# c0070: Closed\n",
	},
	{
		path = "rafts/R0070/R0070.md",
		front = {
			"id: R0070",
			"type: feature",
			"title: Zeta",
			"single: true",
			"issues: [f0070]",
			"design: draft",
		},
		body = "# R0070: Zeta\n",
	},
	{
		path = "issues/f0070/f0070.md",
		front = {
			"id: f0070",
			"type: feature",
			"title: Waits",
			"raft: R0070",
			"depends_on: [f0060]",
			"emergent: false",
			"design: draft",
		},
		body = "# f0070: Waits\n",
	},
	{
		path = "issues/f0080/f0080.md",
		front = {
			"id: f0080",
			"type: feature",
			"title: Orphan",
			"raft: R0999",
			"depends_on: []",
			"emergent: false",
			"design: draft",
		},
		body = "# f0080: Orphan\n",
	},
}

local function dirname(path: string): string
	return string.match(path, "^(.*)/[^/]*$") or "."
end

function fixture.write(root: string, reverse: boolean?, skip: string?)
	if fs.isDir(root) then
		fs.removeDir(root)
	end
	local n = #fixture.FILES
	for i = 1, n do
		local f = fixture.FILES[if reverse then n + 1 - i else i]
		if skip and string.find(f.path, skip, 1, true) then
			continue
		end
		local path = `{root}/{f.path}`
		fs.writeDir(dirname(path))
		fs.writeFile(path, "---\n" .. table.concat(f.front, "\n") .. "\n---\n\n" .. f.body)
		-- an unrelated file in each item directory, as real items have check.sh
		fs.writeFile(`{dirname(path)}/check.sh`, "#!/usr/bin/env bash\n")
	end
end

local ROOT = ".cache/c0400-model/tracker"

local function byId(list: { any }): { [string]: any }
	local out = {}
	for _, v in list do
		out[v.id] = v
	end
	return out
end

local function ids(list: { any }): { string }
	local out = {}
	for _, v in list do
		table.insert(out, v.id)
	end
	return out
end

return t.spec("c0400 board model", function(it)
	fixture.write(ROOT)
	local m = board.collect(ROOT)
	local rafts = byId(m.rafts)
	local issues = byId(m.issues)

	it("lists rafts and issues, each sorted by id", function()
		t.expect(ids(m.rafts)).toEqual({ "R0010", "R0020", "R0030", "R0040", "R0050", "R0070" })
		t.expect(ids(m.issues))
			.toEqual({ "c0010", "c0050", "c0070", "f0020", "f0030", "f0031", "f0040", "f0060", "f0070", "f0080" })
	end)

	it("derives a status from the lifecycle directory and the design field", function()
		local want: { [string]: string } = {
			R0010 = "done",
			R0020 = "active",
			R0030 = "ready",
			R0040 = "draft",
			R0050 = "reviewed",
			R0070 = "draft",
		}
		for id, status in want do
			t.expect(rafts[id].status).toBe(status)
		end
		t.expect(issues.c0010.status).toBe("done")
		t.expect(issues.f0020.status).toBe("active")
		t.expect(issues.c0050.status).toBe("reviewed")
		t.expect(issues.f0060.status).toBe("draft")
	end)

	it("keeps each item's fields from its document", function()
		local r = rafts.R0030
		t.expect(r.kind).toBe("raft")
		t.expect(r.type).toBe("feature")
		t.expect(r.title).toBe("Gamma")
		t.expect(r.state).toBe("backlog")
		t.expect(r.design).toBe("ready")
		t.expect(r.single).toBe(false)
		t.expect(r.issues).toEqual({ "f0030", "f0031" })
		local i = issues.f0031
		t.expect(i.kind).toBe("issue")
		t.expect(i.raft).toBe("R0030")
		t.expect(i.dependsOn).toEqual({ "f0099" })
		t.expect(i.emergent).toBe(false)
		t.expect(issues.f0060.raft).toBe(nil)
		t.expect(issues.f0080.raft).toBe(nil) -- names R0999, which does not exist
		t.expect(issues.f0040.type).toBe("feature")
	end)

	it("keeps the markdown body without its frontmatter", function()
		t.expect(rafts.R0030.body).toBe("# R0030: Gamma\n\n| a | b |\n|---|---|\n| 1 | 2 |\n")
		t.expect(issues.c0010.body).toBe("# c0010: First\n")
	end)

	it("derives raft dependencies from member issues' depends_on, and their reverse", function()
		t.expect(rafts.R0010.dependsOn).toEqual({})
		t.expect(rafts.R0020.dependsOn).toEqual({ "R0010", "R0040" })
		t.expect(rafts.R0030.dependsOn).toEqual({ "R0020" }) -- f0099 does not exist: ignored
		t.expect(rafts.R0040.dependsOn).toEqual({ "R0050" })
		t.expect(rafts.R0050.dependsOn).toEqual({ "R0010" })
		t.expect(rafts.R0070.dependsOn).toEqual({}) -- its dependency f0060 has no raft
		t.expect(rafts.R0010.dependents).toEqual({ "R0020", "R0050" })
		t.expect(rafts.R0020.dependents).toEqual({ "R0030" })
		t.expect(rafts.R0050.dependents).toEqual({ "R0040" })
		t.expect(rafts.R0040.dependents).toEqual({ "R0020" })
		t.expect(rafts.R0030.dependents).toEqual({})
	end)

	it("blockedBy lists unfinished dependencies: rafts, and issues that have no raft", function()
		t.expect(rafts.R0010.blockedBy).toEqual({})
		t.expect(rafts.R0020.blockedBy).toEqual({ "R0040" }) -- R0010 is done
		t.expect(rafts.R0030.blockedBy).toEqual({ "R0020" })
		t.expect(rafts.R0040.blockedBy).toEqual({ "R0050" })
		t.expect(rafts.R0050.blockedBy).toEqual({})
		t.expect(rafts.R0070.blockedBy).toEqual({ "f0060" })
	end)

	it("a raft is top level when nothing blocks it", function()
		t.expect(rafts.R0010.topLevel).toBe(true)
		t.expect(rafts.R0020.topLevel).toBe(false)
		t.expect(rafts.R0030.topLevel).toBe(false)
		t.expect(rafts.R0040.topLevel).toBe(false)
		t.expect(rafts.R0050.topLevel).toBe(true)
		t.expect(rafts.R0070.topLevel).toBe(false)
	end)

	it("splits Rafts and Issues into Ready, Not ready and Done", function()
		t.expect(m.views.rafts.ready).toEqual({ "R0020", "R0030" })
		t.expect(m.views.rafts["not"]).toEqual({ "R0040", "R0050", "R0070" })
		t.expect(m.views.rafts.done).toEqual({ "R0010" })
		t.expect(m.views.issues.ready).toEqual({ "f0020", "f0030", "f0031" })
		t.expect(m.views.issues["not"]).toEqual({ "c0050", "f0040", "f0060", "f0070", "f0080" })
		t.expect(m.views.issues.done).toEqual({ "c0010", "c0070" })
		t.expect(m.initialView).toBe("rafts")
		t.expect(rafts.R0020.command).toBe("/z-run R0020")
		t.expect(rafts.R0030.command).toBe("/z-ready R0030")
		t.expect(rafts.R0040.command).toBe(nil)
		t.expect(rafts.R0050.command).toBe(nil)
		t.expect(issues.f0060.command).toBe("/z-design f0060")
		t.expect(issues.f0080.command).toBe("/z-design f0080")
		t.expect(issues.f0060.dependents).toEqual({ "R0070" })
		t.expect(issues.c0070.dependents).toEqual({})
		for _, id in ids(m.rafts) do
			t.expect((string.find(id, "none:", 1, true))).toBe(nil)
		end
	end)

	it("opens on Rafts even when nothing is active", function()
		t.expect(m.initialView).toBe("rafts")
		fixture.write(ROOT .. "-noactive", false, "/active/")
		local quiet = board.collect(ROOT .. "-noactive")
		fs.removeDir(ROOT .. "-noactive")
		t.expect(quiet.initialView).toBe("rafts")
		t.expect(quiet.views.rafts.ready).toEqual({ "R0030" })
	end)

	it("maps every raft and issue id to itself", function()
		t.expect(m.home).toEqual({
			R0010 = "R0010",
			R0020 = "R0020",
			R0030 = "R0030",
			R0040 = "R0040",
			R0050 = "R0050",
			R0070 = "R0070",
			c0010 = "c0010",
			f0020 = "f0020",
			f0030 = "f0030",
			f0031 = "f0031",
			f0040 = "f0040",
			c0050 = "c0050",
			f0060 = "f0060",
			f0070 = "f0070",
			f0080 = "f0080",
			c0070 = "c0070",
		})
	end)

	fs.removeDir(".cache/c0400-model")
end)
