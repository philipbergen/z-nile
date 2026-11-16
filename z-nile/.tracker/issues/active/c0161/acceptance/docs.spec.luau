--!strict
-- c0161 AC4: the skills say what c0161's Design says. A closure (a defect that does not reproduce, any issue closed with
-- no code change) is designed and reviewed like any issue, and `./zn status <id> prepared` refuses an issue with no
-- approving design review round. z-design (the rule, step 5.5), the defect checklist, zz-review's design mode, zz-rules
-- and z-raft say it the same way, and nothing still restates the move's old conditions. Reads the real tree, plain
-- finds only.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local SKILLS = "z-nile/skills"
-- runs from z-nile/ (the project's home): every path this spec reads is the repository's, from its top
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local function read(path: string): string
	return fs.readFile(`{TOP}/{path}`)
end
local function at(text: string, needle: string, where: string)
	if string.find(text, needle, 1, true) == nil then
		error(`{where} is missing: {needle}`, 2)
	end
end
local function absent(text: string, needle: string, where: string)
	if string.find(text, needle, 1, true) ~= nil then
		error(`{where} still says: {needle}`, 2)
	end
end

-- the one description of the refusal, as every skill words it
local ROUND =
	"its newest `design-review-NNN.md` says `Verdict: approve` and quotes the design as it is (`Design record: <hash>`, from `./zn design-record <id>`)"

return t.spec("c0161 the skills: a closure is reviewed, and prepared needs an approving round", function(it)
	it(
		"z-design: a closure is designed and reviewed like any issue, and step 5.5 states what prepared refuses",
		function()
			local s = read(`{SKILLS}/z-design/SKILL.md`)
			local w = "z-design"
			at(s, "**A closure is designed and reviewed like any issue.**", w)
			at(s, 'No step and no review round is waived because the Design says "No code change".', w)
			at(s, "the author's record, apart from the user's own words", w)
			at(
				s,
				"`./zn status <id> prepared` refuses an issue whose folder has no approving design review",
				w
			)
			-- step 5.5: the carried move's conditions
			at(
				s,
				"refuses unless the issue is `design: ready`, "
					.. ROUND
					.. ", and it is `preparing` on `origin/main`",
				w
			)
			absent(s, "refuses unless the issue is `design: ready` and `preparing` on `origin/main`", w)
			-- the earlier rules stay as they were
			at(s, "Answering a finding by an edit needs a new round", w)
			at(s, "A Design changed after a round needs a new round too", w)
			at(s, "a round that says `changes` is followed by another round whatever this rule says", w)
			at(
				s,
				"Tell the reviewer to run `./zn design-record <id>` in the prep worktree that holds the design",
				w
			)
			at(s, "Everything under `experiments/` is part of the design record", w)
			at(s, "the user decides another round past the cap", w)
			at(s, "the engine prepares nothing on a `changes` round", w)
			at(s, "or has a finding you answer by an edit, goes to the user", w)
			at(
				s,
				"An approving final round's findings answered by a refute keep it final; answered by an edit, they need the next round.",
				w
			)
			at(
				s,
				"z-design designs one issue to `design: ready` and status `prepared`, and does not create a raft",
				w
			)
			at(s, "Run the reviewer on **Opus 5.5**", w)
			-- the recovery for a prepared issue edited later (design review 006 F2)
			at(s, "its design round is run in the worktree that holds the edit and landed with it", w)
			at(s, "(it takes two landings, z-raft 2)", w)
		end
	)

	it("the defect checklist has a Closure item that sends a closure through the same review", function()
		local s = read(`{SKILLS}/z-design/checklists/defect.md`)
		local w = "the defect checklist"
		at(s, "- **Closure**", w)
		at(s, "the user's own words kept apart from the author's reading", w)
		at(s, "what changed between the reports", w)
		at(s, "designed and reviewed like any issue", w)
		at(s, "- **Reproduction**", w)
	end)

	it("zz-review's design mode judges a closure's record", function()
		local s = read(`{SKILLS}/zz-review/SKILL.md`)
		local w = "zz-review"
		at(s, "12. **Closure**", w)
		at(s, "\nDesign record: <hash>\n```", w)
		at(s, "Never edit a round after it is written", w)
		at(s, "code mode and raft mode have none", w)
		at(s, "Everything under `experiments/` is part of the design record", w)
		at(s, "a round with a second of either is refused", w)
		at(s, "run `./zn design-record <id>` before you read", w)
		at(s, "Judge a closure as you would a fix", w)
		at(s, "11. **Scope fidelity**", w)
	end)

	it(
		"zz-rules and z-raft state the refusal, for the issue itself and for a raft's preparing members",
		function()
			local rules = read(`{SKILLS}/zz-rules/SKILL.md`)
			local w = "zz-rules"
			at(
				rules,
				"The move to `prepared` is **carried by the prep PR**: it only edits the local documents.",
				w
			)
			at(
				rules,
				"It refuses an issue whose folder has no approving design review that read the design as it is ("
					.. ROUND
					.. ")",
				w
			)
			at(rules, "every `preparing` issue a raft's carried move takes", w)
			at(rules, "a prepared issue is taken as it is", w)
			at(rules, "a raft's own folder is no stand-in for a member's", w)
			absent(rules, "writes nothing), `design-record <id>`", w)
			at(rules, "`start`, `design-record`, `status <id> <to>`", w)
			at(rules, "so a design edited after the move to prepared is caught at the next read", w)
			at(rules, "It refuses in the main checkout (a preparing design lives in its prep worktree)", w)
			at(rules, "| design-record | `./zn design-record <issue-id>` | read-only.", w)
			absent(rules, "or `Verdict: changes` with every finding answered", w)
			absent(rules, "judged by its own folder, or else by the raft's", w)
			local raft = read(`{SKILLS}/z-raft/SKILL.md`)
			at(raft, "takes each member that is prepared on `origin/main` as it is", "z-raft")
			at(
				raft,
				"refuse a prepared issue whose design was edited after its newest design round quoted its record",
				"z-raft"
			)
			at(raft, "a `preparing` member with no approving design review of its own", "z-raft")
			-- the recovery and the skip (design review 006 F2, F5)
			at(raft, "`ready` reads it too, and `raft-plan` skips it and names it", "z-raft")
			at(raft, "**A stale prepared issue is made current by a design round for it**", "z-raft")
			at(raft, "**A rafted member takes two landings**", "z-raft")
			at(
				raft,
				"`./zn unfold <R-id> <id>`, make the member's edit and add its approving design round",
				"z-raft"
			)
			at(
				raft,
				"in a second rafting worktree `./zn fold <R-id> <id>` (which records the landed design)",
				"z-raft"
			)
			at(raft, "The cost is one extra PR per in-raft member fix.", "z-raft")
			at(raft, "it needs a design round for it first (\u{a7}2)", "z-raft")
			at(
				rules,
				"A stale prepared issue is made current by an approving design round that quotes its record, run in the worktree that holds the edit and landed with it",
				"zz-rules"
			)
			at(rules, "`raft-plan` skips a stale issue and names it", "zz-rules")
			at(
				rules,
				"a rafted member takes two landings (`unfold` with its edit and round, land;",
				"zz-rules"
			)
			at(rules, "one extra PR per in-raft member fix; z-raft 2)", "zz-rules")
			local ready = read(`{SKILLS}/z-ready/SKILL.md`)
			at(ready, "Every member whose design rounds quote a `Design record:` still matches it", "z-ready")
			at(
				ready,
				"needs a design round for it, run in the worktree that holds the edit and landed first",
				"z-ready"
			)
		end
	)
end)
