--!strict
-- Lobby server adapter (f0145): the gate in front of START GAME. A free start due or a play held lets the player go
-- (the lobby charges nothing: the arrival does); otherwise it opens the purchase screen and refuses. A store that
-- cannot be read lets the player go and leaves a pass, so the arrival lets that one game go free (decided with the
-- user, 2026-10-26). One read per player at a time, and presses within PRESS_SECONDS answer from the last read
-- (design review 003 F1). A fresh grant of a play presses START for the player at once. The status goes to the
-- player on PayStatus.
local Players = game:GetService("Players")

local Pay = require("@game/ReplicatedStorage/Shared/Logic/Pay")
local Purchases = require("@game/ReplicatedStorage/Shared/Purchases")

local Paid = {}
Paid.PRESS_SECONDS = 2

type Seen = { at: number, record: Pay.Record }

local asking: { [Player]: boolean } = {} -- a read under way
local kept: { [Player]: Seen } = {} -- the last read, and every grant heard since
local pressFor: ((Player) -> ())? = nil

local function tell(player: Player, record: Pay.Record)
	if player.Parent ~= nil then
		Purchases.remote("PayStatus"):FireClient(player, Purchases.mode(), Pay.status(record, os.time()))
	end
end

-- Whether this press may go. It may yield (the store's read).
function Paid.allow(player: Player): boolean
	if asking[player] then
		return false
	end
	local record: Pay.Record
	local seen = kept[player]
	if seen and os.clock() - seen.at < Paid.PRESS_SECONDS then
		record = seen.record
	else
		asking[player] = true
		local read, ok = Purchases.read(player.UserId)
		asking[player] = nil
		if player.Parent == nil then
			return false
		end
		if not ok then
			Purchases.pass(player.UserId) -- the play place lets this one game go free (decided 2026-10-26)
			return true
		end
		record = read
		kept[player] = { at = os.clock(), record = record }
	end
	tell(player, record)
	local now = Pay.status(record, os.time())
	if now.free or now.plays > 0 then
		return true
	end
	Purchases.ask(player, "play") -- nothing on a closed server (decided 2026-10-26: "Refuse paid play")
	return false
end

local function granted(player: Player, record: Pay.Record)
	kept[player] = { at = os.clock(), record = record }
	tell(player, record)
	local press = pressFor
	if press and player.Parent ~= nil then
		press(player) -- a bought game starts at once
	end
end

-- `press` is Starts' own press (Starts.start(Paid.allow) returns it), used for a press the server makes.
function Paid.start(press: (Player) -> ())
	pressFor = press
	Purchases.start(function(player: Player?, _userId: number, product: Pay.Product, record: Pay.Record)
		if player and product == "play" then
			granted(player, record)
		end
	end)
	local purchase = Purchases.remote("Purchase")
	Purchases.remote("PayStatus")
	purchase.OnServerEvent:Connect(function(player: Player, answer: any)
		if answer == "confirm" then
			local record, fresh = Purchases.testGrant(player, "play", Purchases.guid())
			if record and fresh then
				granted(player, record)
			end
		elseif answer == "cancel" then
			Purchases.cancel(player)
		end
	end)
	Players.PlayerAdded:Connect(function(player: Player)
		-- the line under START GAME from the start (this read is not kept: a press reads for itself)
		local record, ok = Purchases.read(player.UserId)
		if ok then
			tell(player, record)
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		asking[player] = nil
		kept[player] = nil
	end)
end

return Paid
