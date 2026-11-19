--!strict
-- f0199 AC2: a place learns every place's id from attributes (arcade/.tracker/architecture.md, Places and publishing):
-- PortalPlaceId, PickmanPlaceId, SnakePlaceId, InvadersPlaceId and AsteroidsPlaceId, where 0 means not published.
-- Places (arcade/src/shared/Places.luau, a config module outside Logic) is pure: the adapter passes the read
-- (ServerScriptService:GetAttribute, where the publisher writes them), and every value goes through Travel's place-id
-- check. The expected answers are written out here, never computed with Travel.destination.
local Places = require("@shared/Places")
local Travel = require("@logic/Travel")
local t = require("@tests/lib/t")

local NAMES = { "Portal", "Pickman", "Snake", "Invaders", "Asteroids" }
local ATTRIBUTES =
	{ "PortalPlaceId", "PickmanPlaceId", "SnakePlaceId", "InvadersPlaceId", "AsteroidsPlaceId" }

-- a read over a table of attribute values that records every name it was asked for
local function reader(values: { [string]: any }): ((string) -> any, { string })
	local asked: { string } = {}
	return function(attribute: string): any
		table.insert(asked, attribute)
		return values[attribute]
	end,
		asked
end

local function count(places: { [any]: any }): number
	local n = 0
	for _ in places do
		n += 1
	end
	return n
end

return t.spec("f0199 place ids", function(it)
	it("the places are the portal and the four games, in that order, and the list is frozen", function()
		t.expect(Places.NAMES).toEqual(NAMES)
		t.expect(table.isfrozen(Places.NAMES)).toBe(true)
	end)

	it("each place's attribute is its name and PlaceId", function()
		for i, name in NAMES do
			t.expect(Places.attribute(name :: any)).toBe(ATTRIBUTES[i])
		end
	end)

	it(
		"a name that is not a place raises, naming it, rather than reading an attribute nobody writes",
		function()
			for _, bad in { "Lobby", "Game", "portal", "", "PortalPlaceId" } do
				local ok, err = pcall(Places.attribute, bad :: any)
				t.expect(ok).toBe(false)
				t.expect(string.find(tostring(err), `"{bad}"`, 1, true) ~= nil).toBe(true)
			end
		end
	)

	it("read reads each of the five attributes once, in order, and nothing else", function()
		local read, asked = reader({ LobbyPlaceId = 7, GamePlaceId = 8 })
		Places.read(read)
		t.expect(asked).toEqual(ATTRIBUTES)
	end)

	it("a published place's id comes back under its name, as a number or as digits", function()
		local read = reader({
			PortalPlaceId = 101,
			PickmanPlaceId = "202",
			SnakePlaceId = 303,
			InvadersPlaceId = Travel.MAX_PLACE_ID,
			AsteroidsPlaceId = "505",
		})
		local places = Places.read(read)
		t.expect(places.Portal).toBe(101)
		t.expect(places.Pickman).toBe(202)
		t.expect(places.Snake).toBe(303)
		t.expect(places.Invaders).toBe(Travel.MAX_PLACE_ID)
		t.expect(places.Asteroids).toBe(505)
		t.expect(count(places)).toBe(5)
	end)

	it("0 means not published, and so does a missing attribute or anything that is not a place id", function()
		local read = reader({
			PortalPlaceId = 0,
			PickmanPlaceId = 4242,
			SnakePlaceId = "0",
			InvadersPlaceId = 1.5,
			-- AsteroidsPlaceId is missing
		})
		local places = Places.read(read)
		t.expect(places.Portal).toBe(nil)
		t.expect(places.Snake).toBe(nil)
		t.expect(places.Invaders).toBe(nil)
		t.expect(places.Asteroids).toBe(nil)
		t.expect(places.Pickman).toBe(4242)
		t.expect(count(places)).toBe(1)
	end)

	it("every value goes through the place-id check, for every place alone", function()
		-- the same non-ids f0061 lists for Travel.destination, and 2^53 (where tonumber rounds 2^53 + 1)
		local bads: { any } = {
			0,
			-1,
			1.5,
			0 / 0,
			math.huge,
			Travel.MAX_PLACE_ID + 2,
			"0",
			"",
			"12a",
			"-5",
			" 7",
			"1.5",
			"0x10",
			"1e3",
			"١٢٣",
			"9007199254740992",
			"9007199254740993",
			true,
			{},
		}
		local goods: { { any } } = {
			{ 1, 1 },
			{ "987654321", 987654321 },
			{ Travel.MAX_PLACE_ID, 9007199254740991 },
			{ "9007199254740991", 9007199254740991 },
		}
		for i, name in NAMES do
			local attribute = ATTRIBUTES[i]
			for _, bad in bads do
				local places = Places.read((reader({ [attribute] = bad })))
				t.expect(`{name} {tostring(bad)}: {count(places)}`).toBe(`{name} {tostring(bad)}: 0`)
			end
			for _, good in goods do
				local places: any = Places.read((reader({ [attribute] = good[1] })))
				t.expect(`{name} {tostring(good[1])}: {tostring(places[name])}`)
					.toBe(`{name} {tostring(good[1])}: {tostring(good[2])}`)
				t.expect(count(places)).toBe(1)
			end
		end
	end)

	it("as checked in (every attribute 0), no place is published", function()
		local values: { [string]: any } = {}
		for _, attribute in ATTRIBUTES do
			values[attribute] = 0
		end
		local places = Places.read((reader(values)))
		t.expect(count(places)).toBe(0)
	end)

	it(
		"every read gives a fresh, frozen answer: what was read once is never changed by a later read",
		function()
			local first = Places.read((reader({ PortalPlaceId = 11 })))
			local second = Places.read((reader({ PortalPlaceId = 22, SnakePlaceId = 33 })))
			t.expect(table.isfrozen(first)).toBe(true)
			t.expect(table.isfrozen(second)).toBe(true)
			t.expect(first.Portal).toBe(11)
			t.expect(first.Snake).toBe(nil)
			t.expect(second.Portal).toBe(22)
			t.expect(second.Snake).toBe(33)
		end
	)
end)
