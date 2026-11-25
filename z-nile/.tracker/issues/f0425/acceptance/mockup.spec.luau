--!strict
-- f0425 AC2-AC6: the approvals mockup on main holds what the ticket's Solution says it holds. String reads of two files
-- only (the mockup and z-nile/README.html), so it runs at the speed of a file read. One case per criterion; check.sh runs
-- this spec once per criterion. The mockup is found where f0437's app-copy.spec looks for it, because f0425's folder
-- moves between issues/, issues/active/ and issues/done/.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

-- runs from z-nile/ (the project's home): every path this spec reads is the repository's, from its top
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local MOCKUPS = {
	"z-nile/.tracker/issues/f0425/mockup/index.html",
	"z-nile/.tracker/issues/active/f0425/mockup/index.html",
	"z-nile/.tracker/issues/done/f0425/mockup/index.html",
}
local README = "z-nile/README.html"

local function mockup(): string
	for _, candidate in MOCKUPS do
		if fs.isFile(`{TOP}/{candidate}`) then
			return fs.readFile(`{TOP}/{candidate}`)
		end
	end
	error(`the f0425 mockup is in none of {table.concat(MOCKUPS, ", ")}`, 0)
end

local function at(text: string, needle: string, where: string)
	if string.find(text, needle, 1, true) == nil then
		error(`{where} is missing: {needle}`, 2)
	end
end

local function absent(text: string, needle: string, where: string)
	if string.find(text, needle, 1, true) ~= nil then
		error(`{where} still holds: {needle}`, 2)
	end
end

-- The page's one inline script.
local function script(page: string): string
	local body = string.match(page, "<script>(.-)</script>")
	if body == nil then
		error("the mockup has no inline <script>", 2)
	end
	return body :: string
end

-- The keys of a one-line object literal `const NAME = { a: "x", b: "y" };` in the script.
local function keysOf(src: string, name: string): { string }
	local body = string.match(src, "const " .. name .. " = (%b{})")
	if body == nil then
		error(`the script has no object literal {name}`, 2)
	end
	local keys: { string } = {}
	for key in string.gmatch(body :: string, "([%a]+)%s*:") do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

local KINDS = { "event", "guess", "queue", "raft", "stat", "ticket", "tributary", "worker" }

-- The `--name:#rrggbb` tokens of one CSS block (its text between the selector's braces).
local function tokens(page: string, selector: string): { [string]: string }
	local at0 = string.find(page, "\n" .. selector .. "{", 1, true)
	if at0 == nil then
		error(`the mockup has no {selector} block`, 2)
	end
	local block = string.match(page, "%b{}", at0) :: string
	local out: { [string]: string } = {}
	for name, hex in string.gmatch(block, "%-%-([%w%-]+):(#%x%x%x%x%x%x)") do
		out[name] = string.lower(hex)
	end
	return out
end

-- The hue of a colour in degrees, or nil for a grey (no hue to judge).
local function hue(hex: string): number?
	local r = tonumber(string.sub(hex, 2, 3), 16) :: number / 255
	local g = tonumber(string.sub(hex, 4, 5), 16) :: number / 255
	local b = tonumber(string.sub(hex, 6, 7), 16) :: number / 255
	local hi, lo = math.max(r, g, b), math.min(r, g, b)
	local d = hi - lo
	if d < 0.08 then
		return nil
	end
	local h
	if hi == r then
		h = ((g - b) / d) % 6
	elseif hi == g then
		h = (b - r) / d + 2
	else
		h = (r - g) / d + 4
	end
	return h * 60
end

-- the status and chart tokens the third Decided line keeps bright, with their backgrounds
local STATUS = { "easy", "normal", "risky", "wait", "ok", "back", "land" }
local SERIES = { "s1", "s2", "s3", "s4", "s5", "s6" }

return t.spec("f0425 the approvals mockup holds what its Solution says", function(it)
	it(
		"AC2: every kind of item has its own route and a Talk control, and the four other views are routed",
		function()
			local src = script(mockup())
			t.expect(table.concat(keysOf(src, "V"), " ")).toBe(table.concat(KINDS, " "))
			t.expect(table.concat(keysOf(src, "TALK_LABEL"), " ")).toBe(table.concat(KINDS, " "))
			for _, kind in KINDS do
				at(src, `talkBtn(ref("{kind}"`, `a Talk button for a {kind}`)
			end
			at(src, 'if (a === "workers" || a === "stats")', "the Workers and Stats routes")
			at(src, 'if (a === "tickets" || a === "rafts")', "the Tickets and Rafts routes")
			at(src, 'return "zn talk " + refStr(talk.ref)', "the zn talk command a Talk control shows")
		end
	)

	it("AC3: the script calls no network API, and the page's only URLs are Google Fonts'", function()
		local page = mockup()
		local src = script(page)
		for _, api in
			{ "fetch(", "XMLHttpRequest", "WebSocket", "EventSource", "sendBeacon", "import(", "new Image" }
		do
			absent(src, api, "the mockup's script")
		end
		local hosts = 0
		for host in string.gmatch(page, "https?://([%w%.%-]+)") do
			hosts += 1
			if host ~= "fonts.googleapis.com" and host ~= "fonts.gstatic.com" then
				error(`the mockup names a URL on {host}`, 0)
			end
		end
		t.expect(hosts > 0).toBe(true)
	end)

	it(
		"AC4: the mockup opens light in the site's gold-e colours and fonts, with no purple status or series colour",
		function()
			local page = mockup()
			t.expect(string.match(page, "<html[^>]*>")).toBe('<html lang="en" data-theme="light">')
			local link = string.match(
				page,
				'<link rel="stylesheet" href="(https://fonts%.googleapis%.com/[^"]*)"'
			) or ""
			for _, family in { "family=Instrument+Serif", "family=Geist:", "family=Geist+Mono" } do
				at(link, family, "the font link")
			end
			local light = tokens(page, ":root")
			local gold = {
				bg = "#f8f7f4",
				surface = "#ffffff",
				text = "#2c2723",
				["text-2"] = "#6e655a",
				line = "#e3e0d6",
				accent = "#7a5a18",
				["accent-strong"] = "#f4d98e",
			}
			for name, value in gold do
				t.expect(`--{name}:{light[name]}`).toBe(`--{name}:{value}`)
			end
			local dark = tokens(page, '[data-theme="dark"]')
			for _, block in { light, dark } do
				for _, list in { STATUS, SERIES } do
					for _, name in list do
						for _, key in { name, `{name}-bg` } do
							local value = block[key]
							local h = if value then hue(value) else nil
							if h and h >= 250 and h <= 320 then
								error(`--{key}:{value} is purple (hue {math.floor(h)})`, 0)
							end
						end
					end
				end
				for _, name in STATUS do
					t.expect(block[name] ~= nil).toBe(true)
				end
				for _, name in SERIES do
					t.expect(block[name] ~= nil).toBe(true)
				end
			end
		end
	)

	it(
		"AC5: README.html uses the same fonts, opens light whatever the OS prefers, and has the theme button",
		function()
			local page = fs.readFile(`{TOP}/{README}`)
			local link = string.match(
				page,
				'<link rel="stylesheet" href="(https://fonts%.googleapis%.com/[^"]*)"'
			) or ""
			for _, family in { "family=Instrument+Serif", "family=Geist:", "family=Geist+Mono" } do
				at(link, family, "README.html's font link")
			end
			absent(page, "Bricolage", "README.html")
			absent(page, "Plex", "README.html")
			absent(page, "prefers-color-scheme", "README.html")
			at(page, '<button class="theme" id="theme"', "README.html's theme button")
			at(page, 'document.getElementById("theme")', "README.html's theme script")
			at(page, 'r.setAttribute("data-theme", dark ? "light" : "dark")', "README.html's theme toggle")
		end
	)

	it("AC6: the mockup names the seven stages and says what a raft is in plain words", function()
		local page = mockup()
		at(
			script(page),
			'const STEPS = ["Idea", "Design", "Bundle", "Code", "Review", "Approval", "Landed"];',
			"the seven stages"
		)
		at(page, "A raft is a bundle of tickets delivered together", "the plain words for a raft")
	end)
end)
