--!strict
-- c0120 AC10: after the move the old places stay empty, and the gate fails if they fill again. tracker/ is a retired
-- root: `./zn audit` reports any tracked file there but the counter's tombstone (`old-root`), and a promoted-spec
-- folder outside its item's project's home (`misplaced-spec`), such as a pickman item's specs promoted into z-nile's
-- tests/acceptance. No tests/ is left at the root (the root belongs to no project, decided with the user, 2026-10-21),
-- and none of pickman's old places. This spec runs in z-nile's gate once promoted, so a resurrection is red there.
-- It runs from z-nile/: the repository is read from its top. Fixture under .cache/c0120-oldroots (this home's).
local audit = require("@znile/engine/audit")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local projects = require("@znile/engine/projects")
local t = require("@tests/lib/t")

-- a promoted-spec path in two parts, so a compaction never rewrites this spec's own test data
local ACC = "tests/" .. "acceptance/"

local root = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local base = `{root}/.cache/c0120-oldroots`
local REGISTRY = 'retired = ["tracker"]\n\n[[project]]\nname = "pickman"\nroot = "pickman/.tracker"\n\n'
	.. '[[project]]\nname = "z-nile"\nroot = "z-nile/.tracker"\n'
-- the old places at the root: none may come back (the root's tests/ as a whole, and pickman's)
local OLD_GAME = {
	"tests",
	"src",
	"default.project.json",
	"lobby.project.json",
	"tests/unit",
	"tests/contract",
	"tests/integration",
	"tests/scenario",
	"tests/place",
	"tests/runtime",
	"tests/fixtures/sim",
	"tests/lib/place.luau",
	"tests/lib/sim.luau",
	"tests/lib/fakeengine.luau",
	"scripts/deploy-beta.luau",
	"scripts/runtime-test.luau",
	"scripts/lib/beta.luau",
	"scripts/lib/opencloud.luau",
}

local function write(rel: string, text: string)
	local path = `{base}/{rel}`
	fs.writeDir(string.match(path, "^(.*)/[^/]+$") :: string)
	fs.writeFile(path, text)
end
local function codes(problems: { audit.Problem }): { string }
	local out: { string } = {}
	for _, p in problems do
		if p.code == "old-root" or p.code == "misplaced-spec" then
			table.insert(out, `{p.level} {p.code} {p.path}`)
		end
	end
	table.sort(out)
	return out
end

return t.spec("c0120 the old places stay empty", function(it)
	it("the repository: nothing but the tombstone under tracker/, every promoted spec in its project's home", function()
		local reg = projects.load(TOP)
		t.expect(reg.retired).toEqual({ "tracker" })
		t.expect(codes(audit.leftovers(TOP, audit.scan(TOP), reg))).toEqual({})
		local r = process.exec("git", { "ls-files", "--", "tracker" }, { cwd = TOP })
		t.expect(r.stdout).toBe("tracker/next\n")
	end)

	it("the repository: no tests/ at the root, and none of pickman's old places", function()
		local back: { string } = {}
		for _, p in OLD_GAME do
			local r = process.exec("git", { "ls-files", "--", p }, { cwd = TOP })
			if string.match(r.stdout, "%S") then
				table.insert(back, p)
			end
		end
		t.expect(table.concat(back, ", ")).toBe("")
	end)

	it("./zn audit is clean of both", function()
		local r = process.exec("bash", { "zn", "audit" }, { cwd = TOP })
		t.expect((string.find(r.stdout, "old-root", 1, true))).toBe(nil)
		t.expect((string.find(r.stdout, "misplaced-spec", 1, true))).toBe(nil)
	end)

	it("audit reports a file under the retired root, but never the tombstone", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		write("z-nile/projects.toml", REGISTRY)
		write("tracker/next", "moved to z-nile/next (c0114): this file never parses\n")
		write("tracker/issues/f0001/f0001.md", "---\nid: f0001\nslug: x\n---\n")
		write("tracker/rafts/active/R0001/prompt.md", "ignored\n")
		write(".gitignore", "/tracker/rafts/active/*/prompt.md\n")
		t.expect(process.exec("git", { "init", "-q", base }).ok).toBe(true)
		fixture.git(base, { "add", "-A" })
		local reg = projects.load(base, true)
		t.expect(codes(audit.leftovers(base, audit.scan(base), reg)))
			.toEqual({ "error old-root tracker/issues/f0001/f0001.md" })
		-- and audit.run carries it
		local found = false
		for _, p in audit.run(base) do
			if p.code == "old-root" and p.level == "error" then
				found = true
			end
		end
		t.expect(found).toBe(true)
	end)

	it("audit reports a promoted-spec folder outside its item's project's home, either way", function()
		write("pickman/.tracker/issues/done/f0002/f0002.md", "---\nid: f0002\nslug: y\n---\n")
		write("z-nile/.tracker/issues/done/c0003/c0003.md", "---\nid: c0003\nslug: z\n---\n")
		write("z-nile/" .. ACC .. "f0002/a.spec.luau", "--!strict\nreturn nil\n")
		write("pickman/" .. ACC .. "c0003/b.spec.luau", "--!strict\nreturn nil\n")
		write("pickman/" .. ACC .. "f0004/c.spec.luau", "--!strict\nreturn nil\n") -- no such item: not judged
		fixture.git(base, { "add", "-A" })
		local reg = projects.load(base, true)
		t.expect(codes(audit.leftovers(base, audit.scan(base), reg))).toEqual({
			"error misplaced-spec pickman/" .. ACC .. "c0003",
			"error misplaced-spec z-nile/" .. ACC .. "f0002",
			"error old-root tracker/issues/f0001/f0001.md",
		})
	end)

	it("cleans up", function()
		fs.removeDir(base)
	end)
end)
