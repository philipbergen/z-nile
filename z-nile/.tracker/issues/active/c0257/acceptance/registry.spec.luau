--!strict
-- c0257 AC11 (G1, ruled 2026-11-16: the app is its own project): the registry has a project kind. `kind = "app"` is
-- the one value; a project without it is a Luau project; each project's table stays { name, root, home } and the
-- registry lists its apps. The shell reader prints them (`--apps`) and leaves app homes out of the Luau folders.
-- Reads files and runs z-nile/roots in the checkout (read-only).
local process = require("@lune/process")
local projects = require("@znile/engine/projects")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function project(name: string, extra: string?): string
	return `[[project]]\nname = "{name}"\nroot = "{name}/.tracker"\n{extra or ""}\n`
end
local function refused(text: string, needle: string)
	local reg, err = projects.parse(text)
	t.expect(reg).toBe(nil)
	t.expect(string.find(err or "", needle, 1, true) ~= nil).toBe(true)
end
local function roots(arg: string): string
	local r = process.exec("lune", { "run", "z-nile/roots", "--", arg }, { cwd = TOP })
	t.expect(r.ok).toBe(true)
	return r.stdout
end

return t.spec("c0257 AC11: an app project in the registry", function(it)
	it("AC11: the real registry lists z-nile-omarchy last, as an app, with the usual table", function()
		local reg = projects.load(TOP)
		local last = reg.projects[#reg.projects]
		t.expect(last)
			.toEqual({ name = "z-nile-omarchy", root = "z-nile-omarchy/.tracker", home = "z-nile-omarchy" })
		t.expect(reg.apps).toEqual({ "z-nile-omarchy" })
	end)

	it('AC11: kind = "app" is accepted, no kind is a Luau project, anything else is refused', function()
		local reg =
			projects.parse(project("z-nile") .. project("a", 'kind = "app"') .. project("b")) :: projects.Registry
		t.expect(reg.apps).toEqual({ "a" })
		t.expect(reg.projects[2]).toEqual({ name = "a", root = "a/.tracker", home = "a" })
		local plain = projects.parse(project("z-nile") .. project("b")) :: projects.Registry
		t.expect(plain.apps).toEqual({})
		refused(project("a", 'kind = "luau"'), "kind")
		refused(project("a", "kind = 1"), "kind")
		refused(project("z-nile", 'kind = "app"'), "z-nile")
		refused(project("a", "extra = 1"), "unknown key")
	end)

	it("AC11: z-nile/roots prints the apps and leaves their homes out of the Luau folders", function()
		t.expect(roots("--apps")).toBe("z-nile-omarchy\n")
		local dirs: { [string]: boolean } = {}
		for w in string.gmatch(roots("--luau-dirs"), "%S+") do
			dirs[w] = true
		end
		t.expect(dirs["z-nile-omarchy"]).toBe(nil)
		t.expect(dirs["z-nile-omarchy/.tracker"]).toBe(true)
		local line = string.match(roots("--projects"), "(z%-nile%-omarchy\t[^\n]*)")
		t.expect(line).toBe("z-nile-omarchy\tz-nile-omarchy\tz-nile-omarchy/.tracker")
	end)
end)
