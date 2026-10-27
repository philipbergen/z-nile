--!strict
-- c0144 AC1: the pure rules of terminal output (z-nile/engine/term.luau): when output is rich and when it is
-- colored (a terminal, the --color choice, NO_COLOR, TERM=dumb), the width a line may use, and the helpers every
-- command's look is built from (paint, links, visible width, fitting, wrapping, aligned columns, bars, glyphs).
local look = require("@znile/engine/look")
local t = require("@tests/lib/t")
local term = require("@znile/engine/term")

local ESC = "\27"
local UTF8 = { LANG = "en_US.UTF-8" }

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

local function rich(width: number?): term.Mode
	return { rich = true, color = true, links = true, unicode = true, width = width or 80 }
end

return t.spec("c0144 terminal output rules", function(it)
	it("decides rich layout and color from the terminal, the choice, NO_COLOR and TERM", function()
		local cases = {
			-- choice, env, tty → rich, color
			{ "auto", {}, false, false, false },
			{ "auto", {}, true, true, true },
			{ "auto", { NO_COLOR = "1" }, true, true, false },
			{ "auto", { NO_COLOR = "" }, true, true, true }, -- an empty NO_COLOR is unset (no-color.org)
			{ "auto", { TERM = "dumb" }, true, true, false },
			{ "never", {}, true, true, false },
			{ "never", {}, false, false, false },
			{ "always", {}, false, true, true },
			{ "always", { NO_COLOR = "1" }, false, true, true }, -- the explicit flag wins
			{ "always", { TERM = "dumb" }, true, true, true },
		}
		for _, c in cases do
			local m = term.decide(c[1] :: any, c[2] :: any, c[3] :: boolean, 100)
			t.expect({ case = c, rich = m.rich, color = m.color })
				.toEqual({ case = c, rich = c[4], color = c[5] })
		end
		-- not a terminal and not forced: exactly the plain mode
		t.expect(term.decide("auto", { NO_COLOR = "" }, false, 100)).toBe(term.PLAIN)
	end)

	it("takes the width from COLUMNS, then the terminal, then 80, and refuses less than 20", function()
		t.expect(term.decide("auto", { COLUMNS = "132" }, true, 90).width).toBe(132)
		t.expect(term.decide("auto", {}, true, 90).width).toBe(90)
		t.expect(term.decide("auto", {}, true, nil).width).toBe(80)
		t.expect(term.decide("auto", { COLUMNS = "7" }, true, 0).width).toBe(80)
		t.expect(term.decide("auto", { COLUMNS = "wide" }, true, 64).width).toBe(64)
		t.expect(term.decide("always", {}, false, nil).width).toBe(80)
	end)

	it("uses Unicode glyphs only under a UTF-8 locale, LC_ALL first, and links only with color", function()
		t.expect(term.decide("auto", UTF8, true, 80).unicode).toBe(true)
		t.expect(term.decide("auto", { LANG = "C" }, true, 80).unicode).toBe(false)
		t.expect(term.decide("auto", { LC_ALL = "C", LANG = "en_US.UTF-8" }, true, 80).unicode).toBe(false)
		t.expect(term.decide("auto", { LC_CTYPE = "en_US.utf8" }, true, 80).unicode).toBe(true)
		t.expect(term.decide("auto", {}, true, 80).links).toBe(true)
		t.expect(term.decide("auto", { ZN_HYPERLINKS = "0" }, true, 80).links).toBe(false)
		t.expect(term.decide("auto", { NO_COLOR = "1" }, true, 80).links).toBe(false)
	end)

	it("reads the --color choice and refuses any other value, naming the rule", function()
		t.expect(term.choice(nil)).toBe("auto")
		t.expect(term.choice("auto")).toBe("auto")
		t.expect(term.choice("always")).toBe("always")
		t.expect(term.choice("never")).toBe("never")
		local bad, why = term.choice("sometimes")
		t.expect(bad).toBe(nil)
		t.expect(why).toBe('--color takes auto, always or never (got "sometimes")')
	end)

	it("paints only with color, and the stripped text is the text", function()
		local off: term.Mode = { rich = true, color = false, links = false, unicode = true, width = 80 }
		t.expect(term.paint(off, "pass", "PASS")).toBe("PASS")
		local on = term.paint(rich(), "pass", "PASS")
		t.expect(has(on, ESC)).toBe(true)
		t.expect(term.strip(on)).toBe("PASS")
		t.expect(term.paint(rich(), "fail", "x")).toBe("\27[31;1mx\27[0m")
		t.expect(term.paint(rich(), "new", "new")).toBe("new") -- a style with no codes adds none
	end)

	it("links with OSC 8 only when links are on, and a link takes no columns", function()
		local linked = term.link(rich(), "file:///tmp/f0001.md", "f0001")
		t.expect(linked).toBe("\27]8;;file:///tmp/f0001.md\27\\f0001\27]8;;\27\\")
		t.expect(term.width(linked)).toBe(5)
		local nolinks: term.Mode = { rich = true, color = true, links = false, unicode = true, width = 80 }
		t.expect(term.link(nolinks, "file:///tmp/x", "f0001")).toBe("f0001")
		t.expect(term.link(rich(), nil, "f0001")).toBe("f0001")
	end)

	it("measures, fits and wraps by visible columns", function()
		t.expect(term.width("\27[1mé…\27[0m")).toBe(2)
		t.expect(term.fit(rich(), "abcdefghij", 6)).toBe("abcde…")
		t.expect(term.fit(rich(), "abc", 6)).toBe("abc")
		local ascii: term.Mode = { rich = true, color = true, links = true, unicode = false, width = 80 }
		t.expect(term.fit(ascii, "abcdefghij", 6)).toBe("abcde.")
		t.expect(term.wrap("one two three four", 9)).toEqual({ "one two", "three", "four" })
		t.expect(term.wrap("", 9)).toEqual({ "" })
	end)

	it("aligns columns, right-aligns numbers and shrinks the flex column to the width", function()
		local cols: { term.Column } = { {}, { flex = true }, { right = true } }
		local rows = { { "f0001", "a long title that will not fit", "7" }, { "c0002", "short", "123" } }
		local wide = term.columns(rich(100), cols, rows)
		t.expect(wide[2]).toBe("c0002  short                           123")
		local narrow = term.columns(rich(30), cols, rows)
		for _, line in narrow do
			t.expect({ line = line, fits = term.width(line) <= 30 }).toEqual({ line = line, fits = true })
		end
		t.expect(has(narrow[1], "…")).toBe(true)
		t.expect(string.sub(narrow[2], -3)).toBe("123")
		-- the flex column never shrinks below 8: a table that can't fit is wider than the width
		local tiny = term.columns(rich(10), cols, rows)
		t.expect(term.width(tiny[1]) > 10).toBe(true)
	end)

	it("draws bars in eighths, or in # and . without Unicode", function()
		t.expect(term.bar(rich(), 1, 4)).toBe("████")
		t.expect(term.bar(rich(), 0, 4)).toBe("    ")
		t.expect(term.bar(rich(), 0.5, 4)).toBe("██  ")
		t.expect(term.bar(rich(), 0.53125, 4)).toBe("██▏ ")
		local ascii: term.Mode = { rich = true, color = false, links = false, unicode = false, width = 80 }
		t.expect(term.bar(ascii, 0.5, 4)).toBe("##..")
		t.expect(term.glyph(ascii, "pass")).toBe("+")
		t.expect(term.glyph(rich(), "pass")).toBe("✔")
	end)

	it(
		"links an active raft to its pull requests on GitHub from origin's URL, and to nothing elsewhere",
		function()
			local q = "https://github.com/acme/pick-man/pulls?q=is%3Apr+head%3AR0003-frame%2Btol"
			t.expect(look.prUrl("git@github.com:acme/pick-man.git\n", "R0003-frame+tol")).toBe(q)
			t.expect(look.prUrl("https://github.com/acme/pick-man.git", "R0003-frame+tol")).toBe(q)
			t.expect(look.prUrl("https://github.com/acme/pick-man", "R0003-frame+tol")).toBe(q)
			t.expect(look.prUrl("ssh://git@github.com/acme/pick-man.git", "R0003-frame+tol")).toBe(q)
			t.expect(look.prUrl("/tmp/origin.git", "R0003-x")).toBe(nil)
			t.expect(look.prUrl("https://gitlab.com/acme/pick-man.git", "R0003-x")).toBe(nil)
			t.expect(look.prUrl(nil, "R0003-x")).toBe(nil)
		end
	)
end)
