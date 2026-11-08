--!strict
-- c0260 AC8: the places that restate the flow agree
-- Shape rules over the text of z-design, zz-rules and the README (the exact wording is not pinned: a place can be
-- reworded and stay green; a place that stops saying it fails).
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local ROOT = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local function readme(): string
	return fs.readFile(`{ROOT}/z-nile/README.md`)
end
local function skill(name: string): string
	return fs.readFile(`{ROOT}/z-nile/skills/{name}/SKILL.md`)
end
local function has(text: string, part: string): boolean
	return string.find(text, part, 1, true) ~= nil
end
return t.spec("c0260 the places that restate the flow agree", function(it)
	it(
		"AC8: z-design reads the capture folder, treats the confirmed Problem as the scope, and asks the user the `ask:` lines",
		function()
			local d = skill("z-design")
			t.expect(has(d, "**The capture folder.**")).toBe(true)
			t.expect(has(d, "never widens or narrows it")).toBe(true)
			t.expect(has(d, "- Fn: ask:")).toBe(true)
			t.expect(has(d, "Confirmed (user, YYYY-MM-DD)")).toBe(true) -- z-design replaces the unattended line
			t.expect(has(d, "before the first review round")).toBe(true)
		end
	)

	it(
		"AC8: zz-rules lists the capture folder in the item layout and the idea mode among the dispatcher's",
		function()
			local r = skill("zz-rules")
			t.expect(has(r, "<ID>/capture/ask.md")).toBe(true)
			t.expect(has(r, "idea-review-NNN.md, idea-refute-NNN.md")).toBe(true)
			t.expect(string.match(r, "%(modes[^)]*`idea`") ~= nil).toBe(true) -- idea is among the modes, in any order
		end
	)

	it(
		"AC8: the README's Skills row and flow step 1 describe the interview and the record, and the Roadmap has c0260's row",
		function()
			local r = readme()
			local row = string.match(r, "\n| `z%-ticket` | 1 | ([^\n]*)") or ""
			t.expect(has(row, "interviews the user")).toBe(true)
			t.expect(has(row, "capture/ask.md")).toBe(true)
			t.expect(has(row, "zz-review --mode idea")).toBe(true)
			local step = string.match(r, "\n1%. %*%*z%-ticket%*%*([^\n]*)") or ""
			t.expect(has(step, "interviewed")).toBe(true)
			t.expect(has(step, "`capture/`")).toBe(true)
			local roadmap = string.match(r, "\n### Roadmap\n(.-)\n### ") or ""
			t.expect(string.match(roadmap, "\n| [^\n]*| c0260 | %a+ |\n") ~= nil).toBe(true)
		end
	)

	it("AC8: zz-rules' land and direct-push sentences name the capture/ files a capture may carry", function()
		local r = skill("zz-rules")
		local land = string.match(r, "A capture lands with `./zn land` instead[^\n]*") or ""
		t.expect(has(land, "`capture/` files")).toBe(true)
		local direct = string.match(r, "%*%*The direct%-push exception%.%*%*[^\n]*") or ""
		t.expect(has(direct, "`capture/` files")).toBe(true)
		t.expect(has(r, "idea-review-NNN")).toBe(true)
	end)
end)
