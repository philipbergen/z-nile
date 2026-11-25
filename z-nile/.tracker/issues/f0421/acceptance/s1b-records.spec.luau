--!strict
-- f0421 slice 3, S1b, AC35 (design-review-002 F3, F8): what a row's model mark rests on, and where a review's writers are read.
-- A row folded from a dispatcher-measured buffer row keeps its model and is never marked. A typed row is judged only when it
-- claims the session's own model (a phase of the session's own work, not a review phase that records a subagent's or a
-- dispatched reviewer's model), and only against this session's own file, by family; a contradiction is marked, never
-- refused. The writers of a review are read from a named tree (the top layer tip for code and final reviews, the prep
-- branch tip for a design review, the rafting branch tip for a raft review), never from the folder the command runs in.
-- Sequestered: compile-red until S1b adds `reviewrec.rowMark` and `reviewrec.writersAt`.
local ledger = require("@znile/engine/ledger")
local reviewrec = require("@znile/engine/reviewrec")
local t = require("@tests/lib/t")

local function row(phase: string, model: string): ledger.Row
	return {
		when = "2026-11-24 10:00",
		subject = phase,
		added = 0,
		removed = 0,
		minutes = 0,
		how = "explicit",
		phase = phase,
		tokens = 10,
		model = model,
	}
end

return t.spec("f0421 S1b AC35: row marks and the writers' tree", function(it)
	it(
		"F3: the rows the protocol tells a lead to write are recorded, and marked only by what the engine knows",
		function()
			-- zz-execute Phase 4 step 3: a Fable lead records its Opus reviewer's row: a typed review row, not the session's own
			t.expect(reviewrec.rowMark({
				model = "claude-opus-5-5-xhigh",
				phase = "code-review",
				cli = "claude",
				fileModel = "claude-fable-5-2",
			})).toBe(nil)
			-- an agent lead commits a dispatched review's row, measured by the adapter: never marked, never compared
			t.expect(reviewrec.rowMark({
				model = "claude-opus-5-5-high",
				phase = "code-review",
				cli = "agent",
				measured = true,
				declared = "gemini-4-neon-high",
			})).toBe(nil)
			-- a grok row of the session's own work, where only another CLI's session file was read in the span: judged against grok's
			-- own file, or not at all
			t.expect(
				reviewrec.rowMark({ model = "grok-4.7-high", phase = "build", cli = "grok", fileModel = nil })
			)
				.toBe(nil)
			t.expect(reviewrec.rowMark({
				model = "grok-4.7-high",
				phase = "build",
				cli = "grok",
				fileModel = "grok-4.7",
			})).toBe(nil)
			-- a claude lead's own row that contradicts this session's file is marked, not refused
			t.expect(reviewrec.rowMark({
				model = "claude-sonnet-5-5-medium",
				phase = "build",
				cli = "claude",
				fileModel = "claude-fable-5-2",
			})).toBe("(contradicts this session's file: claude-fable-5-2)")
			-- a CLI whose file the engine does not read: the declared marks of S1a stand
			t.expect(reviewrec.rowMark({
				model = "gemini-4-neon-high",
				phase = "build",
				cli = "agy",
				declared = "gemini-4-neon-high",
			})).toBe("(declared)")
			t.expect(reviewrec.rowMark({
				model = "gemini-4-neon-high",
				phase = "build",
				cli = "agy",
				declared = "gemini-4-argon-high",
			})).toBe("(declared; the session declared ZN_MODEL=gemini-4-argon-high)")
		end
	)

	it(
		"F8: the writers of each kind of review are read from its named tree, so the folder it is asked from does not matter",
		function()
			local spend = ledger.append(nil, "c0100", "c0100", row("build", "claude-sonnet-5-5-medium"))
			local prep = ledger.append(nil, "c0100", "c0100", row("prep", "claude-opus-5-5-high"))
			local trees: { [string]: { [string]: string } } = {
				["R0100/1/c0100"] = { ["pickman/.tracker/issues/active/c0100/spend.md"] = spend },
				["prep-hundred"] = { ["pickman/.tracker/issues/c0100/spend.md"] = prep },
				["raft-hundred"] = { ["pickman/.tracker/issues/c0100/spend.md"] = prep },
			}
			local function read(ref: string, path: string): string?
				local tree = trees[ref]
				return if tree then tree[path] else nil
			end
			local cases = {
				{
					"code-review",
					"R0100/1/c0100",
					"pickman/.tracker/issues/active/c0100",
					"claude-sonnet-5-5-medium",
				},
				{
					"final-review",
					"R0100/1/c0100",
					"pickman/.tracker/issues/active/c0100",
					"claude-sonnet-5-5-medium",
				},
				{ "design-review", "prep-hundred", "pickman/.tracker/issues/c0100", "claude-opus-5-5-high" },
				{ "raft-review", "raft-hundred", "pickman/.tracker/issues/c0100", "claude-opus-5-5-high" },
			}
			for _, c in cases do
				local writers, why = reviewrec.writersAt({ dirs = { c[3] }, ref = c[2], read = read }, c[1])
				t.expect(`{c[1]}: {table.concat(writers, ",")} {tostring(why)}`).toBe(`{c[1]}: {c[4]} nil`)
			end
			-- no tree readable: no writers, and the one wording that says so
			local none, why =
				reviewrec.writersAt({ dirs = { "x" }, ref = "gone", read = read }, "code-review")
			t.expect(#none).toBe(0)
			t.expect(string.find(why or "", "could not be read", 1, true) ~= nil).toBe(true)
		end
	)
end)
