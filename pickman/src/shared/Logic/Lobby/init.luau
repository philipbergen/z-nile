--!strict
-- Lobby: what the lobby screen shows. Pure view models: the hiscore panel (empty until the boards exist) and
-- the start button for a travel status.
local Travel = require("./Travel")

export type Row = { rank: number, name: string, score: number, level: number }
export type Panel = { title: string, rows: { Row }, empty: string? }
export type Button = { text: string, enabled: boolean, message: string? }

local Lobby = {}
Lobby.TITLE = "HISCORES"
Lobby.EMPTY = "No scores yet"
Lobby.MAX_ROWS = 10
Lobby.BUTTON_MIN_PX = 44 -- the smallest touch target (design: Mobile)
Lobby.READ_GAP = 1 -- seconds before the screen asks again after a failed answer; a copy of Hiscores.READ_GAP
Lobby.MAX_RETRIES = 3 -- failed answers in a row that are asked for again

-- The panel for the rows the boards give (nil or none: the empty state). Rows are shown in rank order, at most MAX_ROWS.
function Lobby.panel(rows: { Row }?): Panel
	local shown: { Row } = {}
	local given: { Row } = rows or {}
	for _, r in given do
		table.insert(shown, { rank = r.rank, name = r.name, score = r.score, level = r.level })
	end
	table.sort(shown, function(a: Row, b: Row): boolean
		return a.rank < b.rank
	end)
	while #shown > Lobby.MAX_ROWS do
		table.remove(shown)
	end
	return { title = Lobby.TITLE, rows = shown, empty = if #shown == 0 then Lobby.EMPTY else nil }
end

-- A board id the screen may ask for: "all", "day" or "week", and nothing else (a number or a table is nil).
function Lobby.board(raw: any): ("all" | "day" | "week")?
	if raw == "all" then
		return "all"
	elseif raw == "day" then
		return "day"
	elseif raw == "week" then
		return "week"
	end
	return nil
end

function Lobby.boardTitle(id: string?): string
	if id == "day" then
		return "TODAY"
	elseif id == "week" then
		return "THIS WEEK"
	end
	return Lobby.TITLE
end

-- The panel of one board: the same rows, cap and empty state as `panel`, under that board's title.
function Lobby.boardPanel(rows: { Row }?, id: string?): Panel
	local p = Lobby.panel(rows)
	p.title = Lobby.boardTitle(id)
	return p
end

-- The panel as text, one row per line. The highlighted rank is one the server sent, marked with "> ".
function Lobby.lines(p: Panel, highlightRank: number?): string
	if p.empty then
		return p.empty
	end
	local out: { string } = {}
	for _, r in p.rows do
		local mark = if highlightRank ~= nil and r.rank == highlightRank then "> " else ""
		table.insert(out, `{mark}{r.rank} {r.name} {r.score} {r.level}`)
	end
	return table.concat(out, "\n")
end

-- How long to wait before asking again after the nth failed answer in a row: 1, 2, 4 s, then stop.
function Lobby.retryAfter(failures: number): number?
	if failures ~= math.floor(failures) or failures < 1 or failures > Lobby.MAX_RETRIES then
		return nil
	end
	return Lobby.READ_GAP * 2 ^ (failures - 1)
end

-- The start button: live only when a destination is set and nothing is under way.
function Lobby.button(status: Travel.Phase, configured: boolean): Button
	if not configured then
		return { text = "UNAVAILABLE", enabled = false, message = "Starting is not set up yet." }
	elseif status == "going" then
		return { text = "STARTING...", enabled = false, message = nil }
	elseif status == "cooling" then
		return { text = "START GAME", enabled = false, message = "Could not start. Try again in a moment." }
	end
	return { text = "START GAME", enabled = true, message = nil }
end

return Lobby
