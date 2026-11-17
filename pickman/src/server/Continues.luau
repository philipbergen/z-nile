--!strict
-- Game place server adapter (f0145): paid play on arrival and the continue offer. Main hands the arrival this returns
-- to Sessions.made (f0148), which tells it each new session once it exists, of a player still here.
-- On arrival it charges the start once (a free start due, else a held play), takes the lobby's pass and decides with
-- Pay.arrive: a charge, or a write that failed, plays with the continue offer on; a "buy" plays only with the pass
-- (a Studio play counts as holding it: the user's ruling of 2026-11-16, "Play in Studio only"), else its run is
-- refused and the player sent back to the lobby (kicked when that fails).
-- During the offer, "ask" uses a held continue at once, else holds the countdown and asks for a purchase; "decline"
-- ends it. One continue in flight per player; its write holds the countdown, so an ask in time is judged at the ask;
-- a continue that cannot be used after its write (the player left, declined, or the offer ended) is given back.
-- A player's store calls are bounded over time (design review 003 F1): an ask while the countdown is held is
-- dropped, an ask writes nothing while this server knows the player holds none, and at most one write per
-- ASK_SECONDS otherwise. Grants are never bounded.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local TeleportService = game:GetService("TeleportService")

local Pay = require("@game/ReplicatedStorage/Shared/Logic/Pay")
local Purchases = require("@game/ReplicatedStorage/Shared/Purchases")
local Session = require("@game/ReplicatedStorage/Shared/Logic/Session")
local Travel = require("@game/ReplicatedStorage/Shared/Logic/Travel")

local Continues = {}
Continues.ASK_SECONDS = 2 -- at most one continue write per player in this span while what they hold is unknown
Continues.BACK_SECONDS = 10 -- a player sent back who is still here after this is kicked
Continues.BACK_MESSAGE = "Start a game from the lobby."

type Flight = { held: boolean, declined: boolean }

-- Whether this server is a Studio play. Ruled by the user (2026-11-16) on R0118 code review 001 F2, (b) "Play in Studio
-- only": a Studio play, which cannot teleport to the lobby, counts as holding the lobby's pass, so a developer's play
-- of the game place is never sent back. The read is guarded: an error, or no IsStudio at all, is not Studio, and G10
-- holds everywhere else.
local function inStudio(): boolean
	local ok, studio = pcall(function(): any
		return (RunService :: any):IsStudio()
	end)
	return ok and studio == true
end

function Continues.start(session: (Player) -> Session.Session?): (Player, Session.Session) -> ()
	local continueRemote = Purchases.remote("Continue")
	local purchase = Purchases.remote("Purchase")
	local status = Purchases.remote("PayStatus")

	local charged: { [Player]: boolean } = {} -- the arrival charged (once per arrival)
	local sentBack: { [Player]: boolean } = {}
	local flying: { [Player]: Flight } = {} -- a continue's write under way
	local known: { [Player]: number } = {} -- the continues held, as this server last read or wrote them
	local asked: { [Player]: number } = {} -- os.clock() of the last ask that wrote

	-- The mode and what the player holds, on PayStatus. Told on every path that lets the player play, with no status
	-- when the record is unknown (a failed write), so a live client never keeps its "nothing is charged" default
	-- (R0118 code review 001 F1), and after every record this server writes or hears.
	local function tell(player: Player, record: Pay.Record?)
		if player.Parent ~= nil then
			status:FireClient(player, Purchases.mode(), if record then Pay.status(record, os.time()) else nil)
		end
	end

	local function kick(player: Player)
		if sentBack[player] and player.Parent ~= nil then
			player:Kick(Continues.BACK_MESSAGE)
		end
	end

	-- a "buy" arrival without the lobby's pass: the run is refused (over, nothing submitted) and the player sent back
	local function back(player: Player, s: Session.Session)
		sentBack[player] = true
		Session.refuse(s, tostring(player.UserId))
		local lobby = Travel.destination(ServerScriptService:GetAttribute("LobbyPlaceId"))
		if lobby == nil then
			kick(player)
			return
		end
		local ok = pcall(TeleportService.TeleportAsync, TeleportService, lobby, { player })
		if not ok then
			kick(player)
			return
		end
		task.delay(Continues.BACK_SECONDS, kick, player)
	end

	local function arrive(player: Player, s: Session.Session)
		local record, how = Purchases.update(player.UserId, function(r: Pay.Record): (Pay.Record, any)
			local start, nextR = Pay.start(r, os.time())
			return nextR, start
		end)
		if player.Parent == nil then
			return -- left during the write (design review 003 F5)
		end
		if record then
			known[player] = record.continues
		end
		local passed = Purchases.takePass(player.UserId) -- taken on every arrival, Studio's too
		if Pay.arrive(if record then how else nil, passed or inStudio()) == "play" then
			Session.allowOffer(s, tostring(player.UserId))
			tell(player, record)
		else
			back(player, s)
		end
	end

	-- the countdown runs again (a purchase screen closed without a purchase)
	local function release(player: Player)
		local s = session(player)
		if s then
			Session.hold(s, tostring(player.UserId), false)
		end
	end

	-- Use one held continue for the player's offer: "busy" while one is in flight, "none" when nothing was used,
	-- "continued", or "refunded" when one was used but could not be applied.
	local function useOne(player: Player): string
		local s = session(player)
		local id = tostring(player.UserId)
		if s == nil or not Session.offering(s, id) then
			return "none"
		end
		if flying[player] then
			return "busy"
		end
		local flight: Flight = { held = not Session.holding(s, id), declined = false }
		flying[player] = flight
		if flight.held then
			Session.hold(s, id, true) -- judged at the ask: the countdown waits for the write (design review 003 F2)
		end
		local record, used = Purchases.update(player.UserId, function(r: Pay.Record): (Pay.Record, any)
			local ok, nextR = Pay.useContinue(r)
			return nextR, ok
		end)
		flying[player] = nil
		used = record ~= nil and used == true
		if record then
			known[player] = record.continues
		end
		local here = player.Parent ~= nil and session(player) == s and Session.offering(s, id)
		if used and here and not flight.declined then
			Session.continue(s, id)
			tell(player, record :: Pay.Record)
			return "continued"
		end
		local latest = record
		if used then
			-- given back: one more continue, outside the receipts (design review 003 F4)
			local given = Purchases.update(player.UserId, function(r: Pay.Record): (Pay.Record, any)
				return Pay.refund(r), true
			end)
			if given then
				known[player] = given.continues
				latest = given
			end
		end
		if latest then
			tell(player, latest) -- what is held now: none found, or the continue given back
		end
		if flight.held and here then
			Session.hold(s, id, false)
		end
		if flight.declined then
			Session.decline(s, id)
		end
		return if used then "refunded" else "none"
	end

	local function ask(player: Player, s: Session.Session, id: string)
		local last = asked[player]
		-- no write when none is held as far as this server knows, or when an ask wrote a moment ago
		local quiet = known[player] == 0 or (last ~= nil and os.clock() - last < Continues.ASK_SECONDS)
		if not quiet then
			asked[player] = os.clock()
			if useOne(player) ~= "none" then
				return
			end
		end
		if
			Session.offering(s, id)
			and Purchases.canBuy() -- a closed server sells nothing (decided 2026-10-26: "Refuse paid play")
		then
			Session.hold(s, id, true)
			Purchases.ask(player, "continue")
		end
	end

	continueRemote.OnServerEvent:Connect(function(player: Player, answer: any)
		local s = session(player)
		local id = tostring(player.UserId)
		if s == nil or not Session.offering(s, id) then
			return
		end
		if answer == "decline" then
			local flight = flying[player]
			if flight then
				flight.declined = true
			else
				Session.decline(s, id)
			end
		elseif
			answer == "ask"
			and not Session.holding(s, id) -- a screen is open (or a receipt awaited): the ask is already being answered
		then
			ask(player, s, id)
		end
	end)

	-- a grant this server heard: what it knew is stale; during the offer the continue is used at once
	-- what useOne did with it: "busy", "none", "continued" or "refunded"
	local function heard(player: Player, record: Pay.Record): string
		known[player] = nil -- a grant reached this server: what it last knew is stale
		tell(player, record) -- the line shows the continue held, also outside the offer (R0118 code review 001 F1)
		return useOne(player)
	end

	Purchases.start(function(player: Player?, _userId: number, product: Pay.Product, record: Pay.Record)
		if player and product == "continue" then
			heard(player, record)
		end
	end)

	purchase.OnServerEvent:Connect(function(player: Player, answer: any)
		if answer == "confirm" then
			local record, fresh, took = Purchases.testGrant(player, "continue", Purchases.guid())
			-- The screen this server opened answered, and its continue was not applied: its grant was not written
			-- (R0118 code review 001 F3), or it was written and the continue's own write then failed (R0118 final
			-- review 001 F2; the continue stays held for the next ask). Nothing more will end the hold the ask set,
			-- so the countdown runs again, as a cancel does. A flight under way ("busy") ends its own hold, and a
			-- confirm with no screen open takes nothing and leaves any other hold (a flight's, a receipt's).
			local done = if record and fresh then heard(player, record) else "none"
			if took and done == "none" then
				release(player)
			end
		elseif answer == "cancel" then
			if Purchases.cancel(player) then
				release(player)
			end
		end
	end)

	MarketplaceService.PromptProductPurchaseFinished:Connect(
		function(userId: number, productId: number, bought: boolean)
			local player = Players:GetPlayerByUserId(userId)
			if player and Purchases.product(productId) == "continue" then
				local s = session(player)
				if s and Session.offering(s, tostring(userId)) then
					if bought then
						Session.awaitReceipt(s, tostring(userId)) -- Roblox does not order the close and the receipt
					else
						release(player)
					end
				end
			end
		end
	)

	TeleportService.TeleportInitFailed:Connect(function(player: Player)
		kick(player)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		charged[player] = nil
		sentBack[player] = nil
		known[player] = nil
		asked[player] = nil
	end)

	return function(player: Player, s: Session.Session)
		if charged[player] then
			return
		end
		charged[player] = true
		task.spawn(function()
			arrive(player, s)
		end)
	end
end

return Continues
