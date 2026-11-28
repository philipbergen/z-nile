--!strict
-- Wallet (f0201): a player's paid-play records, one per title, through one UpdateAsync per decision; the portal's
-- passes; this run's revives; and the guards that bound what one client can make this server spend. Server only
-- (ServerStorage.Arcade): no client can read it. Every decision is PaidPlay's, taken inside the transform, and the
-- transform's last call decides (UpdateAsync may call it again on a newer value). What a teleport carries is never read.
-- Engine surface: time limits are task.delay, waits are coroutine.yield resumed by task.spawn, a player is present
-- while their Parent is not nil, and a buyer is found with Players:GetPlayerByUserId.
local Catalog = require("./Catalog")
local PaidPlay = require("@game/ReplicatedStorage/Arcade/Logic/PaidPlay")

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Wallet = {}

Wallet.WAIT_SECONDS = 5 -- a claim, a pass read or a read not back by then counts as failed
Wallet.READ_SECONDS = 60 -- a read within this of the last record seen answers from it (every write here refreshes it)
Wallet.RETRY_SECONDS = 6 -- after a read that failed, reads answer "down" with no store call for this long
Wallet.USE_SECONDS = 6 -- at most one revive write per player and title in this span
Wallet.KEEP_SECONDS = 600 -- a departed player's run count is dropped this long after they left
Wallet.PASS_SECONDS = 300 -- a portal pass lives this long
Wallet.PASS_MAP = "PaidPlayPass" -- MemoryStore hash map of the passes, key "<name>/<user id>"
Wallet.MODE_ATTRIBUTE = "PaidPlay" -- ServerScriptService attribute: "live" for live mode

type Arrival = { verdict: PaidPlay.Verdict, start: PaidPlay.Start? }
-- per Player object and title; dropped when the player leaves
type Slot = {
	seen: PaidPlay.Record?, -- the last record of this title this server saw for the player, in the mode's store
	seenAt: number?,
	reading: boolean,
	late: boolean, -- the read in progress timed out past WAIT_SECONDS (d0405)
	downUntil: number?, -- reads answer "down" with no store call until then
	mayPass: boolean, -- the last read answered "down" and no pass was written since
	using: boolean,
	usedAt: number?,
	arrival: Arrival?, -- this join's arrival, answered once
	arriving: { thread }?, -- callers waiting for the arrival under way
	calls: number, -- store calls on this slot under way
	gen: number, -- bumped at every store call's start and end on this slot
	passedAt: number?, -- when this server last wrote the player's pass for this title
}

local configured: PaidPlay.Config? = nil
local slots: { [any]: { [string]: Slot } } = {}
local tallies: { [string]: number } = {} -- "<name>/<user id>": revives used in this run
local leftAt: { [string]: number } = {} -- "<name>/<user id>": when that player last left
local stores: { [string]: any } = {}
local standIns: { [string]: any } = {}
local passMap: any = nil

function Wallet.config(): PaidPlay.Config
	local c = configured
	if c == nil then
		c = PaidPlay.configure(
			Catalog,
			ServerScriptService:GetAttribute(Wallet.MODE_ATTRIBUTE),
			function(name: string): any
				return ServerScriptService:GetAttribute(name)
			end
		)
		configured = c
	end
	return c :: PaidPlay.Config
end

local function title(name: string): PaidPlay.Title
	local t = Wallet.config().titles[name]
	if t == nil then
		error(`Wallet: no title "{tostring(name)}" in the catalog`, 2)
	end
	return t
end

function Wallet.mode(name: string): PaidPlay.Mode
	return title(name).mode
end

local function keyOf(name: string, userId: number): string
	return `{name}/{userId}`
end

local function present(player: any): boolean
	return player.Parent ~= nil
end

local function newSlot(): Slot
	return { reading = false, late = false, mayPass = false, using = false, calls = 0, gen = 0 }
end

local function slotOf(player: any, name: string): Slot
	local byName = slots[player]
	if byName == nil then
		byName = {}
		slots[player] = byName
	end
	local slot = byName[name]
	if slot == nil then
		slot = newSlot()
		byName[name] = slot
	end
	return slot
end

-- Slots are kept per Player object and title and dropped when the player leaves, so a result that comes back after a
-- leave lands in a dropped slot, and a rejoin starts a fresh one.
local function see(slot: Slot, r: PaidPlay.Record)
	slot.seen = r
	slot.seenAt = os.clock()
end

-- The record seen is ordered by the store, not by when an answer comes back (review 001 F1): a store call on a slot
-- takes a ticket when it starts (`begin`) and reports its end (`ended`). Its record becomes the record seen only when no
-- other call on that slot started or ended while it ran; otherwise the record seen is forgotten, so the next read
-- reads the store and the next revive writes, rather than answer from a record another call may have outdated. A
-- write that failed forgets it too (it may have been applied); a failed read leaves it.
local function begin(slot: Slot): number
	slot.calls += 1
	slot.gen += 1
	return slot.gen
end

local function forget(slot: Slot)
	slot.gen += 1
	slot.seen = nil
	slot.seenAt = nil
end

local function ended(slot: Slot, ticket: number, r: PaidPlay.Record?, wrote: boolean)
	slot.calls -= 1
	local alone = slot.gen == ticket and slot.calls == 0
	slot.gen += 1
	if r ~= nil and alone then
		see(slot, r)
	elseif r ~= nil or wrote then
		forget(slot)
	end
end

-- A per-server stand-in for a store, with UpdateAsync's and GetAsync's contract: test mode's records where the test
-- store cannot be opened (a Studio playtest from a file, API access off), so a test purchase still goes through.
local function standIn(name: string): any
	local s = standIns[name]
	if s == nil then
		local values: { [string]: any } = {}
		s = {
			UpdateAsync = function(_: any, key: string, fn: (any) -> any): any
				local value = fn(values[key])
				if value ~= nil then
					values[key] = value
				end
				return value
			end,
			GetAsync = function(_: any, key: string): any
				return values[key]
			end,
		}
		standIns[name] = s
	end
	return s
end

-- The DataStore of that name, opened on first use inside a pcall and kept; nil when it cannot be opened, except a
-- test store (`test`), which then has its stand-in.
local function store(name: string, test: boolean): any
	local s = stores[name]
	if s == nil then
		local ok, opened = pcall(function(): any
			return DataStoreService:GetDataStore(name)
		end)
		if ok and opened ~= nil then
			s = opened
			stores[name] = s
		elseif test then
			s = standIn(name)
			stores[name] = s
		end
	end
	return s
end

local function storeOf(t: PaidPlay.Title): any
	return store(PaidPlay.store(t.entry, t.mode), t.mode == "test")
end

-- One UpdateAsync of a player's record: `fn` answers the new record (nil writes nothing) and a decision; the value
-- written is PaidPlay.stored's. Answers the final record and the decision of the transform's last call, or nil when
-- the store failed.
local function update(
	s: any,
	userId: number,
	fn: (PaidPlay.Record) -> (PaidPlay.Record?, any)
): (PaidPlay.Record?, any)
	if s == nil then
		return nil
	end
	local final: PaidPlay.Record? = nil
	local decision: any = nil
	local ok = pcall(function()
		s:UpdateAsync(tostring(userId), function(raw: any): any
			local r = PaidPlay.record(raw)
			local n, d = fn(r)
			final, decision = n or r, d
			return if n then PaidPlay.stored(n) else nil
		end)
	end)
	if not ok then
		return nil
	end
	return final, decision
end

-- Runs fn in its own thread and answers (true, its results), or (false) when it is not back within `seconds`.
local function within(seconds: number, fn: () -> ...any): (boolean, ...any)
	local me = coroutine.running()
	local result: { any }? = nil
	local waiting = false
	local function settle(r: { any })
		if result ~= nil then
			return
		end
		result = r
		if waiting then
			task.spawn(me)
		end
	end
	task.spawn(function()
		settle(table.pack(true, fn()))
	end)
	if result == nil then
		task.delay(seconds, function()
			settle(table.pack(false))
		end)
	end
	if result == nil then
		waiting = true
		coroutine.yield()
	end
	local r = result :: any
	return table.unpack(r, 1, r.n)
end

-- A player's record of a title, from the mode's store. Answers nil and "busy" while a read for them is under way; the
-- last record seen when it is less than READ_SECONDS old; nil and "down" when the store failed or was not back
-- within WAIT_SECONDS, and then for RETRY_SECONDS after that call ended, with no store call; nil and "down" for a
-- player who left. A "down" answer allows one pass (Wallet.pass).
function Wallet.read(player: any, name: string): (PaidPlay.Record?, string?)
	local t = title(name)
	if not present(player) then
		return nil, "down"
	end
	local slot = slotOf(player, name)
	if slot.reading then
		if not slot.late then
			slot.mayPass = false
		end
		return nil, "busy"
	end
	if slot.downUntil ~= nil and os.clock() < slot.downUntil then
		slot.mayPass = true
		return nil, "down"
	end
	if slot.seen ~= nil and slot.seenAt ~= nil and os.clock() - slot.seenAt < Wallet.READ_SECONDS then
		slot.mayPass = false
		return slot.seen
	end
	slot.reading = true
	slot.late = false
	local s = storeOf(t)
	local late = false
	local ticket = begin(slot)
	local back, ok, record = within(Wallet.WAIT_SECONDS, function(): (boolean, PaidPlay.Record?)
		local okRead, value = false, nil
		if s ~= nil then
			okRead, value = pcall(function(): any
				return s:GetAsync(tostring(player.UserId))
			end)
		end
		slot.reading = false
		slot.late = false
		if not okRead or late then
			slot.downUntil = os.clock() + Wallet.RETRY_SECONDS
		end
		local r = if okRead then PaidPlay.record(value) else nil
		ended(slot, ticket, if late then nil else r, false)
		return okRead, r
	end)
	if not back then
		-- the call ends later; until then the player stays busy, and its end starts the retry span
		late = true
		slot.late = true
		slot.mayPass = true
		return nil, "down"
	end
	if not ok then
		slot.mayPass = true
		return nil, "down"
	end
	slot.mayPass = false
	return record
end

-- The portal's pass, for a player it let go on a failed read: the arrival then plays even with nothing to pay with.
-- Written only after this server's last read for that player and title answered "down", once per such answer; else
-- false and nothing written.
function Wallet.pass(player: any, name: string): boolean
	title(name)
	if not present(player) then
		return false
	end
	local slot = slotOf(player, name)
	if not slot.mayPass then
		return false
	end
	slot.mayPass = false
	-- the entry this server wrote within RETRY_SECONDS is still there: at most one write per RETRY_SECONDS per player
	-- and title, however often a client asks during an outage (review 001 F3)
	local at = slot.passedAt
	if at ~= nil and os.clock() - at < Wallet.RETRY_SECONDS then
		return true
	end
	local ok = pcall(function()
		if passMap == nil then
			passMap = MemoryStoreService:GetHashMap(Wallet.PASS_MAP)
		end
		passMap:SetAsync(keyOf(name, player.UserId), true, Wallet.PASS_SECONDS)
	end)
	if ok then
		slot.passedAt = os.clock()
	end
	return ok
end

-- Takes the player's pass for a title: true when one was there, or when the map cannot be read or is not back within
-- WAIT_SECONDS (decided with the user, 2026-10-31: "Let all of them play"); a late answer still removes the entry.
local function takePass(userId: number, name: string): boolean
	local key = keyOf(name, userId)
	local back, found = within(Wallet.WAIT_SECONDS, function(): boolean
		local ok, value = pcall(function(): any
			if passMap == nil then
				passMap = MemoryStoreService:GetHashMap(Wallet.PASS_MAP)
			end
			return passMap:GetAsync(key)
		end)
		if not ok then
			return true
		end
		if value == nil then
			return false
		end
		pcall(function()
			passMap:RemoveAsync(key)
		end)
		return true
	end)
	return not back or found == true
end

-- The arrival in a title's place, once per join: the free start due, else a held play (PaidPlay.start, in one
-- UpdateAsync); the portal's pass is taken whatever the start; a claim that failed or was not back within
-- WAIT_SECONDS plays (a failure costs the player nothing). Answers "play" or "back" and the start (nil: failed).
-- Begins this run's revive count. A second call during the first waits for it; a later one answers the same. A
-- player who already left goes "back" with nothing claimed.
function Wallet.arrive(player: any, name: string): (PaidPlay.Verdict, PaidPlay.Start?)
	local t = title(name)
	if not present(player) then
		return "back", nil
	end
	local slot = slotOf(player, name)
	local done = slot.arrival
	if done ~= nil then
		return done.verdict, done.start
	end
	local waiting = slot.arriving
	if waiting ~= nil then
		table.insert(waiting, coroutine.running())
		return coroutine.yield()
	end
	slot.arriving = {}
	local userId = player.UserId
	local now = os.time()
	local s = storeOf(t)
	local ticket = begin(slot)
	local _, _, start = within(Wallet.WAIT_SECONDS, function(): (PaidPlay.Record?, any)
		local final, st = update(s, userId, function(r: PaidPlay.Record): (PaidPlay.Record?, any)
			local claim, n = PaidPlay.start(r, now)
			return if claim == "buy" then nil else n, claim
		end)
		-- the claim's record is applied as its write returns, not after the pass read (review 001 F1)
		ended(slot, ticket, final, true)
		return final, st
	end)
	local passed = takePass(userId, name)
	local verdict: PaidPlay.Verdict = PaidPlay.arrive(start, passed) :: PaidPlay.Verdict
	local key = keyOf(name, userId)
	tallies[key] = 0
	leftAt[key] = nil
	local answer: Arrival = { verdict = verdict, start = start }
	slot.arrival = answer
	local woken: { thread } = slot.arriving or {}
	slot.arriving = nil
	for _, thread in woken do
		task.spawn(thread, verdict, start)
	end
	return verdict, start
end

-- Uses one held revive: true when used (this run's count goes up), false when none is held (known from the last
-- record this server saw, then no write), nil when it cannot tell (a use under way, one within USE_SECONDS, the
-- store failed, or the player left).
function Wallet.useRevive(player: any, name: string): boolean?
	local t = title(name)
	if not present(player) then
		return nil
	end
	local slot = slotOf(player, name)
	if slot.using then
		return nil
	end
	local seen = slot.seen
	if seen ~= nil and seen.revives < 1 then
		return false
	end
	if slot.usedAt ~= nil and os.clock() - slot.usedAt < Wallet.USE_SECONDS then
		return nil
	end
	slot.using = true
	slot.usedAt = os.clock()
	local userId = player.UserId
	local ticket = begin(slot)
	local final, used = update(storeOf(t), userId, function(r: PaidPlay.Record): (PaidPlay.Record?, any)
		local u, n = PaidPlay.useRevive(r)
		return if u then n else nil, u
	end)
	slot.using = false
	ended(slot, ticket, final, true)
	if final == nil then
		return nil
	end
	if used then
		local key = keyOf(name, userId)
		tallies[key] = (tallies[key] or 0) + 1
	end
	return used == true
end

-- Gives a credit back (a revive used that could not be applied): its own credit, outside the receipts, written for a
-- player who left too. A written revive refund takes one off this run's count, never below 0.
function Wallet.refund(player: any, name: string, kind: PaidPlay.Kind): boolean
	local t = title(name)
	local slot = if present(player) then slotOf(player, name) else newSlot()
	local userId = player.UserId
	local ticket = begin(slot)
	local final = update(storeOf(t), userId, function(r: PaidPlay.Record): (PaidPlay.Record?, any)
		return PaidPlay.refund(r, kind), nil
	end)
	ended(slot, ticket, final, true)
	if final == nil then
		return false
	end
	if kind == "revive" then
		local key = keyOf(name, userId)
		tallies[key] = math.max(0, (tallies[key] or 0) - 1)
	end
	return true
end

-- The revives this run of the player has used (PaidPlay's count for the boards): 0 at the arrival, one more for each
-- revive used, one less for each revive refunded. Kept after the player leaves for KEEP_SECONDS (a departed run is
-- submitted after PlayerRemoving), and started again at their next arrival.
function Wallet.revives(player: any, name: string): number
	title(name)
	return tallies[keyOf(name, player.UserId)] or 0
end

local function grantInto(
	s: any,
	userId: number,
	kind: PaidPlay.Kind,
	receiptId: string
): (boolean, boolean, PaidPlay.Record?)
	local final, fresh = update(s, userId, function(r: PaidPlay.Record): (PaidPlay.Record?, any)
		local n, isNew = PaidPlay.grant(r, kind, receiptId)
		return if isNew then n else nil, isNew
	end)
	if final == nil then
		return false, false, nil
	end
	return true, fresh == true, final
end

-- A grant refreshes the record seen of a buyer on this server: the buyer's slot takes part in the ordering when the
-- buyer is here as the write starts; one who joined during the write has the record seen forgotten instead.
local function grantFor(
	userId: number,
	name: string,
	write: () -> (boolean, boolean, PaidPlay.Record?)
): (boolean, boolean)
	local before = Players:GetPlayerByUserId(userId)
	local slot = if before ~= nil and present(before) then slotOf(before, name) else nil
	local ticket = if slot ~= nil then begin(slot) else 0
	local written, fresh, final = write()
	if slot ~= nil then
		ended(slot, ticket, final, true)
	else
		local after = Players:GetPlayerByUserId(userId)
		if after ~= nil and present(after) then
			forget(slotOf(after, name))
		end
	end
	return written, fresh
end

-- A Roblox receipt's grant, by user id (the buyer need not be on this server): always into the title's live store,
-- since real Robux were charged. Answers whether it was written, and whether it was new (not granted before). The
-- record seen is refreshed unless this server's mode for the title is test (it sees the test record).
function Wallet.grant(
	userId: number,
	name: string,
	kind: PaidPlay.Kind,
	receiptId: string
): (boolean, boolean)
	local t = title(name)
	local function write(): (boolean, boolean, PaidPlay.Record?)
		return grantInto(store(t.entry.store, false), userId, kind, receiptId)
	end
	if t.mode == "test" then
		return write() -- this server sees the test record: a live grant leaves it alone
	end
	return grantFor(userId, name, write)
end

-- A test purchase's grant (test mode only): into the test store (or its stand-in), under a fresh "test:" id.
-- Answers whether written; the record seen is refreshed.
function Wallet.testGrant(player: any, name: string, kind: PaidPlay.Kind): boolean
	local t = title(name)
	if t.mode ~= "test" then
		return false
	end
	local receiptId = "test:" .. HttpService:GenerateGUID(false)
	local written = grantFor(player.UserId, name, function(): (boolean, boolean, PaidPlay.Record?)
		return grantInto(store(t.entry.testStore, true), player.UserId, kind, receiptId)
	end)
	return written
end

Players.PlayerRemoving:Connect(function(player: any)
	slots[player] = nil
	local userId = player.UserId
	local now = os.clock()
	for _, entry in Catalog do
		local key = keyOf(entry.name, userId)
		if tallies[key] ~= nil then
			leftAt[key] = now
			task.delay(Wallet.KEEP_SECONDS, function()
				local at = leftAt[key]
				if at ~= nil and os.clock() - at >= Wallet.KEEP_SECONDS then
					tallies[key] = nil
					leftAt[key] = nil
				end
			end)
		end
	end
end)

return Wallet
