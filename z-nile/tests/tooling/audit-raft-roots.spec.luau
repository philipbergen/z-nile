--!strict
-- c0114 (R0043 code review 006): `audit` reports an unfinished raft whose member sits in another project root, as
-- `new raft` refuses to make one. Such a raft arrives by merge (every capture does while c0114's branch waits to land),
-- so audit is what catches it. Membership is read both ways: the raft's `issues:` and the issue's `raft:`. A finished
-- raft spanning two roots is clean: R0001 does by decision. Plain folders under .cache/audit-raft-roots; no git.
local audit = require("@znile/engine/audit")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

-- c0120: the spec runs from z-nile/; the registry is read at the checkout's top, and pickman's root is pickman/.tracker
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local base = ".cache/audit-raft-roots"

local function doc(id: string, extra: string): string
	return `---\nid: {id}\ntype: chore\ntitle: T\nslug: s\n{extra}---\n\n# {id}\n`
end
local function write(path: string, text: string)
	fs.writeDir(string.match(path, "^(.*)/[^/]+$") :: string)
	fs.writeFile(path, text)
end
-- a tree with the registry, the counter and `items` (path under the checkout -> document)
local function tree(name: string, items: { [string]: string }): string
	local dir = `{base}/{name}`
	if fs.isDir(dir) then
		fs.removeDir(dir)
	end
	write(`{dir}/z-nile/projects.toml`, fs.readFile(`{TOP}/z-nile/projects.toml`))
	write(`{dir}/z-nile/next`, "issue 100 a-b-c\nraft 100 a-b-c\n")
	for path, text in items do
		local id = string.match(path, "([^/]+)$") :: string
		write(`{dir}/{path}/{id}.md`, text)
	end
	return dir
end
local function spans(dir: string): { string }
	local out: { string } = {}
	for _, p in audit.run(dir) do
		if p.code == "raft-spans-projects" then
			t.expect(p.level).toBe("error")
			table.insert(out, `{p.path}: {p.message}`)
		end
	end
	return out
end

return t.spec("audit: a raft lives in its members' project", function(it)
	it("an unfinished pickman raft listing a z-nile issue is an error", function()
		local dir = tree("listed", {
			["pickman/.tracker/rafts/R0047"] = doc("R0047", "issues: [c0127]\n"),
			["z-nile/.tracker/issues/c0127"] = doc("c0127", "raft: \n"),
		})
		local found = spans(dir)
		t.expect(#found).toBe(1)
		t.expect(
			string.find(
				found[1],
				"pickman/.tracker/rafts/R0047: c0127 is in z-nile/.tracker, not pickman/.tracker",
				1,
				true
			) ~= nil
		).toBe(true)
	end)

	it("the same with the link only in the issue's raft: field is an error", function()
		local dir = tree("linked", {
			["pickman/.tracker/rafts/active/R0047"] = doc("R0047", "issues: []\n"),
			["z-nile/.tracker/issues/active/c0127"] = doc("c0127", "raft: R0047\n"),
		})
		t.expect(#spans(dir)).toBe(1)
	end)

	it("a raft in its members' root is clean", function()
		local dir = tree("same", {
			["z-nile/.tracker/rafts/R0047"] = doc("R0047", "issues: [c0127]\n"),
			["z-nile/.tracker/issues/c0127"] = doc("c0127", "raft: R0047\n"),
		})
		t.expect(#spans(dir)).toBe(0)
	end)

	it("a finished raft spanning two roots is clean (R0001's shape)", function()
		local dir = tree("done", {
			["pickman/.tracker/rafts/done/R0001"] = doc("R0001", "issues: [c0001, c0002]\n"),
			["z-nile/.tracker/issues/done/c0001"] = doc("c0001", "raft: R0001\n"),
			["pickman/.tracker/issues/done/c0002"] = doc("c0002", "raft: R0001\n"),
		})
		t.expect(#spans(dir)).toBe(0)
		fs.removeDir(base)
	end)
end)
