--!strict
-- d0331: the skills say what the tools now do. A main that moved is no reason to restack; done merges onto it.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

return t.spec("d0331 the skills on a main that moved", function(it)
	it(
		"AC10: zz-execute Phase 5 no longer orders a restack because main moved, and says when one is needed",
		function()
			local text = fs.readFile(`{TOP}/z-nile/skills/zz-execute/SKILL.md`)
			t.expect(has(text, "If `main` moved, `./zn restack <R-id>`")).toBe(false)
			t.expect(has(text, "so the stack is on that main before `done`")).toBe(false)
			-- f0399's restack after the raft it was built on lands is still named (d0331 Design 1a)
			t.expect(
				has(
					text,
					"after a fix on a lower layer, or when `./zn trace` or `done` asks for it on a raft readied `--on` another raft once that raft has landed."
				)
			).toBe(true)
			t.expect(
				has(
					text,
					"2. A `main` that moved needs no restack: `./zn finish`, `./zn trace` and `done` judge layer 1 against the commit where it left `main`, and `done` merges the stack onto the newest `main` and runs the gate on that merged tree. If `main` moves again during that gate, `done` merges and gates again by itself, up to nine times. Run `./zn restack <R-id>` only when `done` reports a conflict or a red gate on the merged tree"
				)
			).toBe(true)
		end
	)

	it("AC10: zz-rules says layer 1 only has to sit on a commit of main", function()
		local text = fs.readFile(`{TOP}/z-nile/skills/zz-rules/SKILL.md`)
		t.expect(
			has(
				text,
				"`./zn restack <R-id>` rebases the layers above a change. Layer 1 only has to sit on a commit of `main`: `main` moving past it is no reason to restack, and `./zn done` merges the stack onto the newest `main` itself."
			)
		).toBe(true)
	end)

	it(
		"AC10: zz-execute's final review step and zz-review's final mode no longer ask for a restacked stack",
		function()
			local execute = fs.readFile(`{TOP}/z-nile/skills/zz-execute/SKILL.md`)
			t.expect(has(execute, "after the last layer is finished and restacked")).toBe(false)
			t.expect(
				has(
					execute,
					"after the last layer is finished, and the layers above any fixed layer are restacked, print the trace skeleton"
				)
			).toBe(true)
			local review = fs.readFile(`{TOP}/z-nile/skills/zz-review/SKILL.md`)
			t.expect(has(review, "on the finished, restacked stack")).toBe(false)
			t.expect(
				has(
					review,
					"Run once per raft on the finished stack, with the layers above any fixed layer restacked,"
				)
			).toBe(true)
		end
	)
end)
