--!strict
-- The tracker board: reads the tracker tree into a model and renders it as one self-contained HTML page.
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local board = {}

board.MARKED_PATH = "scripts/vendor/marked.umd.js"
board.MARKED_SHA256 = "21568877a938d2c4e7d74e27f18e60da96bb73a68809610ca39216e1efebae62"
board.TEMPLATE_PATH = "scripts/tracker/board.html"

-- Errors unless the vendored marked is the pinned build.
function board.checkMarked(js: string)
	local got = serde.hash("sha256", js)
	if got ~= board.MARKED_SHA256 then
		error(`{board.MARKED_PATH} is not the pinned marked build (sha256 {got}, expected {board.MARKED_SHA256})`, 0)
	end
end

-- marked without its trailing source-map comment, so a browser never fetches marked.umd.js.map.
function board.inlineMarked(js: string): string
	return (string.gsub(js, "\n//# sourceMappingURL=[^\n]*\n?$", "\n"))
end

return board
