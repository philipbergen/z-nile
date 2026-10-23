--!strict
-- c0129 AC1: the game place has no play again since f0065, so the Submits adapter has no play-again hook.
-- The real Submits source runs here on a small stub `game` (BindToClose only) with a stub HiscoreStore: its
-- public table is exactly ready, step, pending and close. It never references Hiscores.onAgain, and no
-- server source defines or calls a play-again hook any more. (AC2, onAgain staying, is onagain.spec.)
local Hiscores = require("@logic/Hiscores")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local t = require("@tests/lib/t")

local SUBMITS = "src/server/Submits.luau"
local LOGIC = "@game/ReplicatedStorage/Shared/Logic/"

local function source(path: string): string
	return string.gsub(fs.readFile(path), "%-%-[^\n]*", "")
end

local function loadSubmits(): any
	local store = {
		submit = function() end,
		pending = function(): number
			return 0
		end,
	}
	local modules: { [string]: any } = { [LOGIC .. "Hiscores"] = Hiscores, ["./HiscoreStore"] = store }
	local env = {
		game = { BindToClose = function(_: any, _fn: () -> ()) end },
		task = {
			wait = function(seconds: number?): number
				return seconds or 0
			end,
		},
		require = function(spec: string): any
			local found = modules[spec]
			assert(found ~= nil, `stub: Submits requires "{spec}", which this spec does not model`)
			return found
		end,
	}
	return luau.load(fs.readFile(SUBMITS), { environment = env, debugName = SUBMITS })()
end

return t.spec("c0129 no play-again hook in Submits", function(it)
	it("AC1: Submits exports exactly ready, step, pending and close", function()
		local names = {}
		for name in loadSubmits() do
			table.insert(names, name)
		end
		table.sort(names)
		t.expect(names).toEqual({ "close", "pending", "ready", "step" })
	end)

	it("AC1: the Submits source never calls Hiscores.onAgain", function()
		t.expect(string.find(source(SUBMITS), "onAgain", 1, true) ~= nil).toBe(false)
	end)

	it(
		'AC1: no server source defines or calls an again hook: .again(, :again(, .again = or ["again"]',
		function()
			local found = {}
			for _, path in fs.readDir("src/server") do
				if string.sub(path, -5) == ".luau" then
					local src = source("src/server/" .. path)
					for _, pattern in { "[%.:]again%s*%(", "%.again%s*=", '%[%s*"again"%s*%]' } do
						if string.find(src, pattern) ~= nil then
							table.insert(found, path)
							break
						end
					end
				end
			end
			t.expect(table.concat(found, ", ")).toBe("")
		end
	)
end)
