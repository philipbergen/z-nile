--!strict
-- PaidPlay (f0201): the cost model every arcade title shares. One free start per rolling hour per title and player,
-- then a held play (bought for 1 R$), else a purchase; a revive (3 new lives) for 1 R$; a receipt granted once; test
-- mode charges nothing. Pure: the clock, the catalog and the attribute reads come in as parameters, and nothing here
-- mutates a record it is given.

export type Mode = "live" | "test" | "closed"
export type Kind = "play" | "revive"
export type Start = "free" | "credit" | "buy"
export type Verdict = "play" | "back"
-- one player's record in one title, as stored (key: the user id)
export type Record = { free: number?, plays: number, revives: number, receipts: { string } }
-- the stored shape: f0145's record (its `continues` are the revives)
export type Stored = { free: number?, plays: number, continues: number, receipts: { string } }
export type Status = { free: boolean, nextFree: number?, plays: number, revives: number }
-- a title's catalog entry: its name, the title its screens print, its two stores and the attribute names of its ids
export type Entry = {
	name: string,
	title: string,
	store: string,
	testStore: string,
	play: string,
	revive: string,
}
export type Ids = { play: number?, revive: number? }
export type Product = { name: string, kind: Kind }
export type Title = { entry: Entry, mode: Mode, ids: Ids }
export type Config = { titles: { [string]: Title }, products: { [number]: Product } }
export type Prices = { struck: string, price: string, sale: string, revive: string }

local PaidPlay = {}

PaidPlay.FREE_SECONDS = 3600 -- the free start's rolling hour
PaidPlay.PRICE = 1 -- R$ a play and a revive; the products carry it
PaidPlay.RECEIPTS_KEPT = 50 -- receipt ids remembered per record, for granting each once
PaidPlay.LIVE = "live" -- the PaidPlay attribute's one live value
PaidPlay.TEST_NOTE = "TEST PURCHASE: NOTHING IS CHARGED"
PaidPlay.KIND_TEXT = table.freeze({ play = "1 GAME", revive = "REVIVE: 3 NEW LIVES" })
PaidPlay.TEST_KEYS = table.freeze({
	confirm = table.freeze({ "Return", "KeypadEnter", "ButtonA" }),
	cancel = table.freeze({ "Backspace", "ButtonB" }),
})

local function whole(x: any): number?
	if type(x) == "number" and x == x and x >= 0 and x < math.huge and x == math.floor(x) then
		return x
	end
	return nil
end

local function id(x: any): number?
	local n = whole(x)
	if n and n > 0 then
		return n
	end
	return nil
end

local function copy(r: Record): Record
	return { free = r.free, plays = r.plays, revives = r.revives, receipts = table.clone(r.receipts) }
end

-- The mode of one title on a server: "live" only for exactly PaidPlay.LIVE with both ids; "live" with an id missing
-- is "closed" (it sells nothing and grants nothing free); anything else is "test".
function PaidPlay.mode(raw: any, ids: Ids): Mode
	if raw ~= PaidPlay.LIVE then
		return "test"
	end
	if ids.play and ids.revive then
		return "live"
	end
	return "closed"
end

-- The store a mode keeps its records in: test mode's own, else the live one (closed included).
function PaidPlay.store(entry: Entry, mode: Mode): string
	if mode == "test" then
		return entry.testStore
	end
	return entry.store
end

-- Every title's mode and ids, and the map from a product id to its title and kind. An id that two products share
-- belongs to neither. `read` answers an attribute's value.
function PaidPlay.configure(catalog: { Entry }, raw: any, read: (string) -> any): Config
	local names: { [string]: boolean } = {}
	local found: { { entry: Entry, ids: Ids } } = {}
	local uses: { [number]: number } = {}
	for _, entry in catalog do
		assert(
			type(entry.name) == "string" and string.match(entry.name, "^%l+$"),
			"PaidPlay: a name is lowercase letters"
		)
		assert(not names[entry.name], `PaidPlay: {entry.name} twice in the catalog`)
		names[entry.name] = true
		local play, revive = id(read(entry.play)), id(read(entry.revive))
		if play then
			uses[play] = (uses[play] or 0) + 1
		end
		if revive then
			uses[revive] = (uses[revive] or 0) + 1
		end
		local ids: Ids = { play = play, revive = revive }
		table.insert(found, { entry = entry, ids = ids })
	end
	local config: Config = { titles = {}, products = {} }
	for _, f in found do
		local ids: Ids = {
			play = if f.ids.play and uses[f.ids.play] == 1 then f.ids.play else nil,
			revive = if f.ids.revive and uses[f.ids.revive] == 1 then f.ids.revive else nil,
		}
		config.titles[f.entry.name] = { entry = f.entry, mode = PaidPlay.mode(raw, ids), ids = ids }
		if ids.play then
			config.products[ids.play] = { name = f.entry.name, kind = "play" }
		end
		if ids.revive then
			config.products[ids.revive] = { name = f.entry.name, kind = "revive" }
		end
	end
	return config
end

-- A stored value read defensively: nil or broken fields are a new player's. Revives are stored as f0145's
-- `continues`, so a Pickman record either build writes is the other's too (PaidPlay.stored).
function PaidPlay.record(raw: any): Record
	local r: Record = { free = nil, plays = 0, revives = 0, receipts = {} }
	if type(raw) ~= "table" then
		return r
	end
	r.free = whole(raw.free)
	r.plays = whole(raw.plays) or 0
	r.revives = whole(raw.continues) or 0
	if type(raw.receipts) == "table" then
		for _, x in raw.receipts do
			if type(x) == "string" and x ~= "" then
				table.insert(r.receipts, x)
			end
		end
	end
	return r
end

-- The value to store: exactly f0145's four fields (`continues` holds the revives), nothing else.
function PaidPlay.stored(r: Record): Stored
	return { free = r.free, plays = r.plays, continues = r.revives, receipts = table.clone(r.receipts) }
end

-- A free start is due when none was taken yet, or the latest one is a full hour old. A clock behind the recorded
-- start (another server's) waits; an instant that is not a whole number never grants one.
function PaidPlay.freeDue(r: Record, now: number): boolean
	if whole(now) == nil then
		return false
	end
	return r.free == nil or now - r.free >= PaidPlay.FREE_SECONDS
end

function PaidPlay.status(r: Record, now: number): Status
	local free = PaidPlay.freeDue(r, now)
	return {
		free = free,
		nextFree = if free or r.free == nil then nil else r.free + PaidPlay.FREE_SECONDS,
		plays = r.plays,
		revives = r.revives,
	}
end

-- The arrival's claim: a free start due first (recording now), else one held play, else "buy" (nothing changes).
function PaidPlay.start(r: Record, now: number): (Start, Record)
	if PaidPlay.freeDue(r, now) then
		local n = copy(r)
		n.free = now
		return "free", n
	end
	if r.plays >= 1 then
		local n = copy(r)
		n.plays -= 1
		return "credit", n
	end
	return "buy", r
end

local function add(r: Record, kind: Kind): Record
	local n = copy(r)
	if kind == "play" then
		n.plays += 1
	else
		n.revives += 1
	end
	return n
end

-- A purchase granted once per receipt id: one credit of its kind, the id remembered (the oldest dropped past
-- RECEIPTS_KEPT). An id already remembered, or no id, grants nothing: false.
function PaidPlay.grant(r: Record, kind: Kind, receiptId: string): (Record, boolean)
	if type(receiptId) ~= "string" or receiptId == "" or table.find(r.receipts, receiptId) then
		return r, false
	end
	local n = add(r, kind)
	table.insert(n.receipts, receiptId)
	while #n.receipts > PaidPlay.RECEIPTS_KEPT do
		table.remove(n.receipts, 1)
	end
	return n, true
end

-- A credit given back (a revive used that could not be applied): its own credit, outside the receipts.
function PaidPlay.refund(r: Record, kind: Kind): Record
	return add(r, kind)
end

-- One held revive used, once; with none held nothing changes.
function PaidPlay.useRevive(r: Record): (boolean, Record)
	if r.revives < 1 then
		return false, r
	end
	local n = copy(r)
	n.revives -= 1
	return true, n
end

-- An arrival: a charged start, or a claim whose write failed (nil), plays; "buy" plays only with the portal's pass.
function PaidPlay.arrive(start: Start?, passed: boolean): Verdict
	if start == "buy" and not passed then
		return "back"
	end
	return "play"
end

-- A text as rich text shows it: &, < and > as entities, so only the markup testLines adds is markup.
local function plain(text: string): string
	return (string.gsub(string.gsub(string.gsub(text, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
end

-- The test purchase screen's lines, as rich text: what is bought, its price, and that nothing is charged. A play's
-- price is the badge's, the struck price marked for strike-through (f0395); a revive's is its own, nothing struck.
function PaidPlay.testLines(title: string, kind: Kind, prices: Prices): { string }
	local price = if kind == "play"
		then `<s>{plain(prices.struck)}</s> {plain(prices.price)} {plain(prices.sale)}`
		else plain(prices.revive)
	return {
		plain(`{title}: {PaidPlay.KIND_TEXT[kind]}`),
		price,
		plain(PaidPlay.TEST_NOTE),
	}
end

-- The test screen's answer for a key or button name, nil for any other.
function PaidPlay.testKey(name: string): ("confirm" | "cancel")?
	if table.find(PaidPlay.TEST_KEYS.confirm, name) then
		return "confirm"
	end
	if table.find(PaidPlay.TEST_KEYS.cancel, name) then
		return "cancel"
	end
	return nil
end

return PaidPlay
