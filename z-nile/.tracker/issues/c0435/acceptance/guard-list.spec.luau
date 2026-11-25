--!strict
-- c0435 AC6: the light path's protected-file list holds every engine file that decides what is light, the easy path's
-- included: a change to any of them is never light, so it gets the separate code review. easy-path.spec pins seven of
-- them and light-path.spec's N2 case pins light and lightgit; this spec pins the whole set c0435 relies on, lightready
-- included, which no other spec names. A pure read of light.PROTECTED.
local light = require("@znile/engine/light")
local t = require("@tests/lib/t")

local FILES = {
	"z-nile/engine/easy.luau",
	"z-nile/engine/light.luau",
	"z-nile/engine/lightgit.luau",
	"z-nile/engine/lightready.luau",
	"z-nile/engine/readycheck.luau",
	"z-nile/engine/readyfacts.luau",
	"z-nile/engine/workread.luau",
	"z-nile/engine/rounds.luau",
	"z-nile/engine/models.luau",
	"z-nile/engine/modelcmd.luau",
	"z-nile/engine/publish.luau",
	"z-nile/engine/contract.luau",
}

return t.spec("c0435 the guard list holds the files that decide what is light", function(it)
	it("every file of the easy path's and the light path's rules is in light.PROTECTED", function()
		local missing: { string } = {}
		for _, path in FILES do
			if not table.find(light.PROTECTED.files, path) then
				table.insert(missing, path)
			end
		end
		t.expect(table.concat(missing, ", ")).toBe("")
	end)

	it("a .models.toml anywhere, a tracker folder's included, makes a diff not light", function()
		local _, why = light.judgeDiff("1\t0\tz-nile/.tracker/issues/c0001/.models.toml")
		t.expect(why ~= nil).toBe(true)
	end)
end)
