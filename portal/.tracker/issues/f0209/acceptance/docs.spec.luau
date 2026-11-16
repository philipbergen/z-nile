--!strict
-- f0209 AC5: the documents that say what the start place publishes say the portal. SETUP.md's Beta section names the
-- portal as the start place, says what the switch does and how it is rolled back, and points the start place's
-- runtime tests at portal/tests/runtime; pickman's game design says the start place is the portal since f0209;
-- portal-test describes that runtime tier; pickman-test says the lobby's runtime scripts run at the start place only
-- before f0209 or after a rollback. Runs from portal/.
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

local function has(s: string, needle: string): boolean
	return string.find(s, needle, 1, true) ~= nil
end

local function beta(): string
	local setup = fs.readFile("../SETUP.md")
	local from = string.find(setup, "## Beta publishing", 1, true)
	assert(from, "SETUP.md has a Beta publishing section")
	local to = string.find(setup, "\n## ", from + 5, true)
	return string.sub(setup, from, to)
end

local function expectAll(text: string, needles: { string })
	for _, needle in needles do
		t.expect(`{needle}: {has(text, needle)}`).toBe(`{needle}: true`)
	end
end

return t.spec("f0209 the documents name the portal as the start place", function(it)
	it("SETUP.md's Beta section: the start place is the portal, since f0209", function()
		local s = beta()
		expectAll(s, {
			"`ROBLOX_BETA_PLACE_ID` the start place (the portal, `portal/default.project.json`, since f0209",
			"**The start place is the portal** (f0209)",
			"which Pickman's game reads as `LobbyPlaceId` for its way back, leads to the portal",
			"pickman's lobby is no longer published",
			"A pull request's deploy publishes its merge with `main`",
		})
		t.expect(has(s, "until the portal replaces it")).toBe(false)
	end)

	it("SETUP.md's Beta section: rolling the start place back is the one line, until c0188", function()
		expectAll(beta(), {
			"**Rolling the start place back** (until c0188 deletes the lobby)",
			'`"build": "portal"` to `"build": "lobby"` on the Portal place',
			"told `GamePlaceId`, as before f0209",
		})
	end)

	it("SETUP.md's Beta section: the start place's runtime tests are the portal's", function()
		expectAll(beta(), {
			"`lune run scripts/runtime-test -- --place Portal <lobby version>` for the start place",
			"the portal's `portal/tests/runtime/` since f0209",
		})
	end)

	it("pickman's game design says the start place is the portal since f0209", function()
		expectAll(fs.readFile("../pickman/.tracker/game-design.md"), {
			"Since f0209 the experience's start place is the portal (`portal/.tracker/game-design.md`), so the way back leads there and the lobby is no longer published",
		})
	end)

	it("portal-test describes the start place's runtime tier", function()
		expectAll(fs.readFile("skills/portal-test/SKILL.md"), {
			"`tests/runtime/` holds the start place's runtime scripts (f0209)",
			"lune run scripts/runtime-test -- --place Portal <version>",
			'returns `"PASS"`, requires nothing',
		})
	end)

	it(
		"pickman-test: the lobby's runtime scripts are the start place's only before f0209 or after a rollback",
		function()
			expectAll(fs.readFile("../pickman/skills/pickman-test/SKILL.md"), {
				"before f0209, or after a rollback of it; the portal's own are `portal/tests/runtime/`",
			})
		end
	)
end)
