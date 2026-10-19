--!strict
-- c0107 AC2: a raft's shown type comes from its issues, and the row colors are not the type colors.
local board = require("@scripts/tracker/board")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

local ROOT = ".cache/c0107-label"

local function dirname(path: string): string
	return string.match(path, "^(.*)/[^/]*$") or "."
end

local function write(path: string, front: { string }, body: string)
	fs.writeDir(`{ROOT}/{dirname(path)}`)
	fs.writeFile(`{ROOT}/{path}`, "---\n" .. table.concat(front, "\n") .. "\n---\n\n" .. body)
end

local function byId(list: { any }): { [string]: any }
	local out: { [string]: any } = {}
	for _, item in list do
		out[item.id] = item
	end
	return out
end

return t.spec("c0107 board labels", function(it)
	if fs.isDir(ROOT) then
		fs.removeDir(ROOT)
	end
	write("rafts/R9201/R9201.md", {
		"id: R9201",
		"type: feature",
		"title: Mixed",
		"issues: [f9201, c9201]",
		"design: draft",
	}, "# R9201: Mixed\n")
	write("rafts/R9202/R9202.md", {
		"id: R9202",
		"type: feature",
		"title: Two defects",
		"issues: [d9202, d9203]",
		"design: draft",
	}, "# R9202: Two defects\n")
	write("rafts/R9203/R9203.md", {
		"id: R9203",
		"type: chore",
		"title: Empty",
		"issues: []",
		"design: draft",
	}, "# R9203: Empty\n")
	write("rafts/R9204/R9204.md", {
		"id: R9204",
		"type: feature",
		"title: One real type",
		"issues: [f9204, f9205]",
		"design: draft",
	}, "# R9204: One real type\n")
	write("issues/f9201/f9201.md", {
		"id: f9201",
		"type: feature",
		"title: Feature",
		"raft: R9201",
		"depends_on: []",
		"design: draft",
	}, "# f9201: Feature\n")
	write("issues/c9201/c9201.md", {
		"id: c9201",
		"type: chore",
		"title: Chore",
		"raft: R9201",
		"depends_on: []",
		"design: draft",
	}, "# c9201: Chore\n")
	write("issues/d9202/d9202.md", {
		"id: d9202",
		"type: defect",
		"title: Defect A",
		"raft: R9202",
		"depends_on: []",
		"design: draft",
	}, "# d9202: Defect A\n")
	write("issues/d9203/d9203.md", {
		"id: d9203",
		"type: defect",
		"title: Defect B",
		"raft: R9202",
		"depends_on: []",
		"design: draft",
	}, "# d9203: Defect B\n")
	write("issues/f9204/f9204.md", {
		"id: f9204",
		"type: feature",
		"title: Typed",
		"raft: R9204",
		"depends_on: []",
		"design: draft",
	}, "# f9204: Typed\n")
	write("issues/f9205/f9205.md", {
		"id: f9205",
		"type:",
		"title: Blank",
		"raft: R9204",
		"depends_on: []",
		"design: draft",
	}, "# f9205: Blank\n")

	local m = board.collect(ROOT) :: any
	local rafts = byId(m.rafts)

	it("shows mix when the issues differ, and keeps the raft's own type field", function()
		t.expect(rafts.R9201.label).toBe("mix")
		t.expect(rafts.R9201.type).toBe("feature")
	end)

	it("shows the issues' type when they agree, even if the raft document says otherwise", function()
		t.expect(rafts.R9202.label).toBe("defect")
		t.expect(rafts.R9202.type).toBe("feature")
	end)

	it("uses the raft document type when no issue has a type", function()
		t.expect(rafts.R9203.label).toBe("chore")
		t.expect(rafts.R9204.label).toBe("feature")
	end)

	it("colors the readiness bar and the type word with different rules", function()
		local html = board.render(m, fs.readFile(board.MARKED_PATH))
		for _, rule in
			{
				"#list li.row.ready { box-shadow: inset 4px 0 #22c55e; }",
				"#list li.row.not { box-shadow: inset 4px 0 #f59e0b; }",
				"#list li.row.done { box-shadow: inset 4px 0 #9ca3af; }",
				".t-feature { color: var(--ser-feature); }",
				".t-defect { color: var(--ser-defect); }",
				".t-chore { color: var(--ser-chore); }",
				".t-mix { color: #7c3aed; }",
			}
		do
			t.expect(string.find(html, rule, 1, true) ~= nil).toBe(true)
		end
	end)

	fs.removeDir(ROOT)
end)
