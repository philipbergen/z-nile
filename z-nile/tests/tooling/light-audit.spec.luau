--!strict
-- f0420 step 3 (review 003 F4): audit reports `light:` on a raft that is not `single: true`, and any value but true.
-- Plain folders under .cache/light-audit; no git.
local audit = require("@znile/engine/audit")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local base = ".cache/light-audit"

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
local function lights(dir: string): { string }
	local out: { string } = {}
	for _, p in audit.run(dir) do
		if p.code == "light" then
			t.expect(p.level).toBe("error")
			table.insert(out, `{p.path}: {p.message}`)
		end
	end
	return out
end

return t.spec("f0420: audit checks light:", function(it)
	it("light: true on a single raft, and no light: at all, are clean", function()
		local found = lights(tree("clean", {
			["z-nile/.tracker/rafts/R0047"] = doc("R0047", "single: true\nlight: true\nissues: []\n"),
			["z-nile/.tracker/rafts/R0048"] = doc("R0048", "single: false\nissues: []\n"),
		}))
		t.expect(#found).toBe(0)
	end)

	it("light: true on a raft that is not single: true is an error naming the document", function()
		local found = lights(tree("multi", {
			["z-nile/.tracker/rafts/R0047"] = doc("R0047", "single: false\nlight: true\nissues: []\n"),
			["z-nile/.tracker/rafts/R0049"] = doc("R0049", "light: true\nissues: []\n"),
		}))
		t.expect(#found).toBe(2)
		t.expect(found[1])
			.toBe("z-nile/.tracker/rafts/R0047: R0047.md says light: true but is not single: true")
		t.expect(found[2])
			.toBe("z-nile/.tracker/rafts/R0049: R0049.md says light: true but is not single: true")
	end)

	it("a light: that is not true is an error", function()
		local found = lights(tree("value", {
			["z-nile/.tracker/rafts/R0047"] = doc("R0047", "single: true\nlight: yes\nissues: []\n"),
		}))
		t.expect(#found).toBe(1)
		t.expect(found[1]).toBe("z-nile/.tracker/rafts/R0047: R0047.md: light: is true or absent, not yes")
	end)

	it(
		"N3: light: true on a single raft whose one ticket is not risk: easy is a warning naming both",
		function()
			local dir = tree("risk", {
				["z-nile/.tracker/rafts/R0047"] = doc(
					"R0047",
					"single: true\nlight: true\nissues: [c0127]\n"
				),
				["z-nile/.tracker/issues/active/c0127"] = doc("c0127", "raft: R0047\nrisk: normal\n"),
				["z-nile/.tracker/rafts/R0048"] = doc(
					"R0048",
					"single: true\nlight: true\nissues: [c0128]\n"
				),
				["z-nile/.tracker/issues/active/c0128"] = doc("c0128", "raft: R0048\nrisk: easy\n"),
			})
			local found: { string } = {}
			for _, p in audit.run(dir) do
				if p.code == "light" then
					t.expect(p.level).toBe("warning")
					table.insert(found, `{p.path}: {p.message}`)
				end
			end
			t.expect(#found).toBe(1)
			t.expect(found[1]).toBe(
				"z-nile/.tracker/rafts/R0047: R0047.md says light: true but its ticket c0127 has risk: normal, not easy"
			)
		end
	)
end)
