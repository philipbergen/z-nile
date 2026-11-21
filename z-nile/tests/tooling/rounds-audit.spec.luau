--!strict
-- f0421 AC7: audit reports a risk: that is not easy, normal or risky on an issue, and any risk: on a raft.
-- Plain folders under .cache/rounds-audit; no git.
local audit = require("@znile/engine/audit")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local base = ".cache/rounds-audit"

local function doc(id: string, extra: string): string
	return `---\nid: {id}\ntype: chore\ntitle: T\nslug: s\n{extra}---\n\n# {id}\n`
end
local function write(path: string, text: string)
	fs.writeDir(string.match(path, "^(.*)/[^/]+$") :: string)
	fs.writeFile(path, text)
end
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
local function risks(dir: string): { string }
	local out: { string } = {}
	for _, p in audit.run(dir) do
		if p.code == "risk" then
			t.expect(p.level).toBe("error")
			table.insert(out, `{p.path}: {p.message}`)
		end
	end
	return out
end

return t.spec("f0421: audit checks risk:", function(it)
	it("an issue whose risk: is not easy, normal or risky is an error naming the document", function()
		local found = risks(tree("bad", {
			["z-nile/.tracker/issues/c0127"] = doc("c0127", "risk: high\n"),
		}))
		t.expect(#found).toBe(1)
		t.expect(found[1]).toBe("z-nile/.tracker/issues/c0127: c0127.md: risk is high: easy, normal or risky")
	end)

	it("easy, normal, risky and an absent or empty risk: are clean", function()
		local found = risks(tree("good", {
			["z-nile/.tracker/issues/c0127"] = doc("c0127", "risk: easy\n"),
			["z-nile/.tracker/issues/c0128"] = doc("c0128", "risk: normal\n"),
			["z-nile/.tracker/issues/c0129"] = doc("c0129", "risk: risky\n"),
			["z-nile/.tracker/issues/c0130"] = doc("c0130", "risk: \n"),
			["z-nile/.tracker/issues/c0131"] = doc("c0131", ""),
		}))
		t.expect(#found).toBe(0)
	end)

	it("a raft document that carries risk: is an error", function()
		local found = risks(tree("raft", {
			["z-nile/.tracker/rafts/R0047"] = doc("R0047", "risk: easy\nissues: []\n"),
			["z-nile/.tracker/rafts/R0048"] = doc("R0048", "issues: []\n"),
		}))
		t.expect(#found).toBe(1)
		t.expect(found[1])
			.toBe("z-nile/.tracker/rafts/R0047: R0047.md: a raft's risk is its members' highest")
	end)
end)
