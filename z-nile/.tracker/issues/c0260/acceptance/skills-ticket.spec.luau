--!strict
-- c0260 AC1: z-ticket describes the interview, the review and the confirmation
-- Shape rules over z-ticket's text: the order of its steps and what each says (the exact wording is not pinned: the
-- skill can be reworded and stay green; a step that moves or goes does not).
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local ROOT = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local function skill(name: string): string
	return fs.readFile(`{ROOT}/z-nile/skills/{name}/SKILL.md`)
end
local function has(text: string, part: string): boolean
	return string.find(text, part, 1, true) ~= nil
end
-- The text of "## <title>" up to the next "## " heading.
local function section(text: string, title: string): string
	local from = string.find(text, `\n## {title}`, 1, true)
	if from == nil then
		error(`no section "{title}"`, 0)
	end
	local rest = string.sub(text, from + 1)
	local to = string.find(rest, "\n## ", 4, true)
	return if to then string.sub(rest, 1, to) else rest
end
-- The numbered steps of z-ticket's main list (before "## The capture folder"): number -> its text.
local function steps(text: string): { [number]: string }
	local out: { [number]: string } = {}
	local cur: number? = nil
	local main = string.sub(text, 1, string.find(text, "\n## The capture folder", 1, true) :: number)
	for line in string.gmatch(main, "[^\n]*") do
		local n = string.match(line, "^(%d+)%. ")
		if n then
			cur = tonumber(n)
			out[cur :: number] = line .. "\n"
		elseif cur then
			out[cur] ..= line .. "\n"
		end
	end
	return out
end

return t.spec("c0260 z-ticket describes the interview, the review and the confirmation", function(it)
	it(
		"AC1: z-ticket's steps run ask, interview, classify, create, clean idea, review, confirm, land in that order",
		function()
			local s = steps(skill("z-ticket"))
			local want: { { n: number, text: string } } = {
				{ n = 1, text = "verbatim" },
				{ n = 2, text = "Interview the user" },
				{ n = 3, text = "Classify the work" },
				{ n = 4, text = "./zn new issue" },
				{ n = 5, text = "clean idea" },
				{ n = 6, text = "./zn dispatch zz-review <id> --mode idea" },
				{ n = 7, text = "confirm" },
				{ n = 8, text = "./zn land" },
			}
			for _, w in want do
				t.expect(s[w.n] ~= nil and has(s[w.n], w.text)).toBe(true)
			end
			t.expect(has(skill("z-ticket"), "\n0. **Open a capture worktree first**")).toBe(true) -- step 0 stays first
		end
	)

	it("AC1: the interview keeps every question and answer, and the ask is never edited", function()
		local s = steps(skill("z-ticket"))
		t.expect(has(s[1], "never edited")).toBe(true)
		t.expect(has(s[2], "every")).toBe(true)
		t.expect(has(s[2], "exactly as asked")).toBe(true)
		t.expect(has(s[2], "own words")).toBe(true)
		t.expect(has(s[2], "AskUserQuestion")).toBe(true)
	end)

	it(
		"AC1: the review is a clean reviewer started with the two-hour timeout, answered line by line, up to three rounds",
		function()
			local s = steps(skill("z-ticket"))
			t.expect(has(s[6], "7200000")).toBe(true)
			t.expect(has(s[6], "idea-refute-NNN.md")).toBe(true)
			t.expect(has(s[6], "Do not review the idea yourself")).toBe(true)
			t.expect(has(s[6], 'model: "opus"')).toBe(true) -- the interactive form, where the dispatcher cannot run
			t.expect(has(s[6], "--note idea-review-NNN")).toBe(true) -- and its spend row
			t.expect(has(s[6], "At most three rounds")).toBe(true)
		end
	)

	it(
		"AC1: only the user's confirmation ends the capture, and a change they ask for goes back through the review",
		function()
			local s = steps(skill("z-ticket"))
			t.expect(has(s[7], "Only the user's confirmation ends the capture")).toBe(true)
			t.expect(has(s[7], "step 6")).toBe(true)
		end
	)

	it(
		"AC1: under the dispatcher a capture does not stop, and records an unattended interview and confirmation",
		function()
			local h = section(skill("z-ticket"), "A capture under the dispatcher")
			t.expect(has(h, "does not stop for the user")).toBe(true)
			t.expect(has(h, "None: unattended")).toBe(true)
			t.expect(has(h, "Confirmed (unattended")).toBe(true)
			t.expect(has(h, "- Fn: ask:")).toBe(true) -- a question it cannot ask is kept for z-design to put to the user
		end
	)

	it(
		"AC1: the verbatim ask is kept in a fence, a batch adds a Part, and a change asked at step 7 gets a round",
		function()
			local s = steps(skill("z-ticket"))
			t.expect(has(s[1], "fenced block")).toBe(true)
			t.expect(has(s[1], "## Part")).toBe(true)
			t.expect(has(s[6], "always gets one more round")).toBe(true)
			t.expect(has(s[7], "asked as Qn")).toBe(true)
		end
	)
end)
