--!strict
-- f0235 AC4 (wiring): Main starts PelletView with Camera.eye and Camera.pose, before it signals Ready. PelletView takes
-- the eye from those getters only, calling them in its render step: it reads no camera, keeps no hop of its own and
-- sends nothing. What Camera.eye returns is camera.spec's (it runs the real Camera).
local place = require("@tests/lib/place")
local t = require("@tests/lib/t")

local game = place.load()

local function client(name: string): any
	local node: any = game
	for _, part in { "StarterPlayer", "StarterPlayerScripts", "Client", name } do
		node = node and node:FindFirstChild(part)
	end
	t.expect(node ~= nil).toBe(true)
	return node
end

-- a script's source without comments, so a mention in a comment proves nothing
local function source(name: string): string
	local src = string.gsub(client(name).Source, "%-%-[^\n]*", "")
	return src
end

local function has(src: string, needle: string): boolean
	return string.find(src, needle, 1, true) ~= nil
end

return t.spec("f0235 beacon wiring", function(it)
	it("Main starts PelletView with Camera.eye and Camera.pose, before it signals Ready", function()
		local main = source("Main")
		local at = string.find(main, "PelletView%.start%(%s*Camera%.eye%s*,%s*Camera%.pose%s*%)")
		t.expect(at ~= nil).toBe(true)
		local ready = string.find(main, "ready:FireServer(", 1, true)
		t.expect(ready ~= nil and (at :: number) < (ready :: number)).toBe(true)
	end)

	it("PelletView's start takes the two getters and calls both in the render step", function()
		local src = source("PelletView")
		local a, b = string.match(src, "function PelletView%.start%(%s*([%w_]+)[^,]*,%s*([%w_]+)")
		t.expect(a ~= nil and b ~= nil).toBe(true)
		local start = string.find(src, "function PelletView.start(", 1, true) :: number
		for _, getter in { a :: string, b :: string } do
			t.expect(string.find(src, "%f[%w_]" .. getter .. "%(%s*%)", start) ~= nil).toBe(true)
		end
		t.expect(string.find(src, "View.elevated(", start, true) ~= nil).toBe(true)
		t.expect(string.find(src, "View.beacons(", start, true) ~= nil).toBe(true)
	end)

	it("PelletView reads no camera, keeps no hop of its own and sends nothing", function()
		local src = source("PelletView")
		for _, word in { "CurrentCamera", "workspace", "Hop.", "hopped", "FireServer", "Remotes" } do
			t.expect(has(src, word)).toBe(false)
		end
	end)
end)
