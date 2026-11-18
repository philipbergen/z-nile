--!strict
-- Play (f0208): what a card's play buttons do and show. Pure rules: the server's decision from a read of the
-- player's record (play now, play on the portal's pass, buy, store unavailable, or read again), the client's intent
-- and the server's status checked field by field, each card's buttons and note for a player, where they sit in the
-- card's Buttons slot, and the keys. A title is a name (src/shared/Modes.luau lists each one's modes); the
-- arcade's paid play reaches this as plain values (a status's `free` and `plays`, a mode's name), never by require.
local Card = require("./Card")

export type Mode = "solo" | "arena" | "pair"
export type Phase = "idle" | "checking" | "buying" | "waiting" | "going" | "closed" | "failed"
export type Decision = "go" | "pass" | "buy" | "closed" | "busy"
-- a record's two figures that decide a play (the arcade's PaidPlay.status), nil when the read gave no record
export type Read = { free: boolean, plays: number }
-- what the server tells one player: the phase of their one play, and the title and mode it is for
export type Status = { phase: Phase, name: string?, mode: Mode? }
export type Intent = { action: "play" | "cancel" | "invite", name: string?, mode: Mode? }
export type Kind = Mode | "cancel" | "invite"
-- `price` is rich text: "FREE", or the struck price and the charge; "" when not known
export type Button = { kind: Kind, text: string, price: string, enabled: boolean }
export type View = { buttons: { Button }, note: string }
export type Slot = { x: number, y: number, width: number, height: number } -- of the Buttons slot's size
export type Key = "second" | "cancel" | "invite"
export type Modes = { [string]: { Mode } }

local Play = {}

Play.MODES = table.freeze({ "solo", "arena", "pair" } :: { Mode })
Play.PHASES =
	table.freeze({ "idle", "checking", "buying", "waiting", "going", "closed", "failed" } :: { Phase })
Play.LABEL = table.freeze({
	solo = "PLAY",
	arena = "ARENA",
	pair = "2 PLAYERS",
	cancel = "CANCEL",
	invite = "INVITE FRIEND",
})
Play.NOTE = table.freeze({
	checking = "CHECKING...",
	buying = "COMPLETE THE PURCHASE",
	waiting = "WAITING FOR A SECOND PLAYER",
	going = "STARTING...",
	closed = "STORE UNAVAILABLE",
	failed = "COULD NOT START. TRY AGAIN.",
	other = "A PLAYER IS WAITING",
})
Play.FREE = "FREE"
-- the card's other keys (Enter, KeypadEnter and ButtonA are the carousel's PLAY, f0205): the card's second button
-- (ARENA or 2 PLAYERS), the waiting card's CANCEL and INVITE FRIEND
Play.KEYS = table.freeze({
	Two = "second",
	KeypadTwo = "second",
	ButtonX = "second",
	Backspace = "cancel",
	ButtonB = "cancel",
	I = "invite",
	ButtonY = "invite",
} :: { [string]: Key })
Play.ACTION = "PortalPlay" -- the ContextActionService action name
Play.PRIORITY = 2500 -- above the default controls' 2000, below the test purchase screen's 3000 (f0201)
Play.GAP = 0.02 -- between buttons, of the slot's width
Play.BUSY_SECONDS = 0.25 -- a check that finds the record being read reads again this much later
Play.CHECK_SECONDS = 10 -- a check still busy this long goes on the pass (more than Wallet's WAIT_SECONDS, 5)
Play.RECEIPT_SECONDS = 30 -- a purchase closed bought waits this long for its receipt
Play.BUY_SECONDS = 120 -- a purchase whose screen never reports closing ends this long after it opened
Play.COOL_SECONDS = 3 -- after any failure the title's buttons rest this long (Travel's own cool-down)
Play.WRITE_SECONDS = 5 -- a MemoryStore write a player waits for counts as failed when not back by then
Play.WRITES = 6 -- MemoryStore writes one player may cause (an arena seat, a pass, an invite set or removed)
Play.WRITE_SPAN = 60 -- ... within this many seconds
Play.RETRY_SECONDS = 1 -- a teleport that raises is tried once more this much later

local function has(list: { any }, v: any): boolean
	return table.find(list, v) ~= nil
end

-- The server's decision for a play of a title, from Wallet.read's answer after `waited` seconds of checking: nil and
-- "busy" reads again until CHECK_SECONDS have passed, then plays on the portal's pass (a read that long under way is
-- a slow store); nil and any other answer (the store down or slow) plays on the pass; a free start due, or a held
-- play, plays; with neither, a title in closed mode cannot sell ("closed"), else the player buys.
function Play.decide(read: Read?, problem: string?, mode: string, waited: number): Decision
	if read == nil then
		return if problem == "busy" and waited < Play.CHECK_SECONDS then "busy" else "pass"
	end
	if read.free == true or read.plays >= 1 then
		return "go"
	end
	if mode == "closed" then
		return "closed"
	end
	return "buy"
end

-- A client's message, checked: "play" with a title of `modes` and one of its modes; "cancel" and "invite" alone.
-- Anything else is nil.
function Play.intent(action: any, name: any, mode: any, modes: Modes): Intent?
	if action == "cancel" or action == "invite" then
		return { action = action }
	end
	if action ~= "play" or type(name) ~= "string" then
		return nil
	end
	local list = modes[name]
	if list == nil or not has(list, mode) then
		return nil
	end
	return { action = "play", name = name, mode = mode }
end

-- The client's read of a status message: a table with a known phase, and a name of `modes` and a mode of it, or
-- neither (idle has none); anything else is nil. It never raises.
function Play.parse(raw: any, modes: Modes): Status?
	if type(raw) ~= "table" or not has(Play.PHASES, raw.phase) then
		return nil
	end
	if raw.name == nil and raw.mode == nil then
		return { phase = raw.phase }
	end
	if type(raw.name) ~= "string" then
		return nil
	end
	local list = modes[raw.name]
	if list == nil or not has(list, raw.mode) then
		return nil
	end
	return { phase = raw.phase, name = raw.name, mode = raw.mode }
end

-- The price line of a play button: "FREE" when the free start is due, else the struck price and the charge.
function Play.price(state: Card.State?, prices: Card.Prices): string
	if state == nil or state.free == nil then
		return ""
	elseif state.free then
		return Play.FREE
	end
	return `{Card.strike(prices.struck)} {prices.price}`
end

local function button(kind: Kind, price: string, enabled: boolean): Button
	return { kind = kind, text = Play.LABEL[kind], price = price, enabled = enabled }
end

-- One card's buttons and note for a player. A title not published shows none. While the player's own play is for
-- this title: checking, buying and going show only the note; waiting shows the note, CANCEL and (for 2 PLAYERS)
-- INVITE FRIEND; closed and failed show the note above the title's buttons (failed ones disabled: its cool-down). Otherwise one button per mode, each
-- with the play's price, enabled once the title's state is known; `others` waiting on a 2 PLAYERS title say so. A
-- card with a note shows its buttons' names only (the badge above says the price).
function Play.view(
	name: string,
	modes: { Mode },
	state: Card.State?,
	status: Status?,
	others: number,
	prices: Card.Prices
): View
	if state ~= nil and not state.published then
		return { buttons = {}, note = "" }
	end
	local mine = status ~= nil and status.name == name and status.phase ~= "idle"
	local phase: Phase = if mine and status then status.phase else "idle"
	if phase == "checking" or phase == "buying" or phase == "going" then
		return { buttons = {}, note = Play.NOTE[phase] }
	end
	if phase == "waiting" then
		local out = { button("cancel", "", true) }
		if status and status.mode == "pair" then
			table.insert(out, button("invite", "", true))
		end
		return { buttons = out, note = Play.NOTE.waiting }
	end
	local note = ""
	if phase == "closed" or phase == "failed" then
		note = Play.NOTE[phase]
	elseif others > 0 and has(modes, "pair") then
		note = Play.NOTE.other
	end
	local price = if note == "" then Play.price(state, prices) else ""
	local enabled = state ~= nil and state.free ~= nil and phase ~= "failed"
	local out = {}
	for _, m in modes do
		table.insert(out, button(m :: Kind, price, enabled))
	end
	return { buttons = out, note = note }
end

-- Where `count` buttons sit in the Buttons slot: side by side with GAP between them, the slot's full width; its full
-- height, or its bottom half under a note.
function Play.slots(count: number, noted: boolean): { Slot }
	local out = {}
	if count < 1 then
		return out
	end
	local y = if noted then 0.5 else 0
	local width = (1 - Play.GAP * (count - 1)) / count
	for i = 1, count do
		table.insert(out, { x = (i - 1) * (width + Play.GAP), y = y, width = width, height = 1 - y })
	end
	return out
end

-- Where the note sits: the whole slot when no button shows, else its top half.
function Play.noteBox(count: number): Slot
	return { x = 0, y = 0, width = 1, height = if count < 1 then 1 else 0.5 }
end

-- One more MemoryStore write for a player whose recent writes are `times` (os.clock() instants): allowed while fewer
-- than WRITES fall within the last WRITE_SPAN seconds. Answers whether it is allowed, and the times kept (the old
-- ones dropped, `now` added when allowed). Never changes the list it is given.
function Play.spend(times: { number }, now: number): (boolean, { number })
	local kept = {}
	for _, at in times do
		if now - at < Play.WRITE_SPAN and at <= now then
			table.insert(kept, at)
		end
	end
	if #kept >= Play.WRITES then
		return false, kept
	end
	table.insert(kept, now)
	return true, kept
end

function Play.key(name: string): Key?
	return Play.KEYS[name]
end

-- The mode of a card's second button (ARENA or 2 PLAYERS), nil when it has one button only.
function Play.second(modes: { Mode }): Mode?
	return modes[2]
end

-- An inviter's user id from an invited friend's launch data: whole decimal digits of a positive id, else nil.
function Play.inviter(raw: any): number?
	if type(raw) ~= "string" or not string.match(raw, "^[1-9]%d*$") or #raw > 15 then
		return nil
	end
	return tonumber(raw)
end

-- An invite's record (MemoryStore): the inviting server's job id and the title the inviter waits on, else nil.
function Play.invite(raw: any, modes: Modes): { job: string, name: string }?
	if type(raw) ~= "table" or type(raw.job) ~= "string" or raw.job == "" or type(raw.name) ~= "string" then
		return nil
	end
	if modes[raw.name] == nil then
		return nil
	end
	return { job = raw.job, name = raw.name }
end

return table.freeze(Play)
