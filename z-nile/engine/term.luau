--!strict
-- Terminal output (c0144): pure rules, no I/O. main.luau decides the mode once from the --color choice, the
-- environment and what it learned about stdout (a terminal or not, and its width), and every command that prints
-- for a person renders through it. Plain mode is today's text, byte for byte: nothing here runs for it.
local term = {}

-- How output is shown. `rich`: the terminal layout (columns, groups, glyphs). `color`: ANSI styles inside it.
-- `links`: OSC 8 hyperlinks. `unicode`: box and bar glyphs (else ASCII). `width`: the columns a line may use.
export type Mode = { rich: boolean, color: boolean, links: boolean, unicode: boolean, width: number }

export type Choice = "auto" | "always" | "never"

-- The mode every non-terminal run gets: today's plain text.
term.PLAIN = table.freeze({ rich = false, color = false, links = false, unicode = false, width = 80 }) :: Mode

-- `--color=<choice>` / `--no-color` as a choice, or nil and the rule a bad value broke.
function term.choice(value: string?): (Choice?, string?)
	if value == nil or value == "auto" then
		return "auto", nil
	elseif value == "always" or value == "never" then
		return value :: Choice, nil
	end
	return nil, `--color takes auto, always or never (got "{value}")`
end

local function utf8Locale(env: { [string]: string? }): boolean
	for _, key in { "LC_ALL", "LC_CTYPE", "LANG" } do
		local v = env[key]
		if v and v ~= "" then
			local l = string.lower(v)
			return string.find(l, "utf-8", 1, true) ~= nil or string.find(l, "utf8", 1, true) ~= nil
		end
	end
	return false
end

-- The mode for a run. `tty`: stdout is a terminal. `ttyColumns`: the terminal's width, when known.
-- Rich layout only on a terminal, or when the choice is `always`; color only inside rich layout, never when the
-- choice is `never`, and in `auto` only when NO_COLOR is unset or empty and TERM is not `dumb`. An explicit
-- `always` wins over NO_COLOR (the flag is the more specific request).
function term.decide(choice: Choice, env: { [string]: string? }, tty: boolean, ttyColumns: number?): Mode
	local rich = choice == "always" or tty
	if not rich then
		return term.PLAIN
	end
	local noColor = env.NO_COLOR ~= nil and env.NO_COLOR ~= ""
	local color = choice == "always" or (choice == "auto" and not noColor and env.TERM ~= "dumb")
	local cols = tonumber(env.COLUMNS or "")
	local width = if cols and cols >= 20
		then math.floor(cols)
		elseif ttyColumns and ttyColumns >= 20 then ttyColumns
		else 80
	return {
		rich = true,
		color = color,
		links = color and env.ZN_HYPERLINKS ~= "0",
		unicode = utf8Locale(env),
		width = width,
	}
end

-- 16-color SGR codes, so the terminal's own theme picks the shades (light or dark backgrounds both work).
local SGR: { [string]: string } = {
	bold = "1",
	dim = "2",
	underline = "4",
	red = "31",
	green = "32",
	yellow = "33",
	blue = "34",
	magenta = "35",
	cyan = "36",
}

-- What each kind of thing looks like: item types, lifecycle states, check outcomes, audit severities.
local STYLE: { [string]: { string } } = {
	feature = { "green" },
	defect = { "red" },
	chore = { "blue" },
	raft = { "magenta" },
	new = {},
	preparing = { "cyan" },
	prepared = { "green" },
	active = { "yellow", "bold" },
	done = { "dim" },
	backlog = {},
	retired = { "dim" },
	pass = { "green", "bold" },
	fail = { "red", "bold" },
	error = { "red", "bold" },
	warning = { "yellow" },
	ok = { "green" },
	heading = { "bold" },
	id = { "bold" },
	muted = { "dim" },
}

-- `text` in the named style (a STYLE key or a raw SGR name), or `text` unchanged when color is off.
function term.paint(mode: Mode, style: string, text: string): string
	if not mode.color or text == "" then
		return text
	end
	local names = STYLE[style] or { style }
	local codes = {}
	for _, n in names do
		table.insert(codes, SGR[n] or error(`term.paint: unknown style {n}`))
	end
	if #codes == 0 then
		return text
	end
	return `\27[{table.concat(codes, ";")}m{text}\27[0m`
end

-- The style of an id by its prefix: f feature, d defect, c chore, R raft.
function term.kindOf(id: string): string
	local p = string.sub(id, 1, 1)
	return if p == "f" then "feature" elseif p == "d" then "defect" elseif p == "R" then "raft" else "chore"
end

-- `text` as an OSC 8 hyperlink to `url` when links are on.
function term.link(mode: Mode, url: string?, text: string): string
	if not mode.links or not url or url == "" then
		return text
	end
	return `\27]8;;{url}\27\\{text}\27]8;;\27\\`
end

-- `text` without ANSI SGR sequences and OSC 8 wrappers: what a terminal shows.
function term.strip(text: string): string
	local s = string.gsub(text, "\27%]8;;[^\27]*\27\\", "")
	s = string.gsub(s, "\27%[[%d;]*m", "")
	return s
end

-- The columns `text` takes on screen: escape sequences take none, each UTF-8 character one.
function term.width(text: string): number
	return utf8.len(term.strip(text)) or #term.strip(text)
end

-- Plain `text` cut to `n` columns, ending in an ellipsis when cut.
function term.fit(mode: Mode, text: string, n: number): string
	if n <= 0 then
		return ""
	end
	local len = utf8.len(text) or #text
	if len <= n then
		return text
	end
	local dots = if mode.unicode then "…" else "."
	local keep = n - (utf8.len(dots) or 1)
	if keep <= 0 then
		return string.sub(dots, 1, n)
	end
	local stop = utf8.offset(text, keep + 1) or (#text + 1)
	return string.sub(text, 1, stop - 1) .. dots
end

-- Plain `text` broken into lines of at most `n` columns at spaces (a word longer than `n` stays whole).
function term.wrap(text: string, n: number): { string }
	local lines: { string } = {}
	local line = ""
	for word in string.gmatch(text, "%S+") do
		if line == "" then
			line = word
		elseif (utf8.len(line) or #line) + 1 + (utf8.len(word) or #word) <= n then
			line ..= " " .. word
		else
			table.insert(lines, line)
			line = word
		end
	end
	if line ~= "" or #lines == 0 then
		table.insert(lines, line)
	end
	return lines
end

local function pad(text: string, n: number, right: boolean?): string
	local gap = math.max(0, n - term.width(text))
	return if right then string.rep(" ", gap) .. text else text .. string.rep(" ", gap)
end

-- A column of a table: `flex` columns shrink (with an ellipsis) so the row fits the width; `right` aligns
-- numbers; `style` paints each cell (a function of the plain cell, or nil for none).
export type Column = { flex: boolean?, right: boolean?, style: ((string) -> string)? }

-- Rows of plain cells laid out in aligned columns two spaces apart, the flex column shrunk so each line fits
-- `mode.width` (down to 8 columns; a table that can't fit then is wider). Cells are styled after fitting.
function term.columns(mode: Mode, cols: { Column }, rows: { { string } }, indent: string?): { string }
	local lead = indent or ""
	local widths: { number } = {}
	for _, row in rows do
		for i, cell in row do
			widths[i] = math.max(widths[i] or 0, utf8.len(cell) or #cell)
		end
	end
	local total = term.width(lead) + 2 * math.max(0, #cols - 1)
	for i = 1, #cols do
		total += widths[i] or 0
	end
	for i, c in cols do
		if c.flex and total > mode.width then
			local w = math.max(8, (widths[i] or 0) - (total - mode.width))
			total -= (widths[i] or 0) - w
			widths[i] = w
		end
	end
	local out: { string } = {}
	for _, row in rows do
		local cells: { string } = {}
		for i, c in cols do
			local plain = term.fit(mode, row[i] or "", widths[i] or 0)
			local shown = if c.style then (c.style :: (string) -> string)(plain) else plain
			cells[i] = if i == #cols and not c.right then shown else pad(shown, widths[i] or 0, c.right)
		end
		table.insert(out, lead .. table.concat(cells, "  "))
	end
	return out
end

-- A bar of `cells` columns filled to `fraction` (0..1): eighth-block glyphs, or `#` and `.` without Unicode.
function term.bar(mode: Mode, fraction: number, cells: number): string
	local f = math.clamp(fraction, 0, 1)
	if not mode.unicode then
		local n = math.floor(f * cells + 0.5)
		return string.rep("#", n) .. string.rep(".", cells - n)
	end
	local eighths = math.floor(f * cells * 8 + 0.5)
	local full = eighths // 8
	local part = eighths % 8
	local PARTS = { "▏", "▎", "▍", "▌", "▋", "▊", "▉" }
	local s = string.rep("█", full)
	if part > 0 and full < cells then
		s ..= PARTS[part]
		full += 1
	end
	return s .. string.rep(" ", cells - full)
end

-- A heading rule: `title` in bold followed by a line to the width.
function term.rule(mode: Mode, title: string): string
	local line = if mode.unicode then "─" else "-"
	local head = ` {title} `
	local n = math.max(2, mode.width - (utf8.len(head) or #head) - 2)
	return term.paint(mode, "muted", string.rep(line, 2))
		.. term.paint(mode, "heading", head)
		.. term.paint(mode, "muted", string.rep(line, n))
end

-- A glyph by name, with its ASCII fallback.
local GLYPHS: { [string]: { string } } = {
	pass = { "✔", "+" },
	fail = { "✘", "x" },
	warning = { "▲", "!" },
	error = { "✖", "x" },
	bullet = { "•", "*" },
	dot = { "·", "-" },
	arrow = { "→", "->" },
}
function term.glyph(mode: Mode, name: string): string
	local g = GLYPHS[name] or error(`term.glyph: unknown glyph {name}`)
	return if mode.unicode then g[1] else g[2]
end

return term
