--!strict
-- f0186 AC7: the documents say what the user decided (2026-10-31), and pickman's free game stays its own. In
-- game-design.md's Paid play section: the boards and the game over show the revives a run used (in place of f0145's
-- lives spent, which no longer appears), pickman's free game is one per hour for pickman alone, and the price of a
-- play shows as 5 R$ struck through, on sale for 1 R$; the Hiscores entries name the revives. architecture.md declares
-- Flow -> Lobby (Flow's revives line uses Lobby's words). Pickman's paid-play records stay in pickman's own stores,
-- the names the arcade library's catalog gives pickman (f0201), so no other title's play spends its free hour.
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

local function has(src: string, needle: string): boolean
	return string.find(src, needle, 1, true) ~= nil
end

-- the text of the section under `heading` (to the next "## " heading)
local function section(doc: string, heading: string): string
	local at = string.find(doc, heading, 1, true)
	assert(at, `no section {heading}`)
	local rest = string.sub(doc, at + #heading)
	local stop = string.find(rest, "\n## ", 1, true)
	return if stop then string.sub(rest, 1, stop) else rest
end

return t.spec("f0186 the documents and pickman's own free game", function(it)
	it(
		"game-design.md's paid play says revives, a free game per game and the sale price; lives spent is gone",
		function()
			local design = fs.readFile(".tracker/game-design.md")
			local paid = section(design, "## Paid play (f0145")
			for _, phrase in
				{
					"**Revives on the boards (f0186)",
					"revives used",
					"**A free game per game (f0186)",
					"one free game per hour for Pickman",
					"**The price shown (f0186)",
					"5 R$",
					"struck through",
					"1 R$",
				}
			do
				if not has(paid, phrase) then
					error(`game-design.md's Paid play section lacks: {phrase}`)
				end
			end
			t.expect(has(design, "lives spent")).toBe(false)
			local entries = string.match(design, "\n%- %*%*Entries:%*%*[^\n]*") or ""
			t.expect(has(entries, "revives")).toBe(true)
		end
	)

	it("architecture.md declares Flow -> Lobby", function()
		local arch = fs.readFile(".tracker/architecture.md")
		local deps = "\n" .. (string.match(arch, "```deps\n(.-)```") or "")
		t.expect(has(deps, "\nFlow -> Lobby\n")).toBe(true)
	end)

	it("pickman's paid-play records stay in pickman's own stores, keyed by user id", function()
		local Pay = require("@logic/Pay") -- f0145's: required here, so the other cases run on a tree without it
		t.expect(Pay.STORE).toBe("PaidPlay")
		t.expect(Pay.TEST_STORE).toBe("PaidPlayTest")
		t.expect(Pay.store("live")).toBe("PaidPlay")
		t.expect(Pay.store("closed")).toBe("PaidPlay")
		t.expect(Pay.store("test")).toBe("PaidPlayTest")
	end)
end)
