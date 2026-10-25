--!strict
-- `tracker.sh migrate` on odd legacy documents (review 001 F3): one with no frontmatter is reported and
-- left alone (exit 1), and an empty `slug:` line is filled from the old filename. Run in a temporary
-- directory outside the repo: migrate needs only the tracker tree.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end

local root = trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)
-- outside any repository: inside one, the main-checkout guard (CI is one) would refuse to run migrate
local base = trim(process.exec("mktemp", { "-d" }).stdout)
-- the tool shim finds lune through a manifest in the working directory or above it
fs.writeFile(`{base}/rokit.toml`, fs.readFile(`{root}/rokit.toml`))
fs.writeDir(`{base}/z-nile`) -- c0114: a tree without the registry refuses
fs.writeFile(`{base}/z-nile/projects.toml`, fs.readFile(`{root}/z-nile/projects.toml`))

-- the game's root (c0120: tracker/ is retired; pickman's items are in pickman/.tracker)
local R = "pickman/.tracker"

-- legacy document names are built from parts: the guard spec rejects literal ones
local function legacy(id: string, slug: string): string
	return `{R}/issues/{id}/{id}-{slug}.md`
end

local function migrate(): process.ExecResult
	return process.exec("lune", { "run", `{root}/z-nile/engine/main`, "--", "migrate" }, { cwd = base })
end

local function write(path: string, text: string)
	local parent = string.match(path, "^(.*)/[^/]+$")
	if parent then
		fs.writeDir(`{base}/{parent}`)
	end
	fs.writeFile(`{base}/{path}`, text)
end

return t.spec("migrate on odd documents", function(it)
	it("a document without frontmatter is reported and left alone; the others still convert", function()
		write(legacy("f0010", "bare"), "just text, no frontmatter\n")
		write(legacy("f0020", "fine"), "---\nid: f0020\ntitle: Fine\n---\n\nbody\n")
		local r = migrate()
		t.expect(r.ok).toBe(false)
		t.expect(r.code).toBe(1)
		t.expect(string.find(r.stderr, `{legacy("f0010", "bare")}: no frontmatter`, 1, true) ~= nil)
			.toBe(true)
		t.expect(fs.isFile(`{base}/{legacy("f0010", "bare")}`)).toBe(true) -- untouched
		t.expect(fs.isFile(`{base}/{R}/issues/f0010/f0010.md`)).toBe(false)
		t.expect(fs.isFile(`{base}/{R}/issues/f0020/f0020.md`)).toBe(true)
		t.expect(
			string.find(fs.readFile(`{base}/{R}/issues/f0020/f0020.md`), "\nslug: fine\n", 1, true) ~= nil
		)
			.toBe(true)
	end)

	it("an empty slug line is filled from the old filename", function()
		fs.removeDir(`{base}/{R}`)
		write(legacy("f0030", "filled"), "---\nid: f0030\ntitle: Filled\nslug:\n---\n\nbody\n")
		local r = migrate()
		t.expect(r.ok).toBe(true)
		local doc = fs.readFile(`{base}/{R}/issues/f0030/f0030.md`)
		t.expect(string.find(doc, "\nslug: filled\n", 1, true) ~= nil).toBe(true)
		t.expect((string.find(doc, "\nslug:\n", 1, true))).toBe(nil)
		fs.removeDir(base)
	end)
end)
