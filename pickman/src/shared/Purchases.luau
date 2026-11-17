--!strict
-- Shared server adapter (f0145): the paid-play plumbing both places' servers use. Required only by server scripts
-- (no client requires it: the store and the purchases are the server's). The mode and the product ids are attributes
-- the publisher sets on ServerScriptService (PaidPlay, PlayProductId, ContinueProductId), read at each call. A
-- player's record is one UpdateAsync of Pay's transforms in the mode's own store, each answer the transform's last
-- call's (UpdateAsync may call it again on a newer value). ProcessReceipt grants a receipt once and answers
-- PurchaseGranted only after the write. Test mode opens our own test screen instead of Roblox's, and only a screen
-- this server opened can be confirmed. The lobby's pass (a player let in on a failed read) is a MemoryStore entry.
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Pay = require("@game/ReplicatedStorage/Shared/Logic/Pay")

local Purchases = {}
Purchases.PASS_MAP = "PaidPlayPass"
Purchases.PASS_SECONDS = 300 -- a pass outlives the teleport, not the hour

export type Granted = (player: Player?, userId: number, product: Pay.Product, record: Pay.Record) -> ()

local pending: { [Player]: Pay.Product } = {} -- the test screen this server opened for each player
local installed = false

local function products(): Pay.Products
	return {
		play = ServerScriptService:GetAttribute("PlayProductId"),
		continue = ServerScriptService:GetAttribute("ContinueProductId"),
	}
end

function Purchases.mode(): Pay.Mode
	return Pay.mode(ServerScriptService:GetAttribute("PaidPlay"), products())
end

-- false on a closed server: nothing can be bought there
function Purchases.canBuy(): boolean
	return Purchases.mode() ~= "closed"
end

function Purchases.product(productId: any): Pay.Product?
	return Pay.product(productId, products())
end

local function store(): DataStore
	return DataStoreService:GetDataStore(Pay.store(Purchases.mode()))
end

-- One write of `change` on the player's record: the record written and the change's answer, both from the
-- transform's last call; nil when the store failed (nothing is known then).
function Purchases.update(userId: number, change: (Pay.Record) -> (Pay.Record, any)): (Pay.Record?, any)
	local answer: any, written: Pay.Record? = nil, nil
	local ok = pcall(function()
		store():UpdateAsync(tostring(userId), function(old: any): any
			local nextR, a = change(Pay.record(old))
			answer, written = a, nextR
			return nextR
		end)
	end)
	if not ok then
		return nil, nil
	end
	return written, answer
end

-- The player's record as stored, and whether the read worked.
function Purchases.read(userId: number): (Pay.Record, boolean)
	local raw: any = nil
	local ok = pcall(function()
		raw = store():GetAsync(tostring(userId))
	end)
	return Pay.record(raw), ok
end

-- A receipt's credit, once by its id: the record (nil when the write failed) and whether this grant is new.
function Purchases.grant(userId: number, product: Pay.Product, receiptId: string): (Pay.Record?, boolean)
	local record, fresh = Purchases.update(userId, function(r: Pay.Record): (Pay.Record, any)
		return Pay.grant(r, product, receiptId)
	end)
	return record, fresh == true
end

-- A test screen's confirmation: in test mode only, and only for the screen this server opened for that player and
-- product (forgotten on a confirm, a cancel or a leave); granted under a fresh test id. The third answer says
-- whether this confirm took an open screen, so a caller can tell a failed write (true, record nil) from a confirm
-- with no screen (false).
function Purchases.testGrant(
	player: Player,
	product: Pay.Product,
	guid: string
): (Pay.Record?, boolean, boolean)
	if Purchases.mode() ~= "test" or pending[player] ~= product then
		return nil, false, false
	end
	pending[player] = nil
	local record, fresh = Purchases.grant(player.UserId, product, "test:" .. guid)
	return record, fresh, true
end

-- The player's test screen closed without buying; true when one was open.
function Purchases.cancel(player: Player): boolean
	local was = pending[player] ~= nil
	pending[player] = nil
	return was
end

-- The remote of this feature, made at run time under ReplicatedStorage.Remotes (the place files' lists stay).
function Purchases.remote(name: string): RemoteEvent
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

-- Ask the player to buy `product`: Roblox's purchase screen in live mode, our test screen in test mode, nothing on
-- a closed server.
function Purchases.ask(player: Player, product: Pay.Product)
	local mode = Purchases.mode()
	if mode == "closed" then
		return
	elseif mode == "live" then
		local id = products()[product]
		if id ~= nil then
			MarketplaceService:PromptProductPurchase(player, id)
		end
	else
		pending[player] = product
		Purchases.remote("Purchase"):FireClient(player, product)
	end
end

local function passMap(): MemoryStoreHashMap
	return MemoryStoreService:GetHashMap(Purchases.PASS_MAP)
end

-- The lobby let this player in on a failed read: their arrival plays that game free.
function Purchases.pass(userId: number)
	pcall(function()
		passMap():SetAsync(tostring(userId), true, Purchases.PASS_SECONDS)
	end)
end

-- An arrival takes the pass, whatever its start: whether there was one. A map that cannot be read counts as a pass
-- (decided with the user, 2026-10-31: "Let all of them play").
function Purchases.takePass(userId: number): boolean
	local had: any = nil
	local ok = pcall(function()
		local map = passMap()
		had = map:GetAsync(tostring(userId))
		if had ~= nil then
			map:RemoveAsync(tostring(userId))
		end
	end)
	return not ok or had == true
end

-- Install ProcessReceipt (once per server): an unknown product or a failed write answers NotProcessedYet and grants
-- nothing; otherwise PurchaseGranted after the write, and a fresh grant (not a retried one) is handed to `granted`.
function Purchases.start(granted: Granted)
	if installed then
		return
	end
	installed = true
	MarketplaceService.ProcessReceipt = function(info: any): Enum.ProductPurchaseDecision
		-- the literal union widens across a require (the Roblox type pass), so the product is cast back here
		local product = Purchases.product(info.ProductId) :: Pay.Product?
		if product == nil or type(info.PurchaseId) ~= "string" then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		local kind: Pay.Product = product :: any
		local record, fresh = Purchases.grant(info.PlayerId, kind, info.PurchaseId)
		if record == nil then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		if fresh then
			granted(Players:GetPlayerByUserId(info.PlayerId), info.PlayerId, kind, record)
		end
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		pending[player] = nil
	end)
end

-- a fresh id for a test grant
function Purchases.guid(): string
	return HttpService:GenerateGUID(false)
end

return Purchases
