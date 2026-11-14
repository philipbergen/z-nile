--!strict
-- c0250 AC12: the documents say block and resolve. The skills' sentences and the README's lines are pinned as the
-- change writes them; the old sentences (a step writes questions.md, a blocked status is c0250, the quota row) are
-- pinned gone. Read as text, whole sentences, so a reworded sentence fails here and names the file.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function read(path: string): string
	return fs.readFile(`{TOP}/{path}`)
end

local function has(text: string, part: string): boolean
	return string.find(text, part, 1, true) ~= nil
end

-- the text says it
local function says(path: string, sentence: string)
	if not has(read(path), sentence) then
		error(`{path} no longer says: {sentence}`, 2)
	end
end

-- the text no longer says it
local function unsays(path: string, sentence: string)
	if has(read(path), sentence) then
		error(`{path} still says: {sentence}`, 2)
	end
end

local RULES = "z-nile/skills/zz-rules/SKILL.md"
local README = "z-nile/README.md"

-- the sentence the Headless paragraph of z-design, z-raft and z-run carries, in parts
local HEADLESS = {
	"or any decision that needs the user: write `escalation.md` in the item's folder (`## Question`, `## What was tried`, `## Open findings or error` and `## Options`, each option a bullet that starts with one of `amend-design`, `approve`, `split`, `retry` or `abort`, and exactly one ending `(recommended)`)",
	"and run `./zn block <id> <reason>` in your worktree, then stop.",
	"The dispatcher stops the chain at the blocked item until the user runs `./zn resolve <id> <decision>`, then `./zn dispatch retry <id>` re-runs the step with the note and its resolution.",
	"A nested step (a review) never blocks the item: its author does.",
	"Under `./zn dispatch`, do not run `./zn done`: the dispatcher lands the layers below (c0252).",
	"A refutation or an unclosed high is `review-exhausted`: write it under `## Open to the human` in the item's document, copy the bullets verbatim under `## Open findings or error` in `escalation.md`, run `./zn block <id> review-exhausted` and stop without ruling on it; after the user's `./zn resolve` (one `--rule <Fn>=\"<ruling>\"` per open id) run `./zn rulings <id>` in your worktree, which writes the rulings under the bullets.",
}
local OLD_HEADLESS =
	"write the questions to `$ZN_DISPATCH_DIR/questions.md`, one `## Q<n>` heading per question with the options and what each costs, and stop. The dispatcher stops the chain there until the user answers and runs `./zn dispatch retry <id>`."

return t.spec("c0250 the documents say block and resolve", function(it)
	it(
		"AC12: zz-rules, the Headless paragraphs, z-work, z-stop and zz-review say block and resolve",
		function()
			-- zz-rules: the status, the two commands, the dispatcher
			says(
				RULES,
				"and `blocked` (c0250) beside them: `preparing -> blocked` and `active -> blocked` are taken by `./zn block` only, and `blocked -> new` and `blocked -> prepared` by `./zn resolve` only (`./zn status <id> blocked` and `./zn status <id> <to>` from a blocked item are refused)."
			)
			says(
				RULES,
				"A blocked item carries `blocked: <reason>` (one of `review-exhausted`, `design-gap`, `needs-decision`, `red-gate`, `quota`, `tripwire`) and holds no claim; its `rank:` is never changed."
			)
			says(
				RULES,
				"`quota_cap_hours` (`.models.toml`, `[dispatch]`, whole hours, at least 1), which c0253's worker waits for."
			)
			says(
				RULES,
				"| block | `./zn block <id> <reason> [--layer <issue>]` | in the item's worktree (never the main checkout), after the worker wrote `escalation.md` in the item's folder there"
			)
			says(RULES, "One tracker commit on `origin/main`, `tracker: <id> blocked <reason>`:")
			says(
				RULES,
				"a readied raft and its members still in `active/` move to the backlog blocked as `stop` moves them (a member in `done/` stays)"
			)
			says(
				RULES,
				"comments `BLOCKED: <reason>: <the question>` on the Layer's PR (`--layer`, else the lowest member still in `active/` on `origin/main`, never the current branch; skipped with a warning when it has no PR) and removes the worktree's copy of the note."
			)
			says(
				RULES,
				"It refuses an issue that is a member of an active raft (block the raft: `./zn block <R> <reason> --layer <issue>`), the reason `tripwire` in an agent session (after a tripwire the worker writes `escalation.md`, runs neither `done --through` nor `block`, and tells the person, who checks the checkout and files it), and a note that already holds a `## Resolution`; on an item already blocked whose note is missing or unreadable it only re-files the note."
			)
			says(
				RULES,
				"| resolve | `./zn resolve <id> <decision> [--answer <text> \\| --answer-file <path>] [--said <text>] [--title <text>] [--rule <Fn>=<ruling>]` | the human's, in any checkout; refused while `ZN_DISPATCH` or `ZN_HEADLESS` is set, and by the session the note's `Session:` names. An agent runs it only when the user's message in this conversation tells it to."
			)
			says(
				RULES,
				"In an agent session `--said \"<the user's message>\"` is required and recorded quoted as the user's word."
			)
			says(
				RULES,
				"One tracker commit, `tracker: <id> resolve <decision>`: appends `## Resolution` to `escalation.md`, removes `blocked:`"
			)
			says(RULES, "appends the `unblocked` row to `provenance.md`, and keeps `rank:`.")
			says(
				RULES,
				'`approve` writes `Decided with the user (<date>), resolve approve: "<answer>"` in the Problem (in an agent session the user\'s `--said` words and `(the option: <answer>)`;'
			)
			says(
				RULES,
				"whose `grouped:` entry and coherence reviews' `Grouped:` lines `resolve` re-records, so an approve on a raft vouches for the change without a new raft-mode round,"
			)
			says(
				RULES,
				"a `review-exhausted` resolve needs one `--rule <Fn>=\"<ruling>\"` per id of the note's `Open:` line, records them in `## Resolution`, and `./zn rulings <id>` writes them as `Ruled (user, <date>)` lines in the step's worktree;"
			)
			says(
				RULES,
				"on a draft raft `approve` and `amend-design` act as `retry` and `split` is refused; a raft left with no unlanded member goes to `done/` (a member landed) or `retired/`;"
			)
			says(
				RULES,
				"`abort` leaves a raft `prepared` as `stop` does and prints the parked branches and PRs to close |"
			)
			says(
				RULES,
				"- **A step on an item blocks it** (c0250). When a decision needs the user, a step on an existing item writes `escalation.md` in the item's folder and runs `./zn block <id> <reason>`, then stops; it does not write `questions.md`."
			)
			says(
				RULES,
				"`dispatch.next` stops first, with exit 3, on an item that is `blocked` on `origin/main`: `<id> is blocked (<reason>): ./zn resolve <id> <decision>`."
			)
			says(
				RULES,
				"`./zn dispatch retry <id>` is refused while the item is blocked (`<id> is blocked: ./zn resolve <id> <decision> first`)"
			)
			says(
				RULES,
				"`--answer` and `--answer-file` are refused for an item (the answer is the resolution's); they stay for a capture."
			)
			says(RULES, "A nested step (a review) that needs the user tells its author to block the item.")
			says(
				RULES,
				"- **Questions and answers for a capture** (c0256). A capture has no item yet, so z-ticket keeps the local `questions.md`"
			)
			says(
				RULES,
				"a `block` or `resolve` commit keeps every line of the origin text in order and may only change the `status:`, `blocked:`, `design:`, `raft:`, `issues:` and `grouped:` lines of the item, its raft's members and the Layer member, add Decided or Scope decision lines inside `## Problem`, and change the `Grouped:` lines of a coherence review"
			)
			says(
				RULES,
				"A `questions.md` a step leaves for an item fails the chain (exit 1, naming `escalation.md` and `./zn block`) and is set aside as `questions-ignored-N.md`. Under `./zn dispatch` a step never runs `./zn done`: it blocks, and the dispatcher lands the layers below (c0252). An unruled `## Open to the human` is a block with reason `review-exhausted`."
			)
			unsays(
				RULES,
				"- **Questions and answers** (c0256). A step that needs the user writes `questions.md` in its state folder and stops."
			)
			-- the Headless paragraphs
			for _, skill in { "z-design", "z-raft", "z-run" } do
				local path = `z-nile/skills/{skill}/SKILL.md`
				for _, part in HEADLESS do
					says(path, part)
				end
				unsays(path, OLD_HEADLESS)
				unsays(path, "write the questions to `$ZN_DISPATCH_DIR/questions.md`")
			end
			says(
				"z-nile/skills/z-design/SKILL.md",
				"(under the dispatcher: write `escalation.md` in the issue's folder and run `./zn block <id> needs-decision`, then stop)"
			)
			unsays(
				"z-nile/skills/z-design/SKILL.md",
				"write the question to `$ZN_DISPATCH_DIR/questions.md` and stop"
			)
			-- a capture has no item to block: z-ticket keeps c0256's local questions.md
			says("z-nile/skills/z-ticket/SKILL.md", OLD_HEADLESS)
			-- zz-execute's escalation
			says(
				"z-nile/skills/zz-execute/SKILL.md",
				"5. Block the raft: land the green layers below the blocked one with `./zn done <R-id> --through <issue>`, write `escalation.md` in the raft's folder in your worktree"
			)
			says(
				"z-nile/skills/zz-execute/SKILL.md",
				"and run `./zn block <R-id> <review-exhausted|design-gap|needs-decision|red-gate|quota|tripwire> [--layer <issue>]`."
			)
			-- under the dispatcher a step never lands layers, a tripwire is the person's, and an agent resolves only on the user's word
			local EXECUTE = "z-nile/skills/zz-execute/SKILL.md"
			says(
				EXECUTE,
				"Under `./zn dispatch` the same two steps are all there is, except that you do not run `./zn done`: write `escalation.md` and run `./zn block <R-id> <reason>`, and the dispatcher lands the layers below (c0252) and stops the chain at the blocked raft until the user runs `./zn resolve <R-id> <decision>`."
			)
			says(
				EXECUTE,
				"After a tripwire (a `REPOSITORY CHANGED` stop, a refused fixture identity) run neither `./zn done --through` nor `./zn block`: write `escalation.md`, tell the person, who checks the checkout and runs `./zn block <R-id> tripwire`."
			)
			says(
				EXECUTE,
				"You run `./zn resolve` only when the user's message in this conversation tells you to, quote that message in `--said`, and never resolve a block your own session filed."
			)
			says(
				EXECUTE,
				"An unruled `## Open to the human` is `review-exhausted`: copy the bullets verbatim under `## Open findings or error`, block, and after the resolve run `./zn rulings <id>` in your worktree."
			)
			says(
				"z-nile/skills/z-design/SKILL.md",
				"Under `./zn dispatch` the list is a block: write `escalation.md` with the bullets verbatim under `## Open findings or error`, run `./zn block <id> review-exhausted`, and after the user's `./zn resolve` run `./zn rulings <id>`, which writes the rulings under the bullets; you never write one."
			)
			-- z-work: step 5 and step 10
			local work = "z-nile/skills/z-work/SKILL.md"
			says(
				work,
				"5. Blocked means a human decision, or the same check failed after a real second attempt. If layers below the blocked one are green, land them first with `./zn done <R> --through <issue>`. Write `escalation.md` in the raft folder, then run `./zn block <R> <reason>` in the raft's worktree. Tell the person, then run `./zn work next` again."
			)
			-- c0248's pinned sentence stays after c0250's step 5 (F21)
			says(
				work,
				"A blocked layer stops the layers above it, and `./zn done <R> --through <issue>` lands the green layers below it."
			)
			says(
				work,
				"After a tripwire (a `REPOSITORY CHANGED` stop, a refused fixture identity) run neither `./zn done --through` nor `./zn block`: write `escalation.md`, tell the person, who checks the checkout and runs `./zn block <R> tripwire`."
			)
			says(
				work,
				"You run `./zn resolve` only when the user's message in this conversation tells you to, quote that message in `--said`, and never resolve a block your own session filed."
			)
			says(work, "A release, and a block, adds one to the count you pass as `--released`.")
			unsays(work, "Write `questions.md` in the raft folder")
			unsays(work, "run `./zn stop <R>`. Tell the person")
			unsays(work, "A blocked status is c0250")
			unsays(work, "`questions.md` is the only block signal")
			-- z-stop: a blocked raft is aborted through resolve
			says(
				"z-nile/skills/z-stop/SKILL.md",
				"5. **A blocked raft** is not stopped: it is already out of `active/`, with its claim given up by `./zn block`. To abort it, the human runs `./zn resolve <R-id> abort`"
			)
			says("z-nile/skills/z-stop/SKILL.md", "`stop` refuses a blocked raft.")
			-- zz-review: a nested reviewer never blocks
			says(
				"z-nile/skills/zz-review/SKILL.md",
				"A reviewer never blocks the item itself, and a reviewer that needs the user says so in its review: the author runs `./zn block <id> <reason>` (zz-execute, To escalate)."
			)
			-- .models.toml carries the cap's comment
			says(
				".models.toml",
				"# quota_cap_hours = <whole hours, at least 1>: c0253's worker blocks the raft with `quota` (./zn block) when every CLI"
			)
			says(".models.toml", "# stays out of quota past this many hours.")
		end
	)

	it(
		"AC12: the README's escalation section, quota row, next-raft line, dispatcher bullet and Roadmap row",
		function()
			local text = read(README)
			says(README, "A worker never guesses past a wall; it escalates formally. *exists* (c0250)")
			unsays(README, "it escalates formally. *captured* (c0250)")
			says(
				README,
				"| `quota` | every CLI stayed out of quota past `quota_cap_hours` (`.models.toml`) |"
			)
			unsays(README, "| `quota` | every CLI failed on quota |")
			says(README, "and takes the next raft that does not depend on the blocked one.")
			unsays(README, "takes the next unblocked item that does not depend on the blocked one")
			says(README, "It stops at a merge gate, at a blocked item and at a failure")
			unsays(README, "at a step's `questions.md`")
			says(
				README,
				"and replaces c0117's local `questions.md` for an item (a capture, which has no item yet, keeps it)."
			)
			says(README, "| `blocked`, `escalation.md`, `./zn resolve` | c0250 | exists |")
			unsays(README, "| `blocked`, `escalation.md`, `./zn resolve` | c0250 | captured |")
			-- no other row of the roadmap changed state with it
			t.expect(has(text, "| a raft delivered as a stacked PR set, one layer per issue | c0248 |"))
				.toBe(true)
			-- the six reasons are still the table's
			for _, reason in
				{ "review-exhausted", "design-gap", "needs-decision", "red-gate", "quota", "tripwire" }
			do
				t.expect(has(text, `| \`{reason}\` |`)).toBe(true)
			end
		end
	)
end)
