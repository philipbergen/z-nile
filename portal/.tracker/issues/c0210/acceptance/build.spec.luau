--!strict
-- c0210 AC8: every build of the checked-in manifest builds with the real Rojo from portal/, through Beta.project's copy
-- with every place published, and the built place's ServerScriptService holds every attribute the plan gives it, with
-- its type (a number for an id, the text "test" for PaidPlay). The checked-in project files are not changed.
local Beta = require("@scripts/lib/beta")
local Experience = require("@scripts/lib/experience")
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local t = require("@tests/lib/t")

local root = (string.gsub(process.cwd, "/+$", ""))
local work = `{root}/.cache/c0210-build`

local ENV: { [string]: string? } = {
	ROBLOX_API_KEY = "KEY",
	ROBLOX_BETA_UNIVERSE_ID = "111",
	ROBLOX_BETA_PLACE_ID = "222",
	ROBLOX_BETA_PICKMAN_PLACE_ID = "333",
	ROBLOX_BETA_SNAKE_PLACE_ID = "444",
	ROBLOX_BETA_INVADERS_PLACE_ID = "555",
	ROBLOX_BETA_ASTEROIDS_PLACE_ID = "666",
}

return t.spec("c0210 every build of the manifest builds with its attributes", function(it)
	fs.writeDir(work)
	local manifest = Experience.parse(fs.readFile("experience.json")) :: Experience.Manifest
	local plan = Beta.plan(ENV, manifest) :: Beta.Plan
	-- the builds no place publishes yet (the portal's own, until f0209) are built with the start place's attributes
	local start = Beta.target(plan, "Portal") :: Beta.Target
	local keys: { string } = {}
	for key in manifest.builds do
		table.insert(keys, key)
	end
	table.sort(keys)

	for _, key in keys do
		it(`the {key} build`, function()
			local build = manifest.builds[key]
			local attributes = start.attributes
			for _, target in plan.targets do
				if target.build == key then
					attributes = target.attributes
				end
			end
			local source = `{root}/{build.project}`
			local text = fs.readFile(source)
			local dir = string.match(source, "^(.*)/[^/]+$") :: string
			local copy = `{work}/{key}.project.json`
			fs.writeFile(copy, Beta.project(text, dir, attributes))
			local out = `{work}/{key}.rbxl`
			local r = process.exec("rojo", { "build", copy, "-o", out })
			t.expect(`{key}: {r.ok} {r.stderr}`).toBe(`{key}: true `)
			local sss = roblox.deserializePlace(fs.readFile(out)):GetService("ServerScriptService")
			for name, value in attributes do
				t.expect(`{key} {name}: {typeof(sss:GetAttribute(name))} {tostring(sss:GetAttribute(name))}`)
					.toBe(
						`{key} {name}: {if type(value) == "string" then "string" else "number"} {tostring(
							value
						)}`
					)
			end
			t.expect(sss:GetAttribute("PaidPlay")).toBe("test")
			t.expect(fs.readFile(source)).toBe(text)
		end)
	end
end)
