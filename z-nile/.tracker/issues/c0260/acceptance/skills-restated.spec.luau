--!strict
-- c0260 AC8: the places that restate the flow agree: z-design, zz-rules and the README. Shape rules over their text
-- (the exact wording is not pinned: a place can be reworded and stay green; a place that stops saying it fails).
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local ROOT = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local function skill(name: string): string
	return fs.readFile(`{ROOT}/z-nile/skills/{name}/SKILL.md`)
end
local function readme(): string
	return fs.readFile(`{ROOT}/z-nile/README.md`)
end
local function has(text: string, part: string): boolean
	return string.find(text, part, 1, true) ~= nil
end

return t.spec("c0260 the places that restate the flow agree", function(it)
	it(
		"AC8: z-design confirms an unattended capture first, as the one small exception, and changes nothing else",
		function()
			local d = skill("z-design")
			t.expect(has(d, "not designed until the user confirms it")).toBe(true)
			t.expect(has(d, "small exception")).toBe(true)
			t.expect(has(d, "Nothing else in z-design changes")).toBe(true)
			t.expect(has(d, "update `## Idea` to match")).toBe(true) -- the extra review round judges the answered idea
			t.expect(has(d, "No Design, `design: reviewed` or `ready` is written before that line exists"))
				.toBe(true)
			t.expect(has(d, "subagent form of z-ticket step 4a")).toBe(true)
			t.expect(has(d, "- Fn: ask:")).toBe(true)
			t.expect(has(d, "Confirmed (<who>, YYYY-MM-DD)")).toBe(true) -- a distinct line, the Unconfirmed one stays
		end
	)

	it(
		"AC8: zz-rules lists the capture folder in the item layout, the idea mode among the dispatcher's, and what land carries",
		function()
			local r = skill("zz-rules")
			t.expect(has(r, "<ID>/capture/idea-review-NNN.md")).toBe(true)
			t.expect(string.match(r, "%(modes[^)]*`idea`") ~= nil).toBe(true) -- idea is among the modes, in any order
			local land = string.match(r, "A capture lands with `./zn land` instead[^\n]*") or ""
			t.expect(has(land, "capture/idea-review-NNN.md")).toBe(true)
			local direct = string.match(r, "%*%*The direct%-push exception%.%*%*[^\n]*") or ""
			t.expect(has(direct, "capture/idea-review-NNN.md")).toBe(true)
		end
	)

	it(
		"AC8: the README's Skills row and flow step 1 describe the interview and the record, and the Roadmap has c0260's row",
		function()
			local r = readme()
			local row = string.match(r, "\n| `z%-ticket` | 1 | ([^\n]*)") or ""
			t.expect(has(row, "interviews the user")).toBe(true)
			t.expect(has(row, "zz-review --mode idea")).toBe(true)
			local step = string.match(r, "\n1%. %*%*z%-ticket%*%*([^\n]*)") or ""
			t.expect(has(step, "interviewed")).toBe(true)
			local roadmap = string.match(r, "\n### Roadmap\n(.-)\n### ") or ""
			t.expect(string.match(roadmap, "\n| [^\n]*| c0260 | %a+ |\n") ~= nil).toBe(true)
		end
	)
end)
