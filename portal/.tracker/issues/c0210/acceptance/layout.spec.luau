--!strict
-- c0210 AC7: the deploy scripts and the runtime runner live in portal/scripts/; pickman/scripts keeps only its two
-- forwarders; the aliases reach them from both homes; and the documents that say where they run say portal/ and
-- --place in the same words.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function read(rel: string): string
	return fs.readFile(`{TOP}/{rel}`)
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

local SCRIPTS = {
	"deploy-beta.luau",
	"runtime-test.luau",
	"cicd.luau",
	"lib/beta.luau",
	"lib/experience.luau",
	"lib/opencloud.luau",
	"lib/cicdconfig.luau",
	"lib/lease.luau",
	"lib/leasefile.luau",
}

local function walk(dir: string, prefix: string, out: { string })
	for _, name in fs.readDir(dir) do
		local p = `{dir}/{name}`
		if fs.isDir(p) then
			walk(p, `{prefix}{name}/`, out)
		else
			table.insert(out, `{prefix}{name}`)
		end
	end
end

return t.spec("c0210 the deploy lives in portal/", function(it)
	it("every deploy script is in portal/scripts", function()
		for _, rel in SCRIPTS do
			t.expect(`{rel}: {fs.isFile(`{TOP}/portal/scripts/{rel}`)}`).toBe(`{rel}: true`)
		end
	end)

	it("pickman/scripts keeps only its two forwarders", function()
		local files: { string } = {}
		walk(`{TOP}/pickman/scripts`, "", files)
		table.sort(files)
		t.expect(files).toEqual({ "check.sh", "tracker.sh" })
	end)

	it("@scripts is portal's scripts from both homes", function()
		local portal = serde.decode("json" :: "json", read("portal/.luaurc")) :: any
		local pickman = serde.decode("json" :: "json", read("pickman/.luaurc")) :: any
		t.expect(portal.aliases.scripts).toBe("./scripts")
		t.expect(pickman.aliases.scripts).toBe("../portal/scripts")
	end)

	it("the merge's cicd runs from portal/", function()
		local rules = read("z-nile/skills/zz-rules/SKILL.md")
		t.expect(
			has(
				rules,
				"In `$dir/portal`, on the detached head from step 2 (`git checkout --detach`), `lune run scripts/cicd` passes. Run it as `../zn run --time 1800 -- lune run scripts/cicd` from `$dir/portal`"
			)
		).toBe(true)
		t.expect(has(rules, "`$dir/pickman`")).toBe(false)
	end)

	it("SETUP.md names the manifest, every variable, portal/ and --place", function()
		local setup = read("SETUP.md")
		for _, needle in
			{
				"by running `lune run scripts/deploy-beta` from `portal/`",
				"`portal/experience.json` lists the experience's places",
				"`ROBLOX_BETA_PICKMAN_PLACE_ID`",
				"the old `ROBLOX_BETA_GAME_PLACE_ID` is still read",
				"`ROBLOX_BETA_SNAKE_PLACE_ID`, `ROBLOX_BETA_INVADERS_PLACE_ID` and `ROBLOX_BETA_ASTEROIDS_PLACE_ID`",
				"A place whose variable is unset or empty is not published",
				"`PortalPlaceId`, `PickmanPlaceId`, `SnakePlaceId`, `InvadersPlaceId`, `AsteroidsPlaceId`; 0 for a place not published",
				"paid play's test mode (`PaidPlay` = `test`, each product id 0)",
				"the games are published first, then the start place",
				"run `lune run scripts/deploy-beta` in `portal/`",
				"runs `lune run scripts/cicd` from `portal/`",
				"`lune run scripts/runtime-test -- --place Pickman <version>`",
				"`lune run scripts/runtime-test -- --place Portal <lobby version>`",
			}
		do
			t.expect(`{needle}: {has(setup, needle)}`).toBe(`{needle}: true`)
		end
		-- the Beta section no longer runs anything from pickman/ (Studio's own steps still do)
		local beta = string.sub(setup, string.find(setup, "## Beta publishing", 1, true) :: number)
		t.expect(has(beta, "--lobby")).toBe(false)
		t.expect(has(beta, "from `pickman/`")).toBe(false)
		t.expect(has(beta, "in `pickman/`")).toBe(false)
	end)

	-- c0210 design review 001 F5: the skills that say where @scripts points move with the alias
	it("zz-test and pickman-test say @scripts is portal's scripts/", function()
		t.expect(
			has(
				read("z-nile/skills/zz-test/SKILL.md"),
				"(and pickman's `@logic` and `@shared` at pickman's folders, and `@scripts` at portal's `scripts/` (c0210), where the deploy lives)"
			)
		).toBe(true)
		t.expect(
			has(
				read("pickman/skills/pickman-test/SKILL.md"),
				"where `pickman/.luaurc` points `@tests`, `@logic` and `@shared` at pickman's own folders, and `@scripts` at portal's `scripts/` (c0210), where the deploy lives."
			)
		).toBe(true)
		t.expect(has(read("z-nile/skills/zz-test/SKILL.md"), "`@shared` and `@scripts` at pickman's folders"))
			.toBe(false)
		t.expect(
			has(
				read("pickman/skills/pickman-test/SKILL.md"),
				"`@shared` and `@scripts` at pickman's own folders"
			)
		).toBe(false)
	end)

	it("pickman-test's runtime row runs the runner from portal/ with --place", function()
		local testing = read("pickman/skills/pickman-test/SKILL.md")
		t.expect(has(testing, "lune run scripts/runtime-test -- --place Pickman <version>")).toBe(true)
		t.expect(has(testing, "run with `--place Portal <version>`")).toBe(true)
		t.expect(has(testing, "A merge runs `lune run scripts/cicd` from `portal/`")).toBe(true)
		t.expect(has(testing, "--lobby")).toBe(false)
	end)
end)
