--!strict
-- Regression guard (c0500): `tracker.sh new` keeps its multiple-of-10 spacing, which leaves room to insert
-- issues. Only `renumber` advances by one.
local engine = require("@tests/lib/engine")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end

local root = trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)
-- outside any repository's remote: the repo has no origin, so the main-checkout guard is off
local base = trim(process.exec("mktemp", { "-d" }).stdout)
fs.writeFile(`{base}/rokit.toml`, fs.readFile(`{root}/rokit.toml`))
process.exec("git", { "init", "-q" }, { cwd = base })
-- c0114 override: the templates and the engine moved to z-nile/
fs.writeDir(`{base}/z-nile`)
process.exec("cp", { "-R", `{root}/z-nile/templates`, `{base}/z-nile/templates` })
engine.registry(base) -- c0114: a tree without the registry refuses
fs.writeDir(`{base}/tracker`)

local function put(id: string)
	fs.writeDir(`{base}/tracker/issues/{id}`)
	fs.writeFile(`{base}/tracker/issues/{id}/{id}.md`, `---\nid: {id}\ntitle: T\nslug: s\n---\n`)
end

local function new(args: { string }): process.ExecResult
	local all = { "run", `{root}/z-nile/engine/main`, "--", "new" }
	for _, a in args do
		table.insert(all, a)
	end
	-- c0114: at a checkout's root the project is named
	table.insert(all, "--project")
	table.insert(all, "pickman")
	return process.exec("lune", all, { cwd = base })
end

return t.spec("new keeps multiple-of-10 spacing", function(it)
	it(
		"the next issue is the next multiple of 10 above the highest, even when that is not a multiple",
		function()
			put("f0111")
			put("c0102")
			local r = new({ "issue", "c", "next-one" })
			t.expect(r.ok).toBe(true)
			t.expect(fs.isFile(`{base}/tracker/issues/c0120/c0120.md`)).toBe(true)
		end
	)

	it("after 0120 comes 0130, not 0121", function()
		local r = new({ "issue", "d", "again" })
		t.expect(r.ok).toBe(true)
		t.expect(fs.isFile(`{base}/tracker/issues/d0130/d0130.md`)).toBe(true)
		t.expect(fs.isFile(`{base}/tracker/issues/d0121/d0121.md`)).toBe(false)
	end)

	it("cleanup", function()
		fs.removeDir(base)
	end)
end)
