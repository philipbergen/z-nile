--!strict
-- Receipts (f0201): the purchases of every title, installed by every place (E4). ProcessReceipt grants a known
-- product's receipt once into its own title's record, by user id, wherever Roblox processes it, and answers
-- PurchaseGranted only after the write; an unknown product or a failed write answers NotProcessedYet. `ask` opens
-- the purchase screen: Roblox's in live mode, the test purchase screen in test mode (which charges nothing), none in
-- closed mode. A client only answers a test screen this server opened for it; it never names a product, a price or a
-- receipt. Fresh grants and closed screens are handed to the place.
local PaidPlay = require("@game/ReplicatedStorage/Arcade/Logic/PaidPlay")
local Prices = require("@game/ReplicatedStorage/Arcade/Prices")
local Wallet = require("./Wallet")

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

export type Handlers = {
	granted: ((player: any, name: string, kind: PaidPlay.Kind) -> ())?, -- a new grant for a player on this server
	closed: ((player: any, name: string, kind: PaidPlay.Kind, bought: boolean) -> ())?, -- a purchase screen closed
}

local Receipts = {}

Receipts.FOLDER = "ArcadePaidPlay" -- ReplicatedStorage folder made at start
Receipts.REMOTE = "TestPurchase" -- its RemoteEvent: "open" to a client, "confirm" or "cancel" back

type Pending = { name: string, kind: PaidPlay.Kind }

local started = false
local on: Handlers = {}
local remote: any = nil
local pending: { [any]: Pending } = {}

local function present(userId: any): any
	if type(userId) ~= "number" then
		return nil
	end
	return Players:GetPlayerByUserId(userId)
end

local function granted(player: any, name: string, kind: PaidPlay.Kind)
	local fn = on.granted
	if fn ~= nil and player.Parent ~= nil then
		task.spawn(fn, player, name, kind)
	end
end

local function closed(player: any, name: string, kind: PaidPlay.Kind, bought: boolean)
	local fn = on.closed
	if fn ~= nil and player.Parent ~= nil then
		task.spawn(fn, player, name, kind, bought)
	end
end

local function process(info: any): any
	local product = Wallet.config().products[info.ProductId]
	local purchaseId = info.PurchaseId
	if
		product == nil
		or type(purchaseId) ~= "string"
		or purchaseId == ""
		or type(info.PlayerId) ~= "number"
	then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local written, fresh = Wallet.grant(info.PlayerId, product.name, product.kind, purchaseId)
	if not written then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if fresh and Wallet.mode(product.name) ~= "test" then
		local player = present(info.PlayerId)
		if player ~= nil then
			granted(player, product.name, product.kind)
		end
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

local function answer(player: any, what: any)
	local p = pending[player]
	if p == nil or (what ~= "confirm" and what ~= "cancel") then
		return
	end
	pending[player] = nil
	if what == "cancel" then
		closed(player, p.name, p.kind, false)
		return
	end
	local written = Wallet.testGrant(player, p.name, p.kind)
	closed(player, p.name, p.kind, written)
	if written then
		granted(player, p.name, p.kind)
	end
end

-- Installs the purchases on this server, once: a second call does nothing and answers false.
function Receipts.start(handlers: Handlers?): boolean
	if started then
		return false
	end
	started = true
	on = handlers or {}
	local config = Wallet.config()
	local folder = ReplicatedStorage:FindFirstChild(Receipts.FOLDER)
	if folder == nil then
		folder = Instance.new("Folder")
		folder.Name = Receipts.FOLDER
		folder.Parent = ReplicatedStorage
	end
	remote = folder:FindFirstChild(Receipts.REMOTE)
	if remote == nil then
		remote = Instance.new("RemoteEvent")
		remote.Name = Receipts.REMOTE
		remote.Parent = folder
	end
	remote.OnServerEvent:Connect(answer)
	MarketplaceService.ProcessReceipt = process
	MarketplaceService.PromptProductPurchaseFinished:Connect(
		function(userId: any, productId: any, bought: any)
			local product = config.products[productId]
			local player = present(userId)
			if product ~= nil and player ~= nil then
				closed(player, product.name, product.kind, bought == true)
			end
		end
	)
	Players.PlayerRemoving:Connect(function(player: any)
		pending[player] = nil
	end)
	return true
end

-- Opens a purchase screen of a title's product for a player: Roblox's in live mode, the test screen in test mode
-- (not while one is open for them), none in closed mode. Answers whether a screen opened.
function Receipts.ask(player: any, name: string, kind: PaidPlay.Kind): boolean
	if not started then
		error("Receipts: start() first", 2)
	end
	local t = Wallet.config().titles[name]
	if t == nil then
		error(`Receipts: no title "{tostring(name)}" in the catalog`, 2)
	end
	if t.mode == "live" then
		MarketplaceService:PromptProductPurchase(player, if kind == "play" then t.ids.play else t.ids.revive)
		return true
	end
	if t.mode == "test" and pending[player] == nil then
		pending[player] = { name = name, kind = kind }
		remote:FireClient(player, "open", PaidPlay.testLines(t.entry.title, kind, Prices))
		return true
	end
	return false
end

return Receipts
