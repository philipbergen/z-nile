--!strict
-- c0248 AC10 and AC11: the documents say it. Each sentence appears verbatim; the sentences it replaces are gone.
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
local RUN = "z-nile/skills/z-run/SKILL.md"
local PROMPT = "z-nile/templates/prompt.md"
local README = "z-nile/README.md"

return t.spec("c0248 the documents say it", function(it)
	it(
		"AC10: zz-execute says one worker builds the layers in order, each complete before the next, a second machine only through a takeover, and no longer says two machines work on different layers",
		function()
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
		end
	)

	it(
		"AC10: zz-execute Phase 4 reviews each layer in its issue folder with a Commit line before the next start",
		function()
			says(
				EXECUTE,
				"Phase 4 runs per layer, after the layer's `./zn finish` and before the next `./zn start`."
			)
			says(
				EXECUTE,
				"Its files are `review-NNN.md` and `refute-NNN.md` in the issue's folder (`<root>/issues/active/<id>/`), numbered from 001 per issue, and each begins with a `Commit: <sha>` line: the layer's finish commit the reviewer was given."
			)
			says(
				EXECUTE,
				"A layer is complete when its newest review is settled and current; `./zn start` and `./zn done` refuse a layer that is not."
			)
			says(
				EXECUTE,
				"The reviewer writes `review-NNN.md` in the issue's folder (starting at 001, with the `Commit: <sha>` line first)"
			)
			unsays(EXECUTE, "The reviewer writes `review-NNN.md` in the raft directory")
			-- Phase 5: a bind per landing, and the shorter bind below a block
			says(
				EXECUTE,
				"`./zn done R0010 --through <issue>` lands only the layers up to that issue's, after its own final review (`final-review-NNN.md`) and trace over exactly those layers."
			)
			says(EXECUTE, "the raft stays in `active/` until its last layer lands")
		end
	)

	it("AC10: zz-rules start and done rows say complete, --through, landed", function()
		says(RULES, "The next layer waits until the one below is complete: finished, green and reviewed.")
		unsays(RULES, "The next layer waits until `./zn finish` has made the one below a single commit.")
		says(
			RULES,
			"A layer is complete when it is finished, green and reviewed (its `review-NNN.md` in its issue's folder, current for its finish commit)."
		)
		says(
			RULES,
			"Refuses a layer that is not complete (finished, green and reviewed: its newest `review-NNN.md` in its issue's folder is settled and names the layer's finish commit), the top one included."
		)
		says(
			RULES,
			"`./zn done R0010 --through <issue>` lands only the layers not yet landed up to that issue's layer, after its own final review"
		)
		says(
			RULES,
			"it promotes and moves only those members to `done/`, keeps the raft in `active/` until its last layer lands, and retargets those layers' pull requests and the next layer's to `main`."
		)
		says(
			RULES,
			"A layer whose issue is in `done/` is landed: `./zn stack` shows it as `landed`, `start` never reopens it and `done` skips it."
		)
		says(
			RULES,
			"or a shorter bind, `./zn done <R-id> --through <issue>`, for the layers below a blocked one"
		)
	end)

	it(
		"AC10: z-run and the prompt template say one worker, each layer complete first, and --through",
		function()
			says(
				RUN,
				"One worker holds the raft and builds its layers one at a time, each complete (finished, green and reviewed in its own folder with a `Commit:` line) before the next `./zn start`."
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
			-- the bind wording of the goal state stays
			says(PROMPT, "lands the stack as one `--no-ff` merge, one commit per ticket.")
			says(
				"z-nile/templates/raft/doc.md",
				"This order is the stack's: layer 1 is the first issue, each next layer is on the one below."
			)
		end
	)

	it(
		"AC11: the README's Stacked delivery is exists and says one bind; the Roadmap row is exists; c0248 to c0254 are one raft and nothing says merging bottom-up",
		function()
			local delivery = section(README, "Stacked delivery")
			for _, part in
				{
					"One worker builds the layers one at a time, each complete (finished, green and reviewed) before the next starts.",
					"The stack lands as one `--no-ff` bind of its top layer, with one full gate on its top;",
					"the green layers below it land now as a shorter bind (`./zn done <R-id> --through <issue>`).",
					"A one-issue raft is a stack of one. *exists*",
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
			says(
				README,
				"c0248 to c0254 are one raft (R-vision), delivered as a stacked PR set in that order:"
			)
			unsays(README, "merging bottom-up")
			unsays(README, "bottom-up")
		end
	)
end)
