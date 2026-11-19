--!strict
-- Places (f0199): the experience's places and the one read of their ids. Every place learns every place's id from a
-- ServerScriptService attribute `<Name>PlaceId` the publisher writes (0 means not published); the read is passed in,
-- so this module stays pure, and every value goes through Travel's place-id check. The one module in the library
-- that names the experience's places (Catalog names the games' paid play): data, never branched on.
local Travel = require("./Logic/Travel")

export type Name = "Portal" | "Pickman" | "Snake" | "Invaders" | "Asteroids"
-- a published place's id under its name; a place that is not published is nil
export type Ids = {
	Portal: number?,
	Pickman: number?,
	Snake: number?,
	Invaders: number?,
	Asteroids: number?,
}

local NAMES: { Name } = { "Portal", "Pickman", "Snake", "Invaders", "Asteroids" }

local Places = {}

Places.NAMES = table.freeze(NAMES)

local function attributeOf(name: Name): string
	return name .. "PlaceId"
end

-- The attribute that holds a place's id; a name that is not a place raises, naming it.
function Places.attribute(name: Name): string
	if not table.find(NAMES, name) then
		error(`Places.attribute: "{tostring(name)}" is not a place`, 2)
	end
	return attributeOf(name)
end

-- Every published place's id, read once each through `read` (an attribute name in, its value out), in the order of
-- NAMES. A value that is not a place id (0, missing, text, a fraction, ...) means not published. Each call answers a
-- new frozen table.
function Places.read(read: (attribute: string) -> any): Ids
	local out: { [string]: number } = {}
	for _, name: Name in NAMES do
		local id = Travel.destination(read(attributeOf(name)))
		if id ~= nil then
			out[name] = id
		end
	end
	return table.freeze(out) :: any
end

return Places
