--!strict
-- c0400 AC2: the page is one self-contained, byte-stable HTML file: the vendored marked is inlined,
-- nothing is loaded from elsewhere, and the model is embedded as escaped JSON that decodes back.
local board = require("@scripts/tracker/board")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")
-- c0120 override: specs run from their project's home (z-nile/); the vendored marked is read from the checkout's top
local TOP = (
	string.gsub(require("@lune/process").exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", "")
)

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

function fixture.write(root: string, reverse: boolean?)
	if fs.isDir(root) then
		fs.removeDir(root)
	end
	local n = #fixture.FILES
	for i = 1, n do
		local f = fixture.FILES[if reverse then n + 1 - i else i]
		local path = `{root}/{f.path}`
		fs.writeDir(dirname(path))
		fs.writeFile(path, "---\n" .. table.concat(f.front, "\n") .. "\n---\n\n" .. f.body)
		-- an unrelated file in each item directory, as real items have check.sh
		fs.writeFile(`{dirname(path)}/check.sh`, "#!/usr/bin/env bash\n")
	end
end

local A = ".cache/c0400-page-a/tracker"
local B = ".cache/c0400-page-b/somewhere/else/tracker"

local function count(s: string, needle: string): number
	local n, i = 0, 1
	while true do
		local at = string.find(s, needle, i, true)
		if not at then
			return n
		end
		n += 1
		i = at + #needle
	end
end

-- the text between <script type="application/json" id="board-data"> and the next </script>
local function dataOf(html: string): string
	local open = '<script type="application/json" id="board-data">'
	local s = string.find(html, open, 1, true)
	t.expect(s ~= nil).toBe(true)
	local from = (s :: number) + #open
	local e = string.find(html, "</script>", from, true)
	return string.sub(html, from, (e :: number) - 1)
end

return t.spec("c0400 board page", function(it)
	fixture.write(A)
	fixture.write(B, true)
	-- c0120 override: the spec runs from its home: the checkout's files are read from the top
	local marked = fs.readFile(`{TOP}/{board.MARKED_PATH}`)
	local mA = board.collect(A)
	local htmlA = board.render(mA, marked)
	local htmlA2 = board.render(board.collect(A), marked)
	local htmlB = board.render(board.collect(B), marked)
	fs.removeDir(".cache/c0400-page-a")
	fs.removeDir(".cache/c0400-page-b")

	it(
		"regenerating from the same data gives the same bytes, wherever the tree is and whatever order it was written in",
		function()
			t.expect(htmlA2 == htmlA).toBe(true)
			t.expect(htmlB == htmlA).toBe(true)
			t.expect((string.find(htmlA, "c0400-page", 1, true))).toBe(nil) -- no paths leak into the page
		end
	)

	it(
		"is a full HTML document with the vendored marked inlined, and loads nothing from elsewhere",
		function()
			t.expect(string.sub(htmlA, 1, 15)).toBe("<!DOCTYPE html>")
			t.expect(string.find(htmlA, '<meta charset="utf-8">', 1, true) ~= nil).toBe(true)
			t.expect(count(htmlA, board.inlineMarked(marked))).toBe(1)
			t.expect((string.find(htmlA, "sourceMappingURL", 1, true))).toBe(nil)
			t.expect((string.find(htmlA, "<script src", 1, true))).toBe(nil)
			t.expect((string.find(htmlA, "<link", 1, true))).toBe(nil)
			t.expect((string.find(htmlA, "@import", 1, true))).toBe(nil)
			for _, attr in { 'src="http', "src='http", 'href="http', "href='http", 'src="//', 'href="//' } do
				t.expect((string.find(htmlA, attr, 1, true))).toBe(nil)
			end
		end
	)

	it("embeds the model as JSON that decodes back to it exactly", function()
		local data = dataOf(htmlA)
		t.expect(serde.decode("json", data)).toEqual(serde.decode("json", serde.encode("json", mA)))
	end)

	it("inlineMarked drops only marked's trailing source-map comment", function()
		local inlined = board.inlineMarked(marked)
		t.expect((string.find(inlined, "sourceMappingURL", 1, true))).toBe(nil)
		t.expect(string.find(inlined, "marked v18.0.14", 1, true) ~= nil).toBe(true)
		t.expect(#marked - #inlined < 100).toBe(true)
		t.expect(board.inlineMarked("a\n//# sourceMappingURL=x.map\n")).toBe("a\n")
	end)

	it("writes empty lists as JSON arrays, never {}", function()
		-- the page iterates lists with forEach; an empty object would throw in the browser
		local data = dataOf(htmlA)
		t.expect(string.find(data, '"dependsOn":[]', 1, true) ~= nil).toBe(true)
		t.expect(string.find(data, '"dependents":[]', 1, true) ~= nil).toBe(true)
		t.expect((string.find(data, ":{}", 1, true))).toBe(nil)
		t.expect(board.encode({})).toBe("[]")
		t.expect(board.encode({ b = {}, a = { 1, 2 }, c = "x<y" })).toBe('{"a":[1,2],"b":[],"c":"x\\u003cy"}')
	end)

	it("escapes < in the embedded data, so markdown can never close the script tag", function()
		local data = dataOf(htmlA)
		t.expect((string.find(data, "<", 1, true))).toBe(nil)
		t.expect((string.find(htmlA, "<script>alert(1)", 1, true))).toBe(nil)
		local decoded = serde.decode("json", data)
		local body: string? = nil
		for _, i in decoded.issues do
			if i.id == "f0031" then
				body = i.body
			end
		end
		t.expect(body).toBe("# f0031: Third B\n\nMentions </script><script>alert(1)</script> literally.\n")
	end)

	it("has Rafts and Issues, and the search field the page is driven by", function()
		for _, id in { 'id="tab-rafts"', 'id="tab-issues"', 'id="search"', 'id="list"', 'id="pane"' } do
			t.expect(string.find(htmlA, id, 1, true) ~= nil).toBe(true)
		end
		for _, id in { 'id="tab-active"', 'id="tab-waiting"', 'id="tab-done"' } do
			t.expect((string.find(htmlA, id, 1, true))).toBe(nil)
		end
	end)
end)
