--!strict
-- c0248 AC13 and AC14: the documents say it. Each sentence appears verbatim; the sentences it replaces are gone.
-- Reads the checkout's files only (read-only).
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function read(rel: string): string
	return fs.readFile(`{root}/{rel}`)
end
local function says(rel: string, line: string)
	if string.find(read(rel), line, 1, true) == nil then
		error(`{rel} does not say: {line}`)
	end
end
local function unsays(rel: string, line: string)
	if string.find(read(rel), line, 1, true) ~= nil then
		error(`{rel} still says: {line}`)
	end
end

-- The text of a `### <heading>` section of the README, to the next heading.
local function section(rel: string, heading: string): string
	local text = "\n" .. read(rel)
	local at = string.find(text, `\n### {heading}\n`, 1, true)
	if not at then
		error(`{rel} has no section {heading}`)
	end
	local body = string.sub(text, at + #heading + 6)
	local stop = string.find(body, "\n#", 1, true)
	return if stop then string.sub(body, 1, stop) else body
end

local EXECUTE = "z-nile/skills/zz-execute/SKILL.md"
local RULES = "z-nile/skills/zz-rules/SKILL.md"
local REVIEW = "z-nile/skills/zz-review/SKILL.md"
local RUN = "z-nile/skills/z-run/SKILL.md"
local PROMPT = "z-nile/templates/prompt.md"
local RAFT = "z-nile/templates/raft/doc.md"
local README = "z-nile/README.md"

return t.spec("c0248 the documents say it", function(it)
	it(
		"AC13: zz-execute, zz-rules, zz-review, z-run, the prompt template and the raft template say it",
		function()
			-- zz-execute: one worker, in order, a takeover for a second machine; streams are subagents
			says(
				EXECUTE,
				"One worker holds the raft and builds its layers one at a time, each complete before the next starts; a second machine works on the raft only through a takeover (c0274)."
			)
			says(
				EXECUTE,
				"A layer may still be built by streams: subagents of the worker committing on the layer it is on."
			)
			unsays(EXECUTE, "Two machines work on different layers of the same raft")
			says(
				EXECUTE,
				"`./zn start` opens the next layer only when this one is complete: finished, green and reviewed."
			)
			-- zz-execute Phase 4: per layer, in the issue's folder, stamped by the tool, open list and harvest in the issue
			says(
				EXECUTE,
				"Phase 4 runs per layer, after the layer's `./zn finish` and before the next `./zn start`."
			)
			says(
				EXECUTE,
				"Its files are `review-NNN.md` and `refute-NNN.md` in the issue's folder (`<root>/issues/active/<id>/`), numbered from 001 per issue. The tool stamps them: `./zn commit` (or the dispatcher, for a dispatched review) writes `Commit: <sha>` and `Patch: <id>` on their first lines from the layer's finish commit, and a reviewer never writes them."
			)
			says(
				EXECUTE,
				"A layer's open list (`## Open to the human`) is the issue document's, and its harvest is the issue folder's `harvest.md`."
			)
			says(
				EXECUTE,
				"A review with `Verdict: approve` and no findings goes to the next layer with nothing more to answer."
			)
			says(
				EXECUTE,
				"The reviewer writes `review-NNN.md` in the issue's folder (starting at 001; the tool stamps it)"
			)
			unsays(EXECUTE, "The reviewer writes `review-NNN.md` in the raft directory")
			-- zz-execute Phase 5: a final review and a bind per landing, and the shorter bind below a block
			says(
				EXECUTE,
				"Run the final review and `./zn done` once per landing. When a layer is blocked, the green layers below it land now: `./zn done R0010 --through <issue>` lands only the layers up to that issue's, after its own final review (`final-review-NNN.md`) and trace (`trace-NNN.md`) over exactly those layers."
			)
			says(EXECUTE, "the raft stays in `active/` until its last layer lands")
			-- zz-rules: the start, done, commit and stack rows, the open list
			says(RULES, "The next layer waits until the one below is complete: finished, green and reviewed.")
			unsays(RULES, "The next layer waits until `./zn finish` has made the one below a single commit.")
			says(
				RULES,
				"A layer is complete when it is finished, green and reviewed: its newest `review-NNN.md` in its issue's folder is settled and current for the layer's finish commit or its patch."
			)
			says(
				RULES,
				"Refuses a layer that is not complete, the top one included (finished, green and reviewed: its newest `review-NNN.md` in its issue's folder is settled and names the layer's finish commit or patch)."
			)
			says(
				RULES,
				"`./zn done R0010 --through <issue>` lands only the layers not yet landed up to that issue's layer, with its own `final-review-NNN.md` and `trace-NNN.md`"
			)
			says(
				RULES,
				"it promotes and moves only those members to `done/`, keeps the raft in `active/` until its last layer lands, and retargets those layers' pull requests and the next layer's to `main`."
			)
			says(
				RULES,
				"It runs the raft's `check.sh` with `ZN_BIND_MEMBERS` set to the landing's ids, and `ZN_BIND_EARLY=1` while layers stay unlanded: `./zn members` and `promote-check` then cover those members, and `RC1` and up are skipped until the last landing."
			)
			says(
				RULES,
				"A layer whose issue is in `done/` on `origin/main` is landed: `./zn stack` shows it as `landed`, `start` never reopens it, `done` skips it, and `restack` puts the lowest unlanded layer on `main`."
			)
			says(
				RULES,
				"a new `review-NNN.md` or `refute-NNN.md` is stamped with `Commit:` and `Patch:` from the layer's finish commit, and refused on a layer that is not finished."
			)
			says(
				RULES,
				"Each layer's pull request body names the raft's Theme and Order and the stack; `start`, `finish`, `restack` and `done` rewrite it, and a failed edit only warns."
			)
			says(
				RULES,
				"stays open until the issue document's `## Open to the human` (the raft document's, for the final review)"
			)
			-- zz-review: where each mode writes, and who stamps
			says(
				REVIEW,
				"- Code mode: `review-NNN.md`, in the issue's folder (the layer's issue; a raft readied before layers were reviewed one by one keeps it in the raft directory). The tool stamps `Commit:` and `Patch:` on it; the reviewer writes neither."
			)
			says(
				REVIEW,
				"- Final mode: `final-review-NNN.md`, in the raft directory, alongside `trace-NNN.md`, once per landing (NNN is one more than the highest final review on `origin/main`)."
			)
			unsays(REVIEW, "- Code mode: `review-NNN.md`, in the raft directory.\n")
			-- z-run, the prompt template and the raft template
			says(
				RUN,
				"One worker holds the raft and builds its layers one at a time, each complete (finished, green and reviewed in its own issue folder, the review stamped by the tool) before the next `./zn start`."
			)
			says(RUN, "`./zn done <R> --through <issue>` lands the green layers below it.")
			says(
				PROMPT,
				"If it says `parallel: yes`, that work runs as subagents committing on the layer you are on; the next layer starts only when this one is complete (finished, green and reviewed)."
			)
			unsays(PROMPT, "that work is another layer of this raft")
			says(
				PROMPT,
				"If a layer blocks, the layers below it land with `./zn done {{RAFT_ID}} --through <issue>`."
			)
			says(PROMPT, "lands the stack as one `--no-ff` merge, one commit per ticket.")
			says(
				RAFT,
				"This order is the stack's: layer 1 is the first issue, each next layer is on the one below."
			)
		end
	)

	it("AC14: the README's Stacked delivery, Roadmap row and one-raft sentence", function()
		local delivery = section(README, "Stacked delivery")
		for _, part in
			{
				"One worker builds the layers one at a time, each complete (finished, green and reviewed) before the next starts.",
				"The stack lands as one `--no-ff` bind of its top layer, with one full gate on its top;",
				"the green layers below it land now as a shorter bind (`./zn done <R-id> --through <issue>`).",
				"A one-issue raft is a stack of one. *exists* (c0248)",
			}
		do
			if string.find(delivery, part, 1, true) == nil then
				error(`README's Stacked delivery does not say: {part}`)
			end
		end
		for _, gone in
			{
				"*captured*",
				"today a raft is one branch and one PR",
				"merge bottom-up",
				"retargeted to `main` as the one below merges",
			}
		do
			if string.find(delivery, gone, 1, true) ~= nil then
				error(`README's Stacked delivery still says: {gone}`)
			end
		end
		says(README, "| a raft delivered as a stacked PR set, one layer per issue | c0248 | exists |")
		unsays(README, "| a raft delivered as a stacked PR set, one layer per issue | c0248 | captured |")
		says(README, "c0248 to c0254 are one raft (R-vision), delivered as a stacked PR set in that order:")
		unsays(README, "bottom-up")
	end)
end)
