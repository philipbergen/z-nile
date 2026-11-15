--!strict
-- c0270 AC4: z-design's step 1 says to look for another prep of the issue before claiming it and at every resume,
-- names searches that find a slug-named branch and a renamed repository's PRs, says which hits are yours and which are
-- another prep, and what to do with one (headless included). Pins the rule's words in step 1, not the sentences: later
-- items may reword around them. Reads the real file; writes nothing.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local top = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

-- the text of `## 1. Claim the issue`, up to the next `## ` heading
local function stepOne(): string
	local text = fs.readFile(`{top}/z-nile/skills/z-design/SKILL.md`)
	local start = string.find(text, "\n## 1. Claim the issue\n", 1, true)
	assert(start, "z-design has no step 1 (## 1. Claim the issue)")
	local after = string.find(text, "\n## ", start + 1, true)
	return string.sub(text, start, if after then after - 1 else #text)
end

-- the bullet of step 1 that starts with `- <lead>`, with its indented sub-bullets: its first line and every line after
-- it that starts with two spaces
local function bullet(lead: string): string
	local s = stepOne()
	local i = string.find(s, "\n- " .. lead, 1, true)
	assert(i, `step 1 has no bullet "- {lead}"`)
	local out: { string } = {}
	local first = true
	for line in string.gmatch(string.sub(s, i + 1) .. "\n", "([^\n]*)\n") do
		if not first and string.sub(line, 1, 2) ~= "  " then
			break
		end
		first = false
		table.insert(out, line)
	end
	return table.concat(out, "\n")
end

-- the needles of `needles` that `text` lacks
local function lacks(text: string, needles: { string }): { string }
	local out: { string } = {}
	for _, needle in needles do
		if not string.find(text, needle, 1, true) then
			table.insert(out, needle)
		end
	end
	return out
end

local LEAD = "**One prep per issue**"

return t.spec("c0270 one prep per issue in z-design step 1", function(it)
	it("step 1 says to look for another prep before the claim and at every resume", function()
		t.expect(lacks(bullet(LEAD), {
			"before you claim an issue",
			"whenever you resume a prep",
			"never design the issue a second time",
		})).toEqual({})
	end)

	it(
		"the searches find a slug-named branch, PRs of every state in the renamed repository, worktrees and the claim",
		function()
			t.expect(lacks(bullet(LEAD), {
				"git fetch --prune origin",
				"git branch -r --list '*<id>*' '*<slug>*'",
				'gh pr list --repo "$(gh repo view --json nameWithOwner -q .nameWithOwner)" --state all --search <id>',
				"git worktree list | grep -e <id> -e <slug>",
				"./zn status <id>",
			})).toEqual({})
		end
	)

	it(
		"what is yours, what the claim proves before and at a resume, and what counts as another prep",
		function()
			t.expect(lacks(bullet(LEAD), {
				-- yours: the branch, its PR and the prototypes the document names
				"the branch this worktree is on and its PR",
				"every prototype branch or worktree your issue document names",
				"Name each prototype you make in Unknowns & experiments",
				-- the claim
				"before you claim, a `preparing` claim is another prep's",
				"At a resume the claim alone proves nothing",
				"the dispatcher starts z-design on a `preparing` issue only after its own chain's z-design step",
				"in a terminal it is yours when this prep claimed it",
				"Whose claim",
				-- another prep, and what is only read
				"any other branch with an open PR or none, or worktree, that holds a design of this issue",
				"whose title names it as `prep <id>`",
				"a PR that only mentions the id",
				"a branch or worktree with no design of the issue",
				"A merged one is history",
			})).toEqual({})
		end
	)

	it(
		"another prep is joined with its owner's say or the session stops, and a headless one reads rulings then asks",
		function()
			t.expect(lacks(bullet(LEAD), {
				"join another prep only with its owner's say (ask the user)",
				"stop and take another issue",
				"whose comments say where its work went",
				"`$ZN_DISPATCH_DIR/answered-*.md`",
				"follow a ruling that names exactly the hits you find now",
				"`$ZN_DISPATCH_DIR/questions.md`",
				"the user ends the other prep",
				"./zn dispatch stop <id>",
				"the user rules that a hit is not a prep of this issue",
			})).toEqual({})
		end
	)
end)
