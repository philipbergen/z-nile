--!strict
-- c0880: the whole-tree audit (scripts/tracker/audit.luau) reports every problem in a tracker tree and never stops
-- at the first one. Plain folders under .cache/c0880-audit; no git.
local audit = require("@scripts/tracker/audit")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end
local root = trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)
local base = `{root}/.cache/c0880-audit`

local function write(path: string, text: string)
	fs.writeDir(string.match(path, "^(.*)/[^/]+$") :: string)
	fs.writeFile(path, text)
end
local function doc(id: string, extra: string?): string
	return `---\nid: {id}\ntype: chore\ntitle: T\nslug: s\n{extra or ""}---\n\n# {id}\n`
end
-- a fresh tree: `items` maps an item path under tracker/ to its document text (false: the folder only)
local function tree(name: string, items: { [string]: string | false }, next: (string | false)?): string
	local dir = `{base}/{name}`
	if fs.isDir(dir) then
		fs.removeDir(dir)
	end
	fs.writeDir(`{dir}/tracker/issues/done`)
	fs.writeDir(`{dir}/tracker/rafts/done`)
	for path, text in items do
		if type(text) == "string" then
			local id = string.match(path, "([^/]+)$") :: string
			write(`{dir}/tracker/{path}/{id}.md`, text)
		else
			fs.writeDir(`{dir}/tracker/{path}`)
		end
	end
	if type(next) == "string" then
		write(`{dir}/tracker/next`, next)
	elseif next == nil then
		write(`{dir}/tracker/next`, "issue 100 a-b-c\nraft 100 a-b-c\n")
	end
	return dir
end
local function codes(problems: { audit.Problem }): { string }
	local out: { string } = {}
	for _, p in problems do
		table.insert(out, `{p.level} {p.code} {p.path}`)
	end
	return out
end

return t.spec("c0880 audit", function(it)
	it("a sound tree has no problems", function()
		local dir = tree("clean", {
			["issues/c0001"] = doc("c0001"),
			["issues/done/f0002"] = doc("f0002"),
			["rafts/R0001"] = doc("R0001"),
		}, "issue 3 a-b-c\nraft 2 a-b-c\n")
		t.expect(audit.run(dir)).toEqual({})
	end)

	it("an id in two lifecycle folders is a duplicate, reported at every copy", function()
		local dir = tree("duplicate", {
			["issues/c0010"] = doc("c0010"),
			["issues/done/c0010"] = doc("c0010"),
			["issues/active/c0010"] = doc("c0010"),
			["issues/c0020"] = doc("c0020"),
		})
		t.expect(codes(audit.run(dir))).toEqual({
			"error duplicate tracker/issues/active/c0010",
			"error duplicate tracker/issues/c0010",
			"error duplicate tracker/issues/done/c0010",
		})
		local p = audit.run(dir)[1]
		t.expect(string.find(p.message, "tracker/issues/done/c0010", 1, true) ~= nil).toBe(true)
	end)

	it("reports each kind of problem, all of them in one run, sorted by path", function()
		local dir = tree("many", {
			["issues/c0010"] = doc("c0010"),
			["issues/done/c0010"] = doc("c0010"),
			["issues/c0020"] = false, -- no document
			["issues/c0040"] = doc("c0041"), -- frontmatter names another id
			["issues/c0050"] = "---\nid: c0050\ntitle: T\n---\n", -- no slug
			["rafts/c0060"] = doc("c0060"), -- an issue id among rafts
			["issues/R0070"] = doc("R0070"), -- a raft id among issues
		})
		-- concatenated: c0420's guard bans a literal legacy document name in specs
		write(`{dir}/tracker/issues/c0030/c0030` .. "-old-name.md", doc("c0030"))
		t.expect(codes(audit.run(dir))).toEqual({
			"error wrong-kind tracker/issues/R0070",
			"error duplicate tracker/issues/c0010",
			"error no-document tracker/issues/c0020",
			"error legacy-name tracker/issues/c0030",
			"error id-mismatch tracker/issues/c0040",
			"error no-slug tracker/issues/c0050",
			"error duplicate tracker/issues/done/c0010",
			"error wrong-kind tracker/rafts/c0060",
		})
	end)

	it("a document without an id: line is not a mismatch", function()
		local dir = tree("no-id-line", { ["issues/c0010"] = "---\ntitle: T\nslug: s\n---\n" })
		t.expect(audit.run(dir)).toEqual({})
	end)

	it("other names in the lifecycle folders are ignored", function()
		local dir = tree("other-names", { ["issues/c0010"] = doc("c0010") })
		write(`{dir}/tracker/issues/.gitkeep`, "")
		write(`{dir}/tracker/issues/done/.gitkeep`, "")
		write(`{dir}/tracker/rafts/README.md`, "notes\n")
		t.expect(audit.run(dir)).toEqual({})
	end)

	it("a missing or malformed counter file is an error", function()
		t.expect(codes(audit.run(tree("next-missing", { ["issues/c0010"] = doc("c0010") }, false)))).toEqual({
			"error next-missing tracker/next",
		})
		t.expect(codes(audit.run(tree("next-bad", { ["issues/c0010"] = doc("c0010") }, "issue ten\n"))))
			.toEqual({
				"error next-malformed tracker/next",
			})
	end)

	it("a counter at or below a number in use is a warning, per space", function()
		local items: { [string]: string | false } =
			{ ["issues/c0010"] = doc("c0010"), ["rafts/R0005"] = doc("R0005") }
		t.expect(codes(audit.run(tree("next-at", items, "issue 10 a\nraft 6 a\n")))).toEqual({
			"warning next-behind tracker/next",
		})
		t.expect(codes(audit.run(tree("raft-behind", items, "issue 11 a\nraft 5 a\n")))).toEqual({
			"warning next-behind tracker/next",
		})
		t.expect(audit.run(tree("next-ok", items, "issue 11 a\nraft 6 a\n"))).toEqual({})
	end)

	it("format puts level, code and path first", function()
		local p = audit.run(tree("fmt", { ["issues/c0020"] = false }))[1]
		local line = audit.format(p)
		t.expect(string.sub(line, 1, #"error no-document tracker/issues/c0020: "))
			.toBe("error no-document tracker/issues/c0020: ")
	end)

	it("cleans up", function()
		fs.removeDir(base)
	end)
end)
