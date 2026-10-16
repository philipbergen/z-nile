--!strict
-- Pure SVG charts for the tracker board. No paint in the markup: the page CSS colors by class.
local chart = {}

export type Series = { key: string, label: string, values: { number? }, notes: { string? }? }
export type Options = {
	id: string,
	title: string,
	unit: string,
	labels: { string },
	kind: "bars" | "stacked" | "mirror" | "lines" | "hbars",
	below: { Series }?,
}

local W = 640

local function esc(s: string): string
	return (
		string.gsub(
			string.gsub(string.gsub(string.gsub(s, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"),
			'"',
			"&quot;"
		)
	)
end

-- One decimal, trailing .0 dropped, ASCII minus. Tenths stay exact so stacked edges add back up.
local function fmtT(tenths: number): string
	local sign = ""
	if tenths < 0 then
		sign = "-"
		tenths = -tenths
	end
	local whole = tenths // 10
	local frac = tenths % 10
	if frac == 0 then
		return `{sign}{whole}`
	end
	return `{sign}{whole}.{frac}`
end

local function tenths(n: number): number
	local sign = if n < 0 then -1 else 1
	return sign * math.floor(math.abs(n) * 10 + 0.5)
end

local function fmt(n: number): string
	return fmtT(tenths(n))
end

local function nice(lo: number, hi: number): (number, number, number)
	if lo == 0 and hi == 0 then
		return 0, 2, 1
	end
	local span = hi - lo
	local function fit(step: number): (number?, number?, number?)
		if step < 0.1 - 1e-9 then
			return nil
		end
		local bottom = math.floor(lo / step + 1e-8) * step
		local top = math.ceil(hi / step - 1e-8) * step
		if bottom > lo then
			bottom -= step
		end
		if top < hi then
			top += step
		end
		local count = math.floor((top - bottom) / step + 0.5) + 1
		if count < 3 or count > 6 or top + 1e-6 < hi or bottom - 1e-6 > lo then
			return nil
		end
		return bottom, top, count
	end
	local exp = math.floor(math.log10(math.max(span / 4, 0.1)))
	local bestLo, bestHi, bestStep, bestScore = 0, 1, 1, math.huge
	for e = exp - 2, exp + 3 do
		local pow = 10 ^ e
		for _, mant in { 1, 2, 5 } do
			local step = mant * pow
			local bottom, top, count = fit(step)
			if bottom and top and count then
				local score = math.abs(count - 5) * 1000 + (top - bottom)
				if score < bestScore then
					bestScore = score
					bestLo, bestHi, bestStep = bottom, top, step
				end
			end
		end
	end
	return bestLo, bestHi, bestStep
end

local function labelIndexes(n: number): { number }
	local out: { number } = {}
	if n <= 8 then
		for i = 1, n do
			table.insert(out, i)
		end
		return out
	end
	for k = 0, 7 do
		table.insert(out, math.floor(1 + k * (n - 1) / 7 + 0.5))
	end
	return out
end

function chart.svg(series: { Series }, opts: Options): string
	local labels = opts.labels
	local n = #labels
	local kind = opts.kind
	local below = opts.below or {}
	local hbars = kind == "hbars"
	local keys: { { key: string, label: string } } = {}
	local seen: { [string]: boolean } = {}
	local function addKey(entry: Series)
		if not seen[entry.key] then
			seen[entry.key] = true
			table.insert(keys, { key = entry.key, label = entry.label })
		end
	end
	for _, entry in series do
		addKey(entry)
	end
	for _, entry in below do
		addKey(entry)
	end
	local showLegend = #keys >= 2

	local lo, hi = 0, 0
	local nonempty = false
	local function note(v: number?)
		if v and v ~= 0 then
			nonempty = true
			lo = math.min(lo, v)
			hi = math.max(hi, v)
		end
	end
	if kind == "stacked" then
		for i = 1, n do
			local up = 0
			for _, entry in series do
				local v = entry.values[i]
				if v and v > 0 then
					up += v
					nonempty = true
				elseif v and v < 0 then
					note(v)
				end
			end
			hi = math.max(hi, up)
		end
	elseif kind == "mirror" then
		for i = 1, n do
			local up, down = 0, 0
			for _, entry in series do
				local v = entry.values[i]
				if v and v > 0 then
					up += v
					nonempty = true
				end
			end
			for _, entry in below do
				local v = entry.values[i]
				if v and v > 0 then
					down += v
					nonempty = true
				end
			end
			hi = math.max(hi, up)
			lo = math.min(lo, -down)
		end
	else
		local lists: { { Series } } = { series, below }
		for _, list in lists do
			for _, entry in list do
				for _, v in entry.values do
					note(v)
				end
			end
		end
	end
	lo = math.min(lo, 0)
	hi = math.max(hi, 0)
	if not nonempty then
		lo, hi = 0, 0
	end
	local axisLo, axisHi, step = nice(lo, hi)
	local span = axisHi - axisLo

	local H = if hbars then 40 + 28 * math.max(n, 1) else 200
	local padL = if hbars then 72 else 44
	local padR = 12
	local padT = if hbars then 20 else 12
	local padB = if hbars then 20 elseif showLegend then 34 else 20
	local plotW = W - padL - padR
	local plotH = H - padT - padB
	local slot = if n > 0 then plotW / n else plotW

	local function yPix(v: number): number
		return padT + plotH * (1 - (v - axisLo) / span)
	end
	local baseY = yPix(0)
	local baseT = tenths(baseY)

	local parts: { string } = {}
	local function push(s: string)
		table.insert(parts, s)
	end
	local function tip(label: string, bucket: string, value: number, noteText: string?): string
		local text = `{label}, {bucket}: {fmt(value)} {opts.unit}`
		if noteText and noteText ~= "" then
			text ..= ` ({noteText})`
		end
		return esc(text)
	end
	local function mark(cls: string, x: number, y: number, w: number, h: number, title: string)
		push(
			`<rect class="{cls}" x="{fmtT(x)}" y="{fmtT(y)}" width="{fmtT(w)}" height="{fmtT(h)}"><title>{title}</title></rect>`
		)
	end

	push(
		`<svg class="chart" data-chart="{esc(opts.id)}" role="img" aria-label="{esc(opts.title)}" viewBox="0 0 {W} {H}"><title>{esc(
			opts.title
		)}</title>`
	)

	local ticks: { number } = {}
	local steps = math.floor((axisHi - axisLo) / step + 0.5)
	for i = 0, steps do
		table.insert(ticks, axisLo + i * step)
	end

	if hbars then
		local x0 = tenths(padL)
		local rowH = 28
		push(
			`<line class="baseline" x1="{fmtT(x0)}" y1="{fmtT(tenths(padT))}" x2="{fmtT(x0)}" y2="{fmtT(
				tenths(padT + rowH * math.max(n, 1))
			)}"></line>`
		)
		for i = 1, n do
			local rowY = padT + (i - 1) * rowH
			push(
				`<text class="x" x="{fmtT(tenths(padL - 8))}" y="{fmtT(tenths(rowY + rowH / 2))}" text-anchor="end" dominant-baseline="middle">{esc(
					labels[i]
				)}</text>`
			)
			local band = rowH / math.max(#series, 1)
			for si, entry in series do
				local v = entry.values[i]
				if nonempty and v and v ~= 0 then
					local hT = math.max(tenths(band - 6), 1)
					local yT = tenths(rowY + (si - 1) * band + (band - hT / 10) / 2)
					local wT = math.max(tenths(math.abs(v) / axisHi * plotW), 1)
					local notes = entry.notes
					mark(
						`mark ser-{entry.key}`,
						x0,
						yT,
						wT,
						hT,
						tip(entry.label, labels[i], v, if notes then notes[i] else nil)
					)
				end
			end
		end
	else
		local x1 = tenths(padL)
		local x2 = tenths(padL + plotW)
		for _, tick in ticks do
			if math.abs(tick) > 1e-9 then
				local y = tenths(yPix(tick))
				push(
					`<line class="grid" x1="{fmtT(x1)}" y1="{fmtT(y)}" x2="{fmtT(x2)}" y2="{fmtT(y)}"></line>`
				)
			end
		end
		push(
			`<line class="baseline" x1="{fmtT(x1)}" y1="{fmtT(baseT)}" x2="{fmtT(x2)}" y2="{fmtT(baseT)}"></line>`
		)
		for _, tick in ticks do
			push(
				`<text class="tick" x="{fmtT(tenths(padL - 6))}" y="{fmtT(tenths(yPix(tick)))}" text-anchor="end" dominant-baseline="middle">{fmt(
					tick
				)}</text>`
			)
		end
		for _, index in labelIndexes(n) do
			local x = padL + (index - 0.5) * slot
			push(
				`<text class="x" x="{fmtT(tenths(x))}" y="{fmtT(tenths(H - padB + 12))}" text-anchor="middle" dominant-baseline="middle">{esc(
					labels[index]
				)}</text>`
			)
		end

		local gap = 20 -- 2px, in tenths
		local barW = math.max(tenths(slot) - gap, 1)
		for i = 1, n do
			local xT = tenths(padL + (i - 1) * slot) + gap // 2
			if kind == "mirror" then
				local cursor = baseT
				local first = true
				for _, entry in series do
					local v = entry.values[i]
					if nonempty and v and v > 0 then
						local hT = math.max(tenths(v / span * plotH), 1)
						if not first then
							cursor -= gap
						end
						local yT = cursor - hT
						mark(`mark ser-{entry.key}`, xT, yT, barW, hT, tip(entry.label, labels[i], v, nil))
						cursor = yT
						first = false
					end
				end
				cursor = baseT
				first = true
				for _, entry in below do
					local v = entry.values[i]
					if nonempty and v and v > 0 then
						local hT = math.max(tenths(v / span * plotH), 1)
						if not first then
							cursor += gap
						end
						mark(
							`mark ser-{entry.key}`,
							xT,
							cursor,
							barW,
							hT,
							tip(entry.label, labels[i], v, nil)
						)
						cursor += hT
						first = false
					end
				end
			elseif kind == "stacked" then
				local cursor = baseT
				local first = true
				for _, entry in series do
					local v = entry.values[i]
					if nonempty and v and v > 0 then
						local hT = math.max(tenths(v / span * plotH), 1)
						if not first then
							cursor -= gap
						end
						local yT = cursor - hT
						mark(`mark ser-{entry.key}`, xT, yT, barW, hT, tip(entry.label, labels[i], v, nil))
						cursor = yT
						first = false
					end
				end
			else
				local entry = series[1]
				local v = entry and entry.values[i]
				if nonempty and entry and v and v ~= 0 then
					local hT = math.max(tenths(math.abs(v) / span * plotH), 1)
					local yT = if v > 0 then baseT - hT else baseT
					local notes = entry.notes
					mark(
						`mark ser-{entry.key}`,
						xT,
						yT,
						barW,
						hT,
						tip(entry.label, labels[i], v, if notes then notes[i] else nil)
					)
				end
			end
		end

		if kind == "lines" and nonempty then
			for _, entry in series do
				local d: { string } = {}
				local pen = false
				local circles: { string } = {}
				for i = 1, n do
					local v = entry.values[i]
					if v == nil then
						pen = false
					else
						local xT = tenths(padL + (i - 0.5) * slot)
						local yT = tenths(yPix(v))
						table.insert(d, if pen then `L {fmtT(xT)} {fmtT(yT)}` else `M {fmtT(xT)} {fmtT(yT)}`)
						pen = true
						table.insert(
							circles,
							`<circle class="point ser-{entry.key}" cx="{fmtT(xT)}" cy="{fmtT(yT)}" r="4"></circle>`
						)
					end
				end
				if #d > 0 then
					push(`<path class="line ser-{entry.key}" d="{table.concat(d, " ")}"></path>`)
					for _, circle in circles do
						push(circle)
					end
				end
			end
		end
	end

	if not nonempty then
		push(
			`<text class="empty" x="{fmtT(tenths(W / 2))}" y="{fmtT(tenths(H / 2))}" text-anchor="middle" dominant-baseline="middle">no data</text>`
		)
	end
	if showLegend then
		push(`<g class="legend">`)
		local x = 8
		for _, entry in keys do
			local y = H - 14
			push(
				`<rect class="swatch ser-{entry.key}" x="{x}" y="{y}" width="8" height="8"></rect><text class="legend-label" x="{x + 12}" y="{y + 4}" dominant-baseline="middle">{esc(
					entry.label
				)}</text>`
			)
			x += 12 + #entry.label * 7 + 16
		end
		push(`</g>`)
	end
	push(`</svg>`)
	return table.concat(parts)
end

return chart
