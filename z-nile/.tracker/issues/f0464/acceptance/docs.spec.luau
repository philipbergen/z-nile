--!strict
-- f0464 AC6: the skills say the new way: z-design's next step is `./zn ready <issue-id>`; z-ready readies a prepared
-- issue in no raft alone (light only when light.luau accepts it, --on outside the dispatcher); z-raft has no default
-- raft and makes a raft of several only from named members, which still need the rafting pull request and the
-- coherence review; z-work's `ready <issue>` is for a ticket at any level; zz-rules' `raft-plan` row and the dispatcher's
-- chain say no rafting step. No skill still sends a raftless prepared issue to `./zn raft-plan` or z-raft by default.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function read(rel: string): string
	return fs.readFile(`{TOP}/{rel}`)
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

local function skill(name: string): string
	return read(`z-nile/skills/{name}/SKILL.md`)
end

return t.spec("f0464 the skills say a ticket is readied alone", function(it)
	it("AC6: z-design ends at ./zn ready <issue-id>, not z-raft", function()
		local s = skill("z-design")
		t.expect(has(s, "- **Next step**: `./zn ready <issue-id>` from the main checkout")).toBe(true)
		t.expect(
			has(
				s,
				"`./zn ready <issue-id> --on <R-id>` when a dependency is finished in `<R-id>` but not landed"
			)
		).toBe(true)
		t.expect(has(s, "`/z-raft` (it groups prepared issues), then `/z-ready <R-id>`")).toBe(false)
		t.expect(has(s, "z-raft groups prepared issues into rafts afterwards")).toBe(false)
		t.expect(has(s, "z-raft groups it later")).toBe(false)
	end)

	it(
		"AC6: z-ready readies a raftless issue alone, light only by light.luau, --on outside the dispatcher",
		function()
			local s = skill("z-ready")
			t.expect(has(s, "A prepared issue in no raft is readied alone (f0464)")).toBe(true)
			t.expect(has(s, "only when light.luau accepts the ticket")).toBe(true)
			t.expect(has(s, "Outside `./zn dispatch`, `./zn ready <issue> --on <R-id>`")).toBe(true)
			t.expect(has(s, "Any other raftless issue is refused, naming z-raft")).toBe(false)
			t.expect(has(s, "If the issue has no raft, stop: z-raft makes one")).toBe(false)
		end
	)

	it(
		"AC6: z-raft has no default raft and keeps the rafting PR and coherence review for named rafts",
		function()
			local s = skill("z-raft")
			t.expect(has(s, "- **No argument**: there is no default raft (f0464).")).toBe(true)
			t.expect(has(s, "neither `./zn work` nor `./zn dispatch` starts a rafting step")).toBe(true)
			t.expect(
				has(
					s,
					"A raft of two or more issues still needs its rafting pull request and its coherence review (§4) before `./zn ready` accepts it."
				)
			).toBe(true)
			t.expect(has(s, "- **No argument**: run `./zn raft-plan`.")).toBe(false)
			t.expect(has(s, "defects fold into one open prepared defect raft")).toBe(false)
			t.expect(has(s, "(`./zn raft-plan --apply` runs them all)")).toBe(false)
		end
	)

	it(
		"AC6: z-work's ready <issue> is for any level, and the walk to a named issue readies, not rafts",
		function()
			local s = skill("z-work")
			t.expect(
				has(s, "a prepared ticket in no raft is readied alone, at any level: `./zn ready <issue>`")
			)
				.toBe(true)
			t.expect(
				has(s, "`./zn ready <issue> --on <R>` when a dependency is finished in `<R>` but not landed")
			)
				.toBe(true)
			t.expect(has(s, "rafting by `./zn raft-plan`")).toBe(false)
			t.expect(has(s, "an easy ticket in no raft takes the light path: `./zn ready <issue>`"))
				.toBe(false)
		end
	)

	it(
		"AC6: zz-rules' raft-plan row, ready row and the dispatcher's chain say there is no rafting step",
		function()
			local s = skill("zz-rules")
			t.expect(has(s, "Makes no raft by default (f0464)")).toBe(true)
			t.expect(
				has(s, "a prepared raftless issue gets `z-ready` on the issue (`./zn ready <id>`, no `--on`)")
			)
				.toBe(true)
			t.expect(
				has(
					s,
					"for a prepared ticket in no raft (`easy`, `normal` or `risky`) makes the ticket's single raft"
				)
			).toBe(true)
			t.expect(has(s, "a prepared raftless issue gets `raft-plan --apply` in `raft-<id>`")).toBe(false)
			t.expect(has(s, "and refuses any other raftless issue, naming z-raft")).toBe(false)
			t.expect(has(s, "`z-ready` never creates a raft: a raftless issue goes to z-raft.")).toBe(false)
		end
	)

	it("AC6: the README's flow and AGENTS.md's table say the same", function()
		local r = read("z-nile/README.md")
		t.expect(has(r, "`./zn raft-plan` groups the prepared issues")).toBe(false)
		t.expect(has(r, "groups prepared issues into rafts (`./zn raft-plan`, or as asked)")).toBe(false)
		t.expect(
			has(r, "A prepared issue in no raft is readied alone: `./zn ready <id>` makes its single raft")
		)
			.toBe(true)
		local a = read("AGENTS.md")
		t.expect(has(a, "by default `./zn ready <issue>` readies each ticket alone")).toBe(true)
	end)
end)
