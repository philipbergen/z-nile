--!strict
-- c0183 AC1: the arcade's five projects are registered after pickman and z-nile, each with its root <name>/.tracker
-- (its home <name>/), and each new root is a tracked, empty tracker: issues/active and rafts/active kept by a .gitkeep.
-- This spec is promoted, so it pins the rule, never today's exact list (design review 001 F3; zz-test lesson
-- promoted-specs-pin-rules-not-sets): a later project registered after these keeps it green. check.sh's AC1 holds the
-- exact seven, which is true on the day c0183 is done. These specs run from z-nile/: the checkout is read from its top.
local fs = require("@lune/fs")
local process = require("@lune/process")
local projects = require("@znile/engine/projects")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local NEW = { "arcade", "portal", "snake", "invaders", "asteroids" }

local function shipped(): projects.Registry
	local reg, err = projects.parse(fs.readFile(`{TOP}/z-nile/projects.toml`))
	t.expect(err).toBe(nil)
	return reg :: projects.Registry
end

return t.spec("c0183 the arcade's projects are registered", function(it)
	it("AC1: pickman and z-nile come first, then the five, in this order, each at <name>/.tracker", function()
		local r = shipped()
		t.expect(r.projects[1].name).toBe("pickman")
		t.expect(r.projects[2].name).toBe("z-nile")
		local at: { [string]: number } = {}
		for i, p in r.projects do
			at[p.name] = i
		end
		local last = 2
		for _, n in NEW do
			local i = at[n]
			if not i then
				error(`{n} is not registered`)
			end
			t.expect(r.projects[i]).toEqual({ name = n, root = `{n}/.tracker`, home = n })
			if i <= last then
				error(`{n} is registered out of order`)
			end
			last = i
		end
		t.expect(r.retired).toEqual({ "tracker" })
	end)

	it(
		"AC1: the shell reader prints one line per registered project, name, home and root, in registry order",
		function()
			local out = process.exec("lune", { "run", "z-nile/roots", "--", "--projects" }, { cwd = TOP })
			t.expect(out.ok).toBe(true)
			local want = ""
			for _, p in shipped().projects do
				want ..= `{p.name}\t{p.home}\t{p.root}\n`
			end
			t.expect(out.stdout).toBe(want)
		end
	)

	it("AC1: every new root is tracked with issues/active and rafts/active kept by a .gitkeep", function()
		for _, n in NEW do
			for _, keep in { "issues/active/.gitkeep", "rafts/active/.gitkeep" } do
				local path = `{n}/.tracker/{keep}`
				local r = process.exec("git", { "ls-files", "--error-unmatch", "--", path }, { cwd = TOP })
				if not r.ok then
					error(`{path} is not tracked`)
				end
			end
		end
	end)
end)
