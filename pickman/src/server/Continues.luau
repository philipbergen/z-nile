--!strict
-- Game place server adapter (f0145, on the arcade library since c0202): paid play on arrival and the continue offer.
-- Main hands the arrival this returns to Sessions.made (f0148), which tells it each new session once it exists, of a
-- player still here. Pickman is the library's title "pickman": its records, its products and its pass are the
-- library's (Wallet, Receipts), installed here once.
-- On arrival the library's Wallet.arrive charges the start once (a free start due, else a held play, whoever sold it:
-- the lobby or the portal) and takes the pass (the lobby's or the portal's, `pickman/<user id>`): a charge, a claim
-- that failed, or a pass plays with the continue offer on, and so does a Studio play (the user's ruling of
-- 2026-11-16, "Play in Studio only", kept in pickman: 2026-11-17); anything else has its run refused and the player
-- sent back to LobbyPlaceId (kicked when that fails).
-- During the offer, "ask" uses a held revive at once (Wallet.useRevive), else holds the countdown and opens the revive
-- product (Receipts.ask); "decline" ends it. One continue in flight per player; its write holds the countdown, so an
-- ask in time is judged at the ask; a revive that cannot be used after its write (the player left, declined, or the
-- offer ended) is given back (Wallet.refund). A revive granted during the offer is used at once. A test confirm whose
-- revive was not used releases the countdown at once (R0118 final review 001 F2); live, the receipt wait holds it, and
-- a use the library could not make then is tried once more after its USE_SECONDS.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local TeleportService = game:GetService("TeleportService")

local PaidPlay = require("@game/ReplicatedStorage/Arcade/Logic/PaidPlay")
local Receipts = require("@game/ServerStorage/Arcade/Receipts")
local Session = require("@game/ReplicatedStorage/Shared/Logic/Session")
local Travel = require("@game/ReplicatedStorage/Shared/Logic/Travel")
local Wallet = require("@game/ServerStorage/Arcade/Wallet")

local Continues = {}
Continues.TITLE = "pickman" -- the library's catalog name for Pickman
Continues.BACK_SECONDS = 10 -- a player sent back who is still here after this is kicked
Continues.BACK_MESSAGE = "Start a game from the lobby."

type Flight = { held: boolean, declined: boolean }

-- the remote of that name under ReplicatedStorage.Remotes, made at run time (the place file's list stays)
local function remote(name: string): RemoteEvent
	local folder = ReplicatedStorage:WaitForChild("Remotes")
	local found = folder:FindFirstChild(name)
	if found then
		return found :: RemoteEvent
	end
	local made = Instance.new("RemoteEvent")
	made.Name = name
	made.Parent = folder
	return made
end

-- Whether this server is a Studio play. Ruled by the user (2026-11-16) on R0118 code review 001 F2, (b) "Play in Studio
-- only", and kept in pickman when it moved onto the library (2026-11-17, "Keep it in pickman"): a Studio play, which
-- cannot teleport to the lobby, plays, so a developer's play of the game place is never sent back. The read is
-- guarded: an error, or no IsStudio at all, is not Studio, and G10 holds everywhere else.
local function inStudio(): boolean
	local ok, studio = pcall(function(): any
		return (RunService :: any):IsStudio()
	end)
	return ok and studio == true
end

function Continues.start(session: (Player) -> Session.Session?): (Player, Session.Session) -> ()
	local continueRemote = remote("Continue")
	local status = remote("PayStatus")

	local charged: { [Player]: boolean } = {} -- the arrival charged (once per arrival)
	local sentBack: { [Player]: boolean } = {}
	local flying: { [Player]: Flight } = {} -- a continue's write under way

	-- The mode, and what the player holds, on PayStatus (R0118 code review 001 F1): the mode is told on every path that
	-- lets the player play, so a live client never keeps its "nothing is charged" default, with no status when the
	-- record is unknown (a claim that failed: nothing is read), and what they hold after every record this server
	-- writes or hears, from the record the library saw (a store read only when it saw none).
	local function tellMode(player: Player)
		if player.Parent ~= nil then
			status:FireClient(player, Wallet.mode(Continues.TITLE), nil)
		end
	end
	local function tell(player: Player)
		if player.Parent == nil then
			return
		end
		local record = Wallet.read(player, Continues.TITLE)
		if record then
			status:FireClient(player, Wallet.mode(Continues.TITLE), PaidPlay.status(record, os.time()))
		end
	end

	local function kick(player: Player)
		if sentBack[player] and player.Parent ~= nil then
			player:Kick(Continues.BACK_MESSAGE)
		end
	end

	-- an arrival with nothing to pay with and no pass: the run is refused (over, nothing submitted), the player sent back
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
		local verdict, start = Wallet.arrive(player, Continues.TITLE) -- the pass is taken on every arrival, Studio's too
		if player.Parent == nil then
			return -- left during the claim (f0145 design review 003 F5)
		end
		-- the literal union widens across a require (f0201 E6): compared as a string
		if (verdict :: string) == "play" or inStudio() then
			Session.allowOffer(s, tostring(player.UserId))
			if start ~= nil then
				tell(player)
			else
				tellMode(player) -- the claim failed (G10): the mode, nothing read
			end
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

	-- Use one held revive for the player's offer: "none" outside the offer, "busy" while one is in flight, "empty" when
	-- none is held (known from the record seen, or from a write that found none), "unknown" when the library could not
	-- tell (a use within its USE_SECONDS, the store failing), "continued", "refunded" when one was used but could not
	-- be applied, or "declined" when none was used and the player declined during the write (the decline is applied
	-- and no purchase screen follows: d0412). A continue and a give-back are told here, after the run's state changes;
	-- "empty" is told by the caller, after what it does next (design review 002 F3: a tell may read the store).
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
			Session.hold(s, id, true) -- judged at the ask: the countdown waits for the write (f0145 review 003 F2)
		end
		local used = Wallet.useRevive(player, Continues.TITLE)
		flying[player] = nil
		local here = player.Parent ~= nil and session(player) == s and Session.offering(s, id)
		if used == true and here and not flight.declined then
			Session.continue(s, id)
			tell(player)
			return "continued"
		end
		if used == true then
			-- given back: one more revive, outside the receipts (f0145 review 003 F4)
			Wallet.refund(player, Continues.TITLE, "revive")
		end
		if flight.held and here then
			Session.hold(s, id, false)
		end
		if flight.declined then
			Session.decline(s, id)
		end
		if used == true then
			tell(player) -- the revive given back, told last
			return "refunded"
		end
		if flight.declined then
			return "declined" -- the decline is applied: no purchase screen follows (d0412)
		end
		return if used == false then "empty" else "unknown"
	end

	local function ask(player: Player, s: Session.Session, id: string)
		local result = useOne(player)
		if result == "continued" or result == "refunded" or result == "declined" or result == "busy" then
			return
		end
		-- nothing held (or nothing known): the revive product; a closed title opens nothing and holds nothing
		if Session.offering(s, id) and Receipts.ask(player, Continues.TITLE, "revive") then
			Session.hold(s, id, true)
		end
		if result == "empty" then
			tell(player) -- none held, told after the screen opened
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

	-- A revive granted for a player here: the line shows it, also outside the offer (R0118 code review 001 F1), and
	-- during the offer it is used at once. In test mode the grant is the confirm's own answer, so a use that did not
	-- continue the run releases the countdown at once (R0118 final review 001 F2; the revive stays held for the next
	-- ask). Live, the receipt wait holds the countdown, and a use the library could not make then is tried once more
	-- after its USE_SECONDS.
	local function heard(player: Player)
		tell(player)
		local result = useOne(player)
		if Wallet.mode(Continues.TITLE) == "test" then
			if result == "none" or result == "empty" or result == "unknown" then
				release(player)
			end
		elseif result == "unknown" then
			task.delay(Wallet.USE_SECONDS, function()
				if player.Parent ~= nil and useOne(player) == "empty" then
					tell(player)
				end
			end)
		end
		if result == "empty" then
			tell(player)
		end
	end

	Receipts.start({
		granted = function(player: Player, name: string, kind: PaidPlay.Kind)
			if name == Continues.TITLE and kind == "revive" then
				heard(player)
			end
		end,
		-- a purchase screen of Pickman's revive closed: not bought (a cancel, Roblox's screen closed, or a test confirm
		-- whose grant was not written: R0118 code review 001 F3) the countdown runs again; bought, it waits for the
		-- receipt (Roblox does not order the close and the receipt; a test confirm's grant follows at once)
		closed = function(player: Player, name: string, kind: PaidPlay.Kind, bought: boolean)
			if name ~= Continues.TITLE or kind ~= "revive" then
				return
			end
			local s = session(player)
			if s and Session.offering(s, tostring(player.UserId)) then
				if bought then
					Session.awaitReceipt(s, tostring(player.UserId))
				else
					release(player)
				end
			end
		end,
	})

	TeleportService.TeleportInitFailed:Connect(function(player: Player)
		kick(player)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		charged[player] = nil
		sentBack[player] = nil
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
