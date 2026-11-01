--!strict
-- c0183 AC5: once registered, the new projects take captures. In a tracker fixture under .cache/c0183-capture
-- (tests/lib/trackerfix: a bare origin, a main checkout, a second terminal) seeded with the shipped registry and the
-- new roots' .gitkeeps, `new issue` run in a new project's folder files in that project's root and publishes to
-- origin's main, --project names any of them, and `list --project` shows each project's own items only.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local NEW = { "arcade", "portal", "snake", "invaders", "asteroids" }

local f: trackerfix.Fixture
local wt = ""

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function onOrigin(path: string): boolean
	return fixture.exec(f.origin, "git", { "cat-file", "-e", `main:{path}` }).ok
end
-- ./zn run from the folder `sub` of the worktree (the directory gives the project)
local function znIn(sub: string, args: { string }): string
	local argv = { "-c", 'cd "$1" || exit 1; shift; exec bash "$OLDPWD/zn" "$@"', "_", sub }
	for _, a in args do
		table.insert(argv, a)
	end
	local r = fixture.exec(wt, "bash", argv)
	if not r.ok then
		error(`{sub}: zn {table.concat(args, " ")} failed: {r.stderr}{r.stdout}`, 2)
	end
	return (string.gsub(r.stdout, "%s+$", ""))
end

return t.spec("c0183 the new projects take captures", function(it)
	it("setup", function()
		local seed: { [string]: string } = {
			["z-nile/projects.toml"] = fs.readFile(`{TOP}/z-nile/projects.toml`),
		}
		for _, n in NEW do
			seed[`{n}/.tracker/issues/active/.gitkeep`] = ""
			seed[`{n}/.tracker/rafts/active/.gitkeep`] = ""
		end
		f = trackerfix.new("c0183-capture", seed)
		wt = trackerfix.trOk(f, f.main, { "worktree", "work" })
	end)

	it(
		"AC5: new issue in a new project's folder files in its root and publishes; --project names the others",
		function()
			local made: { [string]: string } = {}
			for _, n in NEW do
				fs.writeDir(`{wt}/{n}`)
				local path = znIn(n, { "new", "issue", "f", `probe-{n}` })
				t.expect(
					string.match(
						path,
						`^{string.gsub(n, "%-", "%%-")}/%.tracker/issues/f%d%d%d%d/f%d%d%d%d%.md$`
					) ~= nil
				).toBe(true)
				t.expect(onOrigin(path)).toBe(true)
				made[n] = string.match(path, "(f%d%d%d%d)%.md$") :: string
			end
			-- --project from another project's folder
			local other = znIn("z-nile", { "new", "issue", "c", "probe-chore", "--project", "invaders" })
			t.expect(string.match(other, "^invaders/%.tracker/issues/c%d%d%d%d/c%d%d%d%d%.md$") ~= nil)
				.toBe(true)
			-- each project lists its own items only
			for _, n in NEW do
				local listed = znIn("z-nile", { "list", "backlog", "--project", n })
				for m, id in made do
					t.expect(has(listed, id)).toBe(m == n)
				end
			end
		end
	)
end)
