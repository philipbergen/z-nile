--!strict
-- c0210 AC1: the experience's manifest, portal/experience.json, and its one reader (scripts/lib/experience): every
-- place of arcade's Places once, each with the variable the architecture names, a build that is a project file of a
-- home, and a version name; the reader refuses anything ambiguous, naming the rule. Runs from portal/.
local Experience = require("@scripts/lib/experience")
local Places = require("@arcade/Places")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local GOOD = {
	places = {
		{ name = "Pickman", env = { "ROBLOX_BETA_PICKMAN_PLACE_ID" }, build = "pickman", output = "version" },
		{ name = "Snake", env = { "ROBLOX_BETA_SNAKE_PLACE_ID" }, build = "snake", output = "snake_version" },
		{
			name = "Invaders",
			env = { "ROBLOX_BETA_INVADERS_PLACE_ID" },
			build = "invaders",
			output = "invaders_version",
		},
		{
			name = "Asteroids",
			env = { "ROBLOX_BETA_ASTEROIDS_PLACE_ID" },
			build = "asteroids",
			output = "asteroids_version",
		},
		{ name = "Portal", env = { "ROBLOX_BETA_PLACE_ID" }, build = "start", output = "lobby_version" },
	},
	builds = {
		pickman = { project = "p/default.project.json", runtime = "p/tests/runtime" },
		snake = { project = "s/default.project.json" },
		invaders = { project = "i/default.project.json" },
		asteroids = { project = "a/default.project.json" },
		start = { project = "default.project.json", attributes = { GamePlaceId = "Pickman" } },
		spare = { project = "x/default.project.json" },
	},
}

-- a deep copy of GOOD with `edit` applied, as JSON text
local function variant(edit: ((any) -> ())?): string
	local doc: any = serde.decode("json" :: "json", serde.encode("json" :: "json", GOOD))
	if edit then
		edit(doc)
	end
	return serde.encode("json" :: "json", doc)
end

local function refuses(text: string, needle: string)
	local m, err = Experience.parse(text)
	t.expect(m).toBe(nil)
	local message = tostring(err)
	t.expect(string.sub(message, 1, #"experience.json: ")).toBe("experience.json: ")
	t.expect(`{needle}: {string.find(message, needle, 1, true) ~= nil}`).toBe(`{needle}: true`)
end

local function place(doc: any, name: string): any
	for _, p in doc.places do
		if p.name == name then
			return p
		end
	end
	error(`no place {name}`)
end

local real = fs.readFile("experience.json")

return t.spec("c0210 the experience's manifest", function(it)
	it("a good manifest reads back as written, unused builds kept", function()
		local m, err = Experience.parse(variant())
		t.expect(err).toBe(nil)
		local manifest = m :: Experience.Manifest
		t.expect(#manifest.places).toBe(5)
		t.expect(manifest.places[1].name).toBe("Pickman")
		t.expect(manifest.places[5].env).toEqual({ "ROBLOX_BETA_PLACE_ID" })
		t.expect(manifest.builds.start.attributes).toEqual({ GamePlaceId = "Pickman" })
		t.expect(manifest.builds.pickman.runtime).toBe("p/tests/runtime")
		t.expect(manifest.builds.snake.runtime).toBe(nil)
		t.expect(manifest.builds.snake.attributes).toEqual({})
		t.expect(manifest.builds.spare.project).toBe("x/default.project.json")
	end)

	it("refuses what is not a manifest", function()
		refuses("not json", "not a JSON object")
		refuses("[1, 2]", "not a JSON object")
		refuses(
			variant(function(d)
				d.extra = 1
			end),
			"unknown key extra"
		)
		refuses(
			variant(function(d)
				d.places = {}
			end),
			"places must be a list"
		)
		refuses(
			variant(function(d)
				d.builds = { 1 }
			end),
			"builds must be an object"
		)
	end)

	it("every place of Places.NAMES once, and nothing else", function()
		refuses(
			variant(function(d)
				table.remove(d.places, 2)
			end),
			"place Snake is missing"
		)
		refuses(
			variant(function(d)
				place(d, "Snake").name = "Pong"
			end),
			"name must be one of Places.NAMES"
		)
		refuses(
			variant(function(d)
				table.insert(
					d.places,
					{ name = "Snake", env = { "ROBLOX_BETA_X_PLACE_ID" }, build = "spare", output = "x" }
				)
			end),
			"place Snake is listed twice"
		)
		refuses(
			variant(function(d)
				place(d, "Snake").colour = "green"
			end),
			"unknown key colour"
		)
	end)

	it("a place's variables are Beta place-id variables, each a place's alone", function()
		refuses(
			variant(function(d)
				place(d, "Snake").env = {}
			end),
			"env must be a list"
		)
		for _, var in
			{
				"ROBLOX_LIVE_SNAKE_PLACE_ID",
				"ROBLOX_BETA_SNAKE",
				"SNAKE_PLACE_ID",
				"roblox_beta_snake_place_id",
			}
		do
			refuses(
				variant(function(d)
					place(d, "Snake").env = { var }
				end),
				`env {var} is not`
			)
		end
		refuses(
			variant(function(d)
				place(d, "Invaders").env = { "ROBLOX_BETA_SNAKE_PLACE_ID" }
			end),
			"env ROBLOX_BETA_SNAKE_PLACE_ID is also place Snake's"
		)
	end)

	it("exactly one place, the start place, reads ROBLOX_BETA_PLACE_ID, and it alone", function()
		refuses(
			variant(function(d)
				place(d, "Portal").env = { "ROBLOX_BETA_PORTAL_PLACE_ID" }
			end),
			"exactly one place reads ROBLOX_BETA_PLACE_ID"
		)
		refuses(
			variant(function(d)
				place(d, "Portal").env = { "ROBLOX_BETA_PLACE_ID", "ROBLOX_BETA_PORTAL_PLACE_ID" }
			end),
			"the start place reads ROBLOX_BETA_PLACE_ID alone"
		)
	end)

	it("a place's build is a build no other place publishes; its output a name of its own", function()
		refuses(
			variant(function(d)
				place(d, "Snake").build = "nope"
			end),
			"build must name a build"
		)
		refuses(
			variant(function(d)
				place(d, "Snake").build = "pickman"
			end),
			"build pickman is also place Pickman's"
		)
		refuses(
			variant(function(d)
				place(d, "Snake").output = "Snake-Version"
			end),
			"output must be lowercase"
		)
		refuses(
			variant(function(d)
				place(d, "Snake").output = "version"
			end),
			"output version is another place's"
		)
	end)

	it(
		"a build is a relative *.project.json, an optional relative runtime folder and attributes naming places",
		function()
			refuses(
				variant(function(d)
					d.builds.snake.project = "s/default.json"
				end),
				"project must be a relative path"
			)
			refuses(
				variant(function(d)
					d.builds.snake.project = "/abs/default.project.json"
				end),
				"project must be a relative path"
			)
			refuses(
				variant(function(d)
					d.builds.snake.runtime = "/abs"
				end),
				"runtime must be a relative folder"
			)
			refuses(
				variant(function(d)
					d.builds.snake.extra = true
				end),
				"build snake: unknown key extra"
			)
			refuses(
				variant(function(d)
					d.builds.snake.attributes = { lower = "Pickman" }
				end),
				"attribute lower must be a capitalized name"
			)
			refuses(
				variant(function(d)
					d.builds.snake.attributes = { BackPlaceId = "Lobby" }
				end),
				"attribute BackPlaceId must name a place"
			)
			refuses(
				variant(function(d)
					d.builds.Bad = { project = "b/default.project.json" }
				end),
				"build Bad: a build's name"
			)
			refuses(
				variant(function(d)
					d.builds.env = { project = "b/default.project.json" }
				end),
				"build env: a build's name"
			)
		end
	)

	it("an extra attribute never overrides one the publish writes itself", function()
		for _, attribute in
			{ "PortalPlaceId", "SnakePlaceId", "PaidPlay", "PlayProductId", "AsteroidsReviveProductId" }
		do
			refuses(
				variant(function(d)
					d.builds.snake.attributes = { [attribute] = "Pickman" }
				end),
				`attribute {attribute} is one the publish writes itself`
			)
		end
	end)

	it("a repeated key is refused, not read as its last value", function()
		local text = variant()
		local twice = string.gsub(text, '"build":"snake"', '"build":"snake","build":"spare"', 1)
		refuses(twice, "a key build is repeated")
		local env = string.gsub(
			text,
			'"output":"snake_version"',
			'"output":"snake_version","env":["ROBLOX_BETA_X_PLACE_ID"]',
			1
		)
		refuses(env, "a key env is repeated")
		local project = string.gsub(
			text,
			'"project":"s/default.project.json"',
			'"project":"s/default.project.json","project":"x/a.project.json"',
			1
		)
		refuses(project, "a key project is repeated")
	end)

	it("the checked-in manifest reads", function()
		local m, err = Experience.parse(real)
		t.expect(err).toBe(nil)
		t.expect(m ~= nil).toBe(true)
	end)

	it("it lists arcade's Places.NAMES, each once (f0199)", function()
		local m = Experience.parse(real) :: Experience.Manifest
		local listed: { string } = {}
		for _, p in m.places do
			table.insert(listed, p.name)
		end
		table.sort(listed)
		local expected: { string } = {}
		for _, name in Places.NAMES do
			table.insert(expected, name)
		end
		table.sort(expected)
		t.expect(listed).toEqual(expected)
	end)

	it(
		"each place reads the variable the architecture names; Pickman the new one first, then the old",
		function()
			local m = Experience.parse(real) :: Experience.Manifest
			local env: { [string]: { string } } = {}
			for _, p in m.places do
				env[p.name] = p.env
			end
			t.expect(env).toEqual({
				Portal = { "ROBLOX_BETA_PLACE_ID" },
				Pickman = { "ROBLOX_BETA_PICKMAN_PLACE_ID", "ROBLOX_BETA_GAME_PLACE_ID" },
				Snake = { "ROBLOX_BETA_SNAKE_PLACE_ID" },
				Invaders = { "ROBLOX_BETA_INVADERS_PLACE_ID" },
				Asteroids = { "ROBLOX_BETA_ASTEROIDS_PLACE_ID" },
			})
		end
	)

	it(
		"each game publishes its own home's default project, and the portal's own project is a build",
		function()
			local m = Experience.parse(real) :: Experience.Manifest
			for _, p in m.places do
				if p.name ~= "Portal" then
					local home = string.lower(p.name)
					t.expect(`{p.name}: {m.builds[p.build].project}`)
						.toBe(`{p.name}: ../{home}/default.project.json`)
				end
			end
			local portal = false
			for _, build in m.builds do
				portal = portal or build.project == "default.project.json"
			end
			t.expect(portal).toBe(true)
		end
	)

	it("every build's project file exists, and every runtime folder", function()
		local m = Experience.parse(real) :: Experience.Manifest
		for key, build in m.builds do
			t.expect(`{key}: {fs.isFile(build.project)}`).toBe(`{key}: true`)
			if build.runtime then
				t.expect(`{key}: {fs.isDir(build.runtime :: string)}`).toBe(`{key}: true`)
			end
		end
	end)

	it(
		"Pickman's outputs keep their names: version for Pickman, lobby_version for the start place",
		function()
			local m = Experience.parse(real) :: Experience.Manifest
			local out: { [string]: string } = {}
			for _, p in m.places do
				out[p.name] = p.output
			end
			t.expect(out.Pickman).toBe("version")
			t.expect(out.Portal).toBe("lobby_version")
		end
	)
end)
