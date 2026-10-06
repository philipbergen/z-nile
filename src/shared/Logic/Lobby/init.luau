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
