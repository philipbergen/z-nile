--!strict
-- f0205 AC3: the portal's games (src/shared/Games.luau), one entry each in the carousel's order: Pickman, Snake,
-- Invaders, Asteroids. Each entry's name and title are its paid-play title in the arcade's Catalog (so the Wallet read
-- finds its record), its place is its name in the arcade's Places (so its id says whether it is published), its
-- tagline is a short line, and its preview is a small scene of parts that the preview camera frames. Frozen.
local Card = require("@logic/Card")
local Games = require("@shared/Games")
local Places = require("@arcade/Places")
local luau = require("@lune/luau")
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

-- the arcade's Catalog is server-only (ServerStorage.Arcade.Catalog): read it from the built place
local function catalog(): { any }
	local built = place.load()
	local node = (built :: any):GetService("ServerStorage"):FindFirstChild("Arcade"):FindFirstChild("Catalog")
	assert(node ~= nil, "ServerStorage.Arcade.Catalog is in the built place")
	return luau.load(node.Source, { debugName = "Catalog" })()
end

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

return t.spec("f0205 games", function(it)
	it("four games in the carousel's order: Pickman, Snake, Invaders, Asteroids", function()
		local names, places = {}, {}
		for _, e in Games.LIST do
			table.insert(names, e.name)
			table.insert(places, e.place)
		end
		t.expect(table.concat(names, " ")).toBe("pickman snake invaders asteroids")
		t.expect(table.concat(places, " ")).toBe("Pickman Snake Invaders Asteroids")
	end)

	it("each game's place is a place of the arcade's Places, and none is the portal", function()
		for _, e in Games.LIST do
			t.expect(table.find(Places.NAMES, e.place :: any) ~= nil).toBe(true)
			t.expect(e.place == "Portal").toBe(false)
		end
	end)

	it("each game's place is published exactly when Places.read finds its id", function()
		for _, e in Games.LIST do
			local ids = Places.read(function(attribute: string): any
				return if attribute == Places.attribute(e.place :: any) then 4242 else 0
			end)
			for _, other in Games.LIST do
				t.expect(Card.published(other, ids :: any)).toBe(other == e)
			end
		end
	end)

	it(
		"each game's name and title are its paid-play title in the arcade's Catalog, in the same order",
		function()
			local titles = catalog()
			t.expect(#titles).toBe(#Games.LIST)
			for i, e in Games.LIST do
				t.expect(e.name).toBe(titles[i].name)
				t.expect(e.title).toBe(titles[i].title)
			end
		end
	)

	it("each tagline is one short line", function()
		for _, e in Games.LIST do
			t.expect(type(e.tagline)).toBe("string")
			t.expect(#e.tagline >= 10 and #e.tagline <= 60).toBe(true)
			t.expect((string.find(e.tagline, "\n", 1, true))).toBe(nil)
		end
	end)

	it("the taglines and titles are each the game's own", function()
		local seen: { [string]: boolean } = {}
		for _, e in Games.LIST do
			t.expect(seen[e.tagline]).toBe(nil)
			t.expect(seen[e.title]).toBe(nil)
			seen[e.tagline] = true
			seen[e.title] = true
		end
	end)

	it(
		"each preview is a scene of 1 to 24 parts, each a known shape with a positive size and an RGB colour",
		function()
			for _, e in Games.LIST do
				t.expect(#e.preview >= 1 and #e.preview <= 24).toBe(true)
				for _, p in e.preview do
					t.expect(table.find(Card.SHAPES, p.shape) ~= nil).toBe(true)
					t.expect(#p.size).toBe(3)
					t.expect(#p.at).toBe(3)
					t.expect(#p.color).toBe(3)
					for k = 1, 3 do
						t.expect(finite(p.size[k]) and p.size[k] > 0).toBe(true)
						t.expect(finite(p.at[k])).toBe(true)
						local c = p.color[k]
						t.expect(finite(c) and c >= 0 and c <= 255 and c == math.floor(c)).toBe(true)
					end
				end
			end
		end
	)

	it(
		"every part of every preview lies within FRAME of the centre on each axis, so the camera frames it",
		function()
			for _, e in Games.LIST do
				for i, p in e.preview do
					for k = 1, 3 do
						local reach = math.abs(p.at[k]) + p.size[k] / 2
						if reach > Card.FRAME + 1e-9 then
							error(
								`expected {e.name} part {i} within FRAME {Card.FRAME} on axis {k}, it reaches {reach}`
							)
						end
					end
				end
			end
		end
	)

	it("the list, every entry and every preview are frozen", function()
		t.expect(table.isfrozen(Games.LIST)).toBe(true)
		for _, e in Games.LIST do
			t.expect(table.isfrozen(e)).toBe(true)
			t.expect(table.isfrozen(e.preview)).toBe(true)
			for _, p in e.preview do
				t.expect(table.isfrozen(p)).toBe(true)
			end
		end
	end)
end)
