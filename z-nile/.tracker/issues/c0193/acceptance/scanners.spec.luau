--!strict
-- c0193 AC7: the tooling's text scanners run over every short hostile text and return on each (or refuse by
-- raising) within the limit, and the cases that the reviewed list names, and the scanners c0193 found, are there.
local fs = require("@lune/fs")
local hostile = require("@tests/lib/hostile")
local process = require("@lune/process")
local scanners = require("@tests/lib/scanners")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local ESCAPES: { [string]: string } =
	{ ["\\n"] = "\n", ["\\t"] = "\t", ["\\\\"] = "\\", ['\\"'] = '"', ["\\'"] = "'" }

-- the one-character string literals a module text compares with (`== "x"`, `~= "x"`, `"x" ==`), decoded
local function compared(text: string): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for _, pattern in
		{
			'[=~]=%s*"(\\?.)"',
			"[=~]=%s*'(\\?.)'",
			'"(\\?.)"%s*[=~]=',
			"'(\\?.)'%s*[=~]=",
		}
	do
		for body in string.gmatch(text, pattern) do
			local c = if #body == 1 then body else ESCAPES[body]
			if c then
				out[c] = true
			end
		end
	end
	return out
end

return t.spec("c0193 the tooling's text scanners on hostile texts", function(it)
	it(
		"has no case twice, and gives every case a witness that shows the call reaches the scanner's work",
		function()
			local seen: { [string]: number } = {}
			for _, c in scanners.CASES do
				seen[c.name] = (seen[c.name] or 0) + 1
				t.expect(`{c.name} witness {c.witness ~= nil}`).toBe(`{c.name} witness true`)
			end
			for name, n in seen do
				t.expect(`{name} {n}`).toBe(`{name} 1`)
			end
		end
	)

	it(
		"feeds the cases every default hostile text and each needle with every wider character on either side",
		function()
			local texts = scanners.texts()
			local set: { [string]: boolean } = {}
			for _, s in texts do
				set[s] = true
			end
			t.expect(#texts > #hostile.texts()).toBe(true)
			for _, s in hostile.texts() do
				t.expect(`{string.format("%q", s)} {set[s] == true}`).toBe(`{string.format("%q", s)} true`)
			end
			for _, n in scanners.NEEDLES do
				for _, c in scanners.ALPHABET do
					t.expect(`{n} before {string.format("%q", c)} {set[c .. n] == true}`)
						.toBe(`{n} before {string.format("%q", c)} true`)
					t.expect(`{n} after {string.format("%q", c)} {set[n .. c] == true}`)
						.toBe(`{n} after {string.format("%q", c)} true`)
				end
			end
		end
	)

	it("maps every case's module to a repository file", function()
		for name, file in scanners.files() do
			t.expect(`{name} {file ~= "?" and string.sub(file, -5) == ".luau"}`).toBe(`{name} true`)
			t.expect(`{name} {fs.isFile(`{TOP}/{file}`)}`).toBe(`{name} true`)
		end
	end)

	it("feeds every character that a case's module compares with, or names it on scanners.EXCEPT", function()
		local alphabet: { [string]: boolean } = {}
		for _, c in scanners.ALPHABET do
			alphabet[c] = true
		end
		local missing: { string } = {}
		for _, c in scanners.CASES do
			local file = scanners.files()[c.name]
			if c.module and file ~= "?" then
				local text = fs.readFile(`{TOP}/{file}`)
				for ch in compared(text) do
					local excepted = scanners.EXCEPT[c.name]
					if not alphabet[ch] and not (excepted and excepted[ch]) then
						table.insert(missing, `{c.name} compares with {string.format("%q", ch)}`)
					end
				end
			end
		end
		table.sort(missing)
		t.expect(table.concat(missing, "\n")).toBe("")
	end)

	it("reads the characters a module compares with (the check above sees them)", function()
		local got = compared('if c == "-" and d ~= \'[\' and "\\n" == e and f == "\\\\" and g == "ab" then')
		t.expect(got).toEqual({ ["-"] = true, ["["] = true, ["\n"] = true, ["\\"] = true })
	end)

	it("[zz-arch/scanning-loops-advance] finishes: no scanner spins on a hostile text", function()
		local r = hostile.finishes("c0193-scanners", scanners.CASES, scanners.texts())
		t.expect(r.message).toBe("")
		t.expect(r.ok).toBe(true)
	end)
end)
