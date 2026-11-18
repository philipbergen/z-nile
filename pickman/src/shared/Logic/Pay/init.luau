--!strict
-- Pay: paid play (f0145). One free start per player per rolling hour, then a play bought and held, else a purchase;
-- a purchase is granted once by its receipt id; a held continue is used once. The mode decides whether anything is
-- charged: "live" only for exactly "live" with both product ids, "closed" for live with an id missing or bad (it
-- sells nothing and grants nothing free), anything else "test" (the screens show, nothing is charged). Pure: the
-- store, the clock and the purchases come in as values. Nothing here mutates the record it is given.

export type Mode = "live" | "test" | "closed"
export type Product = "play" | "continue"
export type Record = { free: number?, plays: number, continues: number, receipts: { string } }
export type Start = "free" | "credit" | "buy"
export type Products = { play: number?, continue: number? }
export type Status = { free: boolean, nextFree: number?, plays: number, continues: number }

local Pay = {}
Pay.FREE_SECONDS = 3600 -- G2: a rolling hour from the latest free start
Pay.PRICE = 1 -- Robux a play or a continue (the products carry the real price)
Pay.RECEIPTS_KEPT = 50 -- receipt ids remembered, for granting each once
Pay.STORE = "PaidPlay" -- the live records (closed mode's too), keyed by user id
Pay.TEST_STORE = "PaidPlayTest" -- test mode's records: test credits never reach a live record

local FREE: Start = "free"
local CREDIT: Start = "credit"
local BUY: Start = "buy"

local function whole(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge and x == math.floor(x)
end

local function count(x: any): number
	return if whole(x) and x > 0 then x else 0
end

local function id(x: any): boolean
	return whole(x) and x > 0
end

local function copy(r: Record): Record
	return { free = r.free, plays = r.plays, continues = r.continues, receipts = table.clone(r.receipts) }
end

function Pay.mode(raw: any, products: Products?): Mode
	if raw ~= "live" then
		return "test"
	end
	local p: Products = products or {}
	return if id(p.play) and id(p.continue) then "live" else "closed"
end

function Pay.store(mode: Mode): string
	return if mode == "test" then Pay.TEST_STORE else Pay.STORE
end

function Pay.arrive(how: Start?, passed: boolean): "play" | "back"
	if how == nil or how == "free" or how == "credit" or passed then
		return "play"
	end
	return "back"
end

function Pay.record(raw: any): Record
	local t: { [any]: any } = if type(raw) == "table" then raw else {}
	local receipts: { string } = {}
	if type(t.receipts) == "table" then
		for _, r in t.receipts do
			if type(r) == "string" and r ~= "" then
				table.insert(receipts, r)
			end
		end
	end
	return {
		free = if whole(t.free) then t.free else nil,
		plays = count(t.plays),
		continues = count(t.continues),
		receipts = receipts,
	}
end

function Pay.freeDue(r: Record, now: number): boolean
	if not whole(now) then
		return false
	end
	if r.free == nil then
		return true
	end
	return now - (r.free :: number) >= Pay.FREE_SECONDS
end

function Pay.status(r: Record, now: number): Status
	local free = Pay.freeDue(r, now)
	return {
		free = free,
		nextFree = if free or r.free == nil then nil else (r.free :: number) + Pay.FREE_SECONDS,
		plays = r.plays,
		continues = r.continues,
	}
end

function Pay.start(r: Record, now: number): (Start, Record)
	local nextR = copy(r)
	if Pay.freeDue(r, now) then
		nextR.free = now
		return FREE, nextR
	elseif r.plays > 0 then
		nextR.plays -= 1
		return CREDIT, nextR
	end
	return BUY, r
end

function Pay.product(productId: any, products: Products): Product?
	if not whole(productId) then
		return nil
	end
	if products.play ~= nil and productId == products.play then
		return "play"
	elseif products.continue ~= nil and productId == products.continue then
		return "continue"
	end
	return nil
end

function Pay.grant(r: Record, product: Product, receiptId: string): (Record, boolean)
	if type(receiptId) ~= "string" or receiptId == "" or table.find(r.receipts, receiptId) ~= nil then
		return r, false
	end
	local nextR = copy(r)
	if product == "play" then
		nextR.plays += 1
	else
		nextR.continues += 1
	end
	table.insert(nextR.receipts, receiptId)
	while #nextR.receipts > Pay.RECEIPTS_KEPT do
		table.remove(nextR.receipts, 1)
	end
	return nextR, true
end

function Pay.useContinue(r: Record): (boolean, Record)
	if r.continues < 1 then
		return false, r
	end
	local nextR = copy(r)
	nextR.continues -= 1
	return true, nextR
end

-- a continue given back (bought or held, but not used): one more held, outside the receipts, since nothing retries
-- a refund and it must not push a real purchase's id out of the ones kept (design review 003 F4)
function Pay.refund(r: Record): Record
	local nextR = copy(r)
	nextR.continues += 1
	return nextR
end

return Pay
