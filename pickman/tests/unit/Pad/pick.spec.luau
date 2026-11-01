--!strict
-- Pad: the controller's pick (f0126).
local Pad = require("@logic/Pad")
local t = require("@tests/lib/t")

return t.spec("Pad pick", function(it)
	it("Y / triangle is the pick, and no other button is", function()
		t.expect(Pad.action("ButtonY")).toBe("Pick")
		for key, action in Pad.BUTTONS do
			if key ~= "ButtonY" then
				t.expect(action == "Pick").toBe(false)
			end
		end
	end)
end)
