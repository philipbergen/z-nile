--!strict
-- The terminal look of each command (c0144): pure renderers from the rows or the plain lines a command prints
-- today to the lines it prints on a terminal. Each takes a rich term.Mode; plain mode never calls them. Every
-- renderer keeps every fact of the plain form (the plain-text pin and the information case in its spec).
local term = require("./term")

local look = {}

type Mode = term.Mode

-- Every item id in `text` painted by its kind, and linked when `url` gives it an address.
function look.ids(mode: Mode, text: string, url: ((string) -> string?)?): string
	return (
		string.gsub(text, "%f[%w]([fdcR]%d%d%d%d)%f[^%w]", function(id: string): string
			local shown = term.paint(mode, term.kindOf(id), id)
			return if url then term.link(mode, url(id), shown) else shown
		end)
	)
end

local STATE_ORDER = { "active", "preparing", "prepared", "new" }

-- `status`: one row per unfinished item on origin/main.
export type StatusRow = {
	id: string,
	state: string,
	kind: string, -- feature, defect, chore, raft
	title: string,
	raft: string, -- the issue's raft, or ""
	claim: string, -- the three stamp words, or ""
	project: string,
	url: string?, -- the item document, for the id's link
}

-- Grouped by project, then by state (active first), aligned in columns (id, type, state, title, raft, claim),
-- the title shrunk to the width, and a summary line of counts.
function look.status(mode: Mode, rows: { StatusRow }): { string }
	local projects: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, r in rows do
		if not seen[r.project] then
			seen[r.project] = true
			table.insert(projects, r.project)
		end
	end
	table.sort(projects)
	local out: { string } = {}
	local counts: { [string]: number } = {}
	for _, project in projects do
		table.insert(out, term.rule(mode, project))
		for _, state in STATE_ORDER do
			local group: { StatusRow } = {}
			for _, r in rows do
				if r.project == project and r.state == state then
					table.insert(group, r)
				end
			end
			if #group > 0 then
				counts[state] = (counts[state] or 0) + #group
				table.sort(group, function(a, b)
					return a.id < b.id
				end)
				table.insert(out, "  " .. term.paint(mode, state, `{string.upper(state)} ({#group})`))
				local cells: { { string } } = {}
				local byId: { [string]: StatusRow } = {}
				for _, r in group do
					byId[r.id] = r
					table.insert(cells, { r.id, r.kind, r.state, r.title, r.raft, r.claim })
				end
				local cols: { term.Column } = {
					{
						style = function(id: string): string
							local r = byId[id]
							return term.link(mode, r and r.url, term.paint(mode, term.kindOf(id), id))
						end,
					},
					{
						style = function(kind: string): string
							return term.paint(mode, kind, kind)
						end,
					},
					{
						style = function(s: string): string
							return term.paint(mode, s, s)
						end,
					},
					{ flex = true },
					{
						style = function(raft: string): string
							return look.ids(mode, raft)
						end,
					},
					{
						style = function(claim: string): string
							return term.paint(mode, "muted", claim)
						end,
					},
				}
				for _, line in term.columns(mode, cols, cells, "    ") do
					table.insert(out, (string.gsub(line, "%s+$", "")))
				end
			end
		end
		-- any state outside the usual four (a hand-edited stamp) still shows, last
		for _, r in rows do
			if r.project == project and not table.find(STATE_ORDER, r.state) then
				counts[r.state] = (counts[r.state] or 0) + 1
				table.insert(out, `    {look.ids(mode, r.id)}  {r.kind}  {r.state}  {r.title}`)
			end
		end
	end
	local parts: { string } = {}
	for _, state in STATE_ORDER do
		if counts[state] then
			table.insert(parts, term.paint(mode, state, `{counts[state]} {state}`))
		end
	end
	for state, n in counts do
		if not table.find(STATE_ORDER, state) then
			table.insert(parts, `{n} {state}`)
		end
	end
	local dot = ` {term.paint(mode, "muted", term.glyph(mode, "dot"))} `
	table.insert(out, term.paint(mode, "heading", `{#rows} items`) .. ": " .. table.concat(parts, dot))
	return out
end

-- `list`: one row per item, as today's columns (id, state, type, raft, title), colored, the title fitted.
export type ListRow = { id: string, state: string, kind: string, raft: string, title: string, url: string? }
function look.list(mode: Mode, rows: { ListRow }): { string }
	local cells: { { string } } = {}
	local byId: { [string]: ListRow } = {}
	for _, r in rows do
		byId[r.id] = r
		table.insert(cells, { r.id, r.state, r.kind, r.raft, r.title })
	end
	local cols: { term.Column } = {
		{
			style = function(id: string): string
				local r = byId[id]
				return term.link(mode, r and r.url, term.paint(mode, term.kindOf(id), id))
			end,
		},
		{
			style = function(s: string): string
				return term.paint(mode, s, s)
			end,
		},
		{
			style = function(k: string): string
				return term.paint(mode, k, k)
			end,
		},
		{
			style = function(raft: string): string
				return look.ids(mode, raft)
			end,
		},
		{ flex = true },
	}
	local out: { string } = {}
	for _, line in term.columns(mode, cols, cells) do
		table.insert(out, (string.gsub(line, "%s+$", "")))
	end
	return out
end

-- `members`: each member's folder, its id in front.
function look.members(mode: Mode, paths: { string }, url: (string) -> string?): { string }
	local out: { string } = {}
	for _, p in paths do
		local id = string.match(p, "([fdcR]%d%d%d%d)$") or ""
		local shown = term.link(mode, url(p), term.paint(mode, term.kindOf(id), id))
		table.insert(out, `{term.glyph(mode, "bullet")} {shown}  {term.paint(mode, "muted", p)}`)
	end
	return out
end

-- `busy`: each reason the item is busy, with a warning glyph.
function look.busy(mode: Mode, lines: { string }): { string }
	local out: { string } = {}
	for _, l in lines do
		local mark = term.paint(mode, "warning", term.glyph(mode, "warning"))
		for _, piece in term.wrap(l, math.max(20, mode.width - 2)) do
			table.insert(out, `{mark} {look.ids(mode, piece)}`)
			mark = " "
		end
	end
	return out
end

-- `audit`: problems as `<severity> <code> <path>: <message>` (audit.format), each one glyph, severity and code on
-- one line and the path and message wrapped under it; the summary colored by its counts.
function look.audit(mode: Mode, lines: { string }, summary: string): { string }
	local out: { string } = {}
	for _, l in lines do
		local sev, code, rest = string.match(l, "^(%S+) (%S+) (.*)$")
		if sev and code and rest then
			local style = if sev == "error" then "error" else "warning"
			local glyph = if sev == "error" then "error" else "warning"
			table.insert(
				out,
				`{term.paint(mode, style, term.glyph(mode, glyph) .. " " .. sev)}  {term.paint(
					mode,
					"heading",
					code
				)}`
			)
			for _, piece in term.wrap(rest, math.max(20, mode.width - 4)) do
				table.insert(out, "    " .. look.ids(mode, piece))
			end
		else
			table.insert(out, l)
		end
	end
	local errors = tonumber(string.match(summary, "(%d+) errors") or "0") or 0
	local warnings = tonumber(string.match(summary, "(%d+) warnings") or "0") or 0
	local e = term.paint(mode, if errors > 0 then "error" else "ok", `{errors} errors`)
	local w = term.paint(mode, if warnings > 0 then "warning" else "ok", `{warnings} warnings`)
	table.insert(out, `{term.paint(mode, "heading", "audit:")} {e}, {w}`)
	return out
end

-- A `=== <title>` heading line (check, promote-check) as a rule.
function look.heading(mode: Mode, line: string): string
	local title = string.match(line, "^=== (.*)$")
	return if title then term.rule(mode, look.ids(mode, title)) else line
end

-- `workstreams`: the plan as waves, ids colored, `parallel:` green for yes.
function look.workstreams(mode: Mode, text: string): { string }
	local out: { string } = {}
	local waves: { [number]: { string } } = {}
	local order: { number } = {}
	local tail: { string } = {}
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		local id, wave = string.match(line, "^([fdcR]%d%d%d%d) wave (%d+)$")
		if id and wave then
			local n = tonumber(wave) :: number
			if not waves[n] then
				waves[n] = {}
				table.insert(order, n)
			end
			table.insert(waves[n], id)
		elseif string.match(line, "^parallel: yes") then
			table.insert(tail, term.paint(mode, "ok", line))
		elseif string.match(line, "^parallel: ") then
			table.insert(tail, term.paint(mode, "warning", line))
		elseif string.match(line, "^raft ") then
			table.insert(out, term.paint(mode, "heading", look.ids(mode, line)))
		elseif line ~= "" then
			table.insert(tail, look.ids(mode, line))
		end
	end
	table.sort(order)
	for _, n in order do
		local ids: { string } = {}
		for _, id in waves[n] do
			table.insert(ids, look.ids(mode, id))
		end
		table.insert(
			out,
			`  {term.paint(mode, "muted", "wave " .. n)} {term.glyph(mode, "arrow")} {table.concat(ids, "  ")}`
		)
	end
	for _, l in tail do
		table.insert(out, l)
	end
	return out
end

-- `lessons` list lines `- <skill>/<slug> (<when>, <n> sources): <check>` with the check wrapped under the id, a
-- bar for the number of sources against the largest; any other line passes through, ids colored.
function look.lessons(mode: Mode, text: string): { string }
	local most = 1
	for count in string.gmatch(text, ", (%d+) sources?%)") do
		most = math.max(most, tonumber(count) or 1)
	end
	local out: { string } = {}
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		local id, when, count, check = string.match(line, "^%- (%S+) %((%a+), (%d+) sources?%): (.*)$")
		if id and when and count and check then
			local n = tonumber(count) :: number
			table.insert(
				out,
				`{term.paint(mode, "heading", id)}  {term.paint(mode, "muted", when)}  {term.paint(
					mode,
					"cyan",
					term.bar(mode, n / most, 8)
				)} {count} sources`
			)
			for _, piece in term.wrap(check, math.max(20, mode.width - 4)) do
				table.insert(out, "    " .. piece)
			end
		elseif string.match(line, "^== ") then
			table.insert(out, term.paint(mode, "heading", line))
		elseif string.match(line, "^lessons: .* ok$") or string.match(line, "^harvest: every finding") then
			table.insert(out, term.paint(mode, "ok", line))
		else
			table.insert(out, look.ids(mode, line))
		end
	end
	if out[#out] == "" then
		table.remove(out)
	end
	return out
end

local function splitRow(line: string): { string }
	local cells: { string } = {}
	local inner = string.match(line, "^|(.*)|%s*$") or line
	for cell in string.gmatch(inner .. "|", "([^|]*)|") do
		table.insert(cells, (string.gsub(string.gsub(cell, "^%s+", ""), "%s+$", "")))
	end
	return cells
end

-- `metrics`: its markdown tables boxed and aligned (numbers right), headings bold; other lines pass through.
function look.markdown(mode: Mode, text: string): { string }
	local out: { string } = {}
	local lines: { string } = {}
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		table.insert(lines, line)
	end
	if lines[#lines] == "" then
		table.remove(lines)
	end
	local v = if mode.unicode then "│" else "|"
	local h = if mode.unicode then "─" else "-"
	local i = 1
	while i <= #lines do
		local line = lines[i]
		if string.sub(line, 1, 1) == "|" then
			local rows: { { string } } = {}
			local header: { string }? = nil
			while i <= #lines and string.sub(lines[i], 1, 1) == "|" do
				if string.match(lines[i], "^|[%s%-:|]+|%s*$") then
					header = rows[1]
				else
					table.insert(rows, splitRow(lines[i]))
				end
				i += 1
			end
			local n = 0
			for _, r in rows do
				n = math.max(n, #r)
			end
			local numeric: { boolean } = {}
			for c = 1, n do
				numeric[c] = true
				for ri, r in rows do
					if not (header and ri == 1) and (r[c] or "") ~= "" and not tonumber(r[c]) then
						numeric[c] = false
					end
				end
			end
			local cols: { term.Column } = {}
			for c = 1, n do
				cols[c] = { right = numeric[c], flex = c == n and not numeric[c] }
			end
			local laid = term.columns(mode, cols, rows)
			for ri, l in laid do
				local shown = string.gsub(l, "  ", ` {term.paint(mode, "muted", v)} `)
				if header and ri == 1 then
					table.insert(out, term.paint(mode, "heading", shown))
					table.insert(
						out,
						term.paint(mode, "muted", string.rep(h, math.min(mode.width, term.width(l))))
					)
				else
					table.insert(out, look.ids(mode, shown))
				end
			end
		else
			if line ~= "" and not string.match(line, "^%s") and string.match(line, "[%.:]$") then
				table.insert(out, term.paint(mode, "heading", line))
			else
				table.insert(out, look.ids(mode, line))
			end
			i += 1
		end
	end
	return out
end

-- `capture`: the header line with its parts told apart; the document below as is.
function look.capture(mode: Mode, text: string): { string }
	local out: { string } = {}
	local first = true
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		if first then
			first = false
			local sha, path, subject = string.match(line, "^capture (%S+) (%S+) (.*)$")
			if sha and path and subject then
				line =
					`{term.paint(mode, "heading", "capture")} {term.paint(mode, "muted", sha)} {path} {look.ids(
						mode,
						subject
					)}`
			end
		end
		table.insert(out, line)
	end
	if out[#out] == "" then
		table.remove(out)
	end
	return out
end

-- A `spend` row `<id> <phase> +<added>/-<removed> <minutes> min[ <tokens> tokens]`: id colored, phase muted,
-- additions green and removals red.
function look.spend(mode: Mode, line: string): { string }
	local id, phase, added, removed, rest = string.match(line, "^(%S+) (%S+) %+(%d+)/%-(%d+) (.*)$")
	if not (id and phase and added and removed and rest) then
		return { look.ids(mode, line) }
	end
	return {
		`{look.ids(mode, id)} {term.paint(mode, "muted", phase)} {term.paint(mode, "green", "+" .. added)}/{term.paint(
			mode,
			"red",
			"-" .. removed
		)} {rest}`,
	}
end

-- The usage text: each command name in bold, its description muted.
function look.usage(mode: Mode, text: string): { string }
	local out: { string } = {}
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		local lead, name, rest = string.match(line, "^(  )(%S+)(.*)$")
		if lead and name and rest then
			local args, desc = string.match(rest, "^(.-)(%s%s%s+.*)$")
			if args and desc then
				line = lead .. term.paint(mode, "heading", name) .. args .. term.paint(mode, "muted", desc)
			else
				line = lead .. term.paint(mode, "heading", name) .. rest
			end
		elseif string.match(line, "^%s%s%s+") then
			line = term.paint(mode, "muted", line)
		elseif line ~= "" then
			line = term.paint(mode, "heading", line)
		end
		table.insert(out, line)
	end
	if out[#out] == "" then
		table.remove(out)
	end
	return out
end

-- A one-line result (`promote-check OK`, a spend sha) marked ok.
function look.ok(mode: Mode, line: string): string
	return `{term.paint(mode, "ok", term.glyph(mode, "pass"))} {term.paint(mode, "ok", line)}`
end

return look
